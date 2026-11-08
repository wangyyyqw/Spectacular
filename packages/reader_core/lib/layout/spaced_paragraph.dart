import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import 'punct_trim.dart';
import 'punctuation_spacing.dart';
import 'text_spacing.dart';

class SpacedLine {
  const SpacedLine(this.start, this.end, this.metrics, this.spacing);

  final int start;
  final int end;
  final LineMetrics metrics;
  final LineSpacing spacing;
}

/// 按字符位置提取每一行的原文区间。
///
/// 混排字号和书内自定义字体可能让 [TextPainter.computeLineMetrics] 的行高
/// 与实际命中区域不一致；此时用行框纵向中点查找边界会把相邻行映射成同一
/// 区间。逐行从上一行末尾继续查询，既能正确处理软换行，也能跳过硬换行，
/// 与绘制端使用的原文坐标保持一致。
List<TextRange> textLineRanges(
  TextPainter painter,
  String text,
  int lineCount,
) {
  if (lineCount <= 0) {
    return const <TextRange>[];
  }
  final ranges = <TextRange>[];
  var cursor = 0;
  while (ranges.length < lineCount) {
    final boundary = painter.getLineBoundary(TextPosition(offset: cursor));
    ranges.add(boundary);
    var next = boundary.end;
    if (next < text.length && text.codeUnitAt(next) == 10) {
      next += 1;
    } else if (next <= cursor) {
      next = cursor + 1;
    }
    cursor = next.clamp(0, text.length);
    if (cursor == text.length && ranges.length < lineCount) {
      ranges.addAll(
        List<TextRange>.filled(
          lineCount - ranges.length,
          TextRange.collapsed(text.length),
        ),
      );
    }
  }
  return ranges;
}

/// 仍由平台决定合法断点；只试探字体可回收的行尾空白，不自行拆词。
class SpacedParagraph {
  SpacedParagraph({
    required this.text,
    required this.span,
    required this.spacing,
    required this.width,
    required this.scale,
    this.firstLine = true,
    this.maxLines,
  });

  final String text;
  final TextSpan span;
  final PunctuationSpacing spacing;
  final double width;
  final double scale;
  final bool firstLine;
  final int? maxLines;
  final _measurements = <(int, int, bool), _LineMeasurement>{};
  final _paragraphStyles = <TextStyle, ui.ParagraphStyle>{};
  final _uiTextStyles = <TextStyle, ui.TextStyle>{};
  TextStyle? _lastParagraphBase;
  ui.ParagraphStyle? _lastParagraphStyle;
  TextStyle? _lastUiBase;
  ui.TextStyle? _lastUiStyle;
  late final TextScaler _scaler = TextScaler.linear(scale);

  ui.ParagraphStyle _paragraphStyle(TextStyle style) {
    final cached = _lastParagraphStyle;
    if (cached != null && identical(style, _lastParagraphBase)) {
      return cached;
    }
    final resolved = _paragraphStyles.putIfAbsent(
      style,
      () => style.getParagraphStyle(
        textAlign: TextAlign.start,
        textDirection: TextDirection.ltr,
        textScaler: _scaler,
      ),
    );
    _lastParagraphBase = style;
    _lastParagraphStyle = resolved;
    return resolved;
  }

  ui.TextStyle _uiTextStyle(TextStyle style) {
    final cached = _lastUiStyle;
    if (cached != null && identical(style, _lastUiBase)) return cached;
    final resolved = _uiTextStyles.putIfAbsent(
      style,
      () => style.getTextStyle(textScaler: _scaler),
    );
    _lastUiBase = style;
    _lastUiStyle = resolved;
    return resolved;
  }

  TextPainter _painter(
    TextSpan text, [
    double width = double.infinity,
    int? maxLines,
  ]) => TextPainter(
    text: text,
    textDirection: TextDirection.ltr,
    textScaler: _scaler,
    maxLines: maxLines,
  )..layout(maxWidth: width);

  List<SpacedLine>? layout(TextPainter painter) => lineSteps(painter)?.toList();

  /// 与同步入口共用逐行算法；检查点可让出执行或抛出取消异常。
  Future<List<SpacedLine>?> layoutAsync(
    TextPainter painter, {
    Future<void> Function()? checkpoint,
  }) async {
    if (checkpoint != null) await checkpoint();
    final steps = lineSteps(painter);
    if (steps == null) return null;
    final result = <SpacedLine>[];
    for (final line in steps) {
      result.add(line);
      if (checkpoint != null) await checkpoint();
    }
    return result;
  }

  /// 每次迭代只完成一行，不把整段行重排封装成不可中断的同步调用。
  Iterable<SpacedLine>? lineSteps(TextPainter painter) {
    final edges = spacing.hasEdgeAdjustments;
    if (!edges && !spacing.hasAdjustments) return null;
    final measured = _lines(painter);
    if (!edges) {
      final lines = [
        for (final line in measured)
          SpacedLine(
            line.start,
            line.end,
            line.metrics,
            spacing.range(line.start, line.end),
          ),
      ];
      if (!_crossesLine(lines)) return lines;
    }
    return _layoutLines(measured, painter);
  }

  List<({int start, int end, LineMetrics metrics})> _lines(
    TextPainter painter,
  ) {
    final metrics = painter.computeLineMetrics();
    final ranges = textLineRanges(painter, text, metrics.length);
    final lines = <({int start, int end, LineMetrics metrics})>[];
    for (var i = 0; i < metrics.length; i++) {
      final range = ranges[i];
      lines.add((start: range.start, end: range.end, metrics: metrics[i]));
    }
    return lines;
  }

  bool _crossesLine(List<SpacedLine> lines) {
    final full = spacing.range(0, text.length, trimTrailing: false);
    for (final line in lines) {
      for (final entry in full.glyphs.entries) {
        if (entry.key >= line.start &&
            entry.key < line.end &&
            !line.spacing.glyphs.containsKey(entry.key - line.start)) {
          return true;
        }
      }
    }
    return false;
  }

  Iterable<SpacedLine> _layoutLines(
    List<({int start, int end, LineMetrics metrics})> measured,
    TextPainter baseline,
  ) sync* {
    var start = 0;
    var lineCount = 0;
    final extra = spacing.maxEndReduction * scale;
    while (start < text.length) {
      final first = start == 0 ? firstLine : text[start - 1] == '\n';
      final index = _baselineIndex(start, measured);
      final baseLine = measured[index];
      final limit = index + 2 < measured.length
          ? measured[index + 2].end
          : text.length;
      // 行首截断会改变英文等字形的塑形上下文，整段 metrics 不能替代行测量。
      final line =
          _unchangedLine(start, baseLine, extra) ??
          _nextLine(start, extra, first, limit, baseline);
      yield line;
      if (++lineCount == maxLines) break;
      // 平台给出的空行不消耗正文，只越过它对应的硬换行。
      var next = line.end;
      if (next < text.length && text[next] == '\n') next++;
      if (next <= start) {
        next = start + text.substring(start).characters.first.length;
      }
      start = next;
    }
  }

  /// 平台基线行已排满时，行边最大挤压也不足以再收一个全角字；此时基线
  /// 断点可靠，只需精确测量本行，跳过逐行探针与单行重排。基线行仍可能
  /// 因挤压多收一字，此时最多向前补三个全角字；其余情况回退到逐行探针，
  /// 保持英文塑形上下文与禁则语义不变。
  SpacedLine? _unchangedLine(
    int start,
    ({int start, int end, LineMetrics metrics}) baselineLine,
    double extra,
  ) {
    if (baselineLine.start != start || baselineLine.end <= start) return null;
    final hardBreak = text.indexOf('\n', start);
    final maxEnd = hardBreak < 0 ? text.length : hardBreak;
    if (maxEnd <= start ||
        text[maxEnd - 1] == ' ' ||
        text[maxEnd - 1] == '\t') {
      return null;
    }
    var end = baselineLine.end;
    if (end > maxEnd) end = maxEnd;
    if (end >= maxEnd) {
      final line = measure(start, end);
      return line.metrics.width <= width + 0.01 ? line : null;
    }
    if (!_isCjk(text.codeUnitAt(end))) return null;
    final fontSize = spacing.styleAt(end).text.fontSize ?? 0;
    final baselineAdvance = (spacing.canTrimEnd(end) ? 0.45 : 0.9) * fontSize;
    final baselineExtra = end > start && spacing.canTrimEnd(end - 1)
        ? extra
        : 0.0;
    if (baselineLine.metrics.width + baselineAdvance - baselineExtra >
        width + 0.01) {
      final line = measure(start, end);
      // 行首压缩会释放额外宽度，基线宽度不足以证明断点，交回逐行探针。
      return line.metrics.width <= width + 0.01 && line.spacing.startTrim == 0
          ? line
          : null;
    }
    // 基线断点后仍可能容纳一字；逐字精确测量，最多补三字。
    for (var attempt = 0; attempt < 3; attempt++) {
      final line = measure(start, end);
      if (line.metrics.width > width + 0.01) return null;
      if (end > start && punctOpeningSet.contains(text[end - 1])) {
        return null;
      }
      if (end >= maxEnd) return line;
      final next = text.codeUnitAt(end);
      if (!_isCjk(next)) return null;
      final size = spacing.styleAt(end).text.fontSize ?? 0;
      final advance = (spacing.canTrimEnd(end) ? 0.45 : 0.9) * size;
      final availableExtra = end > start && spacing.canTrimEnd(end - 1)
          ? extra
          : 0.0;
      if (line.metrics.width + advance - availableExtra > width + 0.01) {
        // 断在行首禁则标点前会生成非法行首，必须交回逐行探针。
        return punctLineStartProhibitedSet.contains(text[end]) ? null : line;
      }
      end += text.substring(end).characters.first.length;
    }
    return null;
  }

  bool _isCjk(int unit) =>
      (unit >= 0x2E80 && unit <= 0x9FFF) ||
      (unit >= 0xAC00 && unit <= 0xD7AF) ||
      (unit >= 0xF900 && unit <= 0xFAFF) ||
      (unit >= 0xFF00 && unit <= 0xFFEF);

  // 只探测基线断行附近三行；避免长段落逐行重排整个余文造成平方级开销。
  int _baselineIndex(
    int start,
    List<({int start, int end, LineMetrics metrics})> lines,
  ) {
    var low = 0;
    var high = lines.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].end <= start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  SpacedLine _nextLine(
    int start,
    double extra,
    bool first,
    int limit,
    TextPainter baseline,
  ) {
    final probe = _lineProbe(start, first, limit, baseline);
    try {
      return _fitLine(probe, start, extra);
    } finally {
      if (identical(probe.painter, baseline)) {
        // 候选宽度只重排同一原生段落；调用方后续查询仍使用原始约束。
        baseline.layout(maxWidth: width);
      } else {
        probe.painter.dispose();
      }
    }
  }

  ({TextPainter painter, int end}) _lineProbe(
    int start,
    bool first,
    int limit,
    TextPainter baseline,
  ) {
    final source = _span(start, limit, first);
    // 缩进只测首行时，整段已按相同文本、样式与 maxLines 塑形，无需再建一份。
    final probe = baseline.maxLines == 1 && baseline.text == source
        ? baseline
        : _painter(source, width, 1);
    var end = probe.getLineBoundary(const TextPosition(offset: 0)).end + start;
    while (end == limit && limit < text.length) {
      limit = (limit + (limit - start) + 1).clamp(0, text.length);
      probe.text = _span(start, limit, first);
      end = _firstEnd(probe, width) + start;
    }
    return (painter: probe, end: end);
  }

  SpacedLine _fitLine(
    ({TextPainter painter, int end}) probe,
    int start,
    double extra,
  ) {
    var end = probe.end;
    final extended = _extendEnd(probe.painter, start, end, extra);
    if (extended != null) return extended;
    var line = measure(start, end);
    // 相邻标点跨行时需要还原被借走的空白；向前找平台认可的断点。
    while (line.metrics.width > width + 0.01 && end > start) {
      final next =
          _firstEnd(
            probe.painter,
            (width - (line.metrics.width - width) - 0.01).clamp(0.01, width),
          ) +
          start;
      if (next >= end || next <= start) break;
      end = next;
      line = measure(start, end);
    }
    return line;
  }

  SpacedLine? _extendEnd(TextPainter probe, int start, int end, double extra) {
    if (extra <= 0 ||
        !width.isFinite ||
        end >= text.length ||
        text[end] == '\n') {
      return null;
    }
    final widerEnd = _firstEnd(probe, width + extra) + start;
    for (var candidate = widerEnd; candidate > end; candidate--) {
      if (!spacing.canTrimEnd(candidate - 1)) continue;
      final line = measure(start, candidate);
      if (line.metrics.width <= width + 0.01 &&
          _legalBoundary(probe, start, candidate)) {
        return line;
      }
    }
    return null;
  }

  int _firstEnd(TextPainter probe, double width) {
    // 同一段落仅改约束即可复用字形塑形；候选宽度不再反复创建原生段落。
    probe.layout(maxWidth: width);
    return probe.getLineBoundary(const TextPosition(offset: 0)).end;
  }

  bool _legalBoundary(TextPainter probe, int start, int end) {
    final source = sliceTextSpan(probe.text! as TextSpan, 0, end - start);
    final measured = _measurements[(start, end, true)];
    // 只有完整样式树相同才复用自然宽；行边或相邻调整不同仍独立塑形。
    final natural = measured?.span == source
        ? measured!.naturalWidth
        : _naturalWidth(source);
    return _firstEnd(probe, natural + 0.01) == end - start;
  }

  double _naturalWidth(TextSpan source) {
    final painter = _painter(source);
    try {
      return painter.width;
    } finally {
      painter.dispose();
    }
  }

  SpacedLine measure(int start, int end, {bool trimEnd = true}) {
    final key = (start, end, trimEnd);
    final cached = _measurements[key];
    if (cached != null) return cached.line;
    final line = _measureLine(start, end, trimEnd);
    if (_measurements.length >= 256) {
      _measurements.remove(_measurements.keys.first);
    }
    _measurements[key] = line;
    return line.line;
  }

  LineSpacing _lineSpacing(int start, int end, {bool trimEnd = true}) {
    final first = start == 0 ? firstLine : text[start - 1] == '\n';
    return spacing.range(
      start,
      end,
      edges: (firstLine: first, trimEnd: trimEnd),
    );
  }

  _LineMeasurement _measureLine(int start, int end, bool trimEnd) {
    final plan = _lineSpacing(start, end, trimEnd: trimEnd);
    // 空硬换行仍需携带原字号的 strut；空省略号前缀也不能取空 metrics。
    final source = start == end
        ? TextSpan(text: '\u200b', style: spacing.styleAt(start).text)
        : sliceTextSpan(span, start, end);
    final lineSpan = applyTextSpacing(source, plan);
    final baseStyle = lineSpan.style ?? const TextStyle();
    final builder = ui.ParagraphBuilder(_paragraphStyle(baseStyle));
    final flatText = lineSpan.children == null ? lineSpan.text : null;
    if (flatText != null && lineSpan.style != null) {
      builder.pushStyle(_uiTextStyle(baseStyle));
      builder.addText(flatText);
      builder.pop();
    } else {
      lineSpan.build(builder, textScaler: _scaler);
    }
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    try {
      // 单行原生接口保留相同行度量，避免整表接口转换每个 run 的样式。
      return _LineMeasurement(
        SpacedLine(start, end, paragraph.getLineMetricsAt(0)!, plan),
        lineSpan,
        paragraph.maxIntrinsicWidth,
      );
    } finally {
      paragraph.dispose();
    }
  }

  TextSpan _span(int start, int end, bool first) {
    final plan = spacing.range(
      start,
      end,
      edges: (firstLine: first, trimEnd: false),
      trimTrailing: false,
    );
    return applyTextSpacing(sliceTextSpan(span, start, end), plan);
  }
}

class _LineMeasurement {
  const _LineMeasurement(this.line, this.span, this.naturalWidth);

  final SpacedLine line;
  final TextSpan span;
  final double naturalWidth;
}
