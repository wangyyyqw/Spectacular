import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';

/// CFI 半开区间在一行中的原文片段。
class ReaderRangeLine {
  /// 创建行片段。
  const ReaderRangeLine({
    required this.line,
    required this.start,
    required this.end,
  });

  /// 行几何。
  final PageLineBox line;

  /// 行内 UTF-16 起止偏移。
  final int start;
  final int end;

  /// 字形矩形，保留实际字体与行距，不改变文字度量。
  List<Rect> get rects => [
    for (final rect in TextHitTester.selectionRects(line, start, end))
      rect.shift(line.rect.topLeft),
  ];
}

/// 标注、手工装饰与规则共用的原文区间映射。
abstract final class ReaderTextRangeGeometry {
  /// 映射到当前页的可见行；非法、倒置和空区间不产生几何。
  static List<ReaderRangeLine> linesFor(
    PageContent page, {
    required String startCfi,
    required String endCfi,
    PageBlockSlice? slice,
  }) {
    final start = EpubCfi.parse(startCfi);
    final end = EpubCfi.parse(endCfi);
    if (start == null || end == null || start.compareTo(end) >= 0) {
      return const [];
    }
    final result = <ReaderRangeLine>[];
    for (final box in TextHitTester.lineBoxes(page)) {
      if (slice != null && !identical(slice, box.slice)) continue;
      final range = _inLine(box, start, end);
      if (range != null) result.add(range);
    }
    return result;
  }

  static ReaderRangeLine? _inLine(PageLineBox box, EpubCfi start, EpubCfi end) {
    final raw = box.slice.block.startCfi;
    final block = raw == null ? null : EpubCfi.parse(raw);
    if (block == null) return null;
    final base = block.withCharOffset(0);
    if (base.compareTo(start.withCharOffset(0)) < 0 ||
        base.compareTo(end.withCharOffset(0)) > 0) {
      return null;
    }
    final from = base.compareTo(start.withCharOffset(0)) == 0
        ? (start.charOffset ?? 0) - (block.charOffset ?? 0)
        : 0;
    final to = base.compareTo(end.withCharOffset(0)) == 0
        ? (end.charOffset ?? 0) - (block.charOffset ?? 0)
        : box.slice.block.layout.text.length;
    final lineStart = box.blockTextOffset;
    final overlapStart = math.max(from, lineStart);
    final overlapEnd = math.min(to, lineStart + box.text.length);
    return overlapStart >= overlapEnd
        ? null
        : ReaderRangeLine(
            line: box,
            start: overlapStart - lineStart,
            end: overlapEnd - lineStart,
          );
  }
}
