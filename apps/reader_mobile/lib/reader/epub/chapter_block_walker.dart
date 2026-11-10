import 'package:reader_core/api.dart' show EpubNode, TextBlockNode;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/text_aggregator.dart';

import 'chapter_flow.dart';
import 'chapter_selectors.dart';
import 'chapter_style_resolver.dart';
import 'container_blocks.dart';
import 'flex_blocks.dart';
import 'generated_chapter_content.dart';
import 'gallery_block_builder.dart';
import 'image_block_builder.dart';
import 'page_root_table_cell.dart';
import 'inline_content_builder.dart';
import 'table_block_builder.dart';
import 'text_block_builder.dart';
import 'block_style_helpers.dart';

/// 文档序遍历只负责分发与容器上下文，各类构块拥有独立职责。
class ChapterBlockWalker {
  ChapterBlockWalker(this.styles, this.inline, this.content, this.flow)
    : text = TextBlockBuilder(styles, inline, content, flow),
      images = ImageBlockBuilder(styles, inline, content),
      tables = TableBlockBuilder(styles, inline, flow);

  static const floatGroupBase = 500000;
  static const _headings = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};
  final ChapterStyleResolver styles;
  final InlineContentBuilder inline;
  final GeneratedChapterContent content;
  final ChapterFlow flow;
  final TextBlockBuilder text;
  final ImageBlockBuilder images;
  final TableBlockBuilder tables;
  double get width => styles.snapshot.width;
  double get height => styles.snapshot.height;

  Future<void> build(BlockDocument document) => _walk(
    document.root,
    BlockPosition(
      attributes: document.root.attributes,
      ancestors: document.root.tag == 'body'
          ? const []
          : [ChapterNodeView('body', document.root.attributes, const [])],
    ),
    document.root,
  );

  Future<void> _walk(
    EpubNode node,
    BlockPosition position,
    BlockNode root,
  ) async {
    await inline.measure.budget.checkpoint();
    if (node is TextBlockNode) {
      await text.build(node, position);
    } else if (node is BlockNode) {
      await _block(node, position, root);
    } else if (node is InlineNode) {
      for (final child in node.children) {
        await _walk(child, position, root);
      }
    }
  }

  Future<void> _block(
    BlockNode node,
    BlockPosition position,
    BlockNode root,
  ) async {
    final ancestors = _promotedAncestors(node, position.ancestors);
    final view = styles.selectorViewOf(node);
    final chain = [...ancestors, view];
    if (styles.chainStyle(chain).display == CssDisplay.none) return;
    if (await _specialBlock(node, position, ancestors, chain)) return;
    if (node is PromotedBlockNode) {
      _promoteTypography(node, position.ancestors, view);
    }
    final scope = _containerScope(node, position, ancestors, chain);
    _retainContainer(scope, identical(node, root));
    scope.child = _childScope(scope);
    if (scope.retained != null && isDuokanGallery(node)) {
      await _gallery(scope, root);
      return;
    }
    await _children(scope, root);
    await _finishContainer(scope);
  }

  List<SelectorElement> _promotedAncestors(
    BlockNode node,
    List<SelectorElement> ancestors,
  ) => node is PromotedBlockNode && node.inlineAncestors.isNotEmpty
      ? [
          ...ancestors,
          for (final ancestor in node.inlineAncestors)
            ChapterNodeView(ancestor.tag, ancestor.attributes, const []),
        ]
      : ancestors;

  Future<bool> _specialBlock(
    BlockNode node,
    BlockPosition position,
    List<SelectorElement> ancestors,
    List<SelectorElement> chain,
  ) async {
    if (const {'img', 'image', 'object'}.contains(node.tag) &&
        node.children.isEmpty) {
      flow.blocks.addAll(
        await images.build(
          node,
          BlockPosition(
            ancestors: ancestors,
            containerFloat: position.containerFloat,
            containerFloatWidth: position.containerFloatWidth,
            containerFloatGroup: position.containerFloatGroup,
          ),
        ),
      );
      return true;
    }
    if (node.tag == 'table') {
      await tables.build(node, ancestors);
      return true;
    }
    if (node.tag == 'hr' && node.children.isEmpty) {
      _horizontalRule(position, chain);
      return true;
    }
    if (node.children.isNotEmpty) return false;
    final block = await inline.measure.emptyBoxBlock(
      styles.chainStyle(chain),
      width,
      containingHeight: styles.snapshot.pageHeight,
    );
    if (block == null) return false;
    flow.blocks.add(block);
    return true;
  }

  void _horizontalRule(BlockPosition position, List<SelectorElement> chain) {
    final style = styles.styleForChain(
      chain,
      quoteDepth: position.quoteDepth,
      firstInContainer: position.firstInContainer,
      lastInContainer: position.lastInContainer,
    );
    final content = BoxModel.fromStyle(
      style,
      containingWidth: width,
    ).resolveContentWidth(width);
    flow.blocks.add(
      PageBlock.styled(
        layout: TextLayoutResult(
          text: '',
          lines: [
            LineBox(
              start: 0,
              end: 0,
              top: 0,
              height: 0,
              baseline: 0,
              width: content,
            ),
          ],
          width: content,
          height: 0,
          maxWidth: content,
          runs: const [],
        ),
        style: style,
        containingWidth: width,
        spaceBefore:
            styles.snapshot.overrides.paragraphSpacing ?? style.margin.top,
        spaceAfter:
            styles.snapshot.overrides.paragraphSpacing ?? style.margin.bottom,
      ),
    );
  }

  void _promoteTypography(
    PromotedBlockNode node,
    List<SelectorElement> ancestors,
    SelectorElement view,
  ) {
    final applyReader =
        !ancestors.any(styles.promotedInlineStyles.containsKey) &&
        !_headings.contains(ancestors.lastOrNull?.tag);
    var parent = styles.chainStyle(ancestors);
    if (applyReader) parent = styles.snapshot.overrides.applyTypography(parent);
    final mark = InlineMark(
      start: 0,
      end: 0,
      tag: node.tag,
      classes: const [],
      chain: [
        for (final ancestor in node.inlineAncestors)
          MarkSubject(
            tag: ancestor.tag,
            classes: const {},
            attributes: ancestor.attributes,
          ),
        MarkSubject(
          tag: node.tag,
          classes: const {},
          attributes: node.attributes,
        ),
      ],
    );
    styles.promotedInlineStyles[view] = styles.inlineMarkStyle(mark, (
      ancestors: ancestors,
      style: parent,
      width: width,
      readerFontFamily: applyReader
          ? styles.snapshot.overrides.fontFamily
          : null,
    ));
  }

  _ContainerScope _containerScope(
    BlockNode node,
    BlockPosition position,
    List<SelectorElement> ancestors,
    List<SelectorElement> chain,
  ) => _ContainerScope(
    node,
    position,
    ancestors,
    chain,
    styles.chainStyle(chain),
    flow.blocks.length,
  );

  void _retainContainer(_ContainerScope scope, bool isRoot) {
    final style = scope.style;
    final isBodyRoot = isRoot && scope.node.tag == 'body';
    final isFloating =
        floatSideOfStyle(style) != null &&
        scope.node.children.any((child) => child is BlockNode);
    if (scope.position.containerFloat != null ||
        !(isBodyRoot ||
            isFloating ||
            scope.isFlexRow ||
            retainsContainer(scope.node, style))) {
      return;
    }
    final parents = scope.ancestors
        .map((view) => styles.retainedContainers[view])
        .nonNulls;
    final parent = parents.lastOrNull;
    final available = parent?.contentWidth ?? width;
    final model = BoxModel.fromStyle(style, containingWidth: available);
    final retained = PageContainer(
      style: style,
      left: (parent?.contentLeft ?? 0) + style.margin.left,
      width: model.borderBoxWidth(model.resolveContentWidth(available)),
      cloneDecoration: clonesContainerDecoration(style),
      isPageRoot: isRoot,
    );
    styles.retainedContainers[scope.chain.last] = retained;
    // 根盒提供作者水平内缩与后代百分比基准；页面背景和垂直留白
    // 继续由页级路径处理，避免重复绘制背景或重复消费 table-cell 内边距。
    if (isBodyRoot &&
        !scope.isFlexRow &&
        !retainsContainer(scope.node, style)) {
      return;
    }
    scope.retained = retained;
    if (!scope.isFlexRow &&
        scope.node.children.any((child) => child is PromotedBlockNode)) {
      styles.splitInlineContainers.add(scope.chain.last);
    }
  }

  BlockPosition _childScope(_ContainerScope scope) {
    final parent = scope.position;
    var group = parent.groupId;
    if (scope.node.tag == 'figure') group = ++flow.figureSeq;
    final side = floatSideOfStyle(scope.style);
    final floatGroup = side == null
        ? parent.containerFloatGroup
        : floatGroupBase + ++flow.containerFloatSeq;
    return BlockPosition(
      blockTag: scope.node.tag,
      attributes: scope.node.attributes,
      groupId: group,
      ancestors: scope.chain,
      quoteDepth: parent.quoteDepth + (scope.node.tag == 'blockquote' ? 1 : 0),
      list: _listContext(scope),
      firstInContainer: parent.firstInContainer,
      lastInContainer: parent.lastInContainer,
      listFirst: scope.node.tag == 'li' && parent.listFirst,
      listLast: scope.node.tag == 'li' && parent.listLast,
      containerFloat: side ?? parent.containerFloat,
      containerFloatWidth: side == null
          ? parent.containerFloatWidth
          : scope.retained?.contentWidth ??
                inline.measure.textWidthFor(scope.style),
      containerFloatGroup: floatGroup,
    );
  }

  ListContext? _listContext(_ContainerScope scope) {
    final list = scope.position.list;
    if (scope.node.tag == 'li' && list != null) list.markerPending = true;
    if (!scope.isList) return list;
    final style = scope.style;
    return ListContext(
      scope.node.tag,
      (list?.depth ?? -1) + 1,
      spaceBefore:
          style.margin.top + style.borders.top.width + style.padding.top,
      spaceAfter:
          style.margin.bottom +
          style.borders.bottom.width +
          style.padding.bottom,
      inside: style.listStylePosition == CssListStylePosition.inside,
    );
  }

  Future<void> _children(_ContainerScope scope, BlockNode root) async {
    final blockChildren = scope.node.children.whereType<BlockNode>().toList();
    for (final child in scope.node.children) {
      await inline.measure.budget.checkpoint();
      final start = flow.blocks.length;
      await _walk(child, _childPosition(scope, child, blockChildren), root);
      if (scope.isFlexRow && flow.blocks.length > start) {
        final item = await _positionedBlocks(start, positioned: false);
        if (item.isNotEmpty) scope.flexItems.add(item);
      }
    }
  }

  Future<void> _gallery(_ContainerScope scope, BlockNode root) async {
    final frames = <GalleryFrameBlocks>[];
    final children = scope.node.children.cast<BlockNode>().toList();
    for (final child in children) {
      await inline.measure.budget.checkpoint();
      final frameFlow = ChapterFlow();
      await ChapterBlockWalker(
        styles,
        inline,
        content,
        frameFlow,
      )._walk(child, _childPosition(scope, child, children), root);
      frames.add((
        cfi: child.cfi.serialize(),
        blocks: frameFlow.blocks,
        fixed: frameFlow.fixedBlocks,
      ));
    }
    final block =
        await GalleryBlockBuilder(
          styles,
          inline.measure.budget.checkpoint,
        ).build(
          scope.node,
          scope.retained!,
          frames,
          groupId: scope.child.groupId,
          ancestorExtent: _galleryAncestorExtent(scope),
        );
    if (block != null) flow.blocks.add(block);
  }

  double _galleryAncestorExtent(_ContainerScope scope) => scope.ancestors
      .map((view) => styles.retainedContainers[view])
      .nonNulls
      .fold(
        0.0,
        (extent, container) =>
            extent +
            container.topDecoration +
            container.bottomDecoration +
            container.style.margin.vertical,
      );

  BlockPosition _childPosition(
    _ContainerScope scope,
    EpubNode node,
    List<BlockNode> blockChildren,
  ) {
    final base = scope.child;
    final isBlock = node is BlockNode && blockChildren.isNotEmpty;
    final first = identical(node, blockChildren.firstOrNull);
    final last = identical(node, blockChildren.lastOrNull);
    return BlockPosition(
      blockTag: base.blockTag,
      attributes: base.attributes,
      groupId: base.groupId,
      list: base.list,
      quoteDepth: base.quoteDepth,
      ancestors: scope.retained != null && node is TextBlockNode
          ? [
              ...base.ancestors,
              ChapterNodeView('reader-anonymous', const {}, const []),
            ]
          : base.ancestors,
      firstInContainer: isBlock ? first : base.firstInContainer,
      lastInContainer: isBlock ? last : base.lastInContainer,
      listFirst: scope.isList ? first : base.listFirst,
      listLast: scope.isList ? last : base.listLast,
      containerFloat: base.containerFloat,
      containerFloatWidth: base.containerFloatWidth,
      containerFloatGroup: base.containerFloatGroup,
    );
  }

  Future<void> _finishContainer(_ContainerScope scope) async {
    await inline.measure.budget.checkpoint();
    final retained = scope.retained;
    if (scope.isFlexRow && retained != null) {
      await _finishFlexRow(scope, retained);
    }
    if (scope.isPageRootFlexColumn) {
      await alignPageRootFlexColumnAsync(
        blocks: flow.blocks,
        start: scope.start,
        containerStyle: scope.style,
        pageWidth: width,
        pageHeight: height,
        checkpoint: inline.measure.budget.checkpoint,
      );
    }
    if (retained != null && floatSideOfStyle(scope.style) != null) {
      await _finishFloatContainer(scope);
    } else if (retained != null && !scope.isFlexRow) {
      await wrapContainerBlocks(
        flow.blocks,
        scope.start,
        retained,
        paragraphSpacing:
            styles.splitInlineContainers.contains(scope.chain.last) &&
                scope.node.tag == 'p'
            ? styles.snapshot.overrides.paragraphSpacing
            : null,
        checkpoint: inline.measure.budget.checkpoint,
      );
    }
    await _alignPageTableCell(scope);
  }

  Future<void> _finishFloatContainer(_ContainerScope scope) async {
    final box = styles.floatBoxForChain(scope.chain);
    for (var index = scope.start; index < flow.blocks.length; index++) {
      await inline.measure.budget.checkpoint();
      final block = flow.blocks[index];
      if (block.groupId == scope.child.containerFloatGroup &&
          block.floatSide == scope.child.containerFloat) {
        flow.blocks[index] = block.withSpacing(floatBox: box);
      }
    }
  }

  Future<void> _finishFlexRow(
    _ContainerScope scope,
    PageContainer retained,
  ) async {
    final positioned = await _positionedBlocks(scope.start, positioned: true);
    final row = await buildFlexRowBlockAsync(
      containerStyle: scope.style,
      containerWidth: retained.contentWidth,
      items: scope.flexItems,
      containingWidth: width,
      pageContentHeight: height,
      groupId: scope.child.groupId,
      checkpoint: inline.measure.budget.checkpoint,
    );
    if (row != null) {
      flow.blocks.replaceRange(scope.start, flow.blocks.length, [
        row,
        ...positioned,
      ]);
    }
  }

  Future<List<PageBlock>> _positionedBlocks(
    int start, {
    required bool positioned,
  }) async {
    final blocks = <PageBlock>[];
    for (final block in flow.blocks.skip(start)) {
      await inline.measure.budget.checkpoint();
      if (block.absolute == positioned) blocks.add(block);
    }
    return blocks;
  }

  Future<void> _alignPageTableCell(_ContainerScope scope) async {
    final parent = scope.ancestors.lastOrNull;
    if (scope.style.display != CssDisplay.tableCell ||
        parent?.tag != 'body' ||
        parent!.childElements.length != 1) {
      return;
    }
    final rootStyle = styles.chainStyle(scope.ancestors);
    if (rootStyle.display != CssDisplay.table || rootStyle.height == null) {
      return;
    }
    await alignPageRootTableCell(
      blocks: flow.blocks,
      start: scope.start,
      rootStyle: rootStyle,
      alignment: scope.style.verticalAlign,
      page: (
        width: width,
        height: height,
        checkpoint: inline.measure.budget.checkpoint,
      ),
    );
  }
}

/// 一个容器只保留其子遍历所需数据，离开本次作业即释放。
class _ContainerScope {
  _ContainerScope(
    this.node,
    this.position,
    this.ancestors,
    this.chain,
    this.style,
    this.start,
  );
  final BlockNode node;
  final BlockPosition position;
  final List<SelectorElement> ancestors;
  final List<SelectorElement> chain;
  final ComputedStyle style;
  final int start;
  PageContainer? retained;
  late BlockPosition child;
  final List<List<PageBlock>> flexItems = [];
  bool get isFlexRow =>
      style.display == CssDisplay.flex &&
      style.flexDirection == CssFlexDirection.row;
  bool get isPageRootFlexColumn =>
      style.display == CssDisplay.flex &&
      style.flexDirection == CssFlexDirection.column &&
      node.tag == 'body';
  bool get isList => node.tag == 'ul' || node.tag == 'ol';
}
