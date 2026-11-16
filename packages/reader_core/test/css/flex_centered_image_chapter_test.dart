import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333334);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.07500000000001,
  8.53333333333336,
  24.08888888888893,
);
const _imageColor = 0x008800ff;

Future<ui.Image> _cover() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff008800), BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(432, 576);
  } finally {
    picture.dispose();
  }
}

Uint8List _book(
  Uint8List image,
  String extraCss, {
  String leadingContent = '',
  String author = 'AUTHOR',
}) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">flex-centered-image</dc:identifier>'
      '<dc:title>Flex 卡片居中回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="i" href="cover.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body {margin:0; padding:20px; height:100vh; display:flex; '
      'justify-content:center; align-items:center; text-align:center; '
      'background:#202020; font-family:Ahem;} '
      '.card {width:100%; max-width:600px; margin:30px; padding:20px; '
      'background:rgba(255,255,255,.9); border-radius:10px; '
      'display:flex; flex-direction:column; align-items:center;} '
      '.card img {width:50%; margin-bottom:20px; border-radius:7px;} '
      '.title {font-size:24px; margin:15px 0;} '
      '.author {font-size:16px;} '
      '$extraCss</style></head><body>$leadingContent<div class="card">'
      '<img src="cover.png"/><div class="title">TITLE</div>'
      '<div class="author">$author</div></div></body></html>',
  'cover.png': image,
});

Future<PageContent> _page(
  ui.Image image,
  String extraCss, {
  String leadingContent = '',
  String author = 'AUTHOR',
  double fontSize = 21,
}) async {
  final imageBytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  final source = await const EpubFormatOpener().openBytes(
    _book(imageBytes, extraCss, leadingContent: leadingContent, author: author),
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _insets.horizontal,
      contentHeight: _pageSize.height - _insets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    ReaderOverrides(fontSize: fontSize, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _pageSize.width - _insets.horizontal,
    height: _pageSize.height - _insets.vertical,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return (await source.loadChapter(0)).single;
}

Future<ByteData> _paint(PageContent page, ui.Image cover) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => cover)
      .paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _insets);
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Rect _imageBounds(ByteData pixels) {
  var left = 384, top = 854, right = -1, bottom = -1;
  for (var y = 0; y < 854; y++) {
    for (var x = 0; x < 384; x++) {
      if (pixels.getUint32((y * 384 + x) * 4) != _imageColor) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '封面必须实际绘制');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

void _expectCentered(List<TableCellRender> cells, Rect card) {
  final cover = cells[1].rect;
  expect(cover.width, closeTo((card.width - 40) * .5, .01));
  expect(cover.height, closeTo(cover.width * 4 / 3, .01));
  expect(cover.center.dx, closeTo(card.center.dx, .01));
  expect(cover.top - card.top, closeTo(20, .01));
  for (final cell in cells.skip(2)) {
    for (final line in cell.layout.lines) {
      final center = cell.textOrigin.dx + line.offsetX + line.advanceWidth / 2;
      expect(center, closeTo(card.center.dx, .01), reason: '文字与封面共用卡片中心');
    }
  }
  expect(card.bottom - cells.last.rect.bottom, closeTo(20, .01));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('隐藏兄弟不参与 Flex 子项计数，封面与换行作者使用收缩后的卡片宽', () async {
    final cover = await _cover();
    addTearDown(cover.dispose);
    const author = 'AUTHOR NAME TRANSLATOR NAME';
    final page = await _page(
      cover,
      'h2 {display:none;} div {margin-top:10px;}',
      leadingContent: '<h2>HIDDEN</h2>',
      author: author,
      fontSize: 18,
    );
    final cells = page.slices.single.block.table!.cells;
    final card = cells.first.rect;
    expect(
      card.width,
      closeTo(_pageSize.width - _insets.horizontal - 100, .01),
    );
    _expectCentered(cells, card);
    final authorCell = cells.last;
    expect(authorCell.layout.text, author);
    expect(authorCell.layout.lines.length, greaterThan(1));
    expect(authorCell.layout.maxWidth, closeTo(card.width - 40, .01));
    for (final line in authorCell.layout.lines) {
      expect(line.advanceWidth, lessThanOrEqualTo(authorCell.rect.width));
    }
    expect(authorCell.startCfi, isNotNull, reason: '换行不丢失原文位置');
  });
  test('Flex 卡片使用不对称外边距和 border-box 时，内容仍沿卡片中心对齐', () async {
    final cover = await _cover();
    addTearDown(cover.dispose);
    final page = await _page(
      cover,
      '.card {width:80%; box-sizing:border-box; margin:10px 40px 30px 20px;}',
    );
    final cells = page.slices.single.block.table!.cells;
    final card = cells.first.rect;
    final parentWidth = _pageSize.width - _insets.horizontal - 40;
    expect(card.width, closeTo(parentWidth * .8, .01));
    expect(card.center.dx, closeTo(parentWidth / 2 - 10, .01));
    _expectCentered(cells, card);
  });
  for (final alpha in [.9, .5]) {
    test('Flex 收缩卡片后，封面与文字居中且白底透明度为 $alpha', () async {
      final cover = await _cover();
      addTearDown(cover.dispose);
      final page = await _page(
        cover,
        '.card {background:rgba(255,255,255,$alpha);}',
      );
      final cells = page.slices.single.block.table!.cells;
      final card = cells.first.rect;
      final contentWidth = _pageSize.width - _insets.horizontal;
      expect(card.width, closeTo(contentWidth - 40 - 60, .01));
      expect(card.center.dx + 20, closeTo(contentWidth / 2, .01));
      _expectCentered(cells, card);
      final pixels = await _paint(page, cover);
      final image = _imageBounds(pixels);
      final paintedCard = card.shift(_insets.topLeft + const Offset(20, 20));
      expect(image.width, closeTo(cells[1].rect.width, 2));
      expect(image.center.dx, closeTo(paintedCard.center.dx, 1));
      final x = (paintedCard.left + 10).round();
      final y = paintedCard.center.dy.round();
      final offset = (y * 384 + x) * 4;
      for (var channel = 0; channel < 3; channel++) {
        expect(
          pixels.getUint8(offset + channel),
          closeTo(255 * alpha + 32 * (1 - alpha), 1),
          reason: '白底只合成一次，不能把半透明面板叠成不透明',
        );
      }
    });
  }
}
