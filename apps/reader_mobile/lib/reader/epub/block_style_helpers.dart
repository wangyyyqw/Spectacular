import 'dart:ui' show Color;

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/page_background.dart';

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

/// 从 body 的级联结果取整页背景；书籍未声明背景图时返回 null。
///
/// 只取 `background-image` 与尺寸/平铺/定位：页面底色仍由阅读主题决定。
PageBackground? chapterPageBackground(ComputedStyle style) {
  final url = style.backgroundImage;
  if (url == null || url.isEmpty) {
    return null;
  }
  return PageBackground(
    imageUrl: url,
    size: style.backgroundSize,
    repeat: style.backgroundRepeat,
    position: style.backgroundPosition,
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
