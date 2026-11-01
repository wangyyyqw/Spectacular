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

/// 仍由平台决定合法断点；只试探字体可回收的行尾空白，不自行拆词。
class SpacedParagraph {
  SpacedParagraph({
    required this.text,
    required this.span,
    required this.spacing,
    required this.width,
    required this.scale,
    this.firstLine = true,
  });

  final String text;
  final TextSpan span;
  final PunctuationSpacing spacing;
  final double width;
  final double scale;
  final bool firstLine;

  TextPainter _painter(TextSpan text, [double width = double.infinity]) =>
      TextPainter(
        text: text,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(scale),
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
    var top = 0.0;
    final lines = <({int start, int end, LineMetrics metrics})>[];
    for (final metrics in painter.computeLineMetrics()) {
      final boundary = painter.getLineBoundary(
        painter.getPositionForOffset(Offset(0, top + metrics.height / 2)),
      );
      lines.add((start: boundary.start, end: boundary.end, metrics: metrics));
      top += metrics.height;
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
    var remaining = _span(start, limit, first);
    var end = _firstEnd(remaining, width) + start;
    while (end == limit && limit < text.length) {
      limit = (limit + (limit - start) + 1).clamp(0, text.length);
      remaining = _span(start, limit, first);
      end = _firstEnd(remaining, width) + start;
    }
    final extended = _extendEnd(remaining, start, end, extra);
    if (extended != null) return extended;
    var line = measure(start, end);
    // 相邻标点跨行时需要还原被借走的空白；向前找平台认可的断点。
    while (line.metrics.width > width + 0.01 && end > start) {
      final narrow = _painter(
        remaining,
        (width - (line.metrics.width - width) - 0.01).clamp(0.01, width),
      );
      final next =
          narrow.getLineBoundary(const TextPosition(offset: 0)).end + start;
      narrow.dispose();
      if (next >= end || next <= start) break;
      end = next;
      line = measure(start, end);
    }
    return line;
  }

  SpacedLine? _extendEnd(TextSpan remaining, int start, int end, double extra) {
    if (extra <= 0 ||
        !width.isFinite ||
        end >= text.length ||
        text[end] == '\n') {
      return null;
    }
    final widerEnd = _firstEnd(remaining, width + extra) + start;
    for (var candidate = widerEnd; candidate > end; candidate--) {
      if (!punctClosingSet.contains(text[candidate - 1])) continue;
      final line = measure(start, candidate);
      if (line.metrics.width <= width + 0.01 &&
          _legalBoundary(remaining, start, candidate)) {
        return line;
      }
    }
    return null;
  }

  int _firstEnd(TextSpan span, double width) {
    final painter = _painter(span, width);
    final end = painter.getLineBoundary(const TextPosition(offset: 0)).end;
    painter.dispose();
    return end;
  }

  bool _legalBoundary(TextSpan remaining, int start, int end) {
    final prefix = _painter(sliceTextSpan(remaining, 0, end - start));
    final natural = prefix.width;
    prefix.dispose();
    final probe = _painter(remaining, natural + 0.01);
    final actual = probe.getLineBoundary(const TextPosition(offset: 0)).end;
    probe.dispose();
    return actual == end - start;
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
