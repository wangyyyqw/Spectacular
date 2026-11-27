import 'package:flutter/material.dart';

/// 阅读指标的标签与数值，共用语义描述和等宽数字样式。
class ReadingMetric extends StatelessWidget {
  const ReadingMetric({
    super.key,
    required this.label,
    required this.value,
    required this.valueKey,
    this.valueSize = 22,
  });

  final String label;
  final String value;
  final Key valueKey;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label：$value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 2,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                key: valueKey,
                maxLines: 1,
                style: TextStyle(
                  fontSize: valueSize,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
