import 'package:flutter/material.dart';

import 'reader_ui_style.dart';

/// 阅读菜单与弹层共用的拖动把手；拖动手势由外层路由负责。
class ReaderDragHandle extends StatelessWidget {
  const ReaderDragHandle({
    super.key,
    this.handleKey,
    required this.label,
    this.onDismiss,
    this.height = ReaderUiStyle.sheetDragHandleHeight,
    this.width = 36,
    this.opacity = .36,
  });

  final Key? handleKey;
  final String label;
  final VoidCallback? onDismiss;
  final double height;
  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    onTap: onDismiss,
    child: SizedBox(
      key: handleKey,
      height: height,
      width: double.infinity,
      child: Center(
        child: Container(
          width: width,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  );
}
