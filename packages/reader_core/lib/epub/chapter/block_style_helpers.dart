import 'dart:ui' show Color;

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/page_background.dart';

/// 从级联胜出的显式长属性或 font 简写中取字号，继承字号不当作新声明。
String? fontSizeDeclarationOf(ComputedStyle style) {
  if (style.explicitProperties.contains('font-size')) {
    return style.values['font-size']?.trim().toLowerCase();
  }
  if (!style.explicitProperties.contains('font')) return null;
  return ComputedStyle.parseFontShorthand(
    style.values['font'],
  )?['font-size']?.trim().toLowerCase();
}

/// 边框线型名（P8-05c 拼合声明用）。
String borderStyleName(CssBorderStyle value) => switch (value) {
  CssBorderStyle.solid => 'solid',
  CssBorderStyle.dashed => 'dashed',
  CssBorderStyle.dotted => 'dotted',
  CssBorderStyle.double => 'double',
  _ => 'solid',
};

/// 颜色转 #RRGGBB（P8-05c 拼合声明用）。
String colorToHex(Color color) {
  return (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
}

/// 从 body 的级联结果取整页背景；书籍未声明背景色、图像或渐变时返回 null。
///
/// 外链 CSS 已解算资源路径；内联样式由 [resolveUrl] 按当前章节目录补齐。
PageBackground? chapterPageBackground(
  ComputedStyle style, {
  String Function(String)? resolveUrl,
}) {
  final rawUrl = style.backgroundImage;
  final url = rawUrl == null || rawUrl.isEmpty
      ? null
      : resolveUrl?.call(rawUrl) ?? rawUrl;
  final layers = List<CssBackgroundLayer>.unmodifiable([
    for (final layer in style.backgroundLayers)
      _pageBackgroundLayer(layer, resolveUrl),
  ]);
  final color = style.backgroundColor.a > 0 ? style.backgroundColor : null;
  final hasLayer = layers.any(
    (layer) => layer.image != null || layer.gradient != null,
  );
  if (url == null && color == null && !hasLayer) {
    return null;
  }
  return PageBackground(
    imageUrl: url,
    backgroundColor: color,
    size: style.backgroundSize,
    repeat: style.backgroundRepeat,
    position: style.backgroundPosition,
    layers: layers,
  );
}

CssBackgroundLayer _pageBackgroundLayer(
  CssBackgroundLayer layer,
  String Function(String)? resolveUrl,
) {
  final image = layer.image;
  if (image == null || resolveUrl == null) return layer;
  final resolved = resolveUrl(image);
  if (resolved == image) return layer;
  return CssBackgroundLayer(
    image: resolved,
    gradient: layer.gradient,
    repeat: layer.repeat,
    size: layer.size,
    position: layer.position,
    origin: layer.origin,
    clip: layer.clip,
  );
}

/// 级联后的浮动方向（f）；未浮动返回 null。
FloatSide? floatSideOfStyle(ComputedStyle style) => switch (style.cssFloat) {
  CssFloat.left => FloatSide.left,
  CssFloat.right => FloatSide.right,
  CssFloat.none => null,
};

/// UA 里承担列表近似缩进的那条规则（见 [cascadeRules] 过滤）。
bool isUaListIndentRule(CssRule rule) =>
    rule.selector.trim() == 'li' &&
    rule.declarations.any(
      (declaration) => declaration.property == 'margin-left',
    );
