import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_mobile/search/chapter_text.dart';
import 'package:reader_mobile/search/scan_search_service.dart';

import 'support/css_chapter_book.dart';

const _baseCss =
    'html, body { font-size: 16px; } '
    'html, body, p, ul, ol, li { margin: 0; } '
    'p, li { text-indent: 0; line-height: 1.2; } ';
const _markerImagePath = 'OEBPS/Images/marker.png';
const _marker = 'AbC§';
final _longListText = '${List.filled(35, '分页正文连续保留，').join()}目标原文末尾';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _registerFontTests();
  _registerViewportTests();
  _registerListTests();
}

void _registerFontTests() {
  const sizes = {
    'xx-small': 9.0,
    'x-small': 10.0,
    'small': 13.0,
    'medium': 16.0,
    'large': 18.0,
    'x-large': 24.0,
    'xx-large': 32.0,
    'xxx-large': 48.0,
  };
  for (final entry in sizes.entries) {
    test('实际章节消费字号关键字 ${entry.key}', () async {
      await _absoluteKeyword(entry.key, entry.value);
    });
  }
  test('嵌套绝对字号取根基准，smaller 和 larger 取父字号', _nestedKeywords);
  test('font 简写的关键字进入实际测量，行内覆盖仍遵守级联', _fontShorthand);
  test('重复调整阅读器字号时，关键字和行内相对字号只缩放一次', _readerFontOnce);
  test('关键字与 ex 作者容器不因阅读器字号变化而放大盒模型', _authorBoxSizes);
  test('ex 在段落、嵌套行内和 font 简写中换算为实际字号与字距', _exMeasurements);
}

void _registerViewportTests() {
  test('六种视口单位随同一章节源旋屏重新计算', _viewportUnitsFollowResize);
  for (final mode in ['vertical-rl', 'vertical-lr']) {
    test('根 $mode 决定 vi 和 vb，横排后代不改变根轴', () async {
      await _logicalViewportAxes(mode);
    });
  }
  test('只改变视口高度也会更新通用 vh 与 vb 计算', _viewportHeightOnlyChange);
  test('两个章节源的视口单位互不影响', _independentViewports);
}

void _registerListTests() {
  const strings = {
    '"AbC>"': 'AbC>',
    r'"\41 bC"': 'AbC',
    '""': '',
    '"中文•📚"': '中文•📚',
    r'"\1F4DA 章节"': '📚章节',
    '"10vw AbC"': '10vw AbC',
  };
  for (final entry in strings.entries) {
    test('字符串列表标记保留 ${entry.key} 的字符语义', () async {
      await _stringMarker(entry.key, entry.value);
    });
  }
  test('list-style 简写保存带空格的字符串和 inside', _listShorthand);
  test('自定义 inside 标记仅缩进首行，outside 正文不额外缩进', _markerPositions);
  test('嵌套列表显式继承自定义字符串，局部覆盖不影响兄弟列表项', _nestedMarkers);
  test('真实章节的图片标记优先于字符串，空字符串仍允许图片', _imageMarkerPriority);
  test('自定义字符串列表跨页仍只有一个起始片段', _markerPagination);
  test('字符串标记不进入原文、搜索内容和 CFI 字符偏移', _markerTextAndCfi);
}

Future<EpubChapterSource> _open(
  String body,
  String css, {
  double width = 300,
  double height = 500,
  ReaderOverrides overrides = const ReaderOverrides(),
}) async {
  final source = await openCssChapter(
    body: body,
    css: '$_baseCss$css',
    contentWidth: width,
    contentHeight: height,
    overrides: overrides,
  );
  addTearDown(source.close);
  return source;
}

Future<Map<String, PageBlock>> _textBlocks(EpubChapterSource source) async => {
  for (final page in await source.loadChapter(0))
    for (final slice in page.slices)
      if (slice.block.layout.text.isNotEmpty)
        slice.block.layout.text: slice.block,
};

ComputedStyle _styleAt(PageBlock block, String text) {
  final offset = block.layout.text.indexOf(text);
  expect(offset, greaterThanOrEqualTo(0));
  return block.layout.runs
      .firstWhere((run) => run.start <= offset && run.end > offset)
      .style;
}

void _expectSize(PageBlock block, double expected) {
  expect(block.style!.fontSize, closeTo(expected, .001));
  expect(block.layout.runs, isNotEmpty);
  expect(
    block.layout.runs.map((run) => run.style.fontSize),
    everyElement(closeTo(expected, .001)),
    reason: '章节输出与实际文字测量使用同一字号',
  );
}

Future<void> _absoluteKeyword(String keyword, double expected) async {
  final source = await _open(
    '<p class="probe">字号样本</p>',
    '.probe { font-size: $keyword; }',
  );
  _expectSize((await _textBlocks(source))['字号样本']!, expected);
}

Future<void> _nestedKeywords() async {
  final source = await _open(
    '<div style="font-size: 10px;"><p class="probe">大'
        '<span class="smaller">小<span class="larger">增</span></span>'
        '<span class="absolute">绝</span></p></div>',
    '.probe { font-size: large; } .smaller { font-size: smaller; } '
        '.larger { font-size: larger; } .absolute { font-size: x-large; }',
  );
  final block = (await _textBlocks(source))['大小增绝']!;
  for (final entry in {'大': 18.0, '小': 15.0, '增': 18.0, '绝': 24.0}.entries) {
    expect(_styleAt(block, entry.key).fontSize, closeTo(entry.value, .001));
  }
}

Future<void> _fontShorthand() async {
  final source = await _open(
    '<p class="probe">简<span>子</span></p>'
        '<p class="probe" style="font-size: large;">覆盖</p>',
    '.probe { font: italic bold x-large/1.5 serif; } '
        '.probe span { font: smaller/2 serif; }',
  );
  final blocks = await _textBlocks(source);
  final style = _styleAt(blocks['简子']!, '简');
  expect(style.fontSize, 24);
  expect(style.italic, isTrue);
  expect(style.fontWeight, 700);
  expect(style.lineHeightFactor, 1.5);
  final child = _styleAt(blocks['简子']!, '子');
  expect(child.fontSize, closeTo(20, .001));
  expect(child.italic, isFalse, reason: 'font 简写重置未声明的斜体');
  expect(child.fontWeight, 400);
  expect(child.lineHeightFactor, 2);
  _expectSize(blocks['覆盖']!, 18);
}

Future<void> _readerFontOnce() async {
  final source = await _open(
    '<p class="probe">本<span class="root">根'
        '<span class="relative">相</span></span><span class="grow">增</span></p>',
    '.probe { font-size: small; } .root { font: x-large/1.5 serif; } '
        '.relative { font-size: smaller; } .grow { font-size: larger; }',
  );
  for (final size in [24.0, 32.0, 24.0]) {
    await source.applyOverrides(ReaderOverrides(fontSize: size));
    final block = (await _textBlocks(source))['本根相增']!;
    final expected = {
      '本': size * 13 / 16,
      '根': size * 1.5,
      '相': size * 1.5 / 1.2,
      '增': size * 13 / 16 * 1.2,
    };
    expect(block.style!.fontSize, closeTo(expected['本']!, .001));
    for (final entry in expected.entries) {
      expect(_styleAt(block, entry.key).fontSize, closeTo(entry.value, .001));
    }
  }
}

Future<void> _authorBoxSizes() async {
  final source = await _open(
    '<div class="box"><p class="probe">作者盒</p></div>',
    '.box { font-size: small; width: 10em; border: 1em solid #000; '
        'padding: 1ex; margin-left: 1rem; } .probe { font-size: x-large; }',
  );
  for (final size in [24.0, 32.0]) {
    await source.applyOverrides(ReaderOverrides(fontSize: size));
    final block = (await _textBlocks(source))['作者盒']!;
    _expectSize(block, size * 1.5);
    final box = block.containers
        .map((fragment) => fragment.container.style)
        .firstWhere((style) => style.borders.left.width > 0);
    expect(box.fontSize, 13);
    expect(box.width!.resolve(300), 130);
    expect(box.borders.left.width, 13);
    expect(box.padding.left, 6.5);
    expect(box.margin.left, 16);
  }
}

Future<void> _exMeasurements() async {
  final source = await _open(
    '<div style="font-size: 20px;"><p class="probe">甲'
        '<span class="small">乙</span><span class="shorthand">丙</span></p></div>',
    '.probe { font-size: 2ex; letter-spacing: .5ex; } '
        '.small { font-size: 1ex; letter-spacing: 1ex; } '
        '.shorthand { font: italic 3ex/1.4 serif; letter-spacing: .5ex; }',
  );
  final block = (await _textBlocks(source))['甲乙丙']!;
  final expected = {'甲': (20.0, 5.0), '乙': (10.0, 5.0), '丙': (30.0, 7.5)};
  for (final entry in expected.entries) {
    final style = _styleAt(block, entry.key);
    expect(style.fontSize, closeTo(entry.value.$1, .001));
    expect(style.letterSpacing, closeTo(entry.value.$2, .001));
  }
}

Future<void> _viewportUnitsFollowResize() async {
  final source = await _open(
    '<p class="probe">视口单位</p>',
    '.probe { padding-left: 10vw; padding-right: 10vh; '
        'margin-left: 2vi; margin-right: 2vb; '
        'letter-spacing: 1vmin; text-indent: 2vmax; }',
  );
  for (final size in [(300.0, 500.0), (500.0, 300.0), (200.0, 600.0)]) {
    await source.applyContentSize(width: size.$1, height: size.$2);
    final block = (await _textBlocks(source))['视口单位']!;
    final style = block.style!;
    final minimum = size.$1 < size.$2 ? size.$1 : size.$2;
    final maximum = size.$1 > size.$2 ? size.$1 : size.$2;
    expect(style.padding.left, closeTo(size.$1 * .1, .001));
    expect(style.padding.right, closeTo(size.$2 * .1, .001));
    expect(style.margin.left, closeTo(size.$1 * .02, .001));
    expect(style.margin.right, closeTo(size.$2 * .02, .001));
    expect(style.letterSpacing, closeTo(minimum * .01, .001));
    expect(style.textIndent, closeTo(maximum * .02, .001));
    expect(block.layout.lines.first.offsetX, closeTo(maximum * .02, .001));
    expect(_styleAt(block, '视').letterSpacing, closeTo(minimum * .01, .001));
  }
}

Future<void> _logicalViewportAxes(String rootMode) async {
  final source = await _open(
    '<div><p class="probe">根轴</p></div>',
    'html { writing-mode: $rootMode; } '
        'div, .probe { writing-mode: horizontal-tb; } '
        '.probe { margin-left: 10vi; margin-right: 10vb; }',
  );
  for (final size in [(300.0, 500.0), (500.0, 300.0)]) {
    await source.applyContentSize(width: size.$1, height: size.$2);
    final style = (await _textBlocks(source))['根轴']!.style!;
    expect(style.writingMode, CssWritingMode.horizontalTb);
    expect(style.margin.left, closeTo(size.$2 * .1, .001));
    expect(style.margin.right, closeTo(size.$1 * .1, .001));
  }
}

Future<void> _viewportHeightOnlyChange() async {
  final source = await _open(
    '<p class="probe">高度变化</p>',
    '.probe { padding-top: 10vh; letter-spacing: 1vb; }',
  );
  final first = (await _textBlocks(source))['高度变化']!;
  expect(first.style!.padding.top, 50);
  expect(await source.applyContentSize(width: 300, height: 240), isTrue);
  final second = (await _textBlocks(source))['高度变化']!;
  expect(second.style!.padding.top, 24);
  expect(_styleAt(second, '高').letterSpacing, closeTo(2.4, .001));
  expect(second.startCfi, first.startCfi, reason: '重排不改变原文定位');
}

Future<void> _independentViewports() async {
  const body = '<p class="probe">独立视口</p>';
  const css = '.probe { font-size: 10vmin; padding-left: 5vmax; }';
  final first = await _open(body, css, width: 200, height: 400);
  final second = await _open(body, css, width: 400, height: 200);
  _expectSize((await _textBlocks(first))['独立视口']!, 20);
  _expectSize((await _textBlocks(second))['独立视口']!, 20);
  await first.applyContentSize(width: 300, height: 500);
  final changed = (await _textBlocks(first))['独立视口']!;
  _expectSize(changed, 30);
  expect(changed.style!.padding.left, 25);
  final unchanged = (await _textBlocks(second))['独立视口']!;
  _expectSize(unchanged, 20);
  expect(unchanged.style!.padding.left, 20);
}

Future<void> _stringMarker(String cssString, String marker) async {
  final source = await _open(
    '<ol class="items"><li>列表正文</li></ol>',
    '.items { list-style-type: $cssString; list-style-position: inside; '
        'padding-left: 30px; }',
  );
  final block = (await _textBlocks(source))['列表正文']!;
  expect(block.style!.listStyleType, CssListStyleType.custom);
  expect(block.style!.listStyleString, marker);
  expect(block.listMarker, marker.isEmpty ? isNull : marker);
  expect(block.layout.text, '列表正文');
  if (marker.isEmpty) expect(block.layout.lines.first.offsetX, 0);
  expect(
    source.chapterPlainText(0),
    isNot(contains(marker.isEmpty ? '""' : marker)),
  );
}

Future<void> _listShorthand() async {
  final source = await _open(
    '<ul class="items"><li>简写标记</li></ul>',
    '.items { list-style: "Ab C" inside; padding-left: 20px; }',
  );
  final block = (await _textBlocks(source))['简写标记']!;
  expect(block.listMarker, 'Ab C');
  expect(block.style!.listStyleString, 'Ab C');
  expect(block.style!.listStylePosition, CssListStylePosition.inside);
  expect(block.layout.lines.first.offsetX, greaterThan(0));
}

Future<void> _markerPositions() async {
  final text = List.filled(5, '列表换行后的正文保持原始顺序').join();
  final source = await _open(
    '<ul class="inside"><li>内$text</li></ul>'
        '<ul class="outside"><li>外$text</li></ul>',
    'ul { list-style-type: "AbC"; padding-left: 20px; } '
        '.inside { list-style-position: inside; } '
        '.outside { list-style-position: outside; }',
    width: 240,
  );
  final blocks = await _textBlocks(source);
  final inside = blocks['内$text']!;
  final outside = blocks['外$text']!;
  expect(inside.listMarker, 'AbC');
  expect(outside.listMarker, 'AbC');
  expect(inside.layout.lineCount, greaterThan(1));
  expect(inside.layout.lines.first.offsetX, greaterThan(0));
  expect(
    inside.layout.lines.skip(1).map((line) => line.offsetX),
    everyElement(0),
  );
  expect(outside.layout.lines.map((line) => line.offsetX), everyElement(0));
}

Future<void> _nestedMarkers() async {
  final source = await _open(
    '<ul class="outer"><li>父<ul><li>继承</li></ul>'
        '<ul class="inner"><li>覆盖</li></ul></li><li>兄</li></ul>',
    'ul { padding-left: 20px; } .outer { list-style-type: "AbC"; } '
        '.outer ul { list-style-type: inherit; } '
        '.outer ul.inner { list-style-type: "内📚"; }',
  );
  final blocks = await _textBlocks(source);
  for (final text in ['父', '继承', '兄']) {
    expect(blocks[text]!.listMarker, 'AbC');
  }
  expect(blocks['覆盖']!.listMarker, '内📚');
  expect(blocks['父']!.style!.margin.left, 20);
  expect(blocks['继承']!.style!.margin.left, 40);
  expect(blocks['覆盖']!.style!.margin.left, 40);
}

Future<EpubChapterSource> _openImageMarker(String marker) async {
  final source = await openCssChapter(
    body: '<ul><li>图片标记正文</li></ul>',
    css:
        '$_baseCss ul { padding-left: 40px; list-style-position: outside; '
        'list-style-image: url("../Images/marker.png"); '
        'list-style-type: "$marker"; }',
    contentWidth: 300,
    contentHeight: 160,
    binaryFiles: {_markerImagePath: await _markerImageBytes()},
  );
  addTearDown(source.close);
  return source;
}

Future<Uint8List> _markerImageBytes() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xffff0000), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

Future<Uint8List> _renderPage(PageContent page, {ui.Image? markerImage}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(
    listMarkerImageOf: (block) => block.style?.listStyleImage,
    imageLookup: (url) => url == _markerImagePath ? markerImage : null,
  ).paint(ui.Canvas(recorder), page, pageSize: const ui.Size(300, 160));
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 160);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

Future<void> _imageMarkerPriority() async {
  final first = await _openImageMarker('AbC');
  final second = await _openImageMarker('很长的备用字符串');
  final empty = await _openImageMarker('');
  final firstPage = (await first.loadChapter(0)).single;
  final bytes = await first.readImageBytes(_markerImagePath);
  expect(bytes, isNotNull);
  final codec = await ui.instantiateImageCodec(bytes!);
  final image = (await codec.getNextFrame()).image;
  addTearDown(image.dispose);
  addTearDown(codec.dispose);
  final pixels = await _renderPage(firstPage, markerImage: image);
  for (final source in [second, empty]) {
    final page = (await source.loadChapter(0)).single;
    final other = await _renderPage(page, markerImage: image);
    expect(listEquals(pixels, other), isTrue, reason: '有图时字符串内容不改变标记绘制');
  }
  final fallback = await _renderPage(firstPage);
  expect(listEquals(pixels, fallback), isFalse, reason: '图片不可用时才绘制备用字符串');
  expect(firstPage.slices.single.block.style!.listStyleImage, _markerImagePath);
}

Future<EpubChapterSource> _openPagedMarker() => _open(
  '<ol><li id="item">$_longListText</li></ol>',
  'ol { padding-left: 24px; list-style: "$_marker" inside; }',
  width: 180,
  height: 120,
);

Future<void> _markerPagination() async {
  final source = await _openPagedMarker();
  final pages = await source.loadChapter(0);
  expect(pages.length, greaterThan(1));
  final slices = pages.expand((page) => page.slices).toList();
  expect(slices.where((slice) => slice.startLine == 0), hasLength(1));
  expect(slices.skip(1).every((slice) => slice.continuesBefore), isTrue);
  expect(slices.map((slice) => slice.block.listMarker), everyElement(_marker));
  for (var i = 1; i < slices.length; i++) {
    expect(slices[i].startLine, slices[i - 1].endLine);
  }
  expect(ChapterText.fromPages(pages).text, _longListText);
}

Future<void> _markerTextAndCfi() async {
  final source = await _openPagedMarker();
  final pages = await source.loadChapter(0);
  expect(pages.first.slices.first.block.listMarker, _marker);
  final anchor = await source.loadAnchorChapter(0);
  expect(source.chapterPlainText(0).trim(), _longListText);
  expect(anchor.text, _longListText);
  expect(ChapterText.fromPages(pages).text, _longListText);
  final search = ScanSearchService(source: source);
  addTearDown(search.dispose);
  expect(await search.search(_marker), isEmpty);
  final results = await search.search('目标原文');
  expect(results, hasLength(1));
  final cfi = await search.resolveCfi(results.single);
  expect(cfi, isNotNull);
  final offset = _longListText.indexOf('目标原文');
  expect(anchor.offsetFor(cfi!), offset);
  expect(cfi, anchor.cfiAt(offset));
}
