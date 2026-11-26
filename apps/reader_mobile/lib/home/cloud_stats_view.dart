import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import '../rea_micro/rea_micro_book_record_tile.dart';
import '../rea_micro/rea_micro_models.dart';
import 'cloud_reading_calendar.dart';
import 'reading_insights.dart';
import 'stats_section.dart';
import 'reading_book_list.dart';
import 'weekday_average_chart.dart';

/// 阅微阅读数据视图，沿用统计页自己的分区、日历和排行排版。
class CloudStatsView extends StatefulWidget {
  /// 创建视图。
  const CloudStatsView({
    super.key,
    required this.stats,
    required this.linkedCloudBookIds,
    required this.loading,
    this.offline = false,
    required this.onRefresh,
    required this.onOpenBook,
    this.linkedUserBookIds = const {},
    this.onLoadMonth,
    this.onLoadHourlyInsights,
    this.onLoadPeriod,
    this.onLoadBookRecords,
    this.onHideBookRecord,
  });

  /// 云端数据快照。
  final ReaMicroCloudStats stats;

  /// 已关联本地书籍的云端标识。
  final Set<int> linkedCloudBookIds;
  final Set<int> linkedUserBookIds;

  /// 是否正在刷新。
  final bool loading;
  final bool offline;

  /// 下拉刷新。
  final Future<void> Function() onRefresh;

  /// 打开书籍。
  final ValueChanged<ReaMicroBookRecord> onOpenBook;

  /// 读取指定月份的阅微统计。
  final Future<ReaMicroPeriodStats> Function(DateTime)? onLoadMonth;

  /// 读取本机真实分时记录；云端仅提供逐日汇总。
  final Future<ReadingInsights> Function()? onLoadHourlyInsights;

  /// 历史周期的汇总与按书阅读记录，共用当前周期选择。
  final Future<ReaMicroPeriodStats> Function(ReaMicroRecordPeriod, DateTime)?
  onLoadPeriod;
  final Future<List<ReaMicroBookRecord>> Function(
    ReaMicroRecordPeriod,
    DateTime,
  )?
  onLoadBookRecords;
  final Future<ReaMicroActionResult> Function(int)? onHideBookRecord;

  @override
  State<CloudStatsView> createState() => _CloudStatsViewState();
}

class _CloudStatsViewState extends State<CloudStatsView> {
  ReaMicroRecordPeriod _period = ReaMicroRecordPeriod.month;
  late DateTime _anchor;
  ReaMicroPeriodStats? _data;
  List<ReaMicroBookRecord>? _records;
  bool _loadingPeriod = false;
  String? _periodError;
  int _request = 0;

  DateTime _periodStart(DateTime date) => switch (_period) {
    ReaMicroRecordPeriod.week => DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday - DateTime.monday)),
    ReaMicroRecordPeriod.month => DateTime(date.year, date.month),
    ReaMicroRecordPeriod.year => DateTime(date.year),
  };

  ReaMicroPeriodStats get _snapshotPeriod => switch (_period) {
    ReaMicroRecordPeriod.week => widget.stats.week,
    ReaMicroRecordPeriod.month => widget.stats.month,
    ReaMicroRecordPeriod.year => widget.stats.year,
  };

  bool get _currentPeriod =>
      _periodStart(_anchor) ==
      _periodStart(widget.stats.periodDate ?? widget.stats.fetchedAt);

  @override
  void initState() {
    super.initState();
    _anchor = widget.stats.periodDate ?? widget.stats.fetchedAt;
    unawaited(_loadPeriod());
  }

  @override
  void didUpdateWidget(CloudStatsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stats, widget.stats)) {
      unawaited(_loadPeriod(preserveData: true));
    }
  }

  Future<void> _loadPeriod({bool preserveData = false}) async {
    final request = ++_request;
    final period = _period;
    final anchor = _anchor;
    final snapshot = _currentPeriod ? _snapshotPeriod : null;
    setState(() {
      _loadingPeriod = true;
      _periodError = null;
      _data = snapshot ?? (preserveData ? _data : null);
      if (!preserveData) _records = null;
    });
    try {
      final loader = widget.onLoadBookRecords;
      final results = await Future.wait<Object?>([
        if (snapshot != null)
          Future.value(snapshot)
        else if (widget.onLoadPeriod != null)
          widget.onLoadPeriod!(period, anchor)
        else
          Future<ReaMicroPeriodStats>.error(Exception('暂无法加载该周期统计')),
        loader == null ? Future.value(null) : loader(period, anchor),
      ]);
      if (!mounted || request != _request) return;
      final records = results[1] as List<ReaMicroBookRecord>?;
      setState(() {
        _data = results[0] as ReaMicroPeriodStats;
        _records = records;
        _loadingPeriod = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loadingPeriod = false;
        _periodError = '该周期阅读记录加载失败';
      });
    }
  }

  void _changePeriod(ReaMicroRecordPeriod period) {
    if (_period == period) return;
    setState(() => _period = period);
    unawaited(_loadPeriod());
  }

  void _shiftPeriod(int direction) {
    setState(() {
      _anchor = switch (_period) {
        ReaMicroRecordPeriod.week => _periodStart(
          _anchor,
        ).add(Duration(days: 7 * direction)),
        ReaMicroRecordPeriod.month => DateTime(
          _anchor.year,
          _anchor.month + direction,
        ),
        ReaMicroRecordPeriod.year => DateTime(_anchor.year + direction),
      };
    });
    unawaited(_loadPeriod());
  }

  String get _dateLabel {
    final start = _periodStart(_anchor);
    return switch (_period) {
      ReaMicroRecordPeriod.week =>
        '${start.month}月${start.day}日 - '
            '${start.add(const Duration(days: 6)).month}月${start.add(const Duration(days: 6)).day}日',
      ReaMicroRecordPeriod.month => '${start.year} 年 ${start.month} 月',
      ReaMicroRecordPeriod.year => '${start.year} 年',
    };
  }

  Future<void> _hideRecord(ReaMicroBookRecord record) async {
    final hide = widget.onHideBookRecord;
    if (hide == null) return;
    final confirmed = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: const Text('隐藏阅读记录？'),
        content: Text('将从阅微阅读记录中隐藏《${record.name}》，不会删除本地书籍。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('隐藏'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await hide(record.bookId);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) {
      setState(
        () => _records = _records
            ?.where((item) => item.bookId != record.bookId)
            .toList(),
      );
      await widget.onRefresh();
    }
  }

  bool _linked(ReaMicroBookRecord book) =>
      book.localBookId != null ||
      widget.linkedUserBookIds.contains(book.bookId) ||
      (book.cloudBookId > 0 &&
          widget.linkedCloudBookIds.contains(book.cloudBookId));

  Widget _bookList(
    List<ReaMicroBookRecord> books,
    String title,
    String allKey, {
    required String prefix,
    ReadingBookSort initialSort = ReadingBookSort.recent,
  }) {
    final period = prefix == 'cloud-duration-record';
    final periodDays = <int, int>{};
    for (final book in _data?.topBooks ?? <ReaMicroTopBook>[]) {
      final id = int.tryParse(book.bookId);
      if (id != null) periodDays[id] = book.readDays;
    }
    final cumulativeDays = {
      for (final book in widget.stats.books) book.bookId: book.readDays,
    };
    return ReadingBookList(
      title: title,
      allKey: ValueKey(allKey),
      initialSort: initialSort,
      books: [
        for (var index = 0; index < books.length; index++)
          cloudReadingBookItem(
            books[index],
            days: period && books[index].readDays == 0
                ? periodDays[books[index].bookId] ??
                      cumulativeDays[books[index].bookId]
                : null,
            daysCumulative:
                period &&
                books[index].readDays == 0 &&
                !periodDays.containsKey(books[index].bookId) &&
                cumulativeDays.containsKey(books[index].bookId),
            linked: _linked(books[index]),
            onOpen: _linked(books[index])
                ? () => widget.onOpenBook(books[index])
                : null,
            onHide: widget.onHideBookRecord == null || books[index].bookId <= 0
                ? null
                : () => _hideRecord(books[index]),
            recentOrder: -index,
            rowKey: ValueKey(
              '$prefix-${books[index].localBookId ?? (prefix == 'cloud-duration-record' ? books[index].bookId : books[index].cloudBookId)}',
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final dailyTotals = _buildDailyTotals(stats);
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: Center(
        child: SizedBox(
          width: 680,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
            children: <Widget>[
              StatsSection(
                title: '阅读概览',
                detail:
                    '${widget.offline ? "离线 · 已合并本地记录 · " : ""}更新于 ${_formatDateTime(stats.fetchedAt)}',
                showDivider: false,
                child: _SummaryGrid(overview: stats.overview),
              ),
              StatsSection(
                title: '图书时长',
                detail: _currentPeriod ? _periodLabel(_period) : _dateLabel,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SegmentedButton<ReaMicroRecordPeriod>(
                      key: const ValueKey<String>('cloud-stats-period'),
                      segments: const <ButtonSegment<ReaMicroRecordPeriod>>[
                        ButtonSegment<ReaMicroRecordPeriod>(
                          value: ReaMicroRecordPeriod.week,
                          label: Text('周'),
                        ),
                        ButtonSegment<ReaMicroRecordPeriod>(
                          value: ReaMicroRecordPeriod.month,
                          label: Text('月'),
                        ),
                        ButtonSegment<ReaMicroRecordPeriod>(
                          value: ReaMicroRecordPeriod.year,
                          label: Text('年'),
                        ),
                      ],
                      selected: <ReaMicroRecordPeriod>{_period},
                      onSelectionChanged: (selection) =>
                          _changePeriod(selection.first),
                    ),
                    if (widget.onLoadPeriod != null)
                      Row(
                        children: [
                          IconButton(
                            key: const ValueKey('cloud-duration-previous'),
                            tooltip: '上一周期',
                            onPressed: () => _shiftPeriod(-1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Text(
                              _dateLabel,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('cloud-duration-next'),
                            tooltip: '下一周期',
                            onPressed: () => _shiftPeriod(1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    const SizedBox(height: 14),
                    if (_periodError != null)
                      Row(
                        children: [
                          Expanded(child: Text(_periodError!)),
                          TextButton(
                            onPressed: _loadPeriod,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    if (_loadingPeriod && _data == null)
                      const Center(child: CircularProgressIndicator()),
                    if (_data != null) ...[
                      _PeriodSummary(stats: _data!),
                      const SizedBox(height: 10),
                      _PeriodBars(
                        stats: _data!,
                        period: _period,
                        anchor: _anchor,
                      ),
                    ],
                    if (widget.onLoadBookRecords != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        '阅读记录 ${_records?.length ?? 0}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_loadingPeriod && _records == null)
                        const Center(child: CircularProgressIndicator())
                      else if (_records?.isEmpty == true)
                        const Text('该周期没有阅微阅读记录。')
                      else if (_records != null)
                        _bookList(
                          _records!,
                          '阅读记录',
                          'cloud-records-all',
                          prefix: 'cloud-duration-record',
                        ),
                    ],
                  ],
                ),
              ),
              StatsSection(
                title: '阅读日历',
                detail: '按月',
                child: CloudReadingCalendar(
                  stats: stats,
                  onLoadMonth: widget.onLoadMonth,
                ),
              ),
              StatsSection(
                title: '每日平均',
                detail: '近 30 天 · 按星期',
                caption: '仅计阅微有阅读记录的日期',
                child: WeekdayAverageChart(
                  insights: ReadingInsights(const [], now: stats.fetchedAt),
                  dailyTotals: dailyTotals,
                  onLoadHourlyInsights: widget.onLoadHourlyInsights,
                ),
              ),
              StatsSection(
                title: '阅读排行',
                detail: '按累计时长',
                child: _bookList(
                  stats.books,
                  '阅读排行',
                  'cloud-ranking-all',
                  prefix: 'cloud-ranking',
                  initialSort: ReadingBookSort.duration,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '统计页展示阅微账号的阅读数据；'
                '已关联书籍的阅读时长和位置按同步设置更新。'
                '本地未导入的云端书籍只展示记录。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Map<DateTime, Duration> _buildDailyTotals(ReaMicroCloudStats stats) {
  final totals = <DateTime, Duration>{};
  void addDay(DateTime date, int seconds) {
    if (seconds <= 0) return;
    totals[DateTime(date.year, date.month, date.day)] = Duration(
      seconds: seconds,
    );
  }

  for (final point in stats.chart) {
    final date = DateTime.tryParse(point.day);
    if (date != null) addDay(date, point.durationSeconds);
  }
  if (totals.isEmpty) {
    final month = stats.monthDate ?? stats.fetchedAt;
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    for (final day in stats.month.days) {
      if (day.day >= 1 && day.day <= lastDay) {
        addDay(DateTime(month.year, month.month, day.day), day.durationSeconds);
      }
    }
  }
  return totals;
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.overview});

  final ReaMicroOverview overview;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('累计阅读', _formatSeconds(overview.totalDurationSeconds)),
      ('阅读天数', '${overview.readDays} 天'),
      ('阅读时长', _formatSeconds(overview.readingDurationSeconds)),
      ('阅读书籍', '${overview.bookCount} 本'),
      ('听书时长', _formatSeconds(overview.listeningDurationSeconds)),
      ('读完书籍', '${overview.finishedBookCount} 本'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            for (final item in items)
              SizedBox(
                width: width,
                child: _MetricCard(label: item.$1, value: item.$2),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: ReaderUiStyle.cardRadiusOf(theme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _PeriodSummary extends StatelessWidget {
  const _PeriodSummary({required this.stats});

  final ReaMicroPeriodStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <String, String>{
      '本期阅读': _formatSeconds(stats.totalDurationSeconds),
      '阅读天数': '${stats.readDays} 天',
      '日均': _formatSeconds(stats.averageDailyDurationSeconds),
      '连续': '${stats.continuousReadDays} 天',
      '书籍': '${stats.bookCount} 本',
      '读完': '${stats.finishedBookCount} 本',
    };
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: <Widget>[
        for (final entry in items.entries)
          Text.rich(
            TextSpan(
              text: '${entry.key} ',
              style: theme.textTheme.bodySmall,
              children: <TextSpan>[
                TextSpan(
                  text: entry.value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PeriodBars extends StatelessWidget {
  const _PeriodBars({
    required this.stats,
    required this.period,
    required this.anchor,
  });
  final ReaMicroPeriodStats stats;
  final ReaMicroRecordPeriod period;
  final DateTime anchor;

  @override
  Widget build(BuildContext context) {
    final start = period == ReaMicroRecordPeriod.week
        ? DateTime(
            anchor.year,
            anchor.month,
            anchor.day,
          ).subtract(Duration(days: anchor.weekday - 1))
        : DateTime(anchor.year, anchor.month);
    final count = switch (period) {
      ReaMicroRecordPeriod.week => 7,
      ReaMicroRecordPeriod.month => DateTime(
        anchor.year,
        anchor.month + 1,
        0,
      ).day,
      ReaMicroRecordPeriod.year => 12,
    };
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final labels = <String>[];
    final durations = <int>[];
    for (var index = 0; index < count; index++) {
      if (period == ReaMicroRecordPeriod.year) {
        labels.add('${index + 1}月');
        durations.add(
          stats.months
                  .where((m) => m.month == index + 1)
                  .firstOrNull
                  ?.durationSeconds ??
              0,
        );
      } else {
        final date = period == ReaMicroRecordPeriod.week
            ? DateTime(start.year, start.month, start.day + index)
            : DateTime(start.year, start.month, index + 1);
        labels.add(
          period == ReaMicroRecordPeriod.week
              ? weekdays[index]
              : '${date.day}日',
        );
        durations.add(
          stats.days
                  .where(
                    (d) =>
                        d.day ==
                        (period == ReaMicroRecordPeriod.week
                            ? index + 1
                            : date.day),
                  )
                  .firstOrNull
                  ?.durationSeconds ??
              0,
        );
      }
    }
    final maximum = durations.fold<int>(0, (a, b) => a > b ? a : b);
    if (maximum == 0) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('本周期暂无阅读时长'),
      );
    }
    final peak = durations.indexOf(maximum);
    final unit = maximum >= 3600 ? 3600 : 60;
    final step = (maximum / unit / 3).ceil().clamp(1, 100000);
    final ceiling = step * unit * 3;
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 186 * scale,
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final slot = constraints.maxWidth / count;
                    return Stack(
                      children: [
                        for (var tick = 0; tick <= 3; tick++)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: tick * constraints.maxHeight / 3,
                            child: Divider(
                              height: 1,
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var index = 0; index < count; index++)
                              Expanded(
                                child: Tooltip(
                                  message:
                                      '${labels[index]} · ${_formatSeconds(durations[index])}',
                                  triggerMode: TooltipTriggerMode.tap,
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      key: ValueKey(
                                        'cloud-duration-bar-$index',
                                      ),
                                      width: (slot * .55).clamp(2, 18),
                                      height: durations[index] == 0
                                          ? 2
                                          : constraints.maxHeight *
                                                durations[index] /
                                                ceiling,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withValues(
                                              alpha: index == peak ? 1 : .5,
                                            ),
                                        borderRadius: BorderRadius.circular(4),
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
              ),
              SizedBox(
                width: 44 * scale,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var tick = 3; tick >= 0; tick--)
                      Text(
                        tick == 0
                            ? '0'
                            : '${step * tick}${unit == 3600 ? 'h' : 'm'}',
                        style: theme.textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.only(right: 44 * scale),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / count;
              final labelWidth = count <= 12 ? slot : 36.0;
              return SizedBox(
                height: 24 * scale,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var index = 0; index < count; index++)
                      if (count <= 12 || index == 0 || (index + 1) % 5 == 0)
                        Positioned(
                          left: slot * (index + .5) - labelWidth / 2,
                          width: labelWidth,
                          child: Text(
                            period == ReaMicroRecordPeriod.week
                                ? labels[index].replaceFirst('周', '')
                                : labels[index].replaceAll(RegExp('[日月]'), ''),
                            key: ValueKey('cloud-duration-tick-$index'),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Container(
          key: const ValueKey('cloud-duration-peak'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            '${labels[peak]}阅读最久 · ${_formatSeconds(maximum)}',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

String _formatSeconds(int seconds) {
  if (seconds <= 0) return '0 分钟';
  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    return minutes <= 0 ? '<1 分钟' : '$minutes 分钟';
  }
  final hours = minutes ~/ 60;
  final remain = minutes % 60;
  return remain == 0 ? '$hours 小时' : '$hours 小时 $remain 分钟';
}

String _formatDateTime(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}

String _periodLabel(ReaMicroRecordPeriod period) => switch (period) {
  ReaMicroRecordPeriod.week => '本周',
  ReaMicroRecordPeriod.month => '本月',
  ReaMicroRecordPeriod.year => '本年',
};
