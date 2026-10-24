import 'dart:ui' show Color;

/// 文本对齐（避免把 Flutter 枚举带进纯解析层）。
enum CssTextAlign { start, end, left, right, center, justify }

/// 定位方式（§60.2 第 1 条：absolute/fixed 先摘出流）。
enum CssPosition { static, relative, absolute, fixed, sticky }

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

/// 文本大小写变换（CSS text-transform 属性）。
enum CssTextTransform { none, uppercase, lowercase, capitalize }

/// 行内垂直对齐（CSS vertical-align 属性）。
enum CssVerticalAlign { baseline, subscript, superscript, middle, top, bottom }

/// 文本装饰线（CSS text-decoration 属性，P2-17）。
enum CssTextDecoration { none, underline, lineThrough, overline }

/// 着重号样式（CSS text-emphasis-style 属性，P2-17）。
enum CssTextEmphasisStyle { none, dot, filled, open }

/// 着重号位置（CSS text-emphasis-position 属性）。
enum CssTextEmphasisPosition { over, under }

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
  const CssBackgroundSize.keyword(this.mode)
    : width = null,
      height = null;

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

/// 清除浮动（CSS clear）。
enum CssClear { none, left, right, both }

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
enum CssBorderStyle { none, solid, dashed, dotted, double }

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

  /// 左上圆角。
  final double topLeftRadius;

  /// 右上圆角。
  final double topRightRadius;

  /// 右下圆角。
  final double bottomRightRadius;

  /// 左下圆角。
  final double bottomLeftRadius;

  /// 是否有任意可见边框。
  bool get hasBorder =>
      top.isVisible || right.isVisible || bottom.isVisible || left.isVisible;

  /// 是否有任意圆角。
  bool get hasRadius =>
      topLeftRadius > 0 ||
      topRightRadius > 0 ||
      bottomRightRadius > 0 ||
      bottomLeftRadius > 0;

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
      'radii=$topLeftRadius/$topRightRadius/$bottomRightRadius/$bottomLeftRadius)';
}

/// 一次算完的不可变样式。
///
/// P1-21 最小字段集：字号、行高、颜色、字重、斜体、text-align、margin。
class ComputedStyle {
  /// 从层叠后的字符串值计算类型化字段。
  ///
  /// [explicitProperties] 为元素自身层叠出的属性；未提供的属性从 [parent]
  /// 继承或取初始值。为 null 时把 [values] 全部视为显式值（直接构造场景）。
  factory ComputedStyle(
    Map<String, String> values, {
    bool hasExplicitTextColor = false,
    ComputedStyle? parent,
    Set<String>? explicitProperties,
    double rootFontSize = 16,
    double containingWidth = 0,
  }) {
    final explicit = explicitProperties ?? values.keys.toSet();
    String? explicitValue(String property) =>
        explicit.contains(property) ? values[property] : null;

    final parentFontSize = parent?.fontSize ?? rootFontSize;
    var fontSize = parent?.fontSize ?? rootFontSize;
    final rawFontSize = explicitValue('font-size');
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

    var lineHeight = parent?.lineHeight ?? fontSize * _defaultLineHeightFactor;
    double? lineHeightFactor;
    final rawLineHeight = explicitValue('line-height');
    if (rawLineHeight != null) {
      final unitless = double.tryParse(rawLineHeight.trim());
      if (unitless != null) {
        lineHeight = fontSize * unitless;
        lineHeightFactor = unitless;
      } else {
        final percent = _parsePercent(rawLineHeight);
        if (percent != null) {
          lineHeight = fontSize * percent / 100;
          lineHeightFactor = percent / 100;
        } else {
          final resolved = _resolveLength(
            rawLineHeight,
            fontSize: fontSize,
            parentFontSize: parentFontSize,
            rootFontSize: rootFontSize,
            percentBase: fontSize,
          );
          if (resolved != null) {
            lineHeight = resolved;
            lineHeightFactor = fontSize == 0 ? null : resolved / fontSize;
          }
        }
      }
    }
    lineHeightFactor ??= fontSize == 0 ? null : lineHeight / fontSize;

    final rawColor = explicitValue('color');
    final color = rawColor == null
        ? (parent?.color ?? const Color(0xFF000000))
        : (_parseColor(rawColor) ?? parent?.color ?? const Color(0xFF000000));

    final rawWeight = explicitValue('font-weight');
    final weight = rawWeight == null
        ? (parent?.fontWeight ?? 400)
        : _parseFontWeight(rawWeight) ?? parent?.fontWeight ?? 400;

    final rawStyle = explicitValue('font-style');
    final italic = rawStyle == null
        ? (parent?.italic ?? false)
        : _isItalic(rawStyle);

    final rawFamily = explicitValue('font-family');
    final fontFamilies = rawFamily == null
        ? (parent?.fontFamilies ?? const <String>[])
        : _parseFontFamilies(rawFamily);

    final rawAlign = explicitValue('text-align');
    final textAlign = rawAlign == null
        ? (parent?.textAlign ?? CssTextAlign.start)
        : _parseTextAlign(rawAlign) ?? parent?.textAlign ?? CssTextAlign.start;

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
      values,
      explicit,
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
    final verticalAlign =
        _parseVerticalAlign(explicitValue('vertical-align')) ??
        CssVerticalAlign.baseline;

    // 装饰与分页属性（P2-17）：text-decoration 不继承，text-emphasis 继承。
    final textDecoration =
        _parseTextDecoration(explicitValue('text-decoration')) ??
        CssTextDecoration.none;
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
    final rawEmphasisColor = explicitValue('text-emphasis-color');
    final textEmphasisColor = rawEmphasisColor == null
        ? parent?.textEmphasisColor
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

    // P0 收口补全（P2-18）：text-shadow、背景子属性、定位偏移、clear、表格边框。
    final rawShadow = explicitValue('text-shadow');
    final textShadow = rawShadow == null
        ? (parent?.textShadow ?? const <CssTextShadow>[])
        : _parseTextShadows(rawShadow, fontSize: fontSize) ??
              parent?.textShadow ??
              const <CssTextShadow>[];
    final backgroundRepeat =
        _parseBackgroundRepeat(explicitValue('background-repeat')) ??
        CssBackgroundRepeat.repeat;
    final backgroundSize =
        _parseBackgroundSize(
          explicitValue('background-size'),
          fontSize: fontSize,
          rootFontSize: rootFontSize,
        ) ??
        const CssBackgroundSize.keyword(CssBackgroundSizeMode.auto);
    final backgroundPosition =
        _parseBackgroundPosition(
          explicitValue('background-position'),
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
    final clear = _parseClear(explicitValue('clear')) ?? CssClear.none;
    final rawCollapse = explicitValue('border-collapse');
    final borderCollapse = rawCollapse == null
        ? (parent?.borderCollapse ?? CssBorderCollapse.separate)
        : _parseBorderCollapse(rawCollapse) ??
              parent?.borderCollapse ??
              CssBorderCollapse.separate;
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
    final top =
        _parseOffset(explicitValue('top'), fontSize: fontSize, rootFontSize: rootFontSize) ??
        parent?.top;
    final right =
        _parseOffset(explicitValue('right'), fontSize: fontSize, rootFontSize: rootFontSize) ??
        parent?.right;
    final bottom =
        _parseOffset(explicitValue('bottom'), fontSize: fontSize, rootFontSize: rootFontSize) ??
        parent?.bottom;
    final left =
        _parseOffset(explicitValue('left'), fontSize: fontSize, rootFontSize: rootFontSize) ??
        parent?.left;

    // background 与 border 不继承，按 CSS 初始值兜底（§65 背景与边框组）。
    final backgroundColor =
        _parseColor(explicitValue('background-color') ?? '') ??
        const Color(0x00000000);
    final backgroundImage = _parseUrl(explicitValue('background-image'));
    final borders = _resolveBorders(
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
            );
    }

    final width = dimension('width');
    final height = dimension('height');
    final minWidth = dimension('min-width');
    final maxWidth = dimension('max-width');
    final minHeight = dimension('min-height');
    final maxHeight = dimension('max-height');
    final padding = _resolvePadding(
      values,
      explicit,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
      containingWidth: containingWidth,
    );
    final boxSizing = _parseBoxSizing(explicitValue('box-sizing'));

    return ComputedStyle._(
      values: values,
      hasExplicitTextColor: hasExplicitTextColor,
      fontSize: fontSize,
      lineHeight: lineHeight,
      lineHeightFactor: lineHeightFactor,
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
      wordSpacing: wordSpacing,
      textTransform: textTransform,
      verticalAlign: verticalAlign,
      textDecoration: textDecoration,
      textEmphasisStyle: textEmphasisStyle,
      textEmphasisPosition: textEmphasisPosition,
      textEmphasisColor: textEmphasisColor,
      pageBreakBefore: pageBreakBefore,
      pageBreakAfter: pageBreakAfter,
      breakInsideAvoid: breakInsideAvoid,
      textShadow: textShadow,
      backgroundRepeat: backgroundRepeat,
      backgroundSize: backgroundSize,
      backgroundPosition: backgroundPosition,
      backgroundOrigin: backgroundOrigin,
      clear: clear,
      borderCollapse: borderCollapse,
      borderSpacing: borderSpacing,
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      backgroundColor: backgroundColor,
      backgroundImage: backgroundImage,
      borders: borders,
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

  const ComputedStyle._({
    required this.values,
    required this.hasExplicitTextColor,
    required this.fontSize,
    required this.lineHeight,
    required this.lineHeightFactor,
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
    required this.wordSpacing,
    required this.textTransform,
    required this.verticalAlign,
    required this.textDecoration,
    required this.textEmphasisStyle,
    required this.textEmphasisPosition,
    required this.textEmphasisColor,
    required this.pageBreakBefore,
    required this.pageBreakAfter,
    required this.breakInsideAvoid,
    required this.textShadow,
    required this.backgroundRepeat,
    required this.backgroundSize,
    required this.backgroundPosition,
    required this.backgroundOrigin,
    required this.clear,
    required this.borderCollapse,
    required this.borderSpacing,
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
    required this.backgroundColor,
    required this.backgroundImage,
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

  static const _defaultLineHeightFactor = 1.5;

  /// 属性 → 层叠后的字符串值。
  final Map<String, String> values;

  /// 是否存在作者/内联显式指定的文字色（暗色替换需要）。
  final bool hasExplicitTextColor;

  /// 最终字号（逻辑像素）。
  final double fontSize;

  /// 最终行高（逻辑像素）。
  final double lineHeight;

  /// 行高相对字号的倍数。
  final double? lineHeightFactor;

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

  /// 词间距（逻辑像素，继承，初始 0）。
  final double wordSpacing;

  /// 文本大小写变换（继承，初始 none）。
  final CssTextTransform textTransform;

  /// 行内垂直对齐（不继承，初始 baseline）。
  final CssVerticalAlign verticalAlign;

  /// 文本装饰线（`text-decoration`，不继承）。
  final CssTextDecoration textDecoration;

  /// 着重号样式（继承，初始 none）。
  final CssTextEmphasisStyle textEmphasisStyle;

  /// 着重号位置（继承，初始 over）。
  final CssTextEmphasisPosition textEmphasisPosition;

  /// 着重号颜色；null 表示跟随文字颜色。
  final Color? textEmphasisColor;

  /// 块前强制分页（`page-break-before: always` 等）。
  final bool pageBreakBefore;

  /// 块后强制分页。
  final bool pageBreakAfter;

  /// 块内禁止分页（`break-inside: avoid`）。
  final bool breakInsideAvoid;

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

  /// 清除浮动（`clear`，不继承）。
  final CssClear clear;

  /// 表格边框合并（`border-collapse`，继承）。
  final CssBorderCollapse borderCollapse;

  /// 表格边框间距（`border-spacing`，继承；top/bottom 存垂直，left/right 存水平）。
  final CssEdges borderSpacing;

  /// 上定位偏移（`top`，未继承；null 表示未声明）。
  final CssLength? top;

  /// 右定位偏移。
  final CssLength? right;

  /// 下定位偏移。
  final CssLength? bottom;

  /// 左定位偏移。
  final CssLength? left;

  /// 行内基线偏移（逻辑像素，正值向下）：sup -0.4em、sub +0.15em（与阅微 BaselineShift 同值）。
  double get verticalAlignShift => switch (verticalAlign) {
    CssVerticalAlign.superscript => -0.4 * fontSize,
    CssVerticalAlign.subscript => 0.15 * fontSize,
    _ => 0,
  };

  /// 背景色（不继承，初始透明）。
  final Color backgroundColor;

  /// 背景图 URL（`background-image: url(...)` 的解析结果，绘制留资源任务）。
  final String? backgroundImage;

  /// 四边边框与四角圆角。
  final CssBorders borders;

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
      percentBase: 0,
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
      var width = 0.0;
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
        if (parsedWidth != null && RegExp(r'^[+-]?[\d.]').hasMatch(token)) {
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
      width: 0,
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
        final parsed = _parseColor(rawColor);
        if (parsed != null) {
          sides[index] = CssBorderSide(
            width: sides[index].width,
            style: sides[index].style,
            color: parsed,
          );
        }
      }
    }
    // 只写了线型没写宽度时按 CSS medium（3px）处理。
    sides = [
      for (final side in sides)
        side.style != CssBorderStyle.none && side.width == 0
            ? CssBorderSide(width: 3, style: side.style, color: side.color)
            : side,
    ];

    var radii = <double>[0, 0, 0, 0];
    final radiusRaw = value('border-radius');
    if (radiusRaw != null) {
      final tokens = radiusRaw.trim().split(RegExp(r'\s+'));
      final slash = tokens.indexOf('/');
      final parts = _expandFour(slash >= 0 ? tokens.sublist(0, slash) : tokens);
      for (var i = 0; i < parts.length && i < 4; i++) {
        radii[i] = length(parts[i]) ?? 0;
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
        radii[index] = length(raw) ?? radii[index];
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
    );
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

  static CssBorderStyle? _parseBorderStyle(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'none' || 'hidden' => CssBorderStyle.none,
        'solid' => CssBorderStyle.solid,
        'dashed' => CssBorderStyle.dashed,
        'dotted' => CssBorderStyle.dotted,
        'double' => CssBorderStyle.double,
        _ => null,
      };

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

  static int? _parseFontWeight(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'normal') {
      return 400;
    }
    if (value == 'bold') {
      return 700;
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
        'center' => CssTextAlign.center,
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

  static CssTextDecoration? _parseTextDecoration(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null) {
      return null;
    }
    if (value == 'none') {
      return CssTextDecoration.none;
    }
    if (value.contains('underline')) {
      return CssTextDecoration.underline;
    }
    if (value.contains('line-through')) {
      return CssTextDecoration.lineThrough;
    }
    if (value.contains('overline')) {
      return CssTextDecoration.overline;
    }
    return null;
  }

  static CssTextEmphasisStyle? _parseTextEmphasisStyle(String raw) {
    // 简写（text-emphasis）可能带颜色/位置，取第一个样式关键字。
    for (final token in raw.trim().toLowerCase().split(RegExp(r'\s+'))) {
      switch (token) {
        case 'none':
          return CssTextEmphasisStyle.none;
        case 'dot':
          return CssTextEmphasisStyle.dot;
        case 'filled' || 'sesame':
          return CssTextEmphasisStyle.filled;
        case 'open' || 'circle':
          return CssTextEmphasisStyle.open;
      }
    }
    return null;
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
    const named = <String, int>{
      'black': 0xFF000000,
      'white': 0xFFFFFFFF,
      'red': 0xFFFF0000,
      'green': 0xFF008000,
      'blue': 0xFF0000FF,
      'gray': 0xFF808080,
      'grey': 0xFF808080,
      'yellow': 0xFFFFFF00,
      'orange': 0xFFFFA500,
      'purple': 0xFF800080,
      'silver': 0xFFC0C0C0,
      'maroon': 0xFF800000,
      'navy': 0xFF000080,
    };
    final argb = named[value];
    return argb == null ? null : Color(argb);
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
