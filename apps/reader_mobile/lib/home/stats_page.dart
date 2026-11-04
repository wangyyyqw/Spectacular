import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/library_store.dart';
import '../reader/book_opener.dart';
import '../storage/reading_session_store.dart';

enum _ProgressBand {
  unread('未开始'),
  finished('已读完'),
  early('0-25%'),
  middle('26-50%'),
  advanced('51-75%'),
  late('76-100%');

  const _ProgressBand(this.label);

  final String label;
}

/// 统计页：书量、阅读进度、近七日阅读与最近阅读。
///
/// 数据来自书架、阅读进度、阅读会话和导入期字符统计。
class StatsPage extends StatefulWidget {
  /// 创建页面。
  const StatsPage({
    super.key,
    required this.library,
    required this.progressStore,
    this.sessionStore,
    this.refreshToken = 0,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 进度存储。
  final ReaderProgressStore progressStore;

  /// 可注入的阅读会话存储；为空时使用书架数据库实现。
  final ReadingSessionStore? sessionStore;

  /// 外部切换页面时递增，用于重新读取阅读进度和会话数据。
  final int refreshToken;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late final BookOpener _bookOpener;
  _LibraryStats? _stats;
  int _reloadToken = 0;

  ReadingSessionStore? get _sessionStore =>
      widget.sessionStore ?? widget.library.readingSessionStore();

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_reload);
    _bookOpener = BookOpener(
      library: widget.library,
      progressStore: widget.progressStore,
    );
    _reload();
  }

  @override
  void dispose() {
    widget.library.removeListener(_reload);
    super.dispose();
  }

  @override
  void didUpdateWidget(StatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.sessionStore != widget.sessionStore) {
      _reload();
    }
  }

  Future<void> _reload() async {
    final token = ++_reloadToken;
    final books = await widget.library.list();
    final progress = await widget.progressStore.snapshot();
    final sessions =
        await (_sessionStore?.list() ??
            Future<List<ReadingSession>>.value(const <ReadingSession>[]));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final readingByDay = _readingByDay(sessions);
    final totalReading = sessions.fold<Duration>(
      Duration.zero,
      (total, session) => total + session.duration,
    );
    final pageTurns = sessions.fold<int>(
      0,
      (total, session) => total + session.pageTurns,
    );
    final charactersRead = sessions.fold<int>(
      0,
      (total, session) => total + session.charactersRead,
    );
    final rows = <_BookReadingStat>[];
    var started = 0;
    var finished = 0;
    var totalCharacters = 0;
    var percentSum = 0;
    var percentCount = 0;
    for (final book in books) {
      final weights = await widget.library.progressWeights(book.id);
      final current = progress[book.id];
      int? percent;
      if (current != null && weights.total > 0) {
        percent = weights.percentInt(current.spineIndex);
        percentSum += percent;
        percentCount += 1;
      }
      if (current != null) {
        started += 1;
        if (current.finished) {
          finished += 1;
        }
      }
      totalCharacters += weights.totalCharacters;
      rows.add(
        _BookReadingStat(book: book, progress: current, percent: percent),
      );
    }
    rows.sort((left, right) {
      final leftTime = left.book.lastReadAt;
      final rightTime = right.book.lastReadAt;
      if (leftTime == null && rightTime == null) {
        return right.book.addedAt.compareTo(left.book.addedAt);
      }
      if (leftTime == null) {
        return 1;
      }
      if (rightTime == null) {
        return -1;
      }
      return rightTime.compareTo(leftTime);
    });
    final activityDates = <DateTime>[
      for (var offset = -6; offset <= 0; offset++)
        DateTime(today.year, today.month, today.day + offset),
    ];
    final activityCounts = <DateTime, int>{};
    var recent = 0;
    for (final row in rows) {
      final lastReadAt = row.book.lastReadAt;
      if (lastReadAt == null) {
        continue;
      }
      final date = DateTime(lastReadAt.year, lastReadAt.month, lastReadAt.day);
      if (date.isBefore(activityDates.first)) {
        continue;
      }
      recent += 1;
      activityCounts[date] = (activityCounts[date] ?? 0) + 1;
    }
    final activity = <_DailyReading>[
      for (final date in activityDates)
        _DailyReading(
          date: date,
          books: activityCounts[date] ?? 0,
          duration: readingByDay[date] ?? Duration.zero,
        ),
    ];
    final stats = _LibraryStats(
      rows: rows,
      started: started,
      finished: finished,
      recent: recent,
      activeDays: activity.where((day) => day.books > 0).length,
      activity: activity,
      totalCharacters: totalCharacters,
      averageProgress: percentCount == 0
          ? null
          : (percentSum / percentCount).round(),
      todayReading: readingByDay[today] ?? Duration.zero,
      totalReading: totalReading,
      readingDays: readingByDay.length,
      pageTurns: pageTurns,
      charactersRead: charactersRead,
      hasReadingSessions: sessions.isNotEmpty,
    );
    if (mounted && token == _reloadToken) {
      setState(() => _stats = stats);
    }
  }

  Future<void> _openBook(BookEntry entry) async {
    await _bookOpener.open(context, entry);
    if (mounted) {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
        actions: [
          IconButton(
            key: const ValueKey<String>('stats-refresh'),
            tooltip: '刷新统计',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: stats == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  _OverviewCard(stats: stats),
                  const SizedBox(height: 12),
                  _ReadingTimeCard(stats: stats),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MetricTile(
                        icon: Icons.library_books_outlined,
                        label: '总书数',
                        value: '${stats.rows.length}',
                        valueKey: const ValueKey<String>('stats-total-books'),
                      ),
                      const SizedBox(width: 8),
                      _MetricTile(
                        icon: Icons.local_fire_department_outlined,
                        label: stats.hasReadingSessions ? '近7天阅读' : '近7天活跃',
                        value: '${stats.weekReadingDays}',
                        valueKey: const ValueKey<String>('stats-recent-7-days'),
                      ),
                      const SizedBox(width: 8),
                      _MetricTile(
                        icon: Icons.text_fields,
                        label: '书库字数',
                        value: _formatCharacters(stats.totalCharacters),
                        valueKey: const ValueKey<String>(
                          'stats-total-characters',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _MetricTile(
                        icon: Icons.swipe_left_alt,
                        label: '翻页次数',
                        value: '${stats.pageTurns}',
                        valueKey: const ValueKey<String>('stats-page-turns'),
                      ),
                      const SizedBox(width: 8),
                      _MetricTile(
                        icon: Icons.auto_stories_outlined,
                        label: '阅读字数',
                        value: _formatMetricCharacters(stats.charactersRead),
                        valueKey: const ValueKey<String>(
                          'stats-characters-read',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _WeekActivityCard(stats: stats),
                  const SizedBox(height: 24),
                  _SectionTitle(
                    title: '阅读分布',
                    detail: '${stats.started} / ${stats.rows.length} 本已开始',
                  ),
                  const SizedBox(height: 10),
                  _DistributionCard(stats: stats),
                  const SizedBox(height: 24),
                  const _SectionTitle(title: '最近阅读'),
                  const SizedBox(height: 10),
                  if (stats.rows.every((row) => row.book.lastReadAt == null))
                    const _NoReadingCard()
                  else
                    for (final row in stats.rows.where(
                      (row) => row.book.lastReadAt != null,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RecentBookCard(
                          stat: row,
                          onOpen: () => _openBook(row.book),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}

class _LibraryStats {
  const _LibraryStats({
    required this.rows,
    required this.started,
    required this.finished,
    required this.recent,
    required this.activeDays,
    required this.activity,
    required this.totalCharacters,
    required this.averageProgress,
    required this.todayReading,
    required this.totalReading,
    required this.readingDays,
    required this.pageTurns,
    required this.charactersRead,
    required this.hasReadingSessions,
  });

  final List<_BookReadingStat> rows;
  final int started;
  final int finished;
  final int recent;
  final int activeDays;
  final List<_DailyReading> activity;
  final int totalCharacters;
  final int? averageProgress;
  final Duration todayReading;
  final Duration totalReading;
  final int readingDays;
  final int pageTurns;
  final int charactersRead;
  final bool hasReadingSessions;

  int get weekReadingDays => hasReadingSessions
      ? activity.where((day) => day.duration > Duration.zero).length
      : activeDays;
}

class _DailyReading {
  const _DailyReading({
    required this.date,
    required this.books,
    required this.duration,
  });

  final DateTime date;
  final int books;
  final Duration duration;
}

class _BookReadingStat {
  const _BookReadingStat({
    required this.book,
    required this.progress,
    required this.percent,
  });

  final BookEntry book;
  final ReaderProgress? progress;
  final int? percent;
}

_ProgressBand _progressBand(_BookReadingStat stat) {
  if (stat.progress == null) {
    return _ProgressBand.unread;
  }
  if (stat.progress!.finished) {
    return _ProgressBand.finished;
  }
  final percent = stat.percent ?? 0;
  if (percent <= 25) {
    return _ProgressBand.early;
  }
  if (percent <= 50) {
    return _ProgressBand.middle;
  }
  if (percent <= 75) {
    return _ProgressBand.advanced;
  }
  return _ProgressBand.late;
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.stats});

  final _LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final average = stats.averageProgress;
    final progress = average == null ? 0.0 : average / 100;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.tertiaryContainer.withValues(alpha: 0.78),
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '阅读进度',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  average == null
                      ? '还没有开始阅读'
                      : stats.finished == 0
                      ? '已开始 ${stats.started} 本书'
                      : '已开始 ${stats.started} 本 · 已读完 ${stats.finished} 本',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.76,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  average == null
                      ? '从书架打开一本书，进度会同步到这里。'
                      : stats.finished > 0
                      ? '完成一本书也值得记录。'
                      : '保持节奏，继续下一章。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.68,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: theme.colorScheme.onPrimaryContainer
                        .withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                ),
                Text(
                  average == null ? '--' : '$average%',
                  key: const ValueKey<String>('stats-average-progress'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingTimeCard extends StatelessWidget {
  const _ReadingTimeCard({required this.stats});

  final _LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSessions = stats.hasReadingSessions;
    return Card(
      key: const ValueKey<String>('stats-reading-time'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.timer_outlined,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '今天已读',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasSessions
                        ? _formatReadingDuration(stats.todayReading)
                        : '--',
                    key: const ValueKey<String>('stats-today-reading'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hasSessions ? '共 ${stats.readingDays} 天' : '等待开始阅读',
                  key: const ValueKey<String>('stats-reading-days'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasSessions
                      ? '累计 ${_formatReadingDuration(stats.totalReading)}'
                      : '只记录前台阅读',
                  key: const ValueKey<String>('stats-total-reading'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(height: 10),
              Text(
                value,
                key: valueKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekActivityCard extends StatelessWidget {
  const _WeekActivityCard({required this.stats});

  final _LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final useDuration = stats.hasReadingSessions;
    final maxValue = stats.activity.fold<int>(0, (maximum, day) {
      final value = useDuration ? day.duration.inSeconds : day.books;
      return value > maximum ? value : maximum;
    });
    final weekDuration = stats.activity.fold<Duration>(
      Duration.zero,
      (total, day) => total + day.duration,
    );
    final readingDays = stats.activity
        .where((day) => day.duration > Duration.zero)
        .length;
    final summary = useDuration
        ? '${_formatReadingDuration(weekDuration)} · $readingDays 天'
        : '${stats.activeDays} 天活跃 · ${stats.recent} 本书';
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    return Card(
      key: const ValueKey<String>('stats-week-activity'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    useDuration ? '近 7 天阅读时长' : '近 7 天阅读',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  summary,
                  key: const ValueKey<String>('stats-activity-summary'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 104,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < stats.activity.length; index++)
                    Expanded(
                      child: _ActivityBar(
                        day: stats.activity[index],
                        maxValue: maxValue,
                        useDuration: useDuration,
                        weekday: index == stats.activity.length - 1
                            ? '今天'
                            : '周${weekdays[stats.activity[index].date.weekday - 1]}',
                        countKey: ValueKey<String>(
                          'stats-activity-count-$index',
                        ),
                        barKey: ValueKey<String>('stats-activity-bar-$index'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              useDuration ? '按实际前台阅读时长统计' : '按每本书的最后阅读日期统计',
              key: const ValueKey<String>('stats-activity-caption'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityBar extends StatelessWidget {
  const _ActivityBar({
    required this.day,
    required this.maxValue,
    required this.useDuration,
    required this.weekday,
    required this.countKey,
    required this.barKey,
  });

  final _DailyReading day;
  final int maxValue;
  final bool useDuration;
  final String weekday;
  final Key countKey;
  final Key barKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = useDuration ? day.duration.inSeconds : day.books;
    final hasActivity = value > 0;
    final ratio = maxValue == 0 ? 0.0 : value / maxValue;
    final label = useDuration
        ? _formatActivityDuration(day.duration)
        : '$value';
    final tooltip = useDuration
        ? '${day.date.month}月${day.date.day}日 · '
              '${_formatReadingDuration(day.duration)} · ${day.books} 本书'
        : '${day.date.month}月${day.date.day}日 · ${day.books} 本';
    return Tooltip(
      message: tooltip,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            label,
            key: countKey,
            style: theme.textTheme.labelSmall?.copyWith(
              color: hasActivity
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: hasActivity ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            key: barKey,
            width: 18,
            height: hasActivity ? 8 + ratio * 52 : 5,
            decoration: BoxDecoration(
              color: hasActivity
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            weekday,
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: hasActivity
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: weekday == '今天' ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        if (detail != null)
          Text(
            detail!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.stats});

  final _LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = stats.rows.length;
    int count(_ProgressBand band) =>
        stats.rows.where((row) => _progressBand(row) == band).length;
    final bands = <(_ProgressBand, Color, int)>[
      (
        _ProgressBand.unread,
        theme.colorScheme.surfaceContainerHighest,
        count(_ProgressBand.unread),
      ),
      (
        _ProgressBand.finished,
        theme.colorScheme.secondary,
        count(_ProgressBand.finished),
      ),
      (
        _ProgressBand.early,
        theme.colorScheme.tertiaryContainer,
        count(_ProgressBand.early),
      ),
      (
        _ProgressBand.middle,
        theme.colorScheme.tertiary,
        count(_ProgressBand.middle),
      ),
      (
        _ProgressBand.advanced,
        theme.colorScheme.primary.withAlpha(170),
        count(_ProgressBand.advanced),
      ),
      (
        _ProgressBand.late,
        theme.colorScheme.primary,
        count(_ProgressBand.late),
      ),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 10,
                child: total == 0
                    ? ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final band in bands)
                            if (band.$3 > 0)
                              Expanded(
                                flex: band.$3,
                                child: ColoredBox(color: band.$2),
                              ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                for (final band in bands)
                  _Legend(
                    color: band.$2,
                    label: '${band.$1.label} ${band.$3} 本',
                    textKey: ValueKey<String>('stats-band-${band.$1.name}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.textKey,
  });

  final Color color;
  final String label;
  final Key textKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, key: textKey, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _RecentBookCard extends StatelessWidget {
  const _RecentBookCard({required this.stat, required this.onOpen});

  final _BookReadingStat stat;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = stat.book;
    final percent = stat.percent;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('stats-open-${book.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _BookCover(book: book),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _positionLabel(book, stat.progress),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        value: percent == null ? 0 : percent / 100,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    percent == null ? '--' : '$percent%',
                    key: ValueKey<String>('stats-book-${book.id}'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _relativeTime(book.lastReadAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final BookEntry book;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 42,
      height: 56,
      decoration: BoxDecoration(
        color: HSLColor.fromAHSL(
          1,
          book.coverHue.toDouble(),
          0.42,
          0.38,
        ).toColor(),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        book.title.isEmpty ? '书' : book.title.characters.first,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final coverPath = book.coverPath;
    return Hero(
      tag: bookCoverHeroTag(book.id),
      transitionOnUserGestures: true,
      child: coverPath == null
          ? placeholder
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(coverPath),
                width: 42,
                height: 56,
                fit: BoxFit.cover,
                cacheWidth: 126,
                errorBuilder: (_, _, _) => placeholder,
              ),
            ),
    );
  }
}

class _NoReadingCard extends StatelessWidget {
  const _NoReadingCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.auto_stories_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '还没有阅读记录，从书架打开一本书吧。',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _positionLabel(BookEntry book, ReaderProgress? progress) {
  if (progress == null) {
    return '尚未开始';
  }
  final position =
      '第 ${progress.spineIndex + 1} 章 · 第 ${progress.pageIndex + 1} 页';
  final total = book.spineCount;
  return total == null ? position : '$position / 共 $total 章';
}

String _relativeTime(DateTime? time) {
  if (time == null) {
    return '';
  }
  final delta = DateTime.now().difference(time);
  if (delta.isNegative || delta.inMinutes < 1) return '刚刚';
  if (delta.inHours < 1) return '${delta.inMinutes} 分钟前';
  if (delta.inDays < 1) return '${delta.inHours} 小时前';
  return '${delta.inDays} 天前';
}

Map<DateTime, Duration> _readingByDay(List<ReadingSession> sessions) {
  final result = <DateTime, Duration>{};
  for (final session in sessions) {
    if (session.duration <= Duration.zero ||
        !session.endedAt.isAfter(session.startedAt)) {
      continue;
    }
    var cursor = session.startedAt;
    while (cursor.isBefore(session.endedAt)) {
      final dayStart = DateTime(cursor.year, cursor.month, cursor.day);
      final nextDay = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final segmentEnd = session.endedAt.isBefore(nextDay)
          ? session.endedAt
          : nextDay;
      final overlap = segmentEnd.difference(cursor);
      if (overlap > Duration.zero) {
        result[dayStart] = (result[dayStart] ?? Duration.zero) + overlap;
      }
      cursor = segmentEnd;
    }
  }
  return result;
}

String _formatReadingDuration(Duration duration) {
  if (duration <= Duration.zero) {
    return '0 分钟';
  }
  final minutes = (duration.inSeconds / 60).ceil();
  if (minutes < 1) {
    return '<1 分钟';
  }
  if (minutes < 60) {
    return '$minutes 分钟';
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
}

String _formatActivityDuration(Duration duration) {
  if (duration <= Duration.zero) {
    return '0';
  }
  if (duration < const Duration(minutes: 1)) {
    return '<1分';
  }
  if (duration < const Duration(hours: 1)) {
    return '${(duration.inSeconds / 60).ceil()}分';
  }
  if (duration.inMinutes % 60 == 0) {
    return '${duration.inHours}时';
  }
  final hours = duration.inMinutes / 60;
  return hours < 10 ? '${hours.toStringAsFixed(1)}时' : '${hours.round()}时';
}

String _formatCharacters(int count) {
  if (count <= 0) {
    return '暂无';
  }
  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(1)}亿';
  }
  if (count >= 1000000) {
    return '${(count / 10000).round()}万';
  }
  if (count >= 10000) {
    return '${(count / 10000).toStringAsFixed(1)}万';
  }
  return '$count';
}

String _formatMetricCharacters(int count) =>
    count <= 0 ? '0' : _formatCharacters(count);
