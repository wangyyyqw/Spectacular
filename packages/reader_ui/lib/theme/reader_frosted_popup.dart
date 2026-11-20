import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import 'reader_frosted_surface.dart';
import 'reader_panel_theme.dart';
import 'reader_theme.dart';

/// 共用目录抽屉材质，路由仍负责返回值、焦点、安全区和拖动关闭。
Future<T?> showReaderBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showDragHandle = false,
  ReaderTheme? readerTheme,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  isDismissible: isDismissible,
  enableDrag: enableDrag,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  elevation: 0,
  clipBehavior: Clip.none,
  builder: (context) {
    final panel = ReaderFrostedSurface(
      radius: 24,
      bottomRadius: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: RepaintBoundary(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDragHandle) _DragHandle(dismissible: isDismissible),
              Flexible(child: Builder(builder: builder)),
            ],
          ),
        ),
      ),
    );
    return readerTheme == null
        ? panel
        : ReaderPanelTheme(theme: readerTheme, child: panel);
  },
);

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.dismissible});

  final bool dismissible;

  @override
  Widget build(BuildContext context) => Semantics(
    label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    button: true,
    onTap: dismissible ? () => Navigator.maybePop(context) : null,
    child: SizedBox(
      height: 48,
      child: Center(
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  );
}

/// 保留原生对话框的定位与键盘避让，只替换实际内容范围内的底板。
class ReaderFrostedDialog extends StatelessWidget {
  const ReaderFrostedDialog({
    super.key,
    required this.child,
    this.insetPadding,
    this.clipBehavior = Clip.antiAlias,
    this.alignment,
    this.constraints,
    this.semanticsRole = SemanticsRole.dialog,
  });

  final Widget child;
  final EdgeInsets? insetPadding;
  final Clip clipBehavior;
  final AlignmentGeometry? alignment;
  final BoxConstraints? constraints;
  final SemanticsRole semanticsRole;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    insetPadding: insetPadding,
    alignment: alignment,
    constraints: constraints,
    semanticsRole: semanticsRole,
    clipBehavior: Clip.none,
    child: ReaderFrostedSurface(
      radius: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        clipBehavior: clipBehavior,
        child: RepaintBoundary(child: child),
      ),
    ),
  );
}

/// 沿用 AlertDialog 的内容布局、滚动和无障碍语义。
class ReaderFrostedAlertDialog extends AlertDialog {
  const ReaderFrostedAlertDialog({
    super.key,
    super.icon,
    super.title,
    super.titlePadding,
    super.content,
    super.contentPadding,
    super.actions,
    super.actionsPadding,
    super.actionsAlignment,
    super.actionsOverflowAlignment,
    super.actionsOverflowDirection,
    super.actionsOverflowButtonSpacing,
    super.buttonPadding,
    super.semanticLabel,
    super.insetPadding,
    super.alignment,
    super.constraints,
    super.scrollable,
  });

  @override
  Widget build(BuildContext context) {
    // Flutter 的 AlertDialog 将布局后的内容交给 Dialog，复用该内容避免重写布局。
    final dialog = super.build(context) as Dialog;
    return ReaderFrostedDialog(
      insetPadding: dialog.insetPadding,
      alignment: dialog.alignment,
      constraints: dialog.constraints,
      semanticsRole: dialog.semanticsRole,
      child: dialog.child!,
    );
  }
}

/// 简单选项弹窗与确认框共用局部底板，选项语义和滚动沿用系统实现。
class ReaderFrostedSimpleDialog extends SimpleDialog {
  const ReaderFrostedSimpleDialog({
    super.key,
    super.title,
    super.titlePadding,
    super.children,
    super.contentPadding,
    super.semanticLabel,
    super.insetPadding,
    super.alignment,
    super.constraints,
  });

  @override
  Widget build(BuildContext context) {
    final dialog = super.build(context) as Dialog;
    return ReaderFrostedDialog(
      insetPadding: dialog.insetPadding,
      alignment: dialog.alignment,
      constraints: dialog.constraints,
      semanticsRole: dialog.semanticsRole,
      child: dialog.child!,
    );
  }
}
