import 'dart:async';

import 'package:flutter/material.dart';

import '../rea_micro/rea_micro_book_record_tile.dart';
import '../rea_micro/rea_micro_models.dart';
import 'cloud_reading_calendar.dart';
import 'reading_insights.dart';
import 'stats_section.dart';
import 'weekday_average_chart.dart';

/// 阅微阅读数据视图，沿用统计页自己的分区、日历和排行排版。
class CloudStatsView extends StatefulWidget {
  /// 创建视图。
  const CloudStatsView({
    super.key,
    required this.stats,
    required this.linkedCloudBookIds,
    required this.loading,
    required this.onRefresh,
    required this.onOpenBook,
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

  /// 是否正在刷新。
  final bool loading;

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
      _periodStart(_anchor) == _periodStart(widget.stats.fetchedAt);

  @override
  void initState() {
    super.initState();
    _anchor = widget.stats.fetchedAt;
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
        _records = records == null
            ? null
            : (List.of(records)..sort((left, right) {
                final byTime = right.totalReadTimeSeconds.compareTo(
                  left.totalReadTimeSeconds,
                );
                return byTime != 0 ? byTime : left.name.compareTo(right.name);
              }));
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
                detail: '更新于 ${_formatDateTime(stats.fetchedAt)}',
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
                      _PeriodBars(stats: _data!, period: _period),
                      if (_data!.topBooks.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        _TopBooks(books: _data!.topBooks),
                      ],
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
                        Card(
                          child: Column(
                            children: [
                              for (
                                var index = 0;
                                index < _records!.length;
                                index++
                              ) ...[
                                if (index > 0) const Divider(height: 1),
                                ReaMicroBookRecordTile(
                                  key: ValueKey(
                                    'cloud-duration-record-${_records![index].bookId}',
                                  ),
                                  record: _records![index],
                                  onHide: widget.onHideBookRecord == null
                                      ? null
                                      : () => _hideRecord(_records![index]),
                                  onOpen:
                                      widget.linkedCloudBookIds.contains(
                                        _records![index].cloudBookId,
                                      )
                                      ? () =>
                                            widget.onOpenBook(_records![index])
                                      : null,
                                ),
                              ],
                            ],
                          ),
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
                child: _CloudRanking(
                  books: stats.books,
                  linkedCloudBookIds: widget.linkedCloudBookIds,
                  onOpenBook: widget.onOpenBook,
                ),
              ),
              StatsSection(
                title: '最近阅读',
                detail: '${stats.books.length} 本',
                child: _CloudBookList(
                  books: stats.books,
                  linkedCloudBookIds: widget.linkedCloudBookIds,
                  onOpenBook: widget.onOpenBook,
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
        borderRadius: BorderRadius.circular(14),
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
  const _PeriodBars({required this.stats, required this.period});

  final ReaMicroPeriodStats stats;
  final ReaMicroRecordPeriod period;

  @override
  Widget build(BuildContext context) {
    if (period == ReaMicroRecordPeriod.year) {
      return _Bars(
        labels: <String>[for (final item in stats.months) '${item.month}月'],
        durations: <int>[for (final item in stats.months) item.durationSeconds],
        emptyText: '今年暂无阅读时长',
      );
    }
    return _Bars(
      labels: <String>[for (final item in stats.days) '${item.day}日'],
      durations: <int>[for (final item in stats.days) item.durationSeconds],
      emptyText: '本周期暂无阅读时长',
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({
    required this.labels,
    required this.durations,
    required this.emptyText,
  });

  final List<String> labels;
  final List<int> durations;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (labels.isEmpty || durations.isEmpty) {
      return SizedBox(
        height: 90,
        child: Center(
          child: Text(emptyText, style: theme.textTheme.bodyMedium),
        ),
      );
    }
    final maxDuration = durations.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    return SizedBox(
      height: 126,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = ((constraints.maxWidth / labels.length) * 0.58)
              .clamp(2.0, 18.0)
              .toDouble();
          final spacing = labels.length > 1
              ? (constraints.maxWidth - barWidth * labels.length) /
                    (labels.length - 1)
              : 0.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (var index = 0; index < labels.length; index++) ...<Widget>[
                Expanded(
                  child: Tooltip(
                    message:
                        '${labels[index]}\n'
                        '${_formatSeconds(durations[index])}',
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: barWidth,
                        height: durations[index] <= 0
                            ? 2
                            : 8 +
                                  88 *
                                      (durations[index] / maxDuration)
                                          .clamp(0.0, 1.0)
                                          .toDouble(),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: index == labels.length - 1 ? 1 : 0.42,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                if (index != labels.length - 1)
                  SizedBox(width: spacing > 0 ? spacing : 0),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TopBooks extends StatelessWidget {
  const _TopBooks({required this.books});

  final List<ReaMicroTopBook> books;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('本期阅读最多', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        for (final book in books.take(3))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    book.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatSeconds(book.durationSeconds),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CloudRanking extends StatelessWidget {
  const _CloudRanking({
    required this.books,
    required this.linkedCloudBookIds,
    required this.onOpenBook,
  });

  final List<ReaMicroBookRecord> books;
  final Set<int> linkedCloudBookIds;
  final ValueChanged<ReaMicroBookRecord> onOpenBook;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return Text(
        '阅微账号暂无书籍阅读记录',
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    final ranked = List<ReaMicroBookRecord>.of(books)
      ..sort(
        (left, right) =>
            right.totalReadTimeSeconds.compareTo(left.totalReadTimeSeconds),
      );
    return Column(
      children: <Widget>[
        for (var index = 0; index < ranked.take(3).length; index++) ...[
          if (index > 0) const Divider(height: 1),
          _CloudRankingRow(
            record: ranked[index],
            linked: linkedCloudBookIds.contains(ranked[index].cloudBookId),
            onOpen: () => onOpenBook(ranked[index]),
          ),
        ],
      ],
    );
  }
}

class _CloudRankingRow extends StatelessWidget {
  const _CloudRankingRow({
    required this.record,
    required this.linked,
    required this.onOpen,
  });

  final ReaMicroBookRecord record;
  final bool linked;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      key: ValueKey<String>('cloud-ranking-${record.cloudBookId}'),
      onTap: linked ? onOpen : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CloudCover(url: record.cover),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    record.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  if (record.author.isNotEmpty)
                    Text(
                      record.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  const SizedBox(height: 5),
                  Text(
                    '进度 ${(record.progress * 100).round()}%'
                    ' · 阅读 ${record.readDays} 天'
                    '${record.finished ? ' · 已读完' : ''}',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatSeconds(record.totalReadTimeSeconds),
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudBookList extends StatelessWidget {
  const _CloudBookList({
    required this.books,
    required this.linkedCloudBookIds,
    required this.onOpenBook,
  });

  final List<ReaMicroBookRecord> books;
  final Set<int> linkedCloudBookIds;
  final ValueChanged<ReaMicroBookRecord> onOpenBook;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return Text(
        '阅微账号暂无书籍阅读记录',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Column(
      children: <Widget>[
        for (var index = 0; index < books.length; index++) ...<Widget>[
          if (index > 0) const Divider(height: 1),
          _CloudBookRow(
            record: books[index],
            linked: linkedCloudBookIds.contains(books[index].cloudBookId),
            onOpen: () => onOpenBook(books[index]),
          ),
        ],
      ],
    );
  }
}

class _CloudBookRow extends StatelessWidget {
  const _CloudBookRow({
    required this.record,
    required this.linked,
    required this.onOpen,
  });

  final ReaMicroBookRecord record;
  final bool linked;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      key: ValueKey<String>('cloud-stats-book-${record.cloudBookId}'),
      onTap: linked ? onOpen : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CloudCover(url: record.cover),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          record.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${(record.progress * 100).round()}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (record.author.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      record.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '累计 ${_formatSeconds(record.totalReadTimeSeconds)}'
                    ' · 阅读 ${record.readDays} 天'
                    '${record.finished ? ' · 已读完' : ''}',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: <Widget>[
                      Icon(
                        linked
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_outlined,
                        size: 14,
                        color: linked ? theme.colorScheme.primary : muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        linked ? '已关联本地书籍，可打开' : '仅云端记录，本地未导入',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
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

class _CloudCover extends StatelessWidget {
  const _CloudCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 40,
        height: 54,
        child: url.isEmpty
            ? ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.menu_book_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.menu_book_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
              ),
      ),
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
