import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/reader_panel_theme.dart';
import '../theme/reader_theme.dart';
import '../theme/reader_frosted_surface.dart';

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

/// 选区浮动菜单（P4-16）：贴在选区上方，空间不足时翻到下方，不遮挡选区。
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

  @override
  Widget build(BuildContext context) {
    if (anchor.bottom <= 0 || anchor.top >= bounds.height) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    final scheme = Theme.of(context).colorScheme;
    final menuTheme =
        readerTheme ??
        ReaderTheme(
          id: 'selection',
          name: '选区菜单',
          background: scheme.surface,
          text: scheme.onSurface,
        );
    final foreground = menuTheme.text;
    final available = math.max(1.0, bounds.width - 24);
    final textScaler = MediaQuery.textScalerOf(context);
    final buttonWidth = _buttonWidth(context, textScaler);
    final columns = (available / buttonWidth).floor().clamp(1, 3);
    final width = math.min(available, columns * buttonWidth);
    final buttonHeight = math.max(44.0, textScaler.scale(18) + 12);
    final height = (actions.length / columns).ceil() * buttonHeight + 8;
    final aboveTop = anchor.top - height - _gap;
    final placeAbove = aboveTop >= 0;
    final top = placeAbove ? aboveTop : anchor.bottom + _gap;
    final clampedTop = top
        .clamp(0.0, math.max(0.0, bounds.height - height))
        .toDouble();
    return Positioned(
      left: 0,
      right: 0,
      top: clampedTop,
      child: Center(
        child: ReaderPanelTheme(
          theme: menuTheme,
          child: ReaderFrostedSurface(
            radius: 4,
            inkMode: inkMode,
            child: Material(
              key: const ValueKey<String>('selection-menu'),
              elevation: 0,
              borderRadius: BorderRadius.circular(4),
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: width,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      for (final action in actions)
                        SizedBox(
                          width: width / columns,
                          height: buttonHeight,
                          child: TextButton(
                            key: ValueKey<String>(
                              'selection-action-${action.id}',
                            ),
                            onPressed: action.onTap,
                            style: TextButton.styleFrom(
                              foregroundColor: foreground,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                            ),
                            child: Text(action.label),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _buttonWidth(BuildContext context, TextScaler scaler) {
    var width = 72.0;
    for (final action in actions) {
      final painter = TextPainter(
        text: TextSpan(
          text: action.label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        textScaler: scaler,
        textDirection: Directionality.of(context),
      )..layout();
      width = math.max(width, painter.width + 24);
      painter.dispose();
    }
    return width;
  }
}
