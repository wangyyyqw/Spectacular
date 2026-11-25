import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

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
    return ReaderFrostedAlertDialog(
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
                const gap = 8.0;
                double columnHeight(int columns) {
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  var height = 0.0;
                  for (
                    var start = 0;
                    start < options.length;
                    start += columns
                  ) {
                    var rowHeight = 44.0;
                    for (final option in options.skip(start).take(columns)) {
                      final painter =
                          TextPainter(
                            text: TextSpan(
                              text: labelFor(option),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: option == selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            textDirection: Directionality.of(context),
                            textScaler: MediaQuery.textScalerOf(context),
                          )..layout(
                            maxWidth:
                                (width - 20 - (option == selected ? 20 : 0))
                                    .clamp(1, double.infinity),
                          );
                      final itemHeight = painter.height + 20;
                      if (itemHeight > rowHeight) rowHeight = itemHeight;
                      painter.dispose();
                    }
                    height += rowHeight + (start == 0 ? 0 : gap);
                  }
                  return height;
                }

                final maxHeight = MediaQuery.sizeOf(context).height * .6;
                var columns = 1;
                final maxColumns = constraints.maxWidth >= 480 ? 3 : 2;
                while (columns < maxColumns &&
                    columnHeight(columns) > maxHeight) {
                  columns++;
                }
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
                            borderRadius: ReaderUiStyle.controlRadiusOf(theme),
                            onTap: () => Navigator.of(context).pop(option),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: option == selected
                                    ? theme.colorScheme.primaryContainer
                                    : null,
                                borderRadius: ReaderUiStyle.controlRadiusOf(
                                  theme,
                                ),
                                border: Border.all(
                                  color: option == selected
                                      ? theme.colorScheme.primary
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
                                            color: option == selected
                                                ? theme
                                                      .colorScheme
                                                      .onPrimaryContainer
                                                : theme.colorScheme.onSurface,
                                            fontWeight: option == selected
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                    ),
                                  ),
                                  if (option == selected) ...[
                                    const SizedBox(width: 4),
                                    AppIcon(
                                      AppGlyph.check,
                                      size: 16,
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                    ),
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
