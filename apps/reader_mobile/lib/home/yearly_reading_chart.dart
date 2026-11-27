import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'reading_insights.dart';

class YearlyReadingChart extends StatelessWidget {
  const YearlyReadingChart({super.key, required this.byYear});

  final Map<int, Duration> byYear;

  @override
  Widget build(BuildContext context) {
    final years = byYear.keys.toList()..sort();
    if (years.isEmpty || byYear.values.every((time) => time == Duration.zero)) {
      return const Text('暂无年度阅读时长');
    }
    final peak = years.reduce(
      (left, right) => byYear[left]! >= byYear[right]! ? left : right,
    );
    final maximum = byYear[peak]!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, bounds) {
            final slot = math.max(
              MediaQuery.textScalerOf(context).scale(38),
              bounds.maxWidth / years.length,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final year in years)
                    SizedBox(
                      width: slot,
                      child: Tooltip(
                        message:
                            '$year年 · ${formatReadingDuration(byYear[year]!)}',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Column(
                          children: [
                            Container(
                              width: math.min(28, slot * .55),
                              height:
                                  116 *
                                  byYear[year]!.inMicroseconds /
                                  maximum.inMicroseconds,
                              decoration: BoxDecoration(
                                color: year == peak
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.secondary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('$year', style: theme.textTheme.labelSmall),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          '$peak年阅读最久 · ${formatReadingDuration(maximum)}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
