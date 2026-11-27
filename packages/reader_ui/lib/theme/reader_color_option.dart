import 'package:flutter/material.dart';

import '../icons/app_icon.dart';

/// 划线和书签共用的颜色选项，保留选中标记与可选的长按操作。
class ReaderColorOption extends StatelessWidget {
  const ReaderColorOption({
    super.key,
    this.buttonKey,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tooltip,
    this.onLongPress,
  });

  final Key? buttonKey;
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? label,
    child: Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox.square(
          dimension: 44,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: _swatch(Theme.of(context).colorScheme),
          ),
        ),
      ),
    ),
  );

  Widget _swatch(ColorScheme scheme) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(
        color: selected ? scheme.onSurface : scheme.outlineVariant,
        width: selected ? 2 : 1,
      ),
    ),
    child: selected
        ? AppIcon(
            AppGlyph.check,
            size: 19,
            color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
          )
        : null,
  );
}
