import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, protected;
import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import 'box_model.dart';
import 'float_occupancy.dart';
import 'line_breaker.dart';

/// 块级盒的测量约束（§60.1）。
///
/// 只描述可用空间，不携带父节点尺寸；子节点测量期间不读父节点。
@immutable
class LayoutConstraints {
  /// 创建约束。
  const LayoutConstraints({
    this.minWidth = 0,
    this.maxWidth = double.infinity,
    this.minHeight = 0,
    this.maxHeight = double.infinity,
  }) : assert(maxWidth >= minWidth, 'maxWidth 不能小于 minWidth'),
       assert(maxHeight >= minHeight, 'maxHeight 不能小于 minHeight');

  /// 最小宽。
  final double minWidth;

  /// 最大宽（内容可用宽）。
  final double maxWidth;

  /// 最小高。
  final double minHeight;

  /// 最大高（内容可用高）。
  final double maxHeight;

  /// 内容可用宽。
  double get contentWidth => maxWidth;

  /// 内容可用高。
  double get contentHeight => maxHeight;

  /// 扣掉已用高度后的剩余约束。
  LayoutConstraints offHeight(double usedHeight) {
    if (!maxHeight.isFinite) {
      return LayoutConstraints(
        minWidth: minWidth,
        maxWidth: maxWidth,
        minHeight: minHeight,
        maxHeight: maxHeight,
      );
    }
    return LayoutConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: math.max(0.0, maxHeight - usedHeight),
    );
  }

  /// 把尺寸收进约束范围。
  Size constrain(Size size) => Size(
    size.width.clamp(minWidth, maxWidth).toDouble(),
    size.height.clamp(minHeight, maxHeight).toDouble(),
  );

  @override
  String toString() =>
      'LayoutConstraints($minWidth..$maxWidth × $minHeight..$maxHeight)';
}

/// 两阶段块测量的基类（§60.1）。
///
/// 阶段一 [onLayout] 只分配约束并测量子树，阶段二 [calculateSize] 只把子节点
/// 已有尺寸相加/取最大值；子节点永远看不到父节点尺寸，因此测量不会来回震荡。
abstract class BlockFlow {
  /// 子节点列表（叶子为空）。
  List<BlockFlow> get children => const <BlockFlow>[];

  /// 自身尺寸；测量前为零。
  Size get size => _size;

  /// 最近一次测量使用的约束。
  LayoutConstraints? get constraints => _constraints;

  /// 阶段一进入次数，用于验证“测量阶段无尺寸反复变更”。
  int get layoutCount => _layoutCount;

  /// 是否脱离文档流（绝对/固定定位、浮动）。
  ///
  /// 脱离流的盒子照常测量，但不推进父容器的块流高度（§60.3）。
  bool get isOutOfFlow => false;

  /// 自身垂直 padding + border（margin 穿透折叠判定用；P7-24）。
  ///
  /// 自塌陷盒 = 高度 0 且自身无垂直 padding/border——其上下 margin
  /// 折叠为一体并与相邻 margin 合并（CSS 2.2 §8.3.1）。
  double get verticalInsets => 0;

  /// 测量分支（由 [resolveFlowBranch] 判定）。
  FlowBranch get branch => FlowBranch.block;

  /// 块的外边距（§60.3）。
  ///
  /// 默认零；文本块取样式里的 margin，容器给出与首末子块折叠后的值。
  /// 脱离流的盒（绝对定位、浮动）不参与块流折叠。
  CssEdges get margin => CssEdges.zero;

  /// 自身样式（clear 判定用，§48.3 第 3 条）；无样式返回 null。
  ComputedStyle? get style => null;

  Size _size = Size.zero;
  LayoutConstraints? _constraints;
  int _layoutCount = 0;

  /// 两阶段测量入口：先分配约束测量子树，再合成自身尺寸。
  Size measure(LayoutConstraints constraints) {
    _layoutCount += 1;
    _constraints = constraints;
    onLayout(constraints);
    _size = calculateSize(constraints);
    return _size;
  }

  /// 阶段一：分配约束、测量子树、登记占位。
  @protected
  void onLayout(LayoutConstraints constraints);

  /// 阶段二：合成自身尺寸；只做加法，不再测量子节点。
  @protected
  Size calculateSize(LayoutConstraints constraints);
}

/// 文本块：一次断行测量即得尺寸。
class TextFlowBlock extends BlockFlow {
  /// 创建文本块。
  TextFlowBlock({
    required this.text,
    required this.style,
    this.runs = const <StyledRun>[],
  });

  /// 文本内容。
  final String text;

  /// 计算样式。
  @override
  final ComputedStyle style;

  /// 行内样式区间。
  final List<StyledRun> runs;

  TextLayoutResult? _layout;
  BoxModel? _boxModel;

  /// 阶段一产出的行布局；未测量时为空。
  TextLayoutResult? get layout => _layout;

  /// 阶段一产出的盒模型；未测量时为空。
  BoxModel? get boxModel => _boxModel;

  @override
  CssEdges get margin => style.margin;

  @override
  void onLayout(LayoutConstraints constraints) {
    final model = BoxModel.fromStyle(
      style,
      containingWidth: constraints.maxWidth,
    );
    _boxModel = model;
    _layout = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: model.resolveContentWidth(constraints.maxWidth),
      runs: runs,
    );
  }

  @override
  Size calculateSize(LayoutConstraints constraints) {
    final layout = _layout;
    final model = _boxModel;
    if (layout == null || model == null || layout.lineCount == 0) {
      return constraints.constrain(Size.zero);
    }
    // 声明宽是块级定宽，直接作为内容宽；auto 时沿用实测行宽（既有收缩语义）。
    final contentWidth = model.contentWidth == null
        ? layout.width
        : model.resolveContentWidth(constraints.maxWidth);
    return constraints.constrain(
      Size(
        model.borderBoxWidth(contentWidth),
        model.borderBoxHeight(layout.height),
      ),
    );
  }
}

/// 纵向流式容器：子块依次向下排，高度相加、宽度取最大（§60.1、§60.4）。
///
/// 相邻子块的上下 margin 按 CSS 2.2 折叠（§60.3）；首块的上 margin 与末块的
/// 下 margin 会与容器自身 margin 折叠后逸出容器，不计入内容高度。
/// 页根（body）容器用 [ColumnFlowBlock.body] 创建，会钳制首个块级子元素的负
/// `margin-top`（§60.7），避免首页首行被顶出内容区。
class ColumnFlowBlock extends BlockFlow {
  /// 创建容器。
  ColumnFlowBlock([
    List<BlockFlow> children = const <BlockFlow>[],
    CssEdges margin = CssEdges.zero,
    bool clampFirstNegativeTopMargin = false,
  ]) : this._(
         children,
         margin,
         clampFirstNegativeTopMargin,
         CssEdges.zero,
         CssEdges.zero,
       );

  ColumnFlowBlock._(
    List<BlockFlow> children,
    CssEdges margin,
    bool clampFirstNegativeTopMargin,
    CssEdges padding,
    CssEdges borders, [
    ComputedStyle? style,
  ]) : _children = List<BlockFlow>.unmodifiable(children),
      _ownMargin = margin,
      _clampFirstNegativeTopMargin = clampFirstNegativeTopMargin,
      _padding = padding,
      _borders = borders,
      _style = style;

  /// 按样式创建容器：padding/border/margin 取自 [style]。
  ///
  /// 子块在内容区（扣掉 padding 与 border）内排布，自身尺寸含 padding/border。
  factory ColumnFlowBlock.styled({
    required List<BlockFlow> children,
    required ComputedStyle style,
    bool clampFirstNegativeTopMargin = false,
  }) => ColumnFlowBlock._(
    children,
    style.margin,
    clampFirstNegativeTopMargin,
    style.padding,
    CssEdges(
      top: style.borders.top.width,
      right: style.borders.right.width,
      bottom: style.borders.bottom.width,
      left: style.borders.left.width,
    ),
    style,
  );

  /// 页根（body）容器：首个块级子元素的负 `margin-top` 钳到 0（§60.7）。
  factory ColumnFlowBlock.body([
    List<BlockFlow> children = const <BlockFlow>[],
    CssEdges margin = CssEdges.zero,
  ]) => ColumnFlowBlock(children, margin, true);

  final List<BlockFlow> _children;
  final CssEdges _ownMargin;
  final CssEdges _padding;
  final CssEdges _borders;
  final bool _clampFirstNegativeTopMargin;
  final ComputedStyle? _style;
  final List<double> _childTops = <double>[];
  final List<double> _childLefts = <double>[];
  final FloatOccupancy _floats = FloatOccupancy();
  var _collapsedMargin = CssEdges.zero;
  var _contentHeight = 0.0;

  /// padding + border 的水平总和。
  double get _horizontalInset => _padding.horizontal + _borders.horizontal;

  /// padding + border 的垂直总和。
  double get _verticalInset => _padding.vertical + _borders.vertical;

  @override
  double get verticalInsets => _verticalInset;

  @override
  List<BlockFlow> get children => _children;

  /// 各流内子块顶边相对容器内容区顶部的偏移（按出现顺序）。
  List<double> get childTops => List<double>.unmodifiable(_childTops);

  /// 各流内子块左边相对容器内容区左边的偏移（P3-13：被左浮动收窄时 >0）。
  List<double> get childLefts => List<double>.unmodifiable(_childLefts);

  /// 本容器的浮动占用（P3-13）：容器测量时登记，跨页衔接（P3-15）与
  /// 绘制消费。
  FloatOccupancy get floats => _floats;

  double _maxFloatBottom(FloatSide side) => _floats.maxBottom(side);

  @override
  ComputedStyle? get style => _style;

  @override
  CssEdges get margin => _collapsedMargin;

  @override
  void onLayout(LayoutConstraints constraints) {
    _childTops.clear();
    _childLefts.clear();
    _floats.clear();
    final childWidth = math.max(0.0, constraints.maxWidth - _horizontalInset);
    var remaining = constraints.maxHeight;
    var cursor = 0.0;
    // 携带的「前块有效下 margin」：自塌陷子块把自己的上下 margin 与
    // 前块下 margin 合并后向前传递（P7-24 穿透折叠，CSS 2.2 §8.3.1）。
    var previousBottom = 0.0;
    // 首末子块的「有效逸出 margin」：自塌陷链的上/下 margin 合并值。
    double? firstEffectiveTop;
    double? lastEffectiveBottom;
    BlockFlow? firstChild;
    BlockFlow? lastChild;
    for (final child in _children) {
      // 浮动分支（P3-13，§48.2）：fit-content 测量后按当前位置登记
      // 占用；不推进块流、不进顶位表（childTops 只覆盖流内子块）、
      // 不参与 margin 折叠——位置由 [floats] 的占用矩形承载。
      if (child.branch == FlowBranch.float && child is FloatFlowBlock) {
        child.measure(
          LayoutConstraints(
            maxWidth: childWidth,
            maxHeight: remaining.isFinite ? remaining : double.infinity,
          ),
        );
        final width = child.size.width;
        final left = child.side == FloatSide.left
            ? child.margin.left
            : math.max(0.0, childWidth - width - child.margin.right);
        _floats.insert(
          BoxOccupied(
            rect: Rect.fromLTWH(left, cursor + child.margin.top, width,
                child.size.height),
            baseline: cursor,
            side: child.side,
          ),
        );
        continue;
      }
      if (child.branch == FlowBranch.absolute) {
        child.measure(
          LayoutConstraints(maxWidth: childWidth, maxHeight: remaining),
        );
        continue;
      }
      final gap = firstChild == null
          ? 0.0
          : collapseMargins(previousBottom, child.margin.top);
      var top = cursor + gap;
      // clear 语义（P3-14，§48.3 第 3 条）：clear:left/right/both 把块顶
      // 推到对应侧浮动底部之下，并把已满足的占用移除（不再约束后续内容）。
      final clear = child.style?.clear ?? CssClear.none;
      if (clear != CssClear.none) {
        final wantLeft = clear == CssClear.left || clear == CssClear.both;
        final wantRight = clear == CssClear.right || clear == CssClear.both;
        var floor = top;
        if (wantLeft) {
          floor = math.max(floor, _maxFloatBottom(FloatSide.left));
        }
        if (wantRight) {
          floor = math.max(floor, _maxFloatBottom(FloatSide.right));
        }
        if (floor > top) {
          top = floor;
          if (wantLeft) {
            _floats.removeSatisfiedBelow(top, FloatSide.left);
          }
          if (wantRight) {
            _floats.removeSatisfiedBelow(top, FloatSide.right);
          }
        }
      }
      // 绕排收窄（P3-13，§48.2 createPlaceholders 的容器侧等价）：
      // 首趟按全宽测量，按块高度区间查占用；浮动收窄了可用宽才重测
      // （最多 3 趟收敛）——无浮动的树保持单次测量不变量。
      var available = childWidth;
      child.measure(
        LayoutConstraints(maxWidth: available, maxHeight: remaining),
      );
      var pass = 0;
      while (true) {
        final bottom = top + child.size.height;
        final narrowed = math.max(
          0.0,
          childWidth -
              _floats.occupiedLeftAt(top, bottom) -
              _floats.occupiedRightAt(top, bottom, childWidth),
        );
        if (narrowed >= available - 0.5 || pass >= 2) {
          break;
        }
        available = narrowed;
        child.measure(
          LayoutConstraints(maxWidth: available, maxHeight: remaining),
        );
        pass += 1;
      }
      final leftInset = _floats.occupiedLeftAt(
        top,
        top + child.size.height,
      );
      final selfCollapsing =
          child.size.height == 0 && child.verticalInsets == 0;
      _childTops.add(top);
      _childLefts.add(leftInset);
      if (selfCollapsing) {
        // 穿透（P7-24，CSS 2.2 §8.3.1）：零高且无垂直 padding/border
        // 的块不推进流——其上下 margin 与前块下 margin 合并后向前
        // 携带（或作为首块向上逸出进容器顶 margin）。
        final merged = collapseMargins(child.margin.top, child.margin.bottom);
        if (firstChild == null) {
          previousBottom = 0;
        } else {
          previousBottom = collapseMargins(previousBottom, merged);
        }
      } else {
        // clear 推移也推进块流（推到浮动底部之下后，后续内容从本块底
        // 部继续）。
        final advanced = top + child.size.height - cursor;
        cursor = top + child.size.height;
        if (remaining.isFinite) {
          remaining = math.max(0.0, remaining - advanced);
        }
        previousBottom = child.margin.bottom;
      }
      final effectiveTop = selfCollapsing
          ? collapseMargins(child.margin.top, child.margin.bottom)
          : child.margin.top;
      final effectiveBottom = selfCollapsing
          ? collapseMargins(child.margin.top, child.margin.bottom)
          : child.margin.bottom;
      firstEffectiveTop ??= effectiveTop;
      lastEffectiveBottom = effectiveBottom;
      firstChild ??= child;
      lastChild = child;
    }
    _contentHeight = cursor;
    // 首块逸出 margin：页根容器对负值钳制（§60.7，P2-09）——自塌陷
    // 链的合并逸出值同样钳制。
    final escapedTop = firstEffectiveTop == null
        ? null
        : (_clampFirstNegativeTopMargin
              ? clampFirstElementNegativeTopMargin(
                  firstEffectiveTop,
                  isBodyFirstElement: true,
                )
              : firstEffectiveTop);
    _collapsedMargin = CssEdges(
      top: firstChild == null
          ? _ownMargin.top
          : collapseMargins(_ownMargin.top, escapedTop ?? 0),
      right: _ownMargin.right,
      bottom: lastChild == null
          ? _ownMargin.bottom
          : collapseMargins(_ownMargin.bottom, lastEffectiveBottom ?? 0),
      left: _ownMargin.left,
    );
  }

  @override
  Size calculateSize(LayoutConstraints constraints) {
    var width = 0.0;
    for (final child in _children) {
      width = math.max(width, child.size.width);
    }
    return constraints.constrain(
      Size(width + _horizontalInset, _contentHeight + _verticalInset),
    );
  }
}

/// 首元素负 margin 钳制（§60.7）。
///
/// `body` 的首个块级子元素若带负 `margin-top`，钳到 0：正文首行留在内容区内，
/// 不会被顶出页顶。其它元素原样返回，负 margin 仍可把块上移。
double clampFirstElementNegativeTopMargin(
  double marginTop, {
  required bool isBodyFirstElement,
}) => isBodyFirstElement && marginTop < 0 ? 0 : marginTop;

/// CSS 2.2 相邻外边距折叠（§60.3）：正正取大、负负取小、正负相加。
double collapseMargins(double first, double second) {
  if (first >= 0 && second >= 0) {
    return math.max(first, second);
  }
  if (first <= 0 && second <= 0) {
    return math.min(first, second);
  }
  return first + second;
}

/// 测量分支，判定顺序见 [resolveFlowBranch]（§60.2）。
enum FlowBranch {
  /// 绝对/固定定位，先摘出文档流。
  absolute,

  /// 浮动。
  float,

  /// 表格。
  table,

  /// 行内（行内块与行内容器）。
  inline,

  /// 常规块级。
  block,

  /// `display: none`，不测量。
  none,
}

/// 按 §60.2 的顺序判定测量分支：绝对/固定定位 → 浮动 → 表格 → 不显示 → 行内 → 块级。
///
/// 竖排（writing-mode）分支尚未接入，统一按水平排版处理（P5 竖排重做）。
FlowBranch resolveFlowBranch(ComputedStyle style) {
  final position = style.position;
  if (position == CssPosition.absolute || position == CssPosition.fixed) {
    return FlowBranch.absolute;
  }
  if (style.cssFloat != CssFloat.none) {
    return FlowBranch.float;
  }
  final display = style.display;
  if (display == CssDisplay.table ||
      display == CssDisplay.tableRow ||
      display == CssDisplay.tableCell) {
    return FlowBranch.table;
  }
  if (display == CssDisplay.none) {
    return FlowBranch.none;
  }
  if (display == CssDisplay.inline || display == CssDisplay.inlineBlock) {
    return FlowBranch.inline;
  }
  return FlowBranch.block;
}

/// 按样式分派创建测量盒：文本内容给 [text]，容器内容给 [children]。
BlockFlow createFlowBox({
  required ComputedStyle style,
  String? text,
  List<StyledRun> runs = const <StyledRun>[],
  List<BlockFlow> children = const <BlockFlow>[],
}) {
  final content = text != null
      ? TextFlowBlock(text: text, style: style, runs: runs)
      : ColumnFlowBlock.styled(children: children, style: style);
  return switch (resolveFlowBranch(style)) {
    FlowBranch.absolute => AbsoluteFlowBlock(content),
    FlowBranch.float => FloatFlowBlock(content, style),
    FlowBranch.table => TableFlowBlock(content),
    FlowBranch.inline => InlineFlowBlock(text != null ? [content] : children),
    FlowBranch.none => HiddenFlowBlock(),
    FlowBranch.block => content,
  };
}

/// 绝对/固定定位盒：按容器约束独立测量，不占流高度（§60.2 第 1 条）。
///
/// 阅微这里按 `position: absolute` 的 computed width 新建容器约束；我们还未解析
/// `width`，先用容器约束，等宽度解析接入后再换成自身宽度。
class AbsoluteFlowBlock extends BlockFlow {
  /// 包裹内容盒。
  AbsoluteFlowBlock(this.content);

  /// 被测内容。
  final BlockFlow content;

  @override
  FlowBranch get branch => FlowBranch.absolute;

  @override
  bool get isOutOfFlow => true;

  @override
  List<BlockFlow> get children => <BlockFlow>[content];

  @override
  void onLayout(LayoutConstraints constraints) {
    content.measure(
      LayoutConstraints(
        maxWidth: constraints.maxWidth,
        maxHeight: constraints.maxHeight,
      ),
    );
  }

  @override
  Size calculateSize(LayoutConstraints constraints) => content.size;
}

/// 浮动盒：按可用宽做 fit-content 收缩，不推进父容器块流（§60.2 第 2 条、§60.5）。
///
/// 容器测量时把它登记进 [FloatOccupancy]，后续流内块按区间收窄宽度绕排
/// （P3-13 createPlaceholders 分支）。
class FloatFlowBlock extends BlockFlow {
  /// 包裹内容盒。
  FloatFlowBlock(this.content, this.style);

  /// 被测内容。
  final BlockFlow content;

  /// 浮动盒自身样式（float 方向与 margin 来源）。
  @override
  final ComputedStyle style;

  /// 浮动方向。
  FloatSide get side =>
      style.cssFloat == CssFloat.right ? FloatSide.right : FloatSide.left;

  @override
  FlowBranch get branch => FlowBranch.float;

  @override
  bool get isOutOfFlow => true;

  @override
  List<BlockFlow> get children => <BlockFlow>[content];

  @override
  void onLayout(LayoutConstraints constraints) {
    // 按可用宽测量即得 fit-content：内容窄时不换行、宽时在可用宽处折行。
    content.measure(
      LayoutConstraints(
        maxWidth: constraints.maxWidth,
        maxHeight: constraints.maxHeight,
      ),
    );
  }

  @override
  Size calculateSize(LayoutConstraints constraints) => content.size;
}

/// 表格盒：宽度对齐内容区，本阶段按纵向测量（单元格布局见 P3-18）。
class TableFlowBlock extends BlockFlow {
  /// 包裹内容盒。
  TableFlowBlock(this.content);

  /// 被测内容。
  final BlockFlow content;

  @override
  FlowBranch get branch => FlowBranch.table;

  @override
  CssEdges get margin => content.margin;

  @override
  List<BlockFlow> get children => <BlockFlow>[content];

  @override
  void onLayout(LayoutConstraints constraints) {
    content.measure(
      LayoutConstraints(
        maxWidth: constraints.maxWidth,
        maxHeight: constraints.maxHeight,
      ),
    );
  }

  @override
  Size calculateSize(LayoutConstraints constraints) => content.size;
}

/// 行内（含行内块）容器：宽高取子节点最大值，不求和（§60.4）。
///
/// 真正的并排换行留到行内布局任务；这里按 §60.4 的尺寸口径合成。
class InlineFlowBlock extends BlockFlow {
  /// 创建行内容器。
  InlineFlowBlock([List<BlockFlow> children = const <BlockFlow>[]])
    : _children = List<BlockFlow>.unmodifiable(children);

  final List<BlockFlow> _children;

  @override
  FlowBranch get branch => FlowBranch.inline;

  @override
  List<BlockFlow> get children => _children;

  @override
  void onLayout(LayoutConstraints constraints) {
    for (final child in _children) {
      child.measure(
        LayoutConstraints(
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
        ),
      );
    }
  }

  @override
  Size calculateSize(LayoutConstraints constraints) {
    var width = 0.0;
    var height = 0.0;
    for (final child in _children) {
      width = math.max(width, child.size.width);
      height = math.max(height, child.size.height);
    }
    return constraints.constrain(Size(width, height));
  }
}

/// `display: none` 盒：不测量子节点，尺寸为零。
class HiddenFlowBlock extends BlockFlow {
  @override
  FlowBranch get branch => FlowBranch.none;

  @override
  void onLayout(LayoutConstraints constraints) {}

  @override
  Size calculateSize(LayoutConstraints constraints) => Size.zero;
}
