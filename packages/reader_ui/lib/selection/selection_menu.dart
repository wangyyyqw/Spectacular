import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/reader_frosted_surface.dart';
import '../theme/reader_panel_theme.dart';
import '../theme/reader_environment.dart';
import '../theme/reader_theme.dart';

/// 选区菜单动作（P4-16）：id 化预留，后续可配置。
class SelectionAction {
  /// 创建动作。
  const SelectionAction({
    required this.id,
    required this.label,
    required this.onTap,
  });

  /// 稳定 id（埋点/配置用）。
  final String id;

  /// 显示文案。
  final String label;

  /// 点击回调。
  final VoidCallback onTap;
}

/// 单行图标选区菜单：贴在选区上方，空间不足时翻到下方。
class SelectionMenu extends StatelessWidget {
  /// 创建菜单。
  const SelectionMenu({
    super.key,
    required this.actions,
    required this.anchor,
    required this.bounds,
    this.readerTheme,
    this.inkMode = false,
  });

  /// 动作列表（按顺序展示）。
  final List<SelectionAction> actions;

  /// 选区包围盒（页内坐标）。
  final Rect anchor;

  /// 可用区域（页内坐标，通常是页面大小）。
  final Size bounds;

  final ReaderTheme? readerTheme;
  final bool inkMode;

  /// 菜单与选区的间距。
  static const double _gap = 8;
  static const double _radius = 12;
  static const double _iconSize = 22;
  static const double _labelSize = 12;
  static const double _labelHeight = 1.25;
  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty || anchor.bottom <= 0 || anchor.top >= bounds.height) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    return ReaderPanelTheme(
      theme: inkMode
          ? ReaderEnvironment.inkTheme
          : readerTheme ?? ReaderTheme.white,
      child: Builder(builder: _buildMenu),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    final labelStyle = Theme.of(context).textTheme.labelMedium!.copyWith(
      fontSize: _labelSize,
      height: _labelHeight,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: color,
    );
    final available = math.max(1.0, bounds.width - 24);
    final textScaler = MediaQuery.textScalerOf(context);
    final minimum = _buttonSize(
      labelStyle,
      textScaler,
      Directionality.of(context),
    );
    final buttonWidth = math.max(
      minimum.width,
      math.min(48.0, (available - 12) / actions.length),
    );
    final width = math.min(available, actions.length * buttonWidth + 12);
    return Positioned(
      left: 0,
      right: 0,
      top: _top(minimum.height),
      child: Center(
        child: _surface(
          color,
          labelStyle,
          Size(width, minimum.height),
          buttonWidth,
        ),
      ),
    );
  }

  double _top(double height) {
    final aboveTop = anchor.top - height - _gap;
    final top = aboveTop >= 0 ? aboveTop : anchor.bottom + _gap;
    return top.clamp(0.0, math.max(0.0, bounds.height - height)).toDouble();
  }

  Widget _surface(
    Color color,
    TextStyle labelStyle,
    Size size,
    double buttonWidth,
  ) => ReaderFrostedSurface(
    radius: _radius,
    inkMode: inkMode,
    child: Material(
      key: const ValueKey<String>('selection-menu'),
      elevation: 0,
      borderRadius: BorderRadius.circular(_radius),
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: SingleChildScrollView(
          key: const ValueKey<String>('selection-menu-scroll'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in actions)
                SizedBox(
                  width: buttonWidth,
                  height: size.height,
                  child: _button(action, color, labelStyle),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _button(SelectionAction action, Color color, TextStyle labelStyle) =>
      TextButton(
        key: ValueKey<String>('selection-action-${action.id}'),
        onPressed: action.onTap,
        style: TextButton.styleFrom(
          foregroundColor: color,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(_glyphOf(action.id), size: _iconSize, color: color),
            const SizedBox(height: 6),
            Text(action.label, maxLines: 1, softWrap: false, style: labelStyle),
          ],
        ),
      );

  Size _buttonSize(
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    var width = 44.0;
    var labelHeight = 0.0;
    for (final action in actions) {
      final painter = TextPainter(
        text: TextSpan(text: action.label, style: style),
        textScaler: scaler,
        textDirection: direction,
      )..layout();
      width = math.max(width, painter.width + 16);
      labelHeight = math.max(labelHeight, painter.height);
      painter.dispose();
    }
    return Size(width, _iconSize + 6 + labelHeight + 16);
  }
}

AppGlyph _glyphOf(String id) => switch (id) {
  'copy' => AppGlyph.copy,
  'mark' => AppGlyph.formatUnderlined,
  'thought' => AppGlyph.rateReview,
  'decoration' => AppGlyph.palette,
  'dictionary' => AppGlyph.menuBook,
  'edit-source' => AppGlyph.edit,
  'relocate' => AppGlyph.link,
  'select-all' => AppGlyph.multiSelect,
  'dismiss' => AppGlyph.close,
  _ => AppGlyph.more,
};
