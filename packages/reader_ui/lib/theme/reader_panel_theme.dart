import 'package:flutter/material.dart';

import 'reader_frosted_surface.dart';
import 'reader_theme.dart';

const _shape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(4)),
);

/// 把正文主题映射为菜单、抽屉和编辑弹层；夜间弹层保持同一背景。
class ReaderPanelTheme extends StatelessWidget {
  /// 创建阅读面板主题。
  const ReaderPanelTheme({super.key, required this.theme, required this.child});

  /// 当前阅读主题。
  final ReaderTheme theme;

  /// 面板内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = _panelScheme(theme);
    var data = _panelTypography(Theme.of(context), theme, scheme);
    data = _panelSurfaces(data, theme, scheme);
    data = _panelButtons(data, theme);
    data = _panelInputs(data, theme, scheme);
    return ReaderFrostedScope(
      inkMode: theme.id == 'ink',
      child: Theme(data: data, child: child),
    );
  }
}

ColorScheme _panelScheme(ReaderTheme theme) {
  final dark = theme.background.computeLuminance() < 0.35;
  final fill = Color.alphaBlend(theme.fill, theme.background);
  return ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: theme.text,
    onPrimary: theme.background,
    primaryContainer: fill,
    onPrimaryContainer: theme.text,
    secondary: theme.text,
    onSecondary: theme.background,
    secondaryContainer: fill,
    onSecondaryContainer: theme.text,
    tertiary: theme.text,
    onTertiary: theme.background,
    tertiaryContainer: fill,
    onTertiaryContainer: theme.text,
    error: dark ? const Color(0xFFF0AAA0) : const Color(0xFFB34338),
    onError: dark ? Colors.black : Colors.white,
    surface: theme.background,
    onSurface: theme.text,
    inverseSurface: theme.text,
    onInverseSurface: theme.background,
    inversePrimary: theme.background,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: theme.background,
    surfaceContainerLow: fill,
    surfaceContainer: fill,
    surfaceContainerHigh: fill,
    surfaceContainerHighest: fill,
    onSurfaceVariant: Color.alphaBlend(theme.sub, theme.background),
    outline: Color.alphaBlend(
      theme.text.withValues(alpha: 0.38),
      theme.background,
    ),
    outlineVariant: Color.alphaBlend(theme.line, theme.background),
  );
}

ThemeData _panelTypography(
  ThemeData base,
  ReaderTheme theme,
  ColorScheme scheme,
) => base.copyWith(
  brightness: scheme.brightness,
  colorScheme: scheme,
  canvasColor: theme.background,
  scaffoldBackgroundColor: theme.background,
  dividerColor: scheme.outlineVariant,
  iconTheme: base.iconTheme.copyWith(color: theme.text),
  textTheme: base.textTheme
      .apply(bodyColor: theme.text, displayColor: theme.text)
      .copyWith(
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
  listTileTheme: base.listTileTheme.copyWith(
    titleTextStyle: base.textTheme.bodyMedium?.copyWith(color: theme.text),
    subtitleTextStyle: base.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    ),
  ),
  appBarTheme: base.appBarTheme.copyWith(
    backgroundColor: theme.background,
    foregroundColor: theme.text,
    surfaceTintColor: Colors.transparent,
  ),
);

ThemeData _panelSurfaces(
  ThemeData base,
  ReaderTheme theme,
  ColorScheme scheme,
) => base.copyWith(
  cardTheme: base.cardTheme.copyWith(
    color: theme.background,
    elevation: 0,
    shape: _shape.copyWith(side: BorderSide(color: scheme.outlineVariant)),
  ),
  dialogTheme: base.dialogTheme.copyWith(
    backgroundColor: theme.background,
    surfaceTintColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(24)),
    ),
  ),
  bottomSheetTheme: base.bottomSheetTheme.copyWith(
    backgroundColor: theme.background,
    surfaceTintColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
  ),
  popupMenuTheme: base.popupMenuTheme.copyWith(
    color: theme.background,
    surfaceTintColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
);

ThemeData _panelButtons(ThemeData base, ReaderTheme theme) {
  final style = FilledButton.styleFrom(
    backgroundColor: theme.text,
    foregroundColor: theme.background,
    elevation: 0,
    shape: _shape,
  );
  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: style),
    elevatedButtonTheme: ElevatedButtonThemeData(style: style),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.text,
        side: BorderSide(color: theme.line),
        shape: _shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: theme.text, shape: _shape),
    ),
  );
}

ThemeData _panelInputs(ThemeData base, ReaderTheme theme, ColorScheme scheme) =>
    base.copyWith(
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(color: theme.text),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          borderSide: BorderSide(color: theme.text),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: scheme.surfaceContainerLow,
        backgroundColor: theme.background,
        labelStyle: TextStyle(color: theme.text),
        shape: _shape,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    );
