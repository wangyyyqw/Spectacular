import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show listEquals;

import 'length.dart';

/// 背景平铺方式（CSS background-repeat）。
enum CssBackgroundRepeatMode { repeat, noRepeat, space, round }

/// 每个轴独立的平铺模式；旧四种常量保持原调用方式。
class CssBackgroundRepeat {
  const CssBackgroundRepeat.axes(this.x, this.y);

  static const repeat = CssBackgroundRepeat.axes(
    CssBackgroundRepeatMode.repeat,
    CssBackgroundRepeatMode.repeat,
  );
  static const repeatX = CssBackgroundRepeat.axes(
    CssBackgroundRepeatMode.repeat,
    CssBackgroundRepeatMode.noRepeat,
  );
  static const repeatY = CssBackgroundRepeat.axes(
    CssBackgroundRepeatMode.noRepeat,
    CssBackgroundRepeatMode.repeat,
  );
  static const noRepeat = CssBackgroundRepeat.axes(
    CssBackgroundRepeatMode.noRepeat,
    CssBackgroundRepeatMode.noRepeat,
  );

  final CssBackgroundRepeatMode x;
  final CssBackgroundRepeatMode y;

  /// 新的间隔/缩放模式按完整绘制区铺图；旧入口保留其既有裁剪范围。
  bool get hasSpacing =>
      x == CssBackgroundRepeatMode.space ||
      y == CssBackgroundRepeatMode.space ||
      x == CssBackgroundRepeatMode.round ||
      y == CssBackgroundRepeatMode.round;

  @override
  bool operator ==(Object other) =>
      other is CssBackgroundRepeat && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'CssBackgroundRepeat(${x.name},${y.name})';
}

/// 背景尺寸模式（CSS background-size）。
enum CssBackgroundSizeMode { auto, cover, contain, explicit }

/// 背景尺寸：关键字或明确宽高（auto 表示该维按比例）。
class CssBackgroundSize {
  /// 关键字尺寸。
  const CssBackgroundSize.keyword(this.mode) : width = null, height = null;

  /// 明确尺寸（可为 auto）。
  const CssBackgroundSize.explicit({this.width, this.height})
    : mode = CssBackgroundSizeMode.explicit;

  /// 模式。
  final CssBackgroundSizeMode mode;

  /// 宽（explicit 模式）。
  final CssLength? width;

  /// 高（explicit 模式）。
  final CssLength? height;

  /// 未指定宽度，由图片固有比例决定。
  bool get autoWidth =>
      mode == CssBackgroundSizeMode.auto ||
      (mode == CssBackgroundSizeMode.explicit && (width?.isAuto ?? true));

  /// 未指定高度，由图片固有比例决定。
  bool get autoHeight =>
      mode == CssBackgroundSizeMode.auto ||
      (mode == CssBackgroundSizeMode.explicit && (height?.isAuto ?? true));

  @override
  bool operator ==(Object other) =>
      other is CssBackgroundSize &&
      other.mode == mode &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(mode, width, height);
}

/// 背景位置（CSS background-position，关键字已折算成百分比/像素）。
class CssBackgroundPosition {
  /// 创建位置。
  const CssBackgroundPosition({required this.x, required this.y});

  /// 水平位置。
  final CssLength x;

  /// 垂直位置。
  final CssLength y;

  @override
  bool operator ==(Object other) =>
      other is CssBackgroundPosition && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// 背景绘制区域（CSS background-origin 的基础）。
enum CssBackgroundOrigin { borderBox, paddingBox, contentBox }

/// 背景裁剪区域（CSS background-clip）。
enum CssBackgroundClip { borderBox, paddingBox, contentBox, text }

/// 一个背景层（CSS 多背景按声明顺序从前到后排列）。
class CssBackgroundLayer {
  /// 创建背景层。
  const CssBackgroundLayer({
    this.image,
    this.gradient,
    this.repeat = CssBackgroundRepeat.repeat,
    this.size = const CssBackgroundSize.keyword(CssBackgroundSizeMode.auto),
    this.position = const CssBackgroundPosition(
      x: CssLength(0, isPercent: true),
      y: CssLength(0, isPercent: true),
    ),
    this.origin = CssBackgroundOrigin.paddingBox,
    this.clip = CssBackgroundClip.borderBox,
  });

  /// 背景图 URL；与 [gradient] 互斥。
  final String? image;

  /// 背景渐变；与 [image] 互斥。
  final CssGradient? gradient;

  /// 平铺方式。
  final CssBackgroundRepeat repeat;

  /// 背景尺寸。
  final CssBackgroundSize size;

  /// 背景位置。
  final CssBackgroundPosition position;

  /// 定位区域。
  final CssBackgroundOrigin origin;

  /// 裁剪区域。
  final CssBackgroundClip clip;

  @override
  bool operator ==(Object other) =>
      other is CssBackgroundLayer &&
      other.image == image &&
      other.gradient == gradient &&
      other.repeat == repeat &&
      other.size == size &&
      other.position == position &&
      other.origin == origin &&
      other.clip == clip;

  @override
  int get hashCode =>
      Object.hash(image, gradient, repeat, size, position, origin, clip);
}

/// 渐变色标（CSS `<color-stop>`）。
///
/// 位置三者择一：[position]（百分比换算的比例，普通渐变 0–1，repeating 渐变
/// 可 >1）、[positionPx]（像素/em 已解算）或都为 null（自动分布）。
/// 绘制层用 [fractionOf] 统一换算。
class CssGradientStop {
  /// 创建色标。
  const CssGradientStop({required this.color, this.position, this.positionPx});

  /// 颜色。
  final Color color;

  /// 位置比例（来自百分比；repeating 渐变可 >1）；null 表示未声明或像素位置。
  final double? position;

  /// 位置（像素，em 已按字号解算）；null 表示未声明或百分比位置。
  final double? positionPx;

  /// 换算成 0–1 比例：百分比直接返回；像素按 [extent]（渐变线长度或盒子
  /// 尺寸）换算；未声明位置或 [extent] ≤ 0 时返回 null（由绘制层均分）。
  double? fractionOf(double extent) {
    if (position != null) {
      return position;
    }
    final px = positionPx;
    if (px == null || extent <= 0) {
      return null;
    }
    return px / extent;
  }

  @override
  bool operator ==(Object other) =>
      other is CssGradientStop &&
      other.color == color &&
      other.position == position &&
      other.positionPx == positionPx;

  @override
  int get hashCode => Object.hash(color, position, positionPx);

  @override
  String toString() =>
      'CssGradientStop($color,${position ?? positionPx ?? "auto"})';
}

/// 背景渐变（`background-image: <gradient>` 的解析结果）。
///
/// 线性、径向和基础锥形渐变共用色标；前两者可重复。
/// 每个背景层独立保存一个渐变，绘制层按具体类型创建 shader。
sealed class CssGradient {
  const CssGradient({required this.stops, this.repeating = false});

  /// 色标（按声明顺序，至少 2 个）。
  final List<CssGradientStop> stops;

  /// 是否 `repeating-linear-gradient` / `repeating-radial-gradient`。
  ///
  /// true 时绘制层按色标区间循环平铺（最后一个色标到第一个色标的距离
  /// 即重复周期）。
  final bool repeating;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is CssGradient &&
      other.repeating == repeating &&
      listEquals(other.stops, stops);

  @override
  int get hashCode =>
      Object.hash(runtimeType, repeating, Object.hashAll(stops));
}

/// 线性渐变。
///
/// [angle] 是 CSS 角度（0deg = 向上、90deg = 向右、顺时针），
/// `to <side|corner>` 已折算成角度，未声明方向时按规范默认 180deg（向下）。
final class CssLinearGradient extends CssGradient {
  /// 创建线性渐变。
  const CssLinearGradient({
    required super.stops,
    super.repeating,
    this.angle = 180,
  });

  /// 渐变角度（度）。
  final double angle;

  @override
  bool operator ==(Object other) =>
      other is CssLinearGradient && super == other && other.angle == angle;

  @override
  int get hashCode => Object.hash(angle, repeating, Object.hashAll(stops));

  @override
  String toString() =>
      'CssLinearGradient(${angle}deg,repeating=$repeating,$stops)';
}

/// 径向渐变形状。
enum CssRadialShape { circle, ellipse }

/// 径向渐变。
///
/// 不支持 extent 关键字（closest-side / farthest-corner 等）：绘制层按默认
/// farthest-corner 近似。[centerX]/[centerY] 支持百分比（默认 50%）与像素。
final class CssRadialGradient extends CssGradient {
  /// 创建径向渐变。
  const CssRadialGradient({
    required super.stops,
    super.repeating,
    this.shape = CssRadialShape.ellipse,
    this.centerX = const CssLength(50, isPercent: true),
    this.centerY = const CssLength(50, isPercent: true),
  });

  /// 形状（`circle` / `ellipse`）。
  final CssRadialShape shape;

  /// 中心点水平位置（百分比按盒子宽解算）。
  final CssLength centerX;

  /// 中心点垂直位置（百分比按盒子高解算）。
  final CssLength centerY;

  @override
  bool operator ==(Object other) =>
      other is CssRadialGradient &&
      super == other &&
      other.shape == shape &&
      other.centerX == centerX &&
      other.centerY == centerY;

  @override
  int get hashCode =>
      Object.hash(shape, centerX, centerY, repeating, Object.hashAll(stops));

  @override
  String toString() =>
      'CssRadialGradient(${shape.name},repeating=$repeating,'
      '$centerX/$centerY,$stops)';
}

/// 基础锥形渐变：中心、十二点起始、顺时针、颜色均分。
///
/// 解析器只接受至少两个不带位置的颜色；不模拟未支持的前置参数或重复。
final class CssConicGradient extends CssGradient {
  const CssConicGradient({required super.stops});

  @override
  String toString() => 'CssConicGradient($stops)';
}
