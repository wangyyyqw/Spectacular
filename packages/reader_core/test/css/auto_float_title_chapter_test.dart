import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _size = Size(384, 853.3333333333334);
const _width = 384 - 8.8 - 8.53333333333336;
const _height = 853.3333333333334 - 56.075 - 24.08888888888893;

Uint8List _book(
  String clear,
  String css,
  String left,
  String right,
) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">auto-float-title</dc:identifier>'
      '<dc:title>浮动标题与清除回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body {margin:0 1%; font-family:Ahem; font-size:16px; line-height:130%;}'
      '.row {padding:.8em; padding-left:1em; background:#f2e4d9; margin:0;}'
      '.left, .right {font-size:.7em; text-indent:0; line-height:130%;}'
      '.left {float:left;} .right {float:right; padding:0 .3em; border-width:0 1px; border-style:solid;}'
      '.clear {clear:both;} .next {margin:2em auto; font-size:small; text-align:center;}'
      '$css</style></head><body><div style="height:100px;"></div><div class="row">'
      '<p class="left">$left</p><p class="right">$right</p>$clear</div>'
      '<h3 class="next">后续标题</h3><p>相邻正文</p></body></html>',
});

Future<EpubChapterSource> _open({
  String clear = '<p style="clear:both;"></p>',
  String css = '',
  String left = '左标题',
  String right = 'RIGHT',
}) async {
  final source = await const EpubFormatOpener().openBytes(
    _book(clear, css, left, right),
    options: const ReaderOpenOptions(
      contentWidth: _width,
      contentHeight: _height,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 18, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _width,
    height: _height,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return source;
}

Future<ByteData> _paint(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: _size,
    pageInsets: _insets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  picture.dispose();
  return data;
}

Rect _colorBounds(ByteData data, int color) {
  var left = 384, right = -1, top = 854, bottom = -1;
  for (var y = 0; y < 854; y++) {
    for (var x = 0; x < 384; x++) {
      final i = (y * 384 + x) * 4;
      if (data.getUint32(i) == color) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }
  expect(right, greaterThan(left));
  return Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1, bottom + 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final clear in [
    '<p style="clear:both;"></p>',
    '<p class="clear">   </p>',
    '<p></p>',
  ]) {
    test('自动宽浮动同排，空段落清除后标题不被背景遮住：$clear', () async {
      final source = await _open(
        clear: clear,
        css: clear == '<p></p>' ? '.row > p:nth-child(3) {clear:both;}' : '',
      );
      final page = (await source.loadChapter(0)).single;
      final floats = page.slices.where((s) => s.overlay).toList();
      expect(floats, hasLength(2));
      expect(floats[0].block.layout.maxWidth, closeTo(3 * 12.6, .01));
      expect(floats[1].block.layout.maxWidth, closeTo(5 * 12.6, .01));
      final lines = TextHitTester.lineBoxes(page);
      final left = lines.singleWhere((l) => l.text == '左标题');
      final right = lines.singleWhere((l) => l.text == 'RIGHT');
      expect(left.rect.top, closeTo(right.rect.top, .01));
      final container = floats.first.block.containers.last.container;
      expect(left.rect.left, closeTo(container.contentLeft, .01));
      expect(
        right.rect.right + 1 + 3.36,
        closeTo(container.contentLeft + container.contentWidth, .01),
      );
      final panel = _colorBounds(await _paint(page), 0xf2e4d9ff);
      final next = lines.singleWhere((l) => l.text == '后续标题');
      expect(panel.bottom, lessThan(next.rect.top + _insets.top));
      expect(panel.bottom, greaterThan(right.rect.bottom + _insets.top));
      expect(floats.every((s) => s.block.startCfi != null), isTrue);
      expect(
        (await source.loadAnchorChapter(0)).text,
        contains('左标题RIGHT后续标题相邻正文'),
      );
    });
  }

  for (final bleed in ['left', 'right', 'leftright']) {
    test('容器 $bleed 出血只扩背景，浮动文字和边框仍在内边距内', () async {
      final source = await _open(
        css:
            '.row {duokan-bleed:$bleed;} '
            '.right {color:#0000ff; border-color:#ff0000; border-width:0 2px;}',
      );
      final page = (await source.loadChapter(0)).single;
      final pixels = await _paint(page);
      final panel = _colorBounds(pixels, 0xf2e4d9ff);
      expect(panel.left, bleed.contains('left') ? 0 : greaterThan(8));
      expect(panel.right, bleed.contains('right') ? 384 : lessThan(376));
      final right = TextHitTester.lineBoxes(page)
          .singleWhere((line) => line.text == 'RIGHT');
      final ink = _colorBounds(pixels, 0x0000ffff);
      final border = _colorBounds(pixels, 0xff0000ff);
      expect(ink.left, closeTo(right.rect.left + _insets.left, 1));
      expect(ink.right, closeTo(right.rect.right + _insets.left, 1));
      expect(ink.left - border.left, closeTo(5.36, 1));
      expect(border.right - ink.right, closeTo(5.36, 1));
      expect(border.left, greaterThan(panel.left));
      expect(border.right, lessThan(panel.right));
    });
  }

  test('浮动窄于三字时不被正文最小行宽放大，行内字号参与收缩', () async {
    final source = await _open(
      left: '甲',
      right: '<span style="font-size:2em;">R</span>',
    );
    final floats = (await source.loadChapter(0)).single.slices
        .where((s) => s.overlay)
        .toList();
    expect(floats[0].block.layout.maxWidth, closeTo(12.6, .01));
    expect(floats[1].block.layout.maxWidth, closeTo(25.2, .01));
  });

  for (final (css, expected) in [
    ('.right {width:100px;}', 100.0),
    ('.right {max-width:40px;}', 40.0),
    ('.right {min-width:90px;}', 90.0),
    ('.right {width:25%;}', (_width * .98 - 28.8) * .25),
  ]) {
    test('浮动保留作者尺寸和父包含块基准：$css', () async {
      final source = await _open(css: css);
      final page = (await source.loadChapter(0)).single;
      final block = page.slices
          .singleWhere((s) => s.block.layout.text == 'RIGHT')
          .block;
      expect(block.layout.maxWidth, closeTo(expected, .01));
    });
  }

  test('较长浮动按父可用宽换行，后续清除仍在浮动下方', () async {
    final text = '甲乙丙丁' * 20;
    final source = await _open(right: text);
    final page = (await source.loadChapter(0)).single;
    final block = page.slices
        .singleWhere((s) => s.block.layout.text == text)
        .block;
    expect(block.layout.maxWidth, closeTo(_width * .98 - 28.8 - 8.72, .01));
    expect(block.layout.lineCount, greaterThan(1));
    final lines = TextHitTester.lineBoxes(page);
    final next = lines.singleWhere((l) => l.text == '后续标题');
    final last = lines.where((l) => identical(l.slice.block, block)).last;
    expect(next.rect.top, greaterThan(last.rect.bottom));
  });
}
