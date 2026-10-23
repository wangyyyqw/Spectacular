import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, protected;
import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
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
  final ComputedStyle style;

  /// 行内样式区间。
  final List<StyledRun> runs;

  TextLayoutResult? _layout;

  /// 阶段一产出的行布局；未测量时为空。
  TextLayoutResult? get layout => _layout;

  @override
  void onLayout(LayoutConstraints constraints) {
    _layout = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: constraints.maxWidth,
      runs: runs,
    );
  }

  @override
  Size calculateSize(LayoutConstraints constraints) {
    final layout = _layout;
    if (layout == null || layout.lineCount == 0) {
      return constraints.constrain(Size.zero);
    }
    return constraints.constrain(Size(layout.width, layout.height));
  }
}

/// 纵向流式容器：子块依次向下排，高度相加、宽度取最大（§60.1、§60.4）。
class ColumnFlowBlock extends BlockFlow {
  /// 创建容器。
  ColumnFlowBlock([List<BlockFlow> children = const <BlockFlow>[]])
    : _children = List<BlockFlow>.unmodifiable(children);

  final List<BlockFlow> _children;

  @override
  List<BlockFlow> get children => _children;

  @override
  void onLayout(LayoutConstraints constraints) {
    var remaining = constraints.maxHeight;
    for (final child in _children) {
      child.measure(
        LayoutConstraints(maxWidth: constraints.maxWidth, maxHeight: remaining),
      );
      if (remaining.isFinite) {
        remaining = math.max(0.0, remaining - child.size.height);
      }
    }
  }

  @override
  Size calculateSize(LayoutConstraints constraints) {
    var width = 0.0;
    var height = 0.0;
    for (final child in _children) {
      width = math.max(width, child.size.width);
      height += child.size.height;
    }
    return constraints.constrain(Size(width, height));
  }
}
