import 'dart:math' as math;

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
import 'generated_block_builder.dart';
import 'gallery_block_builder.dart';
import 'image_block_builder.dart';
import 'page_root_table_cell.dart';
import 'inline_content_builder.dart';
import 'table_block_builder.dart';
import 'text_block_builder.dart';
import 'intrinsic_blocks.dart';
import 'chapter_text_measurer.dart';
import 'block_style_helpers.dart';
import 'multicol_blocks.dart';

/// 文档序遍历只负责分发与容器上下文，各类构块拥有独立职责。
class ChapterBlockWalker {
  ChapterBlockWalker(this.styles, this.inline, this.content, this.flow)
    : text = TextBlockBuilder(styles, inline, content, flow),
      generated = GeneratedBlockBuilder(styles, inline, content),
      images = ImageBlockBuilder(styles, inline, content),
      tables = TableBlockBuilder(styles, inline, flow);

  static const floatGroupBase = 500000;
  static const _headings = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};
  final ChapterStyleResolver styles;
  final InlineContentBuilder inline;
  final GeneratedChapterContent content;
  final ChapterFlow flow;
  final TextBlockBuilder text;
  final GeneratedBlockBuilder generated;
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
    final isRoot = identical(node, root);
    if (await _specialBlock(
      node,
      position,
      ancestors,
      chain,
      isBodyRoot: isRoot && node.tag == 'body',
    )) {
      return;
    }
    if (node is PromotedBlockNode) {
      await _promoteTypography(node, position.ancestors, view);
    }
    final scope = _containerScope(node, position, ancestors, chain);
    scope.pseudos = generated.blockPseudosFor(chain, scope.style);
    await _retainContainer(scope, isRoot);
    scope.child = _childScope(scope);
    if (scope.retained != null && isDuokanGallery(node)) {
      await _gallery(scope, root);
      return;
    }
    if (scope.retained != null) {
      styles.blockPseudoElements[scope.chain.last] = scope.pseudos;
      content.applyCounters(scope.chain);
    }
    await _generatedChild(scope, '::before');
    await _children(scope, root);
    await _generatedChild(scope, '::after');
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
    List<SelectorElement> chain, {
    required bool isBodyRoot,
  }) async {
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
    return _emptyBlock(chain, isBodyRoot);
  }

  Future<bool> _emptyBlock(List<SelectorElement> chain, bool isBodyRoot) async {
    final style = styles.chainStyle(chain);
    final floatBox = style.isOutOfFlow || floatSideOfStyle(style) == null
        ? null
        : styles.floatBoxForChain(chain);
    // 空 body 同样使用页级背景，避免在正文区再次缩放绘制。
    final block = await inline.measure.emptyBoxBlock(
      isBodyRoot ? style.withoutBackground() : style,
      floatBox?.containingWidth ?? width,
      containingHeight: styles.snapshot.pageHeight,
      floatBox: floatBox,
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

  Future<void> _promoteTypography(
    PromotedBlockNode node,
    List<SelectorElement> ancestors,
    SelectorElement view,
  ) async {
    final applyReader =
        !ancestors.any(styles.promotedInlineStyles.containsKey) &&
        !_headings.contains(ancestors.lastOrNull?.tag);
    var parent = styles.chainStyle(ancestors);
    if (applyReader) parent = styles.snapshot.overrides.applyTypography(parent);
    styles.promotedInlineStyles[view] = await styles.inlineMarkStyle(
      _promotedMark(node),
      (
        ancestors: ancestors,
        style: parent,
        width: width,
        readerFontFamily: applyReader
            ? styles.snapshot.overrides.fontFamily
            : null,
      ),
      checkpoint: inline.measure.budget.checkpoint,
    );
  }

  InlineMark _promotedMark(PromotedBlockNode node) => InlineMark(
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

  Future<void> _retainContainer(_ContainerScope scope, bool isRoot) async {
    final style = scope.style;
    final isBodyRoot = isRoot && scope.node.tag == 'body';
    final isFloating =
        floatSideOfStyle(style) != null &&
        scope.node.children.any((child) => child is BlockNode);
    if (scope.position.containerFloat != null ||
        !(isBodyRoot ||
            isFloating ||
            scope.isFixedContainer ||
            scope.isAbsoluteContainer ||
            scope.isFlexRow ||
            scope.pseudos.isNotEmpty ||
            retainsContainer(scope.node, style))) {
      return;
    }
    final parents = scope.ancestors
        .map((view) => styles.retainedContainers[view])
        .nonNulls;
    final parent = parents.lastOrNull;
    final fixedWidth =
        width +
        styles.snapshot.sideInsets.left +
        styles.snapshot.sideInsets.right;
    final positioningParent = parents
        .where(
          (box) =>
              box.style.position != CssPosition.static ||
              box.style.transforms.isNotEmpty,
        )
        .lastOrNull;
    final available = scope.isFixedContainer
        ? fixedWidth
        : scope.isAbsoluteContainer
        ? (positioningParent == null
              ? width
              : positioningParent.contentWidth +
                    positioningParent.style.padding.horizontal)
        : parent?.flowWidth ?? width;
    final model = BoxModel.fromStyle(style, containingWidth: available);
    final positioned = scope.isFixedContainer || scope.isAbsoluteContainer
        ? style.resolveAbsoluteBox(
            containingWidth: available,
            containingHeight: height,
          )
        : null;
    final intrinsic =
        style.hasIntrinsicWidth &&
            ChapterTextMeasurer.isOrdinaryHorizontalBlock(style)
        ? await ChapterIntrinsicMeasurer(styles, text, content).contentWidths(
            scope.node,
            scope.chain,
            available,
            list: scope.position.list,
          )
        : null;
    final resolvedWidth = _flexItemWidth(
      scope,
      parent,
      model,
      positioned?.width == null
          ? model.resolveContentWidth(available, intrinsicWidths: intrinsic)
          : math.max(
              0,
              positioned!.width! -
                  (style.boxSizing == CssBoxSizing.borderBox
                      ? model.horizontalInset
                      : 0),
            ),
    );
    final usedStyle = intrinsic == null
        ? style
        : style.withIntrinsicMargins(
            contentWidth: resolvedWidth,
            containingWidth: available,
          );
    final retained = PageContainer(
      style: isBodyRoot ? usedStyle.withoutBackground() : usedStyle,
      left:
          (scope.isFixedContainer && positioned?.left != null
              ? positioned!.left! - styles.snapshot.sideInsets.left
              : null) ??
          _containerLeft(
            parent,
            usedStyle,
            model.borderBoxWidth(resolvedWidth),
            scope.ancestors.lastOrNull,
          ),
      width: model.borderBoxWidth(resolvedWidth),
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

  double _flexItemWidth(
    _ContainerScope scope,
    PageContainer? parent,
    BoxModel model,
    double contentWidth,
  ) {
    final parentView = scope.ancestors.lastOrNull;
    final style = scope.style;
    if (style.isOutOfFlow ||
        parent == null ||
        !identical(parent, styles.retainedContainers[parentView]) ||
        parent.style.display != CssDisplay.flex ||
        parent.style.flexDirection != CssFlexDirection.row ||
        parentView?.childElements.where((child) {
              final childStyle = styles.chainStyle([...scope.ancestors, child]);
              return childStyle.display != CssDisplay.none &&
                  !childStyle.isOutOfFlow;
            }).singleOrNull ==
            null ||
        style.flexShrink < 1 ||
        style.intrinsicWidth != null ||
        !style.flexBasis.isAuto ||
        style.flexBasisIsContent) {
      return contentWidth;
    }
    // 隐藏或脱离普通流的兄弟不产生 Flex 子项。单个可完全收缩的子项
    // 在测量后代前即可确定最终内容宽，
    // 百分比图片与文字不能继续使用收缩前的包含块。
    final available = math.max(
      0.0,
      parent.contentWidth - style.margin.horizontal - model.horizontalInset,
    );
    final minWidth = math.max(
      0.0,
      (style.minWidth?.resolve(parent.contentWidth) ?? 0) -
          (style.boxSizing == CssBoxSizing.borderBox
              ? model.horizontalInset
              : 0),
    );
    return math.min(contentWidth, math.max(available, minWidth));
  }

  double _containerLeft(
    PageContainer? parent,
    ComputedStyle style,
    double borderWidth,
    SelectorElement? parentView,
  ) {
    final left = (parent?.contentLeft ?? 0) + style.margin.left;
    if (parent == null ||
        !identical(parent, styles.retainedContainers[parentView]) ||
        parent.style.display != CssDisplay.flex ||
        parent.style.flexDirection != CssFlexDirection.column ||
        parent.style.alignItems != CssAlignItems.center) {
      return left;
    }
    // 仅对齐直接子项的外边距盒，后代复用同一内容坐标。
    final free = parent.contentWidth - borderWidth - style.margin.horizontal;
    return left + free / 2;
  }

  BlockPosition _childScope(_ContainerScope scope) {
    final parent = scope.position;
    var group = parent.groupId;
    if (scope.node.tag == 'figure') group = ++flow.figureSeq;
    final side = floatSideOfStyle(scope.style);
    final floatGroup = side == null
        ? parent.containerFloatGroup
        : floatGroupBase + ++flow.containerFloatSeq;
    // 多栏内部按单列独立测量，只有外包装参与父流的浮动占位。
    final separateFlow = scope.isMulticol;
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
      containerFloat: separateFlow ? null : side ?? parent.containerFloat,
      containerFloatWidth: separateFlow
          ? null
          : side == null
          ? parent.containerFloatWidth
          : scope.retained?.contentWidth ??
                inline.measure.textWidthFor(scope.style),
      containerFloatGroup: separateFlow ? 0 : floatGroup,
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

  Future<void> _generatedChild(_ContainerScope scope, String pseudo) async {
    if (scope.retained == null || !scope.pseudos.contains(pseudo)) return;
    final block = await generated.build(
      scope.chain,
      pseudo,
      groupId: scope.child.groupId,
    );
    if (block == null) return;
    flow.blocks.add(block);
    if (scope.isFlexRow) scope.flexItems.add([block]);
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
    if (retained != null && await _finishMulticol(scope, retained)) return;
    if (scope.isFlexRow && retained != null) {
      await _finishFlexRow(scope, retained);
    }
    if (scope.isPageRootFlexColumn) {
      await alignPageRootFlexColumn(
        blocks: flow.blocks,
        start: scope.start,
        containerStyle: scope.style,
        page: (
          width: width,
          height: height,
          retainedTopInset: retained?.topDecoration ?? 0,
        ),
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
    if (scope.isFixedContainer) await _finishFixedContainer(scope);
    if (scope.isAbsoluteContainer && retained != null) {
      await _finishAbsoluteContainer(scope);
    }
  }

  /// 多块绝对定位盒保留共享父框和原块载荷，内部段距先折叠再整体脱离正文流。
  Future<void> _finishAbsoluteContainer(_ContainerScope scope) async {
    final children = await collapseMarginsIgnoringFloatsAsync(
      flow.blocks.sublist(scope.start),
      checkpoint: inline.measure.budget.checkpoint,
    );
    var top = 0.0;
    for (var index = 0; index < children.length; index++) {
      final block = children[index];
      if (block.absolute) continue;
      children[index] = block.withSpacing(absolute: true, absoluteTop: top);
      top += block.leadingExtent + block.height + block.trailingExtent;
    }
    flow.blocks.replaceRange(scope.start, flow.blocks.length, children);
  }

  /// 固定定位父盒作为完整覆盖层绘制；子项只保留各自文字和装饰，不占正文流。
  Future<void> _finishFixedContainer(_ContainerScope scope) async {
    var top =
        scope.style
            .resolveAbsoluteBox(
              containingWidth:
                  width +
                  styles.snapshot.sideInsets.left +
                  styles.snapshot.sideInsets.right,
              containingHeight: height,
            )
            ?.top ??
        0;
    // 固定容器锚定整页，绘制器添加阅读内缩前先还原其页面坐标。
    top -= styles.snapshot.topInset;
    final children = flow.blocks.sublist(scope.start);
    flow.blocks.removeRange(scope.start, flow.blocks.length);
    for (final block in children) {
      await inline.measure.budget.checkpoint();
      flow.fixedBlocks.add(
        block.absolute
            ? block
            : block.withSpacing(
                absolute: true,
                absoluteTop: top,
                absoluteLeft: 0,
              ),
      );
      if (!block.absolute) {
        top += block.leadingExtent + block.height + block.trailingExtent;
      }
    }
  }

  Future<bool> _finishMulticol(
    _ContainerScope scope,
    PageContainer retained,
  ) async {
    if (scope.isFlexRow || scope.isPageRootFlexColumn) return false;
    var block = await buildMulticolContainer(
      children: flow.blocks.sublist(scope.start),
      container: retained,
      style: styles.styleForChain(scope.chain),
      containingWidth: width,
      checkpoint: inline.measure.budget.checkpoint,
    );
    if (block == null) return false;
    final side = floatSideOfStyle(scope.style);
    if (side != null) {
      block = block.withSpacing(
        floatSide: side,
        floatBox: styles.floatBoxForChain(scope.chain),
      );
    }
    flow.blocks.replaceRange(scope.start, flow.blocks.length, [block]);
    return true;
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
    final row = await buildFlexRowBlock(
      containerStyle: retained.isPageRoot
          ? retained.style
          : styles.styleForChain(scope.chain),
      containerWidth: retained.contentWidth,
      containerContentLeft: retained.contentLeft,
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
  Set<String> pseudos = const {};
  final List<List<PageBlock>> flexItems = [];
  bool get isFlexRow =>
      style.display == CssDisplay.flex &&
      style.flexDirection == CssFlexDirection.row;
  bool get isFixedContainer =>
      style.position == CssPosition.fixed &&
      node.children.any((child) => child is BlockNode);
  bool get isAbsoluteContainer =>
      style.position == CssPosition.absolute &&
      node.children.any((child) => child is BlockNode);
  bool get isPageRootFlexColumn =>
      style.display == CssDisplay.flex &&
      style.flexDirection == CssFlexDirection.column &&
      node.tag == 'body';
  bool get isList => node.tag == 'ul' || node.tag == 'ol';
  bool get isMulticol =>
      retained != null &&
      !isFlexRow &&
      !isPageRootFlexColumn &&
      MulticolGeometry.fromStyle(retained!.style, retained!.contentWidth) !=
          null;
}
