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
  const ReaderDecorationBox({
    required this.range,
    required this.style,
    this.highlightSource,
    this.backgroundImageRange,
  });

  /// 原文行片段。
  final ReaderRangeLine range;

  /// 已按后者覆盖前者合并的属性。
  final ReaderDecorationStyle style;

  final ReaderDecorationRange? highlightSource;
  final ReaderRangeLine? backgroundImageRange;

  Rect imageAnchorFor(Rect rect) =>
      backgroundImageRange?.rects
          .where((anchor) => anchor.overlaps(rect))
          .firstOrNull ??
      rect;

  Rect imageClipFor(Rect rect, Size pageSize) {
    final source = backgroundImageRange;
    final line = range.line;
    final clipStart = source != null && range.start > source.start;
    final clipEnd = source != null && range.end < source.end;
    return line.isVertical
        ? Rect.fromLTRB(
            line.rect.left,
            clipStart ? rect.top : 0,
            line.rect.right,
            clipEnd ? rect.bottom : pageSize.height,
          )
        : Rect.fromLTRB(
            clipStart ? rect.left : 0,
            line.rect.top,
            clipEnd ? rect.right : pageSize.width,
            line.rect.bottom,
          );
  }

  /// 绘制内边距不参与断行；留白允许越过选择行盒，最多外扩 8dp。
  /// 选择盒包含字体行高，不能把它的边缘当作字形背景的裁切边界。
  List<Rect> get rects => [
    for (final rect in range.rects)
      Rect.fromLTRB(
        rect.left - style.paddingLeft,
        rect.top - math.min(style.paddingTop, 8),
        rect.right + style.paddingRight,
        rect.bottom + math.min(style.paddingBottom, 8),
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
    if (decorations.isEmpty) return const [];
    final ranges = <(ReaderRangeLine, ReaderDecorationRange)>[];
    for (final decoration in decorations) {
      for (final range in ReaderTextRangeGeometry.linesFor(
        page,
        startCfi: decoration.startCfi,
        endCfi: decoration.endCfi,
        slice: slice,
      )) {
        ranges.add((range, decoration));
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
    List<(ReaderRangeLine, ReaderDecorationRange)> matches,
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
      ReaderDecorationRange? highlightSource;
      ReaderRangeLine? backgroundImageRange;
      for (final match in matches) {
        if (match.$1.start <= start && match.$1.end >= end) {
          style = style == null ? match.$2.style : style.merge(match.$2.style);
          if (match.$2.style.highlight != null) highlightSource = match.$2;
          if (match.$2.style.backgroundImagePath != null) {
            backgroundImageRange = match.$1;
          }
        }
      }
      if (style == null) continue;
      result.add(
        ReaderDecorationBox(
          range: ReaderRangeLine(line: line, start: start, end: end),
          style: style,
          highlightSource: highlightSource,
          backgroundImageRange: backgroundImageRange,
        ),
      );
    }
    return result;
  }

  static List<ReaderDecorationBox> highlightBoxesFor(
    List<ReaderDecorationBox> boxes,
  ) {
    final result = <ReaderDecorationBox>[];
    for (final box in boxes) {
      if (box.style.highlight == null) continue;
      final previous = result.lastOrNull;
      if (previous != null &&
          box.highlightSource != null &&
          identical(previous.highlightSource, box.highlightSource) &&
          identical(previous.range.line, box.range.line) &&
          previous.range.end == box.range.start) {
        result[result.length - 1] = ReaderDecorationBox(
          range: ReaderRangeLine(
            line: box.range.line,
            start: previous.range.start,
            end: box.range.end,
          ),
          style: previous.style,
          highlightSource: box.highlightSource,
        );
      } else {
        result.add(box);
      }
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
