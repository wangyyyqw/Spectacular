import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';

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
/// 支持同块与跨块区间：起点块从起点字符画到块末，终点块从块首画到终点
/// 字符；跨页部分由翻页后的同一计算覆盖（§64.3）。
abstract final class AnnotationDecorations {
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
        if (blockBase != startBase && blockBase != endBase) {
          continue;
        }
        final blockLength = box.slice.block.layout.text.length;
        // 本块内标注区间（半开）。
        var from = 0;
        var to = blockLength;
        if (blockBase == startBase) {
          from = startOffset;
        }
        if (blockBase == endBase) {
          to = endOffset;
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
}
