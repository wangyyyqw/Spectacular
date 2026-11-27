import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import 'reader_frosted_surface.dart';
import 'reader_panel_theme.dart';
import 'reader_sheet_form.dart';
import 'reader_theme.dart';
import 'reader_ui_components.dart';
import 'reader_ui_style.dart';

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
  bool guardDragDismissal = false,
  bool showDragHandle = true,
  double dragHandleHeight = 48,
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
    enableDrag: enableDrag && !guardDragDismissal,
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
      guardDragDismissal: guardDragDismissal,
      isDismissible: isDismissible,
      dragHandleHeight: dragHandleHeight,
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
  bool guardDragDismissal = false,
  bool showDragHandle = true,
  double dragHandleHeight = 48,
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
      guardDragDismissal: guardDragDismissal,
      showDragHandle: showDragHandle,
      dragHandleHeight: dragHandleHeight,
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
  bool guardDragDismissal = false,
  bool isDismissible = true,
  bool desktop = false,
  double dragHandleHeight = 48,
}) {
  final panel = Builder(
    builder: (context) {
      final radius = ReaderUiStyle.panelCornerOf(Theme.of(context));
      return ReaderFrostedSurface(
        radius: radius,
        bottomRadius: desktop ? radius : 0,
        child: ClipRRect(
          borderRadius: desktop
              ? BorderRadius.circular(radius)
              : BorderRadius.vertical(top: Radius.circular(radius)),
          child: RepaintBoundary(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDragHandle)
                  _DragHandle(
                    dismissible: isDismissible,
                    height: dragHandleHeight,
                    guardDragDismissal: guardDragDismissal,
                  ),
                Flexible(child: Builder(builder: builder)),
              ],
            ),
          ),
        ),
      );
    },
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

class _DragHandle extends StatefulWidget {
  const _DragHandle({
    required this.dismissible,
    required this.guardDragDismissal,
    this.height = 48,
  });

  final bool dismissible;
  final double height;
  final bool guardDragDismissal;

  @override
  State<_DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<_DragHandle> {
  double _distance = 0;

  @override
  Widget build(BuildContext context) => Semantics(
    label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    button: true,
    onTap: widget.dismissible ? () => Navigator.maybePop(context) : null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: widget.guardDragDismissal
          ? (_) => _distance = 0
          : null,
      onVerticalDragUpdate: widget.guardDragDismissal
          ? (details) => _distance += details.delta.dy
          : null,
      onVerticalDragEnd: widget.guardDragDismissal
          ? (details) {
              if (widget.dismissible &&
                  (_distance >= 40 || (details.primaryVelocity ?? 0) > 500)) {
                Navigator.maybePop(context);
              }
            }
          : null,
      child: SizedBox(
        key: const ValueKey<String>('reader-drawer-drag-handle'),
        height: widget.height,
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
      radius: ReaderUiStyle.panelCornerOf(Theme.of(context)),
      child: ClipRRect(
        borderRadius: ReaderUiStyle.panelRadiusOf(Theme.of(context)),
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

/// 统一的确认弹窗入口：规范按钮顺序（取消在左、确认在右）与危险操作配色。
Future<bool> showReaderConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool destructive = false,
  Key? cancelKey,
  Key? confirmKey,
  bool barrierDismissible = true,
}) async =>
    await showReaderDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) {
        final theme = Theme.of(context);
        return ReaderFrostedAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              key: cancelKey,
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancelLabel),
            ),
            FilledButton(
              key: confirmKey,
              style: destructive
                  ? ReaderUiStyle.destructiveFilledButtonStyle(theme)
                  : null,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    ) ??
    false;

/// 统一的底部/侧边动作菜单：移动端底部抽屉，桌面端右抽屉，共用 `ReaderSheetForm`。
Future<T?> showReaderActionSheet<T>({
  required BuildContext context,
  String? title,
  String? subtitle,
  required List<ReaderSheetAction<T>> actions,
  bool showCloseButton = false,
  ReaderTheme? readerTheme,
  double maxWidth = 520,
}) => showReaderDrawer<T>(
  context: context,
  readerTheme: readerTheme,
  maxWidth: maxWidth,
  builder: (context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final list = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
          _SheetActionTile<T>(action: actions[i]),
        ],
      ],
    );
    if (title == null) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: list,
        ),
      );
    }
    return ReaderSheetForm(
      title: subtitle == null
          ? Text(title)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
      showCloseButton: showCloseButton,
      contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      content: list,
    );
  },
);

class _SheetActionTile<T> extends StatelessWidget {
  const _SheetActionTile({required this.action});

  final ReaderSheetAction<T> action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fg = action.destructive
        ? colors.error
        : action.selected
        ? colors.onPrimaryContainer
        : colors.onSurface;
    return ListTile(
      key: action.key,
      enabled: action.enabled,
      selected: action.selected,
      leading: action.icon == null
          ? null
          : IconTheme(
              data: IconThemeData(
                size: 20,
                color: action.destructive
                    ? colors.error
                    : action.selected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
              child: action.icon!,
            ),
      title: Text(
        action.title,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: action.enabled ? fg : colors.onSurface.withValues(alpha: .38),
          fontWeight: action.selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: action.subtitle == null ? null : Text(action.subtitle!),
      trailing: action.selected
          ? AppIcon(AppGlyph.check, size: 20, color: colors.onPrimaryContainer)
          : null,
      onTap: action.enabled
          ? () => Navigator.of(context).pop(action.value)
          : null,
    );
  }
}
