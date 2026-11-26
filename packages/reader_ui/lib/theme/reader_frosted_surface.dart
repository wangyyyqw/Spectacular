import 'package:flutter/material.dart';

import 'reader_ui_style.dart';

/// 阅读控件共用的实色底板：完全不透明，保留柔和高光和阴影，不采样背景。
class ReaderFrostedSurface extends StatelessWidget {
  const ReaderFrostedSurface({
    super.key,
    required this.child,
    this.radius,
    this.bottomRadius,
    this.inkMode = false,
    this.inset = EdgeInsets.zero,
  });

  final Widget child;
  final double? radius;
  final double? bottomRadius;
  final bool inkMode;

  /// 只缩小可见底板，保留内容的触控区域。
  final EdgeInsets inset;

  /// 抽屉内的内容面板共用凝光底板，独立显示时保留原来的背景色。
  static Color panelColorOf(BuildContext context, {Color? fallback}) =>
      context.dependOnInheritedWidgetOfExactType<_FrostedPanelContent>() != null
      ? Colors.transparent
      : fallback ?? Theme.of(context).colorScheme.surface;

  // 底板和内容的声明式层级保持内联，避免仅为拆行增加无复用的构建方法。
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final flat =
        inkMode ||
        ReaderFrostedScope.inkModeOf(context) ||
        MediaQuery.highContrastOf(context);
    final topRadius = radius ?? ReaderUiStyle.panelCornerOf(Theme.of(context));
    final lowerRadius = bottomRadius ?? topRadius;
    final rounded = topRadius > 0 || lowerRadius > 0;
    // 底板完全不透明，用原生圆角直接覆盖阴影，无需玻璃混合高光及反向裁剪。
    // 将底板与内容一起缓存，弹窗位移或缩放时仅合成已有图层。
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Padding(
              padding: inset,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 1),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(topRadius),
                    bottom: Radius.circular(lowerRadius),
                  ),
                  border: flat || !rounded
                      ? null
                      : Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 0.5,
                        ),
                  boxShadow:
                      flat || !rounded || scheme.brightness == Brightness.dark
                      ? null
                      : const [
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
