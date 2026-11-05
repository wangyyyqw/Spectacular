import 'package:flutter/painting.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';

import '../selection/selection.dart';
import 'annotation.dart';

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

  /// 笔记圆点相对行尾的距离（逻辑像素）。
  static const double noteMarkerOffset = 4;

  /// 笔记圆点绘制半径（逻辑像素）。
  static const double noteMarkerRadius = 3;

  /// 笔记圆点的可点击半径（逻辑像素），对应 48dp 触控目标。
  static const double noteMarkerTapRadius = 24;

  /// 计算当前页的标注片段，按创建时间排序（先创建的在下层叠加）。
  static List<AnnotationLine> linesFor(
    PageContent page,
    List<ReaderAnnotation> annotations,
  ) {
    if (annotations.isEmpty) {
      return const <AnnotationLine>[];
    }
    final boxes = TextHitTester.lineBoxes(page);
    if (boxes.isEmpty) {
      return const <AnnotationLine>[];
    }
    final sorted = List<ReaderAnnotation>.of(annotations)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final result = <AnnotationLine>[];
    for (final annotation in sorted) {
      if (annotation.needsRelocation) continue;
      final start = EpubCfi.parse(annotation.startCfi)?.withCharOffset(0);
      final end = EpubCfi.parse(annotation.endCfi)?.withCharOffset(0);
      if (start == null || end == null || start.compareTo(end) > 0) continue;
      final startBase = cfiBase(annotation.startCfi);
      final endBase = cfiBase(annotation.endCfi);
      final startOffset = cfiCharOffset(annotation.startCfi) ?? 0;
      final endOffset = cfiCharOffset(annotation.endCfi) ?? startOffset;
      for (final box in boxes) {
        final base = box.slice.block.startCfi;
        if (base == null || base.isEmpty) {
          continue;
        }
        final blockBase = cfiBase(base);
        final blockCfi = EpubCfi.parse(base)?.withCharOffset(0);
        if (blockCfi == null ||
            blockCfi.compareTo(start) < 0 ||
            blockCfi.compareTo(end) > 0) {
          continue;
        }
        final blockLength = box.slice.block.layout.text.length;
        // 本块内标注区间（半开）。
        var from = 0;
        var to = blockLength;
        if (blockBase == startBase) {
          from = startOffset - (cfiCharOffset(base) ?? 0);
        }
        if (blockBase == endBase) {
          to = endOffset - (cfiCharOffset(base) ?? 0);
        }
        // 标注偏移是块内坐标；行盒的 textOffset 是整页坐标，
        // 块内基址要用 blockTextOffset（P9-28）。
        final lineStart = box.blockTextOffset;
        final lineEnd = box.blockTextOffset + box.text.length;
        final overlapStart = from > lineStart ? from : lineStart;
        final overlapEnd = to < lineEnd ? to : lineEnd;
        if (overlapEnd <= overlapStart) {
          continue;
        }
        result.add(
          AnnotationLine(
            annotation: annotation,
            line: box,
            startOffset: overlapStart - lineStart,
            endOffset: overlapEnd - lineStart,
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
    List<ReaderAnnotation> annotations,
  ) {
    final lines = linesFor(page, annotations);
    for (final line in lines.reversed) {
      final rects = SelectionOps.lineRectsFor(
        line.line,
        line.startOffset,
        line.endOffset,
      );
      for (final rect in rects) {
        if (rect.inflate(tapSlop).contains(position)) {
          return line.annotation;
        }
      }
      if (line.annotation.type == ReaderAnnotationType.note &&
          rects.isNotEmpty) {
        final markerCenter = Offset(
          rects.last.right + noteMarkerOffset,
          rects.last.center.dy,
        );
        if ((position - markerCenter).distance <= noteMarkerTapRadius) {
          return line.annotation;
        }
      }
    }
    return null;
  }
}
