import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_dropdown.dart';

class SettingsChoiceTile<T> extends StatelessWidget {
  const SettingsChoiceTile({
    super.key,
    required this.title,
    required this.current,
    required this.values,
    required this.label,
    required this.onChanged,
    this.optionKey,
  });

  final String title;
  final T current;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T>? onChanged;
  final Key Function(T)? optionKey;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    trailing: SettingsTrailingValue(label(current)),
    onTap: onChanged == null
        ? null
        : () async {
            final selected = await showReaderChoiceMenu<T>(
              context,
              value: current,
              items: [
                for (final value in values)
                  DropdownMenuItem(
                    key: optionKey?.call(value),
                    value: value,
                    child: Text(label(value)),
                  ),
              ],
            );
            if (context.mounted && selected != null && selected != current) {
              onChanged?.call(selected);
            }
          },
  );
}

class SettingsTrailingValue extends StatelessWidget {
  const SettingsTrailingValue(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * .4,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 4),
        const AppIcon(AppGlyph.chevronRight),
      ],
    ),
  );
}
