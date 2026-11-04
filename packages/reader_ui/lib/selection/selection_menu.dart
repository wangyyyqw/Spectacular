import 'package:flutter/material.dart';

/// 选区菜单动作（P4-16）：id 化预留，后续可配置（§40 / Reeden 270 号）。
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
  });

  /// 动作列表（按顺序展示）。
  final List<SelectionAction> actions;

  /// 选区包围盒（页内坐标）。
  final Rect anchor;

  /// 可用区域（页内坐标，通常是页面大小）。
  final Size bounds;

  /// 菜单高度估算（用于决定贴上方还是下方）。
  static const double _menuHeight = 44;

  /// 菜单与选区的间距。
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    if (anchor.bottom <= 0 || anchor.top >= bounds.height) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    final theme = Theme.of(context);
    final aboveTop = anchor.top - _menuHeight - _gap;
    final placeAbove = aboveTop >= 0;
    final top = placeAbove ? aboveTop : anchor.bottom + _gap;
    final clampedTop = top.clamp(0.0, bounds.height - _menuHeight);
    return Positioned(
      left: 0,
      right: 0,
      top: clampedTop,
      child: Center(
        child: Material(
          key: const ValueKey<String>('selection-menu'),
          elevation: 4,
          borderRadius: BorderRadius.circular(22),
          color: theme.colorScheme.inverseSurface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final action in actions)
                  TextButton(
                    key: ValueKey<String>('selection-action-${action.id}'),
                    onPressed: action.onTap,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onInverseSurface,
                      minimumSize: const Size(64, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Text(action.label),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
