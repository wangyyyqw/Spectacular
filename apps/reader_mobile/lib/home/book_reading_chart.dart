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
  const BookReadingChart({super.key, required this.durations});

  /// 每日阅读时长。
  final List<Duration> durations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final lineColor = dark ? const Color(0xFF7AB9EA) : const Color(0xFF176DB3);
    final label = <String>[
      '最近 7 天每日阅读时长',
      for (final duration in durations) formatReadingDuration(duration),
    ].join('，');
    return Semantics(
      container: true,
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey<String>('book-detail-reading-chart'),
          height: 126,
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
                      lineColor: lineColor,
                      gridColor: theme.colorScheme.outlineVariant.withValues(
                        alpha: dark ? 0.22 : 0.38,
                      ),
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
    required this.lineColor,
    required this.gridColor,
  });

  final List<Duration> durations;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (durations.length < 2 || size.isEmpty) return;
    final plot = Rect.fromLTRB(2, 4, size.width - 2, size.height - 2);
    if (plot.isEmpty) return;

    final maxMicros = durations.fold<int>(
      0,
      (maximum, duration) =>
          duration.inMicroseconds > maximum ? duration.inMicroseconds : maximum,
    );
    if (maxMicros <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final fraction in const <double>[0.25, 0.5, 0.75]) {
      final y = plot.top + plot.height * fraction;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }

    final step = plot.width / (durations.length - 1);
    final points = <Offset>[
      for (var index = 0; index < durations.length; index++)
        Offset(
          plot.left + step * index,
          plot.bottom -
              plot.height * durations[index].inMicroseconds / maxMicros,
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
  }

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
        durations.length != oldDelegate.durations.length) {
      return true;
    }
    for (var index = 0; index < durations.length; index++) {
      if (durations[index] != oldDelegate.durations[index]) return true;
    }
    return false;
  }
}
