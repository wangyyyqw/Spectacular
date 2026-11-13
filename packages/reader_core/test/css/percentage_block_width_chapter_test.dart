import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333333);
const _pageInsets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _imageColor = Color(0xFF008800);
final _bodyWidth = _pageSize.width - _pageInsets.horizontal - 16;
final _cases = [
  for (final position in ['static', 'relative'])
    (
      css: 'width:90%; position:$position;',
      fontSize: 21.0,
      width: _bodyWidth * .9,
    ),
  (
    css: 'width:90%; position:relative;',
    fontSize: null,
    width: _bodyWidth * .9,
  ),
  for (final entry in {
    'width:100%; max-width:90%;': _bodyWidth * .9,
    'width:50%; min-width:90%;': _bodyWidth * .9,
    'width:calc(90% - 12px);': _bodyWidth * .9 - 12,
    'width:200px;': 200.0,
    'width:auto;': _bodyWidth,
  }.entries)
    (
      css: '${entry.key} position:relative;',
      fontSize: 21.0,
      width: entry.value,
    ),
];

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(_imageColor, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(432, 576);
  } finally {
    picture.dispose();
  }
}

Uint8List _bookBytes(Uint8List imageBytes, String css) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">percentage-block-width</dc:identifier>'
      '<dc:title>百分比块宽居中回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="pic" href="image.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'html, body { height:95%; padding:.5em; } '
      'body { margin:0; height:30%; font-family:Ahem; } '
      'div { margin:0; padding:0; text-indent:0; } '
      '.centered { margin:0 auto; top:12%; text-align:center; $css } '
      'img { width:100%; margin:0; } '
      '</style></head><body><div style="height:300%;">'
      '<div class="centered"><img src="image.png"/><br/>'
      '<span>题注</span></div></div></body></html>',
  'image.png': imageBytes,
});

Future<PageContent> _page(
  Uint8List imageBytes,
  String css, {
  double? fontSize = 21,
}) async {
  final source = await const EpubFormatOpener().openBytes(
    _bookBytes(imageBytes, css),
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _pageInsets.horizontal,
      contentHeight: _pageSize.height - _pageInsets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    ReaderOverrides(fontSize: fontSize, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _pageSize.width - _pageInsets.horizontal,
    height: _pageSize.height - _pageInsets.vertical,
    topInset: _pageInsets.top,
    sideInsets: (left: _pageInsets.left, right: _pageInsets.right),
  );
  return (await source.loadChapter(0)).single;
}

Future<ByteData> _render(PageContent page, ui.Image image) async {
  final recorder = ui.PictureRecorder();
  PagePainter(
    imageLookup: (_) => image,
  ).paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _pageInsets);
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(384, 854);
  try {
    return (await rendered.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    rendered.dispose();
    picture.dispose();
  }
}

Rect _imageBounds(ByteData pixels) {
  var left = 384;
  var right = -1;
  var top = 854;
  var bottom = -1;
  for (var y = 0; y < 854; y++) {
    for (var x = 0; x < 384; x++) {
      final offset = (y * 384 + x) * 4;
      if (pixels.getUint8(offset) == 0 &&
          pixels.getUint8(offset + 1) == 136 &&
          pixels.getUint8(offset + 2) == 0) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '图片应实际绘制到页面上');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

Future<void> _expectCentered(
  PageContent page,
  ui.Image image,
  double expectedWidth,
) async {
  final center =
      _pageInsets.left + (_pageSize.width - _pageInsets.horizontal) / 2;
  expect(
    page.slices.single.block.layout.maxWidth,
    closeTo(expectedWidth, .001),
  );
  final bounds = _imageBounds(await _render(page, image));
  // 完整颜色的像素不含两侧抗锯齿边缘，最多回收两个像素。
  expect(bounds.width, closeTo(expectedWidth, 2));
  expect(bounds.height, closeTo(expectedWidth * 4 / 3, 2));
  expect(bounds.center.dx, closeTo(center, 1), reason: '图片应在父内容盒中居中');
  final caption = TextHitTester.lineBoxes(page)
      .singleWhere((line) => line.text == '题注');
  final glyphs = TextHitTester.selectionRects(
    caption,
    0,
    2,
  ).reduce((a, b) => a.expandToInclude(b));
  expect(
    glyphs.center.dx + caption.rect.left + _pageInsets.left,
    closeTo(center, .01),
    reason: '题注与图片必须使用同一个父内容盒中心',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.Image image;
  late Uint8List imageBytes;
  setUpAll(() async {
    image = await _image();
    imageBytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  });
  tearDownAll(() => image.dispose());

  for (final sample in _cases) {
    final font = sample.fontSize == null ? '原书字号' : '阅读器字号';
    test('父内容盒中的图片与题注共同居中：${sample.css}，$font', () async {
      final page = await _page(
        imageBytes,
        sample.css,
        fontSize: sample.fontSize,
      );
      await _expectCentered(page, image, sample.width);
    });
  }
}
