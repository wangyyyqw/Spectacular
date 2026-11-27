import 'package:flutter/material.dart';

import 'reader_ui_style.dart';

/// 带有动画选中状态的胶囊分区切换控件。
typedef ReaderSectionSliderItem = ({String key, String label});

/// 笔记页与阅读器弹层共用的分区切换样式。
class ReaderSectionSlider extends StatelessWidget {
  const ReaderSectionSlider({
    super.key,
    required this.sections,
    required this.index,
    required this.onSelected,
    this.itemKeyBuilder,
  });

  final List<ReaderSectionSliderItem> sections;
  final int index;
  final ValueChanged<int> onSelected;
  final Key Function(ReaderSectionSliderItem item)? itemKeyBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = theme.useMaterial3
        ? BorderRadius.circular(999)
        : ReaderUiStyle.controlRadiusOf(theme);
    final thumbRadius = theme.useMaterial3
        ? BorderRadius.circular(999)
        : BorderRadius.circular(3);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: radius,
        border: theme.useMaterial3
            ? null
            : Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segment = constraints.maxWidth / sections.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: index * segment,
                top: 0,
                width: segment,
                height: constraints.maxHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: thumbRadius,
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: .08),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < sections.length; i++)
                    Expanded(
                      child: Semantics(
                        key:
                            itemKeyBuilder?.call(sections[i]) ??
                            ValueKey('${sections[i].key}-tab'),
                        label: sections[i].label,
                        button: true,
                        selected: index == i,
                        onTap: () => onSelected(i),
                        excludeSemantics: true,
                        child: InkWell(
                          borderRadius: thumbRadius,
                          onTap: () => onSelected(i),
                          child: Center(
                            child: Text(
                              sections[i].label,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.2,
                                fontWeight: index == i
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: index == i
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
