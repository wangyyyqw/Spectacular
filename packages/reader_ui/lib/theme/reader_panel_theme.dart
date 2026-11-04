import 'package:flutter/material.dart';

import 'reader_theme.dart';

/// 把阅读主题映射为菜单、抽屉和编辑弹层使用的 [ThemeData]。
///
/// 阅读页的面板背景必须跟随正文主题，否则夜间模式下白色弹层会造成
/// 明显刺眼和视觉断层（设计稿 `.drawer-panel { background: var(--bg); }`）。
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
    final dark = theme.background.computeLuminance() < 0.35;
    final brightness = dark ? Brightness.dark : Brightness.light;
    final filledSurface = Color.alphaBlend(theme.fill, theme.background);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: theme.accent,
          brightness: brightness,
        ).copyWith(
          primary: theme.accent,
          onPrimary: theme.accent.computeLuminance() > 0.5
              ? Colors.black
              : Colors.white,
          surface: theme.background,
          onSurface: theme.text,
          surfaceTint: Colors.transparent,
          surfaceContainerLowest: theme.background,
          surfaceContainerLow: filledSurface,
          surfaceContainer: filledSurface,
          surfaceContainerHigh: filledSurface,
          surfaceContainerHighest: filledSurface,
          onSurfaceVariant: Color.alphaBlend(theme.sub, theme.background),
          outline: Color.alphaBlend(
            theme.text.withValues(alpha: 0.38),
            theme.background,
          ),
          outlineVariant: Color.alphaBlend(
            theme.text.withValues(alpha: 0.16),
            theme.background,
          ),
        );
    return Theme(
      data: base.copyWith(
        brightness: brightness,
        colorScheme: scheme,
        canvasColor: theme.background,
        scaffoldBackgroundColor: theme.background,
        dividerColor: scheme.outlineVariant,
        iconTheme: base.iconTheme.copyWith(color: theme.text),
        textTheme: base.textTheme.apply(
          bodyColor: theme.text,
          displayColor: theme.text,
        ),
        dialogTheme: base.dialogTheme.copyWith(
          backgroundColor: theme.background,
        ),
        bottomSheetTheme: base.bottomSheetTheme.copyWith(
          backgroundColor: theme.background,
        ),
      ),
      child: child,
    );
  }
}
