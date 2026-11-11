import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/search/chapter_text.dart';
import 'package:reader_mobile/search/scan_search_service.dart';

import 'support/css_chapter_book.dart';

const _baseCss =
    'html, body, div, p, pre { margin: 0; padding: 0; } '
    'html, body, div, p, pre { font-family: Ahem; font-size: 16px; '
    'font-weight: normal; line-height: 1.25; letter-spacing: 0; '
    'word-spacing: 0; text-indent: 0; text-align: left; } ';
const _boxColor = 0xff123456;
const _sample = 'aa BBBBB cc';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _registerTextTests();
  _registerContainerTests();
  _registerBoxTests();
  test('fit-content 随旋屏在最小宽、可用宽和最大宽之间重排', _resizeFit);
  test('用户字号变化后重新预测，反复切换不累积放大', _resizeFont);
  test('预测与分页重排不改变原文、搜索、CFI 和字符进度', _stablePositions);
  test('嵌套容器预测不重复推进伪元素 counter', _counterSnapshot);
}

void _registerTextTests() {
  test('min-content 以最长英文词确定内容宽并在空格处换行', _minimumWords);
  test('max-content 超过视口时保持整条软行的自然宽度', _maximumWords);
  for (final mode in ['min-content', 'max-content', 'fit-content']) {
    test('$mode 不把长英文不可断词压缩到视口宽度', () => _longWord(mode));
  }
  for (final mode in ['min-content', 'max-content']) {
    test('$mode 消费中文的逐字断行机会', () => _cjkText(mode));
    test('$mode 的 pre 宽度保留空格并取最长硬行', () => _preText(mode));
    test('$mode 使用字间距和行内实际字号', () => _styledText(mode));
  }
  test('max-content 尊重 br，取最长硬行而不拼接两行', _hardBreak);
  for (final width in [32.0, 112.0, 300.0]) {
    test('fit-content 在 $width 像素视口消费正确宽度边界', () => _fitBound(width));
  }
  test('fit-content 可用宽扣除外边距、边框和内边距', _fitInsets);
}

void _registerContainerTests() {
  test('max-content 容器取最大子块占宽，段落不横向拼接', _siblingWidths);
  test('min-content 容器取各子块最长不可断内容的最大值', _containerMinimum);
  test('嵌套容器占宽计入子容器边框、内边距和外边距', _nestedInsets);
  test('显式定宽子块的边框盒与外边距参与父容器预测', _fixedChild);
  test('子容器自身的 min-content 约束参与父 max-content 预测', _nestedMode);
}

void _registerBoxTests() {
  for (final tag in ['p', 'div']) {
    for (final sizing in ['content-box', 'border-box']) {
      test('$tag 的 $sizing 不从内在内容宽重复扣除边框和内边距', () async {
        await _intrinsicInsets(tag, sizing);
      });
    }
    test('$tag 的 min/max-width 钳制内在宽度，冲突时 min 优先', () async {
      await _widthConstraints(tag);
    });
    test('$tag 的百分比 min/max-width 相对父内容宽并遵守 border-box', () async {
      await _percentageConstraints(tag);
    });
    test('$tag 的实际背景和边框按内在宽度绘制', () => _paintWidth(tag));
  }
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

Future<Map<String, PageBlock>> _blocks(EpubChapterSource source) async => {
  for (final page in await source.loadChapter(0))
    for (final slice in page.slices)
      if (slice.block.layout.text.isNotEmpty)
        slice.block.layout.text: slice.block,
};

// 独立文字测量只提供自然字宽，不调用待测的内在尺寸和盒模型实现。
double _textWidth(String text, {double size = 16, double spacing = 0}) =>
    _spanWidth(
      TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Ahem',
          fontSize: size,
          letterSpacing: spacing,
        ),
      ),
    );

double _spanWidth(TextSpan span) {
  final painter = TextPainter(text: span, textDirection: ui.TextDirection.ltr)
    ..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

void _expectWidth(PageBlock block, double width) {
  expect(block.layout.maxWidth, closeTo(width, .05));
}

PageContainer _box(PageBlock block) => block.containers
    .map((fragment) => fragment.container)
    .singleWhere(
      (container) => container.style.backgroundColor.toARGB32() == _boxColor,
    );

String _boxHtml(String tag, String text, {String classes = ''}) => tag == 'p'
    ? '<p class="probe $classes">$text</p>'
    : '<div class="probe $classes"><p>$text</p></div>';

void _expectBoxWidth(PageBlock block, String tag, double width) {
  _expectWidth(block, width);
  if (tag == 'div') expect(_box(block).contentWidth, closeTo(width, .05));
}

Future<void> _minimumWords() async {
  final source = await _open('<p>$_sample</p>', 'p { width: min-content; }');
  final block = (await _blocks(source))[_sample]!;
  _expectWidth(block, _textWidth('BBBBB'));
  expect(block.layout.lineCount, 3);
  expect(
    block.layout.lines.map(
      (line) => block.layout.text.substring(line.start, line.end).trim(),
    ),
    ['aa', 'BBBBB', 'cc'],
  );
}

Future<void> _maximumWords() async {
  final source = await _open(
    '<p>$_sample</p>',
    'p { width: max-content; }',
    width: 80,
  );
  final block = (await _blocks(source))[_sample]!;
  _expectWidth(block, _textWidth(_sample));
  expect(block.layout.maxWidth, greaterThan(source.contentWidth));
  expect(block.layout.lineCount, 1);
}

Future<void> _longWord(String mode) async {
  const text = 'Antidisestablishmentarianism';
  final source = await _open('<p>$text</p>', 'p { width: $mode; }', width: 72);
  final block = (await _blocks(source))[text]!;
  _expectWidth(block, _textWidth(text));
  expect(block.layout.lineCount, 1);
}

Future<void> _cjkText(String mode) async {
  const text = '天地玄黄宇宙洪荒';
  final source = await _open('<p>$text</p>', 'p { width: $mode; }', width: 64);
  final block = (await _blocks(source))[text]!;
  final minimum = mode == 'min-content';
  _expectWidth(block, _textWidth(minimum ? '天' : text));
  expect(block.layout.lineCount, minimum ? text.length : 1);
}

Future<void> _hardBreak() async {
  final source = await _open(
    '<p>AB<br/>CDEFG</p>',
    'p { width: max-content; }',
    width: 48,
  );
  final block = (await _blocks(source)).values.single;
  expect(block.layout.text, 'AB\nCDEFG');
  _expectWidth(block, _textWidth('CDEFG'));
  expect(block.layout.lineCount, 2);
}

Future<void> _preText(String mode) async {
  const text = 'aa bb\nccc';
  final source = await _open(
    '<pre>$text</pre>',
    'pre { width: $mode; }',
    width: 40,
  );
  final block = (await _blocks(source)).values.single;
  expect(block.layout.text, text);
  _expectWidth(block, _textWidth('aa bb'));
  expect(block.layout.lineCount, 2);
}

Future<void> _styledText(String mode) async {
  final source = await _open(
    '<p>AA <span>BBBB</span> C</p>',
    'p { width: $mode; letter-spacing: 2px; } span { font-size: 24px; }',
    width: 100,
  );
  final block = (await _blocks(source))['AA BBBB C']!;
  final expected = mode == 'min-content'
      ? _textWidth('BBBB', size: 24, spacing: 2)
      : _spanWidth(
          const TextSpan(
            style: TextStyle(
              fontFamily: 'Ahem',
              fontSize: 16,
              letterSpacing: 2,
            ),
            children: [
              TextSpan(text: 'AA '),
              TextSpan(text: 'BBBB', style: TextStyle(fontSize: 24)),
              TextSpan(text: ' C'),
            ],
          ),
        );
  _expectWidth(block, expected);
  expect(block.layout.lineCount, mode == 'min-content' ? 3 : 1);
}

Future<void> _fitBound(double width) async {
  final source = await _open(
    '<p>$_sample</p>',
    'p { width: fit-content; }',
    width: width,
  );
  final expected = math.min(
    _textWidth(_sample),
    math.max(_textWidth('BBBBB'), width),
  );
  _expectWidth((await _blocks(source))[_sample]!, expected);
}

Future<void> _fitInsets() async {
  final source = await _open(
    '<p>AA BB CC DD EE</p>',
    'p { width: fit-content; margin: 0 8px; padding: 0 10px; '
        'border: 2px solid black; }',
    width: 160,
  );
  final block = (await _blocks(source)).values.single;
  _expectWidth(block, 120);
  expect(block.layout.lineCount, greaterThan(1));
}

Future<void> _siblingWidths() async {
  final source = await _open(
    '<div class="probe"><p>AAAA</p><p>BBBBBB</p></div>',
    '.probe { width: max-content; background: #123456; }',
    width: 64,
  );
  final blocks = await _blocks(source);
  final widest = _textWidth('BBBBBB');
  for (final block in blocks.values) {
    _expectBoxWidth(block, 'div', widest);
    expect(block.layout.lineCount, 1);
  }
  expect(identical(_box(blocks['AAAA']!), _box(blocks['BBBBBB']!)), isTrue);
}

Future<void> _containerMinimum() async {
  final source = await _open(
    '<div class="probe"><p>AA BBBB</p><p>C DDD E</p></div>',
    '.probe { width: min-content; background: #123456; }',
  );
  final blocks = await _blocks(source);
  for (final block in blocks.values) {
    _expectBoxWidth(block, 'div', _textWidth('BBBB'));
    expect(block.layout.lineCount, greaterThan(1));
  }
}

Future<void> _nestedInsets() async {
  final source = await _open(
    '<div class="probe"><div class="inner"><p>ABCDE</p></div><p>XY</p></div>',
    '.probe { width: max-content; background: #123456; '
        'padding: 3px; border: 2px solid black; } '
        '.inner { margin: 0 7px; padding: 0 5px; border: 2px solid black; }',
  );
  final blocks = await _blocks(source);
  final innerTextWidth = _textWidth('ABCDE');
  final outer = _box(blocks['ABCDE']!);
  expect(outer.contentWidth, closeTo(innerTextWidth + 28, .05));
  expect(outer.width, closeTo(innerTextWidth + 38, .05));
  _expectWidth(blocks['ABCDE']!, innerTextWidth);
  _expectWidth(blocks['XY']!, innerTextWidth + 28);
}

Future<void> _fixedChild() async {
  final source = await _open(
    '<div class="probe"><p class="fixed">AB</p><p>CD</p></div>',
    '.probe { width: max-content; background: #123456; } '
        '.fixed { width: 180px; padding: 0 5px; '
        'border: 1px solid black; margin: 0 7px; }',
    width: 128,
  );
  final blocks = await _blocks(source);
  expect(_box(blocks['AB']!).contentWidth, 206);
  _expectWidth(blocks['AB']!, 180);
  _expectWidth(blocks['CD']!, 206);
}

Future<void> _nestedMode() async {
  final source = await _open(
    '<div class="probe"><div class="inner"><p>AA BBBB CC</p></div><p>DD</p></div>',
    '.probe { width: max-content; background: #123456; } '
        '.inner { width: min-content; }',
  );
  final blocks = await _blocks(source);
  _expectBoxWidth(blocks['AA BBBB CC']!, 'div', _textWidth('BBBB'));
  expect(blocks['AA BBBB CC']!.layout.lineCount, 3);
}

Future<void> _intrinsicInsets(String tag, String sizing) async {
  const text = 'AB CD';
  final source = await _open(
    _boxHtml(tag, text),
    '.probe { width: max-content; box-sizing: $sizing; background: #123456; '
    'padding: 6px 10px; border: 2px solid black; }',
  );
  final block = (await _blocks(source))[text]!;
  _expectBoxWidth(block, tag, _textWidth(text));
  if (tag == 'div') {
    expect(_box(block).width, closeTo(_textWidth(text) + 24, .05));
  }
}

Future<void> _widthConstraints(String tag) async {
  final source = await _open(
    _boxHtml(tag, 'GG HHHH JJ', classes: 'grow') +
        _boxHtml(tag, 'AA BB CC', classes: 'cap') +
        _boxHtml(tag, 'DD EE FF', classes: 'conflict') +
        _boxHtml(tag, 'KK LL MM', classes: 'border-conflict'),
    '.probe { background: #123456; } '
    '.grow { width: min-content; min-width: 100px; } '
    '.cap { width: max-content; max-width: 80px; } '
    '.conflict { width: fit-content; min-width: 150px; max-width: 80px; } '
    '.border-conflict { width: fit-content; min-width: 150px; max-width: 80px; '
    'box-sizing: border-box; padding: 0 10px; border: 2px solid black; }',
  );
  final blocks = await _blocks(source);
  _expectBoxWidth(blocks['GG HHHH JJ']!, tag, 100);
  _expectBoxWidth(blocks['AA BB CC']!, tag, 80);
  _expectBoxWidth(blocks['DD EE FF']!, tag, 150);
  _expectBoxWidth(blocks['KK LL MM']!, tag, 126);
  expect(blocks['AA BB CC']!.layout.lineCount, 2);
  expect(blocks['DD EE FF']!.layout.lineCount, 1);
}

Future<void> _percentageConstraints(String tag) async {
  final source = await _open(
    '<div class="parent">${_boxHtml(tag, 'AA BB CC DD EE')} '
        '${_boxHtml(tag, 'LL MMMM NN', classes: 'minimum')}</div>',
    '.parent { width: 200px; padding: 10px; border: 2px solid black; } '
        '.probe { width: max-content; max-width: 75%; min-width: 50%; '
        'box-sizing: border-box; padding: 0 10px; border: 2px solid black; '
        'background: #123456; } .minimum { width: min-content; }',
    width: 320,
  );
  final blocks = await _blocks(source);
  _expectBoxWidth(blocks['AA BB CC DD EE']!, tag, 126);
  _expectBoxWidth(blocks['LL MMMM NN']!, tag, 76);
  if (tag == 'div') {
    expect(_box(blocks['AA BB CC DD EE']!).width, 150);
    expect(_box(blocks['LL MMMM NN']!).width, 100);
  }
}

Future<void> _resizeFit() async {
  final source = await _open(
    '<div class="probe"><p>$_sample</p></div>',
    '.probe { width: fit-content; background: #123456; }',
    width: 112,
    height: 220,
  );
  for (final width in [112.0, 40.0, 240.0, 112.0]) {
    await source.applyContentSize(width: width, height: 220);
    final block = (await _blocks(source))[_sample]!;
    final expected = math.min(
      _textWidth(_sample),
      math.max(_textWidth('BBBBB'), width),
    );
    _expectBoxWidth(block, 'div', expected);
  }
}

Future<void> _resizeFont() async {
  const text = 'AA BBB CC';
  final source = await _open(
    '<div class="probe"><p>$text</p></div>',
    '.probe { width: max-content; padding: 0 10px; '
        'border: 2px solid black; background: #123456; }',
  );
  for (final size in [16.0, 24.0, 32.0, 16.0]) {
    await source.applyOverrides(ReaderOverrides(fontSize: size));
    final block = (await _blocks(source))[text]!;
    expect(block.style!.fontSize, size);
    _expectBoxWidth(block, 'div', _textWidth(text, size: size));
    expect(_box(block).width, closeTo(_textWidth(text, size: size) + 24, .05));
  }
}

Future<void> _stablePositions() async {
  final text = '${'天地玄黄宇宙洪荒' * 40}目标原文';
  final source = await _open(
    '<div class="probe"><p id="text">$text</p></div>',
    '.probe { width: fit-content; }',
    width: 128,
    height: 100,
  );
  final anchor = await source.loadAnchorChapter(0);
  final cfi = anchor.cfiAt(text.indexOf('目标原文'))!;
  final progress = source.readingPercentForCfi(cfi);
  final middle = await source.prepareCfiForReadingPercent(.61);
  expect(progress, isNotNull);
  expect(middle, isNotNull);
  for (final (width, fontSize) in [
    (128.0, 16.0),
    (224.0, 24.0),
    (128.0, 16.0),
  ]) {
    await source.applyContentSize(width: width, height: 100);
    await source.applyOverrides(ReaderOverrides(fontSize: fontSize));
    final pages = await source.loadChapter(0);
    final current = await source.loadAnchorChapter(0);
    expect(pages.length, greaterThan(1));
    expect(source.chapterPlainText(0).trim(), text);
    expect(ChapterText.fromPages(pages).text, text);
    expect(current.text, text);
    expect(current.cfiAt(text.indexOf('目标原文')), cfi);
    expect(current.offsetFor(cfi), text.indexOf('目标原文'));
    expect(source.readingPercentForCfi(cfi), closeTo(progress!, 1e-12));
    expect(await source.prepareCfiForReadingPercent(.61), middle);
  }
  final search = ScanSearchService(source: source);
  addTearDown(search.dispose);
  final results = await search.search('目标原文');
  expect(results, hasLength(1));
  expect(await search.resolveCfi(results.single), cfi);
}

Future<void> _counterSnapshot() async {
  final source = await _open(
    '<div class="probe"><div class="inner"><p class="item">甲</p>'
        '<p class="item">乙</p></div><p class="item">丙</p></div>',
    '.probe { width: max-content; counter-reset: item; background: #123456; } '
        '.inner { width: fit-content; } '
        '.item::before { counter-increment: item; content: counter(item) ". "; }',
    width: 160,
    height: 90,
  );
  for (final size in [16.0, 24.0, 16.0]) {
    await source.applyContentSize(width: 160 + size, height: 90);
    await source.applyOverrides(ReaderOverrides(fontSize: size));
    final blocks = await _blocks(source);
    expect(blocks.keys, ['1. 甲', '2. 乙', '3. 丙']);
    for (final block in blocks.values) {
      _expectBoxWidth(block, 'div', _textWidth('1. 甲', size: size));
    }
  }
}

Future<void> _paintWidth(String tag) async {
  const text = 'AB CD';
  final source = await _open(
    _boxHtml(tag, text),
    '.probe { width: max-content; padding: 8px 10px; '
    'border: 2px solid black; background: #ff0000; color: transparent; }',
    height: 160,
  );
  final pixels = await _renderPage((await source.loadChapter(0)).single);
  final redXs = <int>[];
  for (var offset = 0; offset < pixels.length; offset += 4) {
    if (pixels[offset] == 255 &&
        pixels[offset + 1] == 0 &&
        pixels[offset + 2] == 0) {
      redXs.add((offset ~/ 4) % 300);
    }
  }
  expect(redXs, isNotEmpty);
  expect(redXs.reduce(math.min), 2);
  expect(redXs.reduce(math.max), closeTo(_textWidth(text) + 21, 1));
  final outside = (8 * 300 + (_textWidth(text) + 28).round()) * 4;
  expect(pixels.sublist(outside, outside + 4), [255, 255, 255, 255]);
}

Future<Uint8List> _renderPage(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    ui.Canvas(recorder),
    page,
    pageSize: const ui.Size(300, 160),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 160);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}
