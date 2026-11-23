import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../rea_micro/rea_micro_controller.dart';
import '../rea_micro/rea_micro_models.dart';
import 'reading_insights.dart';

/// 按日补齐最近一年；仅使用阅微云端时长，未来日期保留空白。
class ReadingHeatmapData {
  ReadingHeatmapData(List<ReaMicroChartPoint> points, DateTime today)
    : end = DateTime(today.year, today.month, today.day) {
    start = DateTime(end.year, end.month, end.day - 364);
    gridStart = DateTime(
      start.year,
      start.month,
      start.day - start.weekday + 1,
    );
    for (final point in points) {
      final parsed = DateTime.tryParse(point.day);
      if (parsed == null) continue;
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      if (day.isBefore(start) || day.isAfter(end)) continue;
      final duration = point.durationSeconds > 0
          ? point.durationSeconds
          : point.readingDurationSeconds + point.listeningDurationSeconds;
      seconds[day] = (seconds[day] ?? 0) + math.max(0, duration);
    }
  }

  final DateTime end;
  late final DateTime start;
  late final DateTime gridStart;
  final Map<DateTime, int> seconds = {};

  int get weeks => (end.difference(gridStart).inDays + 7) ~/ 7;
  int get readingDays => seconds.values.where((value) => value > 0).length;
  DateTime dayAt(int week, int row) =>
      DateTime(gridStart.year, gridStart.month, gridStart.day + week * 7 + row);
  bool contains(DateTime day) => !day.isBefore(start) && !day.isAfter(end);

  /// 零时长与四档强度分开，避免短时阅读被涂成空白。
  int intensity(DateTime day) => switch (seconds[day] ?? 0) {
    <= 0 => 0,
    < 15 * 60 => 1,
    < 30 * 60 => 2,
    < 60 * 60 => 3,
    _ => 4,
  };
}

/// 账号下方的年度阅读热力图，横向浏览月份并点击查看当天时长。
class ReadingHeatmap extends StatefulWidget {
  const ReadingHeatmap({super.key, required this.controller, this.today});

  final ReaMicroController controller;
  final DateTime? today;

  @override
  State<ReadingHeatmap> createState() => _ReadingHeatmapState();
}

class _ReadingHeatmapState extends State<ReadingHeatmap> {
  static const _step = 12.0;
  static const _top = 20.0;
  final _scroll = ScrollController();
  DateTime? _selected;
  int? _accountId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      if (!widget.controller.signedIn) return const SizedBox.shrink();
      if (_accountId != widget.controller.user?.id) {
        _accountId = widget.controller.user?.id;
        _selected = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
      final data = ReadingHeatmapData(
        widget.controller.heatmapChart,
        widget.today ?? DateTime.now(),
      );
      final scheme = Theme.of(context).colorScheme;
      final selected = data.contains(_selected ?? data.end)
          ? _selected ?? data.end
          : data.end;
      final duration = formatReadingDuration(
        Duration(seconds: data.seconds[selected] ?? 0),
      );
      final dateLabel = '${selected.year}年${selected.month}月${selected.day}日';
      return Padding(
        key: const ValueKey('profile-reading-heatmap'),
        padding: const EdgeInsets.only(top: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '阅读热力图',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '近一年阅读 ${data.readingDays} 天',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: _top),
                      child: Column(
                        children: [
                          for (final label in ['一', '', '三', '', '五', '', '日'])
                            SizedBox(
                              height: _step,
                              width: 20,
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: scheme.onSurfaceVariant,
                                ),
                                textScaler: TextScaler.noScaling,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: const ValueKey('heatmap-months'),
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        child: Semantics(
                          label: '最近一年阅微阅读记录，横向滑动查看月份，点击查看日期',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) {
                              final position = details.localPosition;
                              final week = (position.dx / _step).floor();
                              final row = ((position.dy - _top) / _step)
                                  .floor();
                              if (row < 0 ||
                                  row > 6 ||
                                  week < 0 ||
                                  week >= data.weeks) {
                                return;
                              }
                              final day = data.dayAt(week, row);
                              if (data.contains(day)) {
                                setState(() => _selected = day);
                              }
                            },
                            child: CustomPaint(
                              size: Size(data.weeks * _step, _top + 7 * _step),
                              painter: _HeatmapPainter(
                                data: data,
                                scheme: scheme,
                                selected: _selected,
                                fontFamily: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.fontFamily,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$dateLabel · $duration',
                        key: const ValueKey('heatmap-selected-day'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '少',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontSize: 10),
                    ),
                    const SizedBox(width: 6),
                    for (var level = 0; level <= 4; level++)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: SizedBox.square(
                          dimension: 6,
                          child: ColoredBox(color: _cellColor(scheme, level)),
                        ),
                      ),
                    const SizedBox(width: 3),
                    Text(
                      '多',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Color _cellColor(ColorScheme scheme, int intensity) => intensity == 0
    ? scheme.surfaceContainerHighest
    : Color.lerp(
        scheme.surfaceContainerHighest,
        scheme.primary,
        intensity / 4,
      )!;

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.data,
    required this.scheme,
    required this.selected,
    required this.fontFamily,
  });

  final ReadingHeatmapData data;
  final ColorScheme scheme;
  final DateTime? selected;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    const step = _ReadingHeatmapState._step;
    const top = _ReadingHeatmapState._top;
    int? month;
    final firstMonth = DateTime(data.end.year, data.end.month - 11);
    final paint = Paint();
    for (var week = 0; week < data.weeks; week++) {
      final first = data.dayAt(week, 0);
      if (!first.isBefore(firstMonth) && first.month != month) {
        month = first.month;
        final label = TextPainter(
          text: TextSpan(
            text: '$month月',
            style: TextStyle(
              fontSize: 10,
              fontFamily: fontFamily,
              color: scheme.onSurfaceVariant,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(
          canvas,
          Offset(math.min(week * step, size.width - label.width), 0),
        );
        label.dispose();
      }
      for (var row = 0; row < 7; row++) {
        final day = data.dayAt(week, row);
        if (!data.contains(day)) continue;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(week * step, top + row * step, 9, 9),
          const Radius.circular(2),
        );
        paint
          ..style = PaintingStyle.fill
          ..color = _cellColor(scheme, data.intensity(day));
        canvas.drawRRect(rect, paint);
        if (day == selected) {
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = scheme.onSurface;
          canvas.drawRRect(rect, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter oldDelegate) => true;
}
