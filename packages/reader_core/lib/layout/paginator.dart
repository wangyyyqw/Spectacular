import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../css/computed_style.dart';
import '../src/api/models.dart' show CancelToken, PageSlice;
import 'block_flow.dart' show collapseMargins;
import 'box_model.dart';
import 'float_occupancy.dart' show FloatSide;
import 'page_background.dart';
import 'table_layout.dart' show TableRenderSpec;
import 'text_layout.dart';

/// 行内图片（P9-06）：占位符下标 + 已解析成书内路径的图片地址。
class InlineImageSpec {
  /// 创建行内图片。
  const InlineImageSpec({
    required this.offset,
    required this.url,
    this.width,
    this.height,
  });

  /// 占位符在块文本中的下标（UTF-16）。
  final int offset;

  /// 书内资源路径（绘制层用 imageLookup 查解码图）。
  final String url;

  /// 书籍 CSS 声明的显示宽（逻辑像素，null 表示按行高 1em 等比）。
  final double? width;

  /// 书籍 CSS 声明的显示高（逻辑像素）。
  final double? height;
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
    this.rubies,
    this.inlineImages = const <InlineImageSpec>[],
    this.absolute = false,
    this.absoluteTop,
    this.absoluteLeft,
    this.bleedLeft = false,
    this.bleedRight = false,
    this.containerSides = false,
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
    TableRenderSpec? table,
    bool absolute = false,
    double? absoluteTop,
    double? absoluteLeft,
    bool bleedLeft = false,
    bool bleedRight = false,
    bool containerSides = false,
    double? effectiveOpacity,
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
      table: table,
      absolute: absolute,
      absoluteTop: absoluteTop,
      absoluteLeft: absoluteLeft,
      bleedLeft: bleedLeft,
      bleedRight: bleedRight,
      containerSides: containerSides,
      // 未显式传入时沿用计算样式的祖先累计不透明度（T3 只在容器分支显式传）。
      effectiveOpacity: effectiveOpacity ?? style.effectiveOpacity,
      // 盒高约束（CSS height/min-height/max-height）：先按声明值解算，
      // 未声明时等于测量高（行高之和）。
      declaredContentHeight: model.resolveContentHeight(
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

  /// 注音标注（P8-08）：ruby/rt 结构（主文本区间 + 注音串），
  /// 渲染层注音趟在主文本区间上方绘制（50% 字号、居中）。
  final List<RubyAnnotation>? rubies;

  /// 行内图片（P9-06）：U+FFFC 占位符位置与图片地址，绘制层按占位符
  /// 字形框画图。
  final List<InlineImageSpec> inlineImages;

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

  /// 位于带边框容器的内部（P9-25）：背景与左右边框向上下段距延伸，让
  /// 被拆成多块的卡片/面板拼回一片，块间缝隙不露页底、边框不断开。
  final bool containerSides;

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

  /// 内容是否被盒高裁掉（声明高度小于行高之和）：分页只排可见行，剩余
  /// 行不进入下一页（`overflow: hidden/clip` 近似；真机渲染由切片裁剪）。
  bool get clipsContent => height + 0.5 < layout.height;

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

  /// 复制块并替换段前/段后间距（其余字段共享引用）。
  PageBlock withSpacing({double? spaceBefore, double? spaceAfter}) =>
      PageBlock(
        layout: layout,
        pageBreakBefore: pageBreakBefore,
        pageBreakAfter: pageBreakAfter,
        startCfi: startCfi,
        endCfi: endCfi,
        style: style,
        spaceBefore: spaceBefore ?? this.spaceBefore,
        spaceAfter: spaceAfter ?? this.spaceAfter,
        topInset: topInset,
        bottomInset: bottomInset,
        leftInset: leftInset,
        breakInsideAvoid: breakInsideAvoid,
        breakAfterAvoid: breakAfterAvoid,
        listMarker: listMarker,
        groupId: groupId,
        table: table,
        floatSide: floatSide,
        rubies: rubies,
        // 重建时必须带全字段（P9-19）：边距折叠会把相邻块换成新实例，
        // 漏字段会让行内图片/绝对定位在真机里随机消失。
        inlineImages: inlineImages,
        absolute: absolute,
        absoluteTop: absoluteTop,
        absoluteLeft: absoluteLeft,
        bleedLeft: bleedLeft,
        bleedRight: bleedRight,
        containerSides: containerSides,
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
    for (var i = 1; i < blocks.length; i++) {
      final previous = result[i - 1];
      final current = blocks[i];
      if (previous.spaceAfter == 0) {
        result.add(current);
        continue;
      }
      result[i - 1] = previous.withSpacing(spaceAfter: 0);
      result.add(
        current.withSpacing(
          spaceBefore: collapseMargins(
            previous.spaceAfter,
            current.spaceBefore,
          ),
        ),
      );
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
  static MulticolGeometry? fromStyle(ComputedStyle style, double availableWidth) {
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
      final byWidth =
          ((availableWidth + gap) / (specWidth + gap)).floor().clamp(1, 8);
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
  });

  /// 来源块。
  final PageBlock block;

  /// 起始行（含）。
  final int startLine;

  /// 结束行（不含）。
  final int endLine;

  /// 本切片高度（含首尾额外高度）。
  final double height;

  /// 首行之前的额外高度（段前间距 + 上内缩），只在块首切片出现。
  final double leadingExtent;

  /// 末行之后的额外高度（下内缩 + 段后间距），只在块尾切片出现。
  final double trailingExtent;

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

  /// 已用高度（不含首页顶部留白）。
  final double usedHeight;

  /// 页高。
  final double pageHeight;

  /// 首页顶部留白。
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
    this.topPadding = 0,
    this.tolerance = 2,
  });

  /// 页高。
  final double pageHeight;

  /// 第一章顶部留白。
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

  /// 盒高内可见的行数：从首行起累加，超过盒高即停（至少 1 行，避免死循环）。
  static int _visibleLineCount(List<LineBox> lines, double boxHeight) {
    var used = 0.0;
    var count = 0;
    for (final line in lines) {
      if (used + line.height > boxHeight + 0.5 && count > 0) {
        break;
      }
      used += line.height;
      count += 1;
    }
    return count;
  }

  /// 组 [groupId] 自 [index] 起的连续成员总占高（leading+height+trailing）。
  static double _groupExtent(List<PageBlock> blocks, int index, int groupId) {
    var extent = 0.0;
    for (var i = index; i < blocks.length && blocks[i].groupId == groupId; i++) {
      extent +=
          blocks[i].leadingExtent + blocks[i].height + blocks[i].trailingExtent;
    }
    return extent;
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
          ellipsized: line.ellipsized,
          ellipsisWidth: line.ellipsisWidth,
          hyphenated: line.hyphenated,
          hyphenWidth: line.hyphenWidth,
        ),
      );
      width = math.max(width, line.advanceWidth);
      top += line.height;
    }
    return TextLayoutResult(
      text: fragment,
      lines: lines,
      // 首列块代表整个多列容器：块宽取「列带总宽」（容器内容宽），
      // 其余列块取列宽；行宽仍是各自列内的实际行宽。
      width: boxWidth ?? width,
      height: top,
      maxWidth: columnWidth,
      runs: const <StyledRun>[],
    );
  }

  /// 由源块与单列子布局构造列块；非首列作为覆盖切片（absolute 定位）。
  static PageBlock _columnBlock(
    PageBlock source,
    TextLayoutResult layout, {
    required double absoluteLeft,
    double? absoluteTop,
    MulticolGeometry? multicol,
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
    containerSides: source.containerSides,
    effectiveOpacity: source.effectiveOpacity,
    multicol: multicol,
    // 第 2 列起脱离正常流，绘制在首列右侧（overlay 切片）。
    absolute: absoluteTop != null,
    absoluteTop: absoluteTop,
    absoluteLeft: absoluteLeft,
  );

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
        final top = (block.absoluteTop ?? used)
            .clamp(0.0, math.max(0.0, pageHeight - 1))
            .toDouble();
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: 0,
            endLine: block.layout.lineCount,
            height: block.height,
            overlay: true,
            absoluteTop: top,
            leftInset: block.absoluteLeft ?? 0,
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
        if (groupExtent > available + tolerance &&
            groupExtent <= pageHeight + tolerance) {
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
      // 已知限制（后续任务）：
      // - 仅支持「整块放进当前页」；跨页列流（列未排满续到下一页）未实现，
      //   超出页高时退回单列；
      // - 重排使用纯文本，行内样式 runs / 行内图片 / 注音不参与分栏；
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
        final relaid = TextLayoutEngine.layout(
          text: block.layout.text,
          style: block.style!,
          maxWidth: multicol.columnWidth,
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
              boxWidth: multicol.columnWidth * multicol.count +
                  multicol.gap * (multicol.count - 1),
            );
            slices.add(
              PageBlockSlice(
                block: _columnBlock(
                  block,
                  firstLayout,
                  absoluteLeft: 0,
                  multicol: multicol,
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
        }
      }

      // break-inside: avoid：能整块放进新页时先收页，不在当前页拆开（P2-17）。
      final blockExtent =
          block.leadingExtent + block.height + block.trailingExtent;
      if (block.breakInsideAvoid &&
          slices.isNotEmpty &&
          blockExtent > available + tolerance &&
          blockExtent <= pageHeight + tolerance) {
        record();
      }

      // break-after: avoid（P3-22，Reeden 510 §3.3 优先级「avoid before
      // （标题不落页底）」）：本块能整块放进当前页、但放完之后剩余高度
      // 不足下一块的首行时，把本块推到下一页与后文同页——标题不孤立在
      // 页底。优先级低于强制断页（force 已在上面 record）与 avoid-inside。
      if (block.breakAfterAvoid &&
          slices.isNotEmpty &&
          blockIndex + 1 < flow.length &&
          blockExtent <= available + tolerance &&
          blockExtent <= pageHeight + tolerance) {
        final next = flow[blockIndex + 1];
        final nextNeed = next.leadingExtent +
            (next.layout.lines.isEmpty
                ? 0.0
                : next.layout.lines.first.height);
        if (available - blockExtent < nextNeed) {
          record();
        }
      }

      // 盒高约束（CSS height/min-height/max-height）：内容盒高可能高于
      // 行高之和（盒内留白）或低于（内容溢出盒高，按盒高裁剪）。
      final boxHeight = block.height;
      final lineTotal = _lineExtent(lines);
      final clipped = lineTotal > boxHeight + tolerance;
      final lineLimit = clipped
          ? _visibleLineCount(lines, boxHeight)
          : lines.length;

      // 盒能整块放进当前页：单切片按盒子高度占位（不按行高之和），声明
      // 高度因此对后续块的位置生效；溢出盒高的行丢弃（overflow 近似）。
      if (block.leadingExtent + boxHeight + block.trailingExtent <=
          available + tolerance) {
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: 0,
            endLine: lineLimit,
            height: block.leadingExtent + boxHeight + block.trailingExtent,
            leadingExtent: block.leadingExtent,
            trailingExtent: block.trailingExtent,
            leftInset: block.leftInset,
          ),
        );
        used += block.leadingExtent + boxHeight + block.trailingExtent;
        available -= block.leadingExtent + boxHeight + block.trailingExtent;
        if (block.pageBreakAfter) {
          record();
        }
        continue;
      }

      var lineStart = 0;
      while (lineStart < lineLimit) {
        final isBlockStart = lineStart == 0;
        // 段前间距与上内缩只在块首切片出现（P2-14 补全：分页几何含盒模型内缩）。
        final leading = isBlockStart ? block.leadingExtent : 0.0;
        var fitEnd = lineStart;
        var linesHeight = 0.0;
        while (fitEnd < lineLimit) {
          final lineHeight = lines[fitEnd].height;
          if (leading + linesHeight + lineHeight <= available + tolerance) {
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

        var trailing = 0.0;
        if (fitEnd == lineLimit) {
          // 下内缩与段后间距只在块尾切片出现；放不下时退一行到下一页。
          trailing = block.trailingExtent;
          if (leading + linesHeight + trailing > available + tolerance &&
              fitEnd - lineStart > 1) {
            fitEnd -= 1;
            linesHeight -= lines[fitEnd].height;
            trailing = 0;
          }
        }

        // 块尾切片按盒子高度收口：行比盒矮时补白到盒底（声明高度生效）；
        // 跨页切开时各页仍按行高累计，末片再补足。
        final boxTail = fitEnd == lineLimit && !clipped
            ? math.max(0.0, boxHeight - lineTotal)
            : 0.0;
        final sliceHeight = leading + linesHeight + trailing + boxTail;
        // 盒内留白也占页高：当前页放不下整盒时先把本块移到新页（页已非空）。
        if (sliceHeight > available + tolerance && slices.isNotEmpty) {
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
        var sliceHeight = 0.0;
        while (fitEnd < lines.length) {
          final lineHeight = lines[fitEnd].height;
          if (sliceHeight + lineHeight <= available + tolerance) {
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
          sliceHeight = lines[lineStart].height;
          fitEnd = lineStart + 1;
        }
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: lineStart,
            endLine: fitEnd,
            height: sliceHeight,
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
