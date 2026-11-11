import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/cjk_justify.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/line_spans.dart';

/// 两端对齐的行宽口径：`width` 是自然宽，`advanceWidth` 是绘制宽。
///
/// 浏览器（Chromium）量的是绘制宽——justify 行正好铺满版心，因此
/// `advanceWidth == 内容宽`；对照工具要导出这个值。
///
/// Ahem：每字 16px 宽，便于算精确值。
ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

TextLayoutResult _layout(
  String text, {
  double width = 168,
  ComputedStyle? style,
}) => TextLayoutEngine.layout(
  text: text,
  style: style ?? _style(const {'text-align': 'justify'}),
  maxWidth: width,
);

double _paintedWidth(TextLayoutResult layout, LineBox line) {
  final painter = TextPainter(
    text: buildLineSpan(
      layout: layout,
      line: line,
      baseStyle: TextLayoutEngine.textStyleFor(_style()),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('justify 行：末个间隙也参与均分，绘制宽 = 内容宽', () {
    // 25 个 CJK 字 ×16px：版心 168 → 每行 10 字（160）+ 余量 8。
    const text = '中文中文中文中文中文中文中文中文中文中文中文中文中文';
    final layout = _layout(text);
    expect(layout.lines.length, greaterThan(2));

    for (final line in layout.lines.take(layout.lines.length - 1)) {
      final lineText = text.substring(line.start, line.end);
      final gaps = cjkJustifyGapOffsets(lineText);
      expect(gaps.length, lineText.length - 1, reason: '纯中文 n 字 n-1 个间隙');
      expect(line.justifyExtra, closeTo(168 - line.width, 0.01));
      // 绘制宽 = 版心：末字之后不留额外间距，行尾正好顶到右缘。
      expect(line.advanceWidth, closeTo(168, 0.01));
      expect(_paintedWidth(layout, line), closeTo(line.advanceWidth, 0.05));
    }
  });

  test('justify 末行不拉伸：advanceWidth 等于自然宽', () {
    const text = '中文中文中文';
    final layout = _layout(text);
    final line = layout.lines.single;
    expect(line.justifyExtra, 0);
    expect(line.advanceWidth, closeTo(line.width, 0.01));
  });

  test('硬断行行不拉伸（pre + 两端对齐）', () {
    // 每行 4 字（64px），版心 168：硬断行行是行尾，按 start 对齐。
    const text = '中文中外\n中文中外';
    final layout = _layout(
      text,
      style: _style(const {'text-align': 'justify', 'white-space': 'pre'}),
    );
    expect(layout.lineCount, 2);
    expect(layout.lines[0].isHardBreak, isTrue);
    expect(layout.lines[0].justifyExtra, 0);
    expect(layout.lines[0].advanceWidth, closeTo(layout.lines[0].width, 0.01));
  });

  test('text-align: start 时不产生 justify 宽', () {
    final layout = _layout(
      '中文中文中文',
      style: _style(const {'text-align': 'start'}),
    );
    expect(layout.lines.single.justifyExtra, 0);
    expect(layout.lines.single.advanceWidth, layout.lines.single.width);
  });
}
