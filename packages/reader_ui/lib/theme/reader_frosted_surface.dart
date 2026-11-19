import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// 阅读控件共用的凝光底板：高斯模糊、凝实底色和柔和高光，无玻璃折射。
class ReaderFrostedSurface extends StatelessWidget {
  const ReaderFrostedSurface({
    super.key,
    required this.child,
    this.radius = 20,
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
                surfaceStyle: inkMode || MediaQuery.highContrastOf(context)
                    ? GlassSurfaceStyle.solid
                    : GlassSurfaceStyle.glass,
                color: scheme.surface,
                settings: LiquidGlassSettings(
                  glassColor: scheme.surface.withValues(alpha: 0.75),
                  blur: 16,
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

class _FrostedPanelContent extends InheritedWidget {
  const _FrostedPanelContent({required super.child});

  @override
  bool updateShouldNotify(_FrostedPanelContent oldWidget) => false;
}
