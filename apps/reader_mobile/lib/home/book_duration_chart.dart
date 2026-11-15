import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'book_duration_summary.dart';
import 'reading_insights.dart';

/// 图书时长：按自然周期查看各书投入和占比，保留已移出书架的记录。
class BookDurationChart extends StatefulWidget {
  const BookDurationChart({
    super.key,
    required this.insights,
    this.bookTitles = const {},
    this.now,
  });

  final ReadingInsights insights;
  final Map<String, String> bookTitles;

  /// 测试可固定当前日期；正常使用时取设备本地时间。
  final DateTime? now;

  @override
  State<BookDurationChart> createState() => _BookDurationChartState();
}

class _BookDurationChartState extends State<BookDurationChart>
    with AutomaticKeepAliveClientMixin<BookDurationChart> {
  BookDurationPeriod _period = BookDurationPeriod.day;
  DateTime? _date;

  DateTime get _now => widget.now ?? DateTime.now();

  /// 统计页滚动回收离屏内容时，保留所选周期。
  @override
  bool get wantKeepAlive => true;

  void _changeDate(DateTime? date) => setState(() => _date = date);

  void _openAll(
    BuildContext context,
    BookDurationPeriod period,
    DateTime start,
  ) {
    final summary = BookDurationSummary(
      widget.insights,
      period: period,
      date: start,
      bookTitles: widget.bookTitles,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDurationListPage(
          period: period,
          start: start,
          summary: summary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final summary = BookDurationSummary(
      widget.insights,
      period: _period,
      date: _date ?? _now,
      bookTitles: widget.bookTitles,
    );
    return Column(
      key: const ValueKey('stats-book-duration'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _periodSelector(),
        _navigation(summary),
        if (summary.entries.isEmpty)
          _emptyState(context)
        else
          _breakdown(context, summary),
        Text(
          '按实际前台阅读时长统计',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _periodSelector() => Row(
    children: [
      for (final period in BookDurationPeriod.values)
        Expanded(
          child: _PeriodButton(
            period: period,
            selected: _period == period,
            onTap: () => setState(() {
              _period = period;
              _date = null;
            }),
          ),
        ),
    ],
  );

  Widget _navigation(BookDurationSummary summary) {
    final current = _period.startOf(_now);
    return Column(
      children: [
        _navigationArrows(summary.start, current),
        if (summary.start.isBefore(current))
          TextButton(
            key: const ValueKey('stats-book-duration-current'),
            onPressed: () => _changeDate(null),
            child: Text('回到${_period.currentLabel}'),
          ),
      ],
    );
  }

  Widget _navigationArrows(DateTime start, DateTime current) {
    final hasEarlier = widget.insights.portions.any(
      (portion) =>
          portion.duration > Duration.zero && portion.date.isBefore(start),
    );
    return Row(
      children: [
        IconButton(
          key: const ValueKey('stats-book-duration-previous'),
          tooltip: '上一${_period.label}',
          onPressed: hasEarlier
              ? () => _changeDate(_period.shift(start, -1))
              : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(child: _rangeLabel(start, current)),
        IconButton(
          key: const ValueKey('stats-book-duration-next'),
          tooltip: '下一${_period.label}',
          onPressed: start.isBefore(current)
              ? () => _changeDate(_period.shift(start, 1))
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _rangeLabel(DateTime start, DateTime current) => Text(
    '${start == current ? '${_period.currentLabel} · ' : ''}'
    '${_period.rangeLabel(start)}',
    key: const ValueKey('stats-book-duration-range'),
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 12, height: 1.5),
  );

  Widget _emptyState(BuildContext context) => Padding(
    key: const ValueKey('stats-book-duration-empty'),
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        const Text('该时段没有阅读记录'),
        const SizedBox(height: 8),
        Text(
          '阅读后可在这里查看每本书的用时。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _breakdown(BuildContext context, BookDurationSummary summary) {
    final scheme = Theme.of(context).colorScheme;
    final colors = _chartColors(scheme);
    final tintColors = _tagColors(scheme);
    final slices = _slices(summary, colors, tintColors);
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _CalloutGeometry(
          width: constraints.maxWidth,
          slices: slices,
          total: summary.total,
          largeText: MediaQuery.textScalerOf(context).scale(13) > 17,
        );
        return Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 16),
          child: SizedBox(
            key: const ValueKey('stats-book-duration-callouts'),
            height: geometry.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DurationCalloutPainter(
                      slices: slices,
                      total: summary.total,
                      geometry: geometry,
                      lineColor: Theme.of(context).colorScheme.outline
                          .withValues(alpha: .55),
                    ),
                  ),
                ),
                for (var index = 0; index < slices.length; index++)
                  _calloutTag(
                    context,
                    summary,
                    slices[index],
                    geometry.labels[index],
                  ),
                Positioned(
                  left: geometry.ringRect.left,
                  top: geometry.ringRect.top,
                  width: geometry.ringRect.width,
                  height: geometry.ringRect.height,
                  child: _DurationRing(
                    summary: summary,
                    slices: slices,
                    geometry: geometry,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _calloutTag(
    BuildContext context,
    BookDurationSummary summary,
    _DurationSlice slice,
    Rect rect,
  ) {
    final isOther = slice.id == null;
    final duration = formatReadingDuration(slice.duration);
    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        button: isOther,
        label: isOther
            ? '${slice.title}，$duration，打开图书时长列表'
            : '${slice.title}，$duration',
        onTap: isOther ? () => _openAll(context, _period, summary.start) : null,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('stats-book-duration-tag-${slice.id ?? 'other'}'),
            onTap: isOther
                ? () => _openAll(context, _period, summary.start)
                : null,
            borderRadius: BorderRadius.circular(4),
            child: _tagContent(
              context,
              slice,
              duration,
              isOther,
              summary.entries.length,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tagContent(
    BuildContext context,
    _DurationSlice slice,
    String duration,
    bool isOther,
    int bookCount,
  ) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final narrow = MediaQuery.sizeOf(context).width < 400;
    final secondary = isOther
        ? (narrow
              ? '${bookCount - 4} 本\n$duration'
              : '${bookCount - 4} 本 · $duration')
        : duration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _titleTag(slice, isOther, duration)),
        const SizedBox(height: 3),
        Text(
          secondary,
          key: ValueKey('stats-book-duration-value-${slice.id ?? 'other'}'),
          maxLines: isOther ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isOther ? Theme.of(context).colorScheme.onSurface : muted,
            fontSize: 12,
            height: 1.25,
            fontWeight: isOther ? FontWeight.w600 : FontWeight.w400,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _titleTag(_DurationSlice slice, bool isOther, String duration) =>
      Container(
        constraints: const BoxConstraints(minHeight: 30),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: slice.tint,
          borderRadius: BorderRadius.circular(4),
          border: isOther
              ? Border.all(color: Colors.white.withValues(alpha: .6))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                slice.id == null ? '其他' : slice.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isOther) ...[
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 16,
              ),
            ],
          ],
        ),
      );
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.period,
    required this.selected,
    required this.onTap,
  });

  final BookDurationPeriod period;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
      ),
      child: Semantics(
        label: period.label,
        button: true,
        selected: selected,
        onTap: onTap,
        excludeSemantics: true,
        child: TextButton(
          key: ValueKey('stats-book-duration-period-${period.name}'),
          onPressed: onTap,
          style: _style(scheme),
          child: Text(period.label),
        ),
      ),
    );
  }

  ButtonStyle _style(ColorScheme scheme) => TextButton.styleFrom(
    minimumSize: const Size(0, 48),
    padding: const EdgeInsets.symmetric(horizontal: 2),
    foregroundColor: selected ? scheme.onSurface : scheme.onSurfaceVariant,
    textStyle: TextStyle(
      fontSize: 12,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    ),
  );
}

/// 当前周期的全部图书时长，按投入时间从高到低排列。
class BookDurationListPage extends StatelessWidget {
  const BookDurationListPage({
    super.key,
    required this.period,
    required this.start,
    required this.summary,
  });

  final BookDurationPeriod period;
  final DateTime start;
  final BookDurationSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      key: const ValueKey('stats-book-duration-list-page'),
      appBar: AppBar(
        title: const Text('图书时长'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: theme.colorScheme.outlineVariant),
        ),
      ),
      body: summary.entries.isEmpty
          ? Center(
              child: Text('该时段没有阅读记录', style: TextStyle(color: muted)),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              itemCount: summary.entries.length + 1,
              separatorBuilder: (_, index) => index == 0
                  ? const SizedBox(height: 8)
                  : Divider(height: 1, color: theme.colorScheme.outlineVariant),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _listHeader(theme);
                }
                final entry = summary.entries[index - 1];
                return _DurationListRow(
                  rank: index,
                  entry: entry,
                  total: summary.total,
                );
              },
            ),
    );
  }

  Widget _listHeader(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          period.rangeLabel(start),
          key: const ValueKey('stats-book-duration-list-range'),
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 7),
        Text(
          '${summary.entries.length} 本书 · 合计 ${formatReadingDuration(summary.total)}',
          key: const ValueKey('stats-book-duration-list-summary'),
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.4,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _DurationListRow extends StatelessWidget {
  const _DurationListRow({
    required this.rank,
    required this.entry,
    required this.total,
  });

  final int rank;
  final BookDurationEntry entry;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage =
        entry.duration.inMicroseconds / total.inMicroseconds * 100;
    final share = percentage < .1
        ? '<0.1%'
        : '${percentage.toStringAsFixed(1)}%';
    return Semantics(
      label:
          '第 $rank 名，${entry.title}，${formatReadingDuration(entry.duration)}，占比 $share',
      excludeSemantics: true,
      child: Padding(
        key: ValueKey('stats-book-duration-list-row-$rank'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '$rank',
                style: TextStyle(
                  color: rank <= 3
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: rank <= 3 ? FontWeight.w600 : FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${formatReadingDuration(entry.duration)} · $share',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.4,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _DurationSlice = ({
  String? id,
  String title,
  Duration duration,
  Color color,
  Color tint,
});

List<Color> _chartColors(ColorScheme scheme) => [
  for (final blend in [0.0, 0.18, 0.36, 0.52, 0.66])
    Color.lerp(scheme.primary, scheme.surface, blend)!,
];

List<Color> _tagColors(ColorScheme scheme) => [
  for (final blend in [0.0, .2, .4, .58, .18])
    Color.lerp(scheme.primary, scheme.secondary, blend)!,
];

List<_DurationSlice> _slices(
  BookDurationSummary summary,
  List<Color> colors,
  List<Color> tintColors,
) {
  final count = summary.entries.length > 5 ? 4 : summary.entries.length;
  return [
    for (var index = 0; index < count; index++)
      (
        id: summary.entries[index].bookId,
        title: summary.entries[index].title,
        duration: summary.entries[index].duration,
        color: colors[index],
        tint: tintColors[index],
      ),
    if (summary.entries.length > 5)
      (
        id: null,
        title: '其他 ${summary.entries.length - 4} 本',
        duration: summary.entries
            .skip(4)
            .fold(Duration.zero, (sum, entry) => sum + entry.duration),
        color: colors.last,
        tint: tintColors.last,
      ),
  ];
}

/// 五段标注的布局几何：左三、右二，引线连接每个扇区的中心。
class _CalloutGeometry {
  _CalloutGeometry({
    required double width,
    required List<_DurationSlice> slices,
    required Duration total,
    required bool largeText,
  }) {
    final compact = width < 380;
    final scale = largeText ? 1.3 : 1.0;
    final ringSize = (width * (compact ? .35 : .32)).clamp(
      largeText ? 112.0 : 108.0,
      166.0,
    );
    final labelWidth = ((width - ringSize - 24) / 2).clamp(78.0, 150.0);
    final labelHeight = (compact ? 66.0 : 62.0) * scale;
    final leftX = 0.0;
    final rightX = width - labelWidth;
    final leftCount = slices.length >= 3 ? (slices.length + 1) ~/ 2 : 1;
    final rightCount = slices.length - leftCount;
    final rowCount = math.max(leftCount, rightCount);
    final requiredHeight =
        rowCount * labelHeight + (rowCount - 1) * (compact ? 8 : 16);
    final ringTop = math.max(12.0, (requiredHeight - ringSize) / 2);
    final height = math.max(requiredHeight, ringTop * 2 + ringSize) + 4;
    final centerY = ringTop + ringSize / 2;
    final ringCenter = Offset(width / 2, centerY);
    final cappedRing = ringSize.clamp(0.0, height);
    ringRect = Rect.fromCenter(
      center: ringCenter,
      width: cappedRing,
      height: cappedRing,
    );
    final ringRadius = ringSize / 2;
    final gap = (height - rowCount * labelHeight) / (rowCount + 1);
    final labelInset = math.max(2.0, (height - requiredHeight) / 3);
    final yPositions = <double>[
      for (var row = 0; row < rowCount; row++)
        (gap + row * (labelHeight + gap)).clamp(
          labelInset,
          height - labelHeight - labelInset,
        ),
    ];
    final angles = <double>[];
    var angle = -math.pi / 2;
    for (final slice in slices) {
      final sweep =
          slice.duration.inMicroseconds / total.inMicroseconds * 2 * math.pi;
      angles.add(angle + sweep / 2);
      angle += sweep;
    }
    centerAngle = -math.pi / 2;
    labels = [];
    anchorPoints = [];
    elbowPoints = [];
    for (var index = 0; index < slices.length; index++) {
      final onLeft = index < leftCount;
      final row = onLeft ? index : index - leftCount;
      final left = onLeft ? leftX : rightX;
      final rect = Rect.fromLTWH(
        left,
        yPositions[row],
        labelWidth,
        labelHeight,
      );
      labels.add(rect);
      final sliceAngle = angles[index];
      final anchor = Offset(
        ringCenter.dx + math.cos(sliceAngle) * (ringRadius + 4),
        ringCenter.dy + math.sin(sliceAngle) * (ringRadius + 4),
      );
      anchorPoints.add(anchor);
      final startX = onLeft ? rect.right : rect.left;
      final elbowX = onLeft
          ? startX + (anchor.dx - startX) * .55
          : startX + (anchor.dx - startX) * .55;
      elbowPoints.add(Offset(elbowX, rect.center.dy));
    }
    this.height = height;
  }

  late final Rect ringRect;
  late final List<Rect> labels;
  late final List<Offset> anchorPoints;
  late final List<Offset> elbowPoints;
  late final double height;
  late final double centerAngle;
}

class _DurationCalloutPainter extends CustomPainter {
  const _DurationCalloutPainter({
    required this.slices,
    required this.total,
    required this.geometry,
    required this.lineColor,
  });

  final List<_DurationSlice> slices;
  final Duration total;
  final _CalloutGeometry geometry;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty) return;
    final center = geometry.ringRect.center;
    final radius = geometry.ringRect.width / 2;
    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    var angle = geometry.centerAngle;
    for (var index = 0; index < slices.length; index++) {
      final sweep =
          slices[index].duration.inMicroseconds /
          total.inMicroseconds *
          2 *
          math.pi;
      final mid = angle + sweep / 2;
      final start = Offset(
        center.dx + math.cos(mid) * (radius + 3),
        center.dy + math.sin(mid) * (radius + 3),
      );
      final label = geometry.labels[index];
      final end = Offset(
        index < (slices.length + 1) ~/ 2 ? label.right - 4 : label.left + 4,
        label.center.dy,
      );
      final root = label.center.dy;
      final bendX = (start.dx + end.dx) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(bendX, start.dy)
        ..lineTo(bendX, root)
        ..lineTo(end.dx, root);
      _dashed(canvas, path, paint);
      angle += sweep;
    }
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      for (
        var distance = 0.0;
        distance < metric.length;
        distance += dash + gap
      ) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            math.min(distance + dash, metric.length),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DurationCalloutPainter oldDelegate) =>
      oldDelegate.slices != slices ||
      oldDelegate.total != total ||
      oldDelegate.geometry != geometry ||
      oldDelegate.lineColor != lineColor;
}

class _DurationRing extends StatelessWidget {
  const _DurationRing({
    required this.summary,
    required this.slices,
    required this.geometry,
  });

  final BookDurationSummary summary;
  final List<_DurationSlice> slices;
  final _CalloutGeometry geometry;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${summary.entries.length} 本书，合计 ${formatReadingDuration(summary.total)}',
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: geometry.ringRect.width,
        child: CustomPaint(
          key: const ValueKey('stats-book-duration-ring'),
          painter: _DurationRingPainter(
            slices: slices,
            total: summary.total,
            centerAngle: geometry.centerAngle,
          ),
          child: Center(child: _centerLabel(context)),
        ),
      ),
    ),
  );

  Widget _centerLabel(BuildContext context) => Padding(
    padding: EdgeInsets.all(geometry.ringRect.width * .145),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${summary.entries.length} 本书',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatReadingDuration(summary.total),
            key: const ValueKey('stats-book-duration-total'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

class _DurationRingPainter extends CustomPainter {
  const _DurationRingPainter({
    required this.slices,
    required this.total,
    this.centerAngle = -math.pi / 2,
  });

  final List<_DurationSlice> slices;
  final Duration total;
  final double centerAngle;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (slices.length == 1) {
      canvas.drawCircle(
        rect.center,
        radius,
        paint..color = slices.single.color,
      );
      return;
    }
    var angle = centerAngle;
    for (final slice in slices) {
      final sweep =
          slice.duration.inMicroseconds / total.inMicroseconds * 2 * math.pi;
      paint.color = slice.color;
      _drawSegment(canvas, rect, paint, angle, sweep);
      angle += sweep;
    }
  }

  void _drawSegment(
    Canvas canvas,
    Rect rect,
    Paint paint,
    double angle,
    double sweep,
  ) {
    final cap = 2 * math.asin(paint.strokeWidth / rect.width);
    final rounded = sweep > cap * 2;
    // 极小时段保留真实角度，不为圆角强行放大占比。
    final gap = rounded ? cap + 0.035 : math.min(0.035, sweep * 0.15);
    paint.strokeCap = rounded ? StrokeCap.round : StrokeCap.butt;
    canvas.drawArc(rect, angle + gap / 2, sweep - gap, false, paint);
  }

  @override
  bool shouldRepaint(_DurationRingPainter oldDelegate) =>
      oldDelegate.slices != slices ||
      oldDelegate.total != total ||
      oldDelegate.centerAngle != centerAngle;
}
