import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

const _ink = Color(0xFF222427);
const _secondary = Color(0xFF686C71);
const _canvas = Color(0xFFF6F6F4);
const _fill = Color(0xFFF0F1EE);
const _line = Color(0xFFE4E5E2);
const _shape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(4)),
);
const _scheme = ColorScheme.light(
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

const _appBar = AppBarTheme(
  backgroundColor: _canvas,
  foregroundColor: _ink,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  centerTitle: false,
  titleTextStyle: TextStyle(
    fontFamily: 'builtin_hei',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: _ink,
  ),
);
const _card = CardThemeData(
  color: Colors.white,
  elevation: 0,
  margin: EdgeInsets.zero,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
    side: BorderSide(color: _line),
  ),
);
const _input = InputDecorationTheme(
  filled: true,
  fillColor: Colors.white,
  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
    borderSide: BorderSide(color: _line),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
    borderSide: BorderSide(color: _line),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
    borderSide: BorderSide(color: _ink),
  ),
);
const _bottomSheet = BottomSheetThemeData(
  backgroundColor: Colors.white,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
  ),
);
const _navigation = BottomNavigationBarThemeData(
  backgroundColor: Colors.white,
  selectedItemColor: _ink,
  unselectedItemColor: _secondary,
  selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
  unselectedLabelStyle: TextStyle(fontSize: 11),
  elevation: 0,
  type: BottomNavigationBarType.fixed,
);

/// 应用界面的纸白与墨黑主题，阅读正文保留独立主题。
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: false,
    colorScheme: _scheme,
    scaffoldBackgroundColor: _canvas,
    canvasColor: Colors.white,
    dividerColor: _line,
    fontFamily: 'builtin_hei',
  );
  return _withControls(_withSurfaces(base));
}

ThemeData _withSurfaces(ThemeData base) => base.copyWith(
  appBarTheme: _appBar,
  actionIconTheme: ActionIconThemeData(
    backButtonIconBuilder: (_) => const AppIcon(AppGlyph.arrowBack),
    closeButtonIconBuilder: (_) => const AppIcon(AppGlyph.close),
  ),
  iconTheme: const IconThemeData(color: _ink, size: 22),
  textTheme: base.textTheme.apply(bodyColor: _ink, displayColor: _ink),
  cardTheme: _card,
  inputDecorationTheme: _input,
  bottomSheetTheme: _bottomSheet,
  bottomNavigationBarTheme: _navigation,
  dialogTheme: const DialogThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: _shape,
  ),
  popupMenuTheme: const PopupMenuThemeData(
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 2,
    shape: _shape,
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: _ink,
    foregroundColor: Colors.white,
    elevation: 0,
    shape: _shape,
  ),
);

ThemeData _withControls(ThemeData base) => base.copyWith(
  filledButtonTheme: FilledButtonThemeData(style: _filledStyle()),
  elevatedButtonTheme: ElevatedButtonThemeData(style: _filledStyle()),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: _ink,
      shape: _shape,
      side: const BorderSide(color: _line),
      minimumSize: const Size(44, 44),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: _ink, shape: _shape),
  ),
  chipTheme: base.chipTheme.copyWith(
    shape: _shape,
    backgroundColor: Colors.white,
    selectedColor: _fill,
    side: const BorderSide(color: _line),
    elevation: 0,
    showCheckmark: false,
    labelStyle: const TextStyle(fontSize: 13, color: _ink),
  ),
);

ButtonStyle _filledStyle() => FilledButton.styleFrom(
  backgroundColor: _ink,
  foregroundColor: Colors.white,
  shape: _shape,
  minimumSize: const Size(44, 44),
  elevation: 0,
);
