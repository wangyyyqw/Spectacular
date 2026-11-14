import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'reading_insights.dart';

/// 按星期展示平均阅读时长的七瓣图。
///
/// 每个星期的均值只计算有阅读记录的自然日；点击星期可查看对应的阅读天数。
class WeekdayAverageChart extends StatefulWidget {
  /// 创建七日花瓣图。
  const WeekdayAverageChart({super.key, required this.insights});

  /// 与其他统计卡片共用的阅读快照。
  final ReadingInsights insights;

  @override
  State<WeekdayAverageChart> createState() => _WeekdayAverageChartState();
}

class _WeekdayAverageChartState extends State<WeekdayAverageChart> {
  int? _selectedWeekday;

  @override
  void initState() {
    super.initState();
    _selectedWeekday = _defaultWeekday(_buildAverages());
  }

  @override
  void didUpdateWidget(WeekdayAverageChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.insights, widget.insights)) {
      _selectedWeekday = _defaultWeekday(_buildAverages());
    }
  }

  List<_WeekdayAverage> _buildAverages() {
    final totals = List<Duration>.filled(7, Duration.zero);
    final readingDays = List<Set<DateTime>>.generate(7, (_) => <DateTime>{});
    for (final portion in widget.insights.portions) {
      final index = portion.date.weekday % 7;
      totals[index] += portion.duration;
      readingDays[index].add(portion.date);
    }
    return <_WeekdayAverage>[
      for (var index = 0; index < 7; index++)
        _WeekdayAverage(
          weekday: index,
          average: readingDays[index].isEmpty
              ? Duration.zero
              : Duration(
                  microseconds:
                      totals[index].inMicroseconds ~/ readingDays[index].length,
                ),
          readingDays: readingDays[index].length,
        ),
    ];
  }

  int? _defaultWeekday(List<_WeekdayAverage> averages) {
    final todayIndex = DateTime.now().weekday % 7;
    if (averages[todayIndex].readingDays > 0) {
      return averages[todayIndex].weekday;
    }
    _WeekdayAverage? best;
    for (final average in averages) {
      if (average.readingDays > 0 &&
          (best == null || average.average > best.average)) {
        best = average;
      }
    }
    return best?.weekday;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final averages = _buildAverages();
    _WeekdayAverage? selected;
    for (final average in averages) {
      if (average.weekday == _selectedWeekday) {
        selected = average;
        break;
      }
    }
    return Container(
      key: const ValueKey<String>('stats-weekday-average-chart'),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(constraints.maxWidth, 400.0);
              return Center(
                child: SizedBox.square(
                  dimension: size,
                  child: _buildFlower(context, averages, size),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: selected == null
                ? Text(
                    '还没有阅读记录，开始阅读后会在这里按星期汇总。',
                    style: TextStyle(fontSize: 12, color: muted, height: 1.4),
                  )
                : _WeekdayDetail(average: selected),
          ),
        ],
      ),
    );
  }

  Widget _buildFlower(
    BuildContext context,
    List<_WeekdayAverage> averages,
    double size,
  ) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final center = size / 2;
    final innerRadius = math.max(28.0, size * 0.115);
    final maxLength = math.max(76.0, size * 0.27);
    final maxAverage = averages.fold<Duration>(
      Duration.zero,
      (max, item) => item.average > max ? item.average : max,
    );
    final lengths = <double>[
      for (final average in averages)
        _petalLength(average.average, maxAverage, maxLength),
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _WeekdayPetalPainter(
              lengths: lengths,
              innerRadius: innerRadius,
              maxLength: maxLength,
              selectedWeekday: _selectedWeekday,
              petalColor: theme.colorScheme.primary,
              ghostColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        Positioned(
          left: center - innerRadius,
          top: center - innerRadius,
          width: innerRadius * 2,
          height: innerRadius * 2,
          child: Center(
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '日均',
                      style: TextStyle(fontSize: 10, height: 1.2, color: muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatCenterDuration(widget.insights.averageDay),
                      key: const ValueKey<String>(
                        'stats-weekday-average-value',
                      ),
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                        fontFeatures: <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        for (var index = 0; index < averages.length; index++) ...[
          if (lengths[index] > 0)
            _valueLabel(
              context,
              averages[index],
              lengths[index],
              center,
              innerRadius,
              size,
            ),
          _weekdayLabel(context, averages[index], center, size, index),
        ],
      ],
    );
  }

  Widget _valueLabel(
    BuildContext context,
    _WeekdayAverage average,
    double length,
    double center,
    double innerRadius,
    double size,
  ) {
    final angle = _angleForIndex(average.weekday);
    final radius = innerRadius + length * 0.64;
    final point = Offset(
      center + radius * math.sin(angle),
      center - radius * math.cos(angle),
    );
    final width = (12 + length * 0.6).clamp(48.0, 80.0);
    return Positioned(
      left: point.dx - width / 2,
      top: point.dy - 14,
      width: width,
      height: 28,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatPetalDuration(average.average),
              key: ValueKey<String>(
                'stats-weekday-petal-value-${average.weekday}',
              ),
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onPrimary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _weekdayLabel(
    BuildContext context,
    _WeekdayAverage average,
    double center,
    double size,
    int index,
  ) {
    final theme = Theme.of(context);
    final selected = average.weekday == _selectedWeekday;
    final angle = index * 2 * math.pi / 7;
    final radius = size * 0.48;
    const labelWidth = 66.0;
    const labelHeight = 44.0;
    final point = Offset(
      center + radius * math.sin(angle),
      center - radius * math.cos(angle),
    );
    return Positioned(
      left: (point.dx - labelWidth / 2).clamp(0.0, size - labelWidth),
      top: (point.dy - labelHeight / 2).clamp(0.0, size - labelHeight),
      width: labelWidth,
      height: labelHeight,
      child: Semantics(
        button: true,
        selected: selected,
        label: _semanticLabel(average),
        child: GestureDetector(
          key: ValueKey<String>('stats-weekday-label-${average.weekday}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _selectedWeekday = average.weekday;
          }),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected)
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 12,
                    color: theme.colorScheme.primary,
                  ),
                Text(
                  average.label,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekdayDetail extends StatelessWidget {
  const _WeekdayDetail({required this.average});

  final _WeekdayAverage average;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${average.label}日均',
                key: const ValueKey<String>('stats-weekday-detail-label'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                average.readingDays == 0
                    ? '暂无阅读记录'
                    : '${average.readingDays} 个阅读日',
                key: const ValueKey<String>('stats-weekday-detail-days'),
                style: TextStyle(fontSize: 11, color: muted, height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          average.readingDays == 0
              ? '--'
              : formatReadingDuration(average.average),
          key: const ValueKey<String>('stats-weekday-detail-value'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: theme.colorScheme.onSurface,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _WeekdayAverage {
  const _WeekdayAverage({
    required this.weekday,
    required this.average,
    required this.readingDays,
  });

  final int weekday;
  final Duration average;
  final int readingDays;

  String get label =>
      const <String>['周日', '周一', '周二', '周三', '周四', '周五', '周六'][weekday % 7];
}

class _WeekdayPetalPainter extends CustomPainter {
  const _WeekdayPetalPainter({
    required this.lengths,
    required this.innerRadius,
    required this.maxLength,
    required this.selectedWeekday,
    required this.petalColor,
    required this.ghostColor,
  });

  final List<double> lengths;
  final double innerRadius;
  final double maxLength;
  final int? selectedWeekday;
  final Color petalColor;
  final Color ghostColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ghostPaint = Paint()..color = ghostColor.withValues(alpha: 0.62);
    for (var index = 0; index < 7; index++) {
      final angle = index * 2 * math.pi / 7;
      _drawPetal(
        canvas,
        center,
        angle,
        innerRadius,
        maxLength,
        _petalWidth(maxLength),
        ghostPaint,
      );
    }
    for (var index = 0; index < lengths.length; index++) {
      final length = lengths[index];
      if (length <= 0) continue;
      final weekday = index;
      final selected = weekday == selectedWeekday;
      final paint = Paint()
        ..color = petalColor.withValues(alpha: selected ? 0.92 : 0.72);
      _drawPetal(
        canvas,
        center,
        index * 2 * math.pi / 7,
        innerRadius,
        length,
        _petalWidth(length),
        paint,
      );
    }
  }

  void _drawPetal(
    Canvas canvas,
    Offset center,
    double angle,
    double innerRadius,
    double length,
    double width,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(
      center.dx + innerRadius * math.sin(angle),
      center.dy - innerRadius * math.cos(angle),
    );
    canvas.rotate(angle + math.pi);
    canvas.drawPath(_petalPath(length, width), paint);
    canvas.restore();
  }

  Path _petalPath(double length, double width) {
    final halfWidth = width / 2;
    return Path()
      ..moveTo(0, 0)
      ..cubicTo(
        -halfWidth * 1.04,
        length * 0.24,
        -halfWidth,
        length * 0.8,
        -halfWidth * 0.5,
        length * 0.95,
      )
      ..cubicTo(
        -halfWidth * 0.2,
        length * 1.03,
        halfWidth * 0.2,
        length * 1.03,
        halfWidth * 0.5,
        length * 0.95,
      )
      ..cubicTo(halfWidth, length * 0.8, halfWidth * 1.04, length * 0.24, 0, 0)
      ..close();
  }

  double _petalWidth(double length) => math.max(52, 14 + length * 0.62);

  @override
  bool shouldRepaint(_WeekdayPetalPainter oldDelegate) =>
      oldDelegate.lengths != lengths ||
      oldDelegate.innerRadius != innerRadius ||
      oldDelegate.maxLength != maxLength ||
      oldDelegate.selectedWeekday != selectedWeekday ||
      oldDelegate.petalColor != petalColor ||
      oldDelegate.ghostColor != ghostColor;
}

double _petalLength(Duration value, Duration max, double maxLength) {
  if (value <= Duration.zero || max <= Duration.zero) return 0;
  final ratio = value.inMicroseconds / max.inMicroseconds;
  return maxLength * (0.22 + 0.78 * math.sqrt(ratio));
}

double _angleForIndex(int weekday) => weekday * 2 * math.pi / 7;

String _semanticLabel(_WeekdayAverage average) => average.readingDays == 0
    ? '${average.label}，暂无阅读记录'
    : '${average.label}，日均 ${formatReadingDuration(average.average)}，'
          '${average.readingDays} 个阅读日';

String _formatPetalDuration(Duration duration) {
  if (duration.inSeconds < 60) return '<1 分钟';
  if (duration.inMinutes < 60) return '${duration.inMinutes} 分钟';
  final hours = duration.inMinutes / 60;
  final rounded = hours.roundToDouble();
  return (hours - rounded).abs() < 0.05
      ? '${rounded.toInt()} 小时'
      : '${hours.toStringAsFixed(1)} 小时';
}

String _formatCenterDuration(Duration duration) {
  if (duration <= Duration.zero) return '0分';
  if (duration < const Duration(minutes: 1)) return '<1分';
  if (duration.inMinutes < 60) return '${(duration.inSeconds / 60).ceil()}分';
  final hours = duration.inMinutes ~/ 60;
  final minutes = duration.inMinutes % 60;
  return minutes == 0 ? '$hours小时' : '$hours小时$minutes分';
}
