import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';

import 'chapter_layout_job.dart';
import 'container_blocks.dart' show containerFragmentsFor;
import 'text_coordinates.dart' show sliceTextRuns;

/// 一次分页的纯结果；宿主决定是否保留页面与索引，不在此写入章节缓存。
class ChapterPaginationResult {
  ChapterPaginationResult({
    required List<PageContent> pages,
    this.pageIndex,
    this.indexDiagnostic,
  }) : pages = List<PageContent>.unmodifiable(pages);

  final List<PageContent> pages;
  final Uint8List? pageIndex;
  final String? indexDiagnostic;
}

/// 只依赖本次冻结的尺寸、字形与预算，不持有书籍资源或阅读会话。
class ChapterPageLayout {
  ChapterPageLayout(this.snapshot, this.budget, this.textCache);

  final LayoutSnapshot snapshot;
  final LayoutBudget budget;
  final TextLayoutCache textCache;

  Future<ChapterPaginationResult> paginate(
    List<PageBlock> blocks,
    List<PageBlock> fixed,
    PageBackground? background, {
    Uint8List? pageIndex,
  }) async {
    budget.check();
    final input = List<PageBlock>.unmodifiable(blocks);
    final overlays = List<PageBlock>.unmodifiable(fixed);
    final traits = await _indexTraits(input);
    final ChapterPaginationResult result;
    if (traits.floats) {
      final floated = await _FloatPagination(this, input).run();
      final pages = await _withFixedOverlays(floated, overlays);
      result = ChapterPaginationResult(
        pages: await _finishChapterPages(pages, background),
      );
    } else {
      result = await _paginateOrdinary(
        input,
        overlays,
        background,
        traits.skipIndex ? null : pageIndex,
        traits.skipIndex,
      );
    }
    budget.check();
    return result;
  }

  Future<({bool floats, bool skipIndex})> _indexTraits(
    List<PageBlock> blocks,
  ) async {
    var floats = false;
    var skipIndex = false;
    for (final block in blocks) {
      await budget.checkpoint();
      floats = floats || block.floatSide != null;
      skipIndex =
          skipIndex ||
          block.absolute ||
          (block.height - block.measuredHeight).abs() > 0.01 ||
          block.clipsContent;
    }
    return (floats: floats, skipIndex: skipIndex);
  }

  Future<ChapterPaginationResult> _paginateOrdinary(
    List<PageBlock> blocks,
    List<PageBlock> fixed,
    PageBackground? background,
    Uint8List? cachedIndex,
    bool skipIndex,
  ) async {
    final replay = await _replayIndex(cachedIndex, blocks);
    if (replay.pages case final pages?) {
      return ChapterPaginationResult(
        pages: await _finishChapterPages(
          await _withFixedOverlays(pages, fixed),
          background,
        ),
        pageIndex: cachedIndex,
      );
    }
    final pages = await _measurePages(blocks);
    final finished = await _finishChapterPages(
      await _withFixedOverlays(pages, fixed),
      background,
    );
    budget.check();
    return ChapterPaginationResult(
      pages: finished,
      pageIndex: skipIndex ? null : await _encodeIndex(finished, blocks),
      indexDiagnostic: replay.diagnostic,
    );
  }

  Future<Uint8List> _encodeIndex(
    List<PageContent> pages,
    List<PageBlock> blocks,
  ) async {
    final index = await PageIndex.fromAsync(
      ChapterPagination(
        spineIndex: snapshot.spineIndex,
        pages: pages,
        pageHeight: snapshot.height,
        totalHeight: 0,
      ),
      blocks,
      checkpoint: budget.checkpoint,
    );
    return index.encodeAsync(checkpoint: budget.checkpoint);
  }

  Future<({List<PageContent>? pages, String? diagnostic})> _replayIndex(
    Uint8List? bytes,
    List<PageBlock> blocks,
  ) async {
    if (bytes == null) return (pages: null, diagnostic: null);
    await budget.checkpoint();
    final index = await PageIndex.decodeAsync(
      bytes,
      checkpoint: budget.checkpoint,
    );
    if (index == null) return (pages: null, diagnostic: 'indexCorrupted');
    final pages = await PageIndex.applyAsync(
      index,
      blocks,
      spineIndex: snapshot.spineIndex,
      trimTextEdges: snapshot.trimTextEdges,
      checkpoint: budget.checkpoint,
    );
    await budget.checkpoint();
    return (
      pages: pages,
      diagnostic: pages == null ? 'indexSchemaMismatch' : null,
    );
  }

  Future<List<PageContent>> _measurePages(List<PageBlock> blocks) async {
    final paginator = Paginator(
      pageHeight: snapshot.height,
      pageWidth: snapshot.width,
      topPadding: await _chapterTopPadding(blocks),
      trimTextEdges: snapshot.trimTextEdges,
    );
    final pages = <PageContent>[];
    await for (final page in paginator.paginate(
      blocks: blocks,
      spineIndex: snapshot.spineIndex,
      token: budget.token,
      budgetCheck: budget.checkpoint,
    )) {
      pages.add(page);
    }
    budget.check();
    return pages;
  }

  /// 章首出血图从页顶开始，正文不重复预留安全区和页眉槽。
  Future<double> _chapterTopPadding(List<PageBlock> blocks) async {
    PageBlock? first;
    for (final block in blocks) {
      await budget.checkpoint();
      if (!block.absolute &&
          block.style?.display != CssDisplay.none &&
          (block.layout.lineCount > 0 || block.height > 0)) {
        first = block;
        break;
      }
    }
    final hasBackground =
        first?.style?.backgroundLayers.any(
          (layer) => layer.image != null || layer.gradient != null,
        ) ??
        false;
    if (first == null ||
        first.floatSide != null ||
        !first.bleedTop ||
        first.bleedBottom ||
        first.layout.text.isNotEmpty ||
        !hasBackground) {
      return 0;
    }
    return -snapshot.topInset;
  }

  Future<List<PageContent>> _withFixedOverlays(
    List<PageContent> pages,
    List<PageBlock> fixed,
  ) async {
    if (fixed.isEmpty || pages.isEmpty) return pages;
    final overlays = await _fixedSlices(fixed);
    final result = <PageContent>[];
    for (final page in pages) {
      await budget.checkpoint();
      result.add(
        PageContent(
          spineIndex: page.spineIndex,
          pageIndex: page.pageIndex,
          slices: [...page.slices, ...overlays],
          usedHeight: page.usedHeight,
          pageHeight: page.pageHeight,
          topPadding: page.topPadding,
          background: page.background,
        ),
      );
    }
    return result;
  }

  Future<List<PageBlockSlice>> _fixedSlices(List<PageBlock> fixed) async {
    final overlays = <PageBlockSlice>[];
    for (final block in fixed) {
      await budget.checkpoint();
      final box = block.style?.resolveAbsoluteBox(
        containingWidth: snapshot.width,
        containingHeight: snapshot.pageHeight,
      );
      overlays.add(
        PageBlockSlice(
          block: block,
          startLine: 0,
          endLine: block.layout.lineCount,
          height: block.height,
          overlay: true,
          absoluteTop: box?.top ?? 0,
          leftInset: box?.left ?? 0,
        ),
      );
    }
    return overlays;
  }

  Future<List<PageContent>> _finishChapterPages(
    List<PageContent> source,
    PageBackground? background,
  ) async {
    await budget.checkpoint();
    final pages = source.isEmpty
        ? [
            PageContent(
              spineIndex: snapshot.spineIndex,
              pageIndex: 0,
              slices: const [],
              usedHeight: 0,
              pageHeight: snapshot.height,
              topPadding: 0,
            ),
          ]
        : source;
    if (background == null) return pages;
    final result = <PageContent>[];
    for (final page in pages) {
      await budget.checkpoint();
      result.add(page.withBackground(background));
    }
    return result;
  }

  ComputedStyle get _style => snapshot.fonts.applyCustomFont(
    snapshot.overrides.apply(
      snapshot.baseStyle,
      containingWidth: snapshot.width,
    ),
    snapshot.overrides,
  );

  /// 绕排续行不再应用 text-indent，行内盒、注音和 run 坐标仍基于原文。
  Future<TextLayoutResult> _relayoutFloatText(
    PageBlock block,
    ComputedStyle style,
    double width, {
    int start = 0,
  }) async {
    final layoutStyle = start == 0
        ? style
        : style.withTypography(textIndent: 0);
    final boxes = await _inlineBoxesFrom(block, start);
    final rubies = await _rubiesFrom(block, start);
    await budget.checkpoint();
    final input = (
      text: block.layout.text.substring(start),
      runs: sliceTextRuns(block.layout, start, block.layout.text.length),
      boxes: boxes,
      rubies: rubies,
    );
    return _measureFloatText(input, layoutStyle, width);
  }

  Future<TextLayoutResult> _measureFloatText(
    _FloatTextInput input,
    ComputedStyle style,
    double width,
  ) => input.boxes.isEmpty
      ? textCache.layoutAsync(
          text: input.text,
          style: style,
          maxWidth: width,
          runs: input.runs,
          rubies: input.rubies,
          hasGlyph: snapshot.fonts.hasGlyph,
          fontDependency: snapshot.fontDependency,
          checkpoint: budget.checkpoint,
        )
      : TextLayoutEngine.layoutAsync(
          text: input.text,
          style: style,
          maxWidth: width,
          runs: input.runs,
          inlineBoxes: input.boxes,
          rubies: input.rubies,
          hasGlyph: snapshot.fonts.hasGlyph,
          checkpoint: budget.checkpoint,
        );

  Future<List<InlineBoxSpec>> _inlineBoxesFrom(
    PageBlock block,
    int start,
  ) async {
    final result = <InlineBoxSpec>[];
    for (final line in block.layout.lines) {
      await budget.checkpoint();
      for (final box in line.inlineBoxes) {
        await budget.checkpoint();
        if (box.offset >= start) {
          result.add(box.spec.atOffset(box.offset - start));
        }
      }
    }
    return result;
  }

  Future<List<RubyAnnotation>> _rubiesFrom(PageBlock block, int start) async {
    final result = <RubyAnnotation>[];
    for (final ruby in block.rubies ?? const <RubyAnnotation>[]) {
      await budget.checkpoint();
      if (ruby.end > start) {
        result.add(
          RubyAnnotation(
            start: math.max(0, ruby.start - start),
            end: ruby.end - start,
            text: ruby.text,
            style: ruby.style,
          ),
        );
      }
    }
    return result;
  }
}

typedef _FloatRegion = ({double left, double width});
typedef _FloatSize = ({double width, double height});
typedef _FloatPosition = ({double top, double x});
typedef _FloatWidth = ({double occupied, double leftSpace, double marginLeft});
typedef _FloatGroupGeometry = ({List<double> tops, double height});
typedef _FloatTextInput = ({
  String text,
  List<StyledRun> runs,
  List<InlineBoxSpec> boxes,
  List<RubyAnnotation> rubies,
});
typedef _OccupiedRange = ({
  double left,
  double right,
  double flowLeft,
  double flowRight,
});
typedef _LineBatch = ({int taken, double height});
typedef _TableFit = ({PageBlock? block, int end, double leading});

/// 一次浮动分页的局部流状态；退出或取消后整份状态随作业释放。
class _FloatPagination {
  _FloatPagination(this.layout, this.blocks);

  final ChapterPageLayout layout;
  final List<PageBlock> blocks;
  final pages = <PageContent>[];
  var slices = <PageBlockSlice>[];
  final occupancy = FloatOccupancy();
  late final List<double?> nextFlowLeading;
  var y = 0.0;
  var hasFlowOnPage = false;
  var lastContentBottom = 0.0;
  var lastBottomMargin = 0.0;
  var topPadding = 0.0;

  double get width => layout.snapshot.width;
  double get height => layout.snapshot.height - topPadding;
  LayoutBudget get budget => layout.budget;

  Future<List<PageContent>> run() async {
    topPadding = await layout._chapterTopPadding(blocks);
    nextFlowLeading = await _nextLeading();
    for (var index = 0; index < blocks.length; index++) {
      await budget.checkpoint();
      index += await _layoutBlock(blocks[index], index);
    }
    if (slices.isNotEmpty || pages.isEmpty) await closePage();
    budget.check();
    return pages;
  }

  Future<int> _layoutBlock(PageBlock block, int index) async {
    if (block.absolute) {
      _addAbsolute(block);
    } else if (block.floatSide != null) {
      if (block.floatBox != null || block.groupId >= 500000) {
        final group = block.groupId >= 500000
            ? await _floatGroup(index)
            : [block];
        await _addFloatGroup(group, index);
        return group.length - 1;
      }
      await _addFloat(block, index);
    } else {
      await _layoutFlowBlock(block, index);
    }
    return 0;
  }

  Future<void> _layoutFlowBlock(PageBlock block, int index) async {
    await _applyClear(block);
    await _keepWithNext(block, index);
    final rows = block.table == null ? 0 : Paginator.splittableTableRows(block);
    if (rows > 1) {
      await _layoutTable(block, rows);
    } else if (block.layout.lineCount == 0 ||
        block.table != null ||
        block.layout.text.isEmpty) {
      await _layoutAtomic(block);
    } else if ((block.height - block.measuredHeight).abs() > 0.5 ||
        block.clipsContent) {
      await _layoutDeclaredBox(block);
    } else {
      await _layoutText(block);
    }
  }

  Future<List<double?>> _nextLeading() async {
    final result = List<double?>.filled(blocks.length, null);
    double? upcoming;
    for (var i = blocks.length - 1; i >= 0; i--) {
      await budget.checkpoint();
      result[i] = upcoming;
      if (!blocks[i].absolute && blocks[i].floatSide == null) {
        upcoming = blocks[i].leadingExtent;
      }
    }
    return result;
  }

  void noteFlow(double contentBottom, double bottomMargin) {
    hasFlowOnPage = true;
    lastContentBottom = contentBottom;
    lastBottomMargin = bottomMargin;
  }

  Future<void> closePage() async {
    for (var index = slices.length - 1; index >= 0; index--) {
      await budget.checkpoint();
      final last = slices[index];
      if (last.overlay) continue;
      final decoration = last.block.containerBottomInset(last.endLine);
      slices[index] = last.withBottomDecoration(decoration);
      y += decoration;
      break;
    }
    pages.add(
      PageContent(
        spineIndex: layout.snapshot.spineIndex,
        pageIndex: pages.length,
        slices: List.unmodifiable(slices),
        usedHeight: y,
        pageHeight: layout.snapshot.height,
        topPadding: topPadding,
      ),
    );
    slices = <PageBlockSlice>[];
    y = 0;
    topPadding = 0;
    hasFlowOnPage = false;
    lastContentBottom = lastBottomMargin = 0;
    occupancy.clear();
  }

  double leadingOf(PageBlock block, {bool starts = true}) =>
      (starts ? block.leadingExtent : 0) +
      (hasFlowOnPage ? 0 : block.containerTopInset(starts ? 0 : 1));

  Future<double> prepareAtomicBlock(PageBlock block) async {
    final bottom = block.containerBottomInset(block.layout.lineCount);
    if (y > 0 &&
        y + leadingOf(block) + block.height + block.trailingExtent + bottom >
            height) {
      await closePage();
    }
    return leadingOf(block);
  }

  void _addAbsolute(PageBlock block) {
    slices.add(
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: block.layout.lineCount,
        height: block.height,
        overlay: true,
        absoluteTop: (block.absoluteTop ?? y)
            .clamp(0.0, math.max(0.0, height - 1))
            .toDouble(),
        leftInset: block.absoluteLeft ?? 0,
      ),
    );
  }

  _FloatRegion floatRegion(PageBlock block) {
    final left =
        (block.floatBox?.containingLeft ?? block.floatContainingLeft ?? 0.0)
            .clamp(0.0, width)
            .toDouble();
    return (
      left: left,
      width:
          (block.floatBox?.containingWidth ??
                  block.floatContainingWidth ??
                  width)
              .clamp(0.0, math.max(0.0, width - left))
              .toDouble(),
    );
  }

  Future<double> occupiedLeftWithin(
    double top,
    double bottom,
    double left,
  ) async {
    var used = 0.0;
    for (final item in occupancy.items) {
      await budget.checkpoint();
      if (item.side == FloatSide.left &&
          item.rect.top < bottom &&
          item.rect.bottom > top) {
        used = math.max(used, item.rect.right - left);
      }
    }
    return math.max(0.0, used);
  }

  Future<double> occupiedRightWithin(
    double top,
    double bottom,
    double right,
  ) async {
    var used = 0.0;
    for (final item in occupancy.items) {
      await budget.checkpoint();
      if (item.side == FloatSide.right &&
          item.rect.top < bottom &&
          item.rect.bottom > top) {
        used = math.max(used, right - item.rect.left);
      }
    }
    return math.max(0.0, used);
  }

  Future<double> _maxBottom(FloatSide side) async {
    var bottom = 0.0;
    for (final item in occupancy.items) {
      await budget.checkpoint();
      if (item.side == side) bottom = math.max(bottom, item.rect.bottom);
    }
    return bottom;
  }

  /// 同行能容纳就并排，否则依次尝试已有浮动底边，保留原位置决策。
  Future<_FloatPosition> placeFloat(
    double preferredTop,
    _FloatSize size,
    FloatSide side,
    _FloatRegion region,
  ) async {
    final rows = <double>{preferredTop};
    for (final item in occupancy.items) {
      await budget.checkpoint();
      if (item.rect.bottom > preferredTop + 0.01) rows.add(item.rect.bottom);
    }
    final ordered = rows.toList()..sort();
    for (final top in ordered) {
      await budget.checkpoint();
      final leftUsed = await occupiedLeftWithin(
        top,
        top + size.height,
        region.left,
      );
      final rightUsed = await occupiedRightWithin(
        top,
        top + size.height,
        region.left + region.width,
      );
      if (leftUsed + rightUsed + size.width <= region.width + 0.5) {
        return (
          top: top,
          x: side == FloatSide.left
              ? region.left + leftUsed
              : region.left + region.width - rightUsed - size.width,
        );
      }
    }
    return (top: math.max(preferredTop, await _maxBottom(side)), x: 0.0);
  }

  Future<List<PageBlock>> _floatGroup(int index) async {
    final first = blocks[index];
    final group = <PageBlock>[first];
    for (var next = index + 1; next < blocks.length; next++) {
      await budget.checkpoint();
      if (blocks[next].groupId != first.groupId ||
          blocks[next].floatSide != first.floatSide) {
        break;
      }
      group.add(blocks[next]);
    }
    return group;
  }

  _FloatWidth _floatWidth(
    PageBlock block,
    _FloatRegion region, {
    bool grouped = false,
  }) {
    final container = grouped ? block.floatBox?.container : null;
    if (container != null) {
      final margin = container.style.margin;
      return (
        occupied: math.min(region.width, container.width + margin.horizontal),
        leftSpace: margin.left,
        marginLeft: container.left,
      );
    }
    final style = block.style;
    final inset = style == null
        ? 0.0
        : style.padding.horizontal +
              style.borders.left.width +
              style.borders.right.width;
    final content = block.layout.maxWidth.isFinite
        ? math.min(block.layout.maxWidth, region.width)
        : block.layout.width;
    final border = math.min(region.width, content + inset);
    final marginLeft = style?.margin.left ?? 0;
    final marginRight = style?.margin.right ?? 0;
    final gap = !grouped && block.layout.text.isEmpty ? 8.0 : 0.0;
    final left = grouped || block.floatSide == FloatSide.left
        ? marginLeft
        : math.max(marginLeft, gap);
    final right = grouped || block.floatSide == FloatSide.right
        ? marginRight
        : math.max(marginRight, gap);
    return (
      occupied: math.min(region.width, left + border + right),
      leftSpace: left,
      marginLeft: marginLeft,
    );
  }

  double _flowPosition(PageBlock block, int index) {
    final parents = block.floatParentMargins;
    if (hasFlowOnPage) {
      return lastContentBottom +
          (parents == null
              ? lastBottomMargin
              : parents.collapseWith(lastBottomMargin));
    }
    // 后继在流块已经消费父边距，不能再次折叠负值；没有后继时才直接使用。
    return (nextFlowLeading[index] ?? parents?.extent ?? 0) +
        block.containerTopInset(0);
  }

  Future<_FloatGroupGeometry> _groupHeight(List<PageBlock> group) async {
    final tops = <double>[];
    final floatBox = group.first.floatBox;
    final container = floatBox?.container;
    var cursor = container == null
        ? 0.0
        : container.topDecoration + group.first.spaceBefore;
    for (var index = 0; index < group.length; index++) {
      await budget.checkpoint();
      final member = group[index];
      if (index > 0) {
        cursor += math.max(group[index - 1].spaceAfter, member.spaceBefore);
      }
      tops.add(cursor);
      cursor += member.topInset + member.height + member.bottomInset;
    }
    final measuredHeight =
        cursor +
        (container == null
            ? 0
            : container.bottomDecoration + group.last.spaceAfter);
    return (
      tops: tops,
      height: floatBox == null
          ? measuredHeight
          : _floatContainerHeight(floatBox, measuredHeight),
    );
  }

  double _floatContainerHeight(PageFloatBox box, double measuredHeight) {
    final model = BoxModel.fromStyle(
      box.container.style,
      containingWidth: box.containingWidth,
    );
    // 浮动包含块未保留确定高度，沿用盒模型的百分比解算基准。
    final contentHeight = model.resolveContentHeight(
      measuredHeight - model.verticalInset,
      containingHeight: 0,
    );
    return model.borderBoxHeight(contentHeight);
  }

  ({double top, double bottom}) _floatGroupMargins(List<PageBlock> group) {
    final margin = group.first.floatBox?.container.style.margin;
    return (
      top: margin?.top ?? group.first.spaceBefore,
      bottom: margin?.bottom ?? group.last.spaceAfter,
    );
  }

  Future<void> _addFloatGroup(List<PageBlock> group, int index) async {
    final first = group.first;
    final last = group.last;
    final region = floatRegion(first);
    final dimensions = _floatWidth(first, region, grouped: true);
    final geometry = await _groupHeight(group);
    final margins = _floatGroupMargins(group);
    final top = margins.top;
    final bottom = margins.bottom;
    if (y > 0 &&
        _flowPosition(first, index) +
                top +
                geometry.height +
                bottom +
                last.containerBottomInset(last.layout.lineCount) >
            height) {
      await closePage();
    }
    final placement = await placeFloat(
      _flowPosition(first, index) + top,
      (width: dimensions.occupied, height: geometry.height + bottom),
      first.floatSide!,
      region,
    );
    await _appendFloatGroup(group, placement, dimensions, geometry);
  }

  Future<void> _appendFloatGroup(
    List<PageBlock> group,
    _FloatPosition placement,
    _FloatWidth dimensions,
    _FloatGroupGeometry geometry,
  ) async {
    final margins = _floatGroupMargins(group);
    final top = margins.top;
    final bottom = margins.bottom;
    final source = group.first.floatBox?.container;
    final container = source == null
        ? null
        : PageContainer(
            style: source.style,
            left: placement.x + dimensions.leftSpace,
            width: source.width,
          );
    _occupyFloatGroup(group.first, placement, dimensions.occupied, (
      top: top,
      height: geometry.height,
      bottom: bottom,
    ));
    for (var member = 0; member < group.length; member++) {
      await budget.checkpoint();
      final block = _floatGroupBlock(group, member, container);
      slices.add(
        PageBlockSlice(
          block: block,
          startLine: 0,
          endLine: block.layout.lineCount,
          height: block.topInset + block.height + block.bottomInset,
          leadingExtent: block.topInset,
          trailingExtent: block.bottomInset,
          overlay: true,
          absoluteTop: topPadding + placement.top + geometry.tops[member],
          leftInset: math.max(
            0.0,
            placement.x + dimensions.leftSpace - dimensions.marginLeft,
          ),
        ),
      );
    }
  }

  void _occupyFloatGroup(
    PageBlock first,
    _FloatPosition placement,
    double occupiedWidth,
    ({double top, double height, double bottom}) extent,
  ) {
    occupancy.insert(
      BoxOccupied(
        rect: Rect.fromLTWH(
          placement.x,
          placement.top - extent.top,
          occupiedWidth,
          extent.top + extent.height + extent.bottom,
        ),
        baseline: placement.top,
        side: first.floatSide!,
      ),
    );
  }

  PageBlock _floatGroupBlock(
    List<PageBlock> group,
    int index,
    PageContainer? container,
  ) {
    final block = group[index];
    if (container == null) return block;
    final first = index == 0;
    final last = index == group.length - 1;
    return block.withSpacing(
      containers: [
        ...block.containers,
        PageContainerFragment(
          container: container,
          startsHere: first,
          endsHere: last,
          topInset: first
              ? block.topInset + block.spaceBefore + container.topDecoration
              : 0,
          bottomInset: last
              ? block.bottomInset +
                    block.spaceAfter +
                    container.bottomDecoration
              : 0,
        ),
      ],
    );
  }

  Future<void> _addFloat(PageBlock block, int index) async {
    final region = floatRegion(block);
    final dimensions = _floatWidth(block, region);
    final overlayHeight = block.topInset + block.height + block.bottomInset;
    if (y > 0 &&
        _flowPosition(block, index) +
                block.spaceBefore +
                overlayHeight +
                block.containerBottomInset(block.layout.lineCount) >
            height) {
      await closePage();
    }
    final placement = await placeFloat(
      _flowPosition(block, index) + block.spaceBefore,
      (width: dimensions.occupied, height: overlayHeight),
      block.floatSide!,
      region,
    );
    _occupyFloat(block, placement, dimensions);
    _appendFloatSlice(block, placement, dimensions, overlayHeight);
  }

  void _occupyFloat(
    PageBlock block,
    _FloatPosition placement,
    _FloatWidth dimensions,
  ) {
    final style = block.style;
    final ownTop = style == null
        ? 0.0
        : style.padding.top +
              (style.borders.top.isVisible ? style.borders.top.width : 0);
    final ownBottom = style == null
        ? 0.0
        : style.padding.bottom +
              (style.borders.bottom.isVisible ? style.borders.bottom.width : 0);
    occupancy.insert(
      BoxOccupied(
        rect: Rect.fromLTWH(
          placement.x,
          placement.top + block.topInset - ownTop,
          dimensions.occupied,
          ownTop + block.height + ownBottom,
        ),
        baseline: placement.top,
        side: block.floatSide!,
      ),
    );
  }

  void _appendFloatSlice(
    PageBlock block,
    _FloatPosition placement,
    _FloatWidth dimensions,
    double overlayHeight,
  ) {
    slices.add(
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: block.layout.lineCount,
        height: overlayHeight,
        leadingExtent: block.topInset,
        trailingExtent: block.bottomInset,
        overlay: true,
        absoluteTop: topPadding + placement.top,
        leftInset: math.max(
          0.0,
          placement.x + dimensions.leftSpace - dimensions.marginLeft,
        ),
      ),
    );
  }

  Future<void> _applyClear(PageBlock block) async {
    final clear = block.style?.clear ?? CssClear.none;
    if (clear == CssClear.none) return;
    var bottom = y;
    if (clear == CssClear.left || clear == CssClear.both) {
      bottom = math.max(bottom, await _maxBottom(FloatSide.left));
    }
    if (clear == CssClear.right || clear == CssClear.both) {
      bottom = math.max(bottom, await _maxBottom(FloatSide.right));
    }
    await _removeSatisfied(bottom);
    if (bottom > y) {
      final delta = bottom - y;
      slices.add(
        PageBlockSlice(
          block: _clearSpacer(block, delta),
          startLine: 0,
          endLine: 1,
          height: delta,
        ),
      );
      y = bottom;
    }
  }

  Future<void> _removeSatisfied(double bottom) async {
    final items = occupancy.items;
    occupancy.clear();
    for (final item in items) {
      await budget.checkpoint();
      if (item.rect.bottom > bottom) occupancy.insert(item);
    }
  }

  PageBlock _clearSpacer(PageBlock block, double delta) => PageBlock(
    layout: TextLayoutResult(
      text: '',
      lines: [
        LineBox(
          start: 0,
          end: 0,
          top: 0,
          height: delta,
          baseline: delta,
          width: width,
        ),
      ],
      width: width,
      height: delta,
      maxWidth: width,
      runs: const [],
    ),
    containers: containerFragmentsFor(block, starts: false, ends: false),
  );

  Future<void> _keepWithNext(PageBlock block, int index) async {
    final extent =
        leadingOf(block) +
        math.max(block.height, block.layout.height) +
        block.trailingExtent;
    if (!block.breakAfterAvoid ||
        y <= 0 ||
        index + 1 >= blocks.length ||
        extent > height) {
      return;
    }
    PageBlock? next;
    for (var candidate = index + 1; candidate < blocks.length; candidate++) {
      await budget.checkpoint();
      if (!blocks[candidate].absolute && blocks[candidate].floatSide == null) {
        next = blocks[candidate];
        break;
      }
    }
    if (next == null || next.pageBreakBefore || block.pageBreakAfter) return;
    final need =
        next.leadingExtent +
        (next.layout.lines.isEmpty ? 0.0 : next.layout.lines.first.height) +
        (next.layout.lineCount <= 1 ? next.trailingExtent : 0.0) +
        next.containerBottomInset(1);
    if (height - y < extent + need) await closePage();
  }

  Future<void> _layoutTable(PageBlock block, int rows) async {
    final headers = Paginator.tableHeaderRows(block);
    var start = 0;
    while (start < rows) {
      await budget.checkpoint();
      final first = start == 0 && headers > 0
          ? math.min(rows, headers + 1)
          : start + 1;
      final fit = await _fitTableRows(block, start, first, rows);
      if (fit.block == null && y > 0) {
        await closePage();
        continue;
      }
      final piece =
          fit.block ??
          await Paginator.tablePieceAsync(
            block,
            start,
            first,
            checkpoint: budget.checkpoint,
          );
      _appendTablePiece(
        piece,
        fit.block == null ? leadingOf(piece) : fit.leading,
      );
      start = fit.block == null ? first : fit.end;
      if (start < rows) await closePage();
    }
    if (block.pageBreakAfter) await closePage();
  }

  Future<_TableFit> _fitTableRows(
    PageBlock block,
    int start,
    int first,
    int rows,
  ) async {
    var end = start;
    var leading = 0.0;
    for (var candidate = first; candidate <= rows; candidate++) {
      await budget.checkpoint();
      final piece = Paginator.tablePieceMetrics(block, start, candidate);
      final nextLeading =
          piece.leading + (hasFlowOnPage ? 0 : piece.topDecoration);
      if (y +
              nextLeading +
              piece.height +
              piece.trailing +
              piece.bottomDecoration >
          height + 0.01) {
        break;
      }
      end = candidate;
      leading = nextLeading;
    }
    if (end == start) return (block: null, end: start, leading: 0.0);
    final piece = await Paginator.tablePieceAsync(
      block,
      start,
      end,
      checkpoint: budget.checkpoint,
    );
    return (block: piece, end: end, leading: leading);
  }

  void _appendTablePiece(PageBlock piece, double leading) {
    final extent = leading + piece.height + piece.trailingExtent;
    slices.add(
      PageBlockSlice(
        block: piece,
        startLine: 0,
        endLine: 1,
        height: extent,
        leadingExtent: leading,
        trailingExtent: piece.trailingExtent,
        leftInset: piece.leftInset,
      ),
    );
    noteFlow(
      y + leading + piece.height,
      piece.style?.margin.bottom ?? piece.spaceAfter,
    );
    y += extent;
  }

  Future<void> _layoutAtomic(PageBlock block) async {
    final leading = await prepareAtomicBlock(block);
    slices.add(
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: block.layout.lineCount,
        height: leading + block.height + block.trailingExtent,
        leadingExtent: leading,
        trailingExtent: block.trailingExtent,
        leftInset: block.leftInset,
      ),
    );
    noteFlow(
      y + leading + block.height,
      block.style?.margin.bottom ?? block.spaceAfter,
    );
    y += leading + block.height + block.trailingExtent;
  }

  Future<void> _layoutDeclaredBox(PageBlock block) async {
    final leading = await prepareAtomicBlock(block);
    final style = block.style ?? layout._style;
    final available = math.max(24.0, style.contentBoxWidth(width));
    final flowLeft = block.leftInset + style.margin.left;
    final left = await occupiedLeftWithin(y, y + block.height, flowLeft);
    final right = await occupiedRightWithin(
      y,
      y + block.height,
      flowLeft + available,
    );
    final narrowed = math.max(24.0, available - left - right);
    final measured = await layout._relayoutFloatText(block, style, narrowed);
    final taken = block.clipsContent
        ? visibleLineCountWithinHeight(measured.lines, block.height)
        : measured.lineCount;
    if (taken > 0) {
      final segment = await _declaredLayout(
        block,
        measured,
        taken,
        narrowed,
        left,
      );
      _appendDeclaredBox(block, segment, leading);
    }
    noteFlow(
      y + leading + block.height,
      block.style?.margin.bottom ?? block.spaceAfter,
    );
    y += leading + block.height + block.trailingExtent;
  }

  void _appendDeclaredBox(
    PageBlock block,
    TextLayoutResult segment,
    double leading,
  ) {
    slices.add(
      PageBlockSlice(
        block: _declaredBlock(block, segment),
        startLine: 0,
        endLine: segment.lineCount,
        height: leading + block.height + block.trailingExtent,
        leadingExtent: leading,
        trailingExtent: block.trailingExtent,
        leftInset: block.leftInset,
      ),
    );
  }

  Future<TextLayoutResult> _declaredLayout(
    PageBlock block,
    TextLayoutResult measured,
    int taken,
    double narrowed,
    double left,
  ) async {
    final lines = <LineBox>[];
    var visibleHeight = 0.0;
    for (final line in measured.lines.take(taken)) {
      await budget.checkpoint();
      visibleHeight += line.height;
      lines.add(line.copyWith(offsetX: line.offsetX + left));
    }
    final text = block.layout.text.substring(0, lines.last.end);
    return TextLayoutResult(
      text: text,
      lines: lines,
      width: narrowed,
      height: visibleHeight,
      maxWidth: narrowed,
      runs: sliceTextRuns(measured, 0, text.length),
      plainTextLayout: measured.plainTextLayout,
    );
  }

  PageBlock _declaredBlock(PageBlock block, TextLayoutResult segment) =>
      PageBlock(
        layout: segment,
        style: block.style,
        pageBreakBefore: block.pageBreakBefore,
        pageBreakAfter: block.pageBreakAfter,
        startCfi: block.startCfi,
        textRuleEligible: block.textRuleEligible,
        breakInsideAvoid: block.breakInsideAvoid,
        breakAfterAvoid: block.breakAfterAvoid,
        leftInset: block.leftInset,
        topInset: block.topInset,
        bottomInset: block.bottomInset,
        containers: block.containers,
        effectiveOpacity: block.effectiveOpacity,
        declaredContentHeight: block.height,
        footnotes: block.footnotes,
      );

  Future<void> _layoutText(PageBlock block) async {
    final style = block.style ?? layout._style;
    final available = math.max(24.0, style.contentBoxWidth(width));
    var cursor = 0;
    while (cursor < block.layout.text.length) {
      await budget.checkpoint();
      final leading = leadingOf(block, starts: cursor == 0);
      final page = await _fillTextPage(
        block,
        style,
        available,
        leading,
        cursor,
      );
      cursor = page.cursor;
      if (page.lines.isNotEmpty) {
        await _appendTextPage(block, page, available, leading);
      }
      if (page.blockedUntil case final bottom?) {
        await _advanceBlockedText(
          block,
          bottom,
          leadingOf(block, starts: cursor == 0),
        );
      } else if (cursor < block.layout.text.length) {
        await closePage();
      }
    }
  }

  Future<void> _advanceBlockedText(
    PageBlock block,
    double bottom,
    double leading,
  ) async {
    final nextY = math.min(height, bottom - leading);
    final delta = nextY - y;
    if (delta > 0) {
      slices.add(
        PageBlockSlice(
          block: _clearSpacer(block, delta),
          startLine: 0,
          endLine: 1,
          height: delta,
        ),
      );
      y = nextY;
    }
    if (y + leading >= height - .01) await closePage();
  }

  Future<_TextPage> _fillTextPage(
    PageBlock block,
    ComputedStyle style,
    double available,
    double leading,
    int start,
  ) async {
    final page = _TextPage(start);
    while (page.cursor < block.layout.text.length) {
      await budget.checkpoint();
      final input = await _measureAvailableText(
        block,
        style,
        available,
        page,
        y + leading + page.height,
      );
      if (input == null) break;
      final (measured: measured, range: range) = input;
      // 核心断行不为段尾 LF 产出空行，但原文仍保留 LF 和字符偏移。
      // 消费这些不绘制的尾字符，避免下一页对空行表取 first。
      if (measured.lines.isEmpty &&
          block.layout.text.codeUnits
              .skip(page.cursor)
              .every((unit) => unit == 10)) {
        page.cursor = block.layout.text.length;
        break;
      }
      var batch = await _takeBatchLines(block, measured, page, leading, range);
      if (batch.taken == 0) {
        if (y > 0 || page.lines.isNotEmpty) break;
        batch = (taken: 1, height: measured.lines.first.height);
      }
      await _appendBatch(
        page,
        measured,
        batch,
        range.left,
        block.layout.text.length,
      );
    }
    return page;
  }

  Future<({TextLayoutResult measured, _OccupiedRange range})?>
  _measureAvailableText(
    PageBlock block,
    ComputedStyle style,
    double available,
    _TextPage page,
    double lineY,
  ) async {
    final range = await _rangeAt(block, style, available, lineY);
    page.blockedUntil = await _blockedLineBottom(
      block,
      style,
      available,
      range,
      lineY,
    );
    if (page.blockedUntil != null) return null;
    final narrowed = math.max(24.0, available - range.left - range.right);
    final measured = await layout._relayoutFloatText(
      block,
      style,
      narrowed,
      start: page.cursor,
    );
    return (measured: measured, range: range);
  }

  /// 浮动把行宽占满或压到断行下限以下时等待，不能扩宽后叠到图片上。
  Future<double?> _blockedLineBottom(
    PageBlock block,
    ComputedStyle style,
    double available,
    _OccupiedRange range,
    double lineY,
  ) async {
    if (range.left <= 0 && range.right <= 0) return null;
    final minimum = math.min(available, LineBreaker().effectiveWidth(style, 0));
    final remaining = available - range.left - range.right;
    if (remaining > .5 && remaining + .5 >= minimum) return null;
    final probeBottom = lineY + block.layout.lines.first.height;
    var bottom = double.infinity;
    for (final item in occupancy.items) {
      await budget.checkpoint();
      final rect = item.rect;
      if (rect.top < probeBottom &&
          rect.bottom > lineY + .01 &&
          rect.left < range.flowRight &&
          rect.right > range.flowLeft) {
        bottom = math.min(bottom, rect.bottom);
      }
    }
    return bottom.isFinite ? bottom : null;
  }

  Future<_OccupiedRange> _rangeAt(
    PageBlock block,
    ComputedStyle style,
    double available,
    double lineY,
  ) async {
    final left = block.leftInset + style.margin.left;
    final right = left + available;
    final probe = block.layout.lines.first.height;
    return (
      left: await occupiedLeftWithin(lineY, lineY + probe, left),
      right: await occupiedRightWithin(lineY, lineY + probe, right),
      flowLeft: left,
      flowRight: right,
    );
  }

  Future<_LineBatch> _takeBatchLines(
    PageBlock block,
    TextLayoutResult measured,
    _TextPage page,
    double leading,
    _OccupiedRange range,
  ) async {
    var taken = 0;
    var batchHeight = 0.0;
    final narrowed = range.left > 0 || range.right > 0;
    while (taken < measured.lineCount) {
      await budget.checkpoint();
      final line = measured.lines[taken];
      final finished = page.cursor + line.end >= block.layout.text.length;
      final bottom =
          block.containerBottomInset(finished ? block.layout.lineCount : 0) +
          (finished ? block.trailingExtent : 0);
      final nextY = y + leading + page.height + batchHeight;
      if (nextY + line.height + bottom > height) break;
      final left = await occupiedLeftWithin(
        nextY,
        nextY + line.height,
        range.flowLeft,
      );
      final right = await occupiedRightWithin(
        nextY,
        nextY + line.height,
        range.flowRight,
      );
      if ((left > 0 || right > 0) != narrowed ||
          (narrowed && (left != range.left || right != range.right))) {
        break;
      }
      batchHeight += line.height;
      taken += 1;
    }
    return (taken: taken, height: batchHeight);
  }

  Future<void> _appendBatch(
    _TextPage page,
    TextLayoutResult measured,
    _LineBatch batch,
    double left,
    int textLength,
  ) async {
    for (var index = 0; index < batch.taken; index++) {
      await budget.checkpoint();
      page.lines.add(
        await _shiftLine(
          measured.lines[index],
          page.cursor,
          page.height,
          left,
          textLength,
        ),
      );
    }
    page.height += batch.height;
    page.cursor += measured.lines[batch.taken - 1].end;
  }

  Future<LineBox> _shiftLine(
    LineBox line,
    int cursor,
    double top,
    double left,
    int textLength,
  ) async {
    return LineBox(
      start: cursor + line.start,
      end: cursor + line.end,
      top: top + line.top,
      height: line.height,
      baseline: top + line.baseline,
      width: line.width,
      indent: line.indent,
      isLastLine: cursor + line.end >= textLength,
      offsetX: line.offsetX + left,
      justifyExtra: line.justifyExtra,
      justifyMode: line.justifyMode,
      spacing: line.spacing,
      isHardBreak: line.isHardBreak,
      ellipsized: line.ellipsized,
      ellipsisWidth: line.ellipsisWidth,
      hyphenated: line.hyphenated,
      hyphenWidth: line.hyphenWidth,
      inlineBoxes: await _shiftInlineBoxes(line.inlineBoxes, cursor),
    );
  }

  Future<List<InlineBoxPlacement>> _shiftInlineBoxes(
    List<InlineBoxPlacement> boxes,
    int cursor,
  ) async {
    final result = <InlineBoxPlacement>[];
    for (final box in boxes) {
      await budget.checkpoint();
      result.add(
        InlineBoxPlacement(
          offset: box.offset + cursor,
          left: box.left,
          width: box.width,
          height: box.height,
          ascent: box.ascent,
          descent: box.descent,
          spec: box.spec.atOffset(box.offset + cursor),
        ),
      );
    }
    return result;
  }

  Future<void> _appendTextPage(
    PageBlock block,
    _TextPage page,
    double available,
    double leading,
  ) async {
    final finished = page.cursor >= block.layout.text.length;
    final trailing = finished ? block.trailingExtent : 0.0;
    slices.add(
      PageBlockSlice(
        block: await _textBlock(block, page, available),
        startLine: 0,
        endLine: page.lines.length,
        height: leading + page.height + trailing,
        leadingExtent: leading,
        trailingExtent: trailing,
        leftInset: block.leftInset,
      ),
    );
    noteFlow(
      y + leading + page.height,
      block.style?.margin.bottom ?? block.spaceAfter,
    );
    y += leading + page.height + trailing;
  }

  Future<PageBlock> _textBlock(
    PageBlock block,
    _TextPage page,
    double available,
  ) async {
    final images = await _imagesBefore(block, page.lines.last.end);
    final rubies = await _rubiesBefore(block, page.lines.last.end);
    return PageBlock(
      layout: page.toLayout(block, available),
      style: block.style,
      pageBreakBefore: block.pageBreakBefore,
      pageBreakAfter: block.pageBreakAfter,
      startCfi: block.startCfi,
      textRuleEligible: block.textRuleEligible,
      breakInsideAvoid: block.breakInsideAvoid,
      breakAfterAvoid: block.breakAfterAvoid,
      leftInset: block.leftInset,
      topInset: block.topInset,
      bottomInset: block.bottomInset,
      containers: containerFragmentsFor(
        block,
        starts: page.lines.first.start == 0,
        ends: page.cursor >= block.layout.text.length,
      ),
      inlineImages: images,
      rubies: rubies,
      effectiveOpacity: block.effectiveOpacity,
      footnotes: block.footnotes,
    );
  }

  Future<List<InlineImageSpec>> _imagesBefore(PageBlock block, int end) async {
    final result = <InlineImageSpec>[];
    for (final image in block.inlineImages) {
      await budget.checkpoint();
      if (image.offset < end) result.add(image);
    }
    return result;
  }

  Future<List<RubyAnnotation>> _rubiesBefore(PageBlock block, int end) async {
    final result = <RubyAnnotation>[];
    for (final ruby in block.rubies ?? const <RubyAnnotation>[]) {
      await budget.checkpoint();
      if (ruby.start < end) result.add(ruby);
    }
    return result;
  }
}

/// 本页某段正文已经接纳的行；原文游标跨批次推进，行顶始终相对本段。
class _TextPage {
  _TextPage(this.cursor);

  int cursor;
  double height = 0;
  double? blockedUntil;
  final lines = <LineBox>[];

  TextLayoutResult toLayout(PageBlock block, double width) => TextLayoutResult(
    text: block.layout.text.substring(0, lines.last.end),
    lines: List<LineBox>.unmodifiable(lines),
    width: width,
    height: height,
    maxWidth: width,
    runs: block.layout.runs,
    plainTextLayout: block.layout.plainTextLayout,
  );
}
