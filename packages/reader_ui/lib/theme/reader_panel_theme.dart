import 'package:flutter/material.dart';

import 'reader_frosted_surface.dart';
import 'reader_theme.dart';
import 'reader_ui_style.dart';

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
    data = data.copyWith(
      inputDecorationTheme: data.inputDecorationTheme.copyWith(
        fillColor: scheme.surfaceContainerLow,
      ),
    );
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
