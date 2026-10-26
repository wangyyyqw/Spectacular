import 'dart:ui' show Color;

import 'computed_style.dart';

/// 阅读器设置覆盖层（P2-22）。
///
/// 设置值通过「显式属性」覆盖书籍样式：合并后的 [ComputedStyle] 里只有
/// 设置声明的属性取设置值，其余继续继承书籍声明（CSS cascade 的 reader
/// origin 高于 author origin，§7.5）。
class ReaderOverrides {
  /// 创建设置。
  const ReaderOverrides({
    this.fontSize,
    this.lineHeight,
    this.paragraphSpacing,
    this.textAlign,
    this.padding,
    this.textColor,
    this.backgroundColor,
  });

  /// 正文字号（逻辑像素）。
  final double? fontSize;

  /// 行高倍数（相对字号）。
  final double? lineHeight;

  /// 段间距（逻辑像素，段与段之间的空隙）。
  ///
  /// null 表示不覆盖：沿用书籍/UA 的段上下边距并按相邻折叠取大。
  final double? paragraphSpacing;

  /// 对齐方式。
  final CssTextAlign? textAlign;

  /// 页边距（四边，逻辑像素）。
  final CssEdges? padding;

  /// 正文颜色。
  final Color? textColor;

  /// 页面背景色。
  final Color? backgroundColor;

  /// 是否没有任何设置。
  bool get isEmpty =>
      fontSize == null &&
      lineHeight == null &&
      paragraphSpacing == null &&
      textAlign == null &&
      padding == null &&
      textColor == null &&
      backgroundColor == null;

  /// 影响排版的设置指纹（字号/行高/段距/对齐/页边距；颜色不参与布局，
  /// P2-24）。
  String get fingerprint => [
    'fs=${fontSize ?? '-'}',
    'lh=${lineHeight ?? '-'}',
    'ps=${paragraphSpacing ?? '-'}',
    'align=${textAlign?.name ?? '-'}',
    'pad=${padding == null ? '-' : '${padding!.top},${padding!.right},'
              '${padding!.bottom},${padding!.left}'}',
  ].join(';');

  /// 正文字体排版声明（字号/行高/对齐）：阅读器设置优先于作者 CSS。
  Map<String, String> typographyDeclarations() {
    final values = <String, String>{};
    final size = fontSize;
    if (size != null) {
      values['font-size'] = _px(size);
    }
    final height = lineHeight;
    if (height != null) {
      values['line-height'] = '$height';
    }
    final align = textAlign;
    if (align != null) {
      values['text-align'] = _alignCss(align);
    }
    return values;
  }

  /// 在正文块样式之上应用字体排版覆盖（字号/行高/对齐）。
  ///
  /// 用于覆盖作者 CSS 的显式声明——阅读器设置属于更高的 origin
  /// （CSS §7.5 reader origin 高于 author），必须作用在级联结果之上；
  /// 只覆盖这三项，页边距与颜色走各自通道。
  ComputedStyle applyTypography(ComputedStyle base) {
    if (fontSize == null && lineHeight == null && textAlign == null) {
      return base;
    }
    // 只改排版属性：重建 ComputedStyle 会把背景/边框/内外边距这些
    // 非继承属性归零，书籍面板会整块消失（P9-01）。
    return base.withTypography(
      fontSize: fontSize,
      lineHeightFactor: lineHeight,
      textAlign: textAlign,
    );
  }

  /// 转成 CSS 声明（覆盖层用显式属性合并）。
  Map<String, String> toCssDeclarations() {
    final values = <String, String>{};
    final size = fontSize;
    if (size != null) {
      values['font-size'] = _px(size);
    }
    final height = lineHeight;
    if (height != null) {
      values['line-height'] = '$height';
    }
    final align = textAlign;
    if (align != null) {
      values['text-align'] = _alignCss(align);
    }
    final edges = padding;
    if (edges != null) {
      values['padding-top'] = _px(edges.top);
      values['padding-right'] = _px(edges.right);
      values['padding-bottom'] = _px(edges.bottom);
      values['padding-left'] = _px(edges.left);
    }
    final text = textColor;
    if (text != null) {
      values['color'] = _colorCss(text);
    }
    final background = backgroundColor;
    if (background != null) {
      values['background-color'] = _colorCss(background);
    }
    return values;
  }

  /// 在书籍样式之上应用覆盖，返回合并后的样式。
  ///
  /// [containingWidth] 用于百分比尺寸解算（通常为正文区宽）。
  ComputedStyle apply(ComputedStyle base, {double? containingWidth}) {
    final declarations = toCssDeclarations();
    if (declarations.isEmpty) {
      return base;
    }
    return ComputedStyle(
      declarations,
      parent: base,
      explicitProperties: declarations.keys.toSet(),
      containingWidth: containingWidth ?? 0,
      rootFontSize: base.fontSize,
    );
  }

  /// 复制并覆盖部分字段。
  ReaderOverrides copyWith({
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    CssTextAlign? textAlign,
    CssEdges? padding,
    Color? textColor,
    Color? backgroundColor,
  }) => ReaderOverrides(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    textAlign: textAlign ?? this.textAlign,
    padding: padding ?? this.padding,
    textColor: textColor ?? this.textColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
  );
}

String _alignCss(CssTextAlign align) => switch (align) {
  CssTextAlign.start => 'start',
  CssTextAlign.end => 'end',
  CssTextAlign.left => 'left',
  CssTextAlign.right => 'right',
  CssTextAlign.center => 'center',
  CssTextAlign.justify => 'justify',
};

String _colorCss(Color color) {
  final value = color.toARGB32();
  final alpha = (value >> 24) & 0xFF;
  if (alpha == 0xFF) {
    return '#${value.toRadixString(16).substring(2).padLeft(6, '0')}';
  }
  return '#${value.toRadixString(16).padLeft(8, '0')}';
}

String _px(double value) =>
    value == value.roundToDouble() ? '${value.toInt()}px' : '${value}px';
