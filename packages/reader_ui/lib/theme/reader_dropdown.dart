import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import 'reader_frosted_surface.dart';
import 'reader_ui_style.dart';

Future<T?> showReaderChoiceMenu<T>(
  BuildContext context, {
  required List<DropdownMenuItem<T>> items,
  required T? value,
}) {
  final theme = Theme.of(context);
  final button = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final width = math.min(144.0, math.max(0.0, overlay.size.width - 16));
  final anchor = button.localToGlobal(
    button.size.topRight(Offset.zero),
    ancestor: overlay,
  );
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      anchor.translate(-width, 0) & Size(width, button.size.height),
      Offset.zero & overlay.size,
    ),
    constraints: BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: MediaQuery.sizeOf(context).height * .6,
    ),
    color: theme.colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 3,
    shape: theme.popupMenuTheme.shape ?? ReaderUiStyle.controlShapeOf(theme),
    clipBehavior: Clip.antiAlias,
    popUpAnimationStyle:
        ReaderFrostedScope.inkModeOf(context) ||
            MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    items: [
      for (final item in items)
        PopupMenuItem<T>(
          key: item.key,
          value: item.value,
          enabled: item.enabled,
          onTap: item.onTap,
          height: 52,
          textStyle: theme.textTheme.bodyMedium,
          labelTextStyle: WidgetStatePropertyAll(theme.textTheme.bodyMedium),
          child: Semantics(
            selected: item.value == value,
            child: Center(
              child: DefaultTextStyle(
                style: theme.textTheme.bodyMedium!.copyWith(
                  fontSize: 14,
                  color: !item.enabled
                      ? theme.disabledColor
                      : item.value == value
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                child: item.child,
              ),
            ),
          ),
        ),
    ],
  );
}

/// 选择框与书源菜单共用圆角浮层，保留当前项、键盘和菜单滚动行为。
class ReaderDropdownButton<T> extends StatelessWidget {
  const ReaderDropdownButton({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.isExpanded = false,
    this.isDense = false,
    this.icon,
    this.underline,
    this.decoration,
  });

  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final T? value;
  final bool isExpanded;
  final bool isDense;
  final Widget? icon;
  final Widget? underline;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final selected = items.where((item) => item.value == value).firstOrNull;
    final enabled = onChanged != null && items.any((item) => item.enabled);
    final theme = Theme.of(context);
    final label = selected?.child ?? const SizedBox.shrink();
    final expanded = isExpanded || decoration != null;
    final content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (expanded) Expanded(child: label) else Flexible(child: label),
        const SizedBox(width: 12),
        icon ?? const AppIcon(AppGlyph.chevronDown, size: 20),
      ],
    );
    return Tooltip(
      message: decoration?.labelText ?? '选择',
      child: InkWell(
        onTap: !enabled
            ? null
            : () async {
                final selected = await showReaderChoiceMenu(
                  context,
                  items: items,
                  value: value,
                );
                if (context.mounted && selected != null) onChanged!(selected);
              },
        child: decoration == null
            ? ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: DefaultTextStyle(
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: enabled
                        ? theme.colorScheme.onSurface
                        : theme.disabledColor,
                  ),
                  child: content,
                ),
              )
            : InputDecorator(
                decoration: decoration!.copyWith(enabled: enabled),
                isEmpty: selected == null,
                child: content,
              ),
      ),
    );
  }
}

/// 表单选择框只改变菜单外观，验证与重置继续交由 FormField 管理。
class ReaderDropdownButtonFormField<T> extends FormField<T> {
  ReaderDropdownButtonFormField({
    super.key,
    super.initialValue,
    required List<DropdownMenuItem<T>> items,
    required this.onChanged,
    InputDecoration decoration = const InputDecoration(),
    Widget? icon,
    bool isExpanded = true,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
  }) : super(
         enabled: onChanged != null,
         builder: (field) => ReaderDropdownButton<T>(
           value: field.value,
           items: items,
           icon: icon,
           isExpanded: isExpanded,
           decoration: decoration.copyWith(errorText: field.errorText),
           onChanged: onChanged == null
               ? null
               : (value) {
                   field.didChange(value);
                   onChanged(value);
                 },
         ),
       );

  final ValueChanged<T?>? onChanged;

  @override
  FormFieldState<T> createState() => _ReaderDropdownFormFieldState<T>();
}

class _ReaderDropdownFormFieldState<T> extends FormFieldState<T> {
  @override
  void didUpdateWidget(covariant ReaderDropdownButtonFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }
}
