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
  static const Color surface = Color(0xFFFFFFFF);

  /// 主文字。
  static const Color text = Color(0xFF333333);

  /// 次级文字与图标。
  static const Color textSecondary = Color(0xFF666666);

  /// 弱化文字。
  static const Color muted = Color(0xFF999999);

  /// 更弱的提示文字。
  static const Color faint = Color(0xFFCCCCCC);

  /// 页签与列表分隔线。
  static const Color divider = Color(0xFFF5F5F5);

  /// 拖拽条。
  static const Color handle = Color(0xFFE0E0E0);

  /// 当前目录项底色。
  static const Color selectedRow = Color(0xFFF5F6F7);

  /// 主题选中圆环。
  static const Color selectedRing = Color(0xFF5EC27D);

  /// 背景选项边框。
  static const Color optionBorder = Color(0xFFE5E5E5);

  /// 背景选项底板。
  static const Color optionFill = Color(0xFFF5F5F5);

  /// 抽屉底色：浅色阅读主题保持参考稿纯白，暗色主题跟随正文表面。
  static Color surfaceOf(ThemeData theme) =>
      theme.brightness == Brightness.dark ? theme.colorScheme.surface : surface;

  /// 主文字。
  static Color textOf(ThemeData theme) =>
      theme.brightness == Brightness.dark ? theme.colorScheme.onSurface : text;

  /// 次级文字。
  static Color secondaryOf(ThemeData theme) =>
      theme.brightness == Brightness.dark
      ? theme.colorScheme.onSurfaceVariant
      : textSecondary;

  /// 弱化文字。
  static Color mutedOf(ThemeData theme) =>
      theme.brightness == Brightness.dark ? theme.colorScheme.outline : muted;

  /// 更弱的图标与提示。
  static Color faintOf(ThemeData theme) => theme.brightness == Brightness.dark
      ? theme.colorScheme.outlineVariant
      : faint;

  /// 分隔线。
  static Color dividerOf(ThemeData theme) => theme.brightness == Brightness.dark
      ? theme.colorScheme.outlineVariant
      : divider;

  /// 当前目录项底色。
  static Color selectedRowOf(ThemeData theme) =>
      theme.brightness == Brightness.dark
      ? theme.colorScheme.surfaceContainerLow
      : selectedRow;

  /// 背景选项边框。
  static Color optionBorderOf(ThemeData theme) =>
      theme.brightness == Brightness.dark
      ? theme.colorScheme.outlineVariant
      : optionBorder;

  /// 背景选项底板。
  static Color optionFillOf(ThemeData theme) =>
      theme.brightness == Brightness.dark
      ? theme.colorScheme.surfaceContainerLow
      : optionFill;
}
