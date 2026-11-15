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
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
final _contentWidth = _pageSize.width - _insets.horizontal;
const _imageColor = Color(0xff008800);
const _bodyText = '插图后的正文继续显示。';

Future<ui.Image> _image(Size size) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(_imageColor, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size.width.toInt(), size.height.toInt());
  } finally {
    picture.dispose();
  }
}

Uint8List _book(Uint8List image, String extraCss) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">natural-image-size</dc:identifier>'
      '<dc:title>正文插图自然尺寸回归</dc:title></metadata><manifest>'
      '<item id="c" href="chapter.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="css" href="style.css" media-type="text/css"/>'
      '<item id="i" href="icon.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'chapter.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" href="style.css"/></head><body>'
      '<h2>1</h2><div class="illustration"><img class="image" '
      'src="icon.png"/></div><p>$_bodyText</p></body></html>',
  'style.css':
      'body {margin:0;} '
      'h2 {font-size:1.6em; color:#555; margin-top:50px; '
      'margin-bottom:10px; padding-bottom:5px; text-align:center;} '
      '.illustration {text-align:center; margin:20px 0;} '
      '.image {max-width:100%; height:auto; display:block; '
      'margin:0 auto; $extraCss}',
  'icon.png': image,
});

Future<List<PageContent>> _pages(ui.Image image, String extraCss) async {
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  final source = await const EpubFormatOpener().openBytes(
    _book(bytes, extraCss),
    options: ReaderOpenOptions(
      contentWidth: _contentWidth,
      contentHeight: _pageSize.height - _insets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _contentWidth,
    height: _pageSize.height - _insets.vertical,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return source.loadChapter(0);
}

Future<ByteData> _paint(PageContent page, ui.Image image) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => image)
      .paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _insets);
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
  var left = 384, top = 854, right = -1, bottom = -1;
  for (var y = 0; y < 854; y++) {
    for (var x = 0; x < 384; x++) {
      if (pixels.getUint32((y * 384 + x) * 4) != 0x008800ff) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
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

Future<void> _checkSize(Size intrinsic, Size expected, String css) async {
  final image = await _image(intrinsic);
  addTearDown(image.dispose);
  final pages = await _pages(image, css);
  final block = pages.first.slices
      .map((slice) => slice.block)
      .singleWhere((block) => block.isReplaced);
  expect(block.startCfi, isNotNull);
  expect(
    block.style!.width!.resolve(_contentWidth),
    closeTo(expected.width, .01),
  );
  expect(block.layout.height, closeTo(expected.height, .01));
  final bounds = _imageBounds(await _paint(pages.first, image));
  expect(bounds.width, closeTo(expected.width, 2));
  expect(bounds.height, closeTo(expected.height, 2));
  expect(bounds.center.dx, closeTo(_insets.left + _contentWidth / 2, 1));
  if (expected.height <= 78) {
    expect(pages, hasLength(1));
    expect(pages.first.slices.last.block.layout.text, _bodyText);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('只声明最大宽度的小插图保留 49×78 自然尺寸，居中且正文紧随', () async {
    await _checkSize(const Size(49, 78), const Size(49, 78), '');
  });
  test('auto 大图只按最大宽度等比缩小', () async {
    await _checkSize(
      const Size(784, 1248),
      Size(_contentWidth, _contentWidth * 78 / 49),
      '',
    );
  });
  test('auto 图片受到最大高度约束时等比缩小', () async {
    await _checkSize(
      const Size(49, 78),
      const Size(24.5, 39),
      'max-height:39px;',
    );
  });
  test('显式百分比宽度继续按包含块缩放小图', () async {
    await _checkSize(
      const Size(49, 78),
      Size(_contentWidth, _contentWidth * 78 / 49),
      'width:100%;',
    );
  });
}
