import 'package:flutter/material.dart';

/// 阅读菜单抽屉的视觉常量，对齐参考稿的白色面板与灰色分隔。
abstract final class ReaderDrawerStyle {
  /// 搜索框使用较高的暗色表面，配合阴影保持夜间层次。
  static Color searchSurfaceOf(ThemeData theme) =>
      theme.brightness == Brightness.dark
      ? theme.colorScheme.surfaceContainerHighest
      : theme.colorScheme.surface;

  /// 搜索框投影。
  static Color searchShadowOf(ThemeData theme) =>
      (theme.brightness == Brightness.dark ? Colors.white : Colors.black)
          .withValues(alpha: theme.brightness == Brightness.dark ? .24 : .28);

  /// 面板底色。
  static Color surfaceOf(ThemeData theme) => theme.colorScheme.surface;

  /// 主文字。
  static Color textOf(ThemeData theme) => theme.colorScheme.onSurface;

  /// 次级文字。
  static Color secondaryOf(ThemeData theme) =>
      theme.colorScheme.onSurfaceVariant;

  /// 弱化文字。
  static Color mutedOf(ThemeData theme) => theme.colorScheme.onSurfaceVariant;

  /// 更弱的图标与提示。
  static Color faintOf(ThemeData theme) => theme.colorScheme.outline;

  /// 分隔线。
  static Color dividerOf(ThemeData theme) => theme.colorScheme.outlineVariant;

  /// 当前目录项底色。
  static Color selectedRowOf(ThemeData theme) =>
      theme.colorScheme.surfaceContainerLow;

  /// 主题选中圆环。
  static Color selectedRingOf(ThemeData theme) => theme.colorScheme.onSurface;

  /// 背景选项边框。
  static Color optionBorderOf(ThemeData theme) =>
      theme.colorScheme.outlineVariant;

  /// 背景选项底板。
  static Color optionFillOf(ThemeData theme) =>
      theme.colorScheme.surfaceContainerLow;
}
