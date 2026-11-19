import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

const _ink = Color(0xFF222427);
const _secondary = Color(0xFF686C71);
const _canvas = Color(0xFFF6F6F4);
const _fill = Color(0xFFF0F1EE);
const _line = Color(0xFFE4E5E2);
const _radius = BorderRadius.all(Radius.circular(4));
const _shape = RoundedRectangleBorder(borderRadius: _radius);
const _dayScheme = ColorScheme.light(
  primary: _ink,
  onPrimary: Colors.white,
  primaryContainer: _fill,
  onPrimaryContainer: _ink,
  secondary: _secondary,
  onSecondary: Colors.white,
  secondaryContainer: _fill,
  onSecondaryContainer: _ink,
  tertiary: _secondary,
  onTertiary: Colors.white,
  tertiaryContainer: _fill,
  onTertiaryContainer: _ink,
  error: Color(0xFFB34338),
  onError: Colors.white,
  errorContainer: Color(0xFFF7ECE9),
  onErrorContainer: Color(0xFF80352E),
  surface: Colors.white,
  onSurface: _ink,
  onSurfaceVariant: _secondary,
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: _canvas,
  surfaceContainer: _fill,
  surfaceContainerHigh: _fill,
  surfaceContainerHighest: _fill,
  outline: Color(0xFFB8BBB6),
  outlineVariant: _line,
  surfaceTint: Colors.transparent,
  inverseSurface: _ink,
  onInverseSurface: Colors.white,
  inversePrimary: Colors.white,
);

const _nightCanvas = Color(0xFF1B1D1F);
const _nightText = Color(0xFFE7E8E4);
const _nightSecondary = Color(0xFFB1B4B4);
const _nightFill = Color(0xFF2B2D30);
const _nightScheme = ColorScheme.dark(
  primary: _nightText,
  onPrimary: _ink,
  primaryContainer: _nightFill,
  onPrimaryContainer: _nightText,
  secondary: _nightSecondary,
  onSecondary: _ink,
  secondaryContainer: _nightFill,
  onSecondaryContainer: _nightText,
  tertiary: _nightSecondary,
  onTertiary: _ink,
  tertiaryContainer: _nightFill,
  onTertiaryContainer: _nightText,
  error: Color(0xFFF0AAA0),
  onError: Color(0xFF4C211C),
  errorContainer: Color(0xFF442B28),
  onErrorContainer: Color(0xFFFFDAD4),
  surface: _ink,
  onSurface: _nightText,
  onSurfaceVariant: _nightSecondary,
  surfaceContainerLowest: _nightCanvas,
  surfaceContainerLow: _nightCanvas,
  surfaceContainer: _nightFill,
  surfaceContainerHigh: Color(0xFF303236),
  surfaceContainerHighest: Color(0xFF35383B),
  outline: Color(0xFF838783),
  outlineVariant: Color(0xFF3B3E42),
  surfaceTint: Colors.transparent,
  inverseSurface: _nightText,
  onInverseSurface: _ink,
  inversePrimary: _ink,
);

AppBarTheme _appBar(ColorScheme colors) => AppBarTheme(
  backgroundColor: colors.surfaceContainerLow,
  foregroundColor: colors.onSurface,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  centerTitle: false,
  titleTextStyle: TextStyle(
    fontFamily: 'builtin_hei',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: colors.onSurface,
  ),
);

InputDecorationTheme _input(ColorScheme colors) {
  final border = OutlineInputBorder(
    borderRadius: _radius,
    borderSide: BorderSide(color: colors.outlineVariant),
  );
  return InputDecorationTheme(
    filled: true,
    fillColor: colors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colors.primary),
    ),
  );
}

/// 应用界面的纸白与墨黑主题，阅读正文保留独立主题。
ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final colors = brightness == Brightness.dark ? _nightScheme : _dayScheme;
  final base = ThemeData(
    useMaterial3: false,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surfaceContainerLow,
    canvasColor: colors.surface,
    dividerColor: colors.outlineVariant,
    fontFamily: 'builtin_hei',
    appBarTheme: _appBar(colors),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const AppIcon(AppGlyph.arrowBack),
      closeButtonIconBuilder: (_) => const AppIcon(AppGlyph.close),
    ),
    iconTheme: IconThemeData(color: colors.onSurface, size: 22),
    inputDecorationTheme: _input(colors),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: colors.surface,
      selectedItemColor: colors.onSurface,
      unselectedItemColor: colors.onSurfaceVariant,
      selectedLabelStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: const TextStyle(fontSize: 11),
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
  );
  return _withControls(_withSurfaces(base, colors), colors);
}

ThemeData _withSurfaces(ThemeData base, ColorScheme colors) => base.copyWith(
  textTheme: base.textTheme.apply(
    bodyColor: colors.onSurface,
    displayColor: colors.onSurface,
  ),
  cardTheme: CardThemeData(
    color: colors.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: _shape.copyWith(side: BorderSide(color: colors.outlineVariant)),
  ),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: colors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: colors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: _shape,
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: colors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 2,
    shape: _shape,
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: colors.primary,
    foregroundColor: colors.onPrimary,
    elevation: 0,
    shape: _shape,
  ),
);

ThemeData _withControls(ThemeData base, ColorScheme colors) => base.copyWith(
  filledButtonTheme: FilledButtonThemeData(style: _filledStyle(colors)),
  elevatedButtonTheme: ElevatedButtonThemeData(style: _filledStyle(colors)),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: colors.primary,
      shape: _shape,
      side: BorderSide(color: colors.outlineVariant),
      minimumSize: const Size(44, 44),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: colors.primary, shape: _shape),
  ),
  chipTheme: base.chipTheme.copyWith(
    shape: _shape,
    backgroundColor: colors.surface,
    selectedColor: colors.primaryContainer,
    side: BorderSide(color: colors.outlineVariant),
    elevation: 0,
    showCheckmark: false,
    labelStyle: TextStyle(fontSize: 13, color: colors.onSurface),
  ),
);

ButtonStyle _filledStyle(ColorScheme colors) => FilledButton.styleFrom(
  backgroundColor: colors.primary,
  foregroundColor: colors.onPrimary,
  shape: _shape,
  minimumSize: const Size(44, 44),
  elevation: 0,
);
