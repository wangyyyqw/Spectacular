import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../storage/reading_session_store.dart';
import 'reading_insights.dart';

/// 长按菜单折线图固定展示的天数。
const bookReadingChartDayCount = 7;

/// 汇总目标书籍最近 7 个自然日的有序阅读时长。
List<Duration> recentBookReadingDurations(
  Iterable<ReadingSession> sessions, {
  required String bookId,
  required DateTime now,
}) {
  final insights = ReadingInsights(
    sessions.where((session) => session.bookId == bookId),
    now: now,
  );
  final today = DateTime(now.year, now.month, now.day);
  return <Duration>[
    for (var offset = bookReadingChartDayCount - 1; offset >= 0; offset--)
      insights.byDay[DateTime(today.year, today.month, today.day - offset)] ??
          Duration.zero,
  ];
}

/// 书架长按菜单中的单折线日阅读时长图。
class BookReadingChart extends StatelessWidget {
  /// 创建图表；[durations] 按时间从早到晚排列。
  const BookReadingChart({super.key, required this.durations, this.endDate});

  /// 每日阅读时长。
  final List<Duration> durations;

  /// 最后一个数据点对应的日期，缺省为今天。
  final DateTime? endDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final lineColor = dark ? const Color(0xFF7AB9EA) : const Color(0xFF176DB3);
    final end = endDate ?? DateTime.now();
    final lastDate = DateTime(end.year, end.month, end.day);
    final dates = <DateTime>[
      for (var offset = bookReadingChartDayCount - 1; offset >= 0; offset--)
        DateTime(lastDate.year, lastDate.month, lastDate.day - offset),
    ];
    final maximum = durations.fold(
      Duration.zero,
      (value, duration) => duration > value ? duration : value,
    );
    final label = <String>[
      '最近 7 天每日阅读时长折线图',
      '横轴 ${_formatAxisDate(dates.first)} 至 ${_formatAxisDate(dates.last)}',
      '纵轴 0 至 ${_formatAxisDuration(maximum)}',
      for (var index = 0; index < durations.length; index++)
        '${_formatAxisDate(dates[index])} '
            '${formatReadingDuration(durations[index])}',
    ].join('，');
    return Semantics(
      container: true,
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey<String>('book-detail-reading-chart'),
          height: 166,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('最近 7 天', style: theme.textTheme.labelLarge),
                  const Spacer(),
                  Text(
                    '每日阅读时长',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SizedBox.expand(
                  child: CustomPaint(
                    painter: _ReadingLinePainter(
                      durations: durations,
                      dates: dates,
                      lineColor: lineColor,
                      gridColor: theme.colorScheme.outlineVariant.withValues(
                        alpha: dark ? 0.22 : 0.38,
                      ),
                      axisColor: theme.colorScheme.outlineVariant,
                      labelColor: theme.colorScheme.onSurfaceVariant,
                      textScaler: MediaQuery.textScalerOf(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingLinePainter extends CustomPainter {
  const _ReadingLinePainter({
    required this.durations,
    required this.dates,
    required this.lineColor,
    required this.gridColor,
    required this.axisColor,
    required this.labelColor,
    required this.textScaler,
  });

  final List<Duration> durations;
  final List<DateTime> dates;
  final Color lineColor;
  final Color gridColor;
  final Color axisColor;
  final Color labelColor;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (durations.length < 2 ||
        durations.length != dates.length ||
        size.isEmpty) {
      return;
    }
    final maxDuration = durations.fold(
      Duration.zero,
      (value, duration) => duration > value ? duration : value,
    );
    if (maxDuration <= Duration.zero) return;

    final yValues = <Duration>[
      maxDuration,
      Duration(microseconds: maxDuration.inMicroseconds ~/ 2),
      Duration.zero,
    ];
    final yLabels = <TextPainter>[
      for (final value in yValues)
        _labelPainter(
          value <= Duration.zero ? '0' : _formatAxisDuration(value),
        ),
    ];
    final yLabelWidth = yLabels.fold<double>(
      0,
      (width, painter) => math.max(width, painter.width),
    );
    final left = math.max(22.0, yLabelWidth + 7);
    final xHeight = _labelPainter('00/00').height + 4;
    final plot = Rect.fromLTRB(left, 7, size.width - 2, size.height - xHeight);
    if (plot.width <= 0 || plot.height <= 0) return;

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final fraction in const <double>[0, 0.5, 1]) {
      final y = plot.top + plot.height * fraction;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    canvas.drawLine(
      Offset(plot.left, plot.top),
      Offset(plot.left, plot.bottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      axisPaint,
    );
    for (var index = 0; index < yLabels.length; index++) {
      final y = plot.top + plot.height * (index / (yLabels.length - 1));
      final painter = yLabels[index];
      painter.paint(
        canvas,
        Offset(plot.left - painter.width - 5, y - painter.height / 2),
      );
      canvas.drawLine(
        Offset(plot.left - 3, y),
        Offset(plot.left, y),
        axisPaint,
      );
    }

    final step = plot.width / (durations.length - 1);
    final points = <Offset>[
      for (var index = 0; index < durations.length; index++)
        Offset(
          plot.left + step * index,
          plot.bottom -
              plot.height *
                  durations[index].inMicroseconds /
                  maxDuration.inMicroseconds,
        ),
    ];
    final line = _smoothPath(points, plot);
    final area = Path.from(line)
      ..lineTo(plot.right, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            lineColor.withValues(alpha: 0.26),
            lineColor.withValues(alpha: 0.015),
          ],
        ).createShader(plot),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final xLabels = <TextPainter>[
      for (final date in dates) _labelPainter(_formatAxisDate(date)),
    ];
    final maxXLabelWidth = xLabels.fold<double>(
      0,
      (width, painter) => math.max(width, painter.width),
    );
    final stride = math.max(1, ((maxXLabelWidth + 8) / step).ceil());
    final labelIndexes = <int>{
      for (var index = 0; index < dates.length; index += stride) index,
      dates.length - 1,
    }.toList()..sort();
    for (final index in labelIndexes) {
      final x = points[index].dx;
      canvas.drawLine(
        Offset(x, plot.bottom),
        Offset(x, plot.bottom + 3),
        axisPaint,
      );
      final painter = xLabels[index];
      final leftOffset = (x - painter.width / 2)
          .clamp(0.0, size.width - painter.width)
          .toDouble();
      painter.paint(canvas, Offset(leftOffset, plot.bottom + 5));
    }
  }

  TextPainter _labelPainter(String text) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: 9,
        height: 1.2,
        color: labelColor,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();

  Path _smoothPath(List<Offset> points, Rect bounds) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 0; index < points.length - 1; index++) {
      final previous = index == 0 ? points[index] : points[index - 1];
      final current = points[index];
      final next = points[index + 1];
      final following = index + 2 < points.length ? points[index + 2] : next;
      final firstControl = Offset(
        current.dx + (next.dx - previous.dx) / 6,
        (current.dy + (next.dy - previous.dy) / 6).clamp(
          bounds.top,
          bounds.bottom,
        ),
      );
      final secondControl = Offset(
        next.dx - (following.dx - current.dx) / 6,
        (next.dy - (following.dy - current.dy) / 6).clamp(
          bounds.top,
          bounds.bottom,
        ),
      );
      path.cubicTo(
        firstControl.dx,
        firstControl.dy,
        secondControl.dx,
        secondControl.dy,
        next.dx,
        next.dy,
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(_ReadingLinePainter oldDelegate) {
    if (lineColor != oldDelegate.lineColor ||
        gridColor != oldDelegate.gridColor ||
        axisColor != oldDelegate.axisColor ||
        labelColor != oldDelegate.labelColor ||
        textScaler != oldDelegate.textScaler ||
        dates.length != oldDelegate.dates.length ||
        durations.length != oldDelegate.durations.length) {
      return true;
    }
    for (var index = 0; index < dates.length; index++) {
      if (dates[index] != oldDelegate.dates[index]) return true;
    }
    for (var index = 0; index < durations.length; index++) {
      if (durations[index] != oldDelegate.durations[index]) return true;
    }
    return false;
  }
}

String _formatAxisDate(DateTime date) => '${date.month}/${date.day}';

String _formatAxisDuration(Duration duration) {
  if (duration <= Duration.zero) return '0';
  if (duration.inSeconds < 60) {
    return '${math.max(1, (duration.inMilliseconds / 1000).round())}秒';
  }
  final minutes = (duration.inSeconds / 60).round();
  if (minutes < 60) return '$minutes分';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours时' : '$hours时$rest分';
}
