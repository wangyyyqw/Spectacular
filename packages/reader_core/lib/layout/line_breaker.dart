import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../src/api/models.dart' show TextLayout;
import '../text/justify.dart';

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
    this.indent = 0,
    this.isLastLine = false,
    this.isHardBreak = false,
    this.offsetX = 0,
    this.justifyExtra = 0,
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

  /// 首行缩进（仅首行非 0）。
  final double indent;

  /// 是否为段落最后一行。
  final bool isLastLine;

  /// 是否以硬换行结束。
  final bool isHardBreak;

  /// 行在内容区内的水平偏移，由 text-align 计算（§61.5）。
  final double offsetX;

  /// justify 需要分摊到行内的额外宽度；末行与硬换行行为 0。
  final double justifyExtra;

  /// 行底。
  double get bottom => top + height;

  /// 复制并更新标志。
  LineBox copyWith({
    int? start,
    int? end,
    double? top,
    double? indent,
    bool? isLastLine,
    bool? isHardBreak,
    double? offsetX,
    double? justifyExtra,
  }) => LineBox(
    start: start ?? this.start,
    end: end ?? this.end,
    top: top ?? this.top,
    height: height,
    baseline: baseline,
    width: width,
    indent: indent ?? this.indent,
    isLastLine: isLastLine ?? this.isLastLine,
    isHardBreak: isHardBreak ?? this.isHardBreak,
    offsetX: offsetX ?? this.offsetX,
    justifyExtra: justifyExtra ?? this.justifyExtra,
  );

  @override
  String toString() =>
      'LineBox($start..$end, top=$top, h=$height, baseline=$baseline, w=$width, '
      'indent=$indent, last=$isLastLine, hard=$isHardBreak, x=$offsetX, '
      'justify=$justifyExtra)';
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
    final indent = width.isFinite
        ? style.textIndent.clamp(0.0, math.max(0.0, width - 1)).toDouble()
        : 0.0;
    final measured = text.isEmpty || indent <= 0
        ? _measureSegment(
            text: text,
            width: width,
            style: style,
            textScaleFactor: textScaleFactor,
            leadingDistribution: leadingDistribution,
          )
        : _measureWithIndent(
            text: text,
            width: width,
            indent: indent,
            style: style,
            textScaleFactor: textScaleFactor,
            leadingDistribution: leadingDistribution,
          );
    return _result(text, _align(text, measured, style.textAlign, width), width);
  }

  /// 首行减宽断行，尾段用完整宽度重排后合并（§61.2）。
  static List<LineBox> _measureWithIndent({
    required String text,
    required double width,
    required double indent,
    required ComputedStyle style,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
  }) {
    final firstWidth = math.max(1.0, width - indent);
    final head = _measureSegment(
      text: text,
      width: firstWidth,
      style: style,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
    );
    if (head.isEmpty) {
      return const <LineBox>[];
    }
    final first = head.first.copyWith(indent: indent);
    var remainderStart = first.end;
    if (remainderStart < text.length && text.codeUnitAt(remainderStart) == 10) {
      remainderStart += 1;
    }
    final remainder = text.substring(remainderStart);
    final rest = _measureSegment(
      text: remainder,
      width: width,
      style: style,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
    );
    final lines = <LineBox>[first];
    for (var i = 0; i < rest.length; i++) {
      final line = rest[i];
      lines.add(
        line.copyWith(
          start: line.start + remainderStart,
          end: line.end + remainderStart,
          top: first.height + line.top,
          isLastLine: i == rest.length - 1,
        ),
      );
    }
    lines[0] = lines[0].copyWith(isLastLine: rest.isEmpty);
    return lines;
  }

  /// 按 text-align 计算每行水平偏移与 justify 分摊宽度（§61.5）。
  ///
  /// 行宽已含 text-indent 造成的减宽，比较基准是 `width - indent`；
  /// justify 的末行与硬换行行按 start 对齐，不拉伸。
  static List<LineBox> _align(
    String text,
    List<LineBox> lines,
    CssTextAlign align,
    double width,
  ) {
    final aligned = <LineBox>[];
    for (final line in lines) {
      final slack = width.isFinite
          ? math.max(0.0, width - line.indent - line.width)
          : 0.0;
      aligned.add(switch (align) {
        CssTextAlign.start ||
        CssTextAlign.left => line.copyWith(offsetX: line.indent),
        CssTextAlign.end ||
        CssTextAlign.right => line.copyWith(offsetX: line.indent + slack),
        CssTextAlign.center => line.copyWith(offsetX: line.indent + slack / 2),
        CssTextAlign.justify => line.copyWith(
          offsetX: line.indent,
          justifyExtra: _justifyExtra(text, line, slack),
        ),
      });
    }
    return aligned;
  }

  /// 该行可用于 justify 的余量；没有可拉伸间隙时返回 0。
  static double _justifyExtra(String text, LineBox line, double slack) {
    if (slack <= 0 || line.isLastLine || line.isHardBreak) {
      return 0;
    }
    final lineText = text.substring(line.start, line.end);
    return justifyGapOffsets(lineText).isEmpty ? 0 : slack;
  }

  static List<LineBox> _measureSegment({
    required String text,
    required double width,
    required ComputedStyle style,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyleFor(style, leadingDistribution: leadingDistribution),
      ),
      textDirection: TextDirection.ltr,
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
          width: math.max(0, metric.width).toDouble(),
        ),
      );
      top += metric.height;
    }
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final hardBreak =
          line.end < text.length && text.codeUnitAt(line.end) == 10;
      lines[i] = line.copyWith(
        isLastLine: i == lines.length - 1,
        isHardBreak: hardBreak,
      );
    }
    return lines;
  }

  static TextLayoutResult _result(
    String text,
    List<LineBox> lines,
    double maxWidth,
  ) {
    var maxLineWidth = 0.0;
    for (final line in lines) {
      maxLineWidth = math.max(maxLineWidth, line.width);
    }
    final height = lines.isEmpty ? 0.0 : lines.last.bottom;
    return TextLayoutResult(
      text: text,
      lines: List<LineBox>.unmodifiable(lines),
      width: maxLineWidth,
      height: height,
      maxWidth: maxWidth,
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
    letterSpacing: style.letterSpacing,
    color: style.color,
  );

  static FontWeight _fontWeight(int weight) {
    final index = ((weight / 100).round() - 1).clamp(0, 8);
    return FontWeight.values[index];
  }
}
