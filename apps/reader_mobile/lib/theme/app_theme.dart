import 'package:flutter/material.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/system_ui.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

import 'app_theme_preset.dart';

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

/// 应用控件风格；旧版本和无效值均沿用现有的经典样式。
enum AppUiStyle {
  classic,
  material3;

  static const settingKey = 'app.uiStyle';

  static AppUiStyle fromSetting(String? value) =>
      AppUiStyle.values.where((style) => style.name == value).firstOrNull ??
      AppUiStyle.classic;
}

/// 让导航栈中的阅读页也能切换并保存全局界面主题。
class AppThemeScope extends InheritedWidget {
  /// 创建全局主题入口。
  const AppThemeScope({
    super.key,
    required this.mode,
    required this.onModeChanged,
    this.uiStyle = AppUiStyle.classic,
    this.onUiStyleChanged,
    required super.child,
  });

  /// 全局主题选择。
  final ThemeMode mode;

  /// 统一保存并应用主题。
  final Future<void> Function(ThemeMode) onModeChanged;

  /// 应用控件风格。
  final AppUiStyle uiStyle;

  /// 保存并应用应用控件风格。
  final Future<void> Function(AppUiStyle)? onUiStyleChanged;

  /// 读取宿主提供的全局主题入口。
  static AppThemeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeScope>();

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) =>
      mode != oldWidget.mode ||
      uiStyle != oldWidget.uiStyle ||
      onUiStyleChanged != oldWidget.onUiStyleChanged;
}

AppBarTheme _appBar(ColorScheme colors, String fontFamily, Color background) =>
    AppBarTheme(
      backgroundColor: background,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: readerSystemBarStyle(background),
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
  ColorScheme? colorScheme,
  AppUiStyle uiStyle = AppUiStyle.classic,
}) {
  final colors = colorScheme ?? preset.colorsFor(brightness);
  // 动态取色使用带种子色的表面层，软件预设保留各自的日夜背景。
  final background = colorScheme != null
      ? colors.surfaceContainerLow
      : colors.surfaceContainerLowest;
  final fallback = fontFamily == AppFonts.defaultFamily
      ? null
      : AppFonts.fallback;
  final base = ThemeData(
    useMaterial3: uiStyle == AppUiStyle.material3,
    colorScheme: colors,
    scaffoldBackgroundColor: background,
    canvasColor: colors.surface,
    dividerColor: colors.outlineVariant,
    fontFamily: fontFamily,
    fontFamilyFallback: fallback,
    appBarTheme: _appBar(colors, fontFamily, background),
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
  // 字体先确定，再生成控件主题，按钮与弹层才能使用相同文字层级。
  final styled = applyReaderUiStyle(
    base.copyWith(textTheme: _appTextTheme(base.textTheme, colors)),
  );
  return styled.copyWith(
    listTileTheme: styled.listTileTheme.copyWith(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 8,
    ),
    dialogTheme: styled.dialogTheme.copyWith(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titleTextStyle: styled.textTheme.titleLarge?.copyWith(fontSize: 18),
      contentTextStyle: styled.textTheme.bodyMedium?.copyWith(
        color: colors.onSurfaceVariant,
        height: 1.5,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.secondaryContainer,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => styled.textTheme.labelSmall?.copyWith(
          color: states.contains(WidgetState.selected)
              ? colors.onSurface
              : colors.onSurfaceVariant,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.normal,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.secondaryContainer,
      selectedIconTheme: IconThemeData(color: colors.onSecondaryContainer),
      unselectedIconTheme: IconThemeData(color: colors.onSurfaceVariant),
      useIndicator: uiStyle == AppUiStyle.material3,
    ),
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
