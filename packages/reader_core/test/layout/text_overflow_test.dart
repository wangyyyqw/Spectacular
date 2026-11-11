import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// `text-overflow: ellipsis`：截断 + 省略号宽参与测量（P2-37）。
///
/// Ahem 每字 1em：14px 字号下每字 14 宽、`…` 14 宽。
ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '14px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'white-space': 'nowrap',
      'text-overflow': 'ellipsis',
      ...overrides,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nowrap + ellipsis：截成最长可放前缀 + …，行宽 ≤ 内容宽', () {
    const text = 'abcdefghijklmnopqrst';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(const {}),
      maxWidth: 168,
    );
    expect(layout.lineCount, 1);
    final line = layout.lines.single;
    expect(layout.ellipsized, isTrue);
    expect(line.ellipsized, isTrue);
    expect(line.ellipsisWidth, closeTo(14, 0.01));
    // 内容宽 168 - 省略号 14 = 154 → 11 个字符。
    expect(line.end, 11);
    expect(line.width, closeTo(154 + 14, 0.01));
    expect(line.width, lessThanOrEqualTo(168 + 0.01));
    // 行区间仍是原文坐标（CFI/选区安全）。
    expect(layout.text.substring(line.start, line.end), 'abcdefghijk');
  });

  test('clip 不截断：整行保留，行宽可超内容宽', () {
    const text = 'abcdefghijklmnopqrst';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(const {'text-overflow': 'clip'}),
      maxWidth: 168,
    );
    final line = layout.lines.single;
    expect(layout.ellipsized, isFalse);
    expect(line.ellipsized, isFalse);
    expect(line.end, text.length);
    expect(line.width, closeTo(280, 0.01));
  });

  test('内容宽足够时不截断', () {
    const text = 'abcdefgh';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(const {}),
      maxWidth: 168,
    );
    expect(layout.ellipsized, isFalse);
    expect(layout.lines.single.width, closeTo(112, 0.01));
    expect(layout.lines.single.end, text.length);
  });

  test('软换行 + 超宽单行（不可断长串）也按内容宽截断', () {
    const text = 'abcdefghijklmnopqrst';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(const {'white-space': 'normal'}),
      maxWidth: 168,
    );
    for (final line in layout.lines) {
      expect(line.width, lessThanOrEqualTo(168 + 0.01));
    }
  });

  test('break-word 超宽词先整体换到下一行，再从新行逐字断开', () {
    const text = 'pre ABCDEFGHIJK';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(const {
        'white-space': 'normal',
        'overflow-wrap': 'break-word',
        'text-overflow': 'clip',
      }),
      maxWidth: 80,
    );
    expect(layout.lineCount, greaterThan(1));
    expect(layout.lines.first.end, text.indexOf('A'));
    expect(
      layout.text.substring(layout.lines.first.start, layout.lines.first.end),
      'pre ',
    );
    expect(
      layout.text.substring(layout.lines[1].start, layout.lines[1].end),
      startsWith('A'),
    );
  });

  test('break-word 复合词优先在连字符处分段，再对超宽段逐字断开', () {
    const text = 'pre abcdefghij-abcdefghij';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(const {
        'white-space': 'normal',
        'overflow-wrap': 'break-word',
        'text-overflow': 'clip',
      }),
      maxWidth: 80,
    );
    final tailStart = text.indexOf('-') + 1;
    expect(
      layout.lines.any((line) => line.start == tailStart),
      isTrue,
      reason: '第二段超宽词也应从新行开始，而不是占用连字符后的余宽',
    );
  });

  test('break-all 不套用 break-word 的整词换行，继续吃当前行余宽', () {
    const text = 'pre ABCDEFGHIJK';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(const {
        'white-space': 'normal',
        'word-break': 'break-all',
        'text-overflow': 'clip',
      }),
      maxWidth: 80,
    );
    expect(layout.lines.first.end, greaterThan(text.indexOf('A')));
    expect(
      layout.text.substring(layout.lines.first.start, layout.lines.first.end),
      'pre A',
    );
  });

  test('ellipsis 参与 justify 前测量：截断行不产生 justify 拉伸', () {
    const text = 'abcdefghijklmnopqrst';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(const {'text-align': 'justify'}),
      maxWidth: 168,
    );
    final line = layout.lines.single;
    expect(line.ellipsized, isTrue);
    expect(line.justifyExtra, 0, reason: '截断行不拉伸');
    expect(line.width, lessThanOrEqualTo(168 + 0.01));
  });

  test('竖排 nowrap + ellipsis 按声明高度（列长）截断', () {
    const text = 'abcdefghijklmnopqrst';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(const {'writing-mode': 'vertical-rl', 'height': '100px'}),
      maxWidth: 54,
    );
    final column = layout.lines.single;
    expect(column.vertical, isTrue);
    expect(column.ellipsized, isTrue);
    expect(column.end, 6);
    expect(column.height, closeTo(98, 0.01));
    expect(column.height, lessThanOrEqualTo(100 + 0.01));
    expect(column.offsetX, 0);
  });

  test('竖排 break-word 按列长判断超宽词并分列', () {
    const text = 'abcdefghijklmno';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(const {
        'writing-mode': 'vertical-rl',
        'height': '100px',
        'white-space': 'normal',
        'overflow-wrap': 'break-word',
        'text-overflow': 'clip',
      }),
      maxWidth: 240,
    );
    expect(layout.lineCount, greaterThan(1));
    for (final column in layout.lines) {
      expect(column.height, lessThanOrEqualTo(100 + 0.01));
    }
  });
}
