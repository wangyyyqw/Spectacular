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

/// 正文过窄告警。
class LineBreakWarning {
  /// 创建告警。
  const LineBreakWarning({
    required this.requestedWidth,
    required this.appliedWidth,
    required this.minimumWidth,
  });

  /// 告警码，固定为 `layout.tooNarrow`。
  String get code => 'layout.tooNarrow';

  /// 调用方请求的宽度。
  final double requestedWidth;

  /// 实际使用的宽度。
  final double appliedWidth;

  /// 3em 下限。
  final double minimumWidth;

  @override
  String toString() =>
      '$code(requested=$requestedWidth, applied=$appliedWidth, min=$minimumWidth)';
}

/// 断行告警回调。
typedef LineBreakWarningCallback = void Function(LineBreakWarning warning);

/// 基于 [TextPainter] 的断行器。
///
/// 正文内容宽低于 [minimumWidthEm]（默认 3em）时钳制到下限，并只触发一次告警；
/// 这是 S4 结论要求的工程约束，避免 2em 极端宽度下的禁则缺陷。
class LineBreaker {
  /// 创建断行器。
  LineBreaker({this.onWarning, this.minimumWidthEm = 3.0})
    : assert(minimumWidthEm > 0);

  /// 告警回调，只在首次钳制时调用。
  final LineBreakWarningCallback? onWarning;

  /// 宽度下限，单位为 em。
  final double minimumWidthEm;

  bool _tooNarrow = false;
  int _warningCount = 0;
  LineBreakWarning? _lastWarning;

  /// 是否发生过宽度钳制。
  bool get tooNarrow => _tooNarrow;

  /// 告警次数；一次断行器实例最多为 1。
  int get warningCount => _warningCount;

  /// 最近一次告警。
  LineBreakWarning? get lastWarning => _lastWarning;

  /// 按样式计算 3em 下限。
  double minimumWidthFor(ComputedStyle style) =>
      style.fontSize * minimumWidthEm;

  /// 返回实际使用的宽度；低于下限时钳制并记录一次告警。
  double effectiveWidth(ComputedStyle style, double requestedWidth) {
    final minimum = minimumWidthFor(style);
    if (!requestedWidth.isFinite || requestedWidth >= minimum) {
      return requestedWidth;
    }
    _tooNarrow = true;
    if (_warningCount == 0) {
      final warning = LineBreakWarning(
        requestedWidth: requestedWidth,
        appliedWidth: minimum,
        minimumWidth: minimum,
      );
      _warningCount = 1;
      _lastWarning = warning;
      onWarning?.call(warning);
    }
    return minimum;
  }

  /// 按 [maxWidth] 测量 [text]。
  ///
  /// 宽度低于 3em 时钳制到 3em；无限宽保持单行断行。
  TextLayoutResult layout({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    double textScaleFactor = 1,
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
  }) {
    final width = effectiveWidth(style, maxWidth);
    return TextLayoutEngine._layoutRaw(
      text: text,
      style: style,
      maxWidth: width,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
    );
  }
}

/// 用 TextPainter 做行测量。
abstract final class TextLayoutEngine {
  /// 按 [maxWidth] 测量 [text]。
  ///
  /// [style] 提供 fontSize/lineHeightFactor/fontFamily/字重/斜体/颜色/对齐；
  /// 行高使用 CSS 语义（`fontSize × factor`），并显式设置 even 行距分布。
  ///
  /// 默认使用 [LineBreaker] 执行 3em 宽度下限；需要观察告警时传入自定义
  /// [lineBreaker]。
  static TextLayoutResult layout({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    double textScaleFactor = 1,
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
    LineBreaker? lineBreaker,
  }) {
    return (lineBreaker ?? LineBreaker()).layout(
      text: text,
      style: style,
      maxWidth: maxWidth,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
    );
  }

  static TextLayoutResult _layoutRaw({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
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
