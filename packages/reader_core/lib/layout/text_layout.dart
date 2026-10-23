import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../src/api/models.dart' show TextLayout;

/// 一行文本的布局结果。
class LineBox {
  /// 创建行框。
  const LineBox({
    required this.start,
    required this.end,
    required this.top,
    required this.height,
    required this.baseline,
    required this.width,
  });

  /// 行起始字符下标（半开区间，P1-23 精化）。
  final int start;

  /// 行结束字符下标（半开）。
  final int end;

  /// 行框顶部（相对文本块）。
  final double top;

  /// 行框高度。
  final double height;

  /// 基线（相对文本块）。
  final double baseline;

  /// 行实际宽度。
  final double width;

  /// 行底。
  double get bottom => top + height;

  @override
  String toString() =>
      'LineBox($start..$end, top=$top, h=$height, baseline=$baseline, w=$width)';
}

/// TextLayout 的测量结果。
class TextLayoutResult implements TextLayout {
  /// 创建结果。
  TextLayoutResult({
    required this.text,
    required this.lines,
    required this.width,
    required this.height,
    required this.maxWidth,
  });

  /// 原始文本。
  final String text;

  /// 行列表。
  final List<LineBox> lines;

  /// 最长行宽度。
  final double width;

  /// 总高度（各行高之和）。
  final double height;

  /// 布局使用的最大宽度。
  final double maxWidth;

  /// 行数。
  int get lineCount => lines.length;
}

/// 用 TextPainter 做行测量。
abstract final class TextLayoutEngine {
  /// 按 [maxWidth] 测量 [text]。
  ///
  /// [style] 提供 fontSize/lineHeightFactor/fontFamily/字重/斜体/颜色/对齐；
  /// 行高使用 CSS 语义（`fontSize × factor`），并显式设置 even 行距分布。
  static TextLayoutResult layout({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    double textScaleFactor = 1,
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
  }) {
    final width = maxWidth.isFinite ? math.max(1.0, maxWidth) : double.infinity;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyleFor(style, leadingDistribution: leadingDistribution),
      ),
      textDirection: TextDirection.ltr,
      textAlign: _textAlign(style.textAlign),
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout(maxWidth: width);

    final metrics = painter.computeLineMetrics();
    final lines = <LineBox>[];
    var top = 0.0;
    for (final metric in metrics) {
      // 用行框垂直中点取该行内的字符位置，再取边界；
      // 直接拿“上一行 end”做位置在硬换行/空行处会落回上一行。
      final position = painter.getPositionForOffset(
        Offset(0, top + metric.height / 2),
      );
      final boundary = painter.getLineBoundary(position);
      lines.add(
        LineBox(
          start: boundary.start,
          end: boundary.end,
          top: top,
          height: metric.height,
          baseline: top + metric.ascent,
          width: metric.width,
        ),
      );
      top += metric.height;
    }

    return TextLayoutResult(
      text: text,
      lines: List<LineBox>.unmodifiable(lines),
      width: painter.width,
      height: top,
      maxWidth: width,
    );
  }

  /// 从计算样式生成绘制/测量用 TextStyle。
  static TextStyle textStyleFor(
    ComputedStyle style, {
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
  }) => TextStyle(
    fontSize: style.fontSize,
    height: style.lineHeightFactor,
    leadingDistribution: leadingDistribution,
    fontWeight: _fontWeight(style.fontWeight),
    fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
    fontFamily: style.fontFamily,
    color: style.color,
  );

  static FontWeight _fontWeight(int weight) {
    final index = ((weight / 100).round() - 1).clamp(0, 8);
    return FontWeight.values[index];
  }

  static TextAlign _textAlign(CssTextAlign align) => switch (align) {
    CssTextAlign.left || CssTextAlign.start => TextAlign.left,
    CssTextAlign.right || CssTextAlign.end => TextAlign.right,
    CssTextAlign.center => TextAlign.center,
    CssTextAlign.justify => TextAlign.justify,
  };
}
