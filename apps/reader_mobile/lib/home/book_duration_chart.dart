import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import 'book_duration_summary.dart';
import 'reading_book_color.dart';
import 'reading_insights.dart';
import 'voxel_duration_chart.dart';

const _tagTitleStyle = TextStyle(
  fontSize: 14,
  height: 1.35,
  fontWeight: FontWeight.w600,
);
const _tagDurationStyle = TextStyle(
  fontSize: 13,
  height: 1.4,
  fontFeatures: [FontFeature.tabularFigures()],
);
final _countingHint =
    '单书单日超过 ${minimumDisplayedBookDayDuration.inMinutes} 分钟后展示，累计时长包含短时阅读';

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
    final visible = entries.take(4);
    if (!visible.any((entry) => entry.bookId == _selectedBookId)) {
      _selectedBookId = null;
    }
  }

  void _changeDate(DateTime? date) => setState(() {
    _date = date;
    _selectedBookId = null;
  });

  Future<void> _pickPeriod() async {
    final anchor = _date ?? _now;
    final current = _period.startOf(_now);
    final dates = {
      current,
      for (final portion in widget.insights.portions)
        if (portion.duration > Duration.zero && !portion.date.isAfter(_now))
          _period.startOf(portion.date),
    }.toList()..sort((left, right) => right.compareTo(left));
    final picked = await showReaderBottomSheet<(BookDurationPeriod, DateTime)>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PeriodPicker(
        period: _period,
        dates: dates,
        selected: _period.startOf(anchor),
        current: current,
        anchor: anchor,
      ),
    );
    if (mounted && picked != null) {
      final (period, date) = picked;
      setState(() {
        _period = period;
        _date = date == _now || date == period.startOf(_now) ? null : date;
        _selectedBookId = null;
      });
    }
  }

  void _selectSlice(DurationBarData slice, BookDurationSummary summary) {
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
    showReaderDrawer<void>(
      context: context,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: BookDurationListPage(
          period: period,
          start: start,
          summary: summary,
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
          navigation,
          _emptyState(context, summary),
        ] else ...[
          _breakdown(context, summary, navigation: navigation),
          _selectionDetail(summary),
          _summaryActions(summary),
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
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: _rangeButton(start, current)),
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
        const SizedBox(width: 4),
        TextButton(
          key: const ValueKey('stats-book-duration-current'),
          onPressed: () => _changeDate(null),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: EdgeInsets.zero,
            backgroundColor: scheme.surfaceContainerHighest,
            foregroundColor: scheme.onSurface,
            shape: const CircleBorder(),
          ),
          child: const Text('今天', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  Widget _rangeButton(DateTime start, DateTime current) => TextButton(
    key: const ValueKey('stats-book-duration-pick-period'),
    onPressed: _pickPeriod,
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: _rangeLabel(start, current)),
        const SizedBox(width: 4),
        const AppIcon(AppGlyph.chevronDown, size: 18),
      ],
    ),
  );

  Widget _rangeLabel(DateTime start, DateTime current) => Text(
    '${start == current ? '${_period.currentLabel} · ' : ''}'
    '${_period.rangeLabel(start)}',
    key: const ValueKey('stats-book-duration-range'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.left,
    style: const TextStyle(fontSize: 13, height: 1.5),
  );

  Widget _summaryActions(BookDurationSummary summary) {
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
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('stats-book-duration-all'),
              onPressed: () => _openAll(context, _period, summary.start),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: TextStyle(
                  fontSize: 12,
                  fontFamily: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.fontFamily,
                ),
              ),
              iconAlignment: IconAlignment.end,
              icon: const AppIcon(AppGlyph.chevronRight, size: 16),
              label: Text('查看全部 ${summary.entries.length} 本'),
            ),
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
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _colorDot(
                readingBookColor(entry.bookId, brightness: scheme.brightness),
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
          ],
        ),
      );

  Widget _breakdown(
    BuildContext context,
    BookDurationSummary summary, {
    required Widget navigation,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final slices = _slices(summary, scheme);
    final timeBars = _timeBars(summary, slices);
    final chart = VoxelDurationChart(
      bars: slices,
      timeBars: timeBars,
      total: summary.total,
      bookCount: summary.entries.length,
      selectedBookId: _selectedBookId,
      onSelected: (slice) => _selectSlice(slice, summary),
      controls: navigation,
    );
    final legend = Column(
      key: const ValueKey('stats-book-duration-legend'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final slice in slices) _legendRow(summary, slice)],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final wide = constraints.maxWidth >= 600 && textScale <= 1.35;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: chart),
                const SizedBox(width: 24),
                Expanded(flex: 4, child: legend),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [chart, const SizedBox(height: 18), legend],
          );
        },
      ),
    );
  }

  List<TimeOfDayBarData> _timeBars(
    BookDurationSummary summary,
    List<DurationBarData> slices,
  ) {
    final buckets = List.generate(12, (_) => <String, Duration>{});
    final entryIndex = {
      for (var index = 0; index < summary.entries.length; index++)
        summary.entries[index].bookId: index,
    };
    final end = _period.shift(summary.start, 1);
    for (final portion in widget.insights.portions) {
      if (portion.date.isBefore(summary.start) || !portion.date.isBefore(end)) {
        continue;
      }
      final span = portion.endedAt.difference(portion.startedAt).inMicroseconds;
      if (span <= 0 || portion.duration <= Duration.zero) continue;
      final position = entryIndex[portion.bookId];
      final sliceKey = position == null
          ? 'short-reading'
          : position < 4
          ? portion.bookId
          : 'other';
      _addPortionToBuckets(buckets, portion, span, sliceKey);
    }
    return [
      for (var index = 0; index < buckets.length; index++)
        _timeBarData(index, buckets[index], slices),
    ];
  }

  Widget _legendRow(BookDurationSummary summary, DurationBarData slice) {
    final opensList = slice.id == null;
    final selected = slice.id != null && _selectedBookId == slice.id;
    final duration = formatReadingDuration(slice.duration);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${slice.title}，$duration，占比 ${slice.share}'
          '${opensList ? '，打开图书时长列表' : ''}',
      onTap: () => _selectSlice(slice, summary),
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? scheme.outlineVariant : Colors.transparent,
          ),
        ),
        child: InkWell(
          key: ValueKey('stats-book-duration-tag-${slice.key}'),
          onTap: () => _selectSlice(slice, summary),
          borderRadius: BorderRadius.circular(10),
          child: _legendContent(slice, summary.total),
        ),
      ),
    );
  }

  Widget _legendContent(DurationBarData slice, Duration total) => Container(
    constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
    padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _legendText(slice, total),
        const SizedBox(height: 9),
        LinearProgressIndicator(
          value: slice.duration.inMicroseconds / total.inMicroseconds,
          color: slice.color,
          backgroundColor: Theme.of(context).colorScheme.outlineVariant
              .withValues(alpha: .6),
          minHeight: 4,
          borderRadius: BorderRadius.circular(99),
        ),
      ],
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
            Row(
              children: [
                Expanded(child: _legendTitle(slice)),
                if (slice.id == null) _legendChevron(),
              ],
            ),
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
          if (slice.id == null) _legendChevron(),
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
        fontSize: 11,
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
      const SizedBox(width: 8),
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

  Widget _legendChevron() => const Padding(
    padding: EdgeInsets.only(left: 4, top: 2),
    child: AppIcon(AppGlyph.chevronRight, size: 16),
  );

  static Widget _colorDot(Color color) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({
    required this.period,
    required this.dates,
    required this.selected,
    required this.current,
    required this.anchor,
  });

  final BookDurationPeriod period;
  final List<DateTime> dates;
  final DateTime selected;
  final DateTime current;
  final DateTime anchor;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '选择阅读周期',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              '切换周期，或选择有阅读记录的日期',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: [
                    for (final type in BookDurationPeriod.values)
                      Expanded(
                        child: _PeriodButton(
                          period: type,
                          selected: type == period,
                          onTap: () =>
                              Navigator.of(context).pop((type, anchor)),
                        ),
                      ),
                  ],
                ),
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
    trailing: date == selected ? const AppIcon(AppGlyph.check) : null,
    onTap: () => Navigator.of(context).pop((period, date)),
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
  Widget build(BuildContext context) => Semantics(
    label: period.label,
    button: true,
    selected: selected,
    onTap: onTap,
    excludeSemantics: true,
    child: TextButton(
      key: ValueKey('stats-book-duration-period-${period.name}'),
      onPressed: onTap,
      style: _style(Theme.of(context)),
      child: Text(period.label),
    ),
  );

  ButtonStyle _style(ThemeData theme) => TextButton.styleFrom(
    minimumSize: const Size(0, kMinInteractiveDimension),
    padding: const EdgeInsets.symmetric(horizontal: 2),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    backgroundColor: selected ? theme.colorScheme.primary : null,
    foregroundColor: selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant,
    textStyle: TextStyle(
      fontSize: 13,
      fontFamily: theme.textTheme.bodyMedium?.fontFamily,
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
    this.inDrawer = false,
  });

  final BookDurationPeriod period;
  final DateTime start;
  final BookDurationSummary summary;

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
    final color = readingBookColor(entry.bookId, brightness: theme.brightness);
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

List<DurationBarData> _slices(BookDurationSummary summary, ColorScheme scheme) {
  final count = math.min(4, summary.entries.length);
  final displayed = summary.entries.fold(
    Duration.zero,
    (sum, entry) => sum + entry.duration,
  );
  final otherCount = summary.entries.length - count;
  final otherDuration = summary.entries
      .skip(count)
      .fold(Duration.zero, (sum, entry) => sum + entry.duration);
  final shortDuration = summary.total - displayed;
  final otherColor = scheme.onSurfaceVariant;
  final shortColor = Color.lerp(otherColor, scheme.surface, .45)!;
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
        ),
      ),
    if (otherCount > 0)
      (
        key: 'other',
        id: null,
        title: '其他$otherCount本',
        shortTitle: '其他$otherCount本',
        share: _share(otherDuration, summary.total),
        duration: otherDuration,
        color: otherColor,
      ),
    if (shortDuration > Duration.zero)
      (
        key: 'short-reading',
        id: null,
        title: '短时阅读',
        shortTitle: '短时阅读',
        share: _share(shortDuration, summary.total),
        duration: shortDuration,
        color: shortColor,
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
  int index,
  Map<String, Duration> bucket,
  List<DurationBarData> slices,
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
  final label = '${index * 2}-${index * 2 + 2}';
  return (key: label, label: label, duration: total, segments: segments);
}
