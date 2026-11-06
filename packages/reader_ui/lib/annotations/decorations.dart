import 'package:flutter/painting.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';

import '../selection/text_range_geometry.dart';
import 'annotation.dart';
import 'thought_marker.dart';

/// 标注在当前页的一行绘制片段（P4-18）。
class AnnotationLine {
  /// 创建片段。
  const AnnotationLine({
    required this.annotation,
    required this.line,
    required this.startOffset,
    required this.endOffset,
  });

  /// 来源标注。
  final ReaderAnnotation annotation;

  /// 页内行。
  final PageLineBox line;

  /// 行内起始字符偏移（含）。
  final int startOffset;

  /// 行内结束字符偏移（不含）。
  final int endOffset;

  /// 是否为空片段。
  bool get isEmpty => endOffset <= startOffset;
}

/// 标注装饰计算（P4-18）：把 CFI 区间映射到当前页的逐行字符区间。
///
/// 支持同块、跨块与跨章区间，中间块完整绘制；待确认记录不参与绘制。
abstract final class AnnotationDecorations {
  /// 高亮触摸容差（逻辑像素）。
  static const double tapSlop = 4;

  /// 计算当前页的标注片段，按创建时间排序（先创建的在下层叠加）。
  static List<AnnotationLine> linesFor(
    PageContent page,
    List<ReaderAnnotation> annotations,
  ) {
    if (annotations.isEmpty) {
      return const <AnnotationLine>[];
    }
    final sorted = List<ReaderAnnotation>.of(annotations)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final result = <AnnotationLine>[];
    for (final annotation in sorted) {
      if (annotation.needsRelocation) continue;
      for (final range in ReaderTextRangeGeometry.linesFor(
        page,
        startCfi: annotation.startCfi,
        endCfi: annotation.endCfi,
      )) {
        result.add(
          AnnotationLine(
            annotation: annotation,
            line: range.line,
            startOffset: range.start,
            endOffset: range.end,
          ),
        );
      }
    }
    return result;
  }

  /// 命中点击位置下最新的标注；未命中返回 null。
  ///
  /// 使用实际绘制矩形而不是最近的字符偏移，避免点在空白处误触。
  static ReaderAnnotation? annotationAt(
    PageContent page,
    Offset position,
    List<ReaderAnnotation> annotations, {
    double? contentWidth,
  }) {
    final lines = linesFor(page, annotations);
    final markers = ThoughtMarkerGeometry.markersFor(
      page,
      lines,
      contentWidth: contentWidth,
    );
    for (final marker in markers.reversed) {
      if (marker.touchRect.contains(position)) return marker.annotation;
    }
    for (final line in lines.reversed) {
      final rects = rectsFor(line);
      for (final rect in rects) {
        if (rect.inflate(tapSlop).contains(position)) {
          return line.annotation;
        }
      }
    }
    return null;
  }

  /// 阅读标记使用字形行框，不借用选区手柄的额外留白。
  static List<Rect> rectsFor(AnnotationLine line) => [
    for (final rect in TextHitTester.selectionRects(
      line.line,
      line.startOffset,
      line.endOffset,
    ))
      rect.shift(line.line.rect.topLeft),
  ];
}
