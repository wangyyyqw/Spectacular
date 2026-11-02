import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/position/cfi.dart';

import 'annotation.dart';

/// 重定位状态（§30.4，对照 Reeden verified/relocated/migrated 三态）。
enum AnnotationRelocationStatus {
  /// CFI 直接命中当前排版（字号/边距变化不影响 CFI）。
  verified,

  /// CFI 失效，按 quote + 上下文找回位置。
  relocated,

  /// 无法定位：保留数据但置灰（§30.4 不删除失效标注）。
  failed,
}

/// 重定位失败原因（对照 Reeden 五枚举的一期子集）。
enum AnnotationRelocationFailure {
  /// 当前章找不到引文。
  quoteNotFound,

  /// 引文多处出现且无法消歧。
  ambiguousQuote,

  /// 引文命中但前后文不匹配。
  contextNotMatched,
}

/// 单条标注的重定位结果。
class AnnotationRelocation {
  /// 创建结果。
  const AnnotationRelocation({
    required this.annotation,
    required this.status,
    required this.startCfi,
    required this.endCfi,
    this.failure,
    this.page,
  });

  /// 原标注。
  final ReaderAnnotation annotation;

  /// 状态。
  final AnnotationRelocationStatus status;

  /// 定位后的起始 CFI（verified 时与原文相同）。
  final String startCfi;

  /// 定位后的结束 CFI。
  final String endCfi;

  /// 失败原因（仅 failed 有值）。
  final AnnotationRelocationFailure? failure;

  /// 命中所在页（可选）。
  final PageContent? page;

  /// 是否可绘制。
  bool get isResolved =>
      status == AnnotationRelocationStatus.verified ||
      status == AnnotationRelocationStatus.relocated;

  /// 带定位后 CFI 的标注副本（渲染用）。
  ReaderAnnotation get resolved => ReaderAnnotation(
    id: annotation.id,
    type: annotation.type,
    startCfi: startCfi,
    endCfi: endCfi,
    quote: annotation.quote,
    contextBefore: annotation.contextBefore,
    contextAfter: annotation.contextAfter,
    color: annotation.color,
    style: annotation.style,
    note: annotation.note,
    createdAt: annotation.createdAt,
    updatedAt: annotation.updatedAt,
  );
}

/// 标注重定位（§30.4）：CFI 优先，失效时按引文与上下文兜底。
///
/// 只消费当前章的分页结果；跨章标注按 spine 过滤后各自定位。三级解析与
/// 指纹消歧由 P7-14 增强，这里先覆盖「直查 → 引文唯一/消歧」。
abstract final class AnnotationRelocator {
  /// 对给定章的页重建所有标注的位置。
  static List<AnnotationRelocation> relocate({
    required List<ReaderAnnotation> annotations,
    required List<PageContent> pages,
  }) {
    if (annotations.isEmpty || pages.isEmpty) {
      return const <AnnotationRelocation>[];
    }
    final blocks = <_BlockRef>[];
    for (final page in pages) {
      for (final slice in page.slices) {
        final cfi = slice.block.startCfi;
        if (cfi == null || cfi.isEmpty) {
          continue;
        }
        blocks.add(
          _BlockRef(
            page: page,
            base: cfiBase(cfi),
            cfi: cfi,
            text: slice.block.layout.text,
          ),
        );
      }
    }
    if (blocks.isEmpty) {
      return const <AnnotationRelocation>[];
    }
    return <AnnotationRelocation>[
      for (final annotation in annotations)
        _relocateOne(annotation, blocks),
    ];
  }

  static AnnotationRelocation _relocateOne(
    ReaderAnnotation annotation,
    List<_BlockRef> blocks,
  ) {
    final startBase = cfiBase(annotation.startCfi);
    final startOffset = cfiCharOffset(annotation.startCfi) ?? 0;

    // 一档：CFI 直接命中（重排不影响块级 CFI）。
    for (final block in blocks) {
      if (block.base == startBase) {
        final valid = startOffset >= 0 && startOffset <= block.text.length;
        if (valid) {
          return AnnotationRelocation(
            annotation: annotation,
            status: AnnotationRelocationStatus.verified,
            startCfi: annotation.startCfi,
            endCfi: annotation.endCfi,
            page: block.page,
          );
        }
      }
    }

    // 二档：按引文找回（§30.4）。
    final quote = annotation.quote;
    if (quote.isEmpty) {
      return AnnotationRelocation(
        annotation: annotation,
        status: AnnotationRelocationStatus.failed,
        startCfi: annotation.startCfi,
        endCfi: annotation.endCfi,
        failure: AnnotationRelocationFailure.quoteNotFound,
      );
    }
    final candidates = <_Candidate>[];
    for (final block in blocks) {
      var index = block.text.indexOf(quote);
      while (index >= 0) {
        candidates.add(
          _Candidate(block: block, offset: index, quoteLength: quote.length),
        );
        index = block.text.indexOf(quote, index + 1);
      }
    }
    if (candidates.isEmpty) {
      return AnnotationRelocation(
        annotation: annotation,
        status: AnnotationRelocationStatus.failed,
        startCfi: annotation.startCfi,
        endCfi: annotation.endCfi,
        failure: AnnotationRelocationFailure.quoteNotFound,
      );
    }
    // 上下文消歧：优先前后文都对得上的候选。
    final before = annotation.contextBefore;
    final after = annotation.contextAfter;
    final contextMatched = candidates.where((candidate) {
      return candidate.matchesContext(before: before, after: after);
    }).toList();
    if (contextMatched.isEmpty && candidates.length > 1) {
      // 多处命中且上下文都对不上：无法安全消歧（P7-14 用指纹进一步收窄）。
      return AnnotationRelocation(
        annotation: annotation,
        status: AnnotationRelocationStatus.failed,
        startCfi: annotation.startCfi,
        endCfi: annotation.endCfi,
        failure: AnnotationRelocationFailure.ambiguousQuote,
      );
    }
    final chosen = contextMatched.isNotEmpty
        ? contextMatched.first
        : candidates.first;
    final newStart = cfiWithCharOffset(chosen.block.cfi, chosen.offset);
    final newEnd = cfiWithCharOffset(
      chosen.block.cfi,
      chosen.offset + quote.length,
    );
    return AnnotationRelocation(
      annotation: annotation,
      status: AnnotationRelocationStatus.relocated,
      startCfi: newStart,
      endCfi: newEnd,
      page: chosen.block.page,
    );
  }
}

class _BlockRef {
  const _BlockRef({
    required this.page,
    required this.base,
    required this.cfi,
    required this.text,
  });

  final PageContent page;
  final String base;
  final String cfi;
  final String text;
}

class _Candidate {
  const _Candidate({
    required this.block,
    required this.offset,
    required this.quoteLength,
  });

  final _BlockRef block;
  final int offset;
  final int quoteLength;

  bool matchesContext({String? before, String? after}) {
    if (before != null && before.isNotEmpty) {
      final start = offset - before.length;
      if (start < 0 || block.text.substring(start, offset) != before) {
        return false;
      }
    }
    if (after != null && after.isNotEmpty) {
      final afterStart = offset + quoteLength;
      final afterEnd = afterStart + after.length;
      if (afterEnd > block.text.length ||
          block.text.substring(afterStart, afterEnd) != after) {
        return false;
      }
    }
    return true;
  }
}
