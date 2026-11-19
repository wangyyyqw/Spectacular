import 'package:flutter/painting.dart';

import '../annotations/annotation.dart';
import 'decoration_highlight.dart';
import 'decoration_nine_slice.dart';
import 'style_values.dart';

export 'decoration_highlight.dart';
export 'decoration_nine_slice.dart';

enum ReaderDecorationImageFit {
  cover('裁剪铺满', BoxFit.cover),
  contain('完整显示', BoxFit.contain),
  fill('拉伸铺满', BoxFit.fill),
  tile('平铺', BoxFit.none),
  nineSlice('点九拉伸', BoxFit.fill);

  const ReaderDecorationImageFit(this.label, this.fit);
  final String label;
  final BoxFit fit;

  static ReaderDecorationImageFit fromJson(Object? value) =>
      values.where((item) => item.name == value).firstOrNull ?? cover;
}

/// 装饰边框线型。
enum ReaderDecorationBorderStyle {
  /// 实线。
  solid,

  /// 双线。
  double,

  /// 虚线。
  dashed,

  /// 点线。
  dotted;

  /// 显示名称。
  String get label => switch (this) {
    solid => '实线',
    double => '双线',
    dashed => '虚线',
    dotted => '点线',
  };

  /// 未知值回退为实线。
  static ReaderDecorationBorderStyle fromJson(Object? value) =>
      values.where((style) => style.name == value).firstOrNull ?? solid;
}

/// 单边边框，零宽表示关闭。
class ReaderDecorationBorderSide {
  /// 创建单边边框。
  const ReaderDecorationBorderSide({this.width = 0, this.color = 0xFF9CA3AF});

  /// 线宽，逻辑像素。
  final double width;

  /// ARGB 颜色。
  final int color;

  /// 序列化边框。
  Map<String, Object?> toJson() => {'width': width, 'color': color};

  /// 解析边框，异常值回退。
  factory ReaderDecorationBorderSide.fromJson(Object? raw) {
    final json = styleObject(raw);
    return ReaderDecorationBorderSide(
      width: styleNumber(json['width'], fallback: 0, min: 0, max: 6),
      color: styleColor(json['color']) ?? 0xFF9CA3AF,
    );
  }
}

/// 选中文字的排版与盒样式，空属性继承正文。
class ReaderDecorationStyle {
  /// 创建样式。
  const ReaderDecorationStyle({
    this.fontFamily,
    this.fontSizeScale = 1,
    this.fontWeight,
    this.italic,
    this.letterSpacingEm = 0,
    this.color,
    this.highlight,
    this.backgroundColor,
    this.backgroundOpacity = 1,
    this.borderRadius = 0,
    this.backgroundImagePath,
    this.backgroundImageFit = ReaderDecorationImageFit.cover,
    this.backgroundImageNineSlice,
    this.borderStyle = ReaderDecorationBorderStyle.solid,
    this.borderTop = const ReaderDecorationBorderSide(),
    this.borderRight = const ReaderDecorationBorderSide(),
    this.borderBottom = const ReaderDecorationBorderSide(),
    this.borderLeft = const ReaderDecorationBorderSide(),
    this.paddingTop = 0,
    this.paddingRight = 0,
    this.paddingBottom = 0,
    this.paddingLeft = 0,
  });

  /// 指定字族。
  final String? fontFamily;

  /// 相对正文字号。
  final double fontSizeScale;

  /// 指定字重。
  final int? fontWeight;

  /// 是否斜体。
  final bool? italic;

  /// 附加字距，以正文字号为基准。
  final double letterSpacingEm;

  /// 文字颜色。
  final int? color;

  final ReaderDecorationHighlight? highlight;

  int? get textColor =>
      highlight?.style == ReaderAnnotationStyle.tint ? highlight!.color : color;

  double get textColorOpacity => highlight?.style == ReaderAnnotationStyle.tint
      ? highlight!.effectiveOpacity
      : 1;

  /// 背景颜色。
  final int? backgroundColor;

  /// 背景透明度。
  final double backgroundOpacity;

  /// 统一圆角。
  final double borderRadius;

  /// 宿主保存的图片路径。
  final String? backgroundImagePath;

  final ReaderDecorationImageFit backgroundImageFit;
  final ReaderDecorationNineSlice? backgroundImageNineSlice;

  /// 四边共用线型。
  final ReaderDecorationBorderStyle borderStyle;

  /// 上边框。
  final ReaderDecorationBorderSide borderTop;

  /// 右边框。
  final ReaderDecorationBorderSide borderRight;

  /// 下边框。
  final ReaderDecorationBorderSide borderBottom;

  /// 左边框。
  final ReaderDecorationBorderSide borderLeft;

  /// 上绘制内边距。
  final double paddingTop;

  /// 右绘制内边距。
  final double paddingRight;

  /// 下绘制内边距。
  final double paddingBottom;

  /// 左绘制内边距。
  final double paddingLeft;

  /// 是否请求字体度量或点九背景占位。
  bool get changesMetrics =>
      fontFamily != null ||
      fontSizeScale != 1 ||
      fontWeight != null ||
      italic != null ||
      letterSpacingEm != 0 ||
      backgroundImagePath != null &&
          backgroundImageFit == ReaderDecorationImageFit.nineSlice;

  /// 可读的样式摘要。
  String get summary {
    final parts = <String>[
      if (fontFamily != null) '自定义字体',
      if (fontSizeScale != 1) '字号 ${(fontSizeScale * 100).round()}%',
      if (fontWeight != null) '字重 $fontWeight',
      if (italic == true) '斜体',
      if (letterSpacingEm != 0) '字距',
      if (color != null) '文字色',
      if (highlight != null) '高亮：${highlight!.style.label}',
      if (backgroundColor != null) '底色',
      if (backgroundImagePath != null) '背景图',
      if ([
        borderTop,
        borderRight,
        borderBottom,
        borderLeft,
      ].any((side) => side.width > 0))
        '边框',
    ];
    return parts.isEmpty ? '跟随原文' : parts.join(' · ');
  }

  /// 保存明确设置的属性，便于逐属性叠加。
  Map<String, Object?> toJson() => {
    'v': 1,
    if (fontFamily != null) 'fontFamily': fontFamily,
    if (fontSizeScale != 1) 'fontSizeScale': fontSizeScale,
    if (fontWeight != null) 'fontWeight': fontWeight,
    if (italic != null) 'italic': italic,
    if (letterSpacingEm != 0) 'letterSpacingEm': letterSpacingEm,
    if (color != null) 'color': color,
    if (highlight != null) 'highlight': highlight!.toJson(),
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
    if (backgroundColor != null || backgroundImagePath != null)
      'backgroundOpacity': backgroundOpacity,
    if (borderRadius != 0) 'borderRadius': borderRadius,
    if (backgroundImagePath != null) 'backgroundImagePath': backgroundImagePath,
    if (backgroundImagePath != null)
      'backgroundImageFit': backgroundImageFit.name,
    if (backgroundImagePath != null)
      'backgroundImageNineSlice': backgroundImageNineSlice?.toJson(),
    if (borderTop.width > 0) 'borderTop': borderTop.toJson(),
    if (borderRight.width > 0) 'borderRight': borderRight.toJson(),
    if (borderBottom.width > 0) 'borderBottom': borderBottom.toJson(),
    if (borderLeft.width > 0) 'borderLeft': borderLeft.toJson(),
    if ([
      borderTop,
      borderRight,
      borderBottom,
      borderLeft,
    ].any((side) => side.width > 0))
      'borderStyle': borderStyle.name,
    if (paddingTop != 0) 'paddingTop': paddingTop,
    if (paddingRight != 0) 'paddingRight': paddingRight,
    if (paddingBottom != 0) 'paddingBottom': paddingBottom,
    if (paddingLeft != 0) 'paddingLeft': paddingLeft,
  };

  /// 将后应用的明确属性叠加到当前样式。
  ReaderDecorationStyle merge(ReaderDecorationStyle next) =>
      ReaderDecorationStyle.fromJson({...toJson(), ...next.toJson()});

  /// 按字段创建更新后的样式；传入空值可以清除可继承属性。
  ReaderDecorationStyle withValues(Map<String, Object?> values) =>
      ReaderDecorationStyle.fromJson({...toJson(), ...values});

  /// 解析版本化样式，未知字段忽略。
  factory ReaderDecorationStyle.fromJson(Object? raw) {
    final json = styleObject(raw);
    final weight = json['fontWeight'];
    double padding(String name) =>
        styleNumber(json[name], fallback: 0, min: 0, max: 12);
    return ReaderDecorationStyle(
      fontFamily: styleString(json['fontFamily']),
      fontSizeScale: styleNumber(
        json['fontSizeScale'],
        fallback: 1,
        min: 0.75,
        max: 2,
      ),
      fontWeight: weight is int && weight >= 100 && weight <= 900
          ? weight
          : null,
      italic: json['italic'] is bool ? json['italic'] as bool : null,
      letterSpacingEm: styleNumber(
        json['letterSpacingEm'],
        fallback: 0,
        min: -0.05,
        max: 0.2,
      ),
      color: styleColor(json['color']),
      highlight: ReaderDecorationHighlight.fromJson(json['highlight']),
      backgroundColor: styleColor(json['backgroundColor']),
      backgroundOpacity: styleNumber(
        json['backgroundOpacity'],
        fallback: 1,
        min: 0,
        max: 1,
      ),
      borderRadius: styleNumber(
        json['borderRadius'],
        fallback: 0,
        min: 0,
        max: 20,
      ),
      backgroundImagePath: styleString(json['backgroundImagePath']),
      backgroundImageFit: ReaderDecorationImageFit.fromJson(
        json['backgroundImageFit'],
      ),
      backgroundImageNineSlice: ReaderDecorationNineSlice.fromJson(
        json['backgroundImageNineSlice'],
      ),
      borderStyle: ReaderDecorationBorderStyle.fromJson(json['borderStyle']),
      borderTop: ReaderDecorationBorderSide.fromJson(json['borderTop']),
      borderRight: ReaderDecorationBorderSide.fromJson(json['borderRight']),
      borderBottom: ReaderDecorationBorderSide.fromJson(json['borderBottom']),
      borderLeft: ReaderDecorationBorderSide.fromJson(json['borderLeft']),
      paddingTop: padding('paddingTop'),
      paddingRight: padding('paddingRight'),
      paddingBottom: padding('paddingBottom'),
      paddingLeft: padding('paddingLeft'),
    );
  }
}

/// 可继续编辑的装饰初始样式。
enum ReaderDecorationPreset {
  highlight(
    '高亮',
    ReaderDecorationStyle(highlight: ReaderDecorationHighlight()),
  ),

  /// 粗体强调。
  emphasis('强调', ReaderDecorationStyle(fontWeight: 700)),

  /// 斜体引用。
  quote(
    '引用',
    ReaderDecorationStyle(
      italic: true,
      color: 0xFF6B7280,
      borderLeft: ReaderDecorationBorderSide(width: 3, color: 0xFF9CA3AF),
      paddingLeft: 10,
      paddingTop: 2,
      paddingBottom: 2,
    ),
  ),

  /// 行内标签。
  tag(
    '标签',
    ReaderDecorationStyle(
      fontSizeScale: 0.85,
      fontWeight: 600,
      color: 0xFF374151,
      backgroundColor: 0xFFFDE68A,
      backgroundOpacity: 0.6,
      borderRadius: 4,
      paddingLeft: 6,
      paddingRight: 6,
      paddingTop: 2,
      paddingBottom: 2,
    ),
  ),

  /// 便签背景。
  sticky(
    '便签',
    ReaderDecorationStyle(
      backgroundColor: 0xFFFFF3C4,
      backgroundOpacity: 0.9,
      borderRadius: 6,
      borderTop: ReaderDecorationBorderSide(width: 1, color: 0xFFE0C97F),
      borderRight: ReaderDecorationBorderSide(width: 1, color: 0xFFE0C97F),
      borderBottom: ReaderDecorationBorderSide(width: 1, color: 0xFFE0C97F),
      borderLeft: ReaderDecorationBorderSide(width: 1, color: 0xFFE0C97F),
      paddingTop: 6,
      paddingRight: 6,
      paddingBottom: 6,
      paddingLeft: 6,
    ),
  );

  const ReaderDecorationPreset(this.label, this.style);

  /// 显示名称。
  final String label;

  /// 预设样式。
  final ReaderDecorationStyle style;
}
