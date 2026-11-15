import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'book_duration_summary.dart';
import 'reading_insights.dart';

const _tagTitleStyle = TextStyle(
  fontSize: 14,
  height: 1.35,
  fontWeight: FontWeight.w600,
);
const _tagDurationStyle = TextStyle(
  fontSize: 12,
  height: 1.4,
  fontFeatures: [FontFeature.tabularFigures()],
);

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
  String? _selectedBookId;

  DateTime get _now => widget.now ?? DateTime.now();

  /// 统计页滚动回收离屏内容时，保留所选周期。
  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(BookDurationChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedBookId == null) return;
    final entries = BookDurationSummary(
      widget.insights,
      period: _period,
      date: _date ?? _now,
      bookTitles: widget.bookTitles,
    ).entries;
    final visible = entries.take(entries.length > 5 ? 4 : entries.length);
    if (!visible.any((entry) => entry.bookId == _selectedBookId)) {
      _selectedBookId = null;
    }
  }

  void _changeDate(DateTime? date) => setState(() {
    _date = date;
    _selectedBookId = null;
  });

  Future<void> _pickPeriod(DateTime start) async {
    final current = _period.startOf(_now);
    final dates = {
      current,
      for (final portion in widget.insights.portions)
        if (portion.duration > Duration.zero && !portion.date.isAfter(_now))
          _period.startOf(portion.date),
    }.toList()..sort((left, right) => right.compareTo(left));
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PeriodPicker(
        period: _period,
        dates: dates,
        selected: start,
        current: current,
      ),
    );
    if (mounted && selected != null) {
      _changeDate(selected == current ? null : selected);
    }
  }

  void _selectSlice(_DurationSlice slice, BookDurationSummary summary) {
    if (slice.id == null) {
      _openAll(context, _period, summary.start);
      return;
    }
    setState(() {
      _selectedBookId = _selectedBookId == slice.id ? null : slice.id;
    });
  }

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
        else ...[
          _summaryHeader(summary),
          _breakdown(context, summary),
          _selectionDetail(summary),
        ],
        const SizedBox(height: 12),
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
              _selectedBookId = null;
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
        Expanded(child: _rangeButton(start, current)),
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

  Widget _rangeButton(DateTime start, DateTime current) => TextButton(
    key: const ValueKey('stats-book-duration-pick-period'),
    onPressed: () => _pickPeriod(start),
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: _rangeLabel(start, current)),
        const SizedBox(width: 4),
        const Icon(Icons.expand_more_rounded, size: 18),
      ],
    ),
  );

  Widget _rangeLabel(DateTime start, DateTime current) => Text(
    '${start == current ? '${_period.currentLabel} · ' : ''}'
    '${_period.rangeLabel(start)}',
    key: const ValueKey('stats-book-duration-range'),
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 13, height: 1.5),
  );

  Widget _summaryHeader(BookDurationSummary summary) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryActions(summary),
        Text(
          formatReadingDuration(summary.total),
          key: const ValueKey('stats-book-duration-total'),
          style: const TextStyle(
            fontSize: 28,
            height: 1.25,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );

  Widget _summaryActions(BookDurationSummary summary) => SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '合计阅读',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        TextButton(
          key: const ValueKey('stats-book-duration-all'),
          onPressed: () => _openAll(context, _period, summary.start),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: Text('全部 ${summary.entries.length} 本 ›'),
        ),
      ],
    ),
  );

  Widget _selectionDetail(BookDurationSummary summary) {
    final entry = summary.entries
        .where((entry) => entry.bookId == _selectedBookId)
        .firstOrNull;
    if (entry == null) {
      return Text(
        '点选书名或圆环，查看时长与占比',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return _selectedEntryDetail(entry, summary.total);
  }

  Widget _selectedEntryDetail(
    BookDurationEntry entry,
    Duration total,
  ) => Semantics(
    liveRegion: true,
    child: Container(
      key: const ValueKey('stats-book-duration-selection'),
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.title, style: const TextStyle(fontSize: 14, height: 1.5)),
          const SizedBox(height: 6),
          Text(
            '${formatReadingDuration(entry.duration)} · 占比 ${_share(entry.duration, total)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
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
    final slices = _slices(summary, colors);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(14) > 19) {
          return _accessibleBreakdown(summary, slices);
        }
        final geometry = _CalloutGeometry(
          width: constraints.maxWidth,
          slices: slices,
          total: summary.total,
          labelHeightForWidth: (width) => _tagHeight(slices, width),
        );
        return _calloutLayout(summary, slices, geometry);
      },
    );
  }

  double _tagHeight(List<_DurationSlice> slices, double width) {
    var height = 48.0;
    for (final slice in slices) {
      final titleWidth = width - 12 - 9 - (slice.id == null ? 16 : 0);
      final title = _textHeight(slice.title, _tagTitleStyle, titleWidth);
      final duration = _textHeight(
        formatReadingDuration(slice.duration),
        _tagDurationStyle,
        width - 12,
      );
      height = math.max(height, 18 + math.max(18, title) + duration);
    }
    return height.ceilToDouble();
  }

  double _textHeight(String text, TextStyle style, double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: Theme.of(context).textTheme.bodyMedium!.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  Widget _calloutLayout(
    BookDurationSummary summary,
    List<_DurationSlice> slices,
    _CalloutGeometry geometry,
  ) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 16),
    child: SizedBox(
      key: const ValueKey('stats-book-duration-callouts'),
      height: geometry.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _calloutLines(summary, slices, geometry),
          for (var index = 0; index < slices.length; index++)
            Positioned.fromRect(
              rect: geometry.labels[index],
              child: _calloutTag(summary, slices[index]),
            ),
          Positioned(
            left: geometry.ringRect.left,
            top: geometry.ringRect.top,
            width: geometry.ringRect.width,
            height: geometry.ringRect.height,
            child: _ring(summary, slices),
          ),
        ],
      ),
    ),
  );

  Widget _calloutLines(
    BookDurationSummary summary,
    List<_DurationSlice> slices,
    _CalloutGeometry geometry,
  ) => Positioned.fill(
    child: CustomPaint(
      painter: _DurationCalloutPainter(
        slices: slices,
        total: summary.total,
        geometry: geometry,
        lineColor: Theme.of(context).colorScheme.outline.withValues(alpha: .55),
      ),
    ),
  );

  Widget _ring(BookDurationSummary summary, List<_DurationSlice> slices) =>
      _DurationRing(
        summary: summary,
        slices: slices,
        selectedBookId: _selectedBookId,
        onSelected: (slice) => _selectSlice(slice, summary),
      );

  Widget _accessibleBreakdown(
    BookDurationSummary summary,
    List<_DurationSlice> slices,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      children: [
        SizedBox.square(dimension: 160, child: _ring(summary, slices)),
        const SizedBox(height: 16),
        for (final slice in slices) _calloutTag(summary, slice, expanded: true),
      ],
    ),
  );

  Widget _calloutTag(
    BookDurationSummary summary,
    _DurationSlice slice, {
    bool expanded = false,
  }) {
    final isOther = slice.id == null;
    final selected = !isOther && _selectedBookId == slice.id;
    final duration = formatReadingDuration(slice.duration);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${slice.title}，$duration，占比 ${_share(slice.duration, summary.total)}'
          '${isOther ? '，打开图书时长列表' : ''}',
      onTap: () => _selectSlice(slice, summary),
      excludeSemantics: true,
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          key: ValueKey('stats-book-duration-tag-${slice.id ?? 'other'}'),
          onTap: () => _selectSlice(slice, summary),
          borderRadius: BorderRadius.circular(4),
          child: _tagContent(slice, duration, expanded: expanded),
        ),
      ),
    );
  }

  Widget _tagContent(
    _DurationSlice slice,
    String duration, {
    required bool expanded,
  }) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: expanded ? 12 : 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tagTitle(slice, expanded: expanded),
          const SizedBox(height: 6),
          Text(
            duration,
            key: ValueKey('stats-book-duration-value-${slice.id ?? 'other'}'),
            maxLines: expanded ? null : 2,
            style: _tagDurationStyle.copyWith(color: muted),
          ),
        ],
      ),
    );
  }

  Widget _tagTitle(_DurationSlice slice, {required bool expanded}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 3,
        height: 16,
        margin: const EdgeInsets.only(top: 2, right: 6),
        color: slice.color,
      ),
      Expanded(
        child: Text(
          slice.title,
          maxLines: expanded ? null : 2,
          overflow: expanded ? null : TextOverflow.ellipsis,
          style: _tagTitleStyle,
        ),
      ),
      if (slice.id == null) const Icon(Icons.chevron_right_rounded, size: 16),
    ],
  );
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({
    required this.period,
    required this.dates,
    required this.selected,
    required this.current,
  });

  final BookDurationPeriod period;
  final List<DateTime> dates;
  final DateTime selected;
  final DateTime current;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '选择阅读时段',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              '列出${period.currentLabel}及有阅读记录的时段',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const ValueKey('stats-book-duration-period-picker'),
              itemCount: dates.length,
              itemBuilder: (context, index) =>
                  _periodTile(context, dates[index]),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _periodTile(BuildContext context, DateTime date) => ListTile(
    key: ValueKey('stats-book-duration-history-${date.toIso8601String()}'),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    selected: date == selected,
    title: Text(
      '${date == current ? '${period.currentLabel} · ' : ''}${period.rangeLabel(date)}',
    ),
    trailing: date == selected ? const Icon(Icons.check_rounded) : null,
    onTap: () => Navigator.of(context).pop(date),
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
    final share = _share(entry.duration, total);
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
});

String _share(Duration duration, Duration total) {
  if (total <= Duration.zero) return '0%';
  final percentage = duration.inMicroseconds / total.inMicroseconds * 100;
  return percentage < .1 ? '<0.1%' : '${percentage.toStringAsFixed(1)}%';
}

List<Color> _chartColors(ColorScheme scheme) => [
  for (final blend in [0.0, 0.18, 0.36, 0.52, 0.66])
    Color.lerp(scheme.primary, scheme.surface, blend)!,
];

List<_DurationSlice> _slices(BookDurationSummary summary, List<Color> colors) {
  final count = summary.entries.length > 5 ? 4 : summary.entries.length;
  return [
    for (var index = 0; index < count; index++)
      (
        id: summary.entries[index].bookId,
        title: summary.entries[index].title,
        duration: summary.entries[index].duration,
        color: colors[index],
      ),
    if (summary.entries.length > 5)
      (
        id: null,
        title: '其他${summary.entries.length - 4}本',
        duration: summary.entries
            .skip(4)
            .fold(Duration.zero, (sum, entry) => sum + entry.duration),
        color: colors.last,
      ),
  ];
}

/// 五段标注的布局几何：标签跟随扇区方位放在左右，引线连接对应扇区中心。
class _CalloutGeometry {
  _CalloutGeometry({
    required double width,
    required List<_DurationSlice> slices,
    required Duration total,
    required double Function(double) labelHeightForWidth,
  }) {
    final compact = width < 380;
    final ringSize = (width * .32).clamp(96.0, 166.0);
    final labelWidth = ((width - ringSize - 20) / 2).clamp(0.0, 150.0);
    final labelHeight = labelHeightForWidth(labelWidth);
    final leftX = 0.0;
    final rightX = width - labelWidth;
    final angles = <double>[];
    var angle = -math.pi / 2;
    for (final slice in slices) {
      final sweep =
          slice.duration.inMicroseconds / total.inMicroseconds * 2 * math.pi;
      angles.add(angle + sweep / 2);
      angle += sweep;
    }
    final leftIndices = <int>[];
    final rightIndices = <int>[];
    for (var index = 0; index < angles.length; index++) {
      (math.cos(angles[index]) < 0 ? leftIndices : rightIndices).add(index);
    }
    int topToBottom(int left, int right) {
      final vertical = math
          .sin(angles[left])
          .compareTo(math.sin(angles[right]));
      return vertical == 0 ? left.compareTo(right) : vertical;
    }

    leftIndices.sort(topToBottom);
    rightIndices.sort(topToBottom);
    final rowCount = math.max(leftIndices.length, rightIndices.length);
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
    final gap = (height - rowCount * labelHeight) / (rowCount + 1);
    final labelInset = math.max(2.0, (height - requiredHeight) / 3);
    final yPositions = <double>[
      for (var row = 0; row < rowCount; row++)
        (gap + row * (labelHeight + gap)).clamp(
          labelInset,
          height - labelHeight - labelInset,
        ),
    ];
    centerAngle = -math.pi / 2;
    labels = List<Rect>.filled(slices.length, Rect.zero);
    labelOnRight = List<bool>.filled(slices.length, false);
    for (final indices in <(List<int>, bool)>[
      (leftIndices, false),
      (rightIndices, true),
    ]) {
      for (var row = 0; row < indices.$1.length; row++) {
        final index = indices.$1[row];
        labels[index] = Rect.fromLTWH(
          indices.$2 ? rightX : leftX,
          yPositions[row],
          labelWidth,
          labelHeight,
        );
        labelOnRight[index] = indices.$2;
      }
    }
    this.height = height;
  }

  late final Rect ringRect;
  late final List<Rect> labels;
  late final List<bool> labelOnRight;
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
        geometry.labelOnRight[index] ? label.left - 4 : label.right + 4,
        label.center.dy,
      );
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(end.dx, end.dy);
      _dashed(canvas, path, paint);
      angle += sweep;
    }
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    const dash = 4.0;
    const gap = 5.0;
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
    required this.selectedBookId,
    required this.onSelected,
  });

  final BookDurationSummary summary;
  final List<_DurationSlice> slices;
  final String? selectedBookId;
  final ValueChanged<_DurationSlice> onSelected;

  _DurationSlice? get _selected => slices
      .where((slice) => slice.id != null && slice.id == selectedBookId)
      .firstOrNull;

  void _onTap(Offset position, Size size) {
    final offset = position - size.center(Offset.zero);
    final radius = (size.shortestSide - 18) / 2;
    if ((offset.distance - radius).abs() > 16) return;
    final angle =
        (math.atan2(offset.dy, offset.dx) + math.pi / 2) % (2 * math.pi);
    var end = 0.0;
    for (final slice in slices) {
      end +=
          slice.duration.inMicroseconds /
          summary.total.inMicroseconds *
          2 *
          math.pi;
      if (angle < end) {
        onSelected(slice);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${summary.entries.length} 本书，合计 ${formatReadingDuration(summary.total)}',
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          onTapUp: (details) =>
              _onTap(details.localPosition, constraints.biggest),
          child: CustomPaint(
            key: const ValueKey('stats-book-duration-ring'),
            painter: _DurationRingPainter(
              slices: slices,
              total: summary.total,
              selectedBookId: _selected?.id,
            ),
            child: Center(child: _centerLabel(context)),
          ),
        ),
      ),
    ),
  );

  Widget _centerLabel(BuildContext context) => Padding(
    padding: const EdgeInsets.all(22),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _selected == null
                ? '${summary.entries.length} 本书'
                : _share(_selected!.duration, summary.total),
            key: const ValueKey('stats-book-duration-ring-value'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _selected == null ? '本期阅读' : '本书占比',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    required this.selectedBookId,
  });

  final List<_DurationSlice> slices;
  final Duration total;
  final String? selectedBookId;

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
    var angle = -math.pi / 2;
    for (final slice in slices) {
      final sweep =
          slice.duration.inMicroseconds / total.inMicroseconds * 2 * math.pi;
      paint.color = selectedBookId == null || slice.id == selectedBookId
          ? slice.color
          : slice.color.withValues(alpha: .25);
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
    final rounded = sweep > cap + 0.035;
    // 极小时段保留真实角度，不为圆角强行放大占比。
    final gap = rounded ? cap + 0.035 : math.min(0.035, sweep * 0.15);
    paint.strokeCap = rounded ? StrokeCap.round : StrokeCap.butt;
    canvas.drawArc(rect, angle + gap / 2, sweep - gap, false, paint);
  }

  @override
  bool shouldRepaint(_DurationRingPainter oldDelegate) =>
      oldDelegate.slices != slices ||
      oldDelegate.total != total ||
      oldDelegate.selectedBookId != selectedBookId;
}
