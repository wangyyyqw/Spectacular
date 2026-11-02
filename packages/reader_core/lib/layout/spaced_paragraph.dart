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

  TextPainter _painter(
    TextSpan text, [
    double width = double.infinity,
    int? maxLines,
  ]) => TextPainter(
    text: text,
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
    maxLines: maxLines,
  )..layout(maxWidth: width);

  List<SpacedLine>? layout(TextPainter painter) {
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
    return _layoutLines(measured);
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

  List<SpacedLine> _layoutLines(
    List<({int start, int end, LineMetrics metrics})> measured,
  ) {
    final lines = <SpacedLine>[];
    var start = 0;
    final extra = spacing.maxEndReduction * scale;
    while (start < text.length) {
      final first = start == 0 ? firstLine : text[start - 1] == '\n';
      final line = _nextLine(start, extra, first, _windowEnd(start, measured));
      lines.add(line);
      if (lines.length == maxLines) break;
      // 平台给出的空行不消耗正文，只越过它对应的硬换行。
      var next = line.end;
      if (next < text.length && text[next] == '\n') next++;
      if (next <= start) {
        next = start + text.substring(start).characters.first.length;
      }
      start = next;
    }
    return lines;
  }

  // 只探测基线断行附近三行；避免长段落逐行重排整个余文造成平方级开销。
  int _windowEnd(
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
    return low + 2 < lines.length ? lines[low + 2].end : text.length;
  }

  SpacedLine _nextLine(int start, double extra, bool first, int limit) {
    final probe = _lineProbe(start, first, limit);
    try {
      return _fitLine(probe, start, extra);
    } finally {
      probe.painter.dispose();
    }
  }

  ({TextPainter painter, int end}) _lineProbe(
    int start,
    bool first,
    int limit,
  ) {
    final probe = _painter(_span(start, limit, first), width, 1);
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
      if (!punctClosingSet.contains(text[candidate - 1])) continue;
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
    final prefix = _painter(
      sliceTextSpan(probe.text! as TextSpan, 0, end - start),
    );
    final natural = prefix.width;
    prefix.dispose();
    return _firstEnd(probe, natural + 0.01) == end - start;
  }

  SpacedLine measure(int start, int end, {bool trimEnd = true}) {
    final first = start == 0 ? firstLine : text[start - 1] == '\n';
    final plan = spacing.range(
      start,
      end,
      edges: (firstLine: first, trimEnd: trimEnd),
    );
    // 空硬换行仍需携带原字号的 strut；空省略号前缀也不能取空 metrics。
    final source = start == end
        ? TextSpan(text: '\u200b', style: spacing.styleAt(start).text)
        : sliceTextSpan(span, start, end);
    final lineSpan = applyTextSpacing(source, plan);
    final painter = _painter(lineSpan);
    final metric = painter.computeLineMetrics().first;
    painter.dispose();
    return SpacedLine(start, end, metric, plan);
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
