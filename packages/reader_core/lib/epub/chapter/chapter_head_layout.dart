import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';

import 'chapter_flow.dart';
import 'chapter_layout_job.dart';
import 'chapter_pagination.dart';
import 'chapter_style_resolver.dart';
import 'container_blocks.dart';

/// 首页及紧邻储备先交付；预览最多八页，随后只进行一次完整分页。
class ChapterHeadLayout {
  ChapterHeadLayout(this.snapshot, this.budget, this.textCache, this.onPages);

  static const _pageLimit = 8;
  final LayoutSnapshot snapshot;
  final LayoutBudget budget;
  final TextLayoutCache textCache;
  final void Function(List<PageContent>) onPages;
  List<PageContent> pages = const [];
  bool waitForClone = false;
  List<PageBlock> _stableBlocks = const [];
  int _measuredCount = 0;
  double _extent = 0;
  late double _nextExtent = snapshot.height;

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
    if (pages.length >= _pageLimit) return;
    for (var index = _measuredCount; index < flow.blocks.length; index++) {
      final block = flow.blocks[index];
      _extent += block.leadingExtent + block.height + block.trailingExtent;
    }
    _measuredCount = flow.blocks.length;
    // 只在真实续框出现后采用零容差；纯行内边框不能改变完整分页策略。
    if (waitForClone &&
        !flow.blocks.any(
          (block) => block.containers.any(
            (fragment) => fragment.container.cloneDecoration,
          ),
        )) {
      return;
    }
    if (_extent < _nextExtent) return;
    _nextExtent = _extent + snapshot.height / 2;
    final blocks = await _prefixBlocks(flow.blocks);
    final stableCount = stableMarginPrefixLength(blocks);
    final candidate = await ChapterPageLayout(snapshot, budget, textCache)
        .paginateStablePrefix(
          blocks,
          stableCount,
          background,
          maxPages: _pageLimit,
        );
    if (candidate.length <= pages.length) return;
    _stableBlocks = List<PageBlock>.of(blocks.take(stableCount));
    pages = List<PageContent>.unmodifiable([
      ...pages,
      ...candidate.skip(pages.length),
    ]);
    budget.check();
    onPages(pages);
    await budget.checkpoint(force: true);
  }

  Future<List<PageBlock>> _prefixBlocks(List<PageBlock> source) async {
    // 装饰与边距操作只作用于快照，不能回改 walker 的开放 scope 索引。
    final decorated = await configureContainerDecorationAsync(
      List<PageBlock>.of(source),
      checkpoint: budget.checkpoint,
    );
    final blocks = await collapseMarginsIgnoringFloatsAsync(
      decorated,
      checkpoint: budget.checkpoint,
    );
    return retainBlocks(blocks);
  }

  /// 完成结果继续使用已交付页及其稳定块，页面身份与索引保持一致。
  List<PageBlock> retainBlocks(List<PageBlock> blocks) {
    for (var index = 0; index < _stableBlocks.length; index++) {
      blocks[index] = _stableBlocks[index];
    }
    return blocks;
  }

  List<PageContent> retainPages(List<PageContent> complete) => [
    ...pages,
    ...complete.skip(pages.length),
  ];
}
