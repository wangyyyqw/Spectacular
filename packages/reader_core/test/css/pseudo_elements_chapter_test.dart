import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/line_spans.dart';
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
final _longText = List.filled(8, '甲乙丙丁戊己').join();

Uint8List _epub(String css, String body, Uint8List? image) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">pseudo-elements</dc:identifier>'
      '<dc:title>伪元素正式入口回归</dc:title></metadata><manifest>'
      '<item id="c" href="text/c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="s" href="styles.css" media-type="text/css"/>'
      '<item id="f" href="font.ttf" media-type="font/ttf"/>'
      '<item id="i" href="images/icon.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'font.ttf': File('test/fixtures/fonts/NoHaltPunctuation.ttf')
      .readAsBytesSync(),
  'styles.css':
      '@font-face {font-family:PseudoFixture; src:url(font.ttf); font-weight:300;}'
      'body {margin:0; padding:0; font-family:Ahem; color:black;}'
      'p {margin:0; padding:0; text-indent:0; text-align:left;}'
      '$css',
  'text/c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" href="../styles.css"/></head>'
      '<body>$body</body></html>',
  'images/icon.png': ?image,
});

Future<EpubChapterSource> _open(
  String css,
  String body, {
  Uint8List? image,
}) async {
  final source = await const EpubFormatOpener().openBytes(
    _epub(css, body, image),
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _insets.horizontal,
      contentHeight: _pageSize.height - _insets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _pageSize.width - _insets.horizontal,
    height: _pageSize.height - _insets.vertical,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return source;
}

Future<PageContent> _page(String css, String body) async =>
    (await (await _open(css, body)).loadChapter(0)).single;

ComputedStyle _styleAt(PageBlock block, int offset) =>
    block.layout.runs
        .where((run) => run.start <= offset && offset < run.end)
        .map((run) => run.style)
        .firstOrNull ??
    block.style!;

Future<ui.Image> _icon() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff008800), BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(12, 10);
  } finally {
    picture.dispose();
  }
}

Future<ByteData> _paint(PageContent page, {ui.Image? icon}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => icon)
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

Rect _coloredBounds(ByteData pixels, bool Function(int, int, int) matches) {
  var left = 384, top = 854, right = -1, bottom = -1;
  for (var y = 0; y < 854; y++) {
    for (var x = 0; x < 384; x++) {
      final offset = (y * 384 + x) * 4;
      if (pixels.getUint8(offset + 3) < 100 ||
          !matches(
            pixels.getUint8(offset),
            pixels.getUint8(offset + 1),
            pixels.getUint8(offset + 2),
          )) {
        continue;
      }
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '指定颜色必须实际绘制');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

void _expectTextCoordinates(PageContent page) {
  for (final box in TextHitTester.lineBoxes(page)) {
    final block = box.slice.block;
    final line = block.layout.lines[box.lineIndex];
    final painter = TextPainter(
      text: buildLineSpan(
        layout: block.layout,
        line: line,
        baseStyle: TextLayoutEngine.textStyleFor(block.style!),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(painter.width, closeTo(line.advanceWidth, .1));
    final selected = TextHitTester.selectionRects(box, 0, 1).single;
    final painted = painter
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 1),
        )
        .single;
    expect(selected.left, closeTo(painted.left, .01));
    expect(selected.right, closeTo(painted.right, .01));
    painter.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final colon in [':', '::']) {
    test('$colon before/after 经正式入口生成文字与图片并只计一次边距', () async {
      final icon = await _icon();
      addTearDown(icon.dispose);
      final image = (await icon.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      final source = await _open(
        'p.generated {color:#a52a2a;}'
            'p.generated${colon}before {margin-right:.25em; content:"■";}'
            'p.generated${colon}after {margin-left:.25em; content:url(images/icon.png);}'
            'p.generated::after {width:12px; height:10px;}',
        '<p class="generated">甲乙</p>',
        image: image,
      );
      final original = await source.loadAnchorChapter(0);
      final cfi = original.cfiAt(1)!;
      final page = (await source.loadChapter(0)).single;
      final block = page.slices.single.block;
      expect(block.layout.text, '■甲乙\uFFFC');
      final prefix = block.layout.runs.singleWhere((run) => run.start == 0);
      expect(prefix.style.color, const Color(0xffa52a2a));
      expect(prefix.trailingInset, closeTo(5.25, .001));
      final boxes = block.layout.lines.single.inlineBoxes;
      final picture = boxes.singleWhere((box) => box.spec.replacesPlaceholder);
      expect(picture.offset, 3);
      expect(picture.spec.width, closeTo(12, .001));
      expect(picture.spec.height, closeTo(10, .001));
      expect(picture.spec.marginLeft, closeTo(5.25, .001));
      expect(picture.spec.outerWidth, closeTo(17.25, .001));
      expect(
        boxes.where((box) => box.spec.payload is InlineSpacingEdge),
        hasLength(1),
      );
      final pixels = await _paint(page, icon: icon);
      final green = _coloredBounds(
        pixels,
        (r, g, b) => r < 20 && g > 100 && b < 20,
      );
      expect(green.width, closeTo(12, 1));
      expect(green.height, closeTo(10, 1));
      final after = await source.loadAnchorChapter(0);
      expect(after.text, original.text);
      expect(after.cfiAt(1), cfi);
      expect(after.offsetFor(cfi), 1);
    });
  }

  test('生成内容及独立样式规则按 important、特异性和实际媒体宽度级联', () async {
    final page = await _page(
      '#sample:before {content:"甲" !important; color:blue !important;}'
          'p.priority::before {content:"乙"; color:red;}'
          '@media (min-width:350px) {#sample::before {margin-right:.5em;}}'
          '@media (max-width:100px) {#sample:before {content:"丙" !important; color:green !important;}}'
          'p.priority:after {content:attr(data-note);}'
          'p.priority::after {color:green;}',
      '<p id="sample" class="priority" data-note="己">丁戊</p>',
    );
    final block = page.slices.single.block;
    expect(block.layout.text, '甲丁戊己');
    expect(_styleAt(block, 0).color, const Color(0xff0000ff));
    expect(_styleAt(block, 3).color, const Color(0xff008000));
    expect(block.layout.runs.first.trailingInset, closeTo(10.5, .001));
  });

  test('空白后代组合器保留起源元素，单双冒号和大小写分支共同匹配', () async {
    final page = await _page(
      '.wrapper :BeFoRe {content:"甲";}'
          'p::AFTER {content:"己";}',
      '<div class="wrapper"><p>乙</p></div><p>丙</p>',
    );
    expect(page.slices.map((slice) => slice.block.layout.text), ['甲乙己', '丙己']);
  });

  test('首行字号参与实际断行，首字高优先并只覆盖首个物理行', () async {
    final source = await _open(
      'p.target {width:200px;}'
          'p.target:first-line {font-family:PseudoFixture; font-weight:300; '
          'font-size:1.5em; color:red; width:1px; margin:100px;}'
          'p.target:first-letter {font-family:PseudoFixture; font-weight:300; '
          'font-size:1.25em; color:blue;}',
      '<p class="target">$_longText</p>',
    );
    final original = await source.loadAnchorChapter(0);
    final cfi = original.cfiAt(7)!;
    final page = (await source.loadChapter(0)).single;
    final block = page.slices.single.block;
    final lines = block.layout.lines;
    expect(lines.length, greaterThan(2));
    expect(lines.first.end, 6, reason: '39.375px 首字加五个 31.5px 字可放入 200px');
    expect(block.layout.maxWidth, closeTo(200, .001));
    expect(_styleAt(block, 0).color, const Color(0xff0000ff));
    expect(_styleAt(block, 0).fontSize, closeTo(39.375, .001));
    expect(_styleAt(block, 1).color, const Color(0xffff0000));
    expect(_styleAt(block, 1).fontSize, closeTo(31.5, .001));
    expect(
      _styleAt(block, 1).fontFamily,
      isNot('Ahem'),
      reason: '单冒号首行专用书内字体必须注册',
    );
    expect(_styleAt(block, lines[1].start).color, const Color(0xff000000));
    expect(_styleAt(block, lines[1].start).fontSize, closeTo(21, .001));
    expect(block.layout.firstLineStyle!.width, isNull);
    expect(block.layout.firstLineStyle!.margin.horizontal, 0);
    _expectTextCoordinates(page);
    final pixels = await _paint(page);
    final red = _coloredBounds(
      pixels,
      (r, g, b) => r > 180 && g < 50 && b < 50,
    );
    final blue = _coloredBounds(
      pixels,
      (r, g, b) => b > 180 && r < 50 && g < 50,
    );
    final first = TextHitTester.lineBoxes(page).first;
    expect(red.top, greaterThanOrEqualTo(_insets.top + first.rect.top - 1));
    expect(red.bottom, lessThanOrEqualTo(_insets.top + first.rect.bottom + 1));
    expect(blue.bottom, lessThanOrEqualTo(_insets.top + first.rect.bottom + 1));
    final after = await source.loadAnchorChapter(0);
    expect(after.text, original.text);
    expect(after.cfiAt(7), cfi);
    expect(after.offsetFor(cfi), 7);
  });

  test('首行重新级联行内继承与显式覆盖，续行恢复正文父样式', () async {
    final page = await _page(
      'p.target {width:200px; font-family:PseudoFixture; font-weight:300;}'
          'p.target::first-line {font-size:1.5em; color:red;}'
          'span.override {color:green;}',
      '<p class="target"><span>甲乙</span><span class="override">丙丁</span>'
          '<span>$_longText</span></p>',
    );
    final block = page.slices.single.block;
    final firstEnd = block.layout.lines.first.end;
    expect(_styleAt(block, 0).color, const Color(0xffff0000));
    expect(_styleAt(block, 0).fontSize, closeTo(31.5, .001));
    expect(_styleAt(block, 2).color, const Color(0xff008000));
    expect(_styleAt(block, 4).color, const Color(0xffff0000));
    expect(_styleAt(block, firstEnd).color, const Color(0xff000000));
    expect(_styleAt(block, firstEnd).fontSize, closeTo(21, .001));
    _expectTextCoordinates(page);
  });

  test('首字按单双冒号及 important 级联，并保留完整组合字素和 UTF-16 坐标', () async {
    const text = 'e\u0301甲乙';
    final page = await _page(
      '#letter:first-letter {color:blue !important; font-size:1.25em;}'
          'p.target::first-letter {color:red; font-size:2em;}'
          '@media (max-width:100px) {#letter::first-letter {color:green !important;}}',
      '<p id="letter" class="target">$text</p>',
    );
    final block = page.slices.single.block;
    final run = block.layout.runs.singleWhere((run) => run.start == 0);
    expect(run.end, 2, reason: '组合字素 e 加重音不能按一个 UTF-16 单位切开');
    expect(run.style.fontSize, closeTo(26.25, .001));
    expect(run.style.color, const Color(0xff0000ff));
    expect(block.layout.text, text);
    expect(_styleAt(block, 2).fontSize, closeTo(21, .001));
  });

  test('首行在硬换行处结束且祖先规则不会误套每个子段', () async {
    final page = await _page(
      'p.target:first-line {color:red;}'
          'div.wrapper::first-line {color:green;}',
      '<p class="target">甲乙<br/>丙丁</p>'
          '<div class="wrapper"><p>戊己</p><p>甲乙</p></div>',
    );
    final blocks = page.slices.map((slice) => slice.block).toList();
    expect(blocks.first.layout.lines, hasLength(2));
    expect(_styleAt(blocks.first, 0).color, const Color(0xffff0000));
    expect(
      _styleAt(blocks.first, blocks.first.layout.lines[1].start).color,
      const Color(0xff000000),
    );
    for (final block in blocks.skip(1)) {
      expect(_styleAt(block, 0).color, const Color(0xff000000));
    }
  });

  test('前置空行消耗首行与首字范围，仅第一个空行使用首行行高', () async {
    final source = await _open(
      'p.target {width:200px;}'
          'p.target:first-line {color:red; font-size:1.5em; line-height:2;}'
          'p.target::first-letter {color:blue; font-size:3em;}',
      '<p class="target"><br/><br/>$_longText</p>',
    );
    final original = await source.loadAnchorChapter(0);
    final cfi = original.cfiAt(1)!;
    final page = (await source.loadChapter(0)).single;
    final block = page.slices.single.block;
    final lines = block.layout.lines;
    expect(lines[0].start, 0);
    expect(lines[0].end, 0);
    expect(lines[1].end, 0);
    expect(lines[0].height, closeTo(63, .001));
    expect(lines[1].height, closeTo(33.6, .001));
    expect(lines[2].top, closeTo(96.6, .001));
    expect(_styleAt(block, 0).color, const Color(0xff000000));
    expect(_styleAt(block, 0).fontSize, closeTo(21, .001));
    expect(block.layout.firstLineStyle, isNull);
    final after = await source.loadAnchorChapter(0);
    expect(after.text, original.text);
    expect(after.cfiAt(1), cfi);
    expect(after.offsetFor(cfi), 1);
  });

  test('同章几何缓存复用时首行文字色仍逐段绑定', () async {
    final page = await _page(
      'p {width:200px;}'
          'p.red:first-line {color:red;}'
          'p.green::first-line {color:green;}',
      '<p class="red">$_longText</p><p class="green">$_longText</p>',
    );
    final blocks = page.slices.map((slice) => slice.block).toList();
    expect(blocks, hasLength(2));
    expect(blocks[0].layout.lines.first.end, blocks[1].layout.lines.first.end);
    expect(_styleAt(blocks[0], 0).color, const Color(0xffff0000));
    expect(_styleAt(blocks[1], 0).color, const Color(0xff008000));
    for (final block in blocks) {
      expect(
        _styleAt(block, block.layout.lines[1].start).color,
        const Color(0xff000000),
      );
    }
    final pixels = await _paint(page);
    _coloredBounds(pixels, (r, g, b) => r > 180 && g < 50 && b < 50);
    _coloredBounds(pixels, (r, g, b) => g > 100 && r < 50 && b < 50);
  });

  test('正文行尾微调保留首行级联输入、续行颜色和原文位置', () async {
    final source = await _open(
      'p.target::first-line {color:red;}',
      '<p class="target">$_longText</p>',
    );
    final original = await source.loadAnchorChapter(0);
    final cfi = original.cfiAt(20)!;
    final page = (await source.loadChapter(0)).single;
    final block = page.slices.single.block;
    expect(block.layout.lines.first.justifyExtra, greaterThan(0));
    expect(block.layout.firstLineStyle?.color, const Color(0xffff0000));
    expect(block.layout.firstLineRuns, isNotNull);
    expect(block.layout.sourceRuns, isNotNull);
    expect(_styleAt(block, 0).color, const Color(0xffff0000));
    expect(
      _styleAt(block, block.layout.lines[1].start).color,
      const Color(0xff000000),
    );
    final pixels = await _paint(page);
    _coloredBounds(pixels, (r, g, b) => r > 180 && g < 50 && b < 50);
    final after = await source.loadAnchorChapter(0);
    expect(after.text, original.text);
    expect(after.cfiAt(20), cfi);
    expect(after.offsetFor(cfi), 20);
  });
}
