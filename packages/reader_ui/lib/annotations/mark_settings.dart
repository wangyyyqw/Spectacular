import 'annotation.dart';

/// 划线外观与一键添加偏好。
class ReaderMarkSettings {
  /// 创建偏好；首次使用黄色实线。
  const ReaderMarkSettings({
    this.lastColor = defaultHighlightColor,
    this.lastStyle = ReaderAnnotationStyle.underline,
    this.strokeWidth = 1.8,
    this.joinBackgroundLines = false,
    this.customColors = const [],
  });

  /// 上次选用颜色。
  final int lastColor;

  /// 上次选用样式。
  final ReaderAnnotationStyle lastStyle;

  /// 全书统一线宽。
  final double strokeWidth;

  /// 同段落底色是否填满行间留白。
  final bool joinBackgroundLines;

  /// 用户保存的颜色，最多八个。
  final List<int> customColors;

  /// 创建更新后的偏好。
  ReaderMarkSettings copyWith({
    int? lastColor,
    ReaderAnnotationStyle? lastStyle,
    double? strokeWidth,
    bool? joinBackgroundLines,
    List<int>? customColors,
  }) => ReaderMarkSettings(
    lastColor: lastColor ?? this.lastColor,
    lastStyle: lastStyle ?? this.lastStyle,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    joinBackgroundLines: joinBackgroundLines ?? this.joinBackgroundLines,
    customColors: customColors == null
        ? this.customColors
        : customColors.toSet().take(8).toList(growable: false),
  );

  @override
  bool operator ==(Object other) =>
      other is ReaderMarkSettings &&
      other.lastColor == lastColor &&
      other.lastStyle == lastStyle &&
      other.strokeWidth == strokeWidth &&
      other.joinBackgroundLines == joinBackgroundLines &&
      _sameColors(other.customColors);

  bool _sameColors(List<int> colors) {
    if (colors.length != customColors.length) return false;
    for (var index = 0; index < colors.length; index++) {
      if (colors[index] != customColors[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    lastColor,
    lastStyle,
    strokeWidth,
    joinBackgroundLines,
    Object.hashAll(customColors),
  );
}
