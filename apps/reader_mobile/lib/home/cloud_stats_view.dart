import 'package:flutter/material.dart';

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

  @override
  State<CloudStatsView> createState() => _CloudStatsViewState();
}

enum _CloudPeriod { week, month, year }

class _CloudStatsViewState extends State<CloudStatsView> {
  _CloudPeriod _period = _CloudPeriod.month;

  ReaMicroPeriodStats get _periodStats => switch (_period) {
    _CloudPeriod.week => widget.stats.week,
    _CloudPeriod.month => widget.stats.month,
    _CloudPeriod.year => widget.stats.year,
  };

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
              if (widget.loading) ...<Widget>[
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 14),
              ],
              StatsSection(
                title: '阅读概览',
                detail: '更新于 ${_formatDateTime(stats.fetchedAt)}',
                showDivider: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SummaryGrid(overview: stats.overview),
                    const SizedBox(height: 10),
                    _SplitCard(overview: stats.overview),
                  ],
                ),
              ),
              StatsSection(
                title: '图书时长',
                detail: _periodLabel(_period),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SegmentedButton<_CloudPeriod>(
                      key: const ValueKey<String>('cloud-stats-period'),
                      segments: const <ButtonSegment<_CloudPeriod>>[
                        ButtonSegment<_CloudPeriod>(
                          value: _CloudPeriod.week,
                          label: Text('本周'),
                        ),
                        ButtonSegment<_CloudPeriod>(
                          value: _CloudPeriod.month,
                          label: Text('本月'),
                        ),
                        ButtonSegment<_CloudPeriod>(
                          value: _CloudPeriod.year,
                          label: Text('本年'),
                        ),
                      ],
                      selected: <_CloudPeriod>{_period},
                      onSelectionChanged: (selection) =>
                          setState(() => _period = selection.first),
                    ),
                    const SizedBox(height: 14),
                    _PeriodSummary(stats: _periodStats),
                    const SizedBox(height: 10),
                    _PeriodBars(stats: _periodStats, period: _period),
                    if (_periodStats.topBooks.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      _TopBooks(books: _periodStats.topBooks),
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
      ('阅读书籍', '${overview.bookCount} 本'),
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

class _SplitCard extends StatelessWidget {
  const _SplitCard({required this.overview});

  final ReaMicroOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = overview.totalDurationSeconds > 0
        ? overview.totalDurationSeconds
        : 1;
    final reading = overview.readingDurationSeconds.clamp(0, total).toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('阅读与听书', style: theme.textTheme.labelMedium),
              const Spacer(),
              Flexible(
                child: Text(
                  '阅读 ${_formatSeconds(overview.readingDurationSeconds)}'
                  ' · 听书 ${_formatSeconds(overview.listeningDurationSeconds)}',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: reading / total,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
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
  final _CloudPeriod period;

  @override
  Widget build(BuildContext context) {
    if (period == _CloudPeriod.year) {
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

String _periodLabel(_CloudPeriod period) => switch (period) {
  _CloudPeriod.week => '本周',
  _CloudPeriod.month => '本月',
  _CloudPeriod.year => '本年',
};
