import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/app_semantic_colors.dart';

/// 书评详情、图书详情与票根共用的五星展示，保留各处的配色和间距。
class BookRatingStars extends StatelessWidget {
  const BookRatingStars({
    super.key,
    required this.rating,
    this.size = 18,
    this.filledColor,
    this.emptyColor,
    this.spacing = 0,
  });

  final int? rating;
  final double size;
  final Color? filledColor;
  final Color? emptyColor;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppSemanticColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          Padding(
            padding: EdgeInsets.only(right: star < 5 ? spacing : 0),
            child: AppIcon(
              AppGlyph.star,
              filled: star <= (rating ?? 0),
              size: size,
              color: star <= (rating ?? 0)
                  ? filledColor ?? colors.starFilled
                  : emptyColor ?? colors.starEmpty,
            ),
          ),
        if (rating == null) ...[
          const SizedBox(width: 4),
          Text(
            '未评分',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// 读完表单与书评编辑器共用的评分按钮；评分状态由表单持有。
class BookRatingPicker extends StatelessWidget {
  const BookRatingPicker({
    super.key,
    required this.rating,
    required this.onSelected,
    required this.keyPrefix,
    this.spread = false,
  });

  final int? rating;
  final ValueChanged<int>? onSelected;
  final String keyPrefix;
  final bool spread;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      for (var star = 1; star <= 5; star++)
        Semantics(
          selected: rating == star,
          child: IconButton(
            key: ValueKey<String>('$keyPrefix-$star'),
            tooltip: '$star 星',
            onPressed: onSelected == null ? null : () => onSelected!(star),
            iconSize: 34,
            color: Theme.of(context).colorScheme.onSurface,
            icon: AppIcon(AppGlyph.star, filled: star <= (rating ?? 0)),
          ),
        ),
    ];
    return spread
        ? Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: buttons,
          )
        : Wrap(spacing: 2, children: buttons);
  }
}
