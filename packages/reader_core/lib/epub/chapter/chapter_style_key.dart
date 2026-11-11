import 'dart:convert';
import 'dart:ui' show Color;

import 'package:crypto/crypto.dart';
import 'package:reader_core/css/computed_style.dart';

/// 基础样式参与后续级联、构块和绘制，不能使用仅描述文本度量的指纹。
/// 每个章节源只计算一次；主题覆盖仍由原有只重绘路径处理。
String chapterBaseStyleKey(ComputedStyle style) {
  final data = {
    'version': 1,
    'values': _ordered(style.values),
    'customProperties': _ordered(style.customProperties),
    'explicitProperties': style.explicitProperties.toList()..sort(),
    'declaredTextProperties': style.declaredTextProperties.toList()..sort(),
    ..._text(style),
    ..._flow(style),
    ..._boxes(style),
    ..._paint(style),
  };
  final encoded = jsonEncode(data, toEncodable: _encodeValue);
  return 'v1:${sha256.convert(utf8.encode(encoded))}';
}

Map<String, String> _ordered(Map<String, String> values) => {
  for (final key in values.keys.toList()..sort()) key: values[key]!,
};

Map<String, Object?> _text(ComputedStyle s) => {
  'fontSize': s.fontSize,
  'parentFontSize': s.parentFontSize,
  'cssRootFontSize': s.cssRootFontSize,
  'cssFontSize': s.cssFontSize,
  'lineHeight': s.lineHeight,
  'lineHeightFactor': s.lineHeightFactor,
  'unitlessLineHeightFactor': s.unitlessLineHeightFactor,
  'fontWeight': s.fontWeight,
  'italic': s.italic,
  'fontFamilies': s.fontFamilies,
  'fontVariantCaps': s.fontVariantCaps,
  'fontVariantLigatures': s.fontVariantLigatures,
  'fontKerning': s.fontKerning,
  'fontFeatureSettings': s.fontFeatureSettings,
  'fontStretch': s.fontStretch,
  'fontSizeAdjust': s.fontSizeAdjust,
  'textAlign': s.textAlign,
  'textAlignLast': s.textAlignLast,
  'textIndent': s.textIndent,
  'letterSpacing': s.letterSpacing,
  'wordSpacing': s.wordSpacing,
  'whiteSpace': s.whiteSpace,
  'hangingPunctuation': s.hangingPunctuation,
  'textSpacingTrim': s.textSpacingTrim,
  'textAutospace': s.textAutospace,
  'textJustify': s.textJustify,
  'textTransform': s.textTransform,
  'textCombine': s.textCombine,
  'quotes': s.quotes,
  'initialLetterLines': s.initialLetterLines,
  'verticalAlign': s.verticalAlign,
  'verticalAlignLength': s.verticalAlignLength,
  'rubyPosition': s.rubyPosition,
  'rubyAlign': s.rubyAlign,
};

Map<String, Object?> _flow(ComputedStyle s) => {
  'display': s.display,
  'position': s.position,
  'cssFloat': s.cssFloat,
  'clear': s.clear,
  'visibility': s.visibility,
  'writingMode': s.writingMode,
  'textOrientation': s.textOrientation,
  'direction': s.direction,
  'hyphens': s.hyphens,
  'wordBreak': s.wordBreak,
  'overflowWrap': s.overflowWrap,
  'lineBreak': s.lineBreak,
  'tabSize': s.tabSize,
  'overflow': s.overflow,
  'textOverflow': s.textOverflow,
  'pageBreakBefore': s.pageBreakBefore,
  'pageBreakAfter': s.pageBreakAfter,
  'breakInsideAvoid': s.breakInsideAvoid,
  'breakAfterAvoid': s.breakAfterAvoid,
  'columnCount': s.columnCount,
  'columnWidth': s.columnWidth,
  'columnGap': s.columnGap,
  'rowGap': s.rowGap,
  'columnRule': s.columnRule,
  'borderCollapse': s.borderCollapse,
  'captionSide': s.captionSide,
  'emptyCells': s.emptyCells,
  'borderSpacing': s.borderSpacing,
  'listStyleType': s.listStyleType,
  'listStyleString': s.listStyleString,
  'listStylePosition': s.listStylePosition,
  'listStyleImage': s.listStyleImage,
  'tableLayout': s.tableLayout,
};

Map<String, Object?> _boxes(ComputedStyle s) => {
  'margin': s.margin,
  'padding': s.padding,
  'width': s.width,
  'intrinsicWidth': s.intrinsicWidth,
  'height': s.height,
  'minWidth': s.minWidth,
  'maxWidth': s.maxWidth,
  'minHeight': s.minHeight,
  'maxHeight': s.maxHeight,
  'aspectRatio': s.aspectRatio,
  'boxSizing': s.boxSizing,
  'top': s.top,
  'right': s.right,
  'bottom': s.bottom,
  'left': s.left,
  'bleed': [s.bleed.top, s.bleed.right, s.bleed.bottom, s.bleed.left],
  'borders': _borders(s.borders),
  'outline': [
    s.outline.width,
    s.outline.style,
    s.outline.color,
    s.outline.offset,
  ],
  'borderImage': s.borderImage,
};

Map<String, Object?> _paint(ComputedStyle s) => {
  'color': s.color,
  'hasExplicitTextColor': s.hasExplicitTextColor,
  'opacity': s.opacity,
  'effectiveOpacity': s.effectiveOpacity,
  'mixBlendMode': s.mixBlendMode,
  'filters': s.filters,
  'backdropFilters': s.backdropFilters,
  'clipPath': s.clipPath,
  'transforms': s.transforms,
  'transformOriginX': s.transformOriginX,
  'transformOriginY': s.transformOriginY,
  'boxShadow': s.boxShadow,
  'textShadow': s.textShadow,
  'textDecoration': s.textDecoration,
  'textDecorationStyle': s.textDecorationStyle,
  'textDecorationColor': s.textDecorationColor,
  'textEmphasisStyle': s.textEmphasisStyle,
  'textEmphasisPosition': s.textEmphasisPosition,
  'textEmphasisColor': s.textEmphasisColor,
  'backgroundColor': s.backgroundColor,
  'backgroundImage': s.backgroundImage,
  'backgroundGradient': s.backgroundGradient,
  'backgroundRepeat': s.backgroundRepeat,
  'backgroundSize': [
    s.backgroundSize.mode,
    s.backgroundSize.width,
    s.backgroundSize.height,
  ],
  'backgroundPosition': [s.backgroundPosition.x, s.backgroundPosition.y],
  'backgroundOrigin': s.backgroundOrigin,
  'backgroundClip': s.backgroundClip,
};

// 不使用对象身份或调试 toString；列表顺序与颜色/长度精度均参与键。
Object _encodeValue(Object? value) => switch (value) {
  Enum() => value.name,
  Color() => [value.colorSpace.name, value.a, value.r, value.g, value.b],
  num() => value.toString(), // JSON 将非有限数交给此分支，不让诊断输入崩溃。
  CssLength() => [value.value, value.isAuto, value.isPercent],
  CssEdges() => [value.top, value.right, value.bottom, value.left],
  CssFontFeatureSetting() => [value.tag, value.value],
  CssQuotesAuto() => ['auto'],
  CssQuotesNone() => ['none'],
  CssQuotesPairs() => [
    'pairs',
    for (final pair in value.pairs) [pair.open, pair.close],
  ],
  _ => _encodePaintValue(value),
};

Object _encodePaintValue(Object? value) => switch (value) {
  CssTextShadow() => [value.offsetX, value.offsetY, value.blur, value.color],
  CssDropShadow() => [value.offsetX, value.offsetY, value.blur, value.color],
  CssBoxShadow() => [
    value.offsetX,
    value.offsetY,
    value.blur,
    value.color,
    value.spread,
    value.inset,
  ],
  CssFilter() => [value.kind, value.amount, value.shadow],
  CssTransform() => _transform(value),
  CssClipPath() => _clip(value),
  _ => _encodeDecorationValue(value),
};

Object _encodeDecorationValue(Object? value) => switch (value) {
  CssBackgroundRepeat() => [value.x, value.y],
  CssBorderSide() => [value.width, value.style, value.color],
  CssBorderImage() => [
    value.url,
    value.sliceTop,
    value.sliceRight,
    value.sliceBottom,
    value.sliceLeft,
    value.slicePercent,
    value.repeat,
    value.fill,
  ],
  CssGradientStop() => [value.color, value.position, value.positionPx],
  CssLinearGradient() => ['linear', value.angle, value.repeating, value.stops],
  CssRadialGradient() => [
    'radial',
    value.shape,
    value.centerX,
    value.centerY,
    value.repeating,
    value.stops,
  ],
  CssConicGradient() => ['conic', value.stops],
  _ => throw StateError('基础样式键尚未覆盖 ${value.runtimeType}'),
};

List<Object?> _transform(CssTransform value) => [
  value.kind,
  value.x,
  value.y,
  value.sx,
  value.sy,
  value.angleDeg,
  value.axDeg,
  value.ayDeg,
  value.values,
];

List<Object?> _borders(CssBorders b) => [
  b.top,
  b.right,
  b.bottom,
  b.left,
  b.topLeftRadius,
  b.topRightRadius,
  b.bottomRightRadius,
  b.bottomLeftRadius,
  b.topLeftRadiusPercent,
  b.topRightRadiusPercent,
  b.bottomRightRadiusPercent,
  b.bottomLeftRadiusPercent,
  b.topLeftRadiusY,
  b.topRightRadiusY,
  b.bottomRightRadiusY,
  b.bottomLeftRadiusY,
  b.topLeftRadiusPercentY,
  b.topRightRadiusPercentY,
  b.bottomRightRadiusPercentY,
  b.bottomLeftRadiusPercentY,
];

List<Object?> _clip(CssClipPath c) => [
  c.kind,
  c.insetTop,
  c.insetRight,
  c.insetBottom,
  c.insetLeft,
  c.insetOffsets,
  c.insetRadiiX,
  c.insetRadiiY,
  c.circleRadius,
  c.circleExtent,
  c.ellipseRadiusX,
  c.ellipseRadiusY,
  c.ellipseExtentX,
  c.ellipseExtentY,
  c.centerX,
  c.centerY,
  c.positionSpecified,
  c.radiiSpecified,
  [
    for (final point in c.points) [point.x, point.y],
  ],
  c.evenOdd,
  c.geometryBox,
];
