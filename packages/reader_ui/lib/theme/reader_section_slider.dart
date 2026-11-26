import 'package:flutter/material.dart';

/// 带有动画选中状态的胶囊分区切换控件。
typedef ReaderSectionSliderItem = ({String key, String label});

/// 笔记页、统计页与阅读器弹层共用的胶囊分段滑块。
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

  /// 可选自定义每项按钮 Key；缺省使用 `<item.key>-tab`。
  final Key Function(ReaderSectionSliderItem item)? itemKeyBuilder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
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
                duration: disableAnimations
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
                        label: sections[i].label,
                        button: true,
                        selected: index == i,
                        onTap: () => onSelected(i),
                        excludeSemantics: true,
                        child: InkWell(
                          key:
                              itemKeyBuilder?.call(sections[i]) ??
                              ValueKey('${sections[i].key}-tab'),
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
