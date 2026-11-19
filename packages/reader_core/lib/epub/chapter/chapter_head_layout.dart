import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/source/chapter_source.dart';

import 'block_style_helpers.dart';
import 'chapter_flow.dart';
import 'chapter_layout_job.dart';
import 'chapter_pagination.dart';
import 'chapter_style_resolver.dart';
import 'container_blocks.dart';

/// 正文逐块构建时持续预排，只有确实闭合的页面才交付给阅读窗口。
class ChapterHeadLayout {
  ChapterHeadLayout(this.snapshot, this.budget, this.textCache, this.onPages);

  final LayoutSnapshot snapshot;
  final LayoutBudget budget;
  final TextLayoutCache textCache;
  final void Function(List<PageContent>) onPages;
  List<PageContent> pages = const [];
  final _ready = <PageContent>[];
  bool waitForClone = false;
  final _margins = ProgressiveMargins();
  StablePageCursor? cursor;
  int _measuredCount = 0;
  static const _backgroundBatchSize = 4;

  /// 后文改变全章分页路径或容差时保留完整入口；此检查不测量文字。
  static Future<({bool supported, bool mayClone})> inspect(
    ChapterStyleResolver resolver,
    LayoutBudget budget,
  ) async {
    if (resolver.pseudoRules.values.any((rules) => rules.isNotEmpty) ||
        resolver.preparedStyles.firstLetterRules.isNotEmpty ||
        resolver.preparedStyles.firstLineRules.isNotEmpty) {
      return (supported: false, mayClone: false);
    }
    var mayClone = false;
    for (final chain in resolver.selectorIndex.chains) {
      await budget.checkpoint();
      final style = resolver.chainStyle(chain);
      if (style.cssFloat != CssFloat.none ||
          style.isOutOfFlow ||
          style.writingMode != CssWritingMode.horizontalTb ||
          (style.columnCount ?? 1) > 1 ||
          (style.columnWidth != null && !style.columnWidth!.isAuto)) {
        return (supported: false, mayClone: false);
      }
      mayClone = mayClone || clonesContainerDecoration(style);
    }
    return (supported: true, mayClone: mayClone);
  }

  Future<void> collect(ChapterFlow flow, PageBackground? background) async {
    if (_measuredCount == flow.blocks.length) return;
    final added = flow.blocks.getRange(_measuredCount, flow.blocks.length);
    await _margins.append(added, budget.checkpoint);
    if (waitForClone &&
        added.any(
          (block) => block.containers.any(
            (fragment) => fragment.container.cloneDecoration,
          ),
        )) {
      waitForClone = false;
    }
    _measuredCount = flow.blocks.length;
    if (waitForClone || _margins.stableCount == 0) return;
    final active = cursor ??= await _createCursor();
    final next = await active.advance(_margins.stableCount, budget.checkpoint);
    if (next.isNotEmpty) {
      _ready.addAll(
        await ChapterPageLayout(
          snapshot,
          budget,
          textCache,
        ).finishPages(next, background),
      );
    }
    if (_ready.isEmpty ||
        (pages.isNotEmpty &&
            budget.priority == ChapterLayoutPriority.background &&
            _ready.length < _backgroundBatchSize)) {
      return;
    }
    pages = List<PageContent>.unmodifiable([...pages, ..._ready]);
    _ready.clear();
    budget.check();
    onPages(pages);
    await budget.checkpoint(force: true);
  }

  Future<StablePageCursor> _createCursor() async => StablePageCursor(
    Paginator(
      pageHeight: snapshot.height,
      pageWidth: snapshot.width,
      topPadding: await chapterTopPadding(
        _margins.blocks,
        snapshot.topInset,
        checkpoint: budget.checkpoint,
      ),
      trimTextEdges: snapshot.trimTextEdges,
    ),
    _margins.blocks,
    snapshot.spineIndex,
  );

  /// 完成结果继续使用已交付页及其稳定块，页面身份与索引保持一致。
  List<PageBlock> retainBlocks(List<PageBlock> blocks) {
    for (var index = 0; index < _margins.stableCount; index++) {
      blocks[index] = _margins.blocks[index];
    }
    return blocks;
  }

  List<PageContent> retainPages(List<PageContent> complete) => [
    ...pages,
    ...complete.skip(pages.length),
  ];
}
