import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/app_semantic_colors.dart';

/// 五星显示；星级以 0.5 为步长，接口的十分制由调用方转换。
class ReaderRatingStars extends StatelessWidget {
  const ReaderRatingStars({
    super.key,
    required this.rating,
    this.size = 18,
    this.color,
  });

  final num? rating;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var star = 1; star <= 5; star++)
        _Star(
          fraction: ((rating ?? 0) - star + 1).clamp(0, 1).toDouble(),
          size: size,
          color: color,
        ),
    ],
  );
}

class _Star extends StatelessWidget {
  const _Star({required this.fraction, required this.size, this.color});
  final double fraction;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      children: [
        AppIcon(
          AppGlyph.star,
          size: size,
          color:
              color ??
              (fraction == 1
                  ? AppSemanticColors.of(context).starFilled
                  : AppSemanticColors.of(context).starEmpty),
          filled: fraction == 1,
        ),
        if (fraction > 0 && fraction < 1)
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: AppIcon(
                AppGlyph.star,
                size: size,
                color: color ?? AppSemanticColors.of(context).starFilled,
                filled: true,
              ),
            ),
          ),
      ],
    ),
  );
}

/// 左半选择半星、右半选择整星；再次选择当前值清除评分。
class ReaderRatingPicker extends StatelessWidget {
  const ReaderRatingPicker({
    super.key,
    required this.rating,
    required this.onChanged,
    required this.keyPrefix,
  });
  final num? rating;
  final ValueChanged<num?>? onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 2,
    children: [
      for (var star = 1; star <= 5; star++)
        SizedBox(
          key: ValueKey('$keyPrefix-$star'),
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IgnorePointer(
                child: _Star(
                  fraction: ((rating ?? 0) - star + 1).clamp(0, 1).toDouble(),
                  size: 34,
                ),
              ),
              Row(
                children: [
                  for (final value in [star - .5, star.toDouble()])
                    Expanded(
                      child: Semantics(
                        label: '$value 星',
                        selected: rating == value,
                        button: true,
                        child: Tooltip(
                          message: '$value 星',
                          child: InkWell(
                            key: ValueKey(
                              '$keyPrefix-half-${(value * 2).round()}',
                            ),
                            onTap: onChanged == null
                                ? null
                                : () => onChanged!(
                                    rating == value ? null : value,
                                  ),
                            child: const SizedBox(height: 48),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
    ],
  );
}
