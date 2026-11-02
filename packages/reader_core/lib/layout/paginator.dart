import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../css/computed_style.dart';
import '../epub/footnote.dart' show NoteKind;
import '../src/api/models.dart' show CancelToken, PageSlice;
import 'block_flow.dart' show collapseMargins;
import 'box_model.dart';
import 'float_occupancy.dart' show FloatSide;
import 'page_background.dart';
import 'table_layout.dart' show TableCellRender, TableRenderSpec;
import 'text_layout.dart';
import 'text_edges.dart';

/// 行内图片（P9-06）：占位符下标 + 已解析成书内路径的图片地址。
class InlineImageSpec {
  /// 创建行内图片。
  const InlineImageSpec({
    required this.offset,
    required this.url,
    this.width,
    this.height,
    this.aspectRatio,
  });

  /// 占位符在块文本中的下标（UTF-16）。
  final int offset;

  /// 书内资源路径（绘制层用 imageLookup 查解码图）。
  final String url;

  /// 书籍 CSS 声明的显示宽（逻辑像素，null 表示按行高 1em 等比）。
  final double? width;

  /// 书籍 CSS 声明的显示高（逻辑像素）。
  final double? height;

  /// 书籍 CSS 声明的首选宽高比；null 表示沿用图片原始比例。
  final double? aspectRatio;
}

/// 正文中的可点击注释引用。
///
/// [start]/[end] 是块文本坐标（UTF-16，半开区间）；图片注号用占位符
/// `U+FFFC` 的一个字符区间表示。正文定义块已被过滤，弹窗只消费这里的
/// 文本和书内图片路径。
class PageFootnote {
  /// 创建注释引用。
  const PageFootnote({
    required this.start,
    required this.end,
    required this.label,
    required this.kind,
    this.text,
    this.imageUrls = const <String>[],
  });

  /// 引用起始偏移。
  final int start;

  /// 引用结束偏移。
  final int end;

  /// 注号文字。
  final String label;

  /// 注释类型。
  final NoteKind kind;

  /// 注释正文。
  final String? text;

  /// 注释内图片。
  final List<String> imageUrls;

  /// 是否命中当前块文本偏移。
  bool contains(int offset) =>
      offset >= start && (offset < end || (start == end && offset == start));
}

/// 分页前保留的容器盒；后代共享实例，以便每页按嵌套顺序绘制。
class PageContainer {
  const PageContainer({
    required this.style,
    required this.left,
    required this.width,
    this.cloneDecoration = false,
    this.isPageRoot = false,
  });

  final ComputedStyle style;
  final double left;
  final double width;

  /// 每页片段独立保留边框与内边距；默认沿用 CSS slice 行为。
  final bool cloneDecoration;

  /// 分页根容器的 overflow 按整页裁剪，不把多看出血截回正文区。
  final bool isPageRoot;

  double get topDecoration => style.padding.top + style.borders.top.width;
  double get bottomDecoration =>
      style.padding.bottom + style.borders.bottom.width;

  double get contentLeft =>
      left + style.borders.left.width + style.padding.left;
  double get contentWidth => math.max(
    0,
    width -
        style.padding.horizontal -
        style.borders.left.width -
        style.borders.right.width,
  );
}

/// 一个文本块在祖先容器中的位置；距离均以本块内容区为基准。
class PageContainerFragment {
  const PageContainerFragment({
    required this.container,
    this.startsHere = false,
    this.endsHere = false,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  final PageContainer container;
  final bool startsHere;
  final bool endsHere;
  final double topInset;
  final double bottomInset;
}

/// 内容盒高度内可见的行数。
///
/// 行顶落在内容盒内时，即使整行放不下也会画出可见部分；下一行从盒底或
/// 盒底以下开始时才裁掉。至少保留 1 行，避免零高盒死循环。
int visibleLineCountWithinHeight(List<LineBox> lines, double boxHeight) {
  var used = 0.0;
  var count = 0;
  for (final line in lines) {
    if (used >= boxHeight + 0.5 && count > 0) {
      break;
    }
    used += line.height;
    count += 1;
  }
  return count;
}

/// 一个待分页的文本块。
class PageBlock {
  /// 创建块。
  const PageBlock({
    required this.layout,
    this.pageBreakBefore = false,
    this.pageBreakAfter = false,
    this.startCfi,
    this.endCfi,
    this.style,
    this.spaceBefore = 0,
    this.spaceAfter = 0,
    this.topInset = 0,
    this.bottomInset = 0,
    this.leftInset = 0,
    this.breakInsideAvoid = false,
    this.breakAfterAvoid = false,
    this.listMarker,
    this.groupId = 0,
    this.table,
    this.floatSide,
    this.floatContainingLeft,
    this.floatContainingWidth,
    this.rubies,
    this.inlineImages = const <InlineImageSpec>[],
    this.footnotes = const <PageFootnote>[],
    this.absolute = false,
    this.absoluteTop,
    this.absoluteLeft,
    this.bleedLeft = false,
    this.bleedRight = false,
    this.bleedTop = false,
    this.bleedBottom = false,
    this.containerSides = false,
    this.containers = const <PageContainerFragment>[],
    this.declaredContentHeight,
    this.effectiveOpacity = 1,
    this.multicol,
  });

  /// 按样式创建块：padding/border 折算成内缩，参与分页几何（P2-14 补全）。
  ///
  /// [containingWidth] 是百分比 padding 的解算基准（通常是正文区宽）；
  /// [groupId] 为整组不可切标记（P7-26，同组连续块是原子单元）。
  factory PageBlock.styled({
    required TextLayoutResult layout,
    required ComputedStyle style,
    required double containingWidth,
    bool? pageBreakBefore,
    bool? pageBreakAfter,
    String? startCfi,
    String? endCfi,
    double? spaceBefore,
    double? spaceAfter,
    int groupId = 0,
    String? listMarker,
    List<RubyAnnotation>? rubies,
    List<InlineImageSpec> inlineImages = const <InlineImageSpec>[],
    List<PageFootnote> footnotes = const <PageFootnote>[],
    TableRenderSpec? table,
    bool absolute = false,
    double? absoluteTop,
    double? absoluteLeft,
    bool bleedLeft = false,
    bool bleedRight = false,
    bool bleedTop = false,
    bool bleedBottom = false,
    bool containerSides = false,
    double? effectiveOpacity,
    double? declaredContentHeight,
  }) {
    final model = BoxModel.fromStyle(style, containingWidth: containingWidth);
    return PageBlock(
      layout: layout,
      style: style,
      pageBreakBefore: pageBreakBefore ?? style.pageBreakBefore,
      pageBreakAfter: pageBreakAfter ?? style.pageBreakAfter,
      breakInsideAvoid: style.breakInsideAvoid,
      breakAfterAvoid: style.breakAfterAvoid,
      startCfi: startCfi,
      endCfi: endCfi,
      // 调用方没给段距时按自身 margin 折（表格/图片块走这里；正文块显式传）。
      spaceBefore: spaceBefore ?? style.margin.top,
      spaceAfter: spaceAfter ?? style.margin.bottom,
      topInset: model.borders.top + model.padding.top,
      bottomInset: model.borders.bottom + model.padding.bottom,
      leftInset: model.borders.left + model.padding.left,
      groupId: groupId,
      listMarker: listMarker,
      rubies: rubies,
      inlineImages: inlineImages,
      footnotes: footnotes,
      table: table,
      absolute: absolute,
      absoluteTop: absoluteTop,
      absoluteLeft: absoluteLeft,
      bleedLeft: bleedLeft,
      bleedRight: bleedRight,
      bleedTop: bleedTop,
      bleedBottom: bleedBottom,
      containerSides: containerSides,
      // 未显式传入时沿用计算样式的祖先累计不透明度（T3 只在容器分支显式传）。
      effectiveOpacity: effectiveOpacity ?? style.effectiveOpacity,
      // 盒高约束（CSS height/min-height/max-height）：先按声明值解算，
      // 未声明时等于测量高（行高之和）。
      declaredContentHeight:
          declaredContentHeight ??
          model.resolveContentHeight(
            layout.height,
            containingHeight: 0,
          ),
    );
  }

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

  /// 块样式（绘制用；P1-28 起可选）。
  final ComputedStyle? style;

  /// 段前间距（逻辑像素，绘制用）。
  final double spaceBefore;

  /// 段后间距（逻辑像素，绘制用）。
  final double spaceAfter;

  /// 内容区上内缩（border.top + padding.top）。
  final double topInset;

  /// 内容区下内缩（border.bottom + padding.bottom）。
  final double bottomInset;

  /// 内容区左内缩（border.left + padding.left）。
  final double leftInset;

  /// 块内禁止分页（`break-inside: avoid`）：能整块放入新页时不在当前页拆开。
  final bool breakInsideAvoid;

  /// 块后避免分页（`break-after: avoid`）：标题不落页底（P3-22）。
  final bool breakAfterAvoid;

  /// 列表标记文本（P3-23）：'•'/'1.' 等；null 非列表项。绘制在块首行
  /// 左侧 gutter（UA li margin-left 的 40px 内），由章节源按列表类型
  /// 与序号赋值。
  final String? listMarker;

  /// 整组不可切标记（P7-26）：非 0 时同组连续块是原子单元——整组放
  /// 不下当前页时整体下移；组高于整页时按序切。0 = 无组。
  final int groupId;

  /// 表格渲染载荷（flat 管线接入）：非 null 时本块是一页表格切片，
  /// layout 为空文本单行盒（高度=切片高，仅参与分页几何），绘制层
  /// 走表格分支（网格线 + 逐格文字）。
  final TableRenderSpec? table;

  /// 浮动方向（flat 管线接入）：非 null 时本块是浮动元素（通常为
  /// 图片块），由浮动感知分页登记占位并以覆盖切片渲染——不占流高。
  final FloatSide? floatSide;

  /// 浮动的包含块左缘（页面坐标）。行内浮动必须相对所在段落收窄，
  /// 不能按整页版心左右缘排布。
  final double? floatContainingLeft;

  /// 浮动的包含块宽度。
  final double? floatContainingWidth;

  /// 注音标注（P8-08）：ruby/rt 结构（主文本区间 + 注音串），
  /// 渲染层注音趟在主文本区间上方绘制（50% 字号、居中）。
  final List<RubyAnnotation>? rubies;

  /// 行内图片（P9-06）：U+FFFC 占位符位置与图片地址，绘制层按占位符
  /// 字形框画图。
  final List<InlineImageSpec> inlineImages;

  /// 正文注释引用（点击弹窗）。
  final List<PageFootnote> footnotes;

  /// 绝对定位块（P9-19）：不占流高，绘制在页内绝对坐标处。
  final bool absolute;

  /// 页内绝对 y（null 表示跟随当前流位置）。
  final double? absoluteTop;

  /// 页内绝对 x（null 表示正文左缘）。
  final double? absoluteLeft;

  /// 左出血（多看 `duokan-bleed`，P9-22）：背景/边框延伸到页面左缘。
  final bool bleedLeft;

  /// 右出血：背景/边框延伸到页面右缘。
  final bool bleedRight;

  /// 上出血（多看 `duokan-bleed` 含 top）：背景/边框延伸到页面顶缘。
  final bool bleedTop;

  /// 下出血：背景/边框延伸到页面底缘。
  final bool bleedBottom;

  /// 位于带边框容器的内部（P9-25）：背景与左右边框向上下段距延伸，让
  /// 被拆成多块的卡片/面板拼回一片，块间缝隙不露页底、边框不断开。
  final bool containerSides;

  /// 真实祖先盒，顺序为外层到内层；不把背景和边框复制到正文。
  final List<PageContainerFragment> containers;

  /// 声明高度解算后的内容盒高（`height`/`min-height`/`max-height`）；
  /// null 表示未声明，按测量高。
  ///
  /// 只由 [PageBlock.styled] 赋值：直接构造的块（垫片、覆盖切片等）沿用
  /// 测量高，行为与之前一致。
  final double? declaredContentHeight;

  /// 块内容区高度：声明高度优先（CSS 盒高约束），否则为行高之和。
  ///
  /// 大于行高之和时是块内留白（min-height/height 撑高）；小于行高之和时
  /// 表示内容溢出盒高（`height`+`max-height`），分页按盒高裁剪内容。
  double get height => declaredContentHeight ?? layout.height;

  /// 测量高（行高之和），不受盒高声明影响。
  double get measuredHeight => layout.height;

  /// 内容是否超出声明盒高。CSS 默认 `overflow: visible`，此时内容仍绘制
  /// 在盒外，只影响后续块的流位置。
  bool get hasContentOverflow => height + 0.5 < layout.height;

  /// 内容是否被盒高裁掉。只有显式设置非 `visible` 的 overflow 才裁剪；
  /// 裁剪掉的行不进入下一页。
  bool get clipsContent =>
      hasContentOverflow && style?.overflow != CssOverflow.visible;

  /// 多列几何（CSS Multicol）：只有「首列块」携带完整几何，绘制层据此画
  /// `column-rule` 与列分隔；其余列块为 null。
  final MulticolGeometry? multicol;

  /// 祖先累计不透明度（`ComputedStyle.effectiveOpacity`，1 为不透明）。
  ///
  /// flat 管线重建块样式时只带当前元素声明，父链的 opacity 会丢；章节源
  /// 在构造时把 `chainStyle(chain).effectiveOpacity` 记下来，绘制层据此
  /// 决定是否 saveLayer 合成（嵌套 opacity 必须按父累计值合成）。
  final double effectiveOpacity;

  /// 块首行之前的额外高度（段前间距 + 上内缩）。
  double get leadingExtent => spaceBefore + topInset;

  /// 块末行之后的额外高度（下内缩 + 段后间距）。
  double get trailingExtent => bottomInset + spaceAfter;

  /// 只回收普通文字的行高留白，保留装饰盒、图片和特殊基线的完整几何。
  PageTextEdges textEdgesAt(int lineIndex) {
    final computed = style;
    if (computed == null || !_canTrimTextEdges(computed)) {
      return const PageTextEdges();
    }
    final line = layout.lines[lineIndex];
    if (line.inlineBoxes.isNotEmpty ||
        layout.text.substring(line.start, line.end).trim().isEmpty) {
      return const PageTextEdges();
    }
    return textLineEdges(layout, line, computed);
  }

  bool _canTrimTextEdges(ComputedStyle computed) =>
      !(layout.isVertical ||
          absolute ||
          floatSide != null ||
          table != null ||
          multicol != null ||
          (height - measuredHeight).abs() > 0.01 ||
          computed.height != null ||
          computed.minHeight != null ||
          computed.maxHeight != null ||
          clipsContent ||
          bleedTop ||
          bleedBottom ||
          bleedLeft ||
          bleedRight ||
          listMarker != null ||
          inlineImages.isNotEmpty ||
          (rubies?.isNotEmpty ?? false) ||
          layout.runs.any((run) => run.baselineShift != 0) ||
          _hasTextEdgeDecoration(computed) ||
          layout.runs.any((run) => _hasTextEdgeDecoration(run.style)) ||
          containers.any(
            (fragment) => fragment.container.isPageRoot
                ? fragment.container.topDecoration > 0 ||
                      fragment.container.bottomDecoration > 0
                : _hasTextEdgeDecoration(fragment.container.style),
          ));

  static bool _hasTextEdgeDecoration(ComputedStyle style) =>
      style.backgroundColor.a > 0 ||
      style.backgroundImage != null ||
      style.backgroundGradient != null ||
      style.borders.hasBorder ||
      style.boxShadow != null ||
      style.textShadow.isNotEmpty ||
      style.filters.isNotEmpty ||
      style.transforms.isNotEmpty ||
      style.padding.vertical != 0;

  /// 续页首需要补上的祖先装饰；真实容器首片已含这部分占位。
  double containerTopInset(int startLine, {int? beforeDepth}) {
    var extent = 0.0;
    for (final fragment in containers.take(beforeDepth ?? containers.length)) {
      if (fragment.container.cloneDecoration &&
          !(startLine == 0 && fragment.startsHere)) {
        extent += fragment.container.topDecoration;
      }
    }
    return extent;
  }

  /// 页末继续到下一页的祖先装饰，不重复真实容器末片的占位。
  double containerBottomInset(int endLine, {int? beforeDepth}) {
    var extent = 0.0;
    final endsBlock = endLine >= layout.lineCount || clipsContent;
    for (final fragment in containers.take(beforeDepth ?? containers.length)) {
      if (fragment.container.cloneDecoration &&
          !(endsBlock && fragment.endsHere)) {
        extent += fragment.container.bottomDecoration;
      }
    }
    return extent;
  }

  /// 复制块并替换段距或容器分页占位（其余字段共享引用）。
  PageBlock withSpacing({
    double? spaceBefore,
    double? spaceAfter,
    double? topInset,
    double? bottomInset,
    List<PageContainerFragment>? containers,
    bool? breakAfterAvoid,
  }) => PageBlock(
    layout: layout,
    pageBreakBefore: pageBreakBefore,
    pageBreakAfter: pageBreakAfter,
    startCfi: startCfi,
    endCfi: endCfi,
    style: style,
    spaceBefore: spaceBefore ?? this.spaceBefore,
    spaceAfter: spaceAfter ?? this.spaceAfter,
    topInset: topInset ?? this.topInset,
    bottomInset: bottomInset ?? this.bottomInset,
    leftInset: leftInset,
    breakInsideAvoid: breakInsideAvoid,
    breakAfterAvoid: breakAfterAvoid ?? this.breakAfterAvoid,
    listMarker: listMarker,
    groupId: groupId,
    table: table,
    floatSide: floatSide,
    floatContainingLeft: floatContainingLeft,
    floatContainingWidth: floatContainingWidth,
    rubies: rubies,
    // 重建时必须带全字段（P9-19）：边距折叠会把相邻块换成新实例，
    // 漏字段会让行内图片/绝对定位在真机里随机消失。
    inlineImages: inlineImages,
    footnotes: footnotes,
    absolute: absolute,
    absoluteTop: absoluteTop,
    absoluteLeft: absoluteLeft,
    bleedLeft: bleedLeft,
    bleedRight: bleedRight,
    bleedTop: bleedTop,
    bleedBottom: bleedBottom,
    containerSides: containerSides,
    containers: containers ?? this.containers,
    declaredContentHeight: declaredContentHeight,
    effectiveOpacity: effectiveOpacity,
    multicol: multicol,
  );

  /// 相邻块上下外边距折叠（CSS 2.2 §60.3 相邻兄弟规则，与块流管线
  /// 共用 [collapseMargins]）。
  ///
  /// flat 管线原本逐块累加 `spaceAfter + spaceBefore`：正文相邻两段各有
  /// 1em 上下边距时，段距变成 2em（真机 32dp，浏览器应为 16dp）。折叠后
  /// 空隙进入下一块的 `spaceBefore`、上一块 `spaceAfter` 清零，分页几何
  /// （leading/trailing）与页索引重放因此自动一致。
  ///
  /// 幂等且最小拷贝：上一块 `spaceAfter` 已为 0 时不再重建任何块，因此
  /// 对已折叠列表返回同一批对象（`PageIndex.from` 依赖块对象身份映射
  /// 块序号，重复折叠不得更换对象）。
  static List<PageBlock> collapseAdjacentMargins(List<PageBlock> blocks) {
    if (blocks.length < 2) {
      return blocks;
    }
    final result = <PageBlock>[blocks.first];
    int? previousFlowIndex = blocks.first.absolute ? null : 0;
    for (var i = 1; i < blocks.length; i++) {
      final current = blocks[i];
      // 绝对/固定定位不占流，不能参与相邻块 margin 折叠。
      if (current.absolute) {
        result.add(current);
        continue;
      }
      if (previousFlowIndex == null) {
        result.add(current);
        previousFlowIndex = i;
        continue;
      }
      final previous = result[previousFlowIndex];
      // 容器边界处的段距属于盒内留白，不能穿过边框/内边距与外部块折叠。
      final containerBoundary =
          previous.containers.any(
            (fragment) =>
                fragment.endsHere &&
                fragment.container.style.padding.bottom +
                        fragment.container.style.borders.bottom.width >
                    0,
          ) ||
          current.containers.any(
            (fragment) =>
                fragment.startsHere &&
                fragment.container.style.padding.top +
                        fragment.container.style.borders.top.width >
                    0,
          );
      if (previous.spaceAfter == 0 || containerBoundary) {
        result.add(current);
        previousFlowIndex = i;
        continue;
      }
      result[previousFlowIndex] = previous.withSpacing(spaceAfter: 0);
      result.add(
        current.withSpacing(
          spaceBefore: collapseMargins(
            previous.spaceAfter,
            current.spaceBefore,
          ),
        ),
      );
      previousFlowIndex = i;
    }
    return result;
  }
}

/// 多列布局几何（CSS Multicol 一级近似）。
///
/// 口径（CSS Multicol §3）：
/// - `column-count` 与 `column-width` 都声明时，列数取两者折小的结果：
///   `count = min(count, floor((可用宽 + gap) / (column-width + gap)))`，
///   即 `column-width` 是「列的最小宽」；
/// - 只声明 `column-width` 时按上式折算列数；只声明 `column-count` 时列数即声明值；
/// - 列宽 = `(可用宽 − gap × (count − 1)) / count`；
/// - `column-gap: normal` 按 1em 处理。
class MulticolGeometry {
  /// 创建几何。
  const MulticolGeometry({
    required this.count,
    required this.columnWidth,
    required this.gap,
  });

  /// 列数（≥2）。
  final int count;

  /// 列宽。
  final double columnWidth;

  /// 列间距。
  final double gap;

  /// 第 [index] 列的左偏移（相对内容区左缘）。
  double leftOf(int index) => index * (columnWidth + gap);

  /// 按样式解算；未形成多列（列数 < 2 或宽度非正）时返回 null。
  static MulticolGeometry? fromStyle(
    ComputedStyle style,
    double availableWidth,
  ) {
    final declaredCount = style.columnCount ?? 0;
    final widthSpec = style.columnWidth;
    final specWidth = widthSpec?.resolve(availableWidth);
    if (declaredCount < 2 && (specWidth == null || specWidth <= 0)) {
      return null;
    }
    // column-gap: normal → 1em。
    final gapRaw = style.columnGap;
    final gap = gapRaw == null || gapRaw <= 0 ? style.fontSize : gapRaw;
    var count = declaredCount;
    if (specWidth != null && specWidth > 0) {
      final byWidth = ((availableWidth + gap) / (specWidth + gap))
          .floor()
          .clamp(1, 8);
      count = declaredCount >= 2
          ? math.min(declaredCount, math.max(1, byWidth))
          : math.max(1, byWidth);
    }
    if (count < 2) {
      return null;
    }
    final width = (availableWidth - gap * (count - 1)) / count;
    if (width <= 0) {
      return null;
    }
    return MulticolGeometry(count: count, columnWidth: width, gap: gap);
  }
}

/// 竖排按页分栏的结果：每页的列块 + 每页占用高。
class _VerticalSplit {
  const _VerticalSplit({required this.chunks, required this.pageHeight});

  /// 每页一个列块（列已按页内顺序重排 x）。
  final List<PageBlock> chunks;

  /// 每个列块在页内占用的高（= 页高或重排后的列长）。
  final double pageHeight;
}

/// 绝对定位解算结果（页内坐标 + 可能 shrink-to-fit 后的块）。
class _AbsolutePlacement {
  const _AbsolutePlacement({
    required this.block,
    required this.top,
    required this.left,
  });

  /// 参与绘制的块（宽:auto 时是重排后的新块）。
  final PageBlock block;

  /// 页内 y。
  final double top;

  /// 页内 x。
  final double left;
}

/// 页内一个块切片；P1-25 只放整块，P1-26 会按行切。
class PageBlockSlice {
  /// 创建切片。
  const PageBlockSlice({
    required this.block,
    required this.startLine,
    required this.endLine,
    required this.height,
    this.leadingExtent = 0,
    this.trailingExtent = 0,
    this.leftInset = 0,
    this.overlay = false,
    this.absoluteTop,
    this.textTopTrim = 0,
    this.textBottomTrim = 0,
  });

  /// 来源块。
  final PageBlock block;

  /// 起始行（含）。
  final int startLine;

  /// 结束行（不含）。
  final int endLine;

  /// 本切片高度（含首尾额外高度）。
  final double height;

  /// 首行之前的额外高度（段前间距 + 上内缩 - 回收的行高留白）。
  final double leadingExtent;

  /// 末行之后的额外高度（下内缩 + 段后间距 - 回收的行高留白）。
  final double trailingExtent;

  /// 仅阅读模式回收的行高留白，与作者负边距分开记录。
  final double textTopTrim;
  final double textBottomTrim;

  /// 行内容的左内缩（border.left + padding.left）。
  final double leftInset;

  /// 浮动覆盖切片（flat 管线接入）：不占流高，渲染在 [absoluteTop]
  /// 处； Paginator 的流游标跳过其高度。
  final bool overlay;

  /// 覆盖切片的页内绝对 y（非覆盖切片为 null）。
  final double? absoluteTop;

  /// 切片行。
  Iterable<LineBox> get lines =>
      block.layout.lines.skip(startLine).take(endLine - startLine);

  /// 是否从块中部开始：前面的行在上一页。
  bool get continuesBefore => startLine > 0;

  /// 是否在块中部结束：后续行在下一页。
  ///
  /// 内容被盒高裁掉（[PageBlock.clipsContent]）时后续行不会出现在下一页，
  /// 因此不算「续到下页」。
  bool get continuesAfter =>
      endLine < block.layout.lineCount && !block.clipsContent;

  /// 页面坐标系中的可见裁剪矩形（§60.8）。
  ///
  /// [top] 是切片顶边在页面上的 y；绘制与命中都要限制在这个矩形内，
  /// 跨页块因此不会画到下一页或下一块的地盘上。
  Rect clipRect(double top, double width) =>
      Rect.fromLTWH(0, top, width, height);

  /// 收页时补上已预留的下装饰，保持正文高度与其它几何信息不变。
  PageBlockSlice withBottomDecoration(double extent) => PageBlockSlice(
    block: block,
    startLine: startLine,
    endLine: endLine,
    height: height + extent,
    leadingExtent: leadingExtent,
    trailingExtent: trailingExtent + extent,
    leftInset: leftInset,
    overlay: overlay,
    absoluteTop: absoluteTop,
    textTopTrim: textTopTrim,
    textBottomTrim: textBottomTrim,
  );

  /// 收页时回收末行下方留白，不改变其它行的绘制原点。
  PageBlockSlice withTextBottomTrim(double extent) => PageBlockSlice(
    block: block,
    startLine: startLine,
    endLine: endLine,
    height: height - extent,
    leadingExtent: leadingExtent,
    trailingExtent: trailingExtent - extent,
    leftInset: leftInset,
    overlay: overlay,
    absoluteTop: absoluteTop,
    textTopTrim: textTopTrim,
    textBottomTrim: extent,
  );
}

/// 一次命中：页面坐标落在哪个切片、哪一行。
class PageHit {
  /// 创建命中结果。
  const PageHit({
    required this.sliceIndex,
    required this.slice,
    required this.lineIndex,
    required this.line,
  });

  /// 切片在页内的序号。
  final int sliceIndex;

  /// 命中的切片。
  final PageBlockSlice slice;

  /// 行在块内的序号。
  final int lineIndex;

  /// 命中的行框。
  final LineBox line;
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
    this.background,
  });

  /// 章节序号。
  final int spineIndex;

  /// 页序号（章内 0 起）。
  final int pageIndex;

  /// 本页块切片。
  final List<PageBlockSlice> slices;

  /// 已用高度（不含首页顶部偏移）。
  final double usedHeight;

  /// 页高。
  final double pageHeight;

  /// 首页相对正文区的顶部偏移；负值用于让章首出血图从整页顶部排起。
  final double topPadding;

  /// 整页背景（书籍 body/html 的 background-image，P9-04）。
  final PageBackground? background;

  /// 换一份整页背景（分页结果复用，只改绘制层）。
  PageContent withBackground(PageBackground? value) {
    if (identical(background, value)) {
      return this;
    }
    return PageContent(
      spineIndex: spineIndex,
      pageIndex: pageIndex,
      slices: slices,
      usedHeight: usedHeight,
      pageHeight: pageHeight,
      topPadding: topPadding,
      background: value,
    );
  }

  /// 是否为空页。
  bool get isEmpty => slices.isEmpty;

  /// 内容区高度（不含首页顶部留白）。
  double get contentHeight => usedHeight;

  /// 页面坐标 [offset] 命中的切片与行；内容区之外返回 null。
  ///
  /// 只搜索本页可见的行：跨页块属于上一页/下一页的行不会被命中，命中区域
  /// 因此与绘制裁剪保持一致（§60.8）。
  PageHit? hitTest(Offset offset, {double contentWidth = double.infinity}) {
    if (offset.dx < 0 || offset.dx > contentWidth) {
      return null;
    }
    final contentBottom = topPadding + usedHeight;
    if (offset.dy < topPadding || offset.dy > contentBottom) {
      return null;
    }
    var y = topPadding;
    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      if (offset.dy >= y && offset.dy < y + slice.height) {
        // 首尾内缩区不命中文字（P2-14 补全：命中几何与绘制几何一致）。
        final lineStartY = y + slice.leadingExtent;
        if (offset.dy < lineStartY) {
          return null;
        }
        var lineY = lineStartY;
        for (
          var lineIndex = slice.startLine;
          lineIndex < slice.endLine;
          lineIndex++
        ) {
          final line = slice.block.layout.lines[lineIndex];
          if (offset.dy < lineY + line.height) {
            return PageHit(
              sliceIndex: i,
              slice: slice,
              lineIndex: lineIndex,
              line: line,
            );
          }
          lineY += line.height;
        }
        return null;
      }
      y += slice.height;
    }
    return null;
  }
}

/// 一章的分页结果。
class ChapterPagination {
  /// 创建结果。
  const ChapterPagination({
    required this.spineIndex,
    required this.pages,
    required this.pageHeight,
    required this.totalHeight,
    this.truncated = false,
  });

  /// 章节序号。
  final int spineIndex;

  /// 页列表。
  final List<PageContent> pages;

  /// 页高。
  final double pageHeight;

  /// 所有块总高度。
  final double totalHeight;

  /// 是否因页数上限截断（P7-16：单章 20000 页截断，渐进提示不中断）。
  final bool truncated;
}

/// 按块推进的分页器状态机。
class Paginator {
  /// 单章页数上限（P7-16；对照 Reeden 20000 页截断防线）。
  static const int maxPagesPerChapter = 20000;

  /// 创建分页器。
  Paginator({
    required this.pageHeight,
    this.pageWidth = 0,
    this.topPadding = 0,
    this.tolerance = 2,
    this.trimTextEdges = false,
  });

  /// 阅读模式：页首、页尾不计行高留白；默认保留 CSS 完整行盒。
  final bool trimTextEdges;

  /// 页高。
  final double pageHeight;

  /// 页宽（绝对定位的包含块宽；0 表示用块内容宽兜底）。
  final double pageWidth;

  /// 章首页相对正文区的顶部偏移；负值回收章首出血图占用的上内缩。
  final double topPadding;

  /// 浮点容差（像素）。
  final double tolerance;

  /// 行高之和。
  static double _lineExtent(List<LineBox> lines) {
    var extent = 0.0;
    for (final line in lines) {
      extent += line.height;
    }
    return extent;
  }

  /// 组 [groupId] 自 [index] 起的连续成员总占高（leading+height+trailing）。
  static double _groupExtent(List<PageBlock> blocks, int index, int groupId) {
    var extent = 0.0;
    var last = blocks[index];
    for (
      var i = index;
      i < blocks.length && blocks[i].groupId == groupId;
      i++
    ) {
      last = blocks[i];
      extent +=
          blocks[i].leadingExtent + blocks[i].height + blocks[i].trailingExtent;
    }
    return extent + last.containerBottomInset(last.layout.lineCount);
  }

  /// 把 [lines] 均衡分配到 [count] 列（CSS `column-fill: balance` 近似）：
  /// 返回每列的 `[start, end)` 行区间，列高尽量相等。
  static List<(int, int)> _columnRanges(List<LineBox> lines, int count) {
    if (lines.isEmpty || count < 2) {
      return <(int, int)>[(0, lines.length)];
    }
    final total = _lineExtent(lines);
    var limit = total / count;
    for (var attempt = 0; attempt < 32; attempt++) {
      final ranges = <(int, int)>[];
      var index = 0;
      for (var column = 0; column < count - 1; column++) {
        final start = index;
        var height = 0.0;
        while (index < lines.length &&
            height + lines[index].height <= limit + 0.01) {
          height += lines[index].height;
          index += 1;
        }
        // 一行都放不下时至少取一行，避免死循环。
        if (index == start && index < lines.length) {
          height += lines[index].height;
          index += 1;
        }
        ranges.add((start, index));
      }
      ranges.add((index, lines.length));
      var tallest = 0.0;
      for (final range in ranges) {
        tallest = math.max(
          tallest,
          _lineExtent(lines.sublist(range.$1, range.$2)),
        );
      }
      if (tallest <= limit + 0.01) {
        return ranges;
      }
      limit = tallest;
    }
    return <(int, int)>[(0, lines.length)];
  }

  /// 单列子布局：把行区间重新从 0 起排（基线按行顶重算），其余字段沿用。
  static TextLayoutResult _columnLayout(
    TextLayoutResult source,
    (int, int) range,
    double columnWidth, {
    double? boxWidth,
  }) {
    // 列片段：文本取该列行区间对应的子串，行下标按子串重排（绘制直接用
    // 片段文本；CFI/选区跨列的映射由章节源按块首尾处理，见已知限制）。
    final textStart = range.$1 < range.$2 ? source.lines[range.$1].start : 0;
    final textEnd = range.$1 < range.$2 ? source.lines[range.$2 - 1].end : 0;
    final fragment = source.text.substring(
      textStart.clamp(0, source.text.length),
      textEnd.clamp(0, source.text.length),
    );
    final lines = <LineBox>[];
    var top = 0.0;
    var width = 0.0;
    for (var i = range.$1; i < range.$2; i++) {
      final line = source.lines[i];
      final ascent = line.baseline - line.top;
      lines.add(
        LineBox(
          start: line.start - textStart,
          end: line.end - textStart,
          top: top,
          height: line.height,
          baseline: top + ascent,
          width: line.width,
          indent: line.indent,
          isLastLine: line.isLastLine,
          isHardBreak: line.isHardBreak,
          offsetX: line.offsetX,
          justifyExtra: line.justifyExtra,
          justifyMode: line.justifyMode,
          spacing: line.spacing,
          ellipsized: line.ellipsized,
          ellipsisWidth: line.ellipsisWidth,
          hyphenated: line.hyphenated,
          hyphenWidth: line.hyphenWidth,
          // 行内盒（inline-block / 行内图片）随列切片平移插入点。
          inlineBoxes: <InlineBoxPlacement>[
            for (final box in line.inlineBoxes)
              if (box.offset >= textStart && box.offset < textEnd)
                InlineBoxPlacement(
                  offset: box.offset - textStart,
                  left: box.left,
                  width: box.width,
                  height: box.height,
                  ascent: box.ascent,
                  descent: box.descent,
                  spec: box.spec,
                  vertical: box.vertical,
                ),
          ],
        ),
      );
      width = math.max(width, line.advanceWidth);
      top += line.height;
    }
    // 切片行内样式区间：列片段只保留与该列文本区间相交的 run，并把偏移
    // 平移到片段坐标（否则列内加粗/斜体/颜色会整体丢失）。
    final runs = <StyledRun>[
      for (final run in source.runs)
        if (run.end > textStart && run.start < textEnd)
          StyledRun(
            start: math.max(run.start, textStart) - textStart,
            end: math.min(run.end, textEnd) - textStart,
            style: run.style,
            baselineShift: run.baselineShift,
            syntheticFontFallback: run.syntheticFontFallback,
          ),
    ];
    return TextLayoutResult(
      text: fragment,
      lines: lines,
      // 首列块代表整个多列容器：块宽取「列带总宽」（容器内容宽），
      // 其余列块取列宽；行宽仍是各自列内的实际行宽。
      width: boxWidth ?? width,
      height: top,
      maxWidth: columnWidth,
      runs: List<StyledRun>.unmodifiable(runs),
      plainTextLayout: source.plainTextLayout,
    );
  }

  /// 由源块与单列子布局构造列块；非首列作为覆盖切片（absolute 定位）。
  static PageBlock _columnBlock(
    PageBlock source,
    TextLayoutResult layout, {
    required double absoluteLeft,
    double? absoluteTop,
    MulticolGeometry? multicol,
    (int start, int end)? textRange,
  }) => PageBlock(
    layout: layout,
    startCfi: source.startCfi,
    endCfi: source.endCfi,
    style: source.style,
    topInset: source.topInset,
    bottomInset: source.bottomInset,
    leftInset: source.leftInset,
    listMarker: source.listMarker,
    groupId: source.groupId,
    bleedLeft: source.bleedLeft,
    bleedRight: source.bleedRight,
    bleedTop: source.bleedTop,
    bleedBottom: source.bleedBottom,
    containerSides: source.containerSides,
    containers: source.containers,
    effectiveOpacity: source.effectiveOpacity,
    multicol: multicol,
    // 注音/行内图片按列文本区间切片并平移到片段坐标。
    rubies: textRange == null
        ? source.rubies
        : <RubyAnnotation>[
            for (final ruby in source.rubies ?? const <RubyAnnotation>[])
              if (ruby.start < textRange.$2 && ruby.end > textRange.$1)
                RubyAnnotation(
                  start: math.max(ruby.start, textRange.$1) - textRange.$1,
                  end: math.min(ruby.end, textRange.$2) - textRange.$1,
                  text: ruby.text,
                ),
          ],
    inlineImages: textRange == null
        ? source.inlineImages
        : <InlineImageSpec>[
            for (final image in source.inlineImages)
              if (image.offset >= textRange.$1 && image.offset < textRange.$2)
                InlineImageSpec(
                  offset: image.offset - textRange.$1,
                  url: image.url,
                  width: image.width,
                  height: image.height,
                  aspectRatio: image.aspectRatio,
                ),
          ],
    footnotes: textRange == null
        ? source.footnotes
        : <PageFootnote>[
            for (final footnote in source.footnotes)
              if (footnote.start < textRange.$2 && footnote.end > textRange.$1)
                PageFootnote(
                  start: math.max(footnote.start, textRange.$1) - textRange.$1,
                  end: math.min(footnote.end, textRange.$2) - textRange.$1,
                  label: footnote.label,
                  kind: footnote.kind,
                  text: footnote.text,
                  imageUrls: footnote.imageUrls,
                ),
          ],
    // 第 2 列起脱离正常流，绘制在首列右侧（overlay 切片）。
    absolute: absoluteTop != null,
    absoluteTop: absoluteTop,
    absoluteLeft: absoluteLeft,
  );

  /// 列区间在原文里的起止偏移（用于切片注音/行内图片）。
  static (int, int) _columnTextRange(
    TextLayoutResult source,
    (int, int) range,
  ) => range.$1 < range.$2
      ? (source.lines[range.$1].start, source.lines[range.$2 - 1].end)
      : (0, 0);

  /// 绝对定位解算（CSS 2.1 §10.3.7/§10.6.4 的扁平管线口径）。
  ///
  /// - 包含块 = 页面内容盒；百分比按包含块宽/高解算；
  /// - `left` 优先于 `right`、`top` 优先于 `bottom`（over-constrained 时忽略
  ///   后者，CSS 2.1 规定 LTR 下忽略 right / 忽略 bottom）；
  /// - 都未声明时用静态位置（块本来会被排到的位置：y = 当前流游标）；
  /// - `width: auto` 时 shrink-to-fit。
  static _AbsolutePlacement _resolveAbsolute(
    PageBlock block, {
    required double containingWidth,
    required double containingHeight,
    required double staticTop,
    required double staticLeft,
  }) {
    final style = block.style;
    var prepared = style == null
        ? block
        : _shrinkToFit(block, style, containingWidth);
    final model = style == null
        ? null
        : BoxModel.fromStyle(style, containingWidth: containingWidth);
    // 块盒宽：声明宽优先（百分比按包含块解算），否则用 shrink-to-fit 结果。
    // 声明宽与已测宽不一致时按声明宽重排，保证行宽/行数与盒宽同口径。
    final declaredContentWidth =
        style != null && style.width != null && !style.width!.isAuto
        ? model!.resolveContentWidth(containingWidth)
        : null;
    if (style != null &&
        declaredContentWidth != null &&
        (prepared.layout.maxWidth - declaredContentWidth).abs() > 0.5) {
      prepared = _relayoutAt(prepared, style, declaredContentWidth);
    }
    final contentWidth =
        declaredContentWidth ??
        (prepared.layout.maxWidth.isFinite
            ? prepared.layout.maxWidth
            : prepared.layout.width);
    final outerWidth =
        contentWidth +
        (model?.horizontalInset ?? 0) +
        (model?.margin.horizontal ?? 0);
    final outerHeight =
        prepared.height +
        (model?.verticalInset ?? 0) +
        (model?.margin.vertical ?? 0);
    double? left = block.absoluteLeft;
    double? top = block.absoluteTop;
    if (style != null) {
      final leftSpec = style.left?.resolve(containingWidth);
      final rightSpec = style.right?.resolve(containingWidth);
      final topSpec = style.top?.resolve(containingHeight);
      final bottomSpec = style.bottom?.resolve(containingHeight);
      left ??= leftSpec;
      if (left == null && rightSpec != null) {
        left = containingWidth - rightSpec - outerWidth;
      }
      top ??= topSpec;
      if (top == null && bottomSpec != null) {
        top = containingHeight - bottomSpec - outerHeight;
      }
    }
    return _AbsolutePlacement(
      block: prepared,
      top: top ?? staticTop,
      left: left ?? staticLeft,
    );
  }

  /// `width: auto` 的绝对定位块做 shrink-to-fit：
  /// `min(max(min-content, 可用宽), max-content)`，再按最终宽重排。
  ///
  /// 已知限制：min-content 用「最长不可断片段」近似（空格切分；CJK 按单字
  /// 累加），不做完整 Unicode 断行分析。
  static PageBlock _shrinkToFit(
    PageBlock block,
    ComputedStyle style,
    double availableWidth,
  ) {
    if ((style.width != null && !style.width!.isAuto) ||
        block.layout.text.trim().isEmpty) {
      return block;
    }
    final model = BoxModel.fromStyle(style, containingWidth: availableWidth);
    final contentAvailable = math.max(
      0.0,
      availableWidth - model.horizontalInset - model.margin.horizontal,
    );
    final preferred = TextLayoutEngine.layout(
      text: block.layout.text,
      style: style,
      maxWidth: double.infinity,
    ).width;
    // shrink-to-fit：min(max(min-content, 可用宽), max-content)。
    final minContent = _minContentWidth(block.layout.text, style);
    final target = math.min(preferred, math.max(minContent, contentAvailable));
    if ((target - block.layout.maxWidth).abs() < 0.5) {
      return block;
    }
    return _withLayout(
      block,
      layout: TextLayoutEngine.layout(
        text: block.layout.text,
        style: style,
        maxWidth: target,
      ),
    );
  }

  /// 按指定宽重排块（绝对定位声明宽与已测宽不一致时用）。
  static PageBlock _relayoutAt(
    PageBlock block,
    ComputedStyle style,
    double width,
  ) => _withLayout(
    block,
    layout: TextLayoutEngine.layout(
      text: block.layout.text,
      style: style,
      maxWidth: width,
    ),
  );

  /// 替换行布局并完整保留块的盒、覆盖层与装饰字段。
  static PageBlock _withLayout(
    PageBlock source, {
    required TextLayoutResult layout,
  }) => PageBlock(
    layout: layout,
    pageBreakBefore: source.pageBreakBefore,
    pageBreakAfter: source.pageBreakAfter,
    startCfi: source.startCfi,
    endCfi: source.endCfi,
    style: source.style,
    spaceBefore: source.spaceBefore,
    spaceAfter: source.spaceAfter,
    topInset: source.topInset,
    bottomInset: source.bottomInset,
    leftInset: source.leftInset,
    breakInsideAvoid: source.breakInsideAvoid,
    breakAfterAvoid: source.breakAfterAvoid,
    listMarker: source.listMarker,
    groupId: source.groupId,
    table: source.table,
    floatSide: source.floatSide,
    rubies: source.rubies,
    inlineImages: source.inlineImages,
    footnotes: source.footnotes,
    absolute: source.absolute,
    absoluteTop: source.absoluteTop,
    absoluteLeft: source.absoluteLeft,
    bleedLeft: source.bleedLeft,
    bleedRight: source.bleedRight,
    bleedTop: source.bleedTop,
    bleedBottom: source.bleedBottom,
    containerSides: source.containerSides,
    containers: source.containers,
    declaredContentHeight: source.declaredContentHeight,
    effectiveOpacity: source.effectiveOpacity,
    multicol: source.multicol,
  );

  /// min-content 宽近似：最长不可断片段宽。
  static double _minContentWidth(String text, ComputedStyle style) {
    var widest = 0.0;
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) {
        return;
      }
      final segment = buffer.toString();
      buffer.clear();
      widest = math.max(
        widest,
        TextLayoutEngine.layout(
          text: segment,
          style: style,
          maxWidth: double.infinity,
        ).width,
      );
    }

    for (final rune in text.runes) {
      if (rune == 0x20 || rune == 0x09 || rune == 0x0A) {
        flush();
        continue;
      }
      buffer.writeCharCode(rune);
    }
    flush();
    return widest;
  }

  /// 可继续按行拆分的表格行数；预切表格的 [TableRenderSpec.rowYs] 从 0 起
  /// 严格递增。返回值包含表头行，供调用方在首个切片后至少取一行正文。
  static int _splittableTableRows(PageBlock block) {
    final rows = block.table?.rowYs;
    if (rows == null || rows.length < 2) {
      return 0;
    }
    for (var i = 1; i < rows.length; i++) {
      if (!rows[i].isFinite || rows[i] <= rows[i - 1] + 0.01) {
        return 0;
      }
    }
    final rowCount = rows.length - 1;
    final headerRows = math.min(block.table!.headerRowCount, rowCount);
    if (headerRows > 0) {
      // 表头之外至少还要有一行正文，且续片必须重复表头。
      return rowCount > headerRows ? rowCount : 0;
    }
    // 保留原行为：无表头的单行表格不进入二次拆分。
    return rowCount > 1 ? rowCount : 0;
  }

  /// 当前表格载荷顶部的表头行数（不超过实际行数）。
  static int _tableHeaderRows(PageBlock block) {
    final table = block.table;
    if (table == null) {
      return 0;
    }
    return math.min(table.headerRowCount, table.rowYs.length - 1);
  }

  /// 从预切表格块中截出 `[startRow, endRow)`，并把单元格和行界坐标平移到
  /// 切片顶。rowspan 格跨过分页边界时只保留可见矩形，避免续页整列消失。
  static PageBlock _tablePiece(PageBlock source, int startRow, int endRow) {
    final table = source.table!;
    final rowYs = table.rowYs;
    final rowCount = rowYs.length - 1;
    final headerRows = math.min(table.headerRowCount, rowCount);
    final headerHeight = headerRows > 0
        ? math.min(table.headerHeight, rowYs[headerRows])
        : 0.0;
    final repeatsHeader = headerRows > 0 && startRow >= headerRows;
    // 首页保留预切表格在内容盒顶部的留白（例如 Flex align-content
    // center/flex-end）；只有从后续行开始时才把该行顶平移到切片顶。
    final top = startRow == 0 ? 0.0 : rowYs[startRow];
    final bottom = rowYs[endRow];
    final headerOffset = repeatsHeader ? headerHeight : 0.0;
    final dataHeight = bottom - top;
    final height = dataHeight + headerOffset;
    final cells = <TableCellRender>[
      for (final cell in table.cells)
        if (!(repeatsHeader && cell.row < headerRows) &&
            cell.rect.bottom > top + 0.01 &&
            cell.rect.top < bottom - 0.01)
          TableCellRender(
            row: cell.row,
            rect: Rect.fromLTRB(
              cell.rect.left,
              math.max(0.0, cell.rect.top - top) + headerOffset,
              cell.rect.right,
              math.min(dataHeight, cell.rect.bottom - top) + headerOffset,
            ),
            layout: cell.layout,
            style: cell.style,
            startCfi: cell.startCfi,
          ),
    ];
    if (repeatsHeader) {
      cells.insertAll(0, [
        for (final cell in table.cells)
          if (cell.row < headerRows)
            TableCellRender(
              row: cell.row,
              rect: Rect.fromLTRB(
                cell.rect.left,
                math.max(0.0, cell.rect.top),
                cell.rect.right,
                math.min(headerHeight, cell.rect.bottom),
              ),
              layout: cell.layout,
              style: cell.style,
              startCfi: cell.startCfi,
            ),
      ]);
    }
    final layout = TextLayoutResult(
      text: source.layout.text,
      lines: <LineBox>[
        LineBox(
          start: 0,
          end: 0,
          top: 0,
          height: height,
          baseline: height,
          width: table.tableWidth,
        ),
      ],
      width: table.tableWidth,
      height: height,
      maxWidth: source.layout.maxWidth,
      runs: const <StyledRun>[],
    );
    return PageBlock(
      layout: layout,
      pageBreakBefore: startRow == 0 && source.pageBreakBefore,
      pageBreakAfter: endRow == rowCount && source.pageBreakAfter,
      startCfi: source.startCfi,
      endCfi: source.endCfi,
      style: source.style,
      spaceBefore: startRow == 0 ? source.spaceBefore : 0,
      spaceAfter: endRow == rowCount ? source.spaceAfter : 0,
      topInset: startRow == 0 ? source.topInset : 0,
      bottomInset: endRow == rowCount ? source.bottomInset : 0,
      leftInset: source.leftInset,
      breakInsideAvoid: source.breakInsideAvoid,
      breakAfterAvoid: source.breakAfterAvoid,
      listMarker: source.listMarker,
      groupId: source.groupId,
      table: TableRenderSpec(
        cells: cells,
        columnXs: table.columnXs,
        rowYs: <double>[
          if (repeatsHeader)
            for (var row = 0; row <= headerRows; row++) rowYs[row],
          for (
            var row = repeatsHeader ? startRow + 1 : startRow;
            row <= endRow;
            row += 1
          )
            rowYs[row] - top + headerOffset,
        ],
        tableWidth: table.tableWidth,
        headerRowCount: headerRows,
        headerHeight: headerHeight,
        flex: table.flex,
      ),
      containerSides: source.containerSides,
      containers: <PageContainerFragment>[
        for (final fragment in source.containers)
          PageContainerFragment(
            container: fragment.container,
            startsHere: startRow == 0 && fragment.startsHere,
            endsHere: endRow == rowCount && fragment.endsHere,
            topInset: fragment.topInset,
            bottomInset: fragment.bottomInset,
          ),
      ],
      declaredContentHeight: height,
      effectiveOpacity: source.effectiveOpacity,
      footnotes: source.footnotes,
    );
  }

  /// 竖排块按页分栏：列长 = 本页可用高重新分列 → 每页容纳
  /// `floor(页宽 / 列宽)` 列，剩余列顺延下一页。返回每页的列块与每页占高；
  /// 列长与页高一致时返回 null（调用方走整块单页路径，保持原语义）。
  _VerticalSplit? _verticalColumnChunks(PageBlock block, double available) {
    final style = block.style;
    if (style == null || pageWidth <= 0) {
      return null;
    }
    // 列长：声明 height 且放得进本页时按声明值（作者意图），否则按页高。
    final declaredHeight = style.height?.resolve(available);
    final columnLength =
        declaredHeight != null &&
            declaredHeight > 0 &&
            declaredHeight <= available
        ? declaredHeight
        : math.max(1.0, available - block.leadingExtent);
    // 屏蔽声明 height（否则 layout 会继续拿块高当列长）。
    final adjusted = ComputedStyle(
      <String, String>{'height': 'auto'},
      parent: style,
      explicitProperties: const <String>{'height'},
      hasExplicitTextColor: style.hasExplicitTextColor,
    );
    final relaid = TextLayoutEngine.layout(
      text: block.layout.text,
      style: adjusted,
      maxWidth: columnLength,
    );
    if (relaid.lineCount == 0 || relaid.lines.isEmpty) {
      return null;
    }
    final columnWidth = relaid.lines.first.width;
    if (columnWidth <= 0) {
      return null;
    }
    final perPage = math.max(1, (pageWidth / columnWidth).floor());
    final chunks = <PageBlock>[];
    var start = 0;
    while (start < relaid.lineCount) {
      final take = math.min(perPage, relaid.lineCount - start);
      chunks.add(_verticalChunk(block, relaid, start, start + take));
      start += take;
    }
    final pageHeight = math.min(
      available,
      block.leadingExtent + relaid.height + block.trailingExtent,
    );
    return _VerticalSplit(chunks: chunks, pageHeight: pageHeight);
  }

  /// 竖排分页的列块：抽出 `[start, end)` 列并把 columnX 重排到 0 起。
  static PageBlock _verticalChunk(
    PageBlock source,
    TextLayoutResult layout,
    int start,
    int end,
  ) {
    final columns = <LineBox>[];
    final count = end - start;
    final columnWidth = layout.lines.first.width;
    final rl = layout.writingMode == CssWritingMode.verticalRl;
    var offset = 0.0;
    for (var i = start; i < end; i++) {
      final line = layout.lines[i];
      // rl：首列排在最右（页内从右向左推进）；lr：从最左开始。
      final columnX = rl ? (count - 1 - (i - start)) * columnWidth : offset;
      columns.add(
        LineBox(
          start: line.start,
          end: line.end,
          top: 0,
          height: line.height,
          baseline: 0,
          width: line.width,
          offsetX: columnX,
          columnIndex: i - start,
          columnX: columnX,
          vertical: true,
          isLastLine: line.isLastLine,
          isHardBreak: line.isHardBreak,
        ),
      );
      offset += line.width;
    }
    return PageBlock(
      layout: TextLayoutResult(
        text: layout.text,
        lines: List<LineBox>.unmodifiable(columns),
        width: offset,
        height: layout.height,
        maxWidth: layout.maxWidth,
        runs: layout.runs,
        isRtl: layout.isRtl,
        writingMode: layout.writingMode,
        plainTextLayout: layout.plainTextLayout,
      ),
      startCfi: source.startCfi,
      endCfi: source.endCfi,
      style: source.style,
      topInset: source.topInset,
      bottomInset: source.bottomInset,
      leftInset: source.leftInset,
      bleedLeft: source.bleedLeft,
      bleedRight: source.bleedRight,
      bleedTop: source.bleedTop,
      bleedBottom: source.bleedBottom,
      containerSides: source.containerSides,
      containers: source.containers,
      effectiveOpacity: source.effectiveOpacity,
      footnotes: source.footnotes,
    );
  }

  /// 对一章块列表分页。
  ChapterPagination measureChapter({
    required List<PageBlock> blocks,
    int spineIndex = 0,
    int maxPages = maxPagesPerChapter,
  }) {
    final pages = <PageContent>[];
    var slices = <PageBlockSlice>[];
    var used = 0.0;
    var available = pageHeight - topPadding;
    var firstPage = true;
    var totalHeight = 0.0;
    var truncated = false;
    // 相邻块上下边距折叠（CSS 2.1 §8.3.1）：段距不再按两段 margin 相加。
    final flow = PageBlock.collapseAdjacentMargins(blocks);
    // 续框必须完整留在页面内，不能让文字容差吃掉边框和内边距。
    final fitTolerance =
        flow.any(
          (block) => block.containers.any(
            (fragment) => fragment.container.cloneDecoration,
          ),
        )
        ? 0.0
        : tolerance;

    double topCredit(PageBlock block, int startLine) =>
        trimTextEdges && slices.isEmpty && !(firstPage && topPadding < 0)
        ? block.textEdgesAt(startLine).top
        : 0;

    double leadingOf(PageBlock block, int startLine) =>
        (startLine == 0 ? block.leadingExtent : 0) +
        (slices.isEmpty ? block.containerTopInset(startLine) : 0) -
        topCredit(block, startLine);

    double bottomCredit(PageBlock block, int endLine) =>
        trimTextEdges && endLine > 0
        ? block.textEdgesAt(endLine - 1).bottom
        : 0;

    void record() {
      // 空页不记录，避免零长度页。
      if (slices.isEmpty) {
        return;
      }
      // 页数上限（P7-16）：达到上限不再产出页，丢弃在途切片并标记
      // 截断——行间收页同样受限，页数恰为上限。
      if (pages.length >= maxPages) {
        truncated = true;
        slices = <PageBlockSlice>[];
        used = 0;
        return;
      }
      // 容行时已经预留，收页才实际挂到末片；后续块仍可使用这块空间。
      final lastFlow = slices.lastIndexWhere((slice) => !slice.overlay);
      if (lastFlow >= 0) {
        final last = slices[lastFlow];
        final decoration = last.block.containerBottomInset(last.endLine);
        if (decoration > 0) {
          slices[lastFlow] = last.withBottomDecoration(decoration);
          used += decoration;
        }
        final credit = bottomCredit(last.block, last.endLine);
        if (credit > 0) {
          slices[lastFlow] = slices[lastFlow].withTextBottomTrim(credit);
          used -= credit;
        }
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

    for (var blockIndex = 0; blockIndex < flow.length; blockIndex++) {
      final block = flow[blockIndex];
      // display: none 的块不占位（P2-15）。
      if (block.style?.display == CssDisplay.none) {
        continue;
      }
      // 绝对定位块（P9-19）：脱离正常流，不占流高，只作为覆盖切片
      // 绘制在页内绝对坐标处（top/left 缺省时跟随当前流位置）。
      if (block.absolute) {
        final containingWidth = pageWidth > 0
            ? pageWidth
            : (block.layout.maxWidth.isFinite && block.layout.maxWidth > 0
                  ? block.layout.maxWidth
                  : pageHeight);
        final containingHeight = math.max(
          0.0,
          pageHeight - (firstPage ? topPadding : 0),
        );
        final resolved = _resolveAbsolute(
          block,
          containingWidth: containingWidth,
          containingHeight: containingHeight,
          staticTop: used,
          staticLeft: 0,
        );
        final top = resolved.top
            .clamp(0.0, math.max(0.0, pageHeight - 1))
            .toDouble();
        slices.add(
          PageBlockSlice(
            block: resolved.block,
            startLine: 0,
            endLine: resolved.block.layout.lineCount,
            height:
                resolved.block.leadingExtent +
                resolved.block.height +
                resolved.block.trailingExtent,
            leadingExtent: resolved.block.leadingExtent,
            trailingExtent: resolved.block.trailingExtent,
            overlay: true,
            absoluteTop: top,
            leftInset: resolved.left,
          ),
        );
        continue;
      }
      // 页数上限截断（P7-16，对照 Reeden「一章超过 20000 页，章节在
      // 这里截断」）：达到上限即停止推进，已产出页保留。
      if (pages.length >= maxPages) {
        truncated = true;
        break;
      }
      // 整组不可切（P7-26，对照 Reeden D28「图和题注、画廊整组不切开」）：
      // 组首块放不下当前页、且整组能放进一个新页时先收页整体下移；
      // 组高于整页时按序切（不强制）。
      if (block.groupId != 0 &&
          (blockIndex == 0 || flow[blockIndex - 1].groupId != block.groupId)) {
        final groupExtent = _groupExtent(flow, blockIndex, block.groupId);
        if (groupExtent > available + fitTolerance &&
            groupExtent + block.containerTopInset(0) <=
                pageHeight + fitTolerance) {
          record();
        }
      }
      totalHeight += block.height + block.leadingExtent + block.trailingExtent;
      final lines = block.layout.lines;
      // 空块（无行且无盒高）不占位；声明了高度的空块（height/min-height）
      // 仍按盒高占位。
      if (lines.isEmpty && block.height <= 0) {
        continue;
      }
      if (block.pageBreakBefore) {
        record();
      }

      // 多列（CSS Multicol §3）：按列宽重排后均衡分列；首列随正常流占高，
      // 其余列作为覆盖切片绘制在首列右侧（绘制/命中沿用 overlay 几何）。
      // 放不下当前页时走「跨页列流」：每列按本页可用高容行，一页排
      // `column-count` 列，剩余内容顺延下一页。列块按列文本区间切片
      // runs/行内盒/注音/行内图片并平移偏移。
      // 已知限制：
      // - 章节页索引（PageIndex）按原块列表记录，分栏块是合成块，重进章节
      //   时索引重放会退回整章重排（不影响正确性，只影响命中率）。
      final multicolWidth =
          block.layout.maxWidth.isFinite && block.layout.maxWidth > 0
          ? block.layout.maxWidth
          : pageHeight;
      final multicol = block.style == null || block.floatSide != null
          ? null
          : MulticolGeometry.fromStyle(block.style!, multicolWidth);
      if (multicol != null && block.layout.text.trim().isNotEmpty) {
        // 带上原块的行内样式区间：分栏重排后列内仍要保留加粗/斜体/颜色。
        final relaid = TextLayoutEngine.layout(
          text: block.layout.text,
          style: block.style!,
          maxWidth: multicol.columnWidth,
          runs: block.layout.runs,
          inlineBoxes: [
            for (final line in block.layout.lines)
              for (final box in line.inlineBoxes) box.spec.atOffset(box.offset),
          ],
          rubies: block.rubies ?? const [],
        );
        if (relaid.lineCount > 0) {
          final ranges = _columnRanges(relaid.lines, multicol.count);
          final columnHeights = <double>[
            for (final range in ranges)
              _lineExtent(relaid.lines.sublist(range.$1, range.$2)),
          ];
          var bandHeight = 0.0;
          for (final height in columnHeights) {
            bandHeight = math.max(bandHeight, height);
          }
          final extent =
              block.leadingExtent + bandHeight + block.trailingExtent;
          if (extent > available + tolerance &&
              extent <= pageHeight + tolerance &&
              slices.isNotEmpty) {
            // 整块放不进当前页：先收页，再按新页重试（record 已重置可用高）。
            record();
          }
          if (extent <= available + tolerance) {
            // 覆盖列与首列首行对齐（含首列段前/上内缩）。
            final bandTop =
                (firstPage ? topPadding : 0) + used + block.leadingExtent;
            final firstLayout = _columnLayout(
              relaid,
              ranges.first,
              multicol.columnWidth,
              boxWidth:
                  multicol.columnWidth * multicol.count +
                  multicol.gap * (multicol.count - 1),
            );
            slices.add(
              PageBlockSlice(
                block: _columnBlock(
                  block,
                  firstLayout,
                  absoluteLeft: 0,
                  multicol: multicol,
                  textRange: _columnTextRange(relaid, ranges.first),
                ),
                startLine: 0,
                endLine: firstLayout.lineCount,
                height: extent,
                leadingExtent: block.leadingExtent,
                trailingExtent: block.trailingExtent,
                leftInset: block.leftInset,
              ),
            );
            for (var column = 1; column < ranges.length; column++) {
              final left = multicol.leftOf(column);
              final layout = _columnLayout(
                relaid,
                ranges[column],
                multicol.columnWidth,
              );
              slices.add(
                PageBlockSlice(
                  block: _columnBlock(
                    block,
                    layout,
                    absoluteLeft: left,
                    absoluteTop: bandTop,
                    textRange: _columnTextRange(relaid, ranges[column]),
                  ),
                  startLine: 0,
                  endLine: layout.lineCount,
                  height: columnHeights[column],
                  overlay: true,
                  absoluteTop: bandTop,
                  leftInset: left,
                ),
              );
            }
            used += extent;
            available -= extent;
            continue;
          }
          // 跨页列流（分页介质里的 multicol）：每列按本页可用高容纳行数，
          // 一页放 `count` 列，剩余内容顺延下一页；首列随正常流占高，其余列
          // 作为覆盖切片绘制在首列右侧。
          var cursor = 0;
          while (cursor < relaid.lineCount) {
            final leading = cursor == 0 ? block.leadingExtent : 0.0;
            final usable = available - leading;
            if (usable <= tolerance) {
              record();
              continue;
            }
            final pageRanges = <(int, int)>[];
            var index = cursor;
            while (pageRanges.length < multicol.count &&
                index < relaid.lineCount) {
              final start = index;
              var pieceHeight = 0.0;
              while (index < relaid.lineCount &&
                  pieceHeight + relaid.lines[index].height <=
                      usable + tolerance) {
                pieceHeight += relaid.lines[index].height;
                index += 1;
              }
              // 单行高于可用高：强制放一行，避免死循环（绘制层裁切）。
              if (index == start) {
                index += 1;
              }
              pageRanges.add((start, index));
            }
            if (pageRanges.isEmpty) {
              break;
            }
            final heights = <double>[
              for (final range in pageRanges)
                _lineExtent(relaid.lines.sublist(range.$1, range.$2)),
            ];
            var bandHeight = 0.0;
            for (final height in heights) {
              bandHeight = math.max(bandHeight, height);
            }
            final lastFragment = pageRanges.last.$2 >= relaid.lineCount;
            final trailing = lastFragment ? block.trailingExtent : 0.0;
            final sliceHeight = leading + bandHeight + trailing;
            final bandTop = (firstPage ? topPadding : 0) + used + leading;
            final firstLayout = _columnLayout(
              relaid,
              pageRanges.first,
              multicol.columnWidth,
              boxWidth:
                  multicol.columnWidth * multicol.count +
                  multicol.gap * (multicol.count - 1),
            );
            slices.add(
              PageBlockSlice(
                block: _columnBlock(
                  block,
                  firstLayout,
                  absoluteLeft: 0,
                  multicol: multicol,
                  textRange: _columnTextRange(relaid, pageRanges.first),
                ),
                startLine: 0,
                endLine: firstLayout.lineCount,
                height: sliceHeight,
                leadingExtent: leading,
                trailingExtent: trailing,
                leftInset: block.leftInset,
              ),
            );
            for (var column = 1; column < pageRanges.length; column++) {
              final left = multicol.leftOf(column);
              final layout = _columnLayout(
                relaid,
                pageRanges[column],
                multicol.columnWidth,
              );
              slices.add(
                PageBlockSlice(
                  block: _columnBlock(
                    block,
                    layout,
                    absoluteLeft: left,
                    absoluteTop: bandTop,
                    textRange: _columnTextRange(relaid, pageRanges[column]),
                  ),
                  startLine: 0,
                  endLine: layout.lineCount,
                  height: heights[column],
                  overlay: true,
                  absoluteTop: bandTop,
                  leftInset: left,
                ),
              );
            }
            used += sliceHeight;
            available -= sliceHeight;
            cursor = pageRanges.last.$2;
            if (cursor < relaid.lineCount) {
              record();
            }
          }
          continue;
        }
      }

      // break-inside: avoid：能整块放进新页时先收页，不在当前页拆开（P2-17）。
      final blockExtent =
          block.leadingExtent + block.height + block.trailingExtent;
      // 竖排（writing-mode: vertical-rl/vertical-lr）：`lines` 其实是「列」，
      // 列沿横轴并排、整块同高（= 块高），不能按纵向空间把列切成多页。
      // 这里整块出一片（覆盖全部列），块高决定流推进；放不下当前页则先换页。
      if (block.layout.isVertical) {
        // 竖排块的内容高 = max(最长列, 声明 height)（声明 height 决定列长与盒高）。
        var contentHeight = block.height;
        final declaredHeight = block.style?.height?.resolve(contentHeight);
        if (declaredHeight != null && declaredHeight > contentHeight) {
          contentHeight = declaredHeight;
        }
        // 需要跨页的两种情形：竖向内容高于本页，或列带总宽超过页宽。
        // 处理：按页高重排列（列长 = 页高），再按页宽分列，一页容纳
        // floor(页宽 / 列宽) 列，剩余列顺延下一页（页序即阅读序）。
        final needsColumnSplit =
            contentHeight > available + tolerance ||
            (pageWidth > 0 && block.layout.width > pageWidth + tolerance);
        if (needsColumnSplit && pageWidth > 0 && block.style != null) {
          final split = _verticalColumnChunks(block, available);
          if (split != null) {
            for (var i = 0; i < split.chunks.length; i++) {
              if (i > 0) {
                record();
              }
              slices.add(
                PageBlockSlice(
                  block: split.chunks[i],
                  startLine: 0,
                  endLine: split.chunks[i].layout.lineCount,
                  height: split.pageHeight,
                  leftInset: block.leftInset,
                ),
              );
            }
            used += split.pageHeight;
            available -= split.pageHeight;
            continue;
          }
        }
        final extent =
            block.leadingExtent + contentHeight + block.trailingExtent;
        if (extent > available + tolerance && slices.isNotEmpty) {
          record();
        }
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: 0,
            endLine: block.layout.lineCount,
            // 与横排切片同口径：高度含上下段距（绘制按 slice.height 推进 y，
            // 对照工具也按 slice.height − leading − trailing 折算盒高）。
            height: extent,
            leadingExtent: block.leadingExtent,
            trailingExtent: block.trailingExtent,
            leftInset: block.leftInset,
          ),
        );
        used += extent;
        available -= extent;
        continue;
      }

      if (block.breakInsideAvoid &&
          slices.isNotEmpty &&
          blockExtent + block.containerBottomInset(lines.length) >
              available + fitTolerance &&
          blockExtent +
                  block.containerTopInset(0) +
                  block.containerBottomInset(lines.length) <=
              pageHeight + fitTolerance) {
        record();
      }

      // break-after: avoid（P3-22，Reeden 510 §3.3 优先级「avoid before
      // （标题不落页底）」）：本块能整块放进当前页、但放完之后剩余高度
      // 不足下一块的首行时，把本块推到下一页与后文同页——标题不孤立在
      // 页底。优先级低于强制断页（force 已在上面 record）与 avoid-inside。
      if (block.breakAfterAvoid &&
          slices.isNotEmpty &&
          blockIndex + 1 < flow.length &&
          blockExtent <= available + fitTolerance &&
          blockExtent <= pageHeight + fitTolerance) {
        final next = flow[blockIndex + 1];
        final nextTableRows = _splittableTableRows(next);
        final nextHeaderRows = _tableHeaderRows(next);
        final nextLineNeed = nextTableRows > 1
            ? _tablePiece(
                next,
                0,
                math.min(nextTableRows, nextHeaderRows + 1),
              ).height
            : (next.layout.lines.isEmpty
                  ? 0.0
                  : next.layout.lines.first.height);
        final nextTrailing = nextTableRows <= 1 && next.layout.lineCount <= 1
            ? next.trailingExtent
            : 0.0;
        final nextNeed =
            next.leadingExtent +
            nextLineNeed +
            nextTrailing +
            next.containerBottomInset(1);
        // 强制断页优先；整组在新页也放不下时不反复推页。
        final pairExtent = blockExtent + nextNeed;
        if (!next.pageBreakBefore &&
            !block.pageBreakAfter &&
            pairExtent + block.containerTopInset(0) <=
                pageHeight + fitTolerance &&
            available < pairExtent - fitTolerance) {
          record();
        }
      }

      // 表格预切片仍可能只差几行才放得进当前页。把预切片继续按 rowYs
      // 拆分，首页先排能容纳的行，其余行顺延下一页，而不是整片下移。
      final tableRows = _splittableTableRows(block);
      if (tableRows > 1) {
        final headerRows = _tableHeaderRows(block);
        var rowStart = 0;
        while (rowStart < tableRows) {
          final firstCandidate = rowStart == 0 && headerRows > 0
              ? math.min(tableRows, headerRows + 1)
              : rowStart + 1;
          PageBlock? fitted;
          var fittedEnd = rowStart;
          var fittedLeading = 0.0;
          for (
            var candidate = firstCandidate;
            candidate <= tableRows;
            candidate++
          ) {
            final piece = _tablePiece(block, rowStart, candidate);
            final leading = leadingOf(piece, 0);
            final extent = leading + piece.height + piece.trailingExtent;
            if (extent + piece.containerBottomInset(1) <=
                available + fitTolerance) {
              fitted = piece;
              fittedEnd = candidate;
              fittedLeading = leading;
            } else {
              break;
            }
          }
          if (fitted == null) {
            if (slices.isNotEmpty) {
              record();
              continue;
            }
            // 单行高于整页：强制放一行，由渲染层按页面裁剪，避免死循环。
            fitted = _tablePiece(block, rowStart, firstCandidate);
            fittedEnd = firstCandidate;
            fittedLeading = leadingOf(fitted, 0);
          }
          final extent = fittedLeading + fitted.height + fitted.trailingExtent;
          slices.add(
            PageBlockSlice(
              block: fitted,
              startLine: 0,
              endLine: 1,
              height: extent,
              leadingExtent: fittedLeading,
              trailingExtent: fitted.trailingExtent,
              leftInset: fitted.leftInset,
            ),
          );
          used += extent;
          available -= extent;
          rowStart = fittedEnd;
          if (rowStart < tableRows) {
            record();
          }
        }
        if (block.pageBreakAfter) {
          record();
        }
        continue;
      }

      // 盒高约束（CSS height/min-height/max-height）：内容盒高可能高于
      // 行高之和（盒内留白）或低于（内容溢出盒高，按盒高裁剪）。
      final boxHeight = block.height;
      final lineTotal = _lineExtent(lines);
      final clipped = block.clipsContent && lineTotal > boxHeight + tolerance;
      final lineLimit = clipped
          ? visibleLineCountWithinHeight(lines, boxHeight)
          : lines.length;

      // 盒能整块放进当前页：单切片按盒子高度占位（不按行高之和），声明
      // 高度因此对后续块的位置生效；溢出盒高的行丢弃（overflow 近似）。
      final wholeLeading = leadingOf(block, 0);
      final wholeExtent = wholeLeading + boxHeight + block.trailingExtent;
      if (wholeExtent + block.containerBottomInset(lineLimit) <=
          available + fitTolerance + bottomCredit(block, lineLimit)) {
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: 0,
            endLine: lineLimit,
            height: wholeExtent,
            leadingExtent: wholeLeading,
            textTopTrim: topCredit(block, 0),
            trailingExtent: block.trailingExtent,
            leftInset: block.leftInset,
          ),
        );
        used += wholeExtent;
        available -= wholeExtent;
        if (block.pageBreakAfter) {
          record();
        }
        continue;
      }

      var lineStart = 0;
      while (lineStart < lineLimit) {
        // 真实块首的段距只计一次；续页补容器边框和内边距，不重复 margin。
        final leading = leadingOf(block, lineStart);
        var fitEnd = lineStart;
        var linesHeight = 0.0;
        while (fitEnd < lineLimit) {
          final lineHeight = lines[fitEnd].height;
          final candidateEnd = fitEnd + 1;
          final bottom =
              block.containerBottomInset(candidateEnd) +
              (candidateEnd == lineLimit ? block.trailingExtent : 0);
          if (leading + linesHeight + lineHeight + bottom <=
              available + fitTolerance + bottomCredit(block, candidateEnd)) {
            linesHeight += lineHeight;
            fitEnd += 1;
          } else {
            break;
          }
        }

        if (fitEnd == lineStart) {
          // 当前页已非空：先收页，在新页重试本行。
          if (slices.isNotEmpty) {
            record();
            continue;
          }
          // 单行高于整页：强制放一行，避免死循环；P1-26 之后由渲染层裁切。
          linesHeight = lines[lineStart].height;
          fitEnd = lineStart + 1;
        }

        final trailing = fitEnd == lineLimit ? block.trailingExtent : 0.0;

        // 块尾切片按盒子高度收口：行比盒矮时补白到盒底（声明高度生效）；
        // 跨页切开时各页仍按行高累计，末片再补足。
        final boxTail = fitEnd == lineLimit && !clipped
            ? math.max(0.0, boxHeight - lineTotal)
            : 0.0;
        final sliceHeight = leading + linesHeight + trailing + boxTail;
        // 盒内留白也占页高：当前页放不下整盒时先把本块移到新页（页已非空）。
        if (sliceHeight + block.containerBottomInset(fitEnd) >
                available + fitTolerance + bottomCredit(block, fitEnd) &&
            slices.isNotEmpty) {
          record();
          continue;
        }
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: lineStart,
            endLine: fitEnd,
            height: sliceHeight,
            leadingExtent: leading,
            trailingExtent: trailing,
            leftInset: block.leftInset,
            textTopTrim: topCredit(block, lineStart),
          ),
        );
        used += sliceHeight;
        available -= sliceHeight;
        lineStart = fitEnd;

        // 本块还有行：当前页已满，记录后下一页继续。
        if (lineStart < lineLimit) {
          record();
        }
      }

      if (block.pageBreakAfter) {
        record();
      }
    }

    // 收尾：未达上限时记录末页；已截断则丢弃在途部分页（P7-16
    // 截断语义——页数恰为上限，已产出页保留）。
    if (pages.length < maxPages) {
      record();
    }

    return ChapterPagination(
      spineIndex: spineIndex,
      pages: List<PageContent>.unmodifiable(pages),
      pageHeight: pageHeight,
      totalHeight: totalHeight,
      truncated: truncated,
    );
  }
}

/// 异步增量分页：每产出一页就让出事件循环，并响应取消。
extension PaginatorStreaming on Paginator {
  /// 逐页产出本章内容。
  Stream<PageContent> paginate({
    required List<PageBlock> blocks,
    int spineIndex = 0,
    CancelToken? token,
  }) async* {
    final slices = <PageBlockSlice>[];
    var used = 0.0;
    var available = pageHeight - topPadding;
    var firstPage = true;

    PageContent? record() {
      if (slices.isEmpty) {
        return null;
      }
      if (trimTextEdges) {
        final last = slices.last;
        final credit = last.block.textEdgesAt(last.endLine - 1).bottom;
        slices[slices.length - 1] = last.withTextBottomTrim(credit);
        used -= credit;
      }
      final page = PageContent(
        spineIndex: spineIndex,
        pageIndex: -1,
        slices: List<PageBlockSlice>.unmodifiable(slices),
        usedHeight: used,
        pageHeight: pageHeight,
        topPadding: firstPage ? topPadding : 0,
      );
      slices.clear();
      used = 0;
      available = pageHeight;
      firstPage = false;
      return page;
    }

    var pageIndex = 0;
    // 与 measureChapter 同口径：相邻块上下边距折叠后再推进。
    for (final block in PageBlock.collapseAdjacentMargins(blocks)) {
      if (token?.isCancelled ?? false) {
        return;
      }
      final lines = block.layout.lines;
      if (lines.isEmpty) {
        continue;
      }
      if (block.pageBreakBefore) {
        final page = record();
        if (page != null) {
          yield _withIndex(page, pageIndex++);
          await Future<void>.delayed(Duration.zero);
          if (token?.isCancelled ?? false) {
            return;
          }
        }
      }

      var lineStart = 0;
      while (lineStart < lines.length) {
        if (token?.isCancelled ?? false) {
          return;
        }
        var fitEnd = lineStart;
        final topTrim =
            trimTextEdges && slices.isEmpty && !(firstPage && topPadding < 0)
            ? block.textEdgesAt(lineStart).top
            : 0.0;
        var sliceHeight = -topTrim;
        while (fitEnd < lines.length) {
          final lineHeight = lines[fitEnd].height;
          final bottomTrim = trimTextEdges
              ? block.textEdgesAt(fitEnd).bottom
              : 0.0;
          if (sliceHeight + lineHeight <= available + tolerance + bottomTrim) {
            sliceHeight += lineHeight;
            fitEnd += 1;
          } else {
            break;
          }
        }
        if (fitEnd == lineStart) {
          if (slices.isNotEmpty) {
            final page = record();
            if (page != null) {
              yield _withIndex(page, pageIndex++);
              await Future<void>.delayed(Duration.zero);
              if (token?.isCancelled ?? false) {
                return;
              }
            }
            continue;
          }
          sliceHeight = lines[lineStart].height - topTrim;
          fitEnd = lineStart + 1;
        }
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: lineStart,
            endLine: fitEnd,
            height: sliceHeight,
            leadingExtent: -topTrim,
            textTopTrim: topTrim,
          ),
        );
        used += sliceHeight;
        available -= sliceHeight;
        lineStart = fitEnd;
        if (lineStart < lines.length) {
          final page = record();
          if (page != null) {
            yield _withIndex(page, pageIndex++);
            await Future<void>.delayed(Duration.zero);
            if (token?.isCancelled ?? false) {
              return;
            }
          }
        }
      }

      if (block.pageBreakAfter) {
        final page = record();
        if (page != null) {
          yield _withIndex(page, pageIndex++);
          await Future<void>.delayed(Duration.zero);
          if (token?.isCancelled ?? false) {
            return;
          }
        }
      }
    }

    final last = record();
    if (last != null) {
      yield _withIndex(last, pageIndex++);
    }
  }

  static PageContent _withIndex(PageContent page, int index) => PageContent(
    spineIndex: page.spineIndex,
    pageIndex: index,
    slices: page.slices,
    usedHeight: page.usedHeight,
    pageHeight: page.pageHeight,
    topPadding: page.topPadding,
  );
}
