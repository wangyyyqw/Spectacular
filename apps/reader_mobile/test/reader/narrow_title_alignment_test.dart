import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';

import 'support/css_chapter_book.dart';

const _title = '第一卷•我们生活在南京';
const _authorEm = 16 * 1.2;
const _contentWidth = _authorEm * 1.2;
const _borderWidth = _contentWidth + _authorEm + 2;
const _titleCss = '''
h1.post {
  font-family: Ahem; font-size: 1.2em; line-height: 140%;
  text-align: center; text-indent: 0; width: 1.2em;
  border-left: 1px solid maroon; border-right: 1px solid maroon;
  padding: 0 .5em; margin: 6.5em 6.5em 0 auto;
}
''';

Future<PageContent> _page({
  double fontSize = 17,
  double width = 350,
  String css = 'body { margin: 0 1%; }',
  bool nested = false,
}) async {
  final source = await openCssChapter(
    body:
        '${nested ? '<div class="frame">' : ''}'
        '<h1 class="post">$_title</h1>${nested ? '</div>' : ''}',
    css: 'html, body { font-size: 16px; } $_titleCss $css',
    contentWidth: width,
    contentHeight: 720,
    overrides: ReaderOverrides(fontSize: fontSize),
  );
  addTearDown(source.close);
  return (await source.loadChapter(0)).single;
}

void _expectTextCenter(PageContent page, double borderLeft) {
  final block = page.slices.single.block;
  expect(block.layout.isVertical, isFalse, reason: '原书通过窄宽度逐字换行');
  expect(block.layout.maxWidth, closeTo(_contentWidth, .01));
  expect(block.style!.padding.horizontal, closeTo(_authorEm, .01));
  expect(block.layout.lineCount, _title.length);
  for (final line in TextHitTester.lineBoxes(page)) {
    expect(line.rect.center.dx, closeTo(borderLeft + _borderWidth / 2, .01));
  }
}

Future<void> _expectRightMargin(double fontSize, bool projected) async {
  const width = 350.0;
  final outer = projected ? width * .01 : 0.0;
  final page = await _page(
    fontSize: fontSize,
    css: 'body { margin: 0 ${projected ? '1%' : '0'}; }',
  );
  final style = page.slices.single.block.style!;
  final right = fontSize * 1.2 * 6.5;
  final left = width - outer - right - _borderWidth;
  expect(style.margin.right, closeTo(outer + right, .01));
  expect(style.margin.left, closeTo(left, .01));
  expect(style.margin.horizontal + _borderWidth, closeTo(width, .01));
  _expectTextCenter(page, left);
}

Future<void> _expectLeftMargin() async {
  final page = await _page(
    css: '''
body { margin: 0 1%; }
h1.post { margin-left: 6.5em; margin-right: auto; }
''',
  );
  const left = 3.5 + 17 * 1.2 * 6.5;
  final style = page.slices.single.block.style!;
  expect(style.margin.left, closeTo(left, .01));
  expect(style.margin.right, closeTo(350 - left - _borderWidth, .01));
  _expectTextCenter(page, left);
}

Future<void> _expectCenteredMargins() async {
  final page = await _page(
    css: '''
body { margin: 0 7px 0 13px; }
h1.post { margin: 6.5em auto 0; }
''',
  );
  const left = 13 + (350 - 13 - 7 - _borderWidth) / 2;
  expect(page.slices.single.block.style!.margin.left, closeTo(left, .01));
  _expectTextCenter(page, left);
}

Future<void> _expectShrunkTitle() async {
  final page = await _page(
    fontSize: 12,
    width: 150,
    css: 'body { margin: 0; }',
  );
  const left = 150 - 12 * 1.2 * 6.5 - _borderWidth;
  expect(page.slices.single.block.style!.margin.left, closeTo(left, .01));
  _expectTextCenter(page, left);
}

Future<void> _expectNestedTitle() async {
  final page = await _page(
    nested: true,
    css: '''
body { margin: 0; }
.frame { width: 200px; padding: 10px; border: 2px solid; margin: 0 0 0 20px; }
''',
  );
  final block = page.slices.single.block;
  final frame = block.containers.single.container;
  expect(frame.left, 20);
  expect(frame.contentLeft, 32);
  expect(frame.contentWidth, 200);
  const left = 32 + 200 - 17 * 1.2 * 6.5 - _borderWidth;
  expect(block.style!.margin.left, closeTo(left, .01));
  _expectTextCenter(page, left);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fontSize in [12.0, 16.0, 17.0]) {
    test(
      '字号 $fontSize 下窄标题的相对右边距和自动左边距同步更新',
      () => _expectRightMargin(fontSize, true),
    );
  }
  test('没有祖先投影时也重新求解自动左边距', () => _expectRightMargin(17, false));
  test('自动右边距吸收左侧相对外边距的缩放变化', _expectLeftMargin);
  test('左右自动外边距让窄标题在不对称父盒内居中', _expectCenteredMargins);
  test('缩小字号后自动外边距从溢出状态恢复剩余空间', _expectShrunkTitle);
  test('缩放窄标题边距时保留祖先的固定盒和内缩', _expectNestedTitle);
}
