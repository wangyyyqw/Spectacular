import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
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

Uint8List _bookBytes(Uint8List imageBytes) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">nested-image-percentage</dc:identifier>'
      '<dc:title>父容器图片百分比宽度</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="pic" href="cover.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body { margin:0; } '
      '.copyright { width:80%; margin:0 auto; padding:32px 12px; } '
      '.cover-wrapper img { width:40%; height:auto; margin:0 auto 20px; '
      'display:block; } '
      '</style></head><body><div class="copyright">'
      '<div class="cover-wrapper"><img src="cover.png"/></div>'
      '<p>封面后的书名</p></div></body></html>',
  'cover.png': imageBytes,
});

Future<PageContent> _page(Uint8List imageBytes) async {
  final source = await const EpubFormatOpener().openBytes(
    _bookBytes(imageBytes),
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _pageInsets.horizontal,
      contentHeight: _pageSize.height - _pageInsets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('块级图片的百分比宽度以最近父内容盒为基准', () async {
    final image = await _image();
    addTearDown(image.dispose);
    final imageBytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    final page = await _page(imageBytes);
    final imageBlock = page.slices
        .map((slice) => slice.block)
        .singleWhere((block) => block.isReplaced);
    final parentContentWidth =
        (_pageSize.width - _pageInsets.horizontal) * 0.8;
    final expectedWidth = parentContentWidth * 0.4;
    expect(
      imageBlock.style!.width!.resolve(1),
      closeTo(expectedWidth, 0.001),
    );
    final bounds = _imageBounds(await _render(page, image));
    expect(
      bounds.width,
      closeTo(expectedWidth, 2),
      reason: '图片应按父内容宽度的 40% 绘制',
    );
    expect(bounds.height, closeTo(expectedWidth * 4 / 3, 2));
    final center =
        _pageInsets.left + (_pageSize.width - _pageInsets.horizontal) / 2;
    expect(
      bounds.center.dx,
      closeTo(center, 1),
      reason: '图片应在居中的父内容盒内水平居中',
    );
  });
}
