import 'dart:math' as math;

import '../css/computed_style.dart';
import 'intrinsic_widths.dart';

/// 盒模型尺寸合成：把样式里的 width/height/padding/border/margin/box-sizing
/// 解算成盒尺寸（CSS 2.1 §10，逻辑像素）。
///
/// 只做纯计算：不测量文本、不依赖 Flutter Canvas、无副作用。
class BoxModel {
  const BoxModel._({
    required this.contentWidth,
    required this.contentHeight,
    required this.declaredHeight,
    required this.padding,
    required this.borders,
    required this.margin,
    required this.boxSizing,
    required this.minWidth,
    required this.maxWidth,
    required this.minHeight,
    required this.maxHeight,
    required this.containingWidth,
    required this.intrinsicWidth,
  });

  /// 从计算样式解算盒模型。
  ///
  /// [containingWidth] 是百分比 width/padding 的基准；百分比 height 与 min/max
  /// 也按它解算（骨架期近似，等页高确定后再换成真实包含块高度）。
  factory BoxModel.fromStyle(
    ComputedStyle style, {
    required double containingWidth,
  }) {
    final padding = style.padding;
    // `border-style: none/hidden` 的边宽按 0 计（Chrome 语义）：边宽仍留在
    // 计算样式里（绘制层判定可见性），但盒模型不占位，避免 hidden 边框
    // 把内容挤偏、块宽撑大。
    double visibleWidth(CssBorderSide side) =>
        side.isVisible ? side.width : 0.0;
    final borders = CssEdges(
      top: visibleWidth(style.borders.top),
      right: visibleWidth(style.borders.right),
      bottom: visibleWidth(style.borders.bottom),
      left: visibleWidth(style.borders.left),
    );
    final horizontalInset = padding.horizontal + borders.horizontal;
    final verticalInset = padding.vertical + borders.vertical;
    final boxSizing = style.boxSizing;

    // 声明尺寸先按 box-sizing 折成内容尺寸：border-box 要扣掉对应 inset。
    double? bound(CssLength? length, double inset) => _resolveBound(
      length,
      base: containingWidth,
      inset: inset,
      boxSizing: boxSizing,
    );

    return BoxModel._(
      contentWidth: bound(style.width, horizontalInset),
      contentHeight: bound(style.height, verticalInset),
      declaredHeight: style.height,
      padding: padding,
      borders: borders,
      margin: style.margin,
      boxSizing: boxSizing,
      minWidth: style.minWidth,
      maxWidth: style.maxWidth,
      minHeight: style.minHeight,
      maxHeight: style.maxHeight,
      containingWidth: containingWidth,
      intrinsicWidth: style.intrinsicWidth,
    );
  }

  /// 已按 box-sizing 解算的内容盒宽；auto 或未声明为 null。
  final double? contentWidth;

  /// 已按 box-sizing 解算的内容盒高；auto 或未声明为 null。
  final double? contentHeight;

  /// 原始 height 声明；百分比高度要等包含块高度已知后再解算。
  final CssLength? declaredHeight;

  /// 四边 padding（逻辑像素）。
  final CssEdges padding;

  /// 四边边框宽度（逻辑像素）。
  final CssEdges borders;

  /// 四边 margin（逻辑像素）。
  final CssEdges margin;

  /// 尺寸解释方式。
  final CssBoxSizing boxSizing;

  /// 最小宽（保留原始声明，供调用方复查）。
  final CssLength? minWidth;

  /// 最大宽。
  final CssLength? maxWidth;

  /// 最小高。
  final CssLength? minHeight;

  /// 最大高。
  final CssLength? maxHeight;

  /// 百分比尺寸的解算基准。
  final double containingWidth;

  /// 仅在调用方提供内容测量结果时消费，不干预原有 auto 和替换元素路径。
  final CssIntrinsicWidth? intrinsicWidth;

  /// padding + border 的水平总和。
  double get horizontalInset => padding.horizontal + borders.horizontal;

  /// padding + border 的垂直总和。
  double get verticalInset => padding.vertical + borders.vertical;

  /// 由内容宽得到边框盒宽。
  double borderBoxWidth(double contentWidth) =>
      math.max(0.0, contentWidth) + horizontalInset;

  /// 由内容高得到边框盒高。
  double borderBoxHeight(double contentHeight) =>
      math.max(0.0, contentHeight) + verticalInset;

  /// 解算内容宽：auto 取可用宽减去 inset 与 margin，声明宽直接用 box-sizing
  /// 折出的内容宽，最后按 min/max 钳制（min 优先于 max）。
  double resolveContentWidth(
    double availableWidth, {
    IntrinsicWidths? intrinsicWidths,
  }) {
    final autoWidth = math.max(
      0.0,
      availableWidth - horizontalInset - margin.horizontal,
    );
    final min = _resolveBound(
      minWidth,
      base: containingWidth,
      inset: horizontalInset,
      boxSizing: boxSizing,
    );
    final max = _resolveBound(
      maxWidth,
      base: containingWidth,
      inset: horizontalInset,
      boxSizing: boxSizing,
    );
    final intrinsic = intrinsicWidths == null || intrinsicWidth == null
        ? null
        : intrinsicWidths.resolve(intrinsicWidth!, autoWidth);
    return _clamp(intrinsic ?? contentWidth ?? autoWidth, min, max);
  }

  /// 解算内容高：未声明高度用测量值，声明高度按 box-sizing 解算后按 min/max
  /// 钳制（min 优先于 max）。
  ///
  /// [containingHeight] 预留给后续页高相关的百分比高度解算，本阶段不参与计算。
  double resolveContentHeight(
    double measuredContentHeight, {
    required double containingHeight,
  }) {
    // 百分比高度相对包含块高度；尚未提供包含块高度时使用宽度基准。
    final verticalBase = containingHeight > 0
        ? containingHeight
        : containingWidth;
    final height =
        _resolveBound(
          declaredHeight,
          base: verticalBase,
          inset: verticalInset,
          boxSizing: boxSizing,
        ) ??
        math.max(0.0, measuredContentHeight);
    final min = _resolveBound(
      minHeight,
      base: verticalBase,
      inset: verticalInset,
      boxSizing: boxSizing,
    );
    final max = _resolveBound(
      maxHeight,
      base: verticalBase,
      inset: verticalInset,
      boxSizing: boxSizing,
    );
    return _clamp(height, min, max);
  }

  /// 百分比/像素长度按 box-sizing 解成内容尺寸；auto 返回 null。
  static double? _resolveBound(
    CssLength? length, {
    required double base,
    required double inset,
    required CssBoxSizing boxSizing,
  }) {
    if (length == null || length.isAuto) {
      return null;
    }
    final declared = length.resolve(base);
    if (declared == null) {
      return null;
    }
    final value = boxSizing == CssBoxSizing.borderBox
        ? declared - inset
        : declared;
    return math.max(0.0, value);
  }

  /// 尺寸钳制：先钳下限 0，再取 max，最后取 min（CSS 2.1 §10.4：min 优先）。
  static double _clamp(double value, double? min, double? max) {
    var result = math.max(0.0, value);
    if (max != null) {
      result = math.min(result, max);
    }
    if (min != null) {
      result = math.max(result, min);
    }
    return result;
  }

  @override
  String toString() =>
      'BoxModel(content=$contentWidth×$contentHeight, padding=$padding, '
      'borders=$borders, margin=$margin, boxSizing=$boxSizing)';
}
