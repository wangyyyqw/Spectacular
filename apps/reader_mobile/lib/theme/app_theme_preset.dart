import 'package:flutter/material.dart';

/// 软件配色预设；日夜模式与正文阅读配色分别管理。
class AppThemePreset {
  const AppThemePreset({
    required this.id,
    required this.name,
    required this.light,
    required this.dark,
  });

  final String id;
  final String name;
  final ColorScheme light;
  final ColorScheme dark;

  ColorScheme colorsFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 首套软件主题；后续预设复用同一套控件语义。
  static const clearBlue = AppThemePreset(
    id: 'clear_blue',
    name: '清蓝',
    light: ColorScheme.light(
      primary: Color(0xFF0A59F7),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFEAF0FF),
      onPrimaryContainer: Color(0xFF174AB5),
      secondary: Color(0xFF686B73),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFEAF0FF),
      onSecondaryContainer: Color(0xFF174AB5),
      tertiary: Color(0xFF686B73),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFF2F3F5),
      onTertiaryContainer: Color(0xFF1D1D1F),
      error: Color(0xFFB34338),
      onError: Colors.white,
      errorContainer: Color(0xFFF7ECE9),
      onErrorContainer: Color(0xFF80352E),
      surface: Colors.white,
      onSurface: Color(0xFF1D1D1F),
      onSurfaceVariant: Color(0xFF686B73),
      surfaceContainerLowest: Color(0xFFF2F3F5),
      surfaceContainerLow: Color(0xFFF7F8FA),
      surfaceContainer: Color(0xFFF2F3F5),
      surfaceContainerHigh: Color(0xFFECEEF2),
      surfaceContainerHighest: Color(0xFFE2E4E8),
      surfaceDim: Color(0xFFF2F3F5),
      surfaceBright: Colors.white,
      outline: Color(0xFF858891),
      outlineVariant: Color(0xFFE2E4E8),
      surfaceTint: Colors.transparent,
      inverseSurface: Color(0xFF1D1D1F),
      onInverseSurface: Color(0xFFE4E4E7),
      inversePrimary: Color(0xFF7EA8FF),
    ),
    dark: ColorScheme.dark(
      primary: Color(0xFF7EA8FF),
      onPrimary: Color(0xFF101C33),
      primaryContainer: Color(0xFF172B4D),
      onPrimaryContainer: Color(0xFFC0D4FF),
      secondary: Color(0xFFA1A1AA),
      onSecondary: Color(0xFF191919),
      secondaryContainer: Color(0xFF172B4D),
      onSecondaryContainer: Color(0xFFC0D4FF),
      tertiary: Color(0xFFA1A1AA),
      onTertiary: Color(0xFF191919),
      tertiaryContainer: Color(0xFF232323),
      onTertiaryContainer: Color(0xFFE4E4E7),
      error: Color(0xFFF0AAA0),
      onError: Color(0xFF4C211C),
      errorContainer: Color(0xFF442B28),
      onErrorContainer: Color(0xFFFFDAD4),
      surface: Color(0xFF191919),
      onSurface: Color(0xFFE4E4E7),
      onSurfaceVariant: Color(0xFFA1A1AA),
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Color(0xFF232323),
      surfaceContainer: Color(0xFF292929),
      surfaceContainerHigh: Color(0xFF2F2F31),
      surfaceContainerHighest: Color(0xFF353538),
      surfaceDim: Colors.black,
      surfaceBright: Color(0xFF353538),
      outline: Color(0xFF85858D),
      outlineVariant: Color(0xFF353538),
      surfaceTint: Colors.transparent,
      inverseSurface: Color(0xFFE4E4E7),
      onInverseSurface: Color(0xFF1D1D1F),
      inversePrimary: Color(0xFF0A59F7),
    ),
  );
}
