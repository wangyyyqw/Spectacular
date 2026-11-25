import 'package:flutter/material.dart';

import 'reader_frosted_surface.dart';
import 'reader_theme.dart';
import 'reader_ui_style.dart';

const _shape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(4)),
);

/// 只覆盖阅读面板；继承主题可随菜单捕获到独立的弹层路由。
class ReaderPanelColorScope extends InheritedTheme {
  const ReaderPanelColorScope({
    super.key,
    required this.scheme,
    required super.child,
  });

  final ColorScheme? scheme;

  static ColorScheme? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ReaderPanelColorScope>()
      ?.scheme;

  @override
  bool updateShouldNotify(ReaderPanelColorScope oldWidget) =>
      scheme != oldWidget.scheme;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      ReaderPanelColorScope(scheme: scheme, child: child);
}

/// 把正文主题映射为菜单和弹层，保留背景取色与夜间面板亮度。
class ReaderPanelTheme extends StatelessWidget {
  /// 创建阅读面板主题。
  const ReaderPanelTheme({super.key, required this.theme, required this.child});

  /// 当前阅读主题。
  final ReaderTheme theme;

  /// 面板内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 选区菜单使用固定深色底板与浅色按钮，不能只覆盖底板的背景取色。
    final override = theme.id == 'ink' || theme.id == 'selection'
        ? null
        : ReaderPanelColorScope.maybeOf(context);
    final scheme = override ?? _panelScheme(theme);
    final panel = ReaderTheme.custom(
      background: scheme.surface,
      text: scheme.onSurface,
    );
    var data = applyReaderUiStyle(
      _panelTypography(Theme.of(context), panel, scheme),
    );
    data = _panelSurfaces(data, panel, scheme);
    data = _panelButtons(data, panel, scheme);
    data = _panelInputs(data, panel, scheme);
    return ReaderFrostedScope(
      inkMode: theme.id == 'ink',
      child: Theme(data: data, child: child),
    );
  }
}

ColorScheme _panelScheme(ReaderTheme theme) {
  final dark = theme.background.computeLuminance() < 0.35;
  // 夜间阅读页可以是纯黑或深色主题，面板提高一个亮度层级，避免菜单和注释
  // 与正文融为一体；正文本身仍使用 [ReaderTheme.background]。
  final background = dark && theme.id != 'selection' && theme.id != 'ink'
      ? Color.alphaBlend(const Color(0x1AFFFFFF), theme.background)
      : theme.background;
  final fill = Color.alphaBlend(theme.fill, background);
  return ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: theme.text,
    onPrimary: background,
    primaryContainer: fill,
    onPrimaryContainer: theme.text,
    secondary: theme.text,
    onSecondary: background,
    secondaryContainer: fill,
    onSecondaryContainer: theme.text,
    tertiary: theme.text,
    onTertiary: background,
    tertiaryContainer: fill,
    onTertiaryContainer: theme.text,
    error: dark ? const Color(0xFFF0AAA0) : const Color(0xFFB34338),
    onError: dark ? Colors.black : Colors.white,
    surface: background,
    onSurface: theme.text,
    inverseSurface: theme.text,
    onInverseSurface: background,
    inversePrimary: background,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: background,
    surfaceContainerLow: fill,
    surfaceContainer: fill,
    surfaceContainerHigh: fill,
    surfaceContainerHighest: fill,
    onSurfaceVariant: Color.alphaBlend(theme.sub, background),
    outline: Color.alphaBlend(theme.text.withValues(alpha: 0.38), background),
    outlineVariant: Color.alphaBlend(theme.line, background),
  );
}

ThemeData _panelTypography(
  ThemeData base,
  ReaderTheme theme,
  ColorScheme scheme,
) => base.copyWith(
  brightness: scheme.brightness,
  colorScheme: scheme,
  canvasColor: scheme.surface,
  scaffoldBackgroundColor: scheme.surface,
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
    titleTextStyle: base.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      color: theme.text,
    ),
    subtitleTextStyle: base.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      color: scheme.onSurfaceVariant,
    ),
  ),
  appBarTheme: base.appBarTheme.copyWith(
    backgroundColor: scheme.surface,
    foregroundColor: theme.text,
    surfaceTintColor: Colors.transparent,
  ),
);

ThemeData _panelSurfaces(
  ThemeData base,
  ReaderTheme theme,
  ColorScheme scheme,
) {
  final cardRadius = base.useMaterial3 ? 12.0 : 4.0;
  final dialogRadius = base.useMaterial3 ? 28.0 : 24.0;
  final sheetRadius = base.useMaterial3 ? 28.0 : 24.0;
  final popupRadius = base.useMaterial3 ? 12.0 : 16.0;
  return base.copyWith(
    cardTheme: base.cardTheme.copyWith(
      color: theme.background,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: theme.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(dialogRadius),
      ),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: theme.background,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(sheetRadius)),
      ),
      constraints: const BoxConstraints(maxWidth: 680),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: theme.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(popupRadius),
      ),
    ),
  );
}

ThemeData _panelButtons(ThemeData base, ReaderTheme theme, ColorScheme scheme) {
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(base.useMaterial3 ? 20 : 4),
  );
  final style = FilledButton.styleFrom(
    backgroundColor: scheme.primary,
    foregroundColor: scheme.onPrimary,
    elevation: 0,
    shape: shape,
  );
  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: style),
    elevatedButtonTheme: ElevatedButtonThemeData(style: style),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: theme.line),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        shape: shape,
      ),
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
          borderRadius: BorderRadius.circular(base.useMaterial3 ? 12 : 4),
          borderSide: BorderSide(color: scheme.primary),
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
