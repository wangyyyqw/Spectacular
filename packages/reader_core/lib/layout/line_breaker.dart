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

/// 行内样式区间：为文本 `[start, end)` 指定独立计算样式。
///
/// 混排字号、上下标、超出行高的行内元素都用它表达；区间必须升序且不重叠，
/// 未覆盖的部分沿用块的样式。
class StyledRun {
  /// 创建区间。
  const StyledRun({
    required this.start,
    required this.end,
    required this.style,
  });

  /// 起始偏移（UTF-16，含）。
  final int start;

  /// 结束偏移（UTF-16，不含）。
  final int end;

  /// 该区间的计算样式。
  final ComputedStyle style;
}

/// 把 `[start, end)` 按样式区间切成连续 span（§61.1 的行内 run）。
///
/// [runs] 需升序且不重叠；区间外的文本用 [baseStyle]。
List<InlineSpan> buildStyledSpans({
  required String text,
  required int start,
  required int end,
  required List<StyledRun> runs,
  required TextStyle baseStyle,
  required TextStyle Function(ComputedStyle style) styleOf,
}) {
  final spans = <InlineSpan>[];
  var cursor = start;
  for (final run in runs) {
    final runStart = math.max(run.start, start);
    final runEnd = math.min(run.end, end);
    if (runEnd <= cursor || runStart >= end) {
      continue;
    }
    final from = math.max(cursor, runStart);
    if (from > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, from), style: baseStyle));
    }
    if (runEnd > from) {
      spans.add(
        TextSpan(text: text.substring(from, runEnd), style: styleOf(run.style)),
      );
      cursor = runEnd;
    }
  }
  if (cursor < end) {
    spans.add(TextSpan(text: text.substring(cursor, end), style: baseStyle));
  }
  return spans;
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
    this.runs = const <StyledRun>[],
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

  /// 行内样式区间（绘制用），偏移基于 [text]。
  final List<StyledRun> runs;

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
  /// [runs] 为行内样式区间，用于混排字号与行内元素；未覆盖部分沿用 [style]。
  TextLayoutResult layout({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    double textScaleFactor = 1,
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
    List<StyledRun> runs = const <StyledRun>[],
  }) {
    final width = effectiveWidth(style, maxWidth);
    return TextLayoutEngine._layoutRaw(
      text: text,
      style: style,
      maxWidth: width,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
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
    List<StyledRun> runs = const <StyledRun>[],
  }) {
    return (lineBreaker ?? LineBreaker()).layout(
      text: text,
      style: style,
      maxWidth: maxWidth,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
    );
  }

  static TextLayoutResult _layoutRaw({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    List<StyledRun> runs = const <StyledRun>[],
  }) {
    final width = maxWidth.isFinite ? math.max(1.0, maxWidth) : double.infinity;
    final indent = width.isFinite
        ? style.textIndent.clamp(0.0, math.max(0.0, width - 1)).toDouble()
        : 0.0;
    final ordered = _normalizeRuns(runs, text.length);
    // 段尾换行不产生空行（与阅微一致：content 末尾的 '\n' 先剥离）。
    var measuredEnd = text.length;
    while (measuredEnd > 0 && text.codeUnitAt(measuredEnd - 1) == 10) {
      measuredEnd -= 1;
    }
    final measuredText = measuredEnd == text.length
        ? text
        : text.substring(0, measuredEnd);
    final measured = measuredText.isEmpty || indent <= 0
        ? _measureSegment(
            text: measuredText,
            width: width,
            style: style,
            textScaleFactor: textScaleFactor,
            leadingDistribution: leadingDistribution,
            runs: ordered,
          )
        : _measureWithIndent(
            text: measuredText,
            width: width,
            indent: indent,
            style: style,
            textScaleFactor: textScaleFactor,
            leadingDistribution: leadingDistribution,
            runs: ordered,
          );
    return _result(
      text,
      _align(measuredText, measured, style.textAlign, width),
      width,
      ordered,
    );
  }

  /// 排序并裁掉越界区间；空区间丢弃。
  static List<StyledRun> _normalizeRuns(List<StyledRun> runs, int length) {
    if (runs.isEmpty) {
      return const <StyledRun>[];
    }
    final ordered = <StyledRun>[];
    for (final run in runs) {
      final start = run.start.clamp(0, length);
      final end = run.end.clamp(start, length);
      if (end > start) {
        ordered.add(StyledRun(start: start, end: end, style: run.style));
      }
    }
    ordered.sort((a, b) => a.start.compareTo(b.start));
    return ordered;
  }

  /// 取 `[start, end)` 范围内的样式区间，偏移改为相对起点。
  static List<StyledRun> _sliceRuns(List<StyledRun> runs, int start, int end) {
    final sliced = <StyledRun>[];
    for (final run in runs) {
      final runStart = math.max(run.start, start);
      final runEnd = math.min(run.end, end);
      if (runEnd > runStart) {
        sliced.add(
          StyledRun(
            start: runStart - start,
            end: runEnd - start,
            style: run.style,
          ),
        );
      }
    }
    return sliced;
  }

  /// 首行减宽断行，尾段用完整宽度重排后合并（§61.2）。
  static List<LineBox> _measureWithIndent({
    required String text,
    required double width,
    required double indent,
    required ComputedStyle style,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    List<StyledRun> runs = const <StyledRun>[],
  }) {
    final firstWidth = math.max(1.0, width - indent);
    final head = _measureSegment(
      text: text,
      width: firstWidth,
      style: style,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
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
      runs: _sliceRuns(runs, remainderStart, text.length),
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
    List<StyledRun> runs = const <StyledRun>[],
  }) {
    final baseStyle = textStyleFor(
      style,
      leadingDistribution: leadingDistribution,
    );
    final painter = TextPainter(
      text: runs.isEmpty
          ? TextSpan(text: text, style: baseStyle)
          : TextSpan(
              style: baseStyle,
              children: buildStyledSpans(
                text: text,
                start: 0,
                end: text.length,
                runs: runs,
                baseStyle: baseStyle,
                styleOf: (runStyle) => textStyleFor(
                  runStyle,
                  leadingDistribution: leadingDistribution,
                ),
              ),
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
    List<StyledRun> runs,
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
      runs: List<StyledRun>.unmodifiable(runs),
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
