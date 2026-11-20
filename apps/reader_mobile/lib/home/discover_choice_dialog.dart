import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

/// 分类和筛选选项按可用宽度分列，长名称自然换行。
class DiscoverChoiceDialog<T> extends StatelessWidget {
  const DiscoverChoiceDialog({
    super.key,
    required this.title,
    required this.options,
    required this.labelFor,
    this.selected,
  });

  final String title;
  final List<T> options;
  final String Function(T) labelFor;
  final T? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .6,
          ),
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 480 ? 3 : 2;
                const gap = 8.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final option in options)
                      SizedBox(
                        width: width,
                        child: Semantics(
                          selected: option == selected,
                          button: true,
                          child: InkWell(
                            key: ValueKey(
                              'discover-choice-${labelFor(option)}',
                            ),
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => Navigator.of(context).pop(option),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: option == selected
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      labelFor(option),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: option == selected
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                    ),
                                  ),
                                  if (option == selected) ...[
                                    const SizedBox(width: 4),
                                    const AppIcon(AppGlyph.check, size: 16),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
