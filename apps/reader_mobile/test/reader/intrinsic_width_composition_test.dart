import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

const _baseCss =
    'html, body, div, p, ul, li { margin: 0; padding: 0; font-family: Ahem; '
    'font-size: 16px; font-weight: normal; text-indent: 0; line-height: 1.25; } ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _registerTextCompositions();
  _registerMarkerCompositions();
  _registerOriginalPaths();
  test('预测子块占宽时 auto 外边距不能填满父视口', _intrinsicAutoMargins);
  test('单字宽中文 min-content 容器不被后代的默认最小宽撑大', _singleCjkWidth);
  test('容器预测不重复消耗叶子 counter reset 与 increment', _counterSnapshot);
  test('CJK、ZWSP、anywhere 测量取消后可重新运行', _cancelMeasurement);
}

void _registerTextCompositions() {
  for (final tag in ['p', 'div']) {
    test('$tag 的 max-content 包含首行缩进', () => _maximumIndent(tag));
    test('$tag 的 min-content 由带缩进的首词决定', () => _minimumIndent(tag, false));
    test('$tag 的 min-content 不把首行缩进加到后续更长词', () => _minimumIndent(tag, true));
    test('$tag 的 max-content 消费 first-letter 实际字号', () => _firstLetter(tag));
    test('$tag 的 max-content 配合 auto 外边距居中', () => _centered(tag));
  }
}

void _registerMarkerCompositions() {
  test('li 的 max-content 包含 inside 字符串标记', () => _insideMarker(false));
  test('祖先 max-content 容器预测包含后代 inside 字符串标记', () => _insideMarker(true));
}

void _registerOriginalPaths() {
  test('原有数值 width 可以同时容纳首行缩进和整段文字', _numericIndent);
  test('原有数值 width 的 auto 外边距正常居中', _numericCenter);
  test('原有数值 width 可以容纳 inside 字符串标记与正文', _numericMarker);
}

Future<EpubChapterSource> _open(String body, String css) async {
  final source = await openCssChapter(body: body, css: '$_baseCss$css');
  addTearDown(source.close);
  return source;
}

Future<List<PageBlock>> _blocks(EpubChapterSource source) async => {
  for (final page in await source.loadChapter(0))
    for (final slice in page.slices) slice.block,
}.toList();

// 使用独立字形测量提供预期，不调用被测内在尺寸计算。
double _textWidth(String text, {double fontSize = 16}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: 'Ahem', fontSize: fontSize),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

String _paragraph(String tag, String text) =>
    tag == 'p' ? '<p>$text</p>' : '<div><p>$text</p></div>';

void _expectWidth(PageBlock block, String tag, double expected) {
  expect(block.layout.maxWidth, closeTo(expected, .05));
  if (tag == 'div') {
    expect(
      block.containers.last.container.contentWidth,
      closeTo(expected, .05),
    );
  }
}

Future<void> _maximumIndent(String tag) async {
  final source = await _open(
    _paragraph(tag, 'AB CD'),
    '$tag { width: max-content; } p { text-indent: 32px; }',
  );
  final block = (await _blocks(source)).single;
  _expectWidth(block, tag, _textWidth('AB CD') + 32);
  expect(block.layout.lineCount, 1);
  expect(block.layout.lines.single.offsetX, 32);
}

Future<void> _minimumIndent(String tag, bool longerLater) async {
  final text = longerLater ? 'A BBBBBBBB' : 'AA B';
  final expected = longerLater ? _textWidth('BBBBBBBB') : _textWidth('AA') + 32;
  final source = await _open(
    _paragraph(tag, text),
    '$tag { width: min-content; } p { text-indent: 32px; }',
  );
  final block = (await _blocks(source)).single;
  _expectWidth(block, tag, expected);
  expect(block.layout.lineCount, 2);
  expect(block.layout.lines.first.offsetX, 32);
  expect(block.layout.lines.last.offsetX, 0);
  // 后续长词只约束内在宽度，首行断词沿用现有数值宽度路径。
  if (!longerLater) {
    expect(
      block.layout.lines.map(
        (line) => text.substring(line.start, line.end).trim(),
      ),
      ['AA', 'B'],
    );
  }
}

Future<void> _firstLetter(String tag) async {
  final source = await _open(
    _paragraph(tag, 'AB'),
    '$tag { width: max-content; } p::first-letter { font-size: 32px; }',
  );
  final block = (await _blocks(source)).single;
  _expectWidth(block, tag, _textWidth('A', fontSize: 32) + _textWidth('B'));
  expect(block.layout.lineCount, 1);
}

Future<void> _centered(String tag) async {
  final source = await _open(
    _paragraph(tag, 'AB CD'),
    '$tag { width: max-content; margin: 0 auto; }',
  );
  final pages = await source.loadChapter(0);
  final expectedLeft = (source.contentWidth - _textWidth('AB CD')) / 2;
  expect(
    TextHitTester.lineBoxes(pages.single).single.rect.left,
    closeTo(expectedLeft, .05),
  );
  final block = pages.single.slices.single.block;
  _expectWidth(block, tag, _textWidth('AB CD'));
  if (tag == 'div') {
    expect(block.containers.last.container.left, closeTo(expectedLeft, .05));
  }
}

Future<void> _insideMarker(bool wrapper) async {
  const list = '<ul><li>AB</li></ul>';
  final source = await _open(
    wrapper ? '<div>$list</div>' : list,
    'ul { list-style: "LONG" inside; } '
    '${wrapper ? 'div' : 'li'} { width: max-content; }',
  );
  final block = (await _blocks(source)).single;
  expect(block.listMarker, 'LONG');
  final expected = _textWidth('LONG') + 16 * .333 + _textWidth('AB');
  _expectWidth(block, wrapper ? 'div' : 'li', expected);
  expect(block.layout.lineCount, 1);
  expect(
    block.layout.lines.single.offsetX,
    closeTo(_textWidth('LONG') + 16 * .333, .05),
  );
  expect(block.layout.text, 'AB', reason: '测量标记占宽不应把标记插入原文');
}

Future<void> _intrinsicAutoMargins() async {
  final source = await _open(
    '<div><p>AB</p></div>',
    'div { width: max-content; } p { width: 80px; margin: 0 auto; }',
  );
  final block = (await _blocks(source)).single;
  expect(block.containers.last.container.contentWidth, 80);
  expect(block.layout.maxWidth, 80);
}

Future<void> _singleCjkWidth() async {
  const text = '天地玄黄';
  final source = await _open(
    '<div><p>$text</p></div>',
    'div { width: min-content; }',
  );
  final block = (await _blocks(source)).single;
  _expectWidth(block, 'div', _textWidth('天'));
  expect(block.layout.lineCount, text.length);
  expect(
    block.layout.lines.map((line) => text.substring(line.start, line.end)),
    ['天', '地', '玄', '黄'],
  );
}

Future<void> _counterSnapshot() async {
  final source = await _open(
    '<div><p class="reset">甲</p><p>乙</p></div>',
    'div { width: max-content; } .reset { counter-reset: item 9; } '
        'p::before { counter-increment: item; content: counter(item) ". "; }',
  );
  final blocks = await _blocks(source);
  expect(blocks.map((block) => block.layout.text), ['10. 甲', '11. 乙']);
  for (final block in blocks) {
    _expectWidth(block, 'div', _textWidth('10. 甲'));
  }
}

Future<void> _cancelMeasurement() async {
  final style = ComputedStyle({
    'font-size': '16px',
    'font-family': 'Ahem',
    'overflow-wrap': 'anywhere',
  });
  var checks = 0;
  await expectLater(
    TextLayoutEngine.minContentTextWidthAsync(
      text: '天\u200B地AB' * 300,
      style: style,
      checkpoint: () async {
        if (++checks == 3) throw StateError('诊断取消');
      },
    ),
    throwsStateError,
  );
  expect(checks, 3);
  expect(
    await TextLayoutEngine.minContentTextWidthAsync(text: '天地AB', style: style),
    closeTo(_textWidth('A'), .05),
  );
}

Future<void> _numericIndent() async {
  final source = await _open(
    '<p>AB CD</p>',
    'p { width: 112px; text-indent: 32px; }',
  );
  expect((await _blocks(source)).single.layout.lineCount, 1);
}

Future<void> _numericCenter() async {
  final source = await _open(
    '<div><p>AB CD</p></div>',
    'div { width: 80px; margin: 0 auto; }',
  );
  final pages = await source.loadChapter(0);
  expect(TextHitTester.lineBoxes(pages.single).single.rect.left, 110);
}

Future<void> _numericMarker() async {
  final source = await _open(
    '<ul><li>AB</li></ul>',
    'ul { list-style: "LONG" inside; } li { width: 102px; }',
  );
  expect((await _blocks(source)).single.layout.lineCount, 1);
}
