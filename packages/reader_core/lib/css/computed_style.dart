import 'dart:ui' show Color;

/// 文本对齐（避免把 Flutter 枚举带进纯解析层）。
enum CssTextAlign { start, end, left, right, center, justify }

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

    final fontFamily =
        explicitValue('font-family')?._firstFamily() ?? parent?.fontFamily;

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

    return ComputedStyle._(
      values: values,
      hasExplicitTextColor: hasExplicitTextColor,
      fontSize: fontSize,
      lineHeight: lineHeight,
      lineHeightFactor: lineHeightFactor,
      color: color,
      fontWeight: weight,
      italic: italic,
      fontFamily: fontFamily,
      textAlign: textAlign,
      textIndent: textIndent,
      letterSpacing: letterSpacing,
      margin: margin,
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
    required this.fontFamily,
    required this.textAlign,
    required this.textIndent,
    required this.letterSpacing,
    required this.margin,
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

  /// 首选字体族（未解析 fallback 链）。
  final String? fontFamily;

  /// 文本对齐。
  final CssTextAlign textAlign;

  /// 首行缩进（逻辑像素）。
  final double textIndent;

  /// 字间距（逻辑像素，可为负）。
  final double letterSpacing;

  /// 四边 margin（逻辑像素）。
  final CssEdges margin;

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
      'indent=$textIndent, letterSpacing=$letterSpacing, margin=$margin)';

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

extension on String {
  String? _firstFamily() {
    final value = trim();
    if (value.isEmpty) {
      return null;
    }
    final first = value.split(',').first.trim();
    if (first.length >= 2 &&
        ((first.startsWith('"') && first.endsWith('"')) ||
            (first.startsWith("'") && first.endsWith("'")))) {
      return first.substring(1, first.length - 1);
    }
    return first;
  }
}
