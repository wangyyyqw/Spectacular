import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import 'hourly_reading_chart.dart';
import 'reading_insights.dart';

/// 按星期展示平均阅读时长的七瓣图。
///
/// 每个星期的均值只计算有阅读记录的自然日；点击星期可查看对应的阅读天数。
class WeekdayAverageChart extends StatefulWidget {
  /// 创建七日花瓣图。
  const WeekdayAverageChart({
    super.key,
    required this.insights,
    this.dailyTotals,
  });

  /// 与其他统计卡片共用的阅读快照。
  final ReadingInsights insights;

  /// 只有逐日汇总的云端数据不构造会话，也不展示小时分布。
  final Map<DateTime, Duration>? dailyTotals;

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
    if (!identical(oldWidget.insights, widget.insights) ||
        !identical(oldWidget.dailyTotals, widget.dailyTotals)) {
      _selectedWeekday = _defaultWeekday(_buildAverages());
    }
  }

  List<_WeekdayAverage> _buildAverages() {
    final totals = List<Duration>.filled(7, Duration.zero);
    final readingDays = List<Set<DateTime>>.generate(7, (_) => <DateTime>{});
    for (final entry in _dailyTotals.entries) {
      final index = entry.key.weekday % 7;
      totals[index] += entry.value;
      readingDays[index].add(entry.key);
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

  Map<int, List<DateTime>> _buildReadingDates() {
    final dates = <int, Set<DateTime>>{
      for (var index = 0; index < 7; index++) index: <DateTime>{},
    };
    for (final date in _dailyTotals.keys) {
      dates[date.weekday % 7]!.add(date);
    }
    return <int, List<DateTime>>{
      for (final entry in dates.entries)
        entry.key: entry.value.toList()
          ..sort((left, right) => right.compareTo(left)),
    };
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

  Map<DateTime, Duration> get _dailyTotals =>
      widget.dailyTotals ?? widget.insights.byDay;

  Duration get _averageDay => _dailyTotals.isEmpty
      ? Duration.zero
      : Duration(
          microseconds:
              _dailyTotals.values.fold<int>(
                0,
                (total, value) => total + value.inMicroseconds,
              ) ~/
              _dailyTotals.length,
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final averages = _buildAverages();
    final readingDates = _buildReadingDates();
    _WeekdayAverage? selected;
    for (final average in averages) {
      if (average.weekday == _selectedWeekday) {
        selected = average;
        break;
      }
    }
    return Column(
      key: const ValueKey<String>('stats-weekday-average-chart'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (MediaQuery.textScalerOf(context).scale(12) > 16)
          _weekdayList(context, averages)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(constraints.maxWidth, 280.0);
              return Center(
                child: SizedBox.square(
                  dimension: size,
                  child: _buildFlower(context, averages, size),
                ),
              );
            },
          ),
        const SizedBox(height: 12),
        Container(
          padding: EdgeInsets.fromLTRB(12, 12, 12, selected == null ? 12 : 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: selected == null
              ? Text(
                  '还没有阅读记录，开始阅读后会在这里按星期汇总。',
                  style: TextStyle(fontSize: 12, color: muted, height: 1.4),
                )
              : _WeekdayDetail(
                  average: selected,
                  readingDates: readingDates[selected.weekday] ?? const [],
                  onOpenDay: (date) => _openHourlyPage(context, date),
                  dailyOnly: widget.dailyTotals != null,
                ),
        ),
      ],
    );
  }

  Widget _weekdayList(BuildContext context, List<_WeekdayAverage> averages) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '日均 ${_formatCenterDuration(_averageDay)}',
            key: const ValueKey('stats-weekday-average-value'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          for (final average in averages) _weekdayListRow(context, average),
        ],
      );

  Widget _weekdayListRow(BuildContext context, _WeekdayAverage average) {
    final selected = average.weekday == _selectedWeekday;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: InkWell(
        key: ValueKey('stats-weekday-label-${average.weekday}'),
        onTap: () => setState(() => _selectedWeekday = average.weekday),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          color: selected ? scheme.surfaceContainerHighest : null,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(average.label, style: const TextStyle(fontSize: 12)),
              Text(
                average.readingDays == 0
                    ? '暂无记录'
                    : formatReadingDuration(average.average),
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
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
    final innerRadius = _innerRadius(size);
    final maxLength = _maxPetalLength(size);
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
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey<String>('stats-weekday-petal-surface'),
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapUp: (details) => _tapFlower(
              details.localPosition,
              Size.square(size),
              averages,
              _buildReadingDates(),
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
                      _formatCenterDuration(_averageDay),
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
            _valueLabel(context, averages[index], lengths[index], size),
          _weekdayLabel(context, averages[index], center, size, index),
        ],
      ],
    );
  }

  void _tapFlower(
    Offset position,
    Size size,
    List<_WeekdayAverage> averages,
    Map<int, List<DateTime>> readingDates,
  ) {
    final center = size.center(Offset.zero);
    final dx = position.dx - center.dx;
    final dy = position.dy - center.dy;
    final radius = math.sqrt(dx * dx + dy * dy);
    final innerRadius = _innerRadius(size.width);
    final maxLength = _maxPetalLength(size.width);
    if (radius < innerRadius * 0.5 || radius > innerRadius + maxLength + 12) {
      return;
    }
    final angle = (math.atan2(dx, -dy) + 2 * math.pi) % (2 * math.pi);
    final index = (angle / (2 * math.pi / 7)).round() % averages.length;
    final weekday = averages[index].weekday;
    setState(() => _selectedWeekday = weekday);
    final dates = readingDates[weekday];
    if (dates == null || dates.isEmpty) return;
    _openHourlyPage(context, dates.first);
  }

  void _openHourlyPage(BuildContext context, DateTime date) {
    if (widget.dailyTotals != null) {
      showReaderDrawer<void>(
        context: context,
        builder: (_) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '${date.year}年${date.month}月${date.day}日\n'
            '阅读与听书 ${formatReadingDuration(_dailyTotals[date] ?? Duration.zero)}',
          ),
        ),
      );
      return;
    }
    showReaderDrawer<void>(
      context: context,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: HourlyReadingPage(
          insights: widget.insights,
          date: date,
          inDrawer: true,
        ),
      ),
    );
  }

  Widget _valueLabel(
    BuildContext context,
    _WeekdayAverage average,
    double length,
    double size,
  ) {
    final angle = average.weekday * 2 * math.pi / 7;
    final radius = _innerRadius(size) + length * 0.6;
    final scheme = Theme.of(context).colorScheme;
    final selected = average.weekday == _selectedWeekday;
    final extent = _petalLabelExtent(length, angle);
    return Positioned(
      left: size / 2 + radius * math.sin(angle) - extent / 2,
      top: size / 2 - radius * math.cos(angle) - extent / 2,
      width: extent,
      height: extent,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatPetalDuration(average.average).replaceFirst(' ', '\n'),
              key: ValueKey('stats-weekday-petal-value-${average.weekday}'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.15,
                color: selected ? scheme.onPrimary : scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
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
    final selected = average.weekday == _selectedWeekday;
    final angle = index * 2 * math.pi / 7;
    final radius = size * 0.48;
    final labelWidth = math.min(
      size / 3,
      math.max(48.0, MediaQuery.textScalerOf(context).scale(12) * 3 + 16),
    );
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
          child: Center(child: _weekdayLabelText(context, average, selected)),
        ),
      ),
    );
  }

  Widget _weekdayLabelText(
    BuildContext context,
    _WeekdayAverage average,
    bool selected,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      '${selected ? '· ' : ''}${average.label}',
      style: TextStyle(
        fontSize: 12,
        height: 1.2,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
      ),
    );
  }
}

class _WeekdayDetail extends StatelessWidget {
  const _WeekdayDetail({
    required this.average,
    required this.readingDates,
    required this.onOpenDay,
    this.dailyOnly = false,
  });

  final _WeekdayAverage average;
  final List<DateTime> readingDates;
  final ValueChanged<DateTime> onOpenDay;
  final bool dailyOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16,
            runSpacing: 8,
            children: [
              Column(
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
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (readingDates.isNotEmpty) ...[
          const SizedBox(height: 4),
          _dateAction(context),
        ],
      ],
    );
  }

  Widget _dateAction(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        Text(
          '最近阅读日 ${readingDates.first.month}月${readingDates.first.day}日',
          key: const ValueKey('stats-weekday-latest-date'),
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        TextButton.icon(
          key: const ValueKey('stats-weekday-open-hourly'),
          onPressed: () => onOpenDay(readingDates.first),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            textStyle: TextStyle(
              fontSize: 12,
              fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
            ),
          ),
          iconAlignment: IconAlignment.end,
          icon: const AppIcon(AppGlyph.chevronRight, size: 16),
          label: Text(dailyOnly ? '当日时长' : '小时分布'),
        ),
      ],
    ),
  );
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
        ..color = selected ? petalColor : petalColor.withValues(alpha: 0.22);
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

  @override
  bool shouldRepaint(_WeekdayPetalPainter oldDelegate) =>
      oldDelegate.lengths != lengths ||
      oldDelegate.innerRadius != innerRadius ||
      oldDelegate.maxLength != maxLength ||
      oldDelegate.selectedWeekday != selectedWeekday ||
      oldDelegate.petalColor != petalColor ||
      oldDelegate.ghostColor != ghostColor;
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

/// 按实际花瓣轮廓留出文字区域，旋转后的四角也必须落在花瓣内。
double _petalLabelExtent(double length, double angle) {
  final path = _petalPath(length, _petalWidth(length));
  final rotation = angle + math.pi;
  var low = 0.0;
  var high = _petalWidth(length);
  for (var step = 0; step < 8; step++) {
    final half = (low + high) / 4;
    final fits = [
      for (final x in [-half, half])
        for (final y in [-half, half])
          path.contains(
            Offset(
              x * math.cos(rotation) + y * math.sin(rotation),
              -x * math.sin(rotation) + y * math.cos(rotation) + length * 0.6,
            ),
          ),
    ].every((inside) => inside);
    if (fits) {
      low = half * 2;
    } else {
      high = half * 2;
    }
  }
  return low * 0.9;
}

double _innerRadius(double size) => math.max(40.0, size * 0.16);

double _maxPetalLength(double size) => math.max(60.0, size * 0.25);

double _petalLength(Duration value, Duration max, double maxLength) {
  if (value <= Duration.zero || max <= Duration.zero) return 0;
  final ratio = value.inMicroseconds / max.inMicroseconds;
  final minimum = math.min(40.0, maxLength);
  return minimum + (maxLength - minimum) * math.sqrt(ratio);
}

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
