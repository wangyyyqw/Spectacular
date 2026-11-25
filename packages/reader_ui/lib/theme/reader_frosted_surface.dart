import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'reader_ui_style.dart';

/// 阅读控件共用的实色底板：完全不透明，保留柔和高光和阴影，不采样背景。
class ReaderFrostedSurface extends StatelessWidget {
  const ReaderFrostedSurface({
    super.key,
    required this.child,
    this.radius = ReaderUiStyle.cardCorner,
    this.bottomRadius,
    this.inkMode = false,
    this.inset = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final double? bottomRadius;
  final bool inkMode;

  /// 只缩小可见底板，保留内容的触控区域。
  final EdgeInsets inset;

  /// 抽屉内的内容面板共用凝光底板，独立显示时保留原来的背景色。
  static Color panelColorOf(BuildContext context, {Color? fallback}) =>
      context.dependOnInheritedWidgetOfExactType<_FrostedPanelContent>() != null
      ? Colors.transparent
      : fallback ?? Theme.of(context).colorScheme.surface;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassTheme(
      data: GlassThemeData.classic(brightness: scheme.brightness),
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Padding(
              padding: inset,
              child: GlassContainer.card(
                padding: EdgeInsets.zero,
                shape: LiquidVerticalRoundedRectangle(
                  topRadius: radius,
                  bottomRadius: bottomRadius ?? radius,
                ),
                useOwnLayer: true,
                quality: GlassQuality.minimal,
                surfaceStyle:
                    inkMode ||
                        ReaderFrostedScope.inkModeOf(context) ||
                        MediaQuery.highContrastOf(context)
                    ? GlassSurfaceStyle.solid
                    : GlassSurfaceStyle.glass,
                color: scheme.surface.withValues(alpha: 1),
                settings: LiquidGlassSettings(
                  glassColor: scheme.surface.withValues(alpha: 1),
                  blur: 0,
                  thickness: 6,
                  refractiveIndex: 1,
                  chromaticAberration: 0,
                  lightIntensity: 0.12,
                  saturation: 1,
                  shadow: const [
                    BoxShadow(
                      color: Color(0x24000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
              ),
            ),
          ),
          _FrostedPanelContent(
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ],
      ),
    );
  }
}

/// 随弹层路由捕获的材质偏好，墨水屏内的二级弹窗也保持实色。
class ReaderFrostedScope extends InheritedTheme {
  const ReaderFrostedScope({
    super.key,
    required this.inkMode,
    required super.child,
  });

  final bool inkMode;

  static bool inkModeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ReaderFrostedScope>()
          ?.inkMode ??
      false;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      ReaderFrostedScope(inkMode: inkMode, child: child);

  @override
  bool updateShouldNotify(ReaderFrostedScope oldWidget) =>
      inkMode != oldWidget.inkMode;
}

class _FrostedPanelContent extends InheritedWidget {
  const _FrostedPanelContent({required super.child});

  @override
  bool updateShouldNotify(_FrostedPanelContent oldWidget) => false;
}
