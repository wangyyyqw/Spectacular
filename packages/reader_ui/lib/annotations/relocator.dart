import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/position/revision_relocator.dart';

import 'annotation.dart';

/// 重定位状态（§30.4）。
enum AnnotationRelocationStatus {
  /// CFI 直接命中当前排版（字号/边距变化不影响 CFI）。
  verified,

  /// CFI 失效，按 quote + 上下文找回位置。
  relocated,

  /// 无法定位：保留数据但置灰（§30.4 不删除失效标注）。
  failed,
}

/// 重定位失败原因（一期子集）。
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
    opacity: annotation.opacity,
    note: annotation.note,
    createdAt: annotation.createdAt,
    updatedAt: annotation.updatedAt,
    relocationStatus: annotation.relocationStatus,
    relocationReason: annotation.relocationReason,
    currentQuote: annotation.currentQuote,
    anchorData: annotation.anchorData,
  );
}

/// 阅读页安全适配器：使用核心统一验证规则，分页仅提供当前章节的文本。
abstract final class AnnotationRelocator {
  static List<AnnotationRelocation> relocate({
    required List<ReaderAnnotation> annotations,
    required List<PageContent> pages,
    String? contentRevision,
  }) {
    if (annotations.isEmpty || pages.isEmpty) return const [];
    final chapters = <int, List<AnchorBlock>>{};
    final seen = <String>{};
    for (final page in pages) {
      for (final slice in page.slices) {
        final table = slice.block.table;
        if (table != null) {
          for (final cell in table.cells) {
            _addBlock(chapters, seen, cell.startCfi, cell.layout.text);
          }
        } else {
          _addBlock(
            chapters,
            seen,
            slice.block.startCfi,
            slice.block.layout.text,
          );
        }
      }
    }
    if (chapters.isEmpty) return const [];
    final book = AnchorBook(
      revision: contentRevision ?? 'reader-layout',
      chapters: [
        for (final entry in chapters.entries)
          AnchorChapter(spineIndex: entry.key, href: '', blocks: entry.value),
      ],
    );
    return relocateAnchors(annotations: annotations, book: book, pages: pages);
  }

  /// 使用已聚合原文核验，不需要先生成章节页面。
  static List<AnnotationRelocation> relocateAnchors({
    required List<ReaderAnnotation> annotations,
    required AnchorBook book,
    List<PageContent> pages = const <PageContent>[],
  }) {
    if (annotations.isEmpty || book.chapters.isEmpty) return const [];
    return [for (final item in annotations) _relocateOne(item, book, pages)];
  }

  static void _addBlock(
    Map<int, List<AnchorBlock>> chapters,
    Set<String> seen,
    String? cfi,
    String text,
  ) {
    if (cfi == null || cfi.isEmpty || !seen.add(cfi)) return;
    final parsed = EpubCfi.parse(cfi);
    final spine = parsed == null ? null : spineIndexOfCfi(parsed);
    if (spine == null) return;
    (chapters[spine] ??= []).add(AnchorBlock(cfi: cfi, text: text));
  }

  static AnnotationRelocation _relocateOne(
    ReaderAnnotation annotation,
    AnchorBook book,
    List<PageContent> pages,
  ) {
    if (annotation.needsRelocation) return _failed(annotation);
    final record = AnchorRecord.decode(annotation.anchorData);
    if (record == null || !record.isResolved) return _failed(annotation);
    final anchor = record.effective;
    // 跨章区间由覆盖时的全书索引核验。仅消费与当前文件版本一致的结果，
    // 避免在当前一章的局部文本中把完整跨章引用误判为删除。
    if (record.isResolved &&
        anchor.revision == book.revision &&
        anchor.end != null &&
        anchor.start.spineIndex != anchor.end!.spineIndex) {
      return _resolved(annotation, anchor.start.cfi, anchor.end!.cfi, pages);
    }
    final result = RevisionRelocator.relocate(
      oldBook: book,
      newBook: book,
      record: record,
    );
    if (!result.isResolved || result.effective.end == null) {
      return _failed(annotation, result.reason);
    }
    final current = result.effective;
    final end = current.end!;
    // 段尾字符位置与下一段开头等价；标注需保留前段结束端点以绘制想法图标。
    final endCfi =
        book.chapter(end.spineIndex)?.cfiAt(end.charOffset, end: true) ??
        end.cfi;
    return _resolved(annotation, current.start.cfi, endCfi, pages);
  }

  static AnnotationRelocation _resolved(
    ReaderAnnotation annotation,
    String start,
    String end,
    List<PageContent> pages,
  ) => AnnotationRelocation(
    annotation: annotation,
    status: start == annotation.startCfi && end == annotation.endCfi
        ? AnnotationRelocationStatus.verified
        : AnnotationRelocationStatus.relocated,
    startCfi: start,
    endCfi: end,
    page: pages.firstOrNull,
  );

  static AnnotationRelocation _failed(
    ReaderAnnotation annotation, [
    String? reason,
  ]) => AnnotationRelocation(
    annotation: annotation,
    status: AnnotationRelocationStatus.failed,
    startCfi: annotation.startCfi,
    endCfi: annotation.endCfi,
    failure: reason?.contains('消歧') == true
        ? AnnotationRelocationFailure.ambiguousQuote
        : AnnotationRelocationFailure.quoteNotFound,
  );
}
