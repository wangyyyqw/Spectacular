import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import 'app_glyph.dart';

export 'app_glyph.dart';

/// 应用图标：按 [AppGlyph] 绘制，尺寸与颜色缺省跟随 [IconTheme]。
class AppIcon extends StatelessWidget {
  /// 创建图标。
  ///
  /// [filled] 为真时绘制实心态（底栏选中态），细节以 [cutoutColor] 镂空。
  const AppIcon(
    this.glyph, {
    super.key,
    this.size,
    this.color,
    this.filled = false,
    this.cutoutColor,
  });

  /// 图标字形。
  final AppGlyph glyph;

  /// 边长，缺省取 [IconTheme] 的尺寸，再缺省为 24。
  final double? size;

  /// 颜色，缺省取 [IconTheme] 的颜色。
  final Color? color;

  /// 是否绘制实心态。
  final bool filled;

  /// 实心态的镂空颜色，应与图标所在底色一致，缺省为白色。
  final Color? cutoutColor;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final iconSize = size ?? iconTheme.size ?? 24.0;
    final iconColor = color ?? iconTheme.color ?? const Color(0xFF000000);
    final opacity = iconTheme.opacity ?? 1;
    return SizedBox.square(
      dimension: iconSize,
      child: Center(
        child: CustomPaint(
          size: Size.square(iconSize),
          painter: _AppIconPainter(
            glyph: glyph,
            color: iconColor.withValues(alpha: iconColor.a * opacity),
            filled: filled,
            cutoutColor: cutoutColor ?? const Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}

class _AppIconPainter extends CustomPainter {
  const _AppIconPainter({
    required this.glyph,
    required this.color,
    required this.filled,
    required this.cutoutColor,
  });

  final AppGlyph glyph;
  final Color color;
  final bool filled;
  final Color cutoutColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    glyph.draw(
      AppIconCanvas(
        canvas,
        color: color,
        filled: filled,
        cutoutColor: cutoutColor,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AppIconPainter oldDelegate) =>
      glyph != oldDelegate.glyph ||
      color != oldDelegate.color ||
      filled != oldDelegate.filled ||
      cutoutColor != oldDelegate.cutoutColor;
}

/// 展开箭头改用 [AppGlyph.chevronDown] 并随展开状态旋转的 [ExpansionTile]。
class AppExpansionTile extends StatefulWidget {
  /// 创建可展开列表项，参数含义同 [ExpansionTile]。
  const AppExpansionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.tilePadding,
    this.initiallyExpanded = false,
    this.children = const <Widget>[],
  });

  /// 标题。
  final Widget title;

  /// 副标题。
  final Widget? subtitle;

  /// 列表项内边距。
  final EdgeInsetsGeometry? tilePadding;

  /// 是否初始展开。
  final bool initiallyExpanded;

  /// 展开后显示的内容。
  final List<Widget> children;

  @override
  State<AppExpansionTile> createState() => _AppExpansionTileState();
}

class _AppExpansionTileState extends State<AppExpansionTile> {
  final _controller = ExpansibleController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    controller: _controller,
    title: widget.title,
    subtitle: widget.subtitle,
    tilePadding: widget.tilePadding,
    initiallyExpanded: widget.initiallyExpanded,
    trailing: ListenableBuilder(
      listenable: _controller,
      builder: (context, child) => AnimatedRotation(
        turns: _controller.isExpanded ? 0.5 : 0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeIn,
        child: child,
      ),
      child: const AppIcon(AppGlyph.chevronDown),
    ),
    children: widget.children,
  );
}

/// 勾选菜单项，布局与 [CheckedPopupMenuItem] 一致，勾选标记改用 [AppGlyph.check]。
PopupMenuItem<T> appCheckedMenuItem<T>({
  Key? key,
  required T value,
  required bool checked,
  required Widget child,
}) => _AppCheckedMenuItem<T>(
  key: key,
  value: value,
  checked: checked,
  child: child,
);

class _AppCheckedMenuItem<T> extends CheckedPopupMenuItem<T> {
  const _AppCheckedMenuItem({
    super.key,
    required super.value,
    required super.checked,
    required super.child,
  });

  @override
  PopupMenuItemState<T, CheckedPopupMenuItem<T>> createState() =>
      _AppCheckedMenuItemState<T>();
}

class _AppCheckedMenuItemState<T>
    extends PopupMenuItemState<T, CheckedPopupMenuItem<T>> {
  @override
  Widget buildSemantics({required Widget child}) => Semantics(
    role: SemanticsRole.menuItemCheckbox,
    enabled: widget.enabled,
    checked: widget.checked,
    button: true,
    child: child,
  );

  @override
  Widget buildChild() => IgnorePointer(
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Opacity(
        opacity: widget.checked ? 1 : 0,
        child: const AppIcon(AppGlyph.check),
      ),
      title: widget.child,
    ),
  );
}
