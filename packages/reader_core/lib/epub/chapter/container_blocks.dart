import 'dart:collection';
import 'dart:math' as math;

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/block_flow.dart' show collapseMargins;
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/text_aggregator.dart';

/// 纯行内浮动段落的独立格式化上下文；分页时保留内部浮动与段落高度。
class InlineFloatContainer extends PageContainer {
  const InlineFloatContainer({
    required super.style,
    required super.left,
    required super.width,
  });
}

/// 相邻外边距折叠，但浮动/绝对定位块不参与（CSS 2.1 §8.3.1：浮动元素
/// 的 margin 不与任何相邻 margin 折叠），也不打断相邻在流兄弟的折叠
///——把它们先摘出来，只折叠连续的在流块，再放回原位。
///
/// 之前直接对整条块链折叠，浮动的段前/段后距被挪到邻居身上，多行浮动
/// 段落的静态位置因此偏了十几像素（38-float-clear）。
List<PageBlock> collapseMarginsIgnoringFloats(List<PageBlock> blocks) {
  final work = _MarginCollapseWork(blocks);
  for (final _ in work.steps()) {}
  return work.result;
}

/// 逐块、逐容器边界检查预算，完成之前不替换调用者的块列表。
Future<List<PageBlock>> collapseMarginsIgnoringFloatsAsync(
  List<PageBlock> blocks, {
  Future<void> Function()? checkpoint,
}) async {
  final work = _MarginCollapseWork(blocks);
  await _consumeContainerSteps(work.steps(), checkpoint);
  return work.result;
}

/// 已折叠前缀的末个在流块和尾部空块链仍可能随下一块改变，保留在途。
int stableMarginPrefixLength(List<PageBlock> blocks) {
  for (var index = blocks.length - 1; index >= 0; index--) {
    final block = blocks[index];
    if (!block.absolute &&
        block.floatSide == null &&
        !_isSelfCollapsingEmptyBlock(block)) {
      return index;
    }
  }
  return 0;
}

/// 浮动分页会把一段拆为多个块，仍保留容器真实首末标记供装饰占位使用。
List<PageContainerFragment> containerFragmentsFor(
  PageBlock block, {
  required bool starts,
  required bool ends,
}) => [
  for (final fragment in block.containers)
    _preserveExternalMarginEdges(
      fragment,
      PageContainerFragment(
        container: fragment.container,
        startsHere: starts && fragment.startsHere,
        endsHere: ends && fragment.endsHere,
        topInset: fragment.topInset,
        bottomInset: fragment.bottomInset,
      ),
    ),
];

/// 外边距已与子块边距分开；只供本文件折叠阶段识别，不引入公共布局字段。
class _ExternalMarginFragment extends PageContainerFragment {
  _ExternalMarginFragment(
    PageContainerFragment source,
    this.separateTop,
    this.separateBottom,
  ) : super(
        container: source.container,
        startsHere: source.startsHere,
        endsHere: source.endsHere,
        topInset: source.topInset,
        bottomInset: source.bottomInset,
      );

  final bool separateTop;
  final bool separateBottom;
}

PageContainerFragment _preserveExternalMarginEdges(
  PageContainerFragment source,
  PageContainerFragment replacement,
) => source is _ExternalMarginFragment
    ? _ExternalMarginFragment(
        replacement,
        source.separateTop,
        source.separateBottom,
      )
    : replacement;

/// 有块级后代的在流容器保留盒结构，浮动和特殊排版仍走各自路径。
bool retainsContainer(BlockNode node, ComputedStyle style) {
  const tags = {
    'div',
    'section',
    'article',
    'aside',
    'main',
    'header',
    'footer',
    'blockquote',
    'figure',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  };
  final splitInlineFlow =
      node is PromotedBlockNode ||
      node.children.any((child) => child is PromotedBlockNode);
  return (tags.contains(node.tag) || splitInlineFlow) &&
      node.children.any((child) => child is BlockNode) &&
      style.cssFloat == CssFloat.none &&
      (style.position == CssPosition.static ||
          style.position == CssPosition.relative) &&
      style.writingMode == CssWritingMode.horizontalTb;
}

/// Flex 直接子项的公共盒。卡片类容器在 `_wrapContainerBlocks` 后
/// 会挂到每个后代块上，取所有成员的共同前缀即可还原该子项背景。
PageContainer? commonFlexItemContainer(List<PageBlock> item) {
  if (item.isEmpty || item.first.containers.isEmpty) {
    return null;
  }
  var count = item.first.containers.length;
  for (final block in item.skip(1)) {
    count = math.min(count, block.containers.length);
    for (var index = 0; index < count; index += 1) {
      if (!identical(
        block.containers[index].container,
        item.first.containers[index].container,
      )) {
        count = index;
        break;
      }
    }
    if (count == 0) {
      return null;
    }
  }
  return item.first.containers.first.container;
}

/// 横排分页默认闭合带框容器；作者的显式 slice 优先。
bool clonesContainerDecoration(ComputedStyle style) {
  final value =
      (style.values['box-decoration-break'] ??
              style.values['-webkit-box-decoration-break'])
          ?.trim()
          .toLowerCase();
  if (value == 'slice') return false;
  return value == 'clone' || style.borders.hasBorder;
}

/// 卡片开头的短标题跟随至少一行正文，不把整个长卡片锁为不可分组。
bool isContainerHeading(PageBlock block) {
  if (block.absolute || block.floatSide != null) return false;
  final table = block.table;
  if (table != null) {
    return table.rowYs.length == 2 &&
        table.cells.isNotEmpty &&
        table.cells.every((cell) => cell.layout.lineCount <= 2);
  }
  final hasText =
      block.layout.text.trim().isNotEmpty ||
      block.layout.lines.any(
        (line) => line.inlineBoxes.any((box) {
          final payload = box.spec.payload;
          return payload is PageBlock && payload.layout.text.trim().isNotEmpty;
        }),
      );
  return hasText && block.layout.lineCount > 0 && block.layout.lineCount <= 2;
}

/// 竖排和分栏尚未按各自分页轴预留续框空间，仍保持切片语义。
List<PageBlock> configureContainerDecoration(List<PageBlock> blocks) {
  final work = _ContainerDecorationWork(blocks);
  for (final _ in work.steps()) {}
  return work.result;
}

/// 发现特殊分页轴和替换每个容器片段时共用同步算法的预算边界。
Future<List<PageBlock>> configureContainerDecorationAsync(
  List<PageBlock> blocks, {
  Future<void> Function()? checkpoint,
}) async {
  final work = _ContainerDecorationWork(blocks);
  await _consumeContainerSteps(work.steps(), checkpoint);
  return work.result;
}

Future<void> _consumeContainerSteps(
  Iterable<int> steps,
  Future<void> Function()? checkpoint,
) async {
  await checkpoint?.call();
  for (final _ in steps) {
    await checkpoint?.call();
  }
  await checkpoint?.call();
}

/// 浮动和定位块保持原位，在流邻居只修改实际需要折叠的那一对。
class _MarginCollapseWork {
  _MarginCollapseWork(this.source);

  final List<PageBlock> source;
  final _blocks = <PageBlock>[];
  var _flowCount = 0;
  int? _previous;
  FloatParentMargins? _pendingFloatParentMargins;
  FloatParentMargins? _pendingEmptyMargins;
  PageBlock? _lastEmptyBlock;
  final _pendingFloatIndices = <int>[];
  bool _parentMarginChanged = false;
  List<PageBlock> get result =>
      _flowCount < 2 && !_parentMarginChanged ? source : _blocks;

  Iterable<int> steps() sync* {
    for (final current in source) {
      yield 0;
      if (current.floatSide != null || current.absolute) {
        if (current.floatParentMargins case final parents?) {
          _pendingFloatParentMargins =
              _pendingFloatParentMargins?.merge(parents) ?? parents;
          _pendingFloatIndices.add(_blocks.length);
        }
        _blocks.add(current);
        continue;
      }
      _flowCount += 1;
      if (_isSelfCollapsingEmptyBlock(current)) {
        yield* _emptyBlock(current);
        continue;
      }
      yield* _flowBlock(current);
    }
    if (_lastEmptyBlock case final block?) {
      _blocks.add(
        block.withSpacing(
          spaceBefore: _pendingEmptyMargins!.extent,
          spaceAfter: 0,
        ),
      );
    }
  }

  Iterable<int> _emptyBlock(PageBlock block) sync* {
    var margins = _pendingEmptyMargins ?? const FloatParentMargins();
    if (_previous case final index?) {
      final previous = _blocks[index];
      final boundary = _MarginBoundary(previous, block);
      yield* boundary.steps();
      if (!boundary.blocked) {
        margins = margins.include(previous.spaceAfter);
        _blocks[index] = previous.withSpacing(spaceAfter: 0);
      }
    }
    _pendingEmptyMargins = margins
        .include(block.spaceBefore)
        .include(block.spaceAfter);
    _lastEmptyBlock = block;
    _parentMarginChanged = true;
  }

  Iterable<int> _flowBlock(PageBlock current) sync* {
    double? previousMargin;
    if (_previous case final previousIndex?) {
      final previous = _blocks[previousIndex];
      final boundary = _MarginBoundary(previous, current);
      yield* boundary.steps();
      if (previous.spaceAfter != 0 && !boundary.blocked) {
        previousMargin = previous.spaceAfter;
        _blocks[previousIndex] = previous.withSpacing(spaceAfter: 0);
      }
    }
    final pending = _pendingEmptyMargins == null
        ? _pendingFloatParentMargins
        : _pendingFloatParentMargins?.merge(_pendingEmptyMargins!) ??
              _pendingEmptyMargins;
    final parents = pending
        ?.include(previousMargin ?? 0)
        .include(current.spaceBefore);
    if (parents != null) yield* _retainParentMargins(parents);
    final before = parents != null
        ? parents.extent
        : previousMargin == null
        ? current.spaceBefore
        : collapseMargins(previousMargin, current.spaceBefore);
    _pendingFloatParentMargins = null;
    _pendingEmptyMargins = null;
    _lastEmptyBlock = null;
    if ((parents != null || previousMargin != null) &&
        before != current.spaceBefore) {
      current = current.withSpacing(spaceBefore: before);
      _parentMarginChanged = true;
    }
    _blocks.add(current);
    _previous = _blocks.length - 1;
  }

  Iterable<int> _retainParentMargins(FloatParentMargins parents) sync* {
    for (final index in _pendingFloatIndices) {
      yield 0;
      final block = _blocks[index];
      if (!identical(block.floatParentMargins, parents)) {
        _blocks[index] = block.withSpacing(floatParentMargins: parents);
        _parentMarginChanged = true;
      }
    }
    _pendingFloatIndices.clear();
  }
}

/// 无行内容、装饰或独立高度的空块，上下外边距可穿透折叠。
bool _isSelfCollapsingEmptyBlock(PageBlock block) =>
    block.layout.text.isEmpty &&
    block.layout.lines.every((line) => line.height == 0) &&
    block.height == 0 &&
    block.topInset == 0 &&
    block.bottomInset == 0 &&
    !block.pageBreakBefore &&
    !block.pageBreakAfter &&
    block.floatSide == null &&
    !block.absolute &&
    block.style != null &&
    block.style!.clear == CssClear.none &&
    containerCollapsesMargins(block.style!);

/// 容器装饰隔断内部段距；已分离的外部兄弟边距仍参与折叠。
class _MarginBoundary {
  _MarginBoundary(this.previous, this.current);

  final PageBlock previous;
  final PageBlock current;
  bool blocked = false;

  Iterable<int> steps() sync* {
    for (final fragment in previous.containers) {
      yield 0;
      final style = fragment.container.style;
      if (fragment.endsHere &&
          style.padding.bottom + style.borders.bottom.width > 0 &&
          !(fragment is _ExternalMarginFragment && fragment.separateBottom)) {
        blocked = true;
        return;
      }
    }
    for (final fragment in current.containers) {
      yield 0;
      final style = fragment.container.style;
      if (fragment.startsHere &&
          style.padding.top + style.borders.top.width > 0 &&
          !(fragment is _ExternalMarginFragment && fragment.separateTop)) {
        blocked = true;
        return;
      }
    }
  }
}

class _ContainerDecorationWork {
  _ContainerDecorationWork(this.source);

  final List<PageBlock> source;
  final _replacements = HashMap<PageContainer, PageContainer>.identity();
  final _blocks = <PageBlock>[];
  bool _special = false;
  List<PageBlock> get result => _special ? _blocks : source;

  Iterable<int> steps() sync* {
    yield* _findSpecial();
    if (_special) yield* _rewriteBlocks();
  }

  Iterable<int> _findSpecial() sync* {
    for (final block in source) {
      yield 0;
      if (_specialStyle(block.style)) {
        _special = true;
        return;
      }
      for (final fragment in block.containers) {
        yield 0;
        if (_specialStyle(fragment.container.style)) {
          _special = true;
          return;
        }
      }
    }
  }

  static bool _specialStyle(ComputedStyle? style) =>
      style != null &&
      (style.writingMode != CssWritingMode.horizontalTb ||
          (style.columnCount ?? 1) > 1 ||
          (style.columnWidth != null && !style.columnWidth!.isAuto));

  Iterable<int> _rewriteBlocks() sync* {
    for (final block in source) {
      yield 0;
      if (block.containers.isEmpty) {
        _blocks.add(block);
        continue;
      }
      final fragments = <PageContainerFragment>[];
      yield* _rewriteFragments(block.containers, fragments);
      _blocks.add(block.withSpacing(containers: fragments));
    }
  }

  Iterable<int> _rewriteFragments(
    List<PageContainerFragment> source,
    List<PageContainerFragment> target,
  ) sync* {
    for (final fragment in source) {
      yield 0;
      final container = fragment.container;
      final sliced = _replacements.putIfAbsent(
        container,
        () => container is InlineFloatContainer
            ? InlineFloatContainer(
                style: container.style,
                left: container.left,
                width: container.width,
              )
            : PageContainer(
                style: container.style,
                left: container.left,
                width: container.width,
                isPageRoot: container.isPageRoot,
              ),
      );
      target.add(
        _preserveExternalMarginEdges(
          fragment,
          PageContainerFragment(
            container: sliced,
            startsHere: fragment.startsHere,
            endsHere: fragment.endsHere,
            topInset: fragment.topInset,
            bottomInset: fragment.bottomInset,
          ),
        ),
      );
    }
  }
}

/// 容器是否可与首个/末个在流子块折叠上下外边距。
///
/// 建立独立块格式化上下文的盒子（浮动、定位、非 visible overflow、
/// inline-block/table/flex 等）不折叠；普通 block/list-item 才折叠。
bool containerCollapsesMargins(ComputedStyle style) {
  final blockLevel =
      style.display == CssDisplay.block || style.display == CssDisplay.listItem;
  return blockLevel &&
      style.cssFloat == CssFloat.none &&
      style.position != CssPosition.absolute &&
      style.position != CssPosition.fixed &&
      style.overflow == CssOverflow.visible;
}

/// 只改宽/最大宽的重建：`writingMode`/`isRtl` 必须一起带上，否则下游
/// （绘制/选区/分页）会把竖排块当横排处理（35-writing-mode 曾因此走错
/// 绘制路径）。
TextLayoutResult pageBlockWithLayoutWidth(
  TextLayoutResult source, {
  double? width,
  double? maxWidth,
}) => TextLayoutResult(
  text: source.text,
  lines: source.lines,
  width: width ?? source.width,
  height: source.height,
  maxWidth: maxWidth ?? source.maxWidth,
  runs: source.runs,
  isRtl: source.isRtl,
  writingMode: source.writingMode,
  plainTextLayout: source.plainTextLayout,
  firstLineStyle: source.firstLineStyle,
  firstLineRuns: source.firstLineRuns,
  sourceRuns: source.sourceRuns,
  inputOffsets: source.inputOffsets,
);

/// 容器垂直占位按预算挂到首末后代，保留原有 margin 折叠顺序。
Future<void> wrapContainerBlocks(
  List<PageBlock> blocks,
  int start,
  PageContainer container, {
  double? paragraphSpacing,
  Future<void> Function()? checkpoint,
}) async {
  if (start == blocks.length) return;
  // 先在父内容盒内折叠空块边距，再把父装饰挂到实际首末子块上。
  if (blocks.skip(start).any(_isSelfCollapsingEmptyBlock)) {
    final children = await collapseMarginsIgnoringFloatsAsync(
      blocks.sublist(start),
      checkpoint: checkpoint,
    );
    blocks.replaceRange(start, blocks.length, children);
  }
  final style = container.style;
  final top = style.padding.top + style.borders.top.width;
  final bottom = style.padding.bottom + style.borders.bottom.width;
  // 含浮动的容器，上内边距必须先作为独立在流空间推进游标。若直接
  // 挂在首个在流块上，浮动仍按填充前的游标定位，后续浮动（气泡）
  // 又会把整段内边距计入静态位置，消息间距会被放大。
  var hasFloatChild = false;
  var hasOutOfFlowChild = false;
  for (var index = start; index < blocks.length; index++) {
    await checkpoint?.call();
    hasOutOfFlowChild =
        hasOutOfFlowChild ||
        blocks[index].floatSide != null ||
        blocks[index].absolute;
    if (blocks[index].floatSide != null) {
      hasFloatChild = true;
      break;
    }
  }
  // 容器上内边距必须落在第一个在流块上：浮动块由独立覆盖层绘制，
  // 把顶部留白挂在浮动上只会推移覆盖层，不会推进正文游标，标题/名字
  // 会和头像错位。下内边距同理优先交给最后一个在流块。
  var topTarget = start;
  var hasFlowChild = false;
  for (var i = start; i < blocks.length; i++) {
    await checkpoint?.call();
    if (blocks[i].floatSide == null && !blocks[i].absolute) {
      topTarget = i;
      hasFlowChild = true;
      break;
    }
  }
  var bottomTarget = start;
  for (var i = blocks.length - 1; i >= start; i--) {
    await checkpoint?.call();
    if (blocks[i].floatSide == null && !blocks[i].absolute) {
      bottomTarget = i;
      break;
    }
  }
  // 无上边框/内边距的块容器与首个在流子块发生外边距折叠：父、子 margin
  // 取较大者，而不是相加。保留在 spaceBefore 上还能继续与外层折叠。
  final containerCollapses =
      paragraphSpacing == null && containerCollapsesMargins(style);
  final collapseTop = top == 0 && containerCollapses;
  final collapseBottom = bottom == 0 && containerCollapses;
  final startsWithFloat = blocks[start].floatSide != null;
  // clear 隔断父子上边距折叠。先在流中消费父边距，所有浮动共享同一
  // 静态位置，后面的 clear 只补足浮动高度，不再次消费这段父留白。
  final separatesFloatMargin =
      startsWithFloat &&
      hasFlowChild &&
      style.margin.top != 0 &&
      (blocks[topTarget].style?.clear ?? CssClear.none) != CssClear.none;
  final hasTopSpacer = hasFloatChild && (top > 0 || separatesFloatMargin);
  if (hasTopSpacer) {
    blocks.insert(
      start,
      _floatContainerTopSpacer(container, paragraphSpacing ?? style.margin.top),
    );
    start += 1;
    topTarget += 1;
    bottomTarget += 1;
  }
  final floatParentTop = !hasTopSpacer && startsWithFloat && collapseTop;
  final floatParentBottom = floatParentTop && !hasFlowChild && collapseBottom;
  if (floatParentTop) {
    await _retainLeadingFloatMargins(
      blocks,
      start,
      const FloatParentMargins()
          .include(style.margin.top)
          .include(floatParentBottom ? style.margin.bottom : 0),
      checkpoint,
    );
  }
  final separateExternalMargins =
      paragraphSpacing == null &&
      (!hasOutOfFlowChild || container is InlineFloatContainer) &&
      style.writingMode == CssWritingMode.horizontalTb &&
      (style.columnCount ?? 1) <= 1 &&
      (style.columnWidth == null || style.columnWidth!.isAuto) &&
      (style.display == CssDisplay.block ||
          style.display == CssDisplay.listItem);
  final separateTop = separateExternalMargins && top > 0;
  final separateBottom = separateExternalMargins && bottom > 0;
  // 绝对定位子块不决定父盒首尾；含浮动的容器继续保留浮动包围范围。
  final boxStart = hasFlowChild && !hasFloatChild ? topTarget : start;
  final boxEnd = hasFlowChild && !hasFloatChild
      ? bottomTarget
      : blocks.length - 1;
  for (var i = start; i < blocks.length; i++) {
    await checkpoint?.call();
    final block = blocks[i];
    final first = i == start;
    final last = i == blocks.length - 1;
    blocks[i] = block.withSpacing(
      breakAfterAvoid:
          block.breakAfterAvoid ||
          (first && !last && isContainerHeading(block)),
      spaceBefore: first && separateTop && !hasTopSpacer
          ? style.margin.top
          : first && collapseTop && !hasTopSpacer && !floatParentTop
          ? collapseMargins(style.margin.top, block.spaceBefore)
          : block.spaceBefore,
      spaceAfter: last && separateBottom
          ? style.margin.bottom
          : last && collapseBottom && !floatParentBottom
          ? collapseMargins(block.spaceAfter, style.margin.bottom)
          : block.spaceAfter,
      topInset:
          block.topInset +
          (i == topTarget
              ? (hasTopSpacer ? 0 : top) +
                    (separateTop
                        ? block.spaceBefore
                        : hasTopSpacer || collapseTop
                        ? 0
                        : (paragraphSpacing ?? style.margin.top))
              : 0),
      bottomInset:
          block.bottomInset +
          (i == bottomTarget
              ? bottom +
                    (separateBottom
                        ? block.spaceAfter
                        : collapseBottom
                        ? 0
                        : (paragraphSpacing ?? style.margin.bottom))
              : 0),
      containers: [
        _ExternalMarginFragment(
          PageContainerFragment(
            container: container,
            startsHere: i == boxStart && !hasTopSpacer,
            endsHere: i == boxEnd,
            topInset: i == boxStart && !hasTopSpacer
                ? block.leadingExtent + top
                : 0,
            bottomInset: i == boxEnd ? block.trailingExtent + bottom : 0,
          ),
          separateTop,
          separateBottom,
        ),
        ...block.containers,
      ],
    );
  }
}

PageBlock _floatContainerTopSpacer(PageContainer container, double margin) =>
    PageBlock(
      spaceBefore: margin,
      layout: TextLayoutResult(
        text: '',
        lines: const <LineBox>[],
        width: container.contentWidth,
        height: container.topDecoration,
        maxWidth: container.contentWidth,
        runs: const <StyledRun>[],
      ),
      containers: <PageContainerFragment>[
        _ExternalMarginFragment(
          PageContainerFragment(container: container, startsHere: true),
          container is InlineFloatContainer,
          false,
        ),
      ],
    );

/// 父边距与浮动自己的段距分开，折叠阶段再与首个在流子块一起解算。
Future<void> _retainLeadingFloatMargins(
  List<PageBlock> blocks,
  int start,
  FloatParentMargins parents,
  Future<void> Function()? checkpoint,
) async {
  for (var index = start; index < blocks.length; index++) {
    await checkpoint?.call();
    final block = blocks[index];
    if (block.floatSide == null && !block.absolute) break;
    if (block.floatSide == null) continue;
    blocks[index] = block.withSpacing(
      floatParentMargins: block.floatParentMargins?.merge(parents) ?? parents,
    );
  }
}
