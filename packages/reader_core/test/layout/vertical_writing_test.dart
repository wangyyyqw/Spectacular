import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/text_layout.dart';

/// 竖排（`writing-mode: vertical-rl / vertical-lr`）布局侧映射。
///
/// Ahem 每字 1em：17px 字号下每字 17 宽；行高 1.6 → 列宽 27.2。
ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '17px',
      'line-height': '1.6',
      'font-family': 'Ahem',
      ...overrides,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('vertical-rl：行变列，列宽 = 行高，列从右向左推进', () {
    // 列长 = 声明 height 200 → 20 字 × 17 = 340 → 2 列。
    final layout = TextLayoutEngine.layout(
      text: '一二三四五六七八九十' * 2,
      style: _style(const {'writing-mode': 'vertical-rl', 'height': '200px'}),
      maxWidth: 350,
    );
    expect(layout.writingMode, CssWritingMode.verticalRl);
    expect(layout.isVertical, isTrue);
    expect(layout.lineCount, 2, reason: '2 列');
    for (final column in layout.lines) {
      expect(column.vertical, isTrue);
      // 列宽 = 实测行高（Skia 行盒高取整：17×1.6=27.2 → 27）。
      expect(column.width, closeTo(27, 0.01), reason: '列宽 = 行高');
    }
    // rl：首列在最右。
    expect(layout.lines.first.columnX, closeTo(27, 0.01));
    expect(layout.lines.last.columnX, closeTo(0, 0.01));
    expect(layout.lines.first.columnIndex, 0);
    // 块宽 = 列数 × 列宽；块高 = 最长列。
    expect(layout.width, closeTo(2 * 27, 0.01));
    // 块高 = 最长列（11 字 × 17 = 187 ≤ 列长 200）。
    expect(layout.height, closeTo(187, 1));
  });

  test('vertical-lr：列从左向右推进', () {
    final layout = TextLayoutEngine.layout(
      text: '一二三四五六七八九十' * 2,
      style: _style(const {'writing-mode': 'vertical-lr', 'height': '200px'}),
      maxWidth: 350,
    );
    expect(layout.writingMode, CssWritingMode.verticalLr);
    expect(layout.lines.first.columnX, closeTo(0, 0.01));
    expect(layout.lines.last.columnX, closeTo(27, 0.01));
  });

  test('竖排与横排的字符顺序/列内容一致（同文本行区间）', () {
    const text = '竖排文字顺序与横排一致，只是沿列自上而下排列。';
    final horizontal = TextLayoutEngine.layout(text: text, style: _style(), maxWidth: 200);
    final vertical = TextLayoutEngine.layout(
      text: text,
      style: _style(const {'writing-mode': 'vertical-rl', 'height': '200px'}),
      maxWidth: 200,
    );
    // 同一段文本：把列按逻辑顺序拼起来 = 原文（每列一个连续区间）。
    final joined = <String>[
      for (final column in vertical.lines)
        text.substring(column.start, column.end),
    ].join();
    expect(joined, text);
    // 每列的字符数不超过横排一行的字符数上限（列长相同）。
    final maxHorizontalChars = horizontal.lines
        .map((line) => line.end - line.start)
        .reduce((a, b) => a > b ? a : b);
    for (final column in vertical.lines) {
      expect(column.end - column.start, lessThanOrEqualTo(maxHorizontalChars));
    }
  });

  test('逐字符度量：CJK 正立 1em、拉丁 mixed 按字形宽、upright 全 1em', () {
    final mixed = TextLayoutEngine.verticalGlyphMetrics(
      '一A',
      _style(),
    );
    expect(mixed, hasLength(2));
    expect(mixed[0].upright, isTrue, reason: 'CJK 正立');
    expect(mixed[0].advance, closeTo(17, 0.01), reason: '正立 = 1em');
    expect(mixed[1].upright, isFalse, reason: '拉丁侧躺');
    expect(mixed[1].advance, closeTo(17, 0.01), reason: 'Ahem 每字 17 宽');

    final upright = TextLayoutEngine.verticalGlyphMetrics(
      'A',
      _style(const {'text-orientation': 'upright'}),
    );
    expect(upright.single.upright, isTrue);
    expect(upright.single.advance, closeTo(17, 0.01));
  });

  test('横排不受影响：vertical 标记为 false、无列信息', () {
    final layout = TextLayoutEngine.layout(
      text: '横排对照',
      style: _style(),
      maxWidth: 200,
    );
    expect(layout.isVertical, isFalse);
    expect(layout.writingMode, CssWritingMode.horizontalTb);
    expect(layout.lines.every((line) => line.vertical == false), isTrue);
    expect(layout.lines.every((line) => line.columnIndex == null), isTrue);
  });

  test('未声明 height 时退回内容宽当列长（调用方需传页高近似）', () {
    final layout = TextLayoutEngine.layout(
      text: '一二三四五六七八九十' * 2,
      style: _style(const {'writing-mode': 'vertical-rl'}),
      maxWidth: 100,
    );
    // 列长 = 100 → 每列 5 字（85）→ 4 列。
    expect(layout.lineCount, 4);
    // 样式里声明了 line-height: 1.6 → 列宽 = 实测行高 27（与是否声明 height 无关）。
    expect(layout.lines.first.width, closeTo(27, 0.01));
  });
}
