import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'reading_insights.dart';

/// 单日小时分布页面。
class HourlyReadingPage extends StatelessWidget {
  /// 创建单日小时分布页面。
  const HourlyReadingPage({
    super.key,
    required this.insights,
    required this.date,
  });

  /// 阅读统计快照。
  final ReadingInsights insights;

  /// 要展示的日期。
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    return Scaffold(
      key: const ValueKey<String>('stats-hourly-page'),
      appBar: AppBar(
        title: const Text('小时分布'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: theme.colorScheme.outlineVariant),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${date.year}年${date.month}月${date.day}日 · '
                    '周${weekdays[date.weekday - 1]}',
                    key: const ValueKey<String>('stats-hourly-page-date'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '按这一天实际前台阅读时长统计',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  HourlyReadingChart(insights: insights, date: date),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 把某一天的阅读时长按小时拆分，供 24 瓣小时图使用。
///
/// [ReadingInsights.portions] 已完成跨日拆分；这里只处理目标日期内的片段，
/// 再按片段实际时长与墙上时间的比例分摊到小时，保证总时长守恒。
List<Duration> hourlyReadingDurations(ReadingInsights insights, DateTime date) {
  final target = DateTime(date.year, date.month, date.day);
  final micros = List<int>.filled(24, 0);
  for (final portion in insights.portions) {
    if (portion.date != target || portion.duration <= Duration.zero) {
      continue;
    }
    final start = portion.startedAt.toLocal();
    final end = portion.endedAt.toLocal();
    final wallMicros = end.difference(start).inMicroseconds;
    if (wallMicros <= 0) {
      continue;
    }
    final durationMicros = portion.duration.inMicroseconds;
    int cumulative(DateTime time) =>
        (durationMicros * (time.difference(start).inMicroseconds / wallMicros))
            .round();

    var cursor = start;
    var previous = 0;
    while (cursor.isBefore(end)) {
      var boundary = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        cursor.hour + 1,
      );
      if (!boundary.isAfter(cursor)) {
        boundary = cursor.add(const Duration(hours: 1));
      }
      final next = end.isBefore(boundary) ? end : boundary;
      final current = cumulative(next);
      final allocated = current - previous;
      if (allocated > 0) {
        micros[cursor.hour] += allocated;
      }
      previous = current;
      cursor = next;
    }
  }
  return <Duration>[for (final value in micros) Duration(microseconds: value)];
}

/// 单日 24 小时花瓣图。
///
/// 0 时位于正上方并顺时针排列；点击花瓣或外侧小时数字可切换小时详情。
class HourlyReadingChart extends StatefulWidget {
  /// 创建单日小时图。
  const HourlyReadingChart({
    super.key,
    required this.insights,
    required this.date,
  });

  /// 阅读统计快照。
  final ReadingInsights insights;

  /// 要展示的日期，只使用年月日。
  final DateTime date;

  @override
  State<HourlyReadingChart> createState() => _HourlyReadingChartState();
}

class _HourlyReadingChartState extends State<HourlyReadingChart> {
  late int _selectedHour;

  @override
  void initState() {
    super.initState();
    _selectedHour = _defaultHour();
  }

  @override
  void didUpdateWidget(HourlyReadingChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.insights, widget.insights) ||
        !_sameDate(oldWidget.date, widget.date)) {
      _selectedHour = _defaultHour();
    }
  }

  int _defaultHour() {
    final durations = hourlyReadingDurations(widget.insights, widget.date);
    final now = DateTime.now();
    if (_sameDate(now, widget.date) && durations[now.hour] > Duration.zero) {
      return now.hour;
    }
    var best = 0;
    for (var hour = 1; hour < durations.length; hour++) {
      if (durations[hour] > durations[best]) {
        best = hour;
      }
    }
    return best;
  }

  void _selectHour(int hour) {
    if (hour == _selectedHour) return;
    setState(() => _selectedHour = hour);
  }

  void _handleChartTap(Offset position, Size size) {
    final center = size.center(Offset.zero);
    final dx = position.dx - center.dx;
    final dy = position.dy - center.dy;
    final radius = math.sqrt(dx * dx + dy * dy);
    final innerRadius = math.max(22.0, size.width * 0.105);
    final maxLength = math.max(58.0, size.width * 0.255);
    if (radius < innerRadius * 0.45 || radius > innerRadius + maxLength + 14) {
      return;
    }
    final angle = (math.atan2(dx, -dy) + 2 * math.pi) % (2 * math.pi);
    final hour = (angle / (2 * math.pi / 24)).round() % 24;
    _selectHour(hour);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durations = hourlyReadingDurations(widget.insights, widget.date);
    final total = durations.fold<Duration>(
      Duration.zero,
      (sum, duration) => sum + duration,
    );
    final selectedDuration = durations[_selectedHour];
    return Container(
      key: const ValueKey<String>('stats-hourly-reading-chart'),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                const Text(
                  '小时分布',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                Text(
                  '合计 ${formatReadingDuration(total)}',
                  key: const ValueKey<String>('stats-hourly-total'),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(constraints.maxWidth, 420.0);
              return Center(
                child: SizedBox.square(
                  dimension: size,
                  child: _buildChart(context, durations, size),
                ),
              );
            },
          ),
          Text(
            '按实际前台阅读时长统计',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 10),
          _HourlyDetail(
            hour: _selectedHour,
            duration: selectedDuration,
            hasReading: total > Duration.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildChart(
    BuildContext context,
    List<Duration> durations,
    double size,
  ) {
    final theme = Theme.of(context);
    final center = size / 2;
    final innerRadius = math.max(22.0, size * 0.105);
    final maxLength = math.max(58.0, size * 0.255);
    final maxDuration = durations.fold<Duration>(
      Duration.zero,
      (max, item) => item > max ? item : max,
    );
    final lengths = <double>[
      for (final duration in durations)
        _petalLength(duration, maxDuration, maxLength),
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _HourlyPetalPainter(
              lengths: lengths,
              innerRadius: innerRadius,
              maxLength: maxLength,
              selectedHour: _selectedHour,
              petalColor: theme.colorScheme.primary,
              ghostColor: theme.colorScheme.surfaceContainerHighest,
              surfaceColor: theme.colorScheme.surface,
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey<String>('stats-hourly-petal-surface'),
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapUp: (details) =>
                _handleChartTap(details.localPosition, Size.square(size)),
          ),
        ),
        for (var hour = 0; hour < 24; hour++)
          _hourLabel(context, hour, durations[hour], center, size),
      ],
    );
  }

  Widget _hourLabel(
    BuildContext context,
    int hour,
    Duration duration,
    double center,
    double size,
  ) {
    final theme = Theme.of(context);
    final selected = hour == _selectedHour;
    final angle = hour * 2 * math.pi / 24;
    final radius = size * 0.455;
    const labelWidth = 30.0;
    const labelHeight = 24.0;
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
        container: true,
        button: true,
        selected: selected,
        label: duration <= Duration.zero
            ? '$hour 时，无阅读记录'
            : '$hour 时，阅读 ${formatReadingDuration(duration)}',
        onTap: () => _selectHour(hour),
        child: GestureDetector(
          key: ValueKey<String>('stats-hourly-label-$hour'),
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: () => _selectHour(hour),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected)
                    AppIcon(
                      AppGlyph.play,
                      size: 9,
                      color: theme.colorScheme.primary,
                    ),
                  Text(
                    '$hour',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const <FontFeature>[
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
    );
  }
}

class _HourlyDetail extends StatelessWidget {
  const _HourlyDetail({
    required this.hour,
    required this.duration,
    required this.hasReading,
  });

  final int hour;
  final Duration duration;
  final bool hasReading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '$hour 时',
                  key: const ValueKey<String>('stats-hourly-selected-hour'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              Text(
                formatReadingDuration(duration),
                key: const ValueKey<String>('stats-hourly-selected-duration'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: theme.colorScheme.onSurface,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          if (!hasReading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '这一天没有阅读记录',
                key: const ValueKey<String>('stats-hourly-empty'),
                style: TextStyle(fontSize: 11, color: muted, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

class _HourlyPetalPainter extends CustomPainter {
  const _HourlyPetalPainter({
    required this.lengths,
    required this.innerRadius,
    required this.maxLength,
    required this.selectedHour,
    required this.petalColor,
    required this.ghostColor,
    required this.surfaceColor,
  });

  final List<double> lengths;
  final double innerRadius;
  final double maxLength;
  final int selectedHour;
  final Color petalColor;
  final Color ghostColor;
  final Color surfaceColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ghostPaint = Paint()..color = ghostColor.withValues(alpha: 0.58);
    for (var hour = 0; hour < 24; hour++) {
      _drawPetal(
        canvas,
        center,
        hour * 2 * math.pi / 24,
        innerRadius,
        maxLength,
        _petalWidth(maxLength),
        ghostPaint,
      );
    }
    for (var hour = 0; hour < lengths.length; hour++) {
      final length = lengths[hour];
      if (length <= 0) continue;
      final selected = hour == selectedHour;
      final ratio = maxLength == 0 ? 0.0 : (length / maxLength).clamp(0, 1);
      final path = _petalPath(length, _petalWidth(length));
      final origin = Offset(
        center.dx + innerRadius * math.sin(hour * 2 * math.pi / 24),
        center.dy - innerRadius * math.cos(hour * 2 * math.pi / 24),
      );
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.rotate(hour * 2 * math.pi / 24 + math.pi);
      canvas.drawPath(
        path,
        Paint()
          ..color = petalColor.withValues(
            alpha: selected ? 0.94 : 0.55 + ratio * 0.25,
          ),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = surfaceColor.withValues(alpha: 0.72),
      );
      canvas.restore();
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
        -halfWidth * 1.18,
        length * 0.2,
        -halfWidth,
        length * 0.82,
        -halfWidth * 0.48,
        length * 0.96,
      )
      ..cubicTo(
        -halfWidth * 0.2,
        length * 1.03,
        halfWidth * 0.2,
        length * 1.03,
        halfWidth * 0.48,
        length * 0.96,
      )
      ..cubicTo(halfWidth, length * 0.82, halfWidth * 1.18, length * 0.2, 0, 0)
      ..close();
  }

  double _petalWidth(double length) => math.max(8, length * 0.31);

  @override
  bool shouldRepaint(_HourlyPetalPainter oldDelegate) =>
      oldDelegate.lengths != lengths ||
      oldDelegate.innerRadius != innerRadius ||
      oldDelegate.maxLength != maxLength ||
      oldDelegate.selectedHour != selectedHour ||
      oldDelegate.petalColor != petalColor ||
      oldDelegate.ghostColor != ghostColor ||
      oldDelegate.surfaceColor != surfaceColor;
}

double _petalLength(Duration value, Duration max, double maxLength) {
  if (value <= Duration.zero || max <= Duration.zero) return 0;
  final ratio = value.inMicroseconds / max.inMicroseconds;
  return maxLength * (0.22 + 0.78 * math.sqrt(ratio));
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
