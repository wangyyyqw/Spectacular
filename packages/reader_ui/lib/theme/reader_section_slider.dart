import 'package:flutter/material.dart';

/// 带有动画选中状态的胶囊分区切换控件。
typedef ReaderSectionSliderItem = ({String key, String label});

/// 笔记页与阅读器弹层共用的分区切换样式。
class ReaderSectionSlider extends StatelessWidget {
  const ReaderSectionSlider({
    super.key,
    required this.sections,
    required this.index,
    required this.onSelected,
  });

  final List<ReaderSectionSliderItem> sections;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segment = constraints.maxWidth / sections.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: index * segment,
                top: 0,
                width: segment,
                height: constraints.maxHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(999),
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
                        key: ValueKey('${sections[i].key}-tab'),
                        label: sections[i].label,
                        button: true,
                        selected: index == i,
                        onTap: () => onSelected(i),
                        excludeSemantics: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
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
