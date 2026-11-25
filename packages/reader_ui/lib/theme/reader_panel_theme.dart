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

/// 阅读控件沿用宿主软件主题，正文配色独立；墨水屏仍使用黑白控件。
class ReaderPanelTheme extends StatelessWidget {
  /// 创建阅读面板主题。
  const ReaderPanelTheme({super.key, required this.theme, required this.child});

  /// 当前阅读主题。
  final ReaderTheme theme;

  /// 面板内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final inkMode = theme.id == 'ink' || ReaderFrostedScope.inkModeOf(context);
    final override = ReaderPanelColorScope.maybeOf(context);
    final scheme = inkMode ? _inkScheme : override ?? base.colorScheme;
    final data = applyReaderUiStyle(_panelTypography(base, scheme));
    return ReaderFrostedScope(
      inkMode: inkMode,
      child: Theme(data: data, child: child),
    );
  }
}

const _inkScheme = ColorScheme.light(
  primary: Colors.black,
  onPrimary: Colors.white,
  primaryContainer: Colors.white,
  onPrimaryContainer: Colors.black,
  secondary: Colors.black,
  onSecondary: Colors.white,
  secondaryContainer: Colors.white,
  onSecondaryContainer: Colors.black,
  tertiary: Colors.black,
  onTertiary: Colors.white,
  tertiaryContainer: Colors.white,
  onTertiaryContainer: Colors.black,
  error: Colors.black,
  onError: Colors.white,
  errorContainer: Colors.white,
  onErrorContainer: Colors.black,
  surface: Colors.white,
  onSurface: Colors.black,
  onSurfaceVariant: Colors.black,
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: Colors.white,
  surfaceContainer: Colors.white,
  surfaceContainerHigh: Colors.white,
  surfaceContainerHighest: Colors.white,
  outline: Colors.black,
  outlineVariant: Colors.black,
  inverseSurface: Colors.black,
  onInverseSurface: Colors.white,
  inversePrimary: Colors.white,
  surfaceTint: Colors.transparent,
);

ThemeData _panelTypography(ThemeData base, ColorScheme scheme) => base.copyWith(
  brightness: scheme.brightness,
  colorScheme: scheme,
  canvasColor: scheme.surface,
  scaffoldBackgroundColor: scheme.surface,
  dividerColor: scheme.outlineVariant,
  iconTheme: base.iconTheme.copyWith(color: scheme.onSurface),
  textTheme: base.textTheme
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
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
      color: scheme.onSurface,
    ),
    subtitleTextStyle: base.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      color: scheme.onSurfaceVariant,
    ),
  ),
  appBarTheme: base.appBarTheme.copyWith(
    backgroundColor: scheme.surface,
    foregroundColor: scheme.onSurface,
    surfaceTintColor: Colors.transparent,
  ),
);
