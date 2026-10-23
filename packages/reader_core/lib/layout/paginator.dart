import '../src/api/models.dart' show PageSlice;
import 'text_layout.dart';

/// 一个待分页的文本块。
class PageBlock {
  /// 创建块。
  const PageBlock({
    required this.layout,
    this.pageBreakBefore = false,
    this.pageBreakAfter = false,
    this.startCfi,
    this.endCfi,
  });

  /// 行布局结果。
  final TextLayoutResult layout;

  /// 块前强制分页。
  final bool pageBreakBefore;

  /// 块后强制分页。
  final bool pageBreakAfter;

  /// 块起始 CFI（可选，供进度记录）。
  final String? startCfi;

  /// 块结束 CFI（可选）。
  final String? endCfi;

  /// 块高度。
  double get height => layout.height;
}

/// 页内一个块切片；P1-25 只放整块，P1-26 会按行切。
class PageBlockSlice {
  /// 创建切片。
  const PageBlockSlice({
    required this.block,
    required this.startLine,
    required this.endLine,
    required this.height,
  });

  /// 来源块。
  final PageBlock block;

  /// 起始行（含）。
  final int startLine;

  /// 结束行（不含）。
  final int endLine;

  /// 本切片高度。
  final double height;

  /// 切片行。
  Iterable<LineBox> get lines =>
      block.layout.lines.skip(startLine).take(endLine - startLine);
}

/// 一页内容。
class PageContent implements PageSlice {
  /// 创建页。
  PageContent({
    required this.spineIndex,
    required this.pageIndex,
    required this.slices,
    required this.usedHeight,
    required this.pageHeight,
    required this.topPadding,
  });

  /// 章节序号。
  final int spineIndex;

  /// 页序号（章内 0 起）。
  final int pageIndex;

  /// 本页块切片。
  final List<PageBlockSlice> slices;

  /// 已用高度（不含首页顶部留白）。
  final double usedHeight;

  /// 页高。
  final double pageHeight;

  /// 首页顶部留白。
  final double topPadding;

  /// 是否为空页。
  bool get isEmpty => slices.isEmpty;
}

/// 一章的分页结果。
class ChapterPagination {
  /// 创建结果。
  const ChapterPagination({
    required this.spineIndex,
    required this.pages,
    required this.pageHeight,
    required this.totalHeight,
  });

  /// 章节序号。
  final int spineIndex;

  /// 页列表。
  final List<PageContent> pages;

  /// 页高。
  final double pageHeight;

  /// 所有块总高度。
  final double totalHeight;
}

/// 按块推进的分页器状态机。
class Paginator {
  /// 创建分页器。
  Paginator({
    required this.pageHeight,
    this.topPadding = 0,
    this.tolerance = 2,
  });

  /// 页高。
  final double pageHeight;

  /// 第一章顶部留白。
  final double topPadding;

  /// 浮点容差（像素）。
  final double tolerance;

  /// 对一章块列表分页。
  ChapterPagination measureChapter({
    required List<PageBlock> blocks,
    int spineIndex = 0,
  }) {
    final pages = <PageContent>[];
    var slices = <PageBlockSlice>[];
    var used = 0.0;
    var available = pageHeight - topPadding;
    var firstPage = true;
    var totalHeight = 0.0;

    void record() {
      // 空页不记录，避免零长度页。
      if (slices.isEmpty) {
        return;
      }
      pages.add(
        PageContent(
          spineIndex: spineIndex,
          pageIndex: pages.length,
          slices: List<PageBlockSlice>.unmodifiable(slices),
          usedHeight: used,
          pageHeight: pageHeight,
          topPadding: firstPage ? topPadding : 0,
        ),
      );
      slices = <PageBlockSlice>[];
      used = 0;
      available = pageHeight;
      firstPage = false;
    }

    void addWhole(PageBlock block) {
      final height = block.height;
      slices.add(
        PageBlockSlice(
          block: block,
          startLine: 0,
          endLine: block.layout.lineCount,
          height: height,
        ),
      );
      used += height;
      available -= height;
    }

    for (final block in blocks) {
      totalHeight += block.height;
      if (block.layout.lineCount == 0) {
        continue;
      }
      if (block.pageBreakBefore) {
        record();
      }
      if (block.height <= available + tolerance) {
        addWhole(block);
      } else if (slices.isEmpty) {
        // P1-25：单块高于整页时先整块放入，P1-26 再做跨页行切分。
        addWhole(block);
        record();
      } else {
        record();
        if (block.height <= available + tolerance) {
          addWhole(block);
        } else {
          addWhole(block);
          record();
        }
      }
      if (block.pageBreakAfter) {
        record();
      }
    }
    record();

    return ChapterPagination(
      spineIndex: spineIndex,
      pages: List<PageContent>.unmodifiable(pages),
      pageHeight: pageHeight,
      totalHeight: totalHeight,
    );
  }
}
