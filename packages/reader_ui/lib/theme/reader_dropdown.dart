import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/app_icon.dart';

/// 选择框使用主题圆角浮层，保留当前项、键盘和菜单滚动行为。
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(48.0, MediaQuery.sizeOf(context).width - 32);
        final width = constraints.hasBoundedWidth && expanded
            ? math.min(constraints.maxWidth, available)
            : math.min(280.0, available);
        return PopupMenuButton<T>(
          enabled: enabled,
          tooltip: decoration?.labelText ?? '选择',
          position: PopupMenuPosition.under,
          clipBehavior: Clip.antiAlias,
          color: theme.popupMenuTheme.color ?? theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: theme.popupMenuTheme.elevation ?? 2,
          shape:
              theme.popupMenuTheme.shape ??
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
          constraints: BoxConstraints(
            minWidth: width,
            maxWidth: width,
            maxHeight: MediaQuery.sizeOf(context).height * .6,
          ),
          onSelected: onChanged,
          itemBuilder: (_) => [
            for (final item in items)
              PopupMenuItem<T>(
                value: item.value,
                enabled: item.enabled,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Semantics(
                  selected: item.value == value,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: item.value == value
                          ? theme.colorScheme.onSurface.withValues(alpha: .06)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: DefaultTextStyle(
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: item.enabled
                                  ? theme.colorScheme.onSurface
                                  : theme.disabledColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            child: item.child,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox.square(
                          dimension: 20,
                          child: item.value == value
                              ? const AppIcon(AppGlyph.check, size: 18)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
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
        );
      },
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
