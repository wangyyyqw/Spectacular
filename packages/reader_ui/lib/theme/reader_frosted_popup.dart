import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import 'reader_frosted_surface.dart';
import 'reader_panel_theme.dart';
import 'reader_theme.dart';

/// 磨砂对话框只缩放，不使用会隔离背景采样的整体淡入。
///
/// 外部持有输入控制器时，可等待退场完成后再释放控制器。
Future<T?> showReaderDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool waitForDismissal = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = _ReaderDialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierDismissible: barrierDismissible,
    reduceMotion:
        ReaderFrostedScope.inkModeOf(context) ||
        MediaQuery.disableAnimationsOf(context),
  );
  final result = await navigator.push(route);
  if (waitForDismissal) await route.completed;
  return result;
}

class _ReaderDialogRoute<T> extends DialogRoute<T> {
  _ReaderDialogRoute({
    required super.context,
    required super.builder,
    required super.themes,
    required super.barrierDismissible,
    required this.reduceMotion,
  }) : super(
         barrierColor: DialogTheme.of(context).barrierColor ?? Colors.black54,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
         animationStyle: reduceMotion
             ? AnimationStyle.noAnimation
             : const AnimationStyle(duration: Duration(milliseconds: 180)),
       );

  final bool reduceMotion;
  static final _scale = Tween<double>(
    begin: 0.96,
    end: 1,
  ).chain(CurveTween(curve: Curves.easeOutCubic));

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 135);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => reduceMotion
      ? child
      : ScaleTransition(scale: animation.drive(_scale), child: child);
}

/// 共用目录抽屉材质，路由仍负责返回值、焦点、安全区和拖动关闭。
Future<T?> showReaderBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showDragHandle = true,
  bool waitForDismissal = false,
  ReaderTheme? readerTheme,
  BoxConstraints? constraints,
}) async {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final reduceMotion =
      ReaderFrostedScope.inkModeOf(context) ||
      readerTheme?.id == 'ink' ||
      MediaQuery.disableAnimationsOf(context);
  final route = ModalBottomSheetRoute<T>(
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: false,
    constraints: constraints,
    backgroundColor: Colors.transparent,
    elevation: 0,
    clipBehavior: Clip.none,
    sheetAnimationStyle: reduceMotion ? AnimationStyle.noAnimation : null,
    builder: (context) => _drawerPanel(
      builder: builder,
      readerTheme: readerTheme,
      showDragHandle: showDragHandle && enableDrag,
      isDismissible: isDismissible,
    ),
  );
  final result = await navigator.push(route);
  if (waitForDismissal) await route.completed;
  return result;
}

/// 手机使用底部抽屉，桌面使用靠右抽屉；两者共享主题和路由返回契约。
Future<T?> showReaderDrawer<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showDragHandle = true,
  bool waitForDismissal = false,
  ReaderTheme? readerTheme,
  double maxWidth = 680,
}) async {
  final platform = Theme.of(context).platform;
  final desktop =
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux;
  if (!desktop) {
    return showReaderBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      waitForDismissal: waitForDismissal,
      readerTheme: readerTheme,
      constraints: BoxConstraints(maxWidth: maxWidth),
    );
  }
  final navigator = Navigator.of(context);
  final route = _ReaderDrawerRoute<T>(
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor:
        Theme.of(context).bottomSheetTheme.modalBarrierColor ?? Colors.black54,
    barrierDismissible: isDismissible,
    useSafeArea: useSafeArea,
    readerTheme: readerTheme,
    maxWidth: maxWidth,
    reduceMotion:
        ReaderFrostedScope.inkModeOf(context) ||
        readerTheme?.id == 'ink' ||
        MediaQuery.disableAnimationsOf(context),
  );
  final result = await navigator.push(route);
  if (waitForDismissal) await route.completed;
  return result;
}

Widget _drawerPanel({
  required WidgetBuilder builder,
  ReaderTheme? readerTheme,
  bool showDragHandle = false,
  bool isDismissible = true,
  bool desktop = false,
}) {
  final panel = ReaderFrostedSurface(
    radius: 24,
    bottomRadius: desktop ? 24 : 0,
    child: ClipRRect(
      borderRadius: desktop
          ? BorderRadius.circular(24)
          : const BorderRadius.vertical(top: Radius.circular(24)),
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
}

class _ReaderDrawerRoute<T> extends PopupRoute<T> {
  _ReaderDrawerRoute({
    required this.builder,
    required this.themes,
    required this.barrierLabel,
    required this.barrierColor,
    required this.barrierDismissible,
    required this.useSafeArea,
    required this.readerTheme,
    required this.maxWidth,
    required this.reduceMotion,
  }) : super(
         requestFocus: true,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
       );

  final WidgetBuilder builder;
  final CapturedThemes themes;
  @override
  final String barrierLabel;
  @override
  final Color barrierColor;
  @override
  final bool barrierDismissible;
  final bool useSafeArea;
  final ReaderTheme? readerTheme;
  final double maxWidth;
  final bool reduceMotion;
  final _shortcuts = ShortcutManager(
    modal: true,
    shortcuts: WidgetsApp.defaultShortcuts,
  );

  @override
  void dispose() {
    _shortcuts.dispose();
    super.dispose();
  }

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 240);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 180);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    Widget panel = Padding(
      padding: MediaQuery.viewInsetsOf(context),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeLeft: true,
        removeTop: true,
        removeRight: true,
        removeBottom: true,
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SizedBox.expand(
              child: _drawerPanel(
                builder: builder,
                readerTheme: readerTheme,
                desktop: true,
              ),
            ),
          ),
        ),
      ),
    );
    if (useSafeArea) panel = SafeArea(child: panel);
    return themes.wrap(
      Shortcuts.manager(
        manager: _shortcuts,
        child: DefaultTextEditingShortcuts(
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            child: panel,
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => reduceMotion
      ? child
      : SlideTransition(
          position: animation.drive(
            Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
          ),
          child: child,
        );
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.dismissible});

  final bool dismissible;

  @override
  Widget build(BuildContext context) => Semantics(
    label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    button: true,
    onTap: dismissible ? () => Navigator.maybePop(context) : null,
    child: SizedBox(
      key: const ValueKey<String>('reader-drawer-drag-handle'),
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
