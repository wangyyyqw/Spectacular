import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

import 'book_duration_summary.dart';
import 'reading_book_color.dart';
import 'reading_insights.dart';
import 'voxel_duration_chart.dart';

const _tagTitleStyle = TextStyle(
  fontSize: 14,
  height: 1.4,
  fontWeight: FontWeight.w600,
);
const _tagDurationStyle = TextStyle(
  fontSize: 14,
  height: 1.4,
  fontFeatures: [FontFeature.tabularFigures()],
);
final _countingHint =
    '单书单日超过 ${minimumDisplayedBookDayDuration.inMinutes} 分钟进入榜单，更多可查看同期全部书籍。';

/// 图书时长：按自然周期查看各书投入和占比，保留已移出书架的记录。
const _selectablePeriods = [
  BookDurationPeriod.day,
  BookDurationPeriod.week,
  BookDurationPeriod.month,
  BookDurationPeriod.year,
];

class BookDurationChart extends StatefulWidget {
  const BookDurationChart({
    super.key,
    required this.insights,
    this.bookTitles = const {},
    this.bookColors = const {},
    this.now,
    this.startWithTimeOfDay = true,
  });

  final ReadingInsights insights;
  final Map<String, String> bookTitles;
  final Map<String, Color> bookColors;

  /// 测试可固定当前日期；正常使用时取设备本地时间。
  final DateTime? now;

  /// 默认展示时段柱状图，点击后切换为按书统计。
  final bool startWithTimeOfDay;

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
    final visible = entries.take(5);
    if (!visible.any((entry) => entry.bookId == _selectedBookId)) {
      _selectedBookId = null;
    }
  }

  void _changeDate(DateTime? date) => setState(() {
    _date = date;
    _selectedBookId = null;
  });

  void _changePeriod(BookDurationPeriod period) {
    if (_period == period) return;
    setState(() {
      _period = period;
      _selectedBookId = null;
    });
  }

  Widget _periodSlider(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedIndex = _selectablePeriods.indexOf(_period);
    final index = selectedIndex < 0 ? 0 : selectedIndex;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segment = constraints.maxWidth / _selectablePeriods.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: index * segment,
                top: 0,
                width: segment,
                height: constraints.maxHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: .08),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final period in _selectablePeriods)
                    Expanded(
                      child: Semantics(
                        label: period.label,
                        button: true,
                        selected: _period == period,
                        onTap: () => _changePeriod(period),
                        excludeSemantics: true,
                        child: InkWell(
                          key: ValueKey(
                            'stats-book-duration-period-${period.name}',
                          ),
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => _changePeriod(period),
                          child: Center(
                            child: Text(
                              period.label,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.2,
                                fontWeight: _period == period
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: _period == period
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _selectSlice(DurationBarData slice) {
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
      applyBookThreshold: false,
    );
    showReaderDrawer<void>(
      context: context,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: BookDurationListPage(
          period: period,
          start: start,
          summary: summary,
          bookColors: widget.bookColors,
          inDrawer: true,
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
    final navigation = _navigation(summary);
    return Column(
      key: const ValueKey('stats-book-duration'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.entries.isEmpty) ...[
          _periodSlider(context),
          const SizedBox(height: 8),
          navigation,
          _emptyState(context, summary),
        ] else ...[
          _breakdown(context, summary, navigation: navigation),
          _selectionDetail(summary),
          _summaryActions(),
        ],
      ],
    );
  }

  Widget _navigation(BookDurationSummary summary) {
    final current = _period.startOf(_now);
    final start = summary.start;
    final hasEarlier = widget.insights.portions.any(
      (portion) =>
          portion.duration > Duration.zero && portion.date.isBefore(start),
    );
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _rangeLabel(start, current),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('stats-book-duration-previous'),
          tooltip: '上一${_period.label}',
          onPressed: hasEarlier
              ? () => _changeDate(_period.shift(start, -1))
              : null,
          icon: const AppIcon(AppGlyph.chevronLeft),
        ),
        IconButton(
          key: const ValueKey('stats-book-duration-next'),
          tooltip: '下一${_period.label}',
          onPressed: start.isBefore(current)
              ? () => _changeDate(_period.shift(start, 1))
              : null,
          icon: const AppIcon(AppGlyph.chevronRight),
        ),
      ],
    );
  }

  Widget _rangeLabel(DateTime start, DateTime current) => Text(
    '${start == current ? '${_period.currentLabel} · ' : ''}'
    '${_period.rangeLabel(start)}',
    key: const ValueKey('stats-book-duration-range'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.left,
    style: const TextStyle(fontSize: 13, height: 1.5),
  );

  Widget _summaryActions() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: AppIcon(
                  AppGlyph.info,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _countingHint,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _selectionDetail(BookDurationSummary summary) {
    final entry = summary.entries
        .where((entry) => entry.bookId == _selectedBookId)
        .firstOrNull;
    if (entry == null) {
      return const SizedBox.shrink();
    }
    return _selectedEntryDetail(entry, summary.total);
  }

  Widget _selectedEntryDetail(BookDurationEntry entry, Duration total) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('stats-book-duration-selection'),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: ReaderUiStyle.cardRadius,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _colorDot(
                readingBookColor(
                  entry.bookId,
                  brightness: scheme.brightness,
                  bookColors: widget.bookColors,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatReadingDuration(entry.duration)} · 占比 ${_share(entry.duration, total)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
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

  Widget _emptyState(BuildContext context, BookDurationSummary summary) =>
      Padding(
        key: const ValueKey('stats-book-duration-empty'),
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            if (summary.total > Duration.zero) ...[
              Text(
                formatReadingDuration(summary.total),
                key: const ValueKey('stats-book-duration-total'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              const Text('该时段暂无符合展示条件的书目'),
            ] else
              const Text('该时段没有阅读记录'),
            const SizedBox(height: 8),
            Text(
              _countingHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (summary.totalBookCount > 0) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: _moreButton(context, summary),
              ),
            ],
          ],
        ),
      );

  Widget _breakdown(
    BuildContext context,
    BookDurationSummary summary, {
    required Widget navigation,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final slices = _slices(summary, scheme, widget.bookColors);
    final timeBars = _timeBars(summary, slices);
    final legend = Column(
      key: const ValueKey('stats-book-duration-legend'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slice in slices.take(3)) _legendRow(summary, slice),
        const SizedBox(height: 6),
        _moreButton(context, summary),
      ],
    );
    final chart = VoxelDurationChart(
      bars: slices,
      timeBars: timeBars,
      total: summary.total,
      bookCount: summary.entries.length,
      selectedBookId: _selectedBookId,
      onSelected: _selectSlice,
      top: _periodSlider(context),
      controls: navigation,
      footer: legend,
      period: _period,
      startWithTimeOfDay: widget.startWithTimeOfDay,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: chart,
    );
  }

  Widget _moreButton(BuildContext context, BookDurationSummary summary) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      key: const ValueKey('stats-book-duration-all'),
      onPressed: () => _openAll(context, _period, summary.start),
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurface,
        shape: ReaderUiStyle.controlShape,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      child: Text('更多 · ${summary.totalBookCount} 本'),
    );
  }

  List<TimeOfDayBarData> _timeBars(
    BookDurationSummary summary,
    List<DurationBarData> slices,
  ) {
    if (_period != BookDurationPeriod.day) {
      return _calendarTimeBars(summary, slices);
    }
    final buckets = List.generate(12, (_) => <String, Duration>{});
    final bookIds = slices.map((slice) => slice.key).toSet();
    final end = _period.shift(summary.start, 1);
    for (final portion in widget.insights.portions) {
      if (portion.date.isBefore(summary.start) ||
          !portion.date.isBefore(end) ||
          !bookIds.contains(portion.bookId)) {
        continue;
      }
      final span = portion.endedAt.difference(portion.startedAt).inMicroseconds;
      if (span <= 0 || portion.duration <= Duration.zero) continue;
      _addPortionToBuckets(buckets, portion, span, portion.bookId);
    }
    return [
      for (var index = 0; index < buckets.length; index++)
        _timeBarData(buckets[index], slices, '${index * 2}-${index * 2 + 2}'),
    ];
  }

  List<TimeOfDayBarData> _calendarTimeBars(
    BookDurationSummary summary,
    List<DurationBarData> slices,
  ) {
    final labels = _calendarLabels(summary.start);
    final buckets = List.generate(labels.length, (_) => <String, Duration>{});
    final bookIds = slices.map((slice) => slice.key).toSet();
    final end = _period.shift(summary.start, 1);
    for (final portion in widget.insights.portions) {
      if (portion.date.isBefore(summary.start) ||
          !portion.date.isBefore(end) ||
          !bookIds.contains(portion.bookId) ||
          portion.duration <= Duration.zero) {
        continue;
      }
      final index = switch (_period) {
        BookDurationPeriod.week => portion.date.weekday - 1,
        BookDurationPeriod.month => portion.date.day - 1,
        _ => portion.date.month - summary.start.month,
      };
      final bucket = buckets[index];
      bucket[portion.bookId] =
          (bucket[portion.bookId] ?? Duration.zero) + portion.duration;
    }
    return [
      for (var index = 0; index < buckets.length; index++)
        _timeBarData(buckets[index], slices, labels[index]),
    ];
  }

  List<String> _calendarLabels(DateTime start) => switch (_period) {
    BookDurationPeriod.week => ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
    BookDurationPeriod.month => List.generate(
      DateTime(start.year, start.month + 1, 0).day,
      (index) => '${index + 1}日',
    ),
    _ => List.generate(
      _period == BookDurationPeriod.year ? 12 : 3,
      (index) => '${start.month + index}月',
    ),
  };

  Widget _legendRow(BookDurationSummary summary, DurationBarData slice) {
    final selected = slice.id != null && _selectedBookId == slice.id;
    final duration = formatReadingDuration(slice.duration);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${slice.title}，$duration，占比 ${slice.share}',
      onTap: () => _selectSlice(slice),
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: ReaderUiStyle.controlRadius,
          side: BorderSide(
            color: selected ? scheme.outlineVariant : Colors.transparent,
          ),
        ),
        child: InkWell(
          key: ValueKey('stats-book-duration-tag-${slice.key}'),
          onTap: () => _selectSlice(slice),
          borderRadius: ReaderUiStyle.controlRadius,
          child: _legendContent(slice, summary.total),
        ),
      ),
    );
  }

  Widget _legendContent(DurationBarData slice, Duration total) => Container(
    constraints: const BoxConstraints(minHeight: 44),
    padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: _legendText(slice, total),
    ),
  );

  Widget _legendText(DurationBarData slice, Duration total) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 290 ||
          MediaQuery.textScalerOf(context).scale(14) > 18;
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Expanded(child: _legendTitle(slice))]),
            const SizedBox(height: 4),
            _legendValues(slice, total, stacked: true),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _legendTitle(slice)),
          const SizedBox(width: 12),
          _legendValues(slice, total, stacked: false),
        ],
      );
    },
  );

  Widget _legendValues(
    DurationBarData slice,
    Duration total, {
    required bool stacked,
  }) {
    final duration = Text(
      formatReadingDuration(slice.duration),
      key: ValueKey('stats-book-duration-value-${slice.key}'),
      style: _tagDurationStyle.copyWith(fontWeight: FontWeight.w600),
    );
    final share = Text(
      slice.share,
      key: ValueKey('stats-book-duration-share-${slice.key}'),
      style: _tagDurationStyle.copyWith(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    if (!stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [duration, const SizedBox(height: 1), share],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [duration, share],
    );
  }

  Widget _legendTitle(DurationBarData slice) => Row(
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: _colorDot(slice.color),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          slice.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _tagTitleStyle,
        ),
      ),
    ],
  );

  static Widget _colorDot(Color color) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// 当前周期的全部图书时长，按投入时间从高到低排列。
class BookDurationListPage extends StatelessWidget {
  const BookDurationListPage({
    super.key,
    required this.period,
    required this.start,
    required this.summary,
    this.bookColors = const {},
    this.inDrawer = false,
  });

  final BookDurationPeriod period;
  final DateTime start;
  final BookDurationSummary summary;
  final Map<String, Color> bookColors;

  /// 从图表进入内容抽屉时使用关闭入口。
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      key: const ValueKey('stats-book-duration-list-page'),
      backgroundColor: inDrawer ? Colors.transparent : null,
      appBar: AppBar(
        backgroundColor: inDrawer ? theme.colorScheme.surface : null,
        automaticallyImplyLeading: !inDrawer,
        leading: inDrawer
            ? IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.maybePop(context),
                icon: const AppIcon(AppGlyph.close),
              )
            : null,
        title: const Text('图书时长'),
        titleTextStyle: inDrawer ? theme.textTheme.titleSmall : null,
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
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
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
                  bookColors: bookColors,
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
    required this.bookColors,
  });

  final int rank;
  final BookDurationEntry entry;
  final Duration total;
  final Map<String, Color> bookColors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = _share(entry.duration, total);
    final color = readingBookColor(
      entry.bookId,
      brightness: theme.brightness,
      bookColors: bookColors,
    );
    return Semantics(
      label:
          '第 $rank 名，${entry.title}，${formatReadingDuration(entry.duration)}，占比 $share',
      excludeSemantics: true,
      child: Padding(
        key: ValueKey('stats-book-duration-list-row-$rank'),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        color: rank <= 3
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: rank <= 3
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                      const SizedBox(height: 5),
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
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: entry.duration.inMicroseconds / total.inMicroseconds,
              color: color,
              backgroundColor: theme.colorScheme.outlineVariant.withValues(
                alpha: .6,
              ),
              minHeight: 4,
              borderRadius: BorderRadius.circular(99),
            ),
          ],
        ),
      ),
    );
  }
}

String _share(Duration duration, Duration total) {
  if (total <= Duration.zero) return '0%';
  final percentage = duration.inMicroseconds / total.inMicroseconds * 100;
  return percentage < .1 ? '<0.1%' : '${percentage.toStringAsFixed(1)}%';
}

List<DurationBarData> _slices(
  BookDurationSummary summary,
  ColorScheme scheme,
  Map<String, Color> bookColors,
) {
  final count = math.min(5, summary.entries.length);
  return [
    for (var index = 0; index < count; index++)
      (
        key: summary.entries[index].bookId,
        id: summary.entries[index].bookId,
        title: summary.entries[index].title,
        shortTitle: _shortBookTitle(summary.entries[index].title),
        share: _share(summary.entries[index].duration, summary.total),
        duration: summary.entries[index].duration,
        color: readingBookColor(
          summary.entries[index].bookId,
          brightness: scheme.brightness,
          bookColors: bookColors,
        ),
      ),
  ];
}

String _shortBookTitle(String title) {
  const limit = 7;
  final runes = title.runes.toList(growable: false);
  if (runes.length <= limit) return title;
  return '${String.fromCharCodes(runes.take(limit - 1))}…';
}

void _addPortionToBuckets(
  List<Map<String, Duration>> buckets,
  ReadingDayPortion portion,
  int span,
  String sliceKey,
) {
  int allocatedAt(DateTime time) =>
      (portion.duration.inMicroseconds *
              (time.difference(portion.startedAt).inMicroseconds / span))
          .round();

  for (var hour = 0; hour < 24; hour += 2) {
    final bucketStart = DateTime(
      portion.startedAt.year,
      portion.startedAt.month,
      portion.startedAt.day,
      hour,
    );
    final bucketEnd = bucketStart.add(const Duration(hours: 2));
    final overlapStart = portion.startedAt.isAfter(bucketStart)
        ? portion.startedAt
        : bucketStart;
    final overlapEnd = portion.endedAt.isBefore(bucketEnd)
        ? portion.endedAt
        : bucketEnd;
    final overlap = overlapEnd.difference(overlapStart).inMicroseconds;
    if (overlap <= 0) continue;
    final allocated = allocatedAt(overlapEnd) - allocatedAt(overlapStart);
    if (allocated <= 0) continue;
    final bucket = buckets[hour ~/ 2];
    bucket[sliceKey] =
        (bucket[sliceKey] ?? Duration.zero) + Duration(microseconds: allocated);
  }
}

TimeOfDayBarData _timeBarData(
  Map<String, Duration> bucket,
  List<DurationBarData> slices,
  String label,
) {
  final segments = [
    for (final slice in slices)
      if ((bucket[slice.key] ?? Duration.zero) > Duration.zero)
        (
          key: slice.key,
          title: slice.title,
          color: slice.color,
          duration: bucket[slice.key]!,
        ),
  ];
  final total = segments.fold(
    Duration.zero,
    (sum, segment) => sum + segment.duration,
  );
  return (key: label, label: label, duration: total, segments: segments);
}
