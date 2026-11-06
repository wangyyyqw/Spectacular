import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';

import '../selection/text_range_geometry.dart';
import 'decoration.dart';

/// 渲染期装饰区间，既可来自规则，也可来自手工存储。
class ReaderDecorationRange {
  /// 创建区间，列表顺序就是逐属性覆盖顺序。
  const ReaderDecorationRange({
    required this.startCfi,
    required this.endCfi,
    required this.style,
  });

  /// 原文的半开区间。
  final String startCfi;
  final String endCfi;

  /// 绘制及文字样式。
  final ReaderDecorationStyle style;
}

/// 一行内合并后的装饰盒。
class ReaderDecorationBox {
  /// 创建盒。
  const ReaderDecorationBox({required this.range, required this.style});

  /// 原文行片段。
  final ReaderRangeLine range;

  /// 已按后者覆盖前者合并的属性。
  final ReaderDecorationStyle style;

  /// 绘制内边距不参与断行，垂直扩展不得越过行距余量或 8dp。
  List<Rect> get rects => [
    for (final rect in range.rects)
      Rect.fromLTRB(
        rect.left - style.paddingLeft,
        rect.top -
            math.min(
              style.paddingTop,
              math.min(8, math.max(0, rect.top - range.line.rect.top)),
            ),
        rect.right + style.paddingRight,
        rect.bottom +
            math.min(
              style.paddingBottom,
              math.min(8, math.max(0, range.line.rect.bottom - rect.bottom)),
            ),
      ),
  ];
}

/// 装饰按原文区间分段合并，每一行独立闭合。
abstract final class ReaderDecorationGeometry {
  /// 将重叠规则和手工装饰切分为互不重叠的逐行盒。
  static List<ReaderDecorationBox> boxesFor(
    PageContent page,
    List<ReaderDecorationRange> decorations, {
    PageBlockSlice? slice,
  }) {
    final ranges = <(ReaderRangeLine, ReaderDecorationStyle)>[];
    for (final decoration in decorations) {
      for (final range in ReaderTextRangeGeometry.linesFor(
        page,
        startCfi: decoration.startCfi,
        endCfi: decoration.endCfi,
        slice: slice,
      )) {
        ranges.add((range, decoration.style));
      }
    }
    final result = <ReaderDecorationBox>[];
    for (final line in TextHitTester.lineBoxes(page)) {
      if (slice != null && !identical(slice, line.slice)) continue;
      final matches = ranges
          .where(
            (item) =>
                identical(item.$1.line.slice, line.slice) &&
                item.$1.line.lineIndex == line.lineIndex,
          )
          .toList();
      result.addAll(_splitLine(line, matches));
    }
    return result;
  }

  static List<ReaderDecorationBox> _splitLine(
    PageLineBox line,
    List<(ReaderRangeLine, ReaderDecorationStyle)> matches,
  ) {
    final boundaries = <int>{};
    for (final item in matches) {
      boundaries
        ..add(item.$1.start)
        ..add(item.$1.end);
    }
    final ordered = boundaries.toList()..sort();
    final result = <ReaderDecorationBox>[];
    for (var index = 0; index < ordered.length - 1; index++) {
      final start = ordered[index];
      final end = ordered[index + 1];
      ReaderDecorationStyle? style;
      for (final match in matches) {
        if (match.$1.start <= start && match.$1.end >= end) {
          style = style == null ? match.$2 : style.merge(match.$2);
        }
      }
      if (style == null) continue;
      result.add(
        ReaderDecorationBox(
          range: ReaderRangeLine(line: line, start: start, end: end),
          style: style,
        ),
      );
    }
    return result;
  }

  /// 只命中最新创建的手工装饰，规则始终点击穿透。
  static ReaderDecoration? decorationAt(
    PageContent page,
    Offset position,
    List<ReaderDecoration> decorations,
  ) {
    final sorted = List<ReaderDecoration>.of(decorations)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    for (final decoration in sorted.reversed) {
      if (decoration.needsRelocation) continue;
      final boxes = boxesFor(page, [
        ReaderDecorationRange(
          startCfi: decoration.startCfi,
          endCfi: decoration.endCfi,
          style: decoration.style,
        ),
      ]);
      if (boxes.any(
        (box) => box.rects.any((rect) => rect.contains(position)),
      )) {
        return decoration;
      }
    }
    return null;
  }
}
