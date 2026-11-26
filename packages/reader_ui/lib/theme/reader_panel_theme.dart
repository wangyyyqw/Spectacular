import 'package:flutter/material.dart';

import 'reader_frosted_surface.dart';
import 'reader_theme.dart';
import 'reader_ui_style.dart';

/// 阅读控件沿用宿主软件主题，正文配色独立；墨水屏仍使用黑白控件。
class ReaderPanelTheme extends StatefulWidget {
  /// 创建阅读面板主题。
  const ReaderPanelTheme({super.key, required this.theme, required this.child});

  /// 当前阅读主题。
  final ReaderTheme theme;

  /// 面板内容。
  final Widget child;

  @override
  State<ReaderPanelTheme> createState() => _ReaderPanelThemeState();
}

class _ReaderPanelThemeState extends State<ReaderPanelTheme> {
  ThemeData? _base;
  ThemeData? _data;
  bool? _inkMode;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final inkMode =
        widget.theme.id == 'ink' || ReaderFrostedScope.inkModeOf(context);
    // 开关抽屉不改变软件主题；避免重复派生状态样式并通知所有控件重建。
    if (_base != base || _inkMode != inkMode) {
      _base = base;
      _inkMode = inkMode;
      final scheme = inkMode ? _inkScheme : base.colorScheme;
      _data = applyReaderUiStyle(_panelTypography(base, scheme));
    }
    return ReaderFrostedScope(
      inkMode: inkMode,
      child: Theme(data: _data!, child: widget.child),
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
