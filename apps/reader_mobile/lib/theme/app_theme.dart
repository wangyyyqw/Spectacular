import 'package:flutter/material.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/system_ui.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

import 'app_theme_preset.dart';

export 'package:reader_ui/theme/app_semantic_colors.dart';
export 'app_theme_preset.dart';

/// 应用界面的字体约定，不作用于书籍正文。
abstract final class AppFonts {
  /// 默认使用内置思源宋体。
  static const String defaultFamily = FontFamilyAliases.song;

  /// 应用字体偏好的设置键。
  static const String settingKey = 'app.fontFamily';

  /// 自定义字体缺字时回退到内置思源宋体。
  static const List<String> fallback = <String>[defaultFamily];
}

/// 让导航栈中的阅读页也能切换并保存全局界面主题与配色方案。
class AppThemeScope extends InheritedWidget {
  /// 创建全局主题入口。
  const AppThemeScope({
    super.key,
    required this.mode,
    required this.onModeChanged,
    this.preset = AppThemePreset.clearBlue,
    this.onPresetChanged,
    required super.child,
  });

  /// 全局主题选择。
  final ThemeMode mode;

  /// 统一保存并应用主题。
  final Future<void> Function(ThemeMode) onModeChanged;

  /// 全局配色预设。
  final AppThemePreset preset;

  /// 统一保存并应用配色预设。
  final Future<void> Function(AppThemePreset)? onPresetChanged;

  /// 读取宿主提供的全局主题入口。
  static AppThemeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeScope>();

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) =>
      mode != oldWidget.mode || preset.id != oldWidget.preset.id;
}

AppBarTheme _appBar(ColorScheme colors, String fontFamily) => AppBarTheme(
  backgroundColor: colors.surfaceContainerLowest,
  foregroundColor: colors.onSurface,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  systemOverlayStyle: readerSystemBarStyle(colors.surfaceContainerLowest),
  centerTitle: false,
  titleTextStyle: TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamily == AppFonts.defaultFamily
        ? null
        : AppFonts.fallback,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: colors.onSurface,
  ),
);

/// 软件界面使用成对的日夜配色，正文保留独立阅读主题。
ThemeData buildAppTheme({
  Brightness brightness = Brightness.light,
  AppThemePreset preset = AppThemePreset.clearBlue,
  String fontFamily = AppFonts.defaultFamily,
}) {
  final colors = preset.colorsFor(brightness);
  final semantics = preset.semanticsFor(brightness);
  final fallback = fontFamily == AppFonts.defaultFamily
      ? null
      : AppFonts.fallback;
  final base = ThemeData(
    useMaterial3: false,
    colorScheme: colors,
    extensions: <ThemeExtension<dynamic>>[semantics],
    scaffoldBackgroundColor: colors.surfaceContainerLowest,
    canvasColor: colors.surface,
    dividerColor: colors.outlineVariant,
    fontFamily: fontFamily,
    fontFamilyFallback: fallback,
    appBarTheme: _appBar(colors, fontFamily),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const AppIcon(AppGlyph.arrowBack),
      closeButtonIconBuilder: (_) => const AppIcon(AppGlyph.close),
    ),
    iconTheme: IconThemeData(color: colors.onSurface, size: 22),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: colors.surface,
      selectedItemColor: colors.primary,
      unselectedItemColor: colors.onSurfaceVariant,
      selectedLabelStyle: TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fallback,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fallback,
        fontSize: 11,
      ),
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
  );
  return applyReaderUiStyle(
    base.copyWith(textTheme: _appTextTheme(base.textTheme, colors)),
  );
}

TextTheme _appTextTheme(TextTheme base, ColorScheme colors) {
  // 以书架书名和作者为基准，所有界面共用 14 / 12 号文字层级。
  final primary = base.bodyMedium!.copyWith(
    fontSize: 14,
    color: colors.onSurface,
  );
  final secondary = base.bodySmall!.copyWith(
    fontSize: 12,
    color: colors.onSurfaceVariant,
  );
  final title = primary.copyWith(fontWeight: FontWeight.w600);
  return base
      .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface)
      .copyWith(
        titleLarge: title,
        titleMedium: primary,
        titleSmall: title,
        bodyLarge: primary,
        bodyMedium: primary,
        bodySmall: secondary,
        labelLarge: primary.copyWith(fontWeight: FontWeight.w500),
        labelMedium: secondary,
        labelSmall: secondary.copyWith(fontSize: 11),
      );
}
