import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/full_bleed.dart';
import 'package:reader_core/perf/trace.dart';

import '../../util/bounded_cache.dart';
import 'book_resources.dart';
import 'block_style_helpers.dart';
import 'chapter_block_walker.dart';
import 'chapter_flow.dart';
import 'chapter_layout_cache.dart';
import 'chapter_layout_job.dart';
import 'chapter_pagination.dart';
import 'chapter_selectors.dart';
import 'chapter_style_resolver.dart';
import 'chapter_styles.dart';
import 'chapter_text_measurer.dart';
import 'container_blocks.dart';
import 'full_page_layout.dart';
import 'generated_chapter_content.dart';
import 'inline_content_builder.dart';

/// 准备完成的数据成对冻结，排版途中不再从门面读取会话配置。
class PreparedChapterLayout {
  const PreparedChapterLayout({
    required this.snapshot,
    required this.document,
    required this.selectors,
    required this.styles,
    required this.footnotes,
    required this.imageAnalysis,
    required this.imageCfi,
    required this.fullPageOptions,
    this.traceBook,
  });
  final LayoutSnapshot snapshot;
  final BlockDocument document;
  final ChapterSelectors selectors;
  final ChapterCascadePreparation styles;
  final Map<String, FootnoteAnchor> footnotes;
  final FullBleedChapter imageAnalysis;
  final String? imageCfi;
  final FullPageLayoutOptions fullPageOptions;
  final String? traceBook;
}

typedef ChapterPipelineResult = ({
  CompletedChapterLayout layout,
  String? indexDiagnostic,
  String? warning,
});

typedef _ChapterBlocks = ({
  List<PageBlock> flow,
  List<PageBlock> fixed,
  PageBackground? background,
  String? warning,
});

/// 一次完整构块与分页，仅产出纯结果；缓存和计数统一由门面提交。
class ChapterLayoutPipeline {
  ChapterLayoutPipeline(this.resources, this.textCache, this.widthCache);
  final BookResources resources;
  final TextLayoutCache textCache;
  final BoundedCache<String, double> widthCache;

  Future<ChapterPipelineResult> run(
    PreparedChapterLayout input,
    LayoutBudget budget, {
    CompletedChapterLayout? cached,
  }) async {
    final blocks = cached == null
        ? await _buildBlocks(input, budget)
        : (
            flow: cached.blocks,
            fixed: cached.fixedBlocks,
            background: cached.background,
            warning: null,
          );
    final watch = Stopwatch()..start();
    final pages = await ChapterPageLayout(input.snapshot, budget, textCache)
        .paginate(
          blocks.flow,
          blocks.fixed,
          blocks.background,
          pageIndex: cached?.pageIndex,
        );
    budget.check();
    _trace(ReaderTraceName.chapterPagination, watch, input.traceBook);
    return (
      layout: await CompletedChapterLayout.createAsync(
        key: input.snapshot.key,
        spineIndex: input.snapshot.spineIndex,
        pages: pages.pages,
        blocks: blocks.flow,
        fixedBlocks: blocks.fixed,
        background: blocks.background,
        fontDependency: input.snapshot.fontDependency,
        pageIndex: pages.pageIndex,
        checkpoint: budget.checkpointIfNeeded,
      ),
      indexDiagnostic: pages.indexDiagnostic,
      warning: blocks.warning,
    );
  }

  Future<_ChapterBlocks> _buildBlocks(
    PreparedChapterLayout input,
    LayoutBudget budget,
  ) async {
    await budget.checkpoint();
    final image = FullPageChapterLayout(
      resources,
      input.snapshot,
      input.imageCfi,
    ).build(input.imageAnalysis, input.fullPageOptions);
    if (image.block case final block?) {
      return (
        flow: [block],
        fixed: const <PageBlock>[],
        background: null,
        warning: image.warning,
      );
    }
    final resolver = ChapterStyleResolver(
      input.snapshot,
      input.selectors,
      input.styles,
    );
    final measure = ChapterTextMeasurer(
      input.snapshot,
      budget,
      textCache,
      widthCache,
    );
    final content = GeneratedChapterContent(
      resolver,
      (source) => resources.imageUrl(input.snapshot.spineIndex, source),
    );
    final inline = InlineContentBuilder(
      resolver,
      content,
      measure,
      resources,
      input.footnotes,
    );
    final flow = ChapterFlow();
    final watch = Stopwatch()..start();
    await ChapterBlockWalker(
      resolver,
      inline,
      content,
      flow,
    ).build(input.document);
    _trace(ReaderTraceName.chapterCollect, watch, input.traceBook);
    await budget.checkpoint();
    flow.blocks = await configureContainerDecorationAsync(
      flow.blocks,
      checkpoint: budget.checkpoint,
    );
    await budget.checkpoint();
    flow.blocks = await collapseMarginsIgnoringFloatsAsync(
      flow.blocks,
      checkpoint: budget.checkpoint,
    );
    await budget.checkpoint();
    return (
      flow: flow.blocks,
      fixed: flow.fixedBlocks,
      background: chapterPageBackground(
        resolver.chainStyle([
          ChapterNodeView('body', input.document.root.attributes, const []),
        ]),
        resolveUrl: (url) => resources.imageUrl(input.snapshot.spineIndex, url),
      ),
      warning: image.warning,
    );
  }

  static void _trace(ReaderTraceName name, Stopwatch watch, String? book) {
    if (!readerTraceEnabled) return;
    ReaderTrace.instance.record(name, watch.elapsedMicroseconds, bookId: book);
  }
}
