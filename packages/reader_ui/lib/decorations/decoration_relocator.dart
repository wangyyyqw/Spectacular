import 'package:reader_core/layout/paginator.dart';

import '../annotations/annotation.dart';
import '../annotations/relocator.dart';
import 'decoration.dart';

/// 装饰与阅读标注共享原文锚点核验，不直接信任存储 CFI。
abstract final class ReaderDecorationRelocator {
  /// 只返回在当前章节确认对应原文的装饰。
  static List<ReaderDecoration> resolve({
    required List<ReaderDecoration> decorations,
    required List<PageContent> pages,
    String? contentRevision,
  }) {
    final source = {
      for (final decoration in decorations) decoration.id: decoration,
    };
    final results = AnnotationRelocator.relocate(
      annotations: [
        for (final decoration in decorations)
          ReaderAnnotation(
            id: decoration.id,
            type: ReaderAnnotationType.mark,
            startCfi: decoration.startCfi,
            endCfi: decoration.endCfi,
            quote: decoration.quote,
            contextBefore: decoration.contextBefore,
            contextAfter: decoration.contextAfter,
            anchorData: decoration.anchorData,
            relocationStatus: decoration.relocationStatus,
            relocationReason: decoration.relocationReason,
            currentQuote: decoration.currentQuote,
            createdAt: decoration.createdAt,
            updatedAt: decoration.updatedAt,
          ),
      ],
      pages: pages,
      contentRevision: contentRevision,
    );
    return [
      for (final result in results)
        if (result.isResolved) _copy(source[result.annotation.id]!, result),
    ];
  }

  static ReaderDecoration _copy(
    ReaderDecoration original,
    AnnotationRelocation result,
  ) => ReaderDecoration(
    id: original.id,
    startCfi: result.startCfi,
    endCfi: result.endCfi,
    quote: original.quote,
    style: original.style,
    contextBefore: original.contextBefore,
    contextAfter: original.contextAfter,
    anchorData: original.anchorData,
    relocationStatus: result.status.name,
    relocationReason: original.relocationReason,
    currentQuote: original.currentQuote,
    createdAt: original.createdAt,
    updatedAt: original.updatedAt,
  );
}
