import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// `tab-size`（CSS Text 3）与 `line-break`（CSS Text 3）在行排版里的消费。
ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'white-space': 'pre',
      ...overrides,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tab-size 4：制表符展开到 4 个空格位（宽度一致）', () {
    final tabbed = TextLayoutEngine.layout(
      text: 'ab\tc',
      style: _style(const {'tab-size': '4'}),
      maxWidth: 400,
    );
    final spaces = TextLayoutEngine.layout(
      text: 'ab  c',
      style: _style(const {'tab-size': '4'}),
      maxWidth: 400,
    );
    expect(tabbed.lines.single.width, closeTo(spaces.lines.single.width, 0.01));
  });

  test('tab-size 8（默认）：制表符补齐到 8 列', () {
    final tabbed = TextLayoutEngine.layout(
      text: 'ab\tc',
      style: _style(const {}),
      maxWidth: 400,
    );
    final spaces = TextLayoutEngine.layout(
      text: 'ab      c',
      style: _style(const {}),
      maxWidth: 400,
    );
    expect(tabbed.lines.single.width, closeTo(spaces.lines.single.width, 0.01));
  });

  test('expandTabs 换行后列计数归零', () {
    expect(expandTabs('a\tb\nc\td', 4), 'a   b\nc   d');
  });

  test('expandTabs 按实际字形宽度对齐制表位', () {
    const advances = <String, double>{'a': 10.25, 'b': 10.25, ' ': 4.25};
    double measure(String text) => text.runes.fold(
      0,
      (width, rune) =>
          width + (advances[String.fromCharCode(rune)] ?? 0),
    );

    expect(
      expandTabs(
        'a\tb',
        4,
        measureWidth: measure,
        spaceWidth: advances[' '],
      ),
      'a  b',
    );
    expect(
      expandTabs(
        'a\tb',
        8,
        measureWidth: measure,
        spaceWidth: advances[' '],
      ),
      'a      b',
    );
  });

  test('line-break: anywhere 允许长西文词任意断行', () {
    final wrap = _style(const {
      'white-space': 'normal',
      'line-break': 'anywhere',
    });
    final plan = TextLayoutEngine.planSoftBreaks(
      text: 'abcdefghij',
      hyphens: CssHyphens.manual,
      overflowWrap: CssOverflowWrap.normal,
      wordBreak: CssWordBreak.normal,
      contentWidth: 40,
      style: wrap,
    );
    // 断点以零宽标记插入测量文本，offsets 长度会超过原文字符数。
    expect(
      plan.offsets.length,
      greaterThan('abcdefghij'.length + 1),
      reason: 'anywhere 应当产生断点',
    );
  });
}
