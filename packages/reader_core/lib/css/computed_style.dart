import 'dart:math' as math;
import 'dart:ui' show Color, Radius, Size;

import 'package:csslib/parser.dart' as csslib;

import 'property_aliases.dart';

/// 文本对齐（避免把 Flutter 枚举带进纯解析层）。
enum CssTextAlign { start, end, left, right, center, justify }

/// 两端对齐的拉伸方式（CSS `text-justify`；P7-21，CSS Text 3）。
///
/// `auto`：现状行为——含 CJK 的行全 gap 分配、西文行只拉伸词间空格；
/// `interWord`：只拉伸词间空格；`interCharacter`/`distribute`：全 gap
/// 分配（不豁免拉丁词内）；`justifyAll`：gap 同 auto，末行也拉伸。
enum CssTextJustify { auto, interWord, interCharacter, distribute, justifyAll }

/// 定位方式（§60.2 第 1 条：absolute/fixed 先摘出流）。
enum CssPosition { static, relative, absolute, fixed, sticky }

/// 绝对定位盒的解算结果（CSS 2.1 §10.3.7 / §10.6.4，非替换块级元素）。
///
/// 语义：`null` 一律表示 CSS 的 `auto`。
/// - [left]/[right]/[top]/[bottom]：已按包含块尺寸解算的偏移（百分比已换算）；
/// - [width]/[height]：已解算的尺寸；null 表示需要布局层 shrink-to-fit；
/// - 两侧偏移都给了、尺寸是 auto 时，尺寸已由偏移推出；
/// - 只给一侧偏移且尺寸已知时，另一侧偏移已推出（方便贴右/贴底）。
/// - 左右都为 null 时用**静态位置**（布局层按正常流位置摆放）。
class CssAbsoluteBox {
  /// 创建解算结果。
  const CssAbsoluteBox({
    this.left,
    this.right,
    this.top,
    this.bottom,
    this.width,
    this.height,
  });

  /// 左偏移（null = auto）。
  final double? left;

  /// 右偏移（null = auto）。
  final double? right;

  /// 上偏移（null = auto）。
  final double? top;

  /// 下偏移（null = auto）。
  final double? bottom;

  /// 宽度（null = auto，需要 shrink-to-fit）。
  final double? width;

  /// 高度（null = auto）。
  final double? height;

  @override
  String toString() =>
      'CssAbsoluteBox(l=${left ?? "auto"},r=${right ?? "auto"},'
      't=${top ?? "auto"},b=${bottom ?? "auto"},'
      'w=${width ?? "auto"},h=${height ?? "auto"})';
}

/// 浮动方向（§60.2 第 2 条）。
enum CssFloat { none, left, right }

/// 显示类型，只保留测量分派需要的一档。
enum CssDisplay {
  block,
  inline,
  inlineBlock,
  table,
  tableRow,
  tableCell,
  flex,
  listItem,
  none,
}

/// 可见性（CSS visibility 属性）。
enum CssVisibility { visible, hidden, collapse }

/// 空白与换行处理（CSS white-space 属性）。
enum CssWhiteSpace { normal, nowrap, pre, preWrap, preLine }

/// 标点悬挂（CSS `hanging-punctuation`；P7-18，CSS Text 4）。
///
/// 本引擎只实现 `allow-end` 语义：两端对齐的非末行行尾句读挂到版心
/// 右缘外；`none`（默认）关闭。其余取值（allow-start 等）按 none 处理。
enum CssHangingPunctuation { none, allowEnd }

/// 标点挤压（CSS `text-spacing-trim`；P7-19，CSS Text 4 语义子集）。
///
/// [trimAdjacent]：相邻全角标点挤掉中间整格空白（前标点加 -0.5em 字距）。
/// 这是 **未声明时的默认值**：Chrome 的 `text-spacing-trim` 初始值是
/// `normal`，实测会把相邻全角标点折到半角（用例 01「：、」各 8.5px/17px），
/// 所以默认必须开启才对得上浏览器。
/// [normal]：不挤压，对应显式 `space-all`（成员名沿用旧枚举，改名会波及
/// layout 层调用点，语义以本注释为准）。
enum CssTextSpacingTrim { normal, trimAdjacent }

/// 中西文自动间距（CSS `text-autospace`；P7-20，语义子集）。
///
/// `normal`（书内显式声明）在 CJK↔拉丁边界插 0.125em 视觉间距；
/// **未声明默认 none**——与 §38.2「书里有什么就是什么」一致（与规范
/// 初始值 normal=启用的偏差在解析层注明）；`no-autospace` 显式关闭。
enum CssTextAutospace { none, normal }

/// 文本大小写变换（CSS text-transform 属性）。
enum CssTextTransform { none, uppercase, lowercase, capitalize }

/// 行内垂直对齐（CSS vertical-align 属性）。
enum CssVerticalAlign { baseline, subscript, superscript, middle, top, bottom }

/// 文本装饰线（CSS `text-decoration-line`）。
///
/// 规范允许同时声明多条线，枚举保存全部非空组合，避免
/// `overline line-through` 被解析成其中一条。
enum CssTextDecoration {
  none,
  underline,
  lineThrough,
  overline,
  underlineLineThrough,
  underlineOverline,
  lineThroughOverline,
  underlineLineThroughOverline,
}

extension CssTextDecorationFlags on CssTextDecoration {
  bool get hasUnderline =>
      this == CssTextDecoration.underline ||
      this == CssTextDecoration.underlineLineThrough ||
      this == CssTextDecoration.underlineOverline ||
      this == CssTextDecoration.underlineLineThroughOverline;

  bool get hasLineThrough =>
      this == CssTextDecoration.lineThrough ||
      this == CssTextDecoration.underlineLineThrough ||
      this == CssTextDecoration.lineThroughOverline ||
      this == CssTextDecoration.underlineLineThroughOverline;

  bool get hasOverline =>
      this == CssTextDecoration.overline ||
      this == CssTextDecoration.underlineOverline ||
      this == CssTextDecoration.lineThroughOverline ||
      this == CssTextDecoration.underlineLineThroughOverline;

  /// 按浏览器计算值的固定顺序展开为单线枚举。
  List<CssTextDecoration> get lineKinds => [
    if (hasUnderline) CssTextDecoration.underline,
    if (hasLineThrough) CssTextDecoration.lineThrough,
    if (hasOverline) CssTextDecoration.overline,
  ];
}

/// 装饰线线型（CSS `text-decoration-style`，P9-18）。
enum CssTextDecorationStyle { solid, double, dotted, dashed, wavy }

/// 着重号样式（CSS `text-emphasis-style`，P2-17）。
///
/// CSS 的「填充/空心」与「点/圆/芝麻点」是两个维度；枚举保存组合值，
/// 避免把 `open circle` 错降成空心圆点或把 `filled sesame` 画成圆点。
enum CssTextEmphasisStyle {
  none,
  dot,
  openDot,
  circle,
  openCircle,
  sesame,
  openSesame,
}

/// 着重号位置（CSS text-emphasis-position 属性）。
enum CssTextEmphasisPosition { over, under }

/// 縦中横（CSS Writing Modes §9.1 `text-combine-upright`）：竖排里把 2–4 位
/// 数字合并成一个正立字块、纵向只占 1em。
enum CssTextCombine { none, all }

/// 注音位置（CSS Ruby 1 §5 `ruby-position`）：横排 over=字上/under=字下，
/// 竖排 over=列右/under=列左。
enum CssRubyPosition { over, under }

/// 注音对齐（CSS Ruby 1 §5 `ruby-align`）：注音在基字区间内的水平对齐。
enum CssRubyAlign { start, center, end, spaceBetween }

/// 文本阴影（CSS text-shadow，P2-18：P0 收口补全）。
class CssTextShadow {
  /// 创建阴影。
  const CssTextShadow({
    required this.offsetX,
    required this.offsetY,
    required this.blur,
    this.color,
  });

  /// 水平偏移（像素）。
  final double offsetX;

  /// 垂直偏移（像素）。
  final double offsetY;

  /// 模糊半径（像素）。
  final double blur;

  /// 阴影颜色；null 表示跟随文字颜色。
  final Color? color;
}

/// 背景平铺方式（CSS background-repeat）。
enum CssBackgroundRepeat { repeat, repeatX, repeatY, noRepeat }

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
}

/// 背景位置（CSS background-position，关键字已折算成百分比/像素）。
class CssBackgroundPosition {
  /// 创建位置。
  const CssBackgroundPosition({required this.x, required this.y});

  /// 水平位置。
  final CssLength x;

  /// 垂直位置。
  final CssLength y;
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
/// 支持 `linear-gradient()` / `radial-gradient()` 及其 `repeating-` 变体
/// （[repeating] 标记）；不支持 conic、多背景层。读取点：绘制层按
/// [CssLinearGradient] / [CssRadialGradient] 分派，[stops] 至少 2 个，
/// 位置用 [CssGradientStop.fractionOf] 换算。
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
      _listEquals(other.stops, stops);

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

/// 滤镜函数种类（CSS `filter`）。
///
/// 绘制层映射建议（T4）：blur → `ImageFilter.blur`；grayscale/sepia/
/// brightness/contrast/saturate/hueRotate/invert/opacity → `ColorFilter.matrix`
/// （或 saveLayer 的 alpha）；dropShadow → Skia 无原生 drop-shadow，按
/// 「blur + 偏移重绘形状」近似。
enum CssFilterKind {
  /// `blur(<length>)`：高斯模糊。
  blur,

  /// `grayscale()`：去色。
  grayscale,

  /// `sepia()`：褐色调。
  sepia,

  /// `brightness()`：亮度倍数。
  brightness,

  /// `contrast()`：对比度倍数。
  contrast,

  /// `saturate()`：饱和度倍数。
  saturate,

  /// `hue-rotate(<angle>)`：色相旋转（度）。
  hueRotate,

  /// `invert()`：反相。
  invert,

  /// `opacity()`：整体透明度（滤镜函数，非 `opacity` 属性）。
  opacity,

  /// `drop-shadow(...)`：投影（见 [CssFilter.shadow]）。
  dropShadow,
}

/// `filter: drop-shadow()` 的阴影（只有偏移/模糊/颜色，没有 spread/inset）。
class CssDropShadow {
  /// 创建投影。
  const CssDropShadow({
    required this.offsetX,
    required this.offsetY,
    this.blur = 0,
    this.color = const Color(0xFF000000),
  });

  /// 水平偏移（右为正）。
  final double offsetX;

  /// 垂直偏移（下为正）。
  final double offsetY;

  /// 模糊半径（≥0）。
  final double blur;

  /// 阴影色。
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is CssDropShadow &&
      other.offsetX == offsetX &&
      other.offsetY == offsetY &&
      other.blur == blur &&
      other.color == color;

  @override
  int get hashCode => Object.hash(offsetX, offsetY, blur, color);

  @override
  String toString() => 'CssDropShadow($offsetX,$offsetY,blur=$blur,$color)';
}

/// CSS `filter` 里的单个滤镜（有序列表的一项，按声明顺序合成）。
///
/// [amount] 的单位随 [kind]：blur 为像素半径；grayscale/sepia/invert/opacity
/// 为 0–1 比例（CSS 允许 >1，绘制层自行钳制）；brightness/contrast/saturate
/// 为倍数（1 = 原样）；hueRotate 为角度（度）；dropShadow 不使用该字段。
class CssFilter {
  /// 创建滤镜。
  const CssFilter({required this.kind, this.amount = 0, this.shadow});

  /// 滤镜种类。
  final CssFilterKind kind;

  /// 数值参数（含义见类注释）。
  final double amount;

  /// `drop-shadow` 的参数；其余种类为 null。
  final CssDropShadow? shadow;

  @override
  bool operator ==(Object other) =>
      other is CssFilter &&
      other.kind == kind &&
      other.amount == amount &&
      other.shadow == shadow;

  @override
  int get hashCode => Object.hash(kind, amount, shadow);

  @override
  String toString() =>
      'CssFilter(${kind.name},$amount${shadow == null ? "" : ",$shadow"})';
}

/// `transform` 函数种类（绘制层按 [CssTransform.kind] 分派）。
enum CssTransformKind {
  /// `translate(x[, y])` / `translateX` / `translateY`。
  translate,

  /// `scale(x[, y])` / `scaleX` / `scaleY`。
  scale,

  /// `rotate(<angle>)`。
  rotate,

  /// `skew(ax[, ay])` / `skewX` / `skewY`。
  skew,

  /// `matrix(a, b, c, d, e, f)`。
  matrix,
}

/// `transform` 里的单个变换函数（有序列表的一项，绘制层按声明顺序合成）。
///
/// 各 [kind] 使用哪些字段：
/// - [CssTransformKind.translate]：[x]、[y]（[CssLength]，**百分比保留标记**，
///   基准分别是边框盒**宽**/**高**，由绘制层 `resolve(宽/高)` 解算）；
/// - [CssTransformKind.scale]：[sx]、[sy]（倍数；[sy] 为 null 表示同 [sx]）；
/// - [CssTransformKind.rotate]：[angleDeg]；
/// - [CssTransformKind.skew]：[axDeg]、[ayDeg]；
/// - [CssTransformKind.matrix]：[values]（a,b,c,d,e,f 六个分量）。
///
/// 角度一律用度，CSS 顺时针为正（绘制层转弧度时注意 y 轴向下）。
class CssTransform {
  /// 创建变换（按 [kind] 取用对应字段，未用到的保持 null/0）。
  const CssTransform({
    required this.kind,
    this.x,
    this.y,
    this.sx,
    this.sy,
    this.angleDeg,
    this.axDeg = 0,
    this.ayDeg = 0,
    this.values,
  });

  /// 种类。
  final CssTransformKind kind;

  /// translate 的水平位移（百分比基准 = 边框盒宽）。
  final CssLength? x;

  /// translate 的垂直位移（百分比基准 = 边框盒高）。
  final CssLength? y;

  /// scale 的水平倍数。
  final double? sx;

  /// scale 的垂直倍数；null 表示同 [sx]。
  final double? sy;

  /// rotate 的角度（度）。
  final double? angleDeg;

  /// skew 的水平斜切角（度）。
  final double axDeg;

  /// skew 的垂直斜切角（度）。
  final double ayDeg;

  /// matrix 的六个分量 `[a, b, c, d, e, f]`。
  final List<double>? values;

  @override
  bool operator ==(Object other) =>
      other is CssTransform &&
      other.kind == kind &&
      other.x == x &&
      other.y == y &&
      other.sx == sx &&
      other.sy == sy &&
      other.angleDeg == angleDeg &&
      other.axDeg == axDeg &&
      other.ayDeg == ayDeg &&
      _listEquals(other.values ?? const <double>[], values ?? const <double>[]);

  @override
  int get hashCode => Object.hash(
    kind,
    x,
    y,
    sx,
    sy,
    angleDeg,
    axDeg,
    ayDeg,
    Object.hashAll(values ?? const <double>[]),
  );

  @override
  String toString() => switch (kind) {
    CssTransformKind.translate => 'CssTransform.translate($x,$y)',
    CssTransformKind.scale => 'CssTransform.scale($sx,${sy ?? sx})',
    CssTransformKind.rotate => 'CssTransform.rotate(${angleDeg}deg)',
    CssTransformKind.skew => 'CssTransform.skew(${axDeg}deg,${ayDeg}deg)',
    CssTransformKind.matrix => 'CssTransform.matrix($values)',
  };
}

/// 书写模式（CSS `writing-mode`）。
enum CssWritingMode {
  /// 横排，行自上而下（默认）。
  horizontalTb,

  /// 竖排，列从右向左（中文古籍/繁体书常见）。
  verticalRl,

  /// 竖排，列从左向右。
  verticalLr,
}

/// 竖排时的字向（CSS `text-orientation`）。
enum CssTextOrientation {
  /// 默认：拉丁字母侧躺、CJK 直立。
  mixed,

  /// 全部直立。
  upright,

  /// 全部侧躺。
  sideways,
}

/// 文本方向（CSS `direction`）。
enum CssDirection {
  /// 从左到右（默认）。
  ltr,

  /// 从右到左。
  rtl,
}

/// 溢出处理（CSS `overflow`）。
enum CssOverflow {
  /// 默认：外溢内容照常绘制（不裁剪）。
  visible,

  /// 裁剪并允许滚动（静态分页下等价于裁剪）。
  hidden,

  /// 裁剪，禁止滚动。
  clip,

  /// 需要滚动条（静态分页下按 hidden 处理）。
  auto,

  /// 总是滚动条（静态分页下按 hidden 处理）。
  scroll,
}

/// 小型大写字母族（CSS `font-variant-caps`，也来自 `font-variant` 简写）。
enum CssFontVariantCaps {
  /// 默认：不做小型大写。
  normal,

  /// 小写字母转小型大写（`small-caps`）。
  smallCaps,

  /// 全部字母（含原本大写）都用小型大写（`all-small-caps`）。
  allSmallCaps,

  /// 小型大写的小号变体（`petite-caps`）。
  petiteCaps,

  /// 全部字母用 petite-caps（`all-petite-caps`）。
  allPetiteCaps,

  /// 大小写混排成同高（`unicase`）。
  unicase,

  /// 标题用大写（`titling-caps`）。
  titlingCaps,
}

/// 连字策略（CSS `font-variant-ligatures`）。
enum CssFontVariantLigatures {
  /// 使用字体默认的常用连字。
  normal,

  /// 关闭常用连字和上下文连字（`none` / `no-common-ligatures`）。
  none,
}

/// 一对引号（CSS `quotes` 的 `<string> <string>`）。
class CssQuotePair {
  /// 创建一对引号。
  const CssQuotePair({required this.open, required this.close});

  /// 开引号（如 `"“"`）。
  final String open;

  /// 闭引号（如 `"”"`）。
  final String close;

  @override
  bool operator ==(Object other) =>
      other is CssQuotePair && other.open == open && other.close == close;

  @override
  int get hashCode => Object.hash(open, close);

  @override
  String toString() => 'CssQuotePair($open,$close)';
}

/// 引号规则（CSS `quotes`，继承）。
///
/// 三态：`auto`（按语言默认，初始值）、`none`（不生成引号）、显式引号对。
/// 消费点在行内文本生成阶段（`<q>` 的开/闭引号插入与嵌套层级取第几对）。
sealed class CssQuotes {
  const CssQuotes();
}

/// `quotes: auto`：按语言/UA 默认（浏览器初始值）。
final class CssQuotesAuto extends CssQuotes {
  /// 创建 auto 规则。
  const CssQuotesAuto();

  @override
  bool operator ==(Object other) => other is CssQuotesAuto;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'CssQuotes.auto';
}

/// `quotes: none`：不生成任何引号。
final class CssQuotesNone extends CssQuotes {
  /// 创建 none 规则。
  const CssQuotesNone();

  @override
  bool operator ==(Object other) => other is CssQuotesNone;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'CssQuotes.none';
}

/// 显式引号对列表（按嵌套层级取用：第 1 对最外层，超出后循环最后一对）。
final class CssQuotesPairs extends CssQuotes {
  /// 创建显式引号对。
  const CssQuotesPairs(this.pairs);

  /// 引号对（至少 1 对）。
  final List<CssQuotePair> pairs;

  @override
  bool operator ==(Object other) =>
      other is CssQuotesPairs && _listEquals(other.pairs, pairs);

  @override
  int get hashCode => Object.hashAll(pairs);

  @override
  String toString() => 'CssQuotes.pairs($pairs)';
}

/// 连字符断行（CSS `hyphens`；`-epub-hyphens`/`-webkit-hyphens` 经别名表落到它）。
enum CssHyphens {
  /// 不自动断行（默认）。
  none,

  /// 只在显式软连字符（U+00AD）处断行。
  manual,

  /// 允许引擎按语言词典自动加连字符。
  auto,
}

/// 断词/断行策略（CSS `word-break`）。
/// 断行严格度（CSS Text 3 `line-break`）。
enum CssLineBreak { auto, loose, normal, strict, anywhere }

/// 混合模式（CSS Compositing `mix-blend-mode`，只建模分页阅读器可近似的几种）。
enum CssMixBlendMode { normal, multiply, screen, overlay, darken, lighten }

enum CssWordBreak {
  /// 默认：只在正常断行点断（CJK 任意处、拉丁按词）。
  normal,

  /// 任意字符处都可断（`break-all`，常用于长 URL/代码）。
  breakAll,

  /// 禁止 CJK 文本内部断行（`keep-all`）。
  keepAll,
}

/// 长词换行策略（CSS `overflow-wrap`，旧名 `word-wrap`）。
enum CssOverflowWrap {
  /// 默认：只在正常断行点断。
  normal,

  /// 单词过长会溢出时，才在单词内部断行（`break-word`）。
  breakWord,

  /// 任意位置都可断行（`anywhere`，且会影响最小内容宽）。
  anywhere,
}

/// 清除浮动（CSS clear）。
enum CssClear { none, left, right, both }

/// 表格列宽算法（CSS `table-layout`，P9-17）。
enum CssTableLayout {
  /// 自动：按内容自然宽分配。
  auto,

  /// 固定：按 `col`/首行声明宽分配，剩余平分。
  fixed,
}

/// 列表标记类型（CSS `list-style-type`，P9-12）。
enum CssListStyleType {
  /// 实心圆点。
  disc,

  /// 空心圆。
  circle,

  /// 方块。
  square,

  /// 阿拉伯数字。
  decimal,

  /// 小写罗马数字。
  lowerRoman,

  /// 大写罗马数字。
  upperRoman,

  /// 小写字母。
  lowerAlpha,

  /// 大写字母。
  upperAlpha,

  /// 不显示标记。
  none,
}

/// 列表标记位置（CSS `list-style-position`；W2）。
///
/// `outside`（初始值）：标记在内容框外，正文首行不缩进、换行不绕标记；
/// `inside`：标记作为首行内联内容，换行文字绕到标记下方。
enum CssListStylePosition { inside, outside }

/// 表格边框合并（CSS border-collapse）。
enum CssBorderCollapse { separate, collapse }

/// 四边长度（逻辑像素）。
class CssEdges {
  /// 创建四边。
  const CssEdges({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  /// 全零。
  static const zero = CssEdges(top: 0, right: 0, bottom: 0, left: 0);

  /// 上。
  final double top;

  /// 右。
  final double right;

  /// 下。
  final double bottom;

  /// 左。
  final double left;

  /// 水平总和。
  double get horizontal => left + right;

  /// 垂直总和。
  double get vertical => top + bottom;

  @override
  String toString() => 'CssEdges($top,$right,$bottom,$left)';
}

/// 尺寸值：像素 / 百分比 / auto。
///
/// 解析层只记录数值与单位标记，百分比按基准长度解算留到盒模型计算时。
class CssLength {
  /// 创建尺寸值；[isPercent] 为 true 时 [value] 是百分比数字（如 50 表示 50%）。
  const CssLength(this.value, {this.isAuto = false, this.isPercent = false});

  /// 关键字 `auto`。
  const CssLength.auto() : value = 0, isAuto = true, isPercent = false;

  /// 数值（像素或百分比数字）。
  final double value;

  /// 是否为关键字 `auto`。
  final bool isAuto;

  /// 是否为百分比。
  final bool isPercent;

  /// 按基准长度解算像素；auto 返回 null。
  double? resolve(double base) =>
      isAuto ? null : (isPercent ? value * base / 100 : value);

  @override
  String toString() => isAuto
      ? 'CssLength(auto)'
      : (isPercent ? 'CssLength($value%)' : 'CssLength($value)');
}

/// 盒模型尺寸基准（CSS `box-sizing`）。
enum CssBoxSizing { contentBox, borderBox }

/// 边框线型（CSS `border-style<border-style>`）。
enum CssBorderStyle {
  none,
  solid,
  dashed,
  dotted,
  double,
  groove,
  ridge,
  inset,
  outset,
}

/// 文本溢出（CSS `text-overflow`；P2-37 抽样：clip/ellipsis 两值，
/// 其余取值按 clip）。
enum CssTextOverflow { clip, ellipsis }

/// 块阴影（CSS `box-shadow`）。
///
/// 只取首个阴影（多阴影的下标/层叠顺序留给后续任务）；blur/spread/inset
/// 都保留，绘制层直接消费。
class CssBoxShadow {
  /// 创建阴影。
  const CssBoxShadow({
    required this.offsetX,
    required this.offsetY,
    required this.color,
    this.blur = 0,
    this.spread = 0,
    this.inset = false,
  });

  /// 水平偏移（右为正）。
  final double offsetX;

  /// 垂直偏移（下为正）。
  final double offsetY;

  /// 阴影色。
  final Color color;

  /// 模糊半径（≥0；未声明为 0）。
  final double blur;

  /// 扩张半径（可为负；未声明为 0）。
  final double spread;

  /// 是否为内阴影（`inset` 关键字）。
  final bool inset;

  @override
  bool operator ==(Object other) =>
      other is CssBoxShadow &&
      other.offsetX == offsetX &&
      other.offsetY == offsetY &&
      other.color == color &&
      other.blur == blur &&
      other.spread == spread &&
      other.inset == inset;

  @override
  int get hashCode => Object.hash(offsetX, offsetY, color, blur, spread, inset);

  @override
  String toString() =>
      'CssBoxShadow($offsetX,$offsetY,blur=$blur,spread=$spread,'
      'inset=$inset,$color)';
}

/// 一条边框：宽度、线型、颜色。
class CssBorderSide {
  /// 创建边框。
  const CssBorderSide({
    this.width = 0,
    this.style = CssBorderStyle.none,
    this.color = const Color(0xFF000000),
  });

  /// 无边框。
  static const none = CssBorderSide();

  /// 线宽（逻辑像素）。
  final double width;

  /// 线型。
  final CssBorderStyle style;

  /// 颜色。
  final Color color;

  /// 是否需要绘制。
  bool get isVisible => style != CssBorderStyle.none && width > 0;

  /// 换颜色。
  CssBorderSide withColor(Color value) =>
      CssBorderSide(width: width, style: style, color: value);

  @override
  String toString() => 'CssBorderSide($width,$style,$color)';
}

/// 元素轮廓（CSS `outline`）：不参与盒模型，绘制在边框盒外侧。
class CssOutline {
  /// 创建轮廓。
  const CssOutline({
    this.width = 3,
    this.style = CssBorderStyle.none,
    this.color = const Color(0xFF000000),
    this.offset = 0,
  });

  /// 无轮廓。
  static const none = CssOutline(width: 0);

  /// 线宽。
  final double width;

  /// 线型；`outline-style: auto` 在读入时按 `solid` 近似。
  final CssBorderStyle style;

  /// 轮廓色。
  final Color color;

  /// 边框盒到轮廓内缘的距离，可为负。
  final double offset;

  /// 是否需要绘制。
  bool get isVisible => style != CssBorderStyle.none && width > 0;
}

/// 出血方向（多看私有属性 `duokan-bleed`，P9-22）。
class CssBleed {
  /// 创建出血方向。
  const CssBleed({
    this.left = false,
    this.right = false,
    this.top = false,
    this.bottom = false,
  });

  /// 无出血。
  static const none = CssBleed();

  /// 左出血。
  final bool left;

  /// 右出血。
  final bool right;

  /// 上出血。
  final bool top;

  /// 下出血。
  final bool bottom;

  /// 是否任一方向出血。
  bool get any => left || right || top || bottom;
}

/// `border-image` 的边条填充方式（CSS Backgrounds §6.3）。
enum CssBorderImageRepeat { stretch, repeat, round, space }

/// `border-image`（CSS Backgrounds §6）：九宫格边图。
///
/// 真书里常见「`border: 20px solid transparent; border-image: url(frame.png)
/// 50 50 repeat`」做章首花纹框——边框本身透明，图像裁成九块贴到边框区域。
class CssBorderImage {
  /// 创建边图。
  const CssBorderImage({
    required this.url,
    required this.sliceTop,
    required this.sliceRight,
    required this.sliceBottom,
    required this.sliceLeft,
    this.slicePercent = false,
    this.repeat = CssBorderImageRepeat.stretch,
    this.fill = false,
  });

  /// 图片地址（章节源已解算为书内绝对路径）。
  final String url;

  /// 上下左右的切割量（像素；[slicePercent] 为 true 时是 0..1 的比例）。
  final double sliceTop;
  final double sliceRight;
  final double sliceBottom;
  final double sliceLeft;

  /// 切割量是否为图片尺寸的百分比。
  final bool slicePercent;

  /// 边条填充方式（四边共用；`space` 按 `repeat` 处理）。
  final CssBorderImageRepeat repeat;

  /// 是否绘制中间区域（`fill` 关键字）。
  final bool fill;
}

/// 四边边框与四角圆角。
class CssBorders {
  /// 创建边框集合。
  const CssBorders({
    this.top = CssBorderSide.none,
    this.right = CssBorderSide.none,
    this.bottom = CssBorderSide.none,
    this.left = CssBorderSide.none,
    this.topLeftRadius = 0,
    this.topRightRadius = 0,
    this.bottomRightRadius = 0,
    this.bottomLeftRadius = 0,
    this.topLeftRadiusPercent,
    this.topRightRadiusPercent,
    this.bottomRightRadiusPercent,
    this.bottomLeftRadiusPercent,
    this.topLeftRadiusY,
    this.topRightRadiusY,
    this.bottomRightRadiusY,
    this.bottomLeftRadiusY,
    this.topLeftRadiusPercentY,
    this.topRightRadiusPercentY,
    this.bottomRightRadiusPercentY,
    this.bottomLeftRadiusPercentY,
  });

  /// 无边框、无圆角。
  static const none = CssBorders();

  /// 上边框。
  final CssBorderSide top;

  /// 右边框。
  final CssBorderSide right;

  /// 下边框。
  final CssBorderSide bottom;

  /// 左边框。
  final CssBorderSide left;

  /// 左上圆角（像素；百分比圆角在 [topLeftRadiusPercent]，绘制时按盒尺寸解算）。
  final double topLeftRadius;

  /// 右上圆角。
  final double topRightRadius;

  /// 右下圆角。
  final double bottomRightRadius;

  /// 左下圆角。
  final double bottomLeftRadius;

  /// 左上圆角的百分比（0..1，null 表示像素圆角）。
  final double? topLeftRadiusPercent;

  /// 右上圆角的百分比（0..1）。
  final double? topRightRadiusPercent;

  /// 右下圆角的百分比（0..1）。
  final double? bottomRightRadiusPercent;

  /// 左下圆角的百分比（0..1）。
  final double? bottomLeftRadiusPercent;

  /// 左上圆角的纵向像素半径；null 表示与横向半径相同。
  final double? topLeftRadiusY;

  /// 右上圆角的纵向像素半径。
  final double? topRightRadiusY;

  /// 右下圆角的纵向像素半径。
  final double? bottomRightRadiusY;

  /// 左下圆角的纵向像素半径。
  final double? bottomLeftRadiusY;

  /// 左上圆角的纵向百分比（0..1）；null 表示纵向使用像素半径。
  final double? topLeftRadiusPercentY;

  /// 右上圆角的纵向百分比。
  final double? topRightRadiusPercentY;

  /// 右下圆角的纵向百分比。
  final double? bottomRightRadiusPercentY;

  /// 左下圆角的纵向百分比。
  final double? bottomLeftRadiusPercentY;

  /// 给定盒子尺寸下的像素圆角（CSS Backgrounds §5.1：百分比横向按盒宽、
  /// 纵向按盒高分别解算，因此非方盒上的百分比圆角是椭圆）。
  ({Radius topLeft, Radius topRight, Radius bottomRight, Radius bottomLeft})
  radiiFor(Size box) {
    Radius resolve(
      double radius,
      double? percent,
      double? radiusY,
      double? percentY,
    ) {
      final horizontal = percent == null ? radius : percent * box.width;
      final vertical = percentY != null
          ? percentY * box.height
          : radiusY ?? (percent == null ? radius : percent * box.height);
      return Radius.elliptical(horizontal, vertical);
    }

    return (
      topLeft: resolve(
        topLeftRadius,
        topLeftRadiusPercent,
        topLeftRadiusY,
        topLeftRadiusPercentY,
      ),
      topRight: resolve(
        topRightRadius,
        topRightRadiusPercent,
        topRightRadiusY,
        topRightRadiusPercentY,
      ),
      bottomRight: resolve(
        bottomRightRadius,
        bottomRightRadiusPercent,
        bottomRightRadiusY,
        bottomRightRadiusPercentY,
      ),
      bottomLeft: resolve(
        bottomLeftRadius,
        bottomLeftRadiusPercent,
        bottomLeftRadiusY,
        bottomLeftRadiusPercentY,
      ),
    );
  }

  /// 是否有任意可见边框。
  bool get hasBorder =>
      top.isVisible || right.isVisible || bottom.isVisible || left.isVisible;

  /// 是否有任意圆角。
  bool get hasRadius =>
      topLeftRadius > 0 ||
      topRightRadius > 0 ||
      bottomRightRadius > 0 ||
      bottomLeftRadius > 0 ||
      topLeftRadiusPercent != null ||
      topRightRadiusPercent != null ||
      bottomRightRadiusPercent != null ||
      bottomLeftRadiusPercent != null ||
      (topLeftRadiusY ?? 0) > 0 ||
      (topRightRadiusY ?? 0) > 0 ||
      (bottomRightRadiusY ?? 0) > 0 ||
      (bottomLeftRadiusY ?? 0) > 0 ||
      topLeftRadiusPercentY != null ||
      topRightRadiusPercentY != null ||
      bottomRightRadiusPercentY != null ||
      bottomLeftRadiusPercentY != null;

  /// 四边是否完全一致（同宽/同线型/同色），圆角绘制的前提。
  bool get isUniform =>
      top.isVisible &&
      top.width == right.width &&
      top.width == bottom.width &&
      top.width == left.width &&
      top.style == right.style &&
      top.style == bottom.style &&
      top.style == left.style &&
      top.color == right.color &&
      top.color == bottom.color &&
      top.color == left.color;

  @override
  String toString() =>
      'CssBorders($top,$right,$bottom,$left,'
      'radii=$topLeftRadius/$topRightRadius/$bottomRightRadius/$bottomLeftRadius,'
      'radiiY=$topLeftRadiusY/$topRightRadiusY/$bottomRightRadiusY/'
      '$bottomLeftRadiusY)';
}

/// 一次算完的不可变样式。
///
/// P1-21 最小字段集：字号、行高、颜色、字重、斜体、text-align、margin。
class ComputedStyle {
  /// 级联关键字使用初始值，避免解析失败后意外沿用父样式。
  static String initialValue(String property, [double rootFontSize = 16]) {
    if (property.startsWith('margin-') || property.startsWith('padding-')) {
      return '0px';
    }
    if (property.startsWith('border-')) {
      if (property.endsWith('-width')) return 'medium';
      if (property.endsWith('-color')) return 'currentcolor';
      if (property.endsWith('-style')) return 'none';
    }
    return switch (property) {
      'font-size' => '${rootFontSize}px',
      'color' => '#000000',
      'font-family' => 'serif',
      'font-size-adjust' ||
      'text-shadow' ||
      'list-style-image' ||
      'text-emphasis-style' ||
      'hanging-punctuation' ||
      'text-autospace' ||
      'text-transform' ||
      'text-combine-upright' => 'none',
      'text-indent' || 'word-spacing' => '0px',
      'text-align' => 'start',
      'text-align-last' || 'text-justify' || 'quotes' || 'line-break' => 'auto',
      'writing-mode' => 'horizontal-tb',
      'text-orientation' => 'mixed',
      'direction' => 'ltr',
      'hyphens' => 'manual',
      'list-style-type' => 'disc',
      'list-style-position' => 'outside',
      'visibility' => 'visible',
      'tab-size' => '8',
      'text-emphasis-color' => 'currentcolor',
      'text-emphasis-position' => 'over right',
      'ruby-align' => 'space-around',
      'ruby-position' => 'over',
      'border-collapse' => 'separate',
      'border-spacing' => '0px',
      'outline-width' => 'medium',
      'outline-style' => 'none',
      'outline-color' => 'currentcolor',
      'outline-offset' => '0px',
      _ => 'normal',
    };
  }

  /// 显式继承非继承属性时，长度必须传递计算值，不能重复解算 em。
  String? computedValue(String property) {
    final edge = RegExp(r'^(margin|padding)-(top|right|bottom|left)$')
        .firstMatch(property);
    if (edge != null) {
      final edges = edge[1] == 'margin' ? margin : padding;
      final value = switch (edge[2]) {
        'top' => edges.top,
        'right' => edges.right,
        'bottom' => edges.bottom,
        _ => edges.left,
      };
      return '${value}px';
    }
    final border = RegExp(
      r'^border-(top|right|bottom|left)-(width|style|color)$',
    ).firstMatch(property);
    if (border != null) {
      final side = switch (border[1]) {
        'top' => borders.top,
        'right' => borders.right,
        'bottom' => borders.bottom,
        _ => borders.left,
      };
      return switch (border[2]) {
        'width' => '${side.width}px',
        'style' => side.style.name,
        _ =>
          'rgba(${(side.color.r * 255).round()}, '
              '${(side.color.g * 255).round()}, ${(side.color.b * 255).round()}, '
              '${side.color.a})',
      };
    }
    if (property.startsWith('outline-')) {
      return switch (property) {
        'outline-width' => '${outline.width}px',
        'outline-style' => outline.style.name,
        'outline-offset' => '${outline.offset}px',
        _ =>
          'rgba(${(outline.color.r * 255).round()}, '
              '${(outline.color.g * 255).round()}, '
              '${(outline.color.b * 255).round()}, ${outline.color.a})',
      };
    }
    return values[property];
  }

  /// 复用类型解析器过滤已支持属性的无效值，保留较早的有效声明。
  static bool isValidDeclaration(String property, String raw) {
    final value = raw.trim().toLowerCase();
    if (property.startsWith('--') ||
        raw.contains('var(') ||
        const {'inherit', 'initial', 'unset'}.contains(value)) {
      return true;
    }
    if (property == 'border' ||
        const {
          'border-top',
          'border-right',
          'border-bottom',
          'border-left',
        }.contains(property)) {
      return parseBorderShorthand(raw) != null;
    }
    if (property == 'outline') {
      return parseOutlineShorthand(raw) != null;
    }
    if (property == 'margin' ||
        property == 'padding' ||
        const {
          'border-width',
          'border-style',
          'border-color',
        }.contains(property)) {
      final tokens = _cssTokens(raw);
      final longhand = property.startsWith('border-')
          ? 'border-top-${property.substring(7)}'
          : '$property-top';
      return tokens.isNotEmpty &&
          tokens.length <= 4 &&
          tokens.every((token) => isValidDeclaration(longhand, token));
    }
    if ((property.startsWith('border-') || property.startsWith('outline-')) &&
        property.endsWith('-style')) {
      return _parseBorderStyle(value) != null ||
          (property == 'outline-style' && value == 'auto');
    }
    if (property == 'color' || property.endsWith('-color')) {
      if (property == 'outline-color' && value == 'invert') {
        return true;
      }
      return value == 'currentcolor' || _parseColor(value) != null;
    }
    final lengthResult = _validLengthDeclaration(property, value);
    if (lengthResult != null) return lengthResult;
    return _validKeywordDeclaration(property, value);
  }

  static bool _validKeywordDeclaration(String property, String value) {
    return switch (property) {
      'font' => parseFontShorthand(value) != null,
      'font-weight' => _parseFontWeight(value) != null,
      'font-style' => const {'normal', 'italic', 'oblique'}.contains(value),
      'text-align' => _parseTextAlign(value) != null,
      'visibility' => _parseVisibility(value) != null,
      'white-space' => _parseWhiteSpace(value) != null,
      'position' => _parsePosition(value) != null,
      'float' => _parseFloat(value) != null,
      'direction' => _parseDirection(value) != null,
      'writing-mode' => _parseWritingMode(value) != null,
      'list-style-position' => _parseListStylePosition(value) != null,
      'opacity' => double.tryParse(value)?.isFinite ?? false,
      _ => true,
    };
  }

  static bool? _validLengthDeclaration(String property, String value) {
    final borderWidth =
        (property.startsWith('border-') || property.startsWith('outline-')) &&
        property.endsWith('-width');
    final margin = property.startsWith('margin-');
    final padding = property.startsWith('padding-');
    const lengths = {
      'font-size',
      'line-height',
      'letter-spacing',
      'word-spacing',
      'text-indent',
      'width',
      'height',
      'min-width',
      'min-height',
      'max-width',
      'max-height',
      'top',
      'right',
      'bottom',
      'left',
      'outline-offset',
    };
    if (!borderWidth && !margin && !padding && !lengths.contains(property)) {
      return null;
    }
    if (borderWidth && const {'thin', 'medium', 'thick'}.contains(value)) {
      return true;
    }
    if ((margin ||
            const {
              'width',
              'height',
              'min-width',
              'min-height',
              'top',
              'right',
              'bottom',
              'left',
            }.contains(property)) &&
        value == 'auto') {
      return true;
    }
    if (property.startsWith('max-') && value == 'none') return true;
    if (const {
          'line-height',
          'letter-spacing',
          'word-spacing',
        }.contains(property) &&
        value == 'normal') {
      return true;
    }
    if (property == 'font-size' &&
        const {
          'xx-small',
          'x-small',
          'small',
          'medium',
          'large',
          'x-large',
          'xx-large',
          'smaller',
          'larger',
        }.contains(value)) {
      return true;
    }
    final length = _resolveLength(
      value,
      fontSize: 16,
      parentFontSize: 16,
      rootFontSize: 16,
      percentBase: 100,
    );
    if (length == null || !length.isFinite) return false;
    final nonnegative =
        padding ||
        borderWidth ||
        const {
          'font-size',
          'line-height',
          'width',
          'height',
          'min-width',
          'min-height',
          'max-width',
          'max-height',
        }.contains(property);
    // calc() 的百分比基准直到布局时才确定，此处不能用探测宽度判负值。
    return !nonnegative || value.startsWith('calc(') || length >= 0;
  }

  /// 边框简写统一拆成长属性，缺项也要重置为初始值。
  static Map<String, String>? parseBorderShorthand(String raw) {
    final result = <String, String>{};
    for (final token in _cssTokens(raw)) {
      final lower = token.toLowerCase();
      final String key;
      if (_parseBorderStyle(lower) != null) {
        key = 'style';
      } else if (lower == 'currentcolor' || _parseColor(token) != null) {
        key = 'color';
      } else if (_validLengthDeclaration('border-top-width', lower) == true &&
          !lower.contains('%')) {
        key = 'width';
      } else {
        return null;
      }
      if (result.containsKey(key)) return null;
      result[key] = token;
    }
    return result.isEmpty ? null : result;
  }

  /// `outline` 简写统一拆成长属性，缺项由调用方补初始值。
  static Map<String, String>? parseOutlineShorthand(String raw) {
    final result = <String, String>{};
    for (final token in _cssTokens(raw)) {
      final lower = token.toLowerCase();
      final String key;
      if (_parseBorderStyle(lower) != null || lower == 'auto') {
        key = 'style';
      } else if (lower == 'currentcolor' ||
          lower == 'invert' ||
          _parseColor(token) != null) {
        key = 'color';
      } else if (_validLengthDeclaration('outline-width', lower) == true &&
          !lower.contains('%')) {
        key = 'width';
      } else {
        return null;
      }
      if (result.containsKey(key)) return null;
      result[key] = token;
    }
    return result.isEmpty ? null : result;
  }

  static List<String> _cssTokens(String raw) {
    final tokens = <String>[];
    var start = 0;
    var depth = 0;
    for (var i = 0; i < raw.length; i++) {
      if (raw[i] == '(') depth++;
      if (raw[i] == ')') depth--;
      if (depth == 0 && RegExp(r'\s').hasMatch(raw[i])) {
        if (i > start) tokens.add(raw.substring(start, i));
        start = i + 1;
      }
    }
    if (start < raw.length) tokens.add(raw.substring(start));
    return tokens;
  }

  /// 从层叠后的字符串值计算类型化字段。
  ///
  /// [explicitProperties] 为元素自身层叠出的属性；未提供的属性从 [parent]
  /// 继承或取初始值。为 null 时把 [values] 全部视为显式值（直接构造场景）。
  factory ComputedStyle(
    Map<String, String> values, {
    bool hasExplicitTextColor = false,
    ComputedStyle? parent,
    Set<String>? explicitProperties,
    Map<String, String> customProperties = const <String, String>{},
    double rootFontSize = 16,
    double containingWidth = 0,
  }) {
    final explicit = explicitProperties ?? values.keys.toSet();
    String? explicitValue(String property) =>
        explicit.contains(property) ? values[property] : null;

    // `font` 简写（P9-09）：长属性缺失时从简写展开，否则整条简写会被
    // 静默丢弃（书籍常用 `font: italic bold 16px/1.5 serif`）。
    final shorthandFont = explicit.contains('font')
        ? parseFontShorthand(values['font'])
        : null;
    String? fontValue(String property) => explicit.contains(property)
        ? values[property]
        : shorthandFont?[property];

    final parentFontSize = parent?.fontSize ?? rootFontSize;
    var fontSize = parent?.fontSize ?? rootFontSize;
    final rawFontSize = fontValue('font-size');
    if (rawFontSize != null) {
      fontSize =
          _resolveLength(
            rawFontSize,
            fontSize: parentFontSize,
            parentFontSize: parentFontSize,
            rootFontSize: rootFontSize,
            percentBase: parentFontSize,
          ) ??
          fontSize;
    }

    // 行高（CSS 2.1 §10.8）：未声明时是 `normal`——没有固定倍数，由字体度量
    // 决定。Flutter 在 `TextStyle(height: null)` 时用字体默认行高，与 Chrome
    // 的 normal 一致，所以这里 `lineHeightFactor` 保持 null 表示 normal；
    // [lineHeight] 只给近似像素值供几何兜底（表格单元格高度估算等）。
    //
    // 继承规则：无单位因子按子元素字号重算；px/百分比按父级算好的绝对值继承；
    // 父级是 normal 时子级继续 normal（不会把近似的像素值继承下来）。
    final parentNormal = parent == null || parent.lineHeightFactor == null;
    var lineHeight = fontSize * _normalLineHeightFactor;
    double? lineHeightFactor;
    double? unitlessLineHeightFactor;
    var hasDeclaredLineHeight = false;

    void applyDeclaredLineHeight(String raw) {
      // 显式 `normal` 是**有效声明**：重置为 normal（不再继承父级绝对值）。
      if (raw.trim().toLowerCase() == 'normal') {
        hasDeclaredLineHeight = true;
        return;
      }
      final unitless = double.tryParse(raw.trim());
      if (unitless != null) {
        lineHeight = fontSize * unitless;
        lineHeightFactor = unitless;
        unitlessLineHeightFactor = unitless;
        hasDeclaredLineHeight = true;
        return;
      }
      final percent = _parsePercent(raw);
      if (percent != null) {
        lineHeight = fontSize * percent / 100;
        lineHeightFactor = fontSize == 0 ? null : percent / 100;
        hasDeclaredLineHeight = true;
        return;
      }
      final resolved = _resolveLength(
        raw,
        fontSize: fontSize,
        parentFontSize: parentFontSize,
        rootFontSize: rootFontSize,
        percentBase: fontSize,
      );
      if (resolved != null) {
        lineHeight = resolved;
        lineHeightFactor = fontSize == 0 ? null : resolved / fontSize;
        hasDeclaredLineHeight = true;
      }
      // 解析不出（含显式 `normal`）→ 保持 normal。
    }

    final rawLineHeight = fontValue('line-height');
    if (rawLineHeight != null) {
      applyDeclaredLineHeight(rawLineHeight);
    }
    if (!hasDeclaredLineHeight && !parentNormal) {
      final inheritedUnitless = parent.unitlessLineHeightFactor;
      if (inheritedUnitless != null) {
        lineHeight = fontSize * inheritedUnitless;
        lineHeightFactor = inheritedUnitless;
        unitlessLineHeightFactor = inheritedUnitless;
      } else {
        lineHeight = parent.lineHeight;
        lineHeightFactor = fontSize == 0 ? null : lineHeight / fontSize;
      }
    }
    // 注意：normal 时 lineHeightFactor 必须保持 null（TextStyle(height: null)
    // 交给字体度量），不能再用 lineHeight/fontSize 反推因子。

    final rawColor = explicitValue('color');
    final color = rawColor == null
        ? (parent?.color ?? const Color(0xFF000000))
        : (_parseColor(rawColor) ?? parent?.color ?? const Color(0xFF000000));

    // 多列布局（W11，不继承）：column-count/width/gap/rule + `columns` 简写。
    final columns = _resolveColumns(
      values,
      explicit,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
      color: color,
    );

    final parentWeight = parent?.fontWeight ?? 400;
    final rawWeight = fontValue('font-weight');
    final weight = rawWeight == null
        ? parentWeight
        : _parseFontWeight(rawWeight, parentWeight: parentWeight) ??
              parentWeight;

    final rawStyle = fontValue('font-style');
    final italic = rawStyle == null
        ? (parent?.italic ?? false)
        : _isItalic(rawStyle);

    final rawFamily = fontValue('font-family');
    final fontFamilies = rawFamily == null
        ? (parent?.fontFamilies ?? const <String>[])
        : _parseFontFamilies(rawFamily);

    final rawAlign = explicitValue('text-align');
    final textAlign = rawAlign == null
        ? (parent?.textAlign ?? CssTextAlign.start)
        : _parseTextAlign(rawAlign) ?? parent?.textAlign ?? CssTextAlign.start;
    final rawJustify = explicitValue('text-justify');
    final textJustify = rawJustify == null
        ? (parent?.textJustify ?? CssTextJustify.auto)
        : _parseTextJustify(rawJustify) ??
              parent?.textJustify ??
              CssTextJustify.auto;
    // text-align-last：auto → null（末行按 start 对齐，现状）。
    final rawAlignLast = explicitValue('text-align-last');
    final textAlignLast = rawAlignLast == null
        ? (parent?.textAlignLast)
        : _parseTextAlign(rawAlignLast) ?? parent?.textAlignLast;
    final rawInitialLetter = explicitValue('initial-letter');
    final initialLetterLines = rawInitialLetter == null
        ? parent?.initialLetterLines
        : _parseInitialLetter(rawInitialLetter) ?? parent?.initialLetterLines;
    // P2-37 抽样属性（均不继承）：opacity 初始 1；text-overflow 初始
    // clip；box-shadow 初始无。
    final rawOpacity = explicitValue('opacity');
    final opacity = rawOpacity == null
        ? 1.0
        : (double.tryParse(rawOpacity.trim()) ?? 1.0).clamp(0.0, 1.0);
    // opacity 不继承，但父级半透明整体作用于子树：沿级联父链做乘积，
    // 章节源/绘制层读 [effectiveOpacity] 才能与浏览器合成结果一致。
    final effectiveOpacity = (parent?.effectiveOpacity ?? 1.0) * opacity;
    final rawTextOverflow = explicitValue('text-overflow');
    final textOverflow = rawTextOverflow == null
        ? CssTextOverflow.clip
        : _parseTextOverflow(rawTextOverflow);
    final boxShadow = _parseBoxShadow(
      explicitValue('box-shadow'),
      fontSize: fontSize,
    );
    // filter（W5）：有序滤镜列表，非继承，初始空；多看的 `-webkit-filter`
    // 也接住（真实书大量使用）。
    final backdropFilters = _parseFilters(
      explicitValue('backdrop-filter') ??
          explicitValue('-webkit-backdrop-filter'),
      fontSize: fontSize,
      rootFontSize: rootFontSize,
    );
    final filters = _parseFilters(
      explicitValue('filter') ?? explicitValue('-webkit-filter'),
      fontSize: fontSize,
      rootFontSize: rootFontSize,
    );

    // transform 族（W11）：有序变换列表 + 原点。百分比一律保留标记，
    // 绘制层按边框盒宽/高解算（不在这里换算成 px）。
    final transforms = _parseTransforms(
      explicitValue('transform') ?? explicitValue('-webkit-transform'),
      fontSize: fontSize,
    );
    final transformOrigin = _parseTransformOrigin(
      explicitValue('transform-origin'),
      fontSize: fontSize,
    );

    // 书写模式族（W11）：writing-mode/text-orientation/direction 都继承。
    final rawWritingMode = explicitValue('writing-mode');
    final writingMode = rawWritingMode == null
        ? (parent?.writingMode ?? CssWritingMode.horizontalTb)
        : _parseWritingMode(rawWritingMode) ??
              parent?.writingMode ??
              CssWritingMode.horizontalTb;
    final rawTextOrientation = explicitValue('text-orientation');
    final textOrientation = rawTextOrientation == null
        ? (parent?.textOrientation ?? CssTextOrientation.mixed)
        : _parseTextOrientation(rawTextOrientation) ??
              parent?.textOrientation ??
              CssTextOrientation.mixed;
    final rawDirection = explicitValue('direction');
    final direction = rawDirection == null
        ? (parent?.direction ?? CssDirection.ltr)
        : _parseDirection(rawDirection) ??
              parent?.direction ??
              CssDirection.ltr;

    // 断行族（W11，都继承）：hyphens / word-break / overflow-wrap。
    final rawHyphens = explicitValue('hyphens');
    final hyphens = rawHyphens == null
        ? (parent?.hyphens ?? CssHyphens.manual)
        : _parseHyphens(rawHyphens) ?? parent?.hyphens ?? CssHyphens.manual;
    final rawWordBreak = explicitValue('word-break');
    final wordBreak = rawWordBreak == null
        ? (parent?.wordBreak ?? CssWordBreak.normal)
        : _parseWordBreak(rawWordBreak) ??
              parent?.wordBreak ??
              CssWordBreak.normal;
    // 旧名 `word-wrap` 与 `overflow-wrap` 同义（别名表里没登记，这里兜底）。
    final rawOverflowWrap =
        explicitValue('overflow-wrap') ?? explicitValue('word-wrap');
    final overflowWrap = rawOverflowWrap == null
        ? (parent?.overflowWrap ?? CssOverflowWrap.normal)
        : _parseOverflowWrap(rawOverflowWrap) ??
              parent?.overflowWrap ??
              CssOverflowWrap.normal;
    final lineBreak =
        _parseLineBreak(explicitValue('line-break')) ??
        parent?.lineBreak ??
        CssLineBreak.auto;
    final tabSize =
        _parseTabSize(explicitValue('tab-size')) ?? parent?.tabSize ?? 8;
    final mixBlendMode =
        _parseMixBlendMode(explicitValue('mix-blend-mode')) ??
        parent?.mixBlendMode ??
        CssMixBlendMode.normal;

    // font-variant 族（W18，继承）：caps 从长属性或简写取；`font` 简写里的
    // small-caps token 已在 parseFontShorthand 里落成 font-variant-caps。
    final rawVariantCaps =
        explicitValue('font-variant-caps') ?? explicitValue('font-variant');
    final fontVariantCaps = rawVariantCaps == null
        ? (parent?.fontVariantCaps ?? CssFontVariantCaps.normal)
        : _parseFontVariantCaps(rawVariantCaps) ??
              parent?.fontVariantCaps ??
              CssFontVariantCaps.normal;
    final rawLigatures = explicitValue('font-variant-ligatures');
    final fontVariantLigatures = rawLigatures == null
        ? (parent?.fontVariantLigatures ?? CssFontVariantLigatures.normal)
        : _parseFontVariantLigatures(rawLigatures) ??
              parent?.fontVariantLigatures ??
              CssFontVariantLigatures.normal;

    // font-stretch（继承，初始 100%）：关键字/百分比统一折成百分比数值。
    final rawFontStretch = explicitValue('font-stretch');
    final fontStretch = rawFontStretch == null
        ? (parent?.fontStretch ?? 100.0)
        : _parseFontStretch(rawFontStretch) ?? parent?.fontStretch ?? 100.0;
    // font-size-adjust（继承，初始 none）：none 必须显式重置为 null。
    var fontSizeAdjust = parent?.fontSizeAdjust;
    final rawSizeAdjust = explicitValue('font-size-adjust');
    if (rawSizeAdjust != null) {
      final token = rawSizeAdjust.trim().toLowerCase();
      fontSizeAdjust = token == 'none'
          ? null
          : double.tryParse(token) ?? fontSizeAdjust;
    }

    // quotes（W18，继承，初始 auto）：显式引号对 / none / auto 三态。
    final rawQuotes = explicitValue('quotes');
    final quotes = rawQuotes == null
        ? (parent?.quotes ?? const CssQuotesAuto())
        : _parseQuotes(rawQuotes) ?? parent?.quotes ?? const CssQuotesAuto();

    // 逻辑属性（margin/padding/border/inset 的 inline|block × start|end）
    // 按书写模式与方向落成物理属性后再解算盒模型；物理显式声明优先，
    // 逻辑声明只在对应物理名未声明时补位（与浏览器「同一属性空间的先后者胜」
    // 近似——声明顺序在层叠后已丢，这里取物理优先的保守口径）。
    final logicalPhysical = CssPropertyAliases.logicalPhysicalMap(
      writingMode: writingMode.name,
      direction: direction.name,
    );
    final edgeValues = <String, String>{...values};
    final edgeExplicit = <String>{...explicit};
    logicalPhysical.forEach((logical, physical) {
      if (edgeExplicit.contains(logical) && !edgeExplicit.contains(physical)) {
        edgeValues[physical] = edgeValues[logical]!;
        edgeExplicit.add(physical);
      }
    });

    // overflow（W11，不继承，初始 visible）：绘制层据此决定是否裁剪外溢内容。
    // `overflow` 简写优先；长属性任一轴非 visible 都需要裁剪。另一轴为
    // visible 时浏览器会把两轴都按可裁剪处理，因此无需保留双轴枚举。
    final rawOverflowX = explicitValue('overflow-x');
    final rawOverflowY = explicitValue('overflow-y');
    final rawOverflow =
        explicitValue('overflow') ??
        (rawOverflowX != null &&
                _parseOverflow(rawOverflowX) != CssOverflow.visible
            ? rawOverflowX
            : rawOverflowY ?? rawOverflowX);
    final overflow = rawOverflow == null
        ? CssOverflow.visible
        : _parseOverflow(rawOverflow);

    var textIndent = parent?.textIndent ?? 0.0;
    final rawTextIndent = explicitValue('text-indent');
    if (rawTextIndent != null) {
      textIndent =
          _resolveLength(
            rawTextIndent,
            fontSize: fontSize,
            parentFontSize: parentFontSize,
            rootFontSize: rootFontSize,
            percentBase: containingWidth,
          ) ??
          textIndent;
    }

    var letterSpacing = parent?.letterSpacing ?? 0.0;
    final rawLetterSpacing = explicitValue('letter-spacing');
    if (rawLetterSpacing != null) {
      if (rawLetterSpacing.trim().toLowerCase() == 'normal') {
        letterSpacing = 0;
      } else {
        letterSpacing =
            _resolveLength(
              rawLetterSpacing,
              fontSize: fontSize,
              parentFontSize: parentFontSize,
              rootFontSize: rootFontSize,
              percentBase: fontSize,
            ) ??
            letterSpacing;
      }
    }

    final margin = _resolveMargin(
      edgeValues,
      edgeExplicit,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
      containingWidth: containingWidth,
    );

    // position/float/display 不继承，按 CSS 初始值兜底（§60.2 分派用）。
    final position =
        _parsePosition(explicitValue('position')) ?? CssPosition.static;
    final cssFloat = _parseFloat(explicitValue('float')) ?? CssFloat.none;
    final display = _parseDisplay(explicitValue('display')) ?? CssDisplay.block;

    // visibility 与 white-space 是可继承属性（P2-15）。
    final rawVisibility = explicitValue('visibility');
    final visibility = rawVisibility == null
        ? (parent?.visibility ?? CssVisibility.visible)
        : _parseVisibility(rawVisibility) ??
              parent?.visibility ??
              CssVisibility.visible;
    final rawWhiteSpace = explicitValue('white-space');
    final whiteSpace = rawWhiteSpace == null
        ? (parent?.whiteSpace ?? CssWhiteSpace.normal)
        : _parseWhiteSpace(rawWhiteSpace) ??
              parent?.whiteSpace ??
              CssWhiteSpace.normal;
    final rawHanging = explicitValue('hanging-punctuation');
    final hangingPunctuation = rawHanging == null
        ? (parent?.hangingPunctuation ?? CssHangingPunctuation.none)
        : _parseHangingPunctuation(rawHanging) ??
              parent?.hangingPunctuation ??
              CssHangingPunctuation.none;
    // 未声明时取 trimAdjacent：Chrome 初始值 `normal` 即折叠相邻全角标点
    // （CSS Text 4），旧版把默认当关闭会让同一行宽下比浏览器宽出一个标点。
    final rawTrim = explicitValue('text-spacing-trim');
    final textSpacingTrim = rawTrim == null
        ? (parent?.textSpacingTrim ?? CssTextSpacingTrim.trimAdjacent)
        : _parseTextSpacingTrim(rawTrim) ??
              parent?.textSpacingTrim ??
              CssTextSpacingTrim.trimAdjacent;
    final rawAutospace = explicitValue('text-autospace');
    final textAutospace = rawAutospace == null
        ? (parent?.textAutospace ?? CssTextAutospace.none)
        : _parseTextAutospace(rawAutospace) ??
              parent?.textAutospace ??
              CssTextAutospace.none;

    // 字符级属性：word-spacing/text-transform 继承，vertical-align 不继承（P2-16）。
    final rawWordSpacing = explicitValue('word-spacing');
    final wordSpacing = rawWordSpacing == null
        ? (parent?.wordSpacing ?? 0.0)
        : _resolveLength(
                rawWordSpacing,
                fontSize: fontSize,
                parentFontSize: fontSize,
                rootFontSize: rootFontSize,
                percentBase: 0,
              ) ??
              parent?.wordSpacing ??
              0.0;
    final rawTransform = explicitValue('text-transform');
    final textTransform = rawTransform == null
        ? (parent?.textTransform ?? CssTextTransform.none)
        : _parseTextTransform(rawTransform) ??
              parent?.textTransform ??
              CssTextTransform.none;
    final rawVerticalAlign = explicitValue('vertical-align');
    final normalizedVerticalAlign = rawVerticalAlign == null
        ? null
        : CssPropertyAliases.normalizeValue(rawVerticalAlign);
    final verticalAlign =
        _parseVerticalAlign(normalizedVerticalAlign) ??
        CssVerticalAlign.baseline;
    // `vertical-align: <length> | <percentage>`（W2）：关键字取值时为 null；
    // 百分比按**本元素行高**解算（Chrome 实测 17px/1.6 → 行高 27.2，10% = 2.72px）。
    // 字段保留 CSS 符号（正=向上），`verticalAlignShift` 再翻成「正值向下」。
    final verticalAlignLength = _parseVerticalAlignLength(
      normalizedVerticalAlign,
      lineHeight: lineHeight,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
    );

    // 装饰与分页属性（P2-17）：text-decoration 不继承，text-emphasis 继承。
    final rawDecoration =
        explicitValue('text-decoration-line') ??
        explicitValue('text-decoration');
    final textDecoration =
        _parseTextDecoration(rawDecoration) ?? CssTextDecoration.none;
    // 装饰线颜色/线型（P9-18）：简写里也能带（underline dotted #f00）。
    final textDecorationStyle =
        _parseTextDecorationStyle(explicitValue('text-decoration-style')) ??
        _decorationStyleFromShorthand(rawDecoration) ??
        CssTextDecorationStyle.solid;
    final textDecorationColor =
        _parseColor(explicitValue('text-decoration-color') ?? '') ??
        _decorationColorFromShorthand(rawDecoration);
    final rawEmphasis =
        explicitValue('text-emphasis-style') ?? explicitValue('text-emphasis');
    final textEmphasisStyle = rawEmphasis == null
        ? (parent?.textEmphasisStyle ?? CssTextEmphasisStyle.none)
        : _parseTextEmphasisStyle(rawEmphasis) ??
              parent?.textEmphasisStyle ??
              CssTextEmphasisStyle.none;
    final rawEmphasisPosition = explicitValue('text-emphasis-position');
    final textEmphasisPosition = rawEmphasisPosition == null
        ? (parent?.textEmphasisPosition ?? CssTextEmphasisPosition.over)
        : _parseTextEmphasisPosition(rawEmphasisPosition) ??
              parent?.textEmphasisPosition ??
              CssTextEmphasisPosition.over;
    final rawRubyPosition = explicitValue('ruby-position');
    final rubyPosition = rawRubyPosition == null
        ? (parent?.rubyPosition ?? CssRubyPosition.over)
        : _parseRubyPosition(rawRubyPosition) ??
              parent?.rubyPosition ??
              CssRubyPosition.over;
    final rawRubyAlign = explicitValue('ruby-align');
    final rubyAlign = rawRubyAlign == null
        ? (parent?.rubyAlign ?? CssRubyAlign.center)
        : _parseRubyAlign(rawRubyAlign) ??
              parent?.rubyAlign ??
              CssRubyAlign.center;
    final rawTextCombine = explicitValue('text-combine-upright');
    final textCombine = rawTextCombine == null
        ? (parent?.textCombine ?? CssTextCombine.none)
        : _parseTextCombine(rawTextCombine) ??
              parent?.textCombine ??
              CssTextCombine.none;
    final rawEmphasisColor = explicitValue('text-emphasis-color');
    final textEmphasisColor = rawEmphasisColor == null
        ? parent?.textEmphasisColor
        : rawEmphasisColor.toLowerCase() == 'currentcolor'
        ? color
        : _parseColor(rawEmphasisColor) ?? parent?.textEmphasisColor;
    final pageBreakBefore = _parsePageBreak(
      explicitValue('page-break-before') ?? explicitValue('break-before'),
    );
    final pageBreakAfter = _parsePageBreak(
      explicitValue('page-break-after') ?? explicitValue('break-after'),
    );
    final rawBreakInside =
        explicitValue('break-inside') ?? explicitValue('page-break-inside');
    final breakInsideAvoid = rawBreakInside?.trim().toLowerCase() == 'avoid';

    // avoid 档位（P3-22，Reeden 510 §3.3：avoid before（标题不落页底））。
    final breakAfterAvoidRaw =
        explicitValue('break-after') ?? explicitValue('page-break-after');
    final breakAfterAvoid = breakAfterAvoidRaw?.trim().toLowerCase() == 'avoid';

    // P0 收口补全（P2-18）：text-shadow、背景子属性、定位偏移、clear、表格边框。
    final rawShadow = explicitValue('text-shadow');
    final textShadow = rawShadow == null
        ? (parent?.textShadow ?? const <CssTextShadow>[])
        : _parseTextShadows(rawShadow, fontSize: fontSize) ??
              parent?.textShadow ??
              const <CssTextShadow>[];
    // `background` 简写（P9-11）：repeat/position/size/color/image 全部
    // 从简写回落，长属性优先；否则 `background: #fff url(x) no-repeat
    // center/cover` 只会取到图与底色。
    final backgroundShorthand = explicit.contains('background')
        ? _parseBackgroundShorthand(values['background'])
        : null;
    String? backgroundValue(String property) => explicit.contains(property)
        ? values[property]
        : backgroundShorthand?[property];
    final backgroundRepeat =
        _parseBackgroundRepeat(backgroundValue('background-repeat')) ??
        CssBackgroundRepeat.repeat;
    final backgroundSize =
        _parseBackgroundSize(
          backgroundValue('background-size'),
          fontSize: fontSize,
          rootFontSize: rootFontSize,
        ) ??
        const CssBackgroundSize.keyword(CssBackgroundSizeMode.auto);
    final backgroundPosition =
        _parseBackgroundPosition(
          backgroundValue('background-position'),
          fontSize: fontSize,
          rootFontSize: rootFontSize,
        ) ??
        const CssBackgroundPosition(
          x: CssLength(0, isPercent: true),
          y: CssLength(0, isPercent: true),
        );
    final backgroundOrigin =
        _parseBackgroundOrigin(explicitValue('background-origin')) ??
        CssBackgroundOrigin.paddingBox;
    final backgroundClip =
        _parseBackgroundClip(explicitValue('background-clip')) ??
        CssBackgroundClip.borderBox;
    final clear = _parseClear(explicitValue('clear')) ?? CssClear.none;
    final rawCollapse = explicitValue('border-collapse');
    final borderCollapse = rawCollapse == null
        ? (parent?.borderCollapse ?? CssBorderCollapse.separate)
        : _parseBorderCollapse(rawCollapse) ??
              parent?.borderCollapse ??
              CssBorderCollapse.separate;
    // 多看出血（P9-22）：`duokan-bleed: left` 允许元素延伸到页面边距。
    // 出血常写在容器上（`div.x { duokan-bleed: lefttopright }`），
    // 由 flat 管线的盒属性传导注入，因此从 values 读而不是只读显式值。
    final rawBleed = values['duokan-bleed'] ?? values['-duokan-bleed'];
    final bleed = _parseBleed(rawBleed);
    // list-style-type（P9-12）：简写在层叠层已展开成长属性，这里只读
    // 长属性，继承与特异性才和 CSS 一致。
    final rawListStyle = explicitValue('list-style-type');
    final listStyleType = rawListStyle == null
        ? (parent?.listStyleType ?? CssListStyleType.disc)
        : _parseListStyleType(rawListStyle) ??
              parent?.listStyleType ??
              CssListStyleType.disc;
    // list-style-position 继承，初始 outside；`list-style` 简写里的
    // inside/outside 由层叠层展开成长属性（与 list-style-type 同一条路径）。
    final listStylePosition =
        _parseListStylePosition(explicitValue('list-style-position')) ??
        parent?.listStylePosition ??
        CssListStylePosition.outside;
    final tableLayout =
        _parseTableLayout(explicitValue('table-layout')) ?? CssTableLayout.auto;
    final rawSpacing = explicitValue('border-spacing');
    final borderSpacing = rawSpacing == null
        ? (parent?.borderSpacing ?? CssEdges.zero)
        : _parseBorderSpacing(
                rawSpacing,
                fontSize: fontSize,
                rootFontSize: rootFontSize,
              ) ??
              parent?.borderSpacing ??
              CssEdges.zero;
    String? edgeValue(String property) =>
        edgeExplicit.contains(property) ? edgeValues[property] : null;
    final top =
        _parseOffset(
          edgeValue('top'),
          fontSize: fontSize,
          rootFontSize: rootFontSize,
        ) ??
        parent?.top;
    final right =
        _parseOffset(
          edgeValue('right'),
          fontSize: fontSize,
          rootFontSize: rootFontSize,
        ) ??
        parent?.right;
    final bottom =
        _parseOffset(
          edgeValue('bottom'),
          fontSize: fontSize,
          rootFontSize: rootFontSize,
        ) ??
        parent?.bottom;
    final left =
        _parseOffset(
          edgeValue('left'),
          fontSize: fontSize,
          rootFontSize: rootFontSize,
        ) ??
        parent?.left;

    // background 与 border 不继承，按 CSS 初始值兜底（§65 背景与边框组）。
    final backgroundColor =
        _parseColor(backgroundValue('background-color') ?? '') ??
        const Color(0x00000000);
    final backgroundImageValue = backgroundValue('background-image');
    final backgroundImage = _parseUrl(backgroundImageValue);
    // 渐变结构（W2）：url 与渐变互斥——同一 background-image 只会命中一个。
    final backgroundGradient = _parseGradient(
      backgroundImageValue,
      fontSize: fontSize,
    );
    final borders = _resolveBorders(
      edgeValues,
      edgeExplicit,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
      color: color,
    );
    final outline = _resolveOutline(
      values,
      explicit,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
      color: color,
    );

    // 尺寸、内边距与 box-sizing 均不继承，未声明时按初始值兜底（P2-14 盒模型）。
    CssLength? dimension(String property) {
      final raw = explicitValue(property);
      return raw == null
          ? null
          : _resolveCssLength(
              raw,
              fontSize: fontSize,
              rootFontSize: rootFontSize,
              percentBase: containingWidth,
            );
    }

    final width = dimension('width');
    final height = dimension('height');
    final minWidth = dimension('min-width');
    final maxWidth = dimension('max-width');
    final minHeight = dimension('min-height');
    final maxHeight = dimension('max-height');
    final padding = _resolvePadding(
      edgeValues,
      edgeExplicit,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
      containingWidth: containingWidth,
    );
    final boxSizing = _parseBoxSizing(explicitValue('box-sizing'));

    return ComputedStyle._(
      values: values,
      hasExplicitTextColor: hasExplicitTextColor,
      fontSize: fontSize,
      parentFontSize: parentFontSize,
      lineHeight: lineHeight,
      lineHeightFactor: lineHeightFactor,
      unitlessLineHeightFactor: unitlessLineHeightFactor,
      color: color,
      fontWeight: weight,
      italic: italic,
      fontFamilies: fontFamilies,
      textAlign: textAlign,
      textIndent: textIndent,
      letterSpacing: letterSpacing,
      margin: margin,
      position: position,
      cssFloat: cssFloat,
      display: display,
      visibility: visibility,
      whiteSpace: whiteSpace,
      hangingPunctuation: hangingPunctuation,
      textSpacingTrim: textSpacingTrim,
      textAutospace: textAutospace,
      textJustify: textJustify,
      textAlignLast: textAlignLast,
      initialLetterLines: initialLetterLines,
      opacity: opacity,
      effectiveOpacity: effectiveOpacity,
      filters: filters,
      backdropFilters: backdropFilters,
      transforms: transforms,
      transformOriginX: transformOrigin.x,
      transformOriginY: transformOrigin.y,
      writingMode: writingMode,
      textOrientation: textOrientation,
      direction: direction,
      hyphens: hyphens,
      wordBreak: wordBreak,
      overflowWrap: overflowWrap,
      lineBreak: lineBreak,
      tabSize: tabSize,
      mixBlendMode: mixBlendMode,
      fontVariantCaps: fontVariantCaps,
      fontVariantLigatures: fontVariantLigatures,
      quotes: quotes,
      fontStretch: fontStretch,
      fontSizeAdjust: fontSizeAdjust,
      overflow: overflow,
      columnCount: columns.count,
      columnWidth: columns.width,
      columnGap: columns.gap,
      columnRule: columns.rule,
      textOverflow: textOverflow,
      boxShadow: boxShadow,
      wordSpacing: wordSpacing,
      textTransform: textTransform,
      verticalAlign: verticalAlign,
      verticalAlignLength: verticalAlignLength,
      textDecoration: textDecoration,
      textEmphasisStyle: textEmphasisStyle,
      textEmphasisPosition: textEmphasisPosition,
      rubyPosition: rubyPosition,
      rubyAlign: rubyAlign,
      textCombine: textCombine,
      textEmphasisColor: textEmphasisColor,
      pageBreakBefore: pageBreakBefore,
      pageBreakAfter: pageBreakAfter,
      breakInsideAvoid: breakInsideAvoid,
      breakAfterAvoid: breakAfterAvoid,
      textShadow: textShadow,
      backgroundRepeat: backgroundRepeat,
      backgroundSize: backgroundSize,
      backgroundPosition: backgroundPosition,
      backgroundOrigin: backgroundOrigin,
      backgroundClip: backgroundClip,
      clear: clear,
      borderCollapse: borderCollapse,
      borderSpacing: borderSpacing,
      listStyleType: listStyleType,
      listStylePosition: listStylePosition,
      tableLayout: tableLayout,
      textDecorationStyle: textDecorationStyle,
      textDecorationColor: textDecorationColor,
      bleed: bleed,
      customProperties: customProperties,
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      backgroundColor: backgroundColor,
      backgroundImage: backgroundImage,
      backgroundGradient: backgroundGradient,
      borders: borders,
      outline: outline,
      borderImage: _parseBorderImage(
        explicitValue('border-image') ?? explicitValue('border-image-source'),
      ),
      width: width,
      height: height,
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
      padding: padding,
      boxSizing: boxSizing,
      explicitProperties: explicit,
    );
  }

  /// 只覆盖排版属性（字号/行高/文本对齐），其余属性原样保留。
  ///
  /// 阅读器设置必须走这里。用 `ComputedStyle(declarations, parent: base)`
  /// 重建会把非继承属性（背景色/背景图/边框/内边距/外边距）按初始值归零，
  /// 书籍里的卡片、面板与外框会整块消失（P9-01 修复）。
  ComputedStyle withTypography({
    double? fontSize,
    double? lineHeightFactor,
    CssTextAlign? textAlign,
  }) {
    if (fontSize == null && lineHeightFactor == null && textAlign == null) {
      return this;
    }
    final nextFontSize = fontSize ?? this.fontSize;
    final nextUnitless = lineHeightFactor ?? unitlessLineHeightFactor;
    final nextLineHeightFactor = lineHeightFactor ?? this.lineHeightFactor;
    // 阅读器覆盖（lineHeightFactor 非空）→ 显式倍数；书籍自身的无单位因子
    // 按新字号重算；两者都没有（CSS normal）→ 只更新像素兜底，因子仍为 null，
    // 真实行高继续交给字体度量。
    final nextLineHeight = lineHeightFactor != null
        ? nextFontSize * lineHeightFactor
        : (nextUnitless != null
              ? nextFontSize * nextUnitless
              : (this.lineHeightFactor == null
                    ? nextFontSize * _normalLineHeightFactor
                    : lineHeight));
    final nextValues = <String, String>{
      ...values,
      if (fontSize != null) 'font-size': '${nextFontSize}px',
      if (lineHeightFactor != null) 'line-height': '$lineHeightFactor',
      if (textAlign != null) 'text-align': _textAlignToCss(textAlign),
    };
    final nextExplicit = <String>{
      ...explicitProperties,
      if (fontSize != null) 'font-size',
      if (lineHeightFactor != null) 'line-height',
      if (textAlign != null) 'text-align',
    };
    return ComputedStyle._(
      values: nextValues,
      hasExplicitTextColor: hasExplicitTextColor,
      fontSize: nextFontSize,
      parentFontSize: parentFontSize,
      lineHeight: nextLineHeight,
      lineHeightFactor: nextLineHeightFactor,
      unitlessLineHeightFactor: nextUnitless,
      color: color,
      fontWeight: fontWeight,
      italic: italic,
      fontFamilies: fontFamilies,
      textAlign: textAlign ?? this.textAlign,
      textIndent: textIndent,
      letterSpacing: letterSpacing,
      margin: margin,
      position: position,
      cssFloat: cssFloat,
      display: display,
      visibility: visibility,
      whiteSpace: whiteSpace,
      hangingPunctuation: hangingPunctuation,
      textSpacingTrim: textSpacingTrim,
      textAutospace: textAutospace,
      textJustify: textJustify,
      textAlignLast: textAlignLast,
      initialLetterLines: initialLetterLines,
      opacity: opacity,
      effectiveOpacity: effectiveOpacity,
      filters: filters,
      backdropFilters: backdropFilters,
      transforms: transforms,
      transformOriginX: transformOriginX,
      transformOriginY: transformOriginY,
      writingMode: writingMode,
      textOrientation: textOrientation,
      direction: direction,
      hyphens: hyphens,
      wordBreak: wordBreak,
      overflowWrap: overflowWrap,
      lineBreak: lineBreak,
      tabSize: tabSize,
      mixBlendMode: mixBlendMode,
      fontVariantCaps: fontVariantCaps,
      fontVariantLigatures: fontVariantLigatures,
      quotes: quotes,
      fontStretch: fontStretch,
      fontSizeAdjust: fontSizeAdjust,
      overflow: overflow,
      columnCount: columnCount,
      columnWidth: columnWidth,
      columnGap: columnGap,
      columnRule: columnRule,
      textOverflow: textOverflow,
      boxShadow: boxShadow,
      wordSpacing: wordSpacing,
      textTransform: textTransform,
      verticalAlign: verticalAlign,
      verticalAlignLength: verticalAlignLength,
      textDecoration: textDecoration,
      textEmphasisStyle: textEmphasisStyle,
      textEmphasisPosition: textEmphasisPosition,
      rubyPosition: rubyPosition,
      rubyAlign: rubyAlign,
      textCombine: textCombine,
      textEmphasisColor: textEmphasisColor,
      pageBreakBefore: pageBreakBefore,
      pageBreakAfter: pageBreakAfter,
      breakInsideAvoid: breakInsideAvoid,
      breakAfterAvoid: breakAfterAvoid,
      textShadow: textShadow,
      backgroundRepeat: backgroundRepeat,
      backgroundSize: backgroundSize,
      backgroundPosition: backgroundPosition,
      backgroundOrigin: backgroundOrigin,
      backgroundClip: backgroundClip,
      clear: clear,
      borderCollapse: borderCollapse,
      borderSpacing: borderSpacing,
      listStyleType: listStyleType,
      listStylePosition: listStylePosition,
      tableLayout: tableLayout,
      textDecorationStyle: textDecorationStyle,
      textDecorationColor: textDecorationColor,
      bleed: bleed,
      customProperties: customProperties,
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      backgroundColor: backgroundColor,
      backgroundImage: backgroundImage,
      backgroundGradient: backgroundGradient,
      borders: borders,
      outline: outline,
      borderImage: _parseBorderImage(
        nextValues['border-image'] ?? nextValues['border-image-source'],
      ),
      width: width,
      height: height,
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
      padding: padding,
      boxSizing: boxSizing,
      explicitProperties: nextExplicit,
    );
  }

  static String _textAlignToCss(CssTextAlign align) => switch (align) {
    CssTextAlign.start => 'start',
    CssTextAlign.end => 'end',
    CssTextAlign.left => 'left',
    CssTextAlign.right => 'right',
    CssTextAlign.center => 'center',
    CssTextAlign.justify => 'justify',
  };

  const ComputedStyle._({
    this.borderImage,
    this.outline = CssOutline.none,
    required this.values,
    required this.hasExplicitTextColor,
    required this.fontSize,
    required this.parentFontSize,
    required this.lineHeight,
    required this.lineHeightFactor,
    required this.unitlessLineHeightFactor,
    required this.color,
    required this.fontWeight,
    required this.italic,
    required this.fontFamilies,
    required this.textAlign,
    required this.textIndent,
    required this.letterSpacing,
    required this.margin,
    required this.position,
    required this.cssFloat,
    required this.display,
    required this.visibility,
    required this.whiteSpace,
    required this.hangingPunctuation,
    required this.textSpacingTrim,
    required this.textAutospace,
    required this.textJustify,
    required this.textAlignLast,
    required this.initialLetterLines,
    required this.opacity,
    required this.effectiveOpacity,
    required this.filters,
    required this.backdropFilters,
    required this.transforms,
    required this.transformOriginX,
    required this.transformOriginY,
    required this.writingMode,
    required this.textOrientation,
    required this.direction,
    required this.hyphens,
    required this.wordBreak,
    required this.overflowWrap,
    required this.lineBreak,
    required this.tabSize,
    required this.mixBlendMode,
    required this.fontVariantCaps,
    required this.fontVariantLigatures,
    required this.quotes,
    required this.fontStretch,
    required this.fontSizeAdjust,
    required this.overflow,
    required this.columnCount,
    required this.columnWidth,
    required this.columnGap,
    required this.columnRule,
    required this.textOverflow,
    required this.boxShadow,
    required this.wordSpacing,
    required this.textTransform,
    required this.verticalAlign,
    required this.verticalAlignLength,
    required this.textDecoration,
    required this.textEmphasisStyle,
    required this.textEmphasisPosition,
    required this.rubyPosition,
    required this.rubyAlign,
    required this.textCombine,
    required this.textEmphasisColor,
    required this.pageBreakBefore,
    required this.pageBreakAfter,
    required this.breakInsideAvoid,
    required this.breakAfterAvoid,
    required this.textShadow,
    required this.backgroundRepeat,
    required this.backgroundSize,
    required this.backgroundPosition,
    required this.backgroundOrigin,
    required this.backgroundClip,
    required this.clear,
    required this.borderCollapse,
    required this.listStyleType,
    required this.listStylePosition,
    required this.tableLayout,
    required this.textDecorationStyle,
    required this.textDecorationColor,
    required this.bleed,
    this.customProperties = const <String, String>{},
    required this.borderSpacing,
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
    required this.backgroundColor,
    required this.backgroundImage,
    required this.backgroundGradient,
    required this.borders,
    required this.width,
    required this.height,
    required this.minWidth,
    required this.maxWidth,
    required this.minHeight,
    required this.maxHeight,
    required this.padding,
    required this.boxSizing,
    required this.explicitProperties,
  });

  /// CSS `line-height: normal` 的近似倍数（仅用于 [lineHeight] 的像素兜底）。
  ///
  /// normal 的真实行高取决于字体度量，排版层用 `TextStyle(height: null)` 让
  /// Flutter 取字体默认值（与 Chrome normal 一致）；这里只是给几何兜底
  /// （表格单元格高度估算等）一个数值。1.437 = 内置思源宋体
  /// (hhea ascent 1151 + descent 286) / 1000，Chrome 同字体实测约 1.44。
  static const _normalLineHeightFactor = 1.437;

  /// 属性 → 层叠后的字符串值。
  final Map<String, String> values;

  /// 叠放层级（CSS 2.1 §9.9）：`z-index` 整数；`auto`/未声明/非法值按 0。
  ///
  /// 只影响绘制顺序（同层按文档序），不参与布局。
  int get zIndex {
    final raw = values['z-index']?.trim().toLowerCase();
    if (raw == null || raw.isEmpty || raw == 'auto') {
      return 0;
    }
    return int.tryParse(raw) ?? 0;
  }

  /// 是否存在作者/内联显式指定的文字色（暗色替换需要）。
  final bool hasExplicitTextColor;

  /// 最终字号（逻辑像素）。
  final double fontSize;

  /// 父级字号（逻辑像素）；根元素取 rootFontSize。
  ///
  /// `vertical-align: super/sub` 的基线偏移按父级字号算（Chrome 实测），
  /// 与自身字号无关——`sup { font-size: 0.83em }` 不会让偏移跟着变小。
  final double parentFontSize;

  /// 最终行高（逻辑像素）。
  final double lineHeight;

  /// 行高相对字号的倍数。
  final double? lineHeightFactor;

  /// 无单位行高因子（`line-height: 1.5`）；px/百分比来源为 null。
  ///
  /// 继承语义（CSS 2.1 §10.8）：无单位因子随继承传递并按子元素自身字号
  /// 重算；px/百分比继承的是父级已解算的绝对行高。
  final double? unitlessLineHeightFactor;

  /// 最终文字颜色。
  final Color color;

  /// 字重 100–900。
  final int fontWeight;

  /// 是否斜体。
  final bool italic;

  /// 字体族列表（font-family 声明顺序，首项优先）。
  final List<String> fontFamilies;

  /// 首选字体族；未声明时为 null。
  String? get fontFamily => fontFamilies.isEmpty ? null : fontFamilies.first;

  /// fallback 链（首项之后的家族）。
  List<String> get fontFamilyFallback => fontFamilies.length <= 1
      ? const <String>[]
      : List<String>.unmodifiable(fontFamilies.sublist(1));

  /// 文本对齐。
  final CssTextAlign textAlign;

  /// 首行缩进（逻辑像素）。
  final double textIndent;

  /// 字间距（逻辑像素，可为负）。
  final double letterSpacing;

  /// 四边 margin（逻辑像素）。
  final CssEdges margin;

  /// 定位方式（不继承，初始 `static`）。
  final CssPosition position;

  /// 浮动方向（不继承，初始 `none`）。
  final CssFloat cssFloat;

  /// 显示类型（不继承，初始 `block`）。
  final CssDisplay display;

  /// 可见性（继承，初始 visible）。
  final CssVisibility visibility;

  /// 空白处理（继承，初始 normal）。
  final CssWhiteSpace whiteSpace;

  /// 标点悬挂（继承，初始 none；P7-18）。
  final CssHangingPunctuation hangingPunctuation;

  /// 标点挤压（继承，初始 normal；P7-19）。
  final CssTextSpacingTrim textSpacingTrim;

  /// 中西文自动间距（继承，初始 none；P7-20）。
  final CssTextAutospace textAutospace;

  /// 两端对齐拉伸方式（继承，初始 auto；P7-21）。
  final CssTextJustify textJustify;

  /// 末行对齐（继承；null = auto，末行按 start；P7-21）。
  final CssTextAlign? textAlignLast;

  /// 首字下沉跨行数（继承；null = normal；P7-28 近似）。
  final double? initialLetterLines;

  /// 元素不透明度（0～1，不继承，初始 1；P2-37）。
  final double opacity;

  /// 沿级联父链累计后的不透明度（含本元素），供合成使用。
  ///
  /// `opacity` 不继承，但父级半透明会整体作用于子树：Chrome 的
  /// `getComputedStyle` 只报各自的值（父 0.5 / 子 0.4），实际合成是 0.2。
  /// 因此构造时做乘积：`父.effectiveOpacity * opacity`，根元素为自身值。
  /// 读取点：章节源应把 `chainStyle(chain).effectiveOpacity` 传给绘制层/合成；
  /// 注意 flat 管线用阅读器基准样式重建块样式时父链会丢，重建后的值不累计祖先。
  final double effectiveOpacity;

  /// `filter` 的有序滤镜列表（非继承，初始空）。
  ///
  /// 绘制层按声明顺序依次合成（先 blur 再 grayscale …）；每种滤镜的参数含义
  /// 见 [CssFilter] 与 [CssFilterKind]。
  final List<CssFilter> filters;

  /// `backdrop-filter`（元素背后区域的滤镜）：分页阅读器里以「页面背景」
  /// 作为 backdrop 近似（无法采样已绘制内容，见审计文档的已知限制）。
  final List<CssFilter> backdropFilters;

  /// `transform` 的有序变换列表（非继承，初始空）。
  ///
  /// 每项按 [CssTransform.kind] 分派；translate 的百分比保留标记，绘制层
  /// 以边框盒宽/高为基准解算。
  final List<CssTransform> transforms;

  /// `transform-origin` 的横轴位置（默认 50%，百分比基准 = 边框盒宽）。
  final CssLength transformOriginX;

  /// `transform-origin` 的纵轴位置（默认 50%，百分比基准 = 边框盒高）。
  final CssLength transformOriginY;

  /// 书写模式（继承，初始 [CssWritingMode.horizontalTb]）。
  final CssWritingMode writingMode;

  /// 竖排字向（继承，初始 [CssTextOrientation.mixed]）。
  final CssTextOrientation textOrientation;

  /// 文本方向（继承，初始 [CssDirection.ltr]）。
  final CssDirection direction;

  /// 行内文本是否从右向左（`direction: rtl`）。
  ///
  /// 排版/绘制层把它映射成 Flutter 的 `TextDirection`（行内 baseDirection）：
  /// `TextPainter(textDirection: style.isRtl ? TextDirection.rtl : ltr)`。
  bool get isRtl => direction == CssDirection.rtl;

  /// 物理化后的文本对齐：`start`/`end` 按 [direction] 折成 left/right。
  ///
  /// 排版/绘制层应读它（而不是原始 [textAlign]）：`direction: rtl` 时
  /// `start` 是右对齐、`end` 是左对齐；`left`/`right`/`center`/`justify`
  /// 原样返回。
  CssTextAlign get resolvedTextAlign => switch (textAlign) {
    CssTextAlign.start => isRtl ? CssTextAlign.right : CssTextAlign.left,
    CssTextAlign.end => isRtl ? CssTextAlign.left : CssTextAlign.right,
    _ => textAlign,
  };

  /// 连字符断行（继承，初始 [CssHyphens.manual]）。
  final CssHyphens hyphens;

  /// 断词策略（继承，初始 [CssWordBreak.normal]）。
  final CssWordBreak wordBreak;

  /// 长词换行策略（继承，初始 [CssOverflowWrap.normal]）。
  final CssOverflowWrap overflowWrap;

  /// 断行严格度（`line-break`，继承，初始 `auto`）。
  final CssLineBreak lineBreak;

  /// 制表位宽度（`tab-size`，以空格数计；继承，初始 8）。
  final int tabSize;

  /// 混合模式（`mix-blend-mode`，非继承，初始 `normal`）。
  final CssMixBlendMode mixBlendMode;

  /// 小型大写字母族（继承，初始 [CssFontVariantCaps.normal]）。
  ///
  /// 来源：`font-variant-caps` 长属性或 `font-variant` 简写（含 `font` 简写里的
  /// `small-caps` token）。绘制层可用 `FontFeature.enable('smcp')` 实现，
  /// 字体无对应特性时按原样绘制（stub）。
  final CssFontVariantCaps fontVariantCaps;

  /// 连字策略（继承，初始 [CssFontVariantLigatures.normal]）。
  final CssFontVariantLigatures fontVariantLigatures;

  /// 引号规则（继承，初始 [CssQuotesAuto]）。
  ///
  /// 消费点在行内文本生成阶段：`<q>` 开/闭引号按嵌套层级取用。
  final CssQuotes quotes;

  /// 字体拉伸（`font-stretch`，继承，初始 100 = normal）。
  ///
  /// 数值是百分比（75 = condensed、87.5 = semi-condensed、125 = expanded…），
  /// 绘制层映射成 `FontVariation('wdth', fontStretch)`；字体无 wdth 轴时
  /// 按原样绘制（不合成）。
  final double fontStretch;

  /// 字号调整（`font-size-adjust`，继承）；null = none（初始值）。
  ///
  /// 绘制层按 1em 的 x-height 比例换算字号；当前引擎不消费，先保留字段。
  final double? fontSizeAdjust;

  /// 溢出处理（非继承，初始 [CssOverflow.visible]）。
  ///
  /// 绘制层用它区分「声明了 width 但 overflow: visible 的正常外溢」与
  /// 「hidden/clip/auto/scroll 应裁剪」。
  final CssOverflow overflow;

  /// `column-count`（非继承）；null = auto（未声明或 auto）。
  final int? columnCount;

  /// `column-width`（非继承）；null = auto。百分比按可用宽解算。
  final CssLength? columnWidth;

  /// `column-gap` 像素值（非继承）；null = normal（布局层按 1em 处理）。
  final double? columnGap;

  /// `column-rule` 简写（非继承）；null = 无分隔线。复用 [CssBorderSide]。
  final CssBorderSide? columnRule;

  /// 文本溢出处理（不继承，初始 clip；P2-37，限定 clip/ellipsis）。
  final CssTextOverflow textOverflow;

  /// 块阴影（不继承，初始无；P2-37，仅首个阴影、blur 不消费）。
  final CssBoxShadow? boxShadow;

  /// 词间距（逻辑像素，继承，初始 0）。
  final double wordSpacing;

  /// 文本大小写变换（继承，初始 none）。
  final CssTextTransform textTransform;

  /// 行内垂直对齐（不继承，初始 baseline）。
  final CssVerticalAlign verticalAlign;

  /// `vertical-align: <length> | <percentage>` 的数值偏移（W2）。
  ///
  /// 单位像素，保留 CSS 符号（正 = 向上抬高）；关键字取值时为 null。
  /// 百分比已按本元素行高解算。读取点：行内 run 的基线位移取
  /// [verticalAlignShift]（已翻成「正值向下」），不要直接用本字段参与布局。
  final double? verticalAlignLength;

  /// 文本装饰线（`text-decoration`，不继承）。
  final CssTextDecoration textDecoration;

  /// 着重号样式（继承，初始 none）。
  final CssTextEmphasisStyle textEmphasisStyle;

  /// 着重号位置（继承，初始 over）。
  final CssTextEmphasisPosition textEmphasisPosition;

  /// 注音位置（横排上/下，竖排列右/列左）。
  final CssRubyPosition rubyPosition;

  /// 注音对齐（基字区间内 start/center/end/space-between）。
  final CssRubyAlign rubyAlign;

  /// 縦中横：竖排数字组合（`all` / `digits` 同口径，`none` 不组合）。
  final CssTextCombine textCombine;

  /// 着重号颜色；null 表示跟随文字颜色。
  final Color? textEmphasisColor;

  /// 块前强制分页（`page-break-before: always` 等）。
  final bool pageBreakBefore;

  /// 块后强制分页。
  final bool pageBreakAfter;

  /// 块内禁止分页（`break-inside: avoid`）。
  final bool breakInsideAvoid;

  /// 块后避免分页（`break-after: avoid`，标题不落页底，P3-22）。
  final bool breakAfterAvoid;

  /// 文本阴影列表（继承，空表示无阴影）。
  final List<CssTextShadow> textShadow;

  /// 背景平铺方式（`background-repeat`，初始 repeat）。
  final CssBackgroundRepeat backgroundRepeat;

  /// 背景尺寸（`background-size`，初始 auto）。
  final CssBackgroundSize backgroundSize;

  /// 背景位置（`background-position`，初始 0% 0%）。
  final CssBackgroundPosition backgroundPosition;

  /// 背景绘制区域（`background-origin`，初始 padding-box）。
  final CssBackgroundOrigin backgroundOrigin;

  /// 背景裁剪区域（`background-clip`，初始 border-box）。
  final CssBackgroundClip backgroundClip;

  /// 清除浮动（`clear`，不继承）。
  final CssClear clear;

  /// 表格边框合并（`border-collapse`，继承）。
  final CssBorderCollapse borderCollapse;

  /// 表格边框间距（`border-spacing`，继承；top/bottom 存垂直，left/right 存水平）。
  final CssEdges borderSpacing;

  /// 列表标记类型（`list-style-type`，继承；P9-12）。
  final CssListStyleType listStyleType;

  /// 列表标记位置（`list-style-position`，非继承，初始 outside；W2）。
  final CssListStylePosition listStylePosition;

  /// 自定义属性（`--token`，继承；P9-14）：`var()` 的取值表。
  final Map<String, String> customProperties;

  /// 表格列宽算法（`table-layout`，非继承；P9-17）。
  final CssTableLayout tableLayout;

  /// 装饰线线型（`text-decoration-style`，P9-18）。
  final CssTextDecorationStyle textDecorationStyle;

  /// 装饰线颜色（`text-decoration-color`，null 表示跟随文字色）。
  final Color? textDecorationColor;

  /// 出血方向（多看 `duokan-bleed`，P9-22）。
  final CssBleed bleed;

  /// 上定位偏移（`top`，未继承；null 表示未声明）。
  final CssLength? top;

  /// 右定位偏移。
  final CssLength? right;

  /// 下定位偏移。
  final CssLength? bottom;

  /// 左定位偏移。
  final CssLength? left;

  /// 是否脱离正常流（`position: absolute` / `fixed`）。
  ///
  /// 布局层（T1/T3）用它把块从正常流中摘出：绝对定位块不占行/页空间，
  /// 位置改用 [resolveAbsoluteBox]；`fixed` 是相对页面（视口）定位，
  /// 包含块取页面内容区。
  bool get isOutOfFlow =>
      position == CssPosition.absolute || position == CssPosition.fixed;

  /// 解算绝对定位盒（仅 `position: absolute|fixed` 有意义，其余返回 null）。
  ///
  /// [containingWidth]/[containingHeight] 是**包含块的 padding box** 尺寸
  /// （CSS 2.1 §10.1：最近 positioned 祖先的 padding box；flat 管线里通常
  /// 传页面/正文内容区尺寸，由 T3 决定）。偏移与尺寸的百分比都按它解算。
  ///
  /// 规则（非替换块级元素）：
  /// 1. `width` 声明值优先（受 min/max 约束）；`width: auto` 且左右偏移都非
  ///    auto 时由 `cbW - left - right - 外边距/边框/内边距` 推出；
  /// 2. 尺寸已知但只给一侧偏移时，另一侧由容器推出（贴右/贴底）；
  /// 3. 左右偏移都 auto → 用静态位置（返回的 left/right 均为 null）；
  /// 4. 竖向同理（top/bottom/height，百分比按 [containingHeight]）。
  ///
  /// 消费点：T1/T3 摆放绝对定位块时读它（不要再自己算百分比），
  /// 绘制层只负责按最终矩形裁剪/绘制。
  CssAbsoluteBox? resolveAbsoluteBox({
    required double containingWidth,
    required double containingHeight,
  }) {
    if (!isOutOfFlow) {
      return null;
    }
    double? resolve(CssLength? length, double base) {
      if (length == null) {
        return null;
      }
      return length.resolve(base);
    }

    final horizontalEdges =
        margin.horizontal +
        padding.horizontal +
        borders.left.width +
        borders.right.width;
    final verticalEdges =
        margin.vertical +
        padding.vertical +
        borders.top.width +
        borders.bottom.width;

    var boxWidth = resolve(width, containingWidth);
    var boxHeight = resolve(height, containingHeight);
    var boxLeft = resolve(left, containingWidth);
    var boxRight = resolve(right, containingWidth);
    var boxTop = resolve(top, containingHeight);
    var boxBottom = resolve(bottom, containingHeight);

    // 1) 两侧偏移都有、尺寸 auto → 由偏移推出尺寸。
    if (boxWidth == null && boxLeft != null && boxRight != null) {
      boxWidth = math.max(
        0,
        containingWidth - boxLeft - boxRight - horizontalEdges,
      );
    }
    if (boxHeight == null && boxTop != null && boxBottom != null) {
      boxHeight = math.max(
        0,
        containingHeight - boxTop - boxBottom - verticalEdges,
      );
    }
    // min/max 约束（CSS 2.1 §10.4）。
    if (boxWidth != null) {
      final minW = resolve(minWidth, containingWidth);
      final maxW = resolve(maxWidth, containingWidth);
      if (maxW != null && boxWidth > maxW) {
        boxWidth = maxW;
      }
      if (minW != null && boxWidth < minW) {
        boxWidth = minW;
      }
    }
    if (boxHeight != null) {
      final minH = resolve(minHeight, containingHeight);
      final maxH = resolve(maxHeight, containingHeight);
      if (maxH != null && boxHeight > maxH) {
        boxHeight = maxH;
      }
      if (minH != null && boxHeight < minH) {
        boxHeight = minH;
      }
    }
    // 2) 尺寸已知、只给一侧偏移 → 推出另一侧（贴右/贴底）。
    if (boxLeft == null && boxRight != null && boxWidth != null) {
      boxLeft = containingWidth - boxRight - boxWidth - horizontalEdges;
    } else if (boxRight == null && boxLeft != null && boxWidth != null) {
      boxRight = containingWidth - boxLeft - boxWidth - horizontalEdges;
    }
    if (boxTop == null && boxBottom != null && boxHeight != null) {
      boxTop = containingHeight - boxBottom - boxHeight - verticalEdges;
    } else if (boxBottom == null && boxTop != null && boxHeight != null) {
      boxBottom = containingHeight - boxTop - boxHeight - verticalEdges;
    }
    return CssAbsoluteBox(
      left: boxLeft,
      right: boxRight,
      top: boxTop,
      bottom: boxBottom,
      width: boxWidth,
      height: boxHeight,
    );
  }

  /// 影响文本测量的样式指纹（P2-26 段落缓存键的一部分）。
  ///
  /// 只含参与 [TextLayoutEngine] 测量的字段；颜色/装饰/背景不在此列。
  String get layoutFingerprint =>
      'fs=$fontSize;lh=$lineHeight;ls=$letterSpacing;ws=$wordSpacing;'
      'ta=${textAlign.name};ti=$textIndent;tt=${textTransform.name};'
      'wsp=${whiteSpace.name};fw=$fontWeight;it=$italic;'
      'ff=${fontFamilies.join(",")};'
      'disp=${display.name};vis=${visibility.name};'
      // P7-18~21 新增排版输入（影响缓存内的 justifyExtra/行宽）：缺失
      // 会撞键（P7-29 检查清单第 1 条的修正项）。
      'hp=${hangingPunctuation.name};ts=${textSpacingTrim.name};'
      'as=${textAutospace.name};tj=${textJustify.name};'
      'al=${textAlignLast?.name ?? "auto"};il=${initialLetterLines ?? 0};'
      // 制表位与断行严格度同样影响测量结果，必须进指纹，否则不同 tab-size
      // 的块会复用彼此的行布局（71 用例实测：两个 pre 共用同一宽度）。
      'tab=$tabSize;lb=${lineBreak.name};tc=${textCombine.name};'
      'wm=${writingMode.name};to=${textOrientation.name};'
      'hy=${hyphens.name};wb=${wordBreak.name};ow=${overflowWrap.name};'
      'dir=${direction.name}';

  /// 行内基线偏移（逻辑像素，正值向下）。
  ///
  /// `vertical-align: <length> | <percentage>` 直接取该数值的相反数
  /// （CSS 正值是向上抬高）；其余按关键字算：
  /// Chrome 实测（headless 155，Source Han Serif / Times / Courier 同值，
  /// 父字号 8–100px 线性拟合）：`sup = -(父字号/3 + 1)`、
  /// `sub = 父字号/5 + 1`；本引擎 17px 父字号下即 -6.66 / +4.39，
  /// 与浏览器逐像素一致。子元素自身字号（如 UA 的 `sup{font-size:0.83em}`）
  /// 不参与计算——0.7em / 2em 子字号实测偏移不变。
  /// 其余关键字不产生基线偏移，text-top/text-bottom/middle 由行排版层按行盒处理。
  double get verticalAlignShift {
    final length = verticalAlignLength;
    if (length != null) {
      return -length;
    }
    return switch (verticalAlign) {
      CssVerticalAlign.superscript => -(parentFontSize / 3 + 1),
      CssVerticalAlign.subscript => parentFontSize / 5 + 1,
      _ => 0,
    };
  }

  /// 背景色（不继承，初始透明）。
  final Color backgroundColor;

  /// 背景图 URL（`background-image: url(...)` 的解析结果，绘制留资源任务）。
  final String? backgroundImage;

  /// 背景渐变（`background-image: linear-gradient(...)` / `radial-gradient(...)`）。
  ///
  /// 不继承，初始 null；与 [backgroundImage]（url）互斥。读取点：绘制层
  /// 优先判 `backgroundGradient != null`，再按 CssLinearGradient /
  /// CssRadialGradient 分派画渐变；章节源做「渐变文字取首色」等兜底时
  /// 可读 `backgroundGradient!.stops.first.color`。
  final CssGradient? backgroundGradient;

  /// 按声明顺序排列的背景层（首个在最上层）。
  ///
  /// 多背景长属性在层叠后仍以逗号列表保存在 [values]；这里按 CSS 的
  /// 列表循环规则补齐 repeat/size/position/origin/clip，再逐层解析图像。
  /// 绘制时逆序执行，让第一层最后落在画布上。
  List<CssBackgroundLayer> get backgroundLayers {
    final rawImages = values['background-image'];
    if (rawImages == null) {
      if (backgroundGradient == null && backgroundImage == null) {
        return const <CssBackgroundLayer>[];
      }
      return <CssBackgroundLayer>[
        CssBackgroundLayer(
          image: backgroundImage,
          gradient: backgroundGradient,
          repeat: backgroundRepeat,
          size: backgroundSize,
          position: backgroundPosition,
          origin: backgroundOrigin,
          clip: backgroundClip,
        ),
      ];
    }
    final images = _splitTopLevel(rawImages, ',');
    if (images.length <= 1) {
      if (backgroundGradient == null && backgroundImage == null) {
        return const <CssBackgroundLayer>[];
      }
      return <CssBackgroundLayer>[
        CssBackgroundLayer(
          image: backgroundImage,
          gradient: backgroundGradient,
          repeat: backgroundRepeat,
          size: backgroundSize,
          position: backgroundPosition,
          origin: backgroundOrigin,
          clip: backgroundClip,
        ),
      ];
    }

    List<String> listValue(String property) {
      final raw = values[property];
      return raw == null ? const <String>[] : _splitTopLevel(raw, ',');
    }

    String at(List<String> items, int index) {
      if (items.isEmpty) {
        return '';
      }
      return items[index % items.length];
    }

    final repeats = listValue('background-repeat');
    final sizes = listValue('background-size');
    final positions = listValue('background-position');
    final origins = listValue('background-origin');
    final clips = listValue('background-clip');
    return <CssBackgroundLayer>[
      for (var index = 0; index < images.length; index++)
        CssBackgroundLayer(
          image: _parseUrl(images[index]),
          gradient: _parseGradient(images[index], fontSize: fontSize),
          repeat:
              _parseBackgroundRepeat(at(repeats, index)) ??
              CssBackgroundRepeat.repeat,
          size:
              _parseBackgroundSize(
                at(sizes, index),
                fontSize: fontSize,
                rootFontSize: fontSize,
              ) ??
              const CssBackgroundSize.keyword(CssBackgroundSizeMode.auto),
          position:
              _parseBackgroundPosition(
                at(positions, index),
                fontSize: fontSize,
                rootFontSize: fontSize,
              ) ??
              const CssBackgroundPosition(
                x: CssLength(0, isPercent: true),
                y: CssLength(0, isPercent: true),
              ),
          origin:
              _parseBackgroundOrigin(at(origins, index)) ??
              CssBackgroundOrigin.paddingBox,
          clip:
              _parseBackgroundClip(at(clips, index)) ??
              CssBackgroundClip.borderBox,
        ),
    ];
  }

  /// 四边边框与四角圆角。
  final CssBorders borders;

  /// 边框外侧轮廓；不参与布局。
  final CssOutline outline;

  /// 九宫格边图（`border-image`）；未声明为 null。边框绘制时替代普通边框色。
  final CssBorderImage? borderImage;

  /// 指定宽度；null 表示未声明（等同于 auto）。
  final CssLength? width;

  /// 指定高度；null 表示未声明（等同于 auto）。
  final CssLength? height;

  /// 最小宽度。
  final CssLength? minWidth;

  /// 最大宽度；`max-width: none` 时为 null。
  final CssLength? maxWidth;

  /// 最小高度。
  final CssLength? minHeight;

  /// 最大高度；`max-height: none` 时为 null。
  final CssLength? maxHeight;

  /// 四边内边距（逻辑像素，百分比已按 containingWidth 解算，负值钳 0）。
  final CssEdges padding;

  /// 盒模型尺寸基准（不继承，初始 `content-box`）。
  final CssBoxSizing boxSizing;

  /// 元素自身层叠出的属性集合。
  final Set<String> explicitProperties;

  /// 取原始指定值。
  String? operator [](String property) => values[property.toLowerCase()];

  /// 是否包含原始属性。
  bool contains(String property) => values.containsKey(property.toLowerCase());

  /// 内容盒宽（CSS 2.1 §10.3 简化）：给定包含块内容宽 [availableWidth]，
  /// 返回该元素**用于文本排版的内容宽**（不含 padding/border）。
  ///
  /// 排版侧应直接用它当 `maxWidth`，不要再手写
  /// `正文区宽 - margin - padding - border`：手写式丢掉了 `width` 与
  /// `box-sizing`，`box-sizing: border-box; width: 200px; padding: 10px;
  /// border: 3px` 会按 200px 排字（正确内容是 200-20-6=174px），行宽超出盒宽。
  ///
  /// 解算顺序：未声明 `width`（auto）取 `availableWidth` 扣 margin 与
  /// padding/border；声明宽按 `box-sizing` 折成内容宽（border-box 扣左右
  /// padding+border）；`min-width`/`max-width` 最后钳制（min 优先）；
  /// 百分比按 [availableWidth] 解算。语义与 `BoxModel.resolveContentWidth`
  /// 一致（两者应保持同步，后续可让 BoxModel 委托到这里）。
  double contentBoxWidth(double availableWidth) {
    final inset = padding.horizontal + borders.left.width + borders.right.width;
    final autoWidth = math.max(0.0, availableWidth - inset - margin.horizontal);
    final max = _contentBoxLength(maxWidth, availableWidth, inset);
    final min = _contentBoxLength(minWidth, availableWidth, inset);
    var result = _contentBoxLength(width, availableWidth, inset) ?? autoWidth;
    if (max != null) {
      result = math.min(result, max);
    }
    if (min != null) {
      result = math.max(result, min);
    }
    return math.max(0.0, result);
  }

  /// 声明尺寸 → 内容宽：`border-box` 扣掉左右内缩；auto/未声明返回 null。
  double? _contentBoxLength(
    CssLength? length,
    double availableWidth,
    double inset,
  ) {
    if (length == null || length.isAuto) {
      return null;
    }
    final declared = length.resolve(availableWidth);
    if (declared == null) {
      return null;
    }
    final value = boxSizing == CssBoxSizing.borderBox
        ? declared - inset
        : declared;
    return math.max(0.0, value);
  }

  @override
  String toString() =>
      'ComputedStyle(fontSize=$fontSize, lineHeight=$lineHeight, '
      'color=$color, weight=$fontWeight, italic=$italic, align=$textAlign, '
      'indent=$textIndent, letterSpacing=$letterSpacing, margin=$margin, '
      'families=$fontFamilies, position=$position, float=$cssFloat, '
      'display=$display, visibility=$visibility, whiteSpace=$whiteSpace, '
      'wordSpacing=$wordSpacing, transform=$textTransform, '
      'valign=$verticalAlign, decoration=$textDecoration, '
      'emphasis=$textEmphasisStyle/$textEmphasisPosition, '
      'break=$pageBreakBefore/$pageBreakAfter/avoid=$breakInsideAvoid, '
      'shadow=${textShadow.length}, bgRepeat=$backgroundRepeat, '
      'bgSize=${backgroundSize.mode}, clear=$clear, '
      'bg=$backgroundColor, borders=$borders, '
      'size=$width/$height, min=$minWidth/$minHeight, '
      'max=$maxWidth/$maxHeight, padding=$padding, boxSizing=$boxSizing)';

  /// 解析 `width` / `height` / `min-*` / `max-*` 为尺寸值。
  ///
  /// `auto` 解析为 [CssLength.auto]，`none`（仅 max-* 合法）视为未设上限返回
  /// null；百分比保留标记不在此层解算。
  static CssLength? _resolveCssLength(
    String raw, {
    required double fontSize,
    required double rootFontSize,
    double percentBase = 0,
  }) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) {
      return null;
    }
    if (value == 'auto') {
      return const CssLength.auto();
    }
    if (value == 'none') {
      return null;
    }
    final percent = _parsePercent(value);
    if (percent != null) {
      return CssLength(percent, isPercent: true);
    }
    final resolved = _resolveLength(
      value,
      fontSize: fontSize,
      parentFontSize: fontSize,
      rootFontSize: rootFontSize,
      percentBase: percentBase,
    );
    return resolved == null ? null : CssLength(resolved);
  }

  /// 解析 `padding` 简写与 `padding-*` 长写；百分比按 [containingWidth] 解算。
  static CssEdges _resolvePadding(
    Map<String, String> values,
    Set<String> explicit, {
    required double fontSize,
    required double rootFontSize,
    required double containingWidth,
  }) {
    String? value(String property) =>
        explicit.contains(property) ? values[property] : null;

    // padding 不允许负值，负值按 CSS 规范钳到 0。
    double padding(String raw) {
      final resolved = _resolveLength(
        raw,
        fontSize: fontSize,
        parentFontSize: fontSize,
        rootFontSize: rootFontSize,
        percentBase: containingWidth,
      );
      return resolved == null || resolved < 0 ? 0 : resolved;
    }

    final sides = <double>[0, 0, 0, 0];
    final shorthand = value('padding');
    if (shorthand != null) {
      final parts = _expandFour(shorthand.trim().split(RegExp(r'\s+')));
      for (var i = 0; i < parts.length && i < 4; i++) {
        sides[i] = padding(parts[i]);
      }
    }
    const names = <(int, String)>[
      (0, 'top'),
      (1, 'right'),
      (2, 'bottom'),
      (3, 'left'),
    ];
    for (final (index, name) in names) {
      final raw = value('padding-$name');
      if (raw != null) {
        sides[index] = padding(raw);
      }
    }
    return CssEdges(
      top: sides[0],
      right: sides[1],
      bottom: sides[2],
      left: sides[3],
    );
  }

  /// 解析 `box-sizing`；只认 `border-box`，其余（含未声明）回退 contentBox。
  static CssBoxSizing _parseBoxSizing(String? raw) =>
      raw?.trim().toLowerCase() == 'border-box'
      ? CssBoxSizing.borderBox
      : CssBoxSizing.contentBox;

  /// 解析 `border` / `border-*` / `border-radius`（§65 背景与边框组）。
  static CssBorders _resolveBorders(
    Map<String, String> values,
    Set<String> explicit, {
    required double fontSize,
    required double rootFontSize,
    required Color color,
  }) {
    String? value(String property) =>
        explicit.contains(property) ? values[property] : null;

    double? length(String raw) => switch (raw.trim().toLowerCase()) {
      'thin' => 1,
      'medium' => 3,
      'thick' => 5,
      _ => _resolveLength(
        raw,
        fontSize: fontSize,
        parentFontSize: fontSize,
        rootFontSize: rootFontSize,
        percentBase: 0,
      ),
    };

    CssBorderSide? parseSide(String raw) {
      final tokens = raw.trim().split(RegExp(r'\s+'));
      var width = 3.0;
      var style = CssBorderStyle.none;
      var sideColor = color;
      var sawToken = false;
      for (final token in tokens) {
        if (token.isEmpty) {
          continue;
        }
        final parsedStyle = _parseBorderStyle(token);
        if (parsedStyle != null) {
          style = parsedStyle;
          sawToken = true;
          continue;
        }
        final parsedColor = _parseColor(token);
        final parsedWidth = length(token);
        if (parsedWidth != null) {
          width = parsedWidth;
          sawToken = true;
        } else if (parsedColor != null) {
          sideColor = parsedColor;
          sawToken = true;
        }
      }
      return sawToken
          ? CssBorderSide(width: width, style: style, color: sideColor)
          : null;
    }

    final initial = CssBorderSide(
      width: 3,
      style: CssBorderStyle.none,
      color: color,
    );
    var sides = <CssBorderSide>[initial, initial, initial, initial];

    final shorthand = parseSide(value('border') ?? '');
    if (shorthand != null) {
      sides = List<CssBorderSide>.filled(4, shorthand);
    }

    void applyWidths(String property) {
      final raw = value(property);
      if (raw == null) {
        return;
      }
      final parts = _expandFour(raw.split(RegExp(r'\s+')));
      for (var i = 0; i < parts.length; i++) {
        final width = length(parts[i]);
        if (width != null) {
          sides[i] = CssBorderSide(
            width: width,
            style: sides[i].style,
            color: sides[i].color,
          );
        }
      }
    }

    void applyStyles(String property) {
      final raw = value(property);
      if (raw == null) {
        return;
      }
      final parts = _expandFour(raw.split(RegExp(r'\s+')));
      for (var i = 0; i < parts.length; i++) {
        final style = _parseBorderStyle(parts[i]);
        if (style != null) {
          sides[i] = CssBorderSide(
            width: sides[i].width,
            style: style,
            color: sides[i].color,
          );
        }
      }
    }

    void applyColors(String property) {
      final raw = value(property);
      if (raw == null) {
        return;
      }
      final parts = _expandFour(raw.split(RegExp(r'\s+')));
      for (var i = 0; i < parts.length; i++) {
        final parsed = _parseColor(parts[i]);
        if (parsed != null) {
          sides[i] = CssBorderSide(
            width: sides[i].width,
            style: sides[i].style,
            color: parsed,
          );
        }
      }
    }

    applyWidths('border-width');
    applyStyles('border-style');
    applyColors('border-color');

    const sides4 = <(int, String)>[
      (0, 'top'),
      (1, 'right'),
      (2, 'bottom'),
      (3, 'left'),
    ];
    for (final (index, name) in sides4) {
      final parsed = parseSide(value('border-$name') ?? '');
      if (parsed != null) {
        sides[index] = parsed;
      }
    }
    for (final (index, name) in sides4) {
      final rawWidth = value('border-$name-width');
      if (rawWidth != null) {
        final width = length(rawWidth);
        if (width != null) {
          sides[index] = CssBorderSide(
            width: width,
            style: sides[index].style,
            color: sides[index].color,
          );
        }
      }
      final rawStyle = value('border-$name-style');
      if (rawStyle != null) {
        final style = _parseBorderStyle(rawStyle);
        if (style != null) {
          sides[index] = CssBorderSide(
            width: sides[index].width,
            style: style,
            color: sides[index].color,
          );
        }
      }
      final rawColor = value('border-$name-color');
      if (rawColor != null) {
        final parsed = rawColor.trim().toLowerCase() == 'currentcolor'
            ? color
            : _parseColor(rawColor);
        if (parsed != null) {
          sides[index] = CssBorderSide(
            width: sides[index].width,
            style: sides[index].style,
            color: parsed,
          );
        }
      }
    }
    // 线型归一（Chrome 语义，W2 实测）：
    // - `border-style: none/hidden` 的计算宽度为 0——`border: 4px hidden`
    //   浏览器 borderTopWidth=0px、盒子不长，这里同步清零，避免盒模型把
    //   5px/4px 的「不可见边框」算进内缩；
    // - 只写线型没写宽度时按 CSS medium（3px）。
    sides = [
      for (final side in sides)
        if (side.style == CssBorderStyle.none)
          CssBorderSide(style: CssBorderStyle.none, color: side.color)
        else
          side,
    ];

    var radii = <double>[0, 0, 0, 0];
    final radiusPercents = <double?>[null, null, null, null];
    final radiiY = <double?>[null, null, null, null];
    final radiusPercentsY = <double?>[null, null, null, null];
    // 百分比圆角（`border-radius: 50%` 的头像/徽章）按盒尺寸解算；像素圆角
    // 在级联期直接算好。
    ({double value, double? percent})? parseRadius(String raw) {
      final percent = _parseRadiusPercent(raw);
      if (percent != null) {
        return (value: 0, percent: percent);
      }
      final value = length(raw);
      return value == null ? null : (value: value, percent: null);
    }

    void applyRadius(
      int index,
      ({double value, double? percent}) horizontal,
      ({double value, double? percent}) vertical,
    ) {
      radii[index] = horizontal.value;
      radiusPercents[index] = horizontal.percent;
      radiiY[index] = vertical.percent == null ? vertical.value : null;
      radiusPercentsY[index] = vertical.percent;
    }

    final radiusRaw = value('border-radius');
    if (radiusRaw != null) {
      final normalized = radiusRaw.replaceAll(RegExp(r'\s*/\s*'), ' / ').trim();
      final halves = normalized.split(' / ');
      if (halves.length <= 2) {
        final horizontal = _expandFour(halves.first.split(RegExp(r'\s+')))
            .map(parseRadius)
            .toList();
        final vertical = _expandFour(
          (halves.length == 2 ? halves[1] : halves.first).split(RegExp(r'\s+')),
        ).map(parseRadius).toList();
        if (horizontal.length == 4 &&
            vertical.length == 4 &&
            horizontal.every((component) => component != null) &&
            vertical.every((component) => component != null)) {
          for (var i = 0; i < 4; i++) {
            applyRadius(i, horizontal[i]!, vertical[i]!);
          }
        }
      }
    }
    const corners = <(int, String)>[
      (0, 'top-left'),
      (1, 'top-right'),
      (2, 'bottom-right'),
      (3, 'bottom-left'),
    ];
    for (final (index, name) in corners) {
      final raw = value('border-$name-radius');
      if (raw != null) {
        final parts = raw
            .replaceAll(RegExp(r'\s*/\s*'), ' ')
            .trim()
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .toList();
        if (parts.isNotEmpty && parts.length <= 2) {
          final horizontal = parseRadius(parts.first);
          final vertical = parseRadius(parts.length == 2 ? parts[1] : parts[0]);
          if (horizontal != null && vertical != null) {
            applyRadius(index, horizontal, vertical);
          }
        }
      }
    }

    return CssBorders(
      top: sides[0],
      right: sides[1],
      bottom: sides[2],
      left: sides[3],
      topLeftRadius: radii[0],
      topRightRadius: radii[1],
      bottomRightRadius: radii[2],
      bottomLeftRadius: radii[3],
      topLeftRadiusPercent: radiusPercents[0],
      topRightRadiusPercent: radiusPercents[1],
      bottomRightRadiusPercent: radiusPercents[2],
      bottomLeftRadiusPercent: radiusPercents[3],
      topLeftRadiusY: radiiY[0],
      topRightRadiusY: radiiY[1],
      bottomRightRadiusY: radiiY[2],
      bottomLeftRadiusY: radiiY[3],
      topLeftRadiusPercentY: radiusPercentsY[0],
      topRightRadiusPercentY: radiusPercentsY[1],
      bottomRightRadiusPercentY: radiusPercentsY[2],
      bottomLeftRadiusPercentY: radiusPercentsY[3],
    );
  }

  /// 解析轮廓及其长属性；简写缺项重置为 CSS 初始值。
  static CssOutline _resolveOutline(
    Map<String, String> values,
    Set<String> explicit, {
    required double fontSize,
    required double rootFontSize,
    required Color color,
  }) {
    String? value(String property) =>
        explicit.contains(property) ? values[property] : null;

    CssBorderStyle styleOf(String raw) {
      if (raw.trim().toLowerCase() == 'auto') {
        return CssBorderStyle.solid;
      }
      return _parseBorderStyle(raw) ?? CssBorderStyle.none;
    }

    double widthOf(String raw) => switch (raw.trim().toLowerCase()) {
      'thin' => 1,
      'medium' => 3,
      'thick' => 5,
      _ => math.max(
        0,
        _resolveLength(
              raw,
              fontSize: fontSize,
              parentFontSize: fontSize,
              rootFontSize: rootFontSize,
              percentBase: 0,
            ) ??
            0,
      ),
    };

    Color colorOf(String raw) {
      final lower = raw.trim().toLowerCase();
      if (lower == 'currentcolor' || lower == 'invert') {
        return color;
      }
      return _parseColor(raw) ?? color;
    }

    var width = 3.0;
    var style = CssBorderStyle.none;
    var outlineColor = color;
    final shorthand = value('outline');
    if (shorthand != null) {
      for (final token in _cssTokens(shorthand)) {
        final lower = token.toLowerCase();
        if (_parseBorderStyle(lower) != null || lower == 'auto') {
          style = styleOf(token);
        } else if (lower == 'currentcolor' ||
            lower == 'invert' ||
            _parseColor(token) != null) {
          outlineColor = colorOf(token);
        } else {
          width = widthOf(token);
        }
      }
    }

    final rawWidth = value('outline-width');
    if (rawWidth != null) {
      width = widthOf(rawWidth);
    }
    final rawStyle = value('outline-style');
    if (rawStyle != null) {
      style = styleOf(rawStyle);
    }
    final rawColor = value('outline-color');
    if (rawColor != null) {
      outlineColor = colorOf(rawColor);
    }
    final rawOffset = value('outline-offset');
    final offset =
        (rawOffset == null
            ? null
            : _resolveLength(
                rawOffset,
                fontSize: fontSize,
                parentFontSize: fontSize,
                rootFontSize: rootFontSize,
                percentBase: 0,
              )) ??
        0;
    return CssOutline(
      width: width,
      style: style,
      color: outlineColor,
      offset: offset,
    );
  }

  /// 解析 `border-image` / `border-image-source`（CSS Backgrounds §6.2）。
  ///
  /// 支持常见形态：`url(...) [<n>|<n>%]{1,4} [/ <border-width>]{0,1} [stretch|
  /// repeat|round|space]?`，`source`/`slice`/`width`/`repeat` 长属性不单独解析
  /// （真书里都是简写）。缺 url 或解析不出切割量时返回 null（按无边框图处理）。
  static CssBorderImage? _parseBorderImage(String? raw) {
    if (raw == null) {
      return null;
    }
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value == 'none') {
      return null;
    }
    final urlMatch = RegExp(r'url\(\s*["\x27]?([^"\x27)]+)["\x27]?\s*\)')
        .firstMatch(value);
    if (urlMatch == null) {
      return null;
    }
    final url = urlMatch.group(1)!;
    final rest = value.replaceFirst(urlMatch.group(0)!, ' ');
    final tokens = rest
        .replaceAll('/', ' / ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    var fill = false;
    var repeat = CssBorderImageRepeat.stretch;
    final sliceTokens = <String>[];
    var inSlice = true;
    for (final token in tokens) {
      if (token == '/') {
        inSlice = false;
        continue;
      }
      switch (token) {
        case 'fill':
          fill = true;
          continue;
        case 'stretch':
        case 'repeat':
        case 'round':
        case 'space':
          repeat = switch (token) {
            'repeat' => CssBorderImageRepeat.repeat,
            'round' => CssBorderImageRepeat.round,
            'space' => CssBorderImageRepeat.space,
            _ => CssBorderImageRepeat.stretch,
          };
          continue;
      }
      if (inSlice) {
        sliceTokens.add(token);
      }
    }
    if (sliceTokens.isEmpty) {
      return null;
    }
    final percent = sliceTokens.first.endsWith('%');
    double parse(String token) {
      final text = token.endsWith('%')
          ? token.substring(0, token.length - 1)
          : token;
      final number = double.tryParse(text);
      if (number == null) {
        return 1;
      }
      return percent ? (number / 100).clamp(0.0, 1.0) : number;
    }

    final expanded = _expandFour(sliceTokens);
    final parsed = <double>[for (var i = 0; i < 4; i++) parse(expanded[i])];
    return CssBorderImage(
      url: url,
      sliceTop: parsed[0],
      sliceRight: parsed[1],
      sliceBottom: parsed[2],
      sliceLeft: parsed[3],
      slicePercent: percent,
      repeat: repeat,
      fill: fill,
    );
  }

  /// 百分比圆角：`50%` → 0.5；非百分比返回 null。
  static double? _parseRadiusPercent(String raw) {
    final value = raw.trim();
    if (!value.endsWith('%')) {
      return null;
    }
    final number = double.tryParse(value.substring(0, value.length - 1));
    if (number == null) {
      return null;
    }
    return (number / 100).clamp(0.0, 1.0);
  }

  /// 把 1–4 个值按 CSS 规则展开成上/右/下/左。
  static List<String> _expandFour(List<String> values) {
    final parts = values.where((part) => part.isNotEmpty).toList();
    return switch (parts.length) {
      1 => <String>[parts[0], parts[0], parts[0], parts[0]],
      2 => <String>[parts[0], parts[1], parts[0], parts[1]],
      3 => <String>[parts[0], parts[1], parts[2], parts[1]],
      >= 4 => parts.sublist(0, 4),
      _ => const <String>[],
    };
  }

  /// 解析 `border-style`。
  ///
  /// `groove/ridge/inset/outset` 引擎不做立体浮雕绘制，按 **solid** 降级
  /// （Chrome 4px 实测同宽同色，视觉差异仅在明暗；T4 可按需再实现浮雕）。
  /// `none`/`hidden` → none（宽度在 [_resolveBorders] 里归零）。
  static CssBorderStyle? _parseBorderStyle(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'none' || 'hidden' => CssBorderStyle.none,
        'solid' => CssBorderStyle.solid,
        // 3D 边框（CSS Backgrounds §4.4）：双色明暗边，绘制层按朝向画两半。
        'groove' => CssBorderStyle.groove,
        'ridge' => CssBorderStyle.ridge,
        'inset' => CssBorderStyle.inset,
        'outset' => CssBorderStyle.outset,
        'dashed' => CssBorderStyle.dashed,
        'dotted' => CssBorderStyle.dotted,
        'double' => CssBorderStyle.double,
        _ => null,
      };

  static final RegExp _fontSizePattern = RegExp(
    r'^(\d*\.?\d+)(px|pt|pc|em|rem|%)?(?:/(\S+))?$',
  );

  /// 解析 `font` 简写（P9-09）：style/variant/weight/size[/line-height]/family。
  ///
  /// 只做阅读器需要的子集；`font: caption` 这类系统字体关键字返回 null
  /// （交给默认值）。级联层（`Cascade._expandShorthand`）复用同一个解析器，
  /// 把简写拆成长属性后再按属性名比优先级。
  /// 解析 `font` 简写（CSS Fonts 3 §4.5）。
  ///
  /// 语义要点：
  /// - 简写会**重置**未写出的子属性：`font-style`/`font-weight`/
  ///   `font-variant-caps` → normal，`font-stretch` → normal（100%），
  ///   `font-size-adjust` → none，`line-height` → normal；
  /// - 尺寸之后的部分是字体族，必须有（缺失整条声明无效，返回 null）；
  /// - `font: caption|icon|menu|message-box|small-caption|status-bar`
  ///   （含 `-webkit-` 前缀）是系统字体关键字：整套字体属性取系统值，
  ///   这里按 Chrome 实测（headless macOS）落成 16px / Arial / normal。
  static Map<String, String>? parseFontShorthand(String? raw) {
    if (raw == null) {
      return null;
    }
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    // 系统字体关键字：整条值只有一个 token。
    final systemKey = value.toLowerCase().replaceFirst('-webkit-', '');
    const systemFonts = <String>{
      'caption',
      'icon',
      'menu',
      'message-box',
      'small-caption',
      'status-bar',
    };
    if (systemFonts.contains(systemKey)) {
      return const <String, String>{
        'font-size': '16px',
        'font-family': 'Arial',
        'font-style': 'normal',
        'font-weight': 'normal',
        'font-variant-caps': 'normal',
        'font-stretch': 'normal',
        'font-size-adjust': 'none',
        'line-height': 'normal',
      };
    }
    // 按引号与空白切词，保留带空格的字体名。
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (quote != null) {
        buffer.write(char);
        if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        buffer.write(char);
        continue;
      }
      if (char == ' ' || char == '\t') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(char);
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }
    if (tokens.isEmpty) {
      return null;
    }

    // 简写重置：未写出的子属性取初始值（否则父级/其它规则的
    // font-weight/font-style/line-height 会漏进来）。
    final result = <String, String>{
      'font-style': 'normal',
      'font-weight': 'normal',
      'font-variant-caps': 'normal',
      'font-stretch': 'normal',
      'font-size-adjust': 'none',
      'line-height': 'normal',
    };
    var index = 0;
    String? size;
    String? lineHeight;
    while (index < tokens.length) {
      final token = tokens[index].toLowerCase();
      if (token == 'italic' || token == 'oblique') {
        result['font-style'] = token == 'oblique' ? 'italic' : token;
      } else if (token == 'normal') {
        // normal 是各子属性的占位，初始值已经写过。
      } else if (token == 'small-caps' ||
          token == 'all-small-caps' ||
          token == 'petite-caps' ||
          token == 'all-petite-caps' ||
          token == 'unicase' ||
          token == 'titling-caps') {
        result['font-variant-caps'] = token;
      } else if (token == 'bold' ||
          token == 'bolder' ||
          token == 'lighter' ||
          RegExp(r'^[1-9]00$').hasMatch(token)) {
        result['font-weight'] = token;
      } else if (_fontStretchKeywords.containsKey(token)) {
        result['font-stretch'] = _fontStretchKeywords[token]!;
      } else if (_fontStretchPercentPattern.hasMatch(token)) {
        result['font-stretch'] = token;
      } else {
        final match = _fontSizePattern.firstMatch(tokens[index]);
        final keyword = const <String>{
          'xx-small',
          'x-small',
          'small',
          'medium',
          'large',
          'x-large',
          'xx-large',
          'smaller',
          'larger',
        }.contains(token);
        if (match != null || keyword) {
          size = tokens[index];
          lineHeight = match?.group(3);
          break;
        }
      }
      index += 1;
    }
    if (size == null) {
      return null;
    }
    result['font-size'] = size.split('/').first;
    if (lineHeight != null) {
      result['line-height'] = lineHeight;
    }
    final family = tokens.skip(index + 1).join(' ').trim();
    // 字体族是字体简写的必填部分（CSS Fonts 3 §4.5），缺失时整条声明无效。
    if (family.isEmpty) {
      return null;
    }
    result['font-family'] = family;
    return result;
  }

  /// `font-stretch` 关键字 → 百分比（CSS Fonts 4 §2.3）。
  static const Map<String, String> _fontStretchKeywords = <String, String>{
    'ultra-condensed': '50%',
    'extra-condensed': '62.5%',
    'condensed': '75%',
    'semi-condensed': '87.5%',
    'semi-expanded': '112.5%',
    'expanded': '125%',
    'extra-expanded': '150%',
    'ultra-expanded': '200%',
  };

  static final RegExp _fontStretchPercentPattern = RegExp(
    r'^(?:[5-9]\d|1\d\d|200)(?:\.\d+)?%$',
  );

  /// 解析 `background-image` 的 url；渐变与 none 返回 null。
  static String? _parseUrl(String? raw) {
    if (raw == null) {
      return null;
    }
    final value = raw.trim();
    final lower = value.toLowerCase();
    if (value.isEmpty ||
        lower == 'none' ||
        lower.startsWith('linear-gradient') ||
        lower.startsWith('radial-gradient')) {
      return null;
    }
    final match = RegExp(
      r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)''',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) {
      return null;
    }
    final url = (match[1] ?? match[2] ?? match[3])?.trim();
    return url == null || url.isEmpty ? null : url;
  }

  /// 解析 `background-image` 的渐变（W2）。
  ///
  /// 支持 `linear-gradient()` 与 `radial-gradient()`（含 `to <side|corner>`、
  /// 角度单位、`circle/ellipse [at <position>]`、`<color> [<percentage>]` 色标）。
  /// 不支持 repeating-*/conic/多背景层/像素位置色标——返回 null 或按均分处理
  /// （见各类型注释）。
  static CssGradient? _parseGradient(String? raw, {double fontSize = 16}) {
    if (raw == null) {
      return null;
    }
    final match = RegExp(
      r'^(repeating-)?(linear|radial)-gradient\((.*)\)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(raw.trim());
    if (match == null) {
      return null;
    }
    final repeating = match.group(1) != null;
    final kind = match.group(2)!.toLowerCase();
    final parts = _splitTopLevel(match.group(3)!, ',');
    // 多背景层（`linear-gradient(...), linear-gradient(...)`）不支持：只要
    // 顶层分组里还出现 gradient( 就放弃，避免把两层拼成一层画错。
    if (parts.any((part) => part.toLowerCase().contains('-gradient('))) {
      return null;
    }
    if (parts.length < 2) {
      return null;
    }
    // 首个参数若是颜色就是色标，否则是方向/形状前置参数。
    final stops = <CssGradientStop>[];
    var prelude = '';
    final firstStops = _parseGradientStops(parts.first, fontSize: fontSize);
    if (firstStops.isEmpty) {
      prelude = parts.first;
    } else {
      stops.addAll(firstStops);
    }
    for (var index = 1; index < parts.length; index++) {
      stops.addAll(_parseGradientStops(parts[index], fontSize: fontSize));
    }
    if (stops.length < 2) {
      return null;
    }
    if (kind == 'linear') {
      return CssLinearGradient(
        angle: _parseGradientAngle(prelude),
        repeating: repeating,
        stops: stops,
      );
    }
    final radial = _parseRadialPrelude(prelude, fontSize: fontSize);
    return CssRadialGradient(
      stops: stops,
      repeating: repeating,
      shape: radial.shape,
      centerX: radial.x,
      centerY: radial.y,
    );
  }

  /// 解析一个色标段 → 0~2 个 [CssGradientStop]。
  ///
  /// 支持 `<color> [<start> [<end>]]`：给了两个位置时按 CSS 语义展开成
  /// **同色的两个色标**（区间色标），第二个位置小于第一个时钳到第一个。
  /// 百分比存 [CssGradientStop.position]（0–1）；像素/em 存
  /// [CssGradientStop.positionPx]，绘制层用 `fractionOf(extent)` 换算。
  static List<CssGradientStop> _parseGradientStops(
    String raw, {
    double fontSize = 16,
  }) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const <CssGradientStop>[];
    }
    final color = _firstColorIn(text);
    if (color == null) {
      return const <CssGradientStop>[];
    }
    // 位置：先去掉颜色函数（其内部可能含 `100%`）与色值 token，再按顺序
    // 收集最多两个位置（百分比或长度）。
    final withoutColor = text
        .replaceAll(
          RegExp(r'(?:rgba?|hsla?)\([^)]*\)', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'#[0-9a-fA-F]+'), ' ');
    // 位置按出现顺序收集（最多两个），每个位置各自保留量纲：`0` 这类
    // 无单位零按长度解析，`50%` 按百分比，绘制层都能换算。
    final positions = <CssGradientStop>[];
    for (final token in withoutColor.split(RegExp(r'\s+'))) {
      if (token.isEmpty || token == 'transparent') {
        continue;
      }
      final percent = _parsePercent(token);
      if (percent != null) {
        if (positions.length < 2) {
          positions.add(CssGradientStop(color: color, position: percent / 100));
        }
        continue;
      }
      final value = _resolveLength(
        token,
        fontSize: fontSize,
        parentFontSize: fontSize,
        rootFontSize: 16,
        percentBase: 0,
      );
      if (value != null && positions.length < 2) {
        positions.add(CssGradientStop(color: color, positionPx: value));
      }
    }
    if (positions.isEmpty) {
      return <CssGradientStop>[CssGradientStop(color: color)];
    }
    if (positions.length == 1) {
      return positions;
    }
    // 区间色标：第二个位置小于第一个时按 CSS 语义钳到第一个（区间宽 0）。
    // 跨量纲（一个百分比一个长度）无法在解析期比较，保持原样交给绘制层。
    final first = positions[0];
    var second = positions[1];
    if (first.position != null &&
        second.position != null &&
        second.position! < first.position!) {
      second = CssGradientStop(color: color, position: first.position);
    } else if (first.positionPx != null &&
        second.positionPx != null &&
        second.positionPx! < first.positionPx!) {
      second = CssGradientStop(color: color, positionPx: first.positionPx);
    }
    return <CssGradientStop>[first, second];
  }

  /// 从一段声明里取首个颜色。
  ///
  /// `rgba(0, 0, 0, 0.5)` 内部含空格与逗号，不能按空白分词：先按颜色函数
  /// 整段匹配，再退回按空白切词找 `#hex`/`transparent`。
  static Color? _firstColorIn(String text) {
    final function = RegExp(
      r'(?:rgba?|hsla?)\([^)]*\)',
      caseSensitive: false,
    ).firstMatch(text);
    if (function != null) {
      final color = _parseColor(function.group(0)!);
      if (color != null) {
        return color;
      }
    }
    for (final token in text.split(RegExp(r'\s+'))) {
      if (token.isEmpty || token.contains('(')) {
        continue;
      }
      final color = _parseColor(token);
      if (color != null) {
        return color;
      }
    }
    return null;
  }

  /// 线性渐变方向 → CSS 角度（0 = 向上，顺时针；未声明默认 180）。
  static double _parseGradientAngle(String prelude) {
    final text = prelude.trim().toLowerCase();
    if (text.isEmpty) {
      return 180;
    }
    final angle = RegExp(r'^([-+]?\d*\.?\d+)(deg|grad|rad|turn)$')
        .firstMatch(text);
    if (angle != null) {
      final value = double.parse(angle.group(1)!);
      return switch (angle.group(2)) {
        'grad' => value * 0.9,
        'rad' => value * 180 / math.pi,
        'turn' => value * 360,
        _ => value,
      };
    }
    if (!text.startsWith('to ')) {
      return 180;
    }
    final sides = text.substring(3).split(RegExp(r'\s+')).toSet();
    final right = sides.contains('right');
    final left = sides.contains('left');
    final top = sides.contains('top');
    final bottom = sides.contains('bottom');
    if (top && right) {
      return 45;
    }
    if (top && left) {
      return 315;
    }
    if (bottom && right) {
      return 135;
    }
    if (bottom && left) {
      return 225;
    }
    if (right) {
      return 90;
    }
    if (left) {
      return 270;
    }
    return top ? 0 : 180;
  }

  /// 径向渐变前置参数：`[circle|ellipse] [at <position>]`。
  static ({CssRadialShape shape, CssLength x, CssLength y}) _parseRadialPrelude(
    String prelude, {
    required double fontSize,
  }) {
    var shape = CssRadialShape.ellipse;
    var x = const CssLength(50, isPercent: true);
    var y = const CssLength(50, isPercent: true);
    final text = prelude.trim().toLowerCase();
    if (text.isEmpty) {
      return (shape: shape, x: x, y: y);
    }
    final tokens = text.split(RegExp(r'\s+'));
    final at = tokens.indexOf('at');
    final head = at >= 0 ? tokens.sublist(0, at) : tokens;
    if (head.contains('circle')) {
      shape = CssRadialShape.circle;
    }
    if (at < 0) {
      return (shape: shape, x: x, y: y);
    }
    final positionTokens = tokens.sublist(at + 1);
    CssLength? positionOf(String token) => switch (token) {
      'left' || 'top' => const CssLength(0, isPercent: true),
      'center' => const CssLength(50, isPercent: true),
      'right' || 'bottom' => const CssLength(100, isPercent: true),
      _ => _gradientPositionLength(token, fontSize: fontSize),
    };
    final parsed = <CssLength>[];
    for (final token in positionTokens) {
      final value = positionOf(token);
      if (value != null) {
        parsed.add(value);
      }
    }
    if (parsed.isEmpty) {
      return (shape: shape, x: x, y: y);
    }
    if (parsed.length == 1) {
      if (positionTokens.first == 'top' || positionTokens.first == 'bottom') {
        y = parsed.first;
      } else {
        x = parsed.first;
      }
    } else {
      x = parsed[0];
      y = parsed[1];
    }
    return (shape: shape, x: x, y: y);
  }

  /// 渐变位置里的长度：百分比保留比例，像素/em 直接解算。
  static CssLength? _gradientPositionLength(
    String token, {
    required double fontSize,
  }) {
    final percent = _parsePercent(token);
    if (percent != null) {
      return CssLength(percent, isPercent: true);
    }
    final resolved = _resolveLength(
      token,
      fontSize: fontSize,
      parentFontSize: fontSize,
      rootFontSize: 16,
      percentBase: 0,
    );
    return resolved == null ? null : CssLength(resolved);
  }

  /// 取首个 `linear-gradient(...)` / `radial-gradient(...)` 原文（配对括号）。
  ///
  /// 供 `background` 简写使用：正则 `[^)]*` 会被色标里的 `rgba(...)` 截断。
  static String? _firstGradientFunction(String text) {
    final match = RegExp(
      r'(?:repeating-)?(?:-[a-z]+-)?(?:linear|radial)-gradient\(',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) {
      return null;
    }
    var depth = 0;
    for (var i = match.end - 1; i < text.length; i++) {
      final char = text[i];
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        depth -= 1;
        if (depth == 0) {
          return text.substring(match.start, i + 1);
        }
      }
    }
    return null;
  }

  /// 按顶层分隔符切分：括号内的分隔符不切（`rgba(...)`、嵌套函数）。
  static List<String> _splitTopLevel(String text, String separator) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        depth -= 1;
      } else if (depth == 0 && char == separator) {
        parts.add(text.substring(start, i).trim());
        start = i + 1;
      }
    }
    parts.add(text.substring(start).trim());
    return parts;
  }

  /// 解析 `filter`（W5）：返回**有序**滤镜列表，`none`/空 → 空列表。
  ///
  /// 支持 blur/grayscale/sepia/brightness/contrast/saturate/hue-rotate/
  /// invert/opacity/drop-shadow；`url(...)` 等 SVG 引用与未知函数跳过。
  static List<CssFilter> _parseFilters(
    String? raw, {
    required double fontSize,
    required double rootFontSize,
  }) {
    if (raw == null) {
      return const <CssFilter>[];
    }
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value == 'none') {
      return const <CssFilter>[];
    }
    final filters = <CssFilter>[];
    var index = 0;
    while (index < value.length) {
      final open = value.indexOf('(', index);
      if (open < 0) {
        break;
      }
      // 函数名：从 '(' 往前取 a-z 与 '-'（hue-rotate / drop-shadow）。
      var nameStart = open;
      while (nameStart > index) {
        final code = value.codeUnitAt(nameStart - 1);
        if (!((code >= 97 && code <= 122) || code == 45)) {
          break;
        }
        nameStart -= 1;
      }
      final name = value.substring(nameStart, open).trim();
      // 配对括号（drop-shadow 的 rgba(...) 是嵌套的）。
      var depth = 0;
      var close = -1;
      for (var i = open; i < value.length; i++) {
        final char = value[i];
        if (char == '(') {
          depth += 1;
        } else if (char == ')') {
          depth -= 1;
          if (depth == 0) {
            close = i;
            break;
          }
        }
      }
      if (close < 0) {
        break;
      }
      final filter = _parseFilterFunction(
        name,
        value.substring(open + 1, close).trim(),
        fontSize: fontSize,
        rootFontSize: rootFontSize,
      );
      if (filter != null) {
        filters.add(filter);
      }
      index = close + 1;
    }
    return filters;
  }

  /// 单个滤镜函数 → [CssFilter]；未知/不支持的函数返回 null。
  static CssFilter? _parseFilterFunction(
    String name,
    String args, {
    required double fontSize,
    required double rootFontSize,
  }) {
    final kind = switch (name) {
      'blur' => CssFilterKind.blur,
      'grayscale' => CssFilterKind.grayscale,
      'sepia' => CssFilterKind.sepia,
      'brightness' => CssFilterKind.brightness,
      'contrast' => CssFilterKind.contrast,
      'saturate' => CssFilterKind.saturate,
      'hue-rotate' => CssFilterKind.hueRotate,
      'invert' => CssFilterKind.invert,
      'opacity' => CssFilterKind.opacity,
      'drop-shadow' => CssFilterKind.dropShadow,
      _ => null,
    };
    if (kind == null) {
      return null;
    }
    if (kind == CssFilterKind.dropShadow) {
      final shadow = _parseDropShadow(
        args,
        fontSize: fontSize,
        rootFontSize: rootFontSize,
      );
      return shadow == null ? null : CssFilter(kind: kind, shadow: shadow);
    }
    if (kind == CssFilterKind.blur) {
      final radius = args.isEmpty
          ? 0.0
          : (_resolveLength(
                  args,
                  fontSize: fontSize,
                  parentFontSize: fontSize,
                  rootFontSize: rootFontSize,
                  percentBase: 0,
                ) ??
                0.0);
      return CssFilter(kind: kind, amount: math.max(0, radius));
    }
    if (kind == CssFilterKind.hueRotate) {
      return CssFilter(
        kind: kind,
        amount: args.isEmpty ? 0 : (_parseAngleDegrees(args) ?? 0),
      );
    }
    // 其余：grayscale/sepia/invert/opacity 与 brightness/contrast/saturate
    // 缺省都是 1（CSS 规范），百分比按 /100 归一。
    return CssFilter(kind: kind, amount: _filterAmount(args, fallback: 1));
  }

  /// 滤镜数值参数：`50%` → 0.5，纯数字原样，缺省取 [fallback]。
  static double _filterAmount(String args, {required double fallback}) {
    final text = args.trim();
    if (text.isEmpty) {
      return fallback;
    }
    final percent = _parsePercent(text);
    if (percent != null) {
      return percent / 100;
    }
    return double.tryParse(text) ?? fallback;
  }

  /// 角度参数 → 度（deg/grad/rad/turn）。
  static double? _parseAngleDegrees(String raw) {
    final match = RegExp(r'^([-+]?\d*\.?\d+)(deg|grad|rad|turn)?$')
        .firstMatch(raw.trim());
    if (match == null) {
      return null;
    }
    final value = double.parse(match.group(1)!);
    return switch (match.group(2)) {
      'grad' => value * 0.9,
      'rad' => value * 180 / math.pi,
      'turn' => value * 360,
      _ => value,
    };
  }

  /// `drop-shadow(<offset-x> <offset-y> [<blur>] [<color>])` 解析。
  static CssDropShadow? _parseDropShadow(
    String args, {
    required double fontSize,
    required double rootFontSize,
  }) {
    final color = _firstColorIn(args);
    final rest = args.replaceAll(
      RegExp(r'(?:rgba?|hsla?)\([^)]*\)', caseSensitive: false),
      ' ',
    );
    final lengths = <double>[];
    for (final token in rest.split(RegExp(r'\s+'))) {
      if (token.isEmpty || token.startsWith('#') || token == 'transparent') {
        continue;
      }
      if (lengths.length >= 3) {
        continue;
      }
      final value = _resolveLength(
        token,
        fontSize: fontSize,
        parentFontSize: fontSize,
        rootFontSize: rootFontSize,
        percentBase: 0,
      );
      if (value != null) {
        lengths.add(value);
      }
    }
    if (lengths.length < 2) {
      return null;
    }
    return CssDropShadow(
      offsetX: lengths[0],
      offsetY: lengths[1],
      blur: lengths.length > 2 ? math.max(0, lengths[2]) : 0,
      color: color ?? const Color(0xFF000000),
    );
  }

  /// 解析 `transform`（W11）：返回**有序**变换列表，`none`/空 → 空列表。
  ///
  /// 支持 translate/translateX/translateY、scale/scaleX/scaleY、rotate、
  /// matrix、skew/skewX/skewY；`translate3d`/`perspective` 等未支持函数跳过。
  static List<CssTransform> _parseTransforms(
    String? raw, {
    required double fontSize,
  }) {
    if (raw == null) {
      return const <CssTransform>[];
    }
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value == 'none') {
      return const <CssTransform>[];
    }
    final transforms = <CssTransform>[];
    var index = 0;
    while (index < value.length) {
      final open = value.indexOf('(', index);
      if (open < 0) {
        break;
      }
      var nameStart = open;
      while (nameStart > index) {
        final code = value.codeUnitAt(nameStart - 1);
        if (!((code >= 97 && code <= 122) || code == 45)) {
          break;
        }
        nameStart -= 1;
      }
      final name = value.substring(nameStart, open).trim();
      var depth = 0;
      var close = -1;
      for (var i = open; i < value.length; i++) {
        final char = value[i];
        if (char == '(') {
          depth += 1;
        } else if (char == ')') {
          depth -= 1;
          if (depth == 0) {
            close = i;
            break;
          }
        }
      }
      if (close < 0) {
        break;
      }
      final transform = _parseTransformFunction(
        name,
        value.substring(open + 1, close),
        fontSize: fontSize,
      );
      if (transform != null) {
        transforms.add(transform);
      }
      index = close + 1;
    }
    return transforms;
  }

  /// 单个 transform 函数 → [CssTransform]；未知函数返回 null。
  static CssTransform? _parseTransformFunction(
    String name,
    String args, {
    required double fontSize,
  }) {
    final parts = _transformArgs(args);
    switch (name) {
      case 'translate':
        return CssTransform(
          kind: CssTransformKind.translate,
          x: _transformLength(parts, 0, fontSize) ?? const CssLength(0),
          y: _transformLength(parts, 1, fontSize) ?? const CssLength(0),
        );
      case 'translatex':
        return CssTransform(
          kind: CssTransformKind.translate,
          x: _transformLength(parts, 0, fontSize) ?? const CssLength(0),
          y: const CssLength(0),
        );
      case 'translatey':
        return CssTransform(
          kind: CssTransformKind.translate,
          x: const CssLength(0),
          y: _transformLength(parts, 0, fontSize) ?? const CssLength(0),
        );
      case 'scale':
        return CssTransform(
          kind: CssTransformKind.scale,
          sx: _transformNumber(parts, 0) ?? 1,
          sy: _transformNumber(parts, 1),
        );
      case 'scalex':
        return CssTransform(
          kind: CssTransformKind.scale,
          sx: _transformNumber(parts, 0) ?? 1,
          sy: 1,
        );
      case 'scaley':
        return CssTransform(
          kind: CssTransformKind.scale,
          sx: 1,
          sy: _transformNumber(parts, 0) ?? 1,
        );
      case 'rotate':
        return CssTransform(
          kind: CssTransformKind.rotate,
          angleDeg: parts.isEmpty ? 0 : (_parseAngleDegrees(parts.first) ?? 0),
        );
      case 'skew':
        return CssTransform(
          kind: CssTransformKind.skew,
          axDeg: parts.isEmpty ? 0 : (_parseAngleDegrees(parts[0]) ?? 0),
          ayDeg: parts.length > 1 ? (_parseAngleDegrees(parts[1]) ?? 0) : 0,
        );
      case 'skewx':
        return CssTransform(
          kind: CssTransformKind.skew,
          axDeg: parts.isEmpty ? 0 : (_parseAngleDegrees(parts.first) ?? 0),
          ayDeg: 0,
        );
      case 'skewy':
        return CssTransform(
          kind: CssTransformKind.skew,
          axDeg: 0,
          ayDeg: parts.isEmpty ? 0 : (_parseAngleDegrees(parts.first) ?? 0),
        );
      case 'matrix':
        final values = <double>[
          for (final part in parts) double.tryParse(part) ?? 0,
        ];
        if (values.length < 6) {
          return null;
        }
        return CssTransform(
          kind: CssTransformKind.matrix,
          values: values.sublist(0, 6),
        );
      default:
        return null;
    }
  }

  /// `transform-origin`：两个位置（默认 50% / 50%）。
  ///
  /// 单值 `top`/`bottom` 只改纵轴（横轴取 center），其余单值改横轴；
  /// 第三个值（z 轴）忽略。百分比保留标记，基准 = 边框盒宽（x）/高（y）。
  static ({CssLength x, CssLength y}) _parseTransformOrigin(
    String? raw, {
    required double fontSize,
  }) {
    const center = CssLength(50, isPercent: true);
    if (raw == null) {
      return (x: center, y: center);
    }
    final tokens = raw
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      return (x: center, y: center);
    }
    CssLength? lengthOf(String token) {
      if (token == 'left' || token == 'top') {
        return const CssLength(0, isPercent: true);
      }
      if (token == 'right' || token == 'bottom') {
        return const CssLength(100, isPercent: true);
      }
      if (token == 'center') {
        return center;
      }
      final percent = _parsePercent(token);
      if (percent != null) {
        return CssLength(percent, isPercent: true);
      }
      final value = _resolveLength(
        token,
        fontSize: fontSize,
        parentFontSize: fontSize,
        rootFontSize: 16,
        percentBase: 0,
      );
      return value == null ? null : CssLength(value);
    }

    if (tokens.length == 1) {
      final token = tokens.first;
      final length = lengthOf(token) ?? center;
      final verticalOnly = token == 'top' || token == 'bottom';
      return verticalOnly ? (x: center, y: length) : (x: length, y: center);
    }
    return (x: lengthOf(tokens[0]) ?? center, y: lengthOf(tokens[1]) ?? center);
  }

  /// transform 参数：优先按逗号切分，单参数形式再按空白切（`translate(10px 20px)`）。
  static List<String> _transformArgs(String raw) {
    final byComma = _splitTopLevel(
      raw,
      ',',
    ).where((part) => part.isNotEmpty).toList();
    if (byComma.length > 1) {
      return byComma;
    }
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  /// transform 的长度参数：px/em 转像素，百分比保留标记（绘制层按盒宽/高解算）。
  static CssLength? _transformLength(
    List<String> parts,
    int index,
    double fontSize,
  ) {
    if (index >= parts.length) {
      return null;
    }
    final token = parts[index];
    final percent = _parsePercent(token);
    if (percent != null) {
      return CssLength(percent, isPercent: true);
    }
    final value = _resolveLength(
      token,
      fontSize: fontSize,
      parentFontSize: fontSize,
      rootFontSize: 16,
      percentBase: 0,
    );
    return value == null ? null : CssLength(value);
  }

  /// transform 的倍数参数（scale）：`50%` → 0.5，纯数字原样。
  static double? _transformNumber(List<String> parts, int index) {
    if (index >= parts.length) {
      return null;
    }
    final token = parts[index].trim();
    final percent = _parsePercent(token);
    if (percent != null) {
      return percent / 100;
    }
    return double.tryParse(token);
  }

  /// 书写模式：含 CSS2 旧值（`tb-rl`/`lr-tb`）与简写（`rl`/`lr`）。
  static CssWritingMode? _parseWritingMode(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'horizontal-tb' || 'lr-tb' || 'lr' || 'rl' => CssWritingMode.horizontalTb,
      'vertical-rl' || 'tb-rl' => CssWritingMode.verticalRl,
      'vertical-lr' || 'tb-lr' => CssWritingMode.verticalLr,
      _ => null,
    };
  }

  /// 竖排字向：`sideways-right` 等旧写法归到 sideways。
  static CssTextOrientation? _parseTextOrientation(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'mixed' => CssTextOrientation.mixed,
      'upright' => CssTextOrientation.upright,
      'sideways' ||
      'sideways-right' ||
      'sideways-left' => CssTextOrientation.sideways,
      _ => null,
    };
  }

  /// 文本方向。
  static CssDirection? _parseDirection(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'ltr' => CssDirection.ltr,
      'rtl' => CssDirection.rtl,
      _ => null,
    };
  }

  /// `overflow`：取第一个值（`overflow: hidden auto` 这类两轴写法只支持首值）。
  static CssOverflow _parseOverflow(String raw) {
    for (final token in raw.trim().toLowerCase().split(RegExp(r'\s+'))) {
      switch (token) {
        case 'hidden':
          return CssOverflow.hidden;
        case 'clip':
          return CssOverflow.clip;
        case 'auto':
          return CssOverflow.auto;
        case 'scroll':
          return CssOverflow.scroll;
        case 'visible':
          return CssOverflow.visible;
      }
    }
    return CssOverflow.visible;
  }

  /// `hyphens`。
  static CssHyphens? _parseHyphens(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'none' => CssHyphens.none,
      'manual' => CssHyphens.manual,
      'auto' => CssHyphens.auto,
      _ => null,
    };
  }

  /// `word-break`。
  static CssWordBreak? _parseWordBreak(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'normal' => CssWordBreak.normal,
      'break-all' => CssWordBreak.breakAll,
      'keep-all' => CssWordBreak.keepAll,
      _ => null,
    };
  }

  /// `overflow-wrap`（含旧名 `word-wrap` 的取值）。
  static CssOverflowWrap? _parseOverflowWrap(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'normal' => CssOverflowWrap.normal,
      'break-word' => CssOverflowWrap.breakWord,
      'anywhere' => CssOverflowWrap.anywhere,
      _ => null,
    };
  }

  /// `font-variant` / `font-variant-caps`：取 caps 关键字（数值变体忽略）。
  static CssFontVariantCaps? _parseFontVariantCaps(String raw) {
    for (final token in raw.trim().toLowerCase().split(RegExp(r'\s+'))) {
      switch (token) {
        case 'normal':
          return CssFontVariantCaps.normal;
        case 'small-caps':
          return CssFontVariantCaps.smallCaps;
        case 'all-small-caps':
          return CssFontVariantCaps.allSmallCaps;
        case 'petite-caps':
          return CssFontVariantCaps.petiteCaps;
        case 'all-petite-caps':
          return CssFontVariantCaps.allPetiteCaps;
        case 'unicase':
          return CssFontVariantCaps.unicase;
        case 'titling-caps':
          return CssFontVariantCaps.titlingCaps;
      }
    }
    return null;
  }

  /// `font-variant-ligatures`：阅读场景只需区分是否关闭常用连字。
  static CssFontVariantLigatures? _parseFontVariantLigatures(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'normal' || 'common-ligatures' => CssFontVariantLigatures.normal,
      'none' || 'no-common-ligatures' => CssFontVariantLigatures.none,
      _ => null,
    };
  }

  /// `font-stretch`：关键字或百分比 → 百分比数值（50–200），非法返回 null。
  static double? _parseFontStretch(String raw) {
    final token = raw.trim().toLowerCase();
    if (token == 'normal') {
      return 100;
    }
    final keyword = _fontStretchKeywords[token];
    if (keyword != null) {
      return double.parse(keyword.replaceAll('%', ''));
    }
    final percent = _parsePercent(token);
    if (percent != null && percent >= 50 && percent <= 200) {
      return percent;
    }
    return null;
  }

  /// `quotes`：`auto` / `none` / 引号对序列（奇数个字符串或解析失败返回 null）。
  static CssQuotes? _parseQuotes(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    final lower = value.toLowerCase();
    if (lower == 'auto') {
      return const CssQuotesAuto();
    }
    if (lower == 'none') {
      return const CssQuotesNone();
    }
    // 手写扫描：CSS 字符串可用 " 或 ' 包裹，内部 \\ 转义不解包。
    final strings = <String>[];
    final buffer = StringBuffer();
    String? quote;
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (quote == null) {
        if (char == '"' || char == "'") {
          quote = char;
          buffer.clear();
        }
        continue;
      }
      if (char == '\\' && i + 1 < value.length) {
        buffer
          ..write(char)
          ..write(value[i + 1]);
        i += 1;
        continue;
      }
      if (char == quote) {
        strings.add(_unescapeCssString(buffer.toString()));
        quote = null;
        continue;
      }
      buffer.write(char);
    }
    if (strings.isEmpty || strings.length.isOdd) {
      return null;
    }
    return CssQuotesPairs(<CssQuotePair>[
      for (var i = 0; i < strings.length; i += 2)
        CssQuotePair(open: strings[i], close: strings[i + 1]),
    ]);
  }

  /// CSS 字符串转义（`\"`、`\\`、`\A` 换行等的最小实现）。
  static String _unescapeCssString(String raw) {
    final buffer = StringBuffer();
    final hex = RegExp(r'[0-9a-fA-F]');
    for (var i = 0; i < raw.length; i++) {
      final char = raw[i];
      if (char != '\\' || i + 1 >= raw.length) {
        buffer.write(char);
        continue;
      }
      // CSS 转义：`\\HHHHHH`（1–6 位十六进制，可跟一个空白终止符），
      // 或单字符转义（`\\'`、`\\\\` 等）。
      var j = i + 1;
      final start = j;
      while (j < raw.length && j - start < 6 && hex.hasMatch(raw[j])) {
        j += 1;
      }
      if (j > start) {
        buffer.writeCharCode(int.parse(raw.substring(start, j), radix: 16));
        if (j < raw.length && (raw[j] == ' ' || raw[j] == '\t')) {
          j += 1;
        }
        i = j - 1;
        continue;
      }
      buffer.write(raw[i + 1]);
      i += 1;
    }
    return buffer.toString();
  }

  /// 多列布局（`columns` 系列，W11）：count/width/gap/rule。
  ///
  /// `columns` 简写在本层展开（`columns: 3 60px`），整数值归 count、
  /// 长度值归 width，与级联层无关（直接构造 ComputedStyle 也能吃到）。
  static ({int? count, CssLength? width, double? gap, CssBorderSide? rule})
  _resolveColumns(
    Map<String, String> values,
    Set<String> explicit, {
    required double fontSize,
    required double rootFontSize,
    required Color color,
  }) {
    String? value(String property) =>
        explicit.contains(property) ? values[property] : null;

    var count = _parseColumnCount(value('column-count'));
    var width = _parseColumnWidth(
      value('column-width'),
      fontSize: fontSize,
      rootFontSize: rootFontSize,
    );
    final shorthand = value('columns');
    if (shorthand != null) {
      for (final token in shorthand.trim().split(RegExp(r'\s+'))) {
        if (token.isEmpty || token.toLowerCase() == 'auto') {
          continue;
        }
        final parsedCount = _parseColumnCount(token);
        if (parsedCount != null) {
          count ??= parsedCount;
          continue;
        }
        width ??= _parseColumnWidth(
          token,
          fontSize: fontSize,
          rootFontSize: rootFontSize,
        );
      }
    }
    return (
      count: count,
      width: width,
      gap: _parseColumnGap(
        value('column-gap'),
        fontSize: fontSize,
        rootFontSize: rootFontSize,
      ),
      rule: _parseColumnRule(
        value('column-rule'),
        fontSize: fontSize,
        rootFontSize: rootFontSize,
        color: color,
      ),
    );
  }

  /// `column-count`：正整数；`auto` 或非法值返回 null。
  static int? _parseColumnCount(String? raw) {
    if (raw == null) {
      return null;
    }
    final value = int.tryParse(raw.trim());
    return value == null || value < 1 ? null : value;
  }

  /// `column-width`：长度（px/em）；`auto` 返回 null。
  static CssLength? _parseColumnWidth(
    String? raw, {
    required double fontSize,
    required double rootFontSize,
  }) {
    if (raw == null) {
      return null;
    }
    final token = raw.trim().toLowerCase();
    if (token.isEmpty || token == 'auto' || token == 'normal') {
      return null;
    }
    final percent = _parsePercent(token);
    if (percent != null) {
      return CssLength(percent, isPercent: true);
    }
    final value = _resolveLength(
      token,
      fontSize: fontSize,
      parentFontSize: fontSize,
      rootFontSize: rootFontSize,
      percentBase: 0,
    );
    return value == null ? null : CssLength(value);
  }

  /// `column-gap`：像素值；`normal`/auto 返回 null（由布局层按 1em 处理）。
  static double? _parseColumnGap(
    String? raw, {
    required double fontSize,
    required double rootFontSize,
  }) {
    if (raw == null) {
      return null;
    }
    final token = raw.trim().toLowerCase();
    if (token.isEmpty || token == 'normal' || token == 'auto') {
      return null;
    }
    return _resolveLength(
      token,
      fontSize: fontSize,
      parentFontSize: fontSize,
      rootFontSize: rootFontSize,
      percentBase: 0,
    );
  }

  /// `column-rule` 简写（`1px solid #999`）→ 复用 [CssBorderSide]。
  static CssBorderSide? _parseColumnRule(
    String? raw, {
    required double fontSize,
    required double rootFontSize,
    required Color color,
  }) {
    if (raw == null) {
      return null;
    }
    var width = 0.0;
    var style = CssBorderStyle.none;
    var ruleColor = color;
    var sawToken = false;
    for (final token in raw.trim().split(RegExp(r'\s+'))) {
      if (token.isEmpty) {
        continue;
      }
      final parsedStyle = _parseBorderStyle(token);
      if (parsedStyle != null) {
        style = parsedStyle;
        sawToken = true;
        continue;
      }
      final parsedColor = _parseColor(token);
      if (parsedColor != null) {
        ruleColor = parsedColor;
        sawToken = true;
        continue;
      }
      final parsedWidth = _resolveLength(
        token,
        fontSize: fontSize,
        parentFontSize: fontSize,
        rootFontSize: rootFontSize,
        percentBase: 0,
      );
      if (parsedWidth != null && RegExp(r'^[+-]?[\d.]').hasMatch(token)) {
        width = parsedWidth;
        sawToken = true;
      }
    }
    if (!sawToken) {
      return null;
    }
    // 与 border 一致：`none` 时宽度归零（Chrome 语义）。
    return CssBorderSide(
      width: style == CssBorderStyle.none ? 0 : width,
      style: style,
      color: ruleColor,
    );
  }

  /// 解析多看 `duokan-bleed`（P9-22）：auto/none 无出血，all 四边；
  /// 多看常把方向连写（`lefttopright`），因此按子串判断而不是分词。
  static CssBleed _parseBleed(String? raw) {
    if (raw == null) {
      return CssBleed.none;
    }
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value == 'none' || value == 'auto') {
      return CssBleed.none;
    }
    final all = value.contains('all') || value.contains('both');
    return CssBleed(
      left: all || value.contains('left'),
      right: all || value.contains('right'),
      top: all || value.contains('top'),
      bottom: all || value.contains('bottom'),
    );
  }

  /// 解析 `table-layout`（P9-17）。
  static CssTableLayout? _parseTableLayout(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'fixed' => CssTableLayout.fixed,
        'auto' => CssTableLayout.auto,
        _ => null,
      };

  static const Map<String, CssListStyleType> _listStyleTypes =
      <String, CssListStyleType>{
        'disc': CssListStyleType.disc,
        'circle': CssListStyleType.circle,
        'square': CssListStyleType.square,
        'decimal': CssListStyleType.decimal,
        'decimal-leading-zero': CssListStyleType.decimal,
        'lower-roman': CssListStyleType.lowerRoman,
        'upper-roman': CssListStyleType.upperRoman,
        'lower-alpha': CssListStyleType.lowerAlpha,
        'lower-latin': CssListStyleType.lowerAlpha,
        'upper-alpha': CssListStyleType.upperAlpha,
        'upper-latin': CssListStyleType.upperAlpha,
        'none': CssListStyleType.none,
      };

  /// 解析 `list-style-type` / `list-style`（P9-12）；未知类型返回 null。
  static CssListStyleType? _parseListStyleType(String raw) =>
      parseListStyleTypeKeyword(raw)?.$1;

  /// 从 `list-style` 简写里取出类型关键字（层叠层展开简写用）。
  static (CssListStyleType, String)? parseListStyleTypeKeyword(String raw) {
    for (final token in raw.toLowerCase().split(RegExp(r'\s+'))) {
      final type = _listStyleTypes[token];
      if (type != null) {
        return (type, token);
      }
    }
    return null;
  }

  /// 解析 `list-style-position`；未知值返回 null（调用方按 outside 兜底）。
  static CssListStylePosition? _parseListStylePosition(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'inside' => CssListStylePosition.inside,
        'outside' => CssListStylePosition.outside,
        _ => null,
      };

  /// 从 `list-style` 简写里取出 inside/outside 关键字（层叠层展开用）。
  static String? parseListStylePositionKeyword(String raw) {
    for (final token in raw.toLowerCase().split(RegExp(r'\s+'))) {
      if (token == 'inside' || token == 'outside') {
        return token;
      }
    }
    return null;
  }

  static final RegExp _backgroundLengthToken = RegExp(
    r'^[-+]?(\d*\.?\d+)(px|pt|pc|em|rem|%)?$',
  );

  static const _backgroundRepeatKeywords = <String>{
    'repeat',
    'repeat-x',
    'repeat-y',
    'no-repeat',
    'space',
    'round',
  };

  static const _backgroundPositionKeywords = <String>{
    'left',
    'right',
    'center',
    'top',
    'bottom',
  };

  /// 解析 `background` 简写（P9-11）：拆分出 image/color/repeat/
  /// position/size；attachment 与多背景暂不支持（取第一层）。渐变（W2）
  /// 原样放进 `background-image`，由 [_parseGradient] 结构化。
  static Map<String, String>? _parseBackgroundShorthand(String? raw) {
    if (raw == null) {
      return null;
    }
    final result = <String, String>{};
    final images = RegExp(
      r'url\([^)]*\)',
      caseSensitive: false,
    ).allMatches(raw).map((match) => match.group(0)!).toList();
    if (images.isNotEmpty) {
      result['background-image'] = images.first;
    }
    // 渐变：配对括号截取，避免色标里的 rgba(...) 把串截断；只有没有 url
    // 时才当作 image（一层背景只能有一个 image）。
    final gradient = _firstGradientFunction(raw);
    if (images.isEmpty && gradient != null) {
      result['background-image'] = gradient;
    }
    var rest = raw;
    for (final image in images) {
      rest = rest.replaceFirst(image, ' ');
    }
    if (gradient != null) {
      rest = rest.replaceFirst(gradient, ' ');
    }
    // 其余层/重复前缀残留的渐变片段统一清掉，避免污染 position/size 分词。
    rest = rest.replaceAll(
      RegExp(
        r'(?:repeating-)?(?:-[a-z]+-)?(?:linear|radial)-gradient\(',
        caseSensitive: false,
      ),
      ' ',
    );
    final tokens = rest
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    final positions = <String>[];
    final sizes = <String>[];
    var afterSlash = false;
    for (final token in tokens) {
      final lower = token.toLowerCase();
      if (lower == '/') {
        afterSlash = true;
        continue;
      }
      if (afterSlash) {
        sizes.add(token);
        continue;
      }
      if (_backgroundRepeatKeywords.contains(lower)) {
        result['background-repeat'] = lower;
        continue;
      }
      if (const <String>{'scroll', 'fixed', 'local'}.contains(lower)) {
        // background-attachment 无对应字段，静态分页下忽略。
        continue;
      }
      if (_backgroundPositionKeywords.contains(lower) ||
          _backgroundLengthToken.hasMatch(token)) {
        positions.add(token);
        continue;
      }
      if (_parseColor(token) != null) {
        result['background-color'] = token;
      }
    }
    if (positions.isNotEmpty) {
      result['background-position'] = positions.take(2).join(' ');
    }
    if (sizes.isNotEmpty) {
      result['background-size'] = sizes.join(' ');
    }
    return result.isEmpty ? null : result;
  }

  static CssEdges _resolveMargin(
    Map<String, String> values,
    Set<String> explicit, {
    required double fontSize,
    required double rootFontSize,
    required double containingWidth,
  }) {
    var top = 0.0;
    var right = 0.0;
    var bottom = 0.0;
    var left = 0.0;
    final shorthand = explicit.contains('margin') ? values['margin'] : null;
    if (shorthand != null) {
      final tokens = shorthand.trim().split(RegExp(r'\s+'));
      final resolved = <String>[for (final token in tokens.take(4)) token];
      if (resolved.isNotEmpty) {
        final lengths = <double>[
          for (final token in resolved)
            _marginValue(
              token,
              fontSize: fontSize,
              rootFontSize: rootFontSize,
              containingWidth: containingWidth,
            ),
        ];
        switch (lengths.length) {
          case 1:
            top = right = bottom = left = lengths[0];
          case 2:
            top = bottom = lengths[0];
            right = left = lengths[1];
          case 3:
            top = lengths[0];
            right = left = lengths[1];
            bottom = lengths[2];
          case 4:
            top = lengths[0];
            right = lengths[1];
            bottom = lengths[2];
            left = lengths[3];
        }
      }
    }
    double? override(String property) {
      if (!explicit.contains(property)) {
        return null;
      }
      final raw = values[property];
      return raw == null
          ? null
          : _marginValue(
              raw,
              fontSize: fontSize,
              rootFontSize: rootFontSize,
              containingWidth: containingWidth,
            );
    }

    top = override('margin-top') ?? top;
    right = override('margin-right') ?? right;
    bottom = override('margin-bottom') ?? bottom;
    left = override('margin-left') ?? left;
    return CssEdges(top: top, right: right, bottom: bottom, left: left);
  }

  static double _marginValue(
    String raw, {
    required double fontSize,
    required double rootFontSize,
    required double containingWidth,
  }) {
    final value = raw.trim().toLowerCase();
    if (value == 'auto') {
      return 0;
    }
    return _resolveLength(
          value,
          fontSize: fontSize,
          parentFontSize: fontSize,
          rootFontSize: rootFontSize,
          percentBase: containingWidth,
        ) ??
        0;
  }

  static double? _resolveLength(
    String raw, {
    required double fontSize,
    required double parentFontSize,
    required double rootFontSize,
    required double percentBase,
  }) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value == 'auto' || value == 'normal') {
      return null;
    }
    // calc()（P9-15）：书籍常用 `calc(100% - 2em)` 之类表达式，之前整条
    // 声明按非法长度丢弃。
    if (value.startsWith('calc(')) {
      return _evaluateCalc(
        value,
        fontSize: fontSize,
        rootFontSize: rootFontSize,
        percentBase: percentBase,
      );
    }
    final match = RegExp(
      r'^(-?(?:\d+(?:\.\d+)?|\.\d+))(px|pt|pc|in|cm|mm|em|rem|%)?$',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }
    final number = double.parse(match[1]!);
    return switch (match[2]) {
      null || 'px' => number,
      'pt' => number * 96 / 72,
      'pc' => number * 16,
      'in' => number * 96,
      'cm' => number * 96 / 2.54,
      'mm' => number * 96 / 25.4,
      'em' => number * fontSize,
      'rem' => number * rootFontSize,
      '%' => number * percentBase / 100,
      _ => null,
    };
  }

  static double? _parsePercent(String raw) {
    final value = raw.trim();
    if (!value.endsWith('%')) {
      return null;
    }
    return double.tryParse(value.substring(0, value.length - 1).trim());
  }

  /// 解析 `font-weight`（CSS Fonts 4 §2.2.1）。
  ///
  /// `bolder`/`lighter` 是**相对父级**的关键字，按 [parentWeight] 映射
  /// （根元素无父级时按初始值 400）：
  /// - bolder：<350→400、350–549→700、≥550→900
  /// - lighter：<550→100、550–749→400、≥750→700
  ///
  /// 阈值取规范映射表（100–900 每档）的中点，非整百字重（如 450）也落在
  /// 期望档位：规范表 bolder 400–500→700、lighter 600–700→400。
  static int? _parseFontWeight(String raw, {int parentWeight = 400}) {
    final value = raw.trim().toLowerCase();
    if (value == 'normal') {
      return 400;
    }
    if (value == 'bold') {
      return 700;
    }
    if (value == 'bolder') {
      return parentWeight < 350 ? 400 : (parentWeight < 550 ? 700 : 900);
    }
    if (value == 'lighter') {
      return parentWeight < 550 ? 100 : (parentWeight < 750 ? 400 : 700);
    }
    final parsed = int.tryParse(value);
    if (parsed == null) {
      return null;
    }
    return parsed.clamp(100, 900);
  }

  static bool _isItalic(String raw) {
    final value = raw.trim().toLowerCase();
    return value == 'italic' || value == 'oblique';
  }

  static CssTextAlign? _parseTextAlign(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'start' => CssTextAlign.start,
        'end' => CssTextAlign.end,
        'left' => CssTextAlign.left,
        'right' => CssTextAlign.right,
        'center' || '-webkit-center' => CssTextAlign.center,
        '-webkit-left' => CssTextAlign.left,
        '-webkit-right' => CssTextAlign.right,
        '-webkit-auto' || 'auto' => CssTextAlign.start,
        'justify' => CssTextAlign.justify,
        _ => null,
      };

  static CssPosition? _parsePosition(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'static' => CssPosition.static,
        'relative' => CssPosition.relative,
        'absolute' => CssPosition.absolute,
        'fixed' => CssPosition.fixed,
        'sticky' => CssPosition.sticky,
        _ => null,
      };

  static CssFloat? _parseFloat(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'none' => CssFloat.none,
        'left' || 'inline-start' => CssFloat.left,
        'right' || 'inline-end' => CssFloat.right,
        _ => null,
      };

  static CssVisibility? _parseVisibility(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'visible' => CssVisibility.visible,
        'hidden' => CssVisibility.hidden,
        'collapse' => CssVisibility.collapse,
        _ => null,
      };

  static CssWhiteSpace? _parseWhiteSpace(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'normal' => CssWhiteSpace.normal,
        'nowrap' => CssWhiteSpace.nowrap,
        'pre' => CssWhiteSpace.pre,
        'pre-wrap' || 'break-spaces' => CssWhiteSpace.preWrap,
        'pre-line' => CssWhiteSpace.preLine,
        _ => null,
      };

  static CssHangingPunctuation? _parseHangingPunctuation(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'allow-end' => CssHangingPunctuation.allowEnd,
        'none' => CssHangingPunctuation.none,
        // allow-start/force-end/force-start 等按 none 处理（一期语义）。
        _ => null,
      };

  /// 解析 `text-spacing-trim`（CSS Text 4）。
  ///
  /// 与 Chrome 对齐：`normal`（规范初始值）会折叠相邻全角标点，因此映射到
  /// [CssTextSpacingTrim.trimAdjacent]；只有显式 `space-all` 才不挤压。
  /// `space-first`/`trim-start`/`trim-both` 的行首半角细节本引擎未实现，
  /// 按 `normal` 的相邻折叠近似；`auto` 按规范等同 `normal`。
  static CssTextSpacingTrim? _parseTextSpacingTrim(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'trim-adjacent' ||
        'normal' ||
        'auto' ||
        'space-first' ||
        'trim-start' ||
        'trim-both' ||
        'trim-all' => CssTextSpacingTrim.trimAdjacent,
        // `space-all`：全部全角标点保持全角，即不挤压。
        'space-all' => CssTextSpacingTrim.normal,
        _ => null,
      };

  static CssTextAutospace? _parseTextAutospace(String raw) =>
      switch (raw.trim().toLowerCase()) {
        // 规范的 normal（初始值）含义为启用；本引擎未声明默认 none
        //（§38.2），书内显式 normal/ideograph-alpha 才启用。
        'normal' || 'ideograph-alpha' => CssTextAutospace.normal,
        'no-autospace' || 'none' => CssTextAutospace.none,
        _ => null,
      };

  static CssTextJustify? _parseTextJustify(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'auto' || 'normal' => CssTextJustify.auto,
        'inter-word' => CssTextJustify.interWord,
        'inter-character' => CssTextJustify.interCharacter,
        'distribute' => CssTextJustify.distribute,
        'justify-all' => CssTextJustify.justifyAll,
        // none/unsafe 等按 auto 处理（一期语义）。
        _ => null,
      };

  /// `initial-letter` 解析（P7-28；CSS Initial Letter）：`normal` → null；
  /// `<n>`（可带第二值，忽略）→ 跨行数 n。近似实现只消费首字放大，
  /// 多行对齐随浮动布局（P3）落地。
  static double? _parseInitialLetter(String raw) {
    final tokens = raw.trim().toLowerCase().split(RegExp(r'\s+'));
    if (tokens.isEmpty || tokens.first == 'normal') {
      return null;
    }
    return double.tryParse(tokens.first);
  }

  /// `text-overflow` 解析（P2-37）：ellipsis / clip，其余取值按 clip。
  static CssTextOverflow _parseTextOverflow(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'ellipsis' => CssTextOverflow.ellipsis,
        _ => CssTextOverflow.clip,
      };

  /// `box-shadow` 解析：`none` 或空 → null；否则解析「颜色 + 1~4 个长度」。
  ///
  /// 长度顺序按规范：offset-x offset-y [blur [spread]]；`inset` 可按规范
  /// 出现在首/尾。多阴影只取首个。
  static CssBoxShadow? _parseBoxShadow(
    String? raw, {
    required double fontSize,
  }) {
    if (raw == null) {
      return null;
    }
    final text = raw.trim().toLowerCase();
    if (text.isEmpty || text == 'none') {
      return null;
    }
    // 多阴影只取首个：先按顶层逗号分段（rgba(...) 内的逗号不切）。
    final first = _splitTopLevel(text, ',').first.trim();
    if (first.isEmpty) {
      return null;
    }
    // 颜色函数内部有空格与逗号，整段取色后再按空白分词量长度。
    final color = _firstColorIn(first);
    final rest = first.replaceAll(
      RegExp(r'(?:rgba?|hsla?)\([^)]*\)', caseSensitive: false),
      ' ',
    );
    final lengths = <double>[];
    var inset = false;
    for (final token in rest.split(RegExp(r'\s+'))) {
      if (token.isEmpty) {
        continue;
      }
      if (token == 'inset') {
        inset = true;
        continue;
      }
      if (token.startsWith('#') || token == 'transparent') {
        continue;
      }
      if (lengths.length >= 4) {
        continue;
      }
      final length = _resolveLength(
        token,
        fontSize: fontSize,
        parentFontSize: fontSize,
        rootFontSize: 16,
        percentBase: fontSize,
      );
      if (length != null) {
        lengths.add(length);
      }
    }
    if (lengths.length < 2) {
      return null;
    }
    return CssBoxShadow(
      offsetX: lengths[0],
      offsetY: lengths[1],
      color: color ?? const Color(0xFF000000),
      // blur 不允许负值（CSS 语义）。
      blur: lengths.length > 2 ? math.max(0, lengths[2]) : 0,
      spread: lengths.length > 3 ? lengths[3] : 0,
      inset: inset,
    );
  }

  static CssTextTransform? _parseTextTransform(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'none' => CssTextTransform.none,
        'uppercase' => CssTextTransform.uppercase,
        'lowercase' => CssTextTransform.lowercase,
        'capitalize' => CssTextTransform.capitalize,
        _ => null,
      };

  static List<CssTextShadow>? _parseTextShadows(
    String raw, {
    required double fontSize,
  }) {
    final value = raw.trim().toLowerCase();
    if (value == 'none') {
      return const <CssTextShadow>[];
    }
    final shadows = <CssTextShadow>[];
    for (final part in raw.split(',')) {
      final tokens = part.trim().split(RegExp(r'\s+'));
      var offsetX = 0.0;
      var offsetY = 0.0;
      var blur = 0.0;
      var lengthIndex = 0;
      Color? color;
      for (final token in tokens) {
        if (token.isEmpty) {
          continue;
        }
        final parsedColor = _parseColor(token);
        if (parsedColor != null) {
          color = parsedColor;
          continue;
        }
        final length = _resolveCssLength(
          token,
          fontSize: fontSize,
          rootFontSize: fontSize,
        );
        if (length == null || length.isPercent) {
          continue;
        }
        final px = length.resolve(0) ?? 0;
        switch (lengthIndex) {
          case 0:
            offsetX = px;
          case 1:
            offsetY = px;
          case 2:
            blur = px;
        }
        lengthIndex += 1;
      }
      if (lengthIndex == 0) {
        continue;
      }
      shadows.add(
        CssTextShadow(
          offsetX: offsetX,
          offsetY: offsetY,
          blur: blur,
          color: color,
        ),
      );
    }
    return shadows;
  }

  static CssBackgroundRepeat? _parseBackgroundRepeat(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'repeat' => CssBackgroundRepeat.repeat,
        'repeat-x' => CssBackgroundRepeat.repeatX,
        'repeat-y' => CssBackgroundRepeat.repeatY,
        'no-repeat' => CssBackgroundRepeat.noRepeat,
        _ => null,
      };

  static CssBackgroundSize? _parseBackgroundSize(
    String? raw, {
    required double fontSize,
    required double rootFontSize,
  }) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) {
      return null;
    }
    switch (value) {
      case 'cover':
        return const CssBackgroundSize.keyword(CssBackgroundSizeMode.cover);
      case 'contain':
        return const CssBackgroundSize.keyword(CssBackgroundSizeMode.contain);
    }
    final tokens = value.split(RegExp(r'\s+'));
    final width = _parseSizeToken(
      tokens.isNotEmpty ? tokens[0] : null,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
    );
    final height = _parseSizeToken(
      tokens.length > 1 ? tokens[1] : null,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
    );
    if (width == null && height == null) {
      return null;
    }
    return CssBackgroundSize.explicit(width: width, height: height);
  }

  static CssLength? _parseSizeToken(
    String? token, {
    required double fontSize,
    required double rootFontSize,
  }) {
    if (token == null || token.isEmpty) {
      return null;
    }
    if (token == 'auto') {
      return const CssLength.auto();
    }
    return _resolveCssLength(
      token,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
    );
  }

  static CssBackgroundPosition? _parseBackgroundPosition(
    String? raw, {
    required double fontSize,
    required double rootFontSize,
  }) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) {
      return null;
    }
    final tokens = value.split(RegExp(r'\s+'));
    CssLength parseOne(String token) {
      switch (token) {
        case 'left':
          return const CssLength(0, isPercent: true);
        case 'right':
          return const CssLength(100, isPercent: true);
        case 'top':
          return const CssLength(0, isPercent: true);
        case 'bottom':
          return const CssLength(100, isPercent: true);
        case 'center':
          return const CssLength(50, isPercent: true);
      }
      return _resolveCssLength(
            token,
            fontSize: fontSize,
            rootFontSize: rootFontSize,
          ) ??
          const CssLength(50, isPercent: true);
    }

    const center = CssLength(50, isPercent: true);
    if (tokens.length == 1) {
      final token = tokens.first;
      if (token == 'top' || token == 'bottom') {
        return CssBackgroundPosition(x: center, y: parseOne(token));
      }
      return CssBackgroundPosition(x: parseOne(token), y: center);
    }
    return CssBackgroundPosition(
      x: parseOne(tokens[0]),
      y: parseOne(tokens[1]),
    );
  }

  static CssBackgroundClip? _parseBackgroundClip(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'border-box' || 'border' => CssBackgroundClip.borderBox,
        'padding-box' || 'padding' => CssBackgroundClip.paddingBox,
        'content-box' || 'content' => CssBackgroundClip.contentBox,
        'text' => CssBackgroundClip.text,
        _ => null,
      };

  static CssBackgroundOrigin? _parseBackgroundOrigin(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'border-box' || 'border' => CssBackgroundOrigin.borderBox,
        'padding-box' || 'padding' => CssBackgroundOrigin.paddingBox,
        'content-box' || 'content' => CssBackgroundOrigin.contentBox,
        _ => null,
      };

  static CssClear? _parseClear(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'none' => CssClear.none,
        'left' => CssClear.left,
        'right' => CssClear.right,
        'both' => CssClear.both,
        _ => null,
      };

  static CssBorderCollapse? _parseBorderCollapse(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'separate' => CssBorderCollapse.separate,
        'collapse' => CssBorderCollapse.collapse,
        _ => null,
      };

  static CssEdges? _parseBorderSpacing(
    String raw, {
    required double fontSize,
    required double rootFontSize,
  }) {
    final tokens = raw.trim().toLowerCase().split(RegExp(r'\s+'));
    double? parse(String? token) {
      if (token == null || token.isEmpty) {
        return null;
      }
      final length = _resolveCssLength(
        token,
        fontSize: fontSize,
        rootFontSize: rootFontSize,
      );
      return length?.resolve(0);
    }

    final horizontal = parse(tokens.isNotEmpty ? tokens[0] : null);
    if (horizontal == null) {
      return null;
    }
    final vertical = parse(tokens.length > 1 ? tokens[1] : null) ?? horizontal;
    return CssEdges(
      top: vertical,
      right: horizontal,
      bottom: vertical,
      left: horizontal,
    );
  }

  static CssLength? _parseOffset(
    String? raw, {
    required double fontSize,
    required double rootFontSize,
  }) {
    if (raw == null) {
      return null;
    }
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value == 'auto') {
      return null;
    }
    return _resolveCssLength(
      value,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
    );
  }

  static const Map<String, CssTextDecorationStyle> _decorationStyles =
      <String, CssTextDecorationStyle>{
        'solid': CssTextDecorationStyle.solid,
        'double': CssTextDecorationStyle.double,
        'dotted': CssTextDecorationStyle.dotted,
        'dashed': CssTextDecorationStyle.dashed,
        'wavy': CssTextDecorationStyle.wavy,
      };

  static CssTextDecorationStyle? _parseTextDecorationStyle(String? raw) =>
      raw == null ? null : _decorationStyles[raw.trim().toLowerCase()];

  static CssTextDecorationStyle? _decorationStyleFromShorthand(String? raw) {
    if (raw == null) {
      return null;
    }
    for (final token in raw.toLowerCase().split(RegExp(r'\s+'))) {
      final style = _decorationStyles[token];
      if (style != null) {
        return style;
      }
    }
    return null;
  }

  static Color? _decorationColorFromShorthand(String? raw) {
    if (raw == null) {
      return null;
    }
    for (final token in raw.split(RegExp(r'\s+'))) {
      final color = _parseColor(token);
      if (color != null) {
        return color;
      }
    }
    return null;
  }

  static CssTextDecoration? _parseTextDecoration(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null) {
      return null;
    }
    if (value == 'none') {
      return CssTextDecoration.none;
    }
    final underline = value.contains('underline');
    final lineThrough = value.contains('line-through');
    final overline = value.contains('overline');
    return switch ((underline, lineThrough, overline)) {
      (true, false, false) => CssTextDecoration.underline,
      (false, true, false) => CssTextDecoration.lineThrough,
      (false, false, true) => CssTextDecoration.overline,
      (true, true, false) => CssTextDecoration.underlineLineThrough,
      (true, false, true) => CssTextDecoration.underlineOverline,
      (false, true, true) => CssTextDecoration.lineThroughOverline,
      (true, true, true) => CssTextDecoration.underlineLineThroughOverline,
      (false, false, false) => null,
    };
  }

  static CssTextEmphasisStyle? _parseTextEmphasisStyle(String raw) {
    final tokens = raw.trim().toLowerCase().split(RegExp(r'\s+')).toSet();
    if (tokens.contains('none')) {
      return CssTextEmphasisStyle.none;
    }
    final open = tokens.contains('open');
    if (tokens.contains('circle')) {
      return open
          ? CssTextEmphasisStyle.openCircle
          : CssTextEmphasisStyle.circle;
    }
    if (tokens.contains('sesame')) {
      return open
          ? CssTextEmphasisStyle.openSesame
          : CssTextEmphasisStyle.sesame;
    }
    if (tokens.contains('dot') ||
        tokens.contains('filled') ||
        tokens.contains('open')) {
      // 只写 filled/open 时按规范默认形状 dot。
      return open ? CssTextEmphasisStyle.openDot : CssTextEmphasisStyle.dot;
    }
    return null;
  }

  static CssTextCombine? _parseTextCombine(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'all' || 'digits' => CssTextCombine.all,
      'none' => CssTextCombine.none,
      _ => null,
    };
  }

  static CssLineBreak? _parseLineBreak(String? raw) {
    if (raw == null) {
      return null;
    }
    return switch (raw.trim().toLowerCase()) {
      'auto' => CssLineBreak.auto,
      'loose' => CssLineBreak.loose,
      'normal' => CssLineBreak.normal,
      'strict' => CssLineBreak.strict,
      'anywhere' => CssLineBreak.anywhere,
      _ => null,
    };
  }

  static int? _parseTabSize(String? raw) {
    if (raw == null) {
      return null;
    }
    final value = raw.trim();
    final number = int.tryParse(value);
    if (number == null || number < 1) {
      // 长度形式（`4em`）按字号的整数倍折算；非法值回退默认 8。
      final em = RegExp(r'^([\d.]+)em$').firstMatch(value);
      if (em == null) {
        return null;
      }
      final parsed = double.tryParse(em.group(1)!);
      if (parsed == null || parsed <= 0) {
        return null;
      }
      return parsed.round().clamp(1, 64);
    }
    return number.clamp(1, 64);
  }

  static CssMixBlendMode? _parseMixBlendMode(String? raw) {
    if (raw == null) {
      return null;
    }
    return switch (raw.trim().toLowerCase()) {
      'normal' => CssMixBlendMode.normal,
      'multiply' => CssMixBlendMode.multiply,
      'screen' => CssMixBlendMode.screen,
      'overlay' => CssMixBlendMode.overlay,
      'darken' => CssMixBlendMode.darken,
      'lighten' => CssMixBlendMode.lighten,
      _ => null,
    };
  }

  static CssRubyPosition? _parseRubyPosition(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.contains('under')) {
      return CssRubyPosition.under;
    }
    if (value.contains('over')) {
      return CssRubyPosition.over;
    }
    return null;
  }

  static CssRubyAlign? _parseRubyAlign(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'start' || 'left' => CssRubyAlign.start,
      'center' || 'centre' => CssRubyAlign.center,
      'end' || 'right' => CssRubyAlign.end,
      'space-between' ||
      'space-around' ||
      'space-evenly' => CssRubyAlign.spaceBetween,
      _ => null,
    };
  }

  static CssTextEmphasisPosition? _parseTextEmphasisPosition(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.contains('under')) {
      return CssTextEmphasisPosition.under;
    }
    if (value.contains('over')) {
      return CssTextEmphasisPosition.over;
    }
    return null;
  }

  static bool _parsePageBreak(String? raw) {
    final value = raw?.trim().toLowerCase();
    return value == 'always' ||
        value == 'page' ||
        value == 'left' ||
        value == 'right';
  }

  static CssVerticalAlign? _parseVerticalAlign(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'baseline' => CssVerticalAlign.baseline,
        'sub' => CssVerticalAlign.subscript,
        'super' => CssVerticalAlign.superscript,
        'middle' => CssVerticalAlign.middle,
        'top' || 'text-top' => CssVerticalAlign.top,
        'bottom' || 'text-bottom' => CssVerticalAlign.bottom,
        _ => null,
      };

  /// 解析 `vertical-align: <length> | <percentage>`（W2）。
  ///
  /// 百分比基准是本元素行高（Chrome 实测口径）；关键字返回 null。
  /// 返回值保留 CSS 符号（正 = 向上抬高）。
  static double? _parseVerticalAlignLength(
    String? raw, {
    required double lineHeight,
    required double fontSize,
    required double rootFontSize,
  }) {
    if (raw == null) {
      return null;
    }
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) {
      return null;
    }
    final percent = _parsePercent(value);
    if (percent != null) {
      return lineHeight * percent / 100;
    }
    return _resolveLength(
      value,
      fontSize: fontSize,
      parentFontSize: fontSize,
      rootFontSize: rootFontSize,
      percentBase: lineHeight,
    );
  }

  static CssDisplay? _parseDisplay(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'block' || 'flow-root' || 'grid' => CssDisplay.block,
        'inline' => CssDisplay.inline,
        'inline-block' => CssDisplay.inlineBlock,
        'table' ||
        'inline-table' ||
        'table-row-group' ||
        'table-header-group' ||
        'table-footer-group' => CssDisplay.table,
        'table-row' => CssDisplay.tableRow,
        'table-cell' => CssDisplay.tableCell,
        'flex' || 'inline-flex' => CssDisplay.flex,
        'list-item' => CssDisplay.listItem,
        'none' => CssDisplay.none,
        _ => null,
      };

  static Color? _parseColor(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'transparent') {
      return const Color(0x00000000);
    }
    if (value.startsWith('#')) {
      final hex = value.substring(1);
      int? parsed;
      if (hex.length == 3 || hex.length == 4) {
        final expanded = StringBuffer();
        for (final char in hex.split('')) {
          expanded.write('$char$char');
        }
        parsed = int.tryParse(expanded.toString(), radix: 16);
      } else if (hex.length == 6 || hex.length == 8) {
        parsed = int.tryParse(hex, radix: 16);
      }
      if (parsed == null) {
        return null;
      }
      return Color(
        hex.length <= 4 || hex.length == 6 ? 0xFF000000 | parsed : parsed,
      );
    }
    final rgb = RegExp(r'^rgba?\(([^)]+)\)$').firstMatch(value);
    if (rgb != null) {
      final parts = rgb[1]!.split(',').map((part) => part.trim()).toList();
      if (parts.length < 3) {
        return null;
      }
      int channel(String text) {
        if (text.endsWith('%')) {
          final percent = double.tryParse(text.substring(0, text.length - 1));
          return percent == null
              ? 0
              : (percent * 255 / 100).round().clamp(0, 255);
        }
        return (double.tryParse(text) ?? 0).round().clamp(0, 255);
      }

      final alpha = parts.length >= 4
          ? (double.tryParse(parts[3]) ?? 1).clamp(0.0, 1.0)
          : 1.0;
      return Color.fromARGB(
        (alpha * 255).round(),
        channel(parts[0]),
        channel(parts[1]),
        channel(parts[2]),
      );
    }
    // 复用 csslib 的标准颜色表，合法命名色不能使整个边框声明失效。
    final named = csslib.TokenKind.matchColorName(value);
    return named == null
        ? null
        : Color(0xFF000000 | csslib.TokenKind.colorValue(named));
  }
}

/// 解析 font-family 列表：按逗号切分，忽略引号内的逗号，去掉引号与空白。
List<String> _parseFontFamilies(String raw) {
  final families = <String>[];
  final buffer = StringBuffer();
  var quote = '';
  for (final char in raw.split('')) {
    if (quote.isEmpty && (char == '"' || char == "'")) {
      quote = char;
      continue;
    }
    if (quote.isNotEmpty && char == quote) {
      quote = '';
      continue;
    }
    if (quote.isEmpty && char == ',') {
      final family = buffer.toString().trim();
      if (family.isNotEmpty) {
        families.add(family);
      }
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  final last = buffer.toString().trim();
  if (last.isNotEmpty) {
    families.add(last);
  }
  return List<String>.unmodifiable(families);
}

/// `calc()` 表达式求值（P9-15）。
///
/// 支持 + - * /、括号与 px/pt/pc/in/cm/mm/em/rem/%；出现百分比时按
/// [percentBase] 折算，基准为 0（未知）时返回 null，交给调用方回退。
double? _evaluateCalc(
  String raw, {
  required double fontSize,
  required double rootFontSize,
  required double percentBase,
}) {
  var expression = raw.trim();
  if (expression.toLowerCase().startsWith('calc(') &&
      expression.endsWith(')')) {
    expression = expression.substring(5, expression.length - 1);
  }
  final evaluator = _CalcEvaluator(
    expression,
    fontSize: fontSize,
    rootFontSize: rootFontSize,
    percentBase: percentBase,
  );
  final result = evaluator.evaluate();
  return evaluator.finished ? result : null;
}

final RegExp _calcTokenPattern = RegExp(
  r'(\d+(?:\.\d+)?|\.\d+)(px|pt|pc|in|cm|mm|em|rem|%)?|[()+\-*/]|\s+',
);

class _CalcEvaluator {
  _CalcEvaluator(
    this.source, {
    required this.fontSize,
    required this.rootFontSize,
    required this.percentBase,
  }) {
    _tokenize();
  }

  final String source;
  final double fontSize;
  final double rootFontSize;
  final double percentBase;
  final List<String> _tokens = <String>[];
  int _position = 0;
  bool finished = false;

  void _tokenize() {
    var index = 0;
    while (index < source.length) {
      final match = _calcTokenPattern.matchAsPrefix(source, index);
      if (match == null) {
        _tokens
          ..clear()
          ..add('?');
        return;
      }
      final token = match.group(0)!;
      index = match.end;
      if (token.trim().isEmpty) {
        continue;
      }
      _tokens.add(token.trim());
    }
  }

  double? evaluate() {
    if (_tokens.isEmpty || _tokens.first == '?') {
      return null;
    }
    final value = _parseExpression();
    if (value == null || _position != _tokens.length) {
      return null;
    }
    finished = true;
    return value;
  }

  double? _parseExpression() {
    var left = _parseTerm();
    if (left == null) {
      return null;
    }
    while (_position < _tokens.length) {
      final token = _tokens[_position];
      if (token != '+' && token != '-') {
        break;
      }
      _position += 1;
      final right = _parseTerm();
      if (right == null) {
        return null;
      }
      left = token == '+' ? left! + right : left! - right;
    }
    return left;
  }

  double? _parseTerm() {
    var left = _parseFactor();
    if (left == null) {
      return null;
    }
    while (_position < _tokens.length) {
      final token = _tokens[_position];
      if (token != '*' && token != '/') {
        break;
      }
      _position += 1;
      final right = _parseFactor();
      if (right == null) {
        return null;
      }
      if (token == '*') {
        left = left! * right;
      } else {
        if (right == 0) {
          return null;
        }
        left = left! / right;
      }
    }
    return left;
  }

  double? _parseFactor() {
    if (_position >= _tokens.length) {
      return null;
    }
    final token = _tokens[_position];
    if (token == '-') {
      _position += 1;
      final inner = _parseFactor();
      return inner == null ? null : -inner;
    }
    if (token == '(') {
      _position += 1;
      final inner = _parseExpression();
      if (inner == null ||
          _position >= _tokens.length ||
          _tokens[_position] != ')') {
        return null;
      }
      _position += 1;
      return inner;
    }
    final match = RegExp(
      r'^(-?(?:\d+(?:\.\d+)?|\.\d+))(px|pt|pc|in|cm|mm|em|rem|%)?$',
    ).firstMatch(token);
    if (match == null) {
      return null;
    }
    _position += 1;
    final number = double.parse(match[1]!);
    return switch (match[2]) {
      null || 'px' => number,
      'pt' => number * 96 / 72,
      'pc' => number * 16,
      'in' => number * 96,
      'cm' => number * 96 / 2.54,
      'mm' => number * 96 / 25.4,
      'em' => number * fontSize,
      'rem' => number * rootFontSize,
      '%' => percentBase == 0 ? null : number * percentBase / 100,
      _ => null,
    };
  }
}

/// 列表逐项相等（[CssGradient] 的 == / hashCode 用）。
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
