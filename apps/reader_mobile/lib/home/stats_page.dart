import 'package:flutter/material.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/library_store.dart';
import 'book_cover_image.dart';
import 'book_duration_chart.dart';
import 'reading_insights.dart';
import 'reading_habits_panel.dart';
import 'book_reading_ranking.dart';
import 'weekday_average_chart.dart';
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

/// 统计页：书架概览、历史阅读趋势、习惯与按书排行。
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
    this.active = true,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 进度存储。
  final ReaderProgressStore progressStore;

  /// 可注入的阅读会话存储；为空时使用书架数据库实现。
  final ReadingSessionStore? sessionStore;

  /// 外部切换页面时递增，用于重新读取阅读进度和会话数据。
  final int refreshToken;

  /// 当前 Tab 是否可见；隐藏时只标记待刷新，避免后台页面重复查询。
  final bool active;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late final BookOpener _bookOpener;
  _LibraryStats? _stats;
  int _reloadToken = 0;
  bool _dirty = true;
  String? _error;

  ReadingSessionStore? get _sessionStore =>
      widget.sessionStore ?? widget.library.readingSessionStore();

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_onLibraryChanged);
    _bookOpener = BookOpener(
      library: widget.library,
      progressStore: widget.progressStore,
    );
    if (widget.active) _reload();
  }

  @override
  void dispose() {
    widget.library.removeListener(_onLibraryChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(StatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameActive = !oldWidget.active && widget.active;
    if ((becameActive && _dirty) ||
        oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.sessionStore != widget.sessionStore) {
      _reload();
    }
  }

  void _onLibraryChanged() {
    if (!widget.active) {
      _dirty = true;
      return;
    }
    _reload();
  }

  Future<void> _reload() async {
    _dirty = false;
    final token = ++_reloadToken;
    try {
      final books = await widget.library.list();
      final progress = await widget.progressStore.snapshot();
      final weightsByBook = await widget.library.progressWeightsForBooks(
        books.map((book) => book.id),
      );
      final recordedSessions =
          await (_sessionStore?.list() ??
              Future<List<ReadingSession>>.value(const []));
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final insights = ReadingInsights(recordedSessions, now: now);
      final sessions = insights.sessions;
      final readingByDay = insights.byDay;
      final rows = <_BookReadingStat>[];
      var started = 0;
      var finished = 0;
      var totalCharacters = 0;
      var percentSum = 0;
      var percentCount = 0;
      for (final book in books) {
        final bookWeights = weightsByBook[book.id];
        final current = progress[book.id];
        int? percent;
        if (current != null) {
          percent = current.readingPercent == null
              ? (bookWeights != null && bookWeights.total > 0
                    ? bookWeights.percentInt(current.spineIndex)
                    : null)
              : (current.readingPercent! * 100).round().clamp(0, 100);
        }
        if (percent != null) {
          percentSum += percent;
          percentCount += 1;
        }
        if (current != null) {
          started += 1;
          if (current.finished) {
            finished += 1;
          }
        }
        totalCharacters += bookWeights?.totalCharacters ?? 0;
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
        final date = DateTime(
          lastReadAt.year,
          lastReadAt.month,
          lastReadAt.day,
        );
        if (date.isBefore(activityDates.first)) {
          continue;
        }
        recent += 1;
        activityCounts[date] = (activityCounts[date] ?? 0) + 1;
      }
      if (sessions.isNotEmpty) {
        activityCounts.clear();
        final booksByDay = <DateTime, Set<String>>{};
        final recentBooks = <String>{};
        for (final portion in insights.portions) {
          if (portion.date.isBefore(activityDates.first) ||
              portion.date.isAfter(today)) {
            continue;
          }
          booksByDay.putIfAbsent(portion.date, () => {}).add(portion.bookId);
          recentBooks.add(portion.bookId);
        }
        for (final entry in booksByDay.entries) {
          activityCounts[entry.key] = entry.value.length;
        }
        recent = recentBooks.length;
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
        insights: insights,
        sessions: sessions,
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
        totalReading: insights.totalReading,
        readingDays: readingByDay.length,
        pageTurns: insights.pageTurns,
        charactersRead: insights.charactersRead,
        hasReadingSessions: sessions.isNotEmpty,
      );
      if (mounted && token == _reloadToken) {
        setState(() {
          _stats = stats;
          _error = null;
        });
      }
    } catch (_) {
      if (!mounted || token != _reloadToken) return;
      if (_stats == null) {
        setState(() => _error = '统计加载失败');
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('统计刷新失败，请稍后重试')));
      }
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
        centerTitle: false,
        scrolledUnderElevation: 0,
        title: const Text('统计'),
        actions: [
          IconButton(
            key: const ValueKey<String>('stats-refresh'),
            tooltip: '刷新统计',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: const _AppBarHairline(),
      ),
      body: stats == null
          ? _error == null
                ? const _StatsSkeleton()
                : _StatsError(onRetry: _reload)
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
                children: [
                  _TodayHero(stats: stats),
                  _Section(
                    title: '概览',
                    child: _OverviewGrid(stats: stats),
                  ),
                  _TrendSection(stats: stats, onOpenBook: _openBook),
                  _Section(
                    title: '图书时长',
                    child: BookDurationChart(
                      insights: stats.insights,
                      bookTitles: {
                        for (final row in stats.rows) row.book.id: row.book.title,
                      },
                    ),
                  ),
                  _Section(
                    title: '每日平均',
                    detail: '按星期',
                    caption: '按星期汇总全部阅读记录，均值只计算有阅读的日期。',
                    child: WeekdayAverageChart(insights: stats.insights),
                  ),
                  _HeatmapSection(stats: stats, onOpenBook: _openBook),
                  _Section(
                    title: '阅读习惯',
                    child: ReadingHabitsPanel(insights: stats.insights),
                  ),
                  _Section(
                    title: '阅读排行',
                    detail: '按累计时长',
                    child: BookReadingRanking(
                      books: [for (final row in stats.rows) row.book],
                      totals: stats.insights.byBook,
                      bookTitles: stats.insights.bookTitles,
                      onOpen: _openBook,
                    ),
                  ),
                  _Section(
                    title: '阅读分布',
                    detail: '已开始 ${stats.started} 本 · 已读完 ${stats.finished} 本',
                    child: _DistributionCard(stats: stats),
                  ),
                  _RecentSection(stats: stats, onOpenBook: _openBook),
                ],
              ),
            ),
    );
  }
}

class _LibraryStats {
  const _LibraryStats({
    required this.rows,
    required this.insights,
    required this.sessions,
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
  final ReadingInsights insights;
  final List<ReadingSession> sessions;
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

/// 数字统一使用等宽字形，避免刷新时左右跳动。
const _tabularFigures = <FontFeature>[FontFeature.tabularFigures()];

class _AppBarHairline extends StatelessWidget implements PreferredSizeWidget {
  const _AppBarHairline();

  @override
  Size get preferredSize => const Size.fromHeight(1);

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: Theme.of(context).colorScheme.outlineVariant);
}

/// 细线分区：标题、右侧摘要、可选说明与内容。
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    this.detail,
    this.caption,
    this.detailKey,
    required this.child,
  });

  final String title;
  final String? detail;
  final String? caption;
  final Key? detailKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        Container(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              if (detail != null)
                Text(
                  detail!,
                  key: detailKey,
                  style: TextStyle(fontSize: 12, color: muted, height: 1.3),
                ),
            ],
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 5),
          Text(
            caption!,
            style: TextStyle(fontSize: 12, color: muted, height: 1.4),
          ),
        ],
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}

/// 英雄区：今天已读 + 累计上下文 + 七日节奏条。
class _TodayHero extends StatelessWidget {
  const _TodayHero({required this.stats});

  final _LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final hasSessions = stats.hasReadingSessions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '今天',
                    style: TextStyle(
                      fontSize: 12,
                      color: muted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      hasSessions
                          ? formatReadingDuration(stats.todayReading)
                          : '--',
                      key: const ValueKey<String>('stats-today-reading'),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w600,
                        height: 1.05,
                        letterSpacing: -0.8,
                        fontFeatures: _tabularFigures,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      hasSessions
                          ? '累计 ${formatReadingDuration(stats.totalReading)}'
                          : '累计 --',
                      key: const ValueKey<String>('stats-total-reading'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                        fontFeatures: _tabularFigures,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      hasSessions ? '共 ${stats.readingDays} 天' : '只记录前台阅读',
                      key: const ValueKey<String>('stats-reading-days'),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _WeekRhythm(stats: stats),
      ],
    );
  }
}

/// 签名细节：近七日阅读节奏，今天为实心墨条。
class _WeekRhythm extends StatelessWidget {
  const _WeekRhythm({required this.stats});

  final _LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets = _buildReadingBuckets(_ChartPeriod.day, DateTime.now());
    for (final bucket in buckets) {
      _fillReadingBucket(bucket, stats.insights.portions);
    }
    final values = <double>[
      for (final bucket in buckets) bucket.duration.inSeconds.toDouble(),
    ];
    final maxValue = values.fold<double>(0, (max, value) {
      return value > max ? value : max;
    });
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    return SizedBox(
      height: 32 + MediaQuery.textScalerOf(context).scale(10) * 1.2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < buckets.length; index++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 6,
                    height: maxValue == 0
                        ? 2
                        : values[index] > 0
                        ? 5 + (values[index] / maxValue) * 17
                        : 2,
                    decoration: BoxDecoration(
                      color: index == 6
                          ? theme.colorScheme.primary
                          : values[index] > 0
                          ? theme.colorScheme.primary.withValues(alpha: 0.26)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    index == 6
                        ? '今'
                        : weekdays[buckets[index].start.weekday - 1],
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: index == 6
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: index == 6
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
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

/// 概览指标：2 列 × 4 行细线网格。
class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.stats});

  final _LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    final cells = <Widget>[
      _MetricCell(
        label: '总书数',
        value: '${stats.rows.length}',
        valueKey: const ValueKey<String>('stats-total-books'),
      ),
      _MetricCell(label: '已开始', value: '${stats.started} 本'),
      _MetricCell(label: '已读完', value: '${stats.finished} 本'),
      _MetricCell(
        label: '平均进度',
        value: stats.averageProgress == null
            ? '--'
            : '${stats.averageProgress}%',
        valueKey: const ValueKey<String>('stats-average-progress'),
      ),
      _MetricCell(
        label: '书库字数',
        value: _formatCharacters(stats.totalCharacters),
        valueKey: const ValueKey<String>('stats-total-characters'),
      ),
      _MetricCell(
        label: '近 7 天阅读',
        value: '${stats.weekReadingDays} 天',
        valueKey: const ValueKey<String>('stats-recent-7-days'),
      ),
      _MetricCell(
        label: '翻页次数',
        value: '${stats.pageTurns}',
        valueKey: const ValueKey<String>('stats-page-turns'),
      ),
      _MetricCell(
        label: '阅读字数',
        value: _formatMetricCharacters(stats.charactersRead),
        valueKey: const ValueKey<String>('stats-characters-read'),
      ),
    ];
    return Column(
      children: [
        for (var row = 0; row < cells.length ~/ 2; row++) ...[
          if (row > 0) Container(height: 1, color: line),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: cells[row * 2],
                    ),
                  ),
                  Container(width: 1, color: line),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: cells[row * 2 + 1],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.value, this.valueKey});

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              key: valueKey,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                height: 1.1,
                fontFeatures: _tabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 加载骨架：几何结构与最终页面一致，避免布局跳变。
class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget block(double height, {double? width}) => Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      children: [
        block(12, width: 40),
        const SizedBox(height: 10),
        block(34, width: 220),
        const SizedBox(height: 20),
        block(40),
        const SizedBox(height: 42),
        block(12, width: 64),
        const SizedBox(height: 16),
        block(256),
        const SizedBox(height: 42),
        block(12, width: 64),
        const SizedBox(height: 16),
        block(190),
      ],
    );
  }
}

/// 首次加载失败：保留可操作的重试，不把用户困在骨架里。
class _StatsError extends StatelessWidget {
  const _StatsError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 32, color: muted),
            const SizedBox(height: 12),
            const Text(
              '统计加载失败',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text('请稍后重试', style: TextStyle(fontSize: 13, color: muted)),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const ValueKey<String>('stats-retry'),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ChartPeriod {
  day('日', '近 7 天'),
  week('周', '近 8 周'),
  month('月', '近 12 月'),
  year('年', '近 5 年');

  const _ChartPeriod(this.label, this.rangeLabel);

  final String label;
  final String rangeLabel;
}

class _ReadingBucket {
  _ReadingBucket({
    required this.start,
    required this.end,
    required this.label,
    required this.rangeLabel,
  });

  final DateTime start;
  final DateTime end;
  final String label;
  final String rangeLabel;
  Duration duration = Duration.zero;
  final Set<ReadingSession> participatingSessions = {};
  final Set<DateTime> readingDates = {};
  int get sessionCount => participatingSessions.length;
  int pageTurns = 0;
  int charactersRead = 0;
  final Map<String, Duration> bookDurations = <String, Duration>{};
}

class _TrendSection extends StatefulWidget {
  const _TrendSection({required this.stats, required this.onOpenBook});

  final _LibraryStats stats;
  final ValueChanged<BookEntry> onOpenBook;

  @override
  State<_TrendSection> createState() => _TrendSectionState();
}

class _TrendSectionState extends State<_TrendSection> {
  _ChartPeriod _period = _ChartPeriod.day;
  int _selectedIndex = 6;
  int _windowOffset = 0;
  (ReadingInsights, _ChartPeriod, DateTime, int)? _bucketsKey;
  List<_ReadingBucket> _buckets = [];

  List<_ReadingBucket> _readingBuckets(DateTime today) {
    final key = (widget.stats.insights, _period, today, _windowOffset);
    if (_bucketsKey != key) {
      _buckets = _buildReadingBuckets(
        _period,
        _windowAnchor(_period, today, _windowOffset),
      );
      for (final bucket in _buckets) {
        _fillReadingBucket(bucket, widget.stats.insights.portions);
      }
      _bucketsKey = key;
    }
    return _buckets;
  }

  void _changeWindow(int offset) => setState(() {
    _windowOffset = offset;
    _selectedIndex = _bucketCount(_period) - 1;
  });

  bool _hasEarlierRecords(DateTime start) => widget.stats.hasReadingSessions
      ? widget.stats.insights.byDay.keys.any((day) => day.isBefore(start))
      : widget.stats.rows.any(
          (row) => row.book.lastReadAt?.isBefore(start) ?? false,
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final useDuration = widget.stats.hasReadingSessions;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final buckets = _readingBuckets(today);
    final selectedIndex = _selectedIndex.clamp(0, buckets.length - 1);
    final selected = buckets[selectedIndex];
    final values = <double>[
      for (final bucket in buckets)
        (_period == _ChartPeriod.day && !useDuration
                ? _booksReadOnDay(widget.stats, bucket.start)
                : bucket.duration.inSeconds)
            .toDouble(),
    ];
    final maxValue = values.fold<double>(0, (max, value) {
      return value > max ? value : max;
    });
    final total = buckets.fold<Duration>(
      Duration.zero,
      (sum, bucket) => sum + bucket.duration,
    );
    final readingDays = {for (final bucket in buckets) ...bucket.readingDates}
        .length;
    final summary = _period == _ChartPeriod.day && !useDuration
        ? _bookActivitySummary(buckets)
        : '${formatReadingDuration(total)} · $readingDays 天';
    final title = _windowOffset > 0
        ? '历史阅读${useDuration ? '时长' : ''}'
        : _period == _ChartPeriod.day && !useDuration
        ? '近 7 天阅读'
        : '${_period.rangeLabel}阅读时长';

    return _Section(
      title: title,
      detail: summary,
      detailKey: const ValueKey<String>('stats-activity-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            key: const ValueKey<String>('stats-chart-period'),
            children: [
              for (final period in _ChartPeriod.values)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: period == _period,
                    child: InkWell(
                      key: ValueKey<String>(
                        'stats-chart-period-${period.name}',
                      ),
                      onTap: () => setState(() {
                        _period = period;
                        _windowOffset = 0;
                        _selectedIndex = _bucketCount(period) - 1;
                      }),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: period == _period
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              width: period == _period ? 2 : 1,
                            ),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          period.label,
                          key: ValueKey<String>(
                            'stats-chart-period-label-${period.name}',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: period == _period
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: period == _period
                                ? theme.colorScheme.onSurface
                                : muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          _windowNavigation(buckets, today),
          const SizedBox(height: 12),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(10) * 1.2 + 4,
            child: Row(
              children: [
                for (var index = 0; index < buckets.length; index++)
                  Expanded(
                    child: Text(
                      _valueLabel(buckets[index], index, useDuration),
                      key: ValueKey<String>('stats-activity-count-$index'),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.2,
                        fontWeight: values[index] > 0
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: values[index] > 0
                            ? theme.colorScheme.onSurface
                            : muted,
                        fontFeatures: _tabularFigures,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 112,
            child: Stack(
              children: [
                Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey<String>('stats-chart-anim-${_period.name}'),
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    builder: (context, progress, _) => CustomPaint(
                      painter: _TrendPainter(
                        values: maxValue == 0
                            ? const <double>[]
                            : <double>[
                                for (final value in values) value / maxValue,
                              ],
                        selectedIndex: selectedIndex,
                        progress: progress,
                        lineColor: theme.colorScheme.primary,
                        gridColor: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
                if (maxValue == 0)
                  Center(
                    child: Text(
                      '该时段没有阅读记录',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                Positioned.fill(
                  child: Row(
                    children: [
                      for (var index = 0; index < buckets.length; index++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: index == selectedIndex,
                            label:
                                '${_bucketRangeLabel(buckets[index])}，'
                                '${_valueLabel(buckets[index], index, useDuration)}',
                            child: InkWell(
                              key: ValueKey<String>(
                                'stats-chart-bar-${_period.name}-$index',
                              ),
                              onTap: () =>
                                  setState(() => _selectedIndex = index),
                              splashColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var index = 0; index < buckets.length; index++)
                Expanded(
                  child: Text(
                    _barLabel(_period, buckets[index], index),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: index == selectedIndex
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: index == selectedIndex
                          ? theme.colorScheme.onSurface
                          : muted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                key: const ValueKey('stats-chart-previous'),
                tooltip: '上一${_period.label}',
                onPressed: selectedIndex == 0
                    ? null
                    : () => setState(() => _selectedIndex = selectedIndex - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  _bucketRangeLabel(selected),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
              IconButton(
                key: const ValueKey('stats-chart-next'),
                tooltip: '下一${_period.label}',
                onPressed: selectedIndex == buckets.length - 1
                    ? null
                    : () => setState(() => _selectedIndex = selectedIndex + 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Text(
            _period == _ChartPeriod.day && !useDuration
                ? '按每本书的最后阅读日期统计'
                : '按实际前台阅读时长统计',
            key: const ValueKey<String>('stats-activity-caption'),
            style: TextStyle(fontSize: 12, color: muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          _ReadingBucketDetail(
            bucket: selected,
            books: widget.stats.rows,
            bookTitles: widget.stats.insights.bookTitles,
            onOpenBook: widget.onOpenBook,
          ),
        ],
      ),
    );
  }

  String _bookActivitySummary(List<_ReadingBucket> buckets) {
    final counts = [
      for (final bucket in buckets) _booksReadOnDay(widget.stats, bucket.start),
    ];
    final days = counts.where((count) => count > 0).length;
    final books = counts.fold(0, (sum, count) => sum + count);
    return '$days 天活跃 · $books 本书';
  }

  Widget _windowNavigation(List<_ReadingBucket> buckets, DateTime today) =>
      Column(
        children: [
          _windowArrows(buckets, today),
          if (_windowOffset > 0)
            TextButton(
              key: const ValueKey('stats-chart-window-current'),
              onPressed: () => _changeWindow(0),
              child: const Text('回到当前'),
            ),
        ],
      );

  Widget _windowArrows(List<_ReadingBucket> buckets, DateTime today) => Row(
    children: [
      IconButton(
        key: const ValueKey('stats-chart-window-previous'),
        tooltip: '查看更早记录',
        onPressed: _hasEarlierRecords(buckets.first.start)
            ? () => _changeWindow(_windowOffset + 1)
            : null,
        icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
      ),
      Expanded(
        child: Text(
          _windowRangeLabel(buckets, today),
          key: const ValueKey('stats-chart-window-range'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontFeatures: _tabularFigures,
          ),
        ),
      ),
      IconButton(
        key: const ValueKey('stats-chart-window-next'),
        tooltip: '查看较新记录',
        onPressed: _windowOffset > 0
            ? () => _changeWindow(_windowOffset - 1)
            : null,
        icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
      ),
    ],
  );

  String _valueLabel(_ReadingBucket bucket, int index, bool useDuration) {
    final useBooks = _period == _ChartPeriod.day && !useDuration;
    final value = useBooks
        ? _booksReadOnDay(widget.stats, bucket.start)
        : bucket.duration.inSeconds;
    if (useBooks) {
      return '$value';
    }
    final showLabel =
        (_period == _ChartPeriod.day || index == _selectedIndex) && value > 0;
    return showLabel ? _formatActivityDuration(bucket.duration) : '';
  }

  String _barLabel(_ChartPeriod period, _ReadingBucket bucket, int index) {
    switch (period) {
      case _ChartPeriod.day:
        if (_windowOffset == 0 && index == 6) {
          return '今天';
        }
        const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
        return '周${weekdays[bucket.start.weekday - 1]}';
      case _ChartPeriod.week:
      case _ChartPeriod.month:
      case _ChartPeriod.year:
        return bucket.label;
    }
  }
}

int _booksReadOnDay(_LibraryStats stats, DateTime date) {
  return stats.rows.where((row) {
    final lastRead = row.book.lastReadAt;
    return lastRead != null &&
        lastRead.year == date.year &&
        lastRead.month == date.month &&
        lastRead.day == date.day;
  }).length;
}

/// 面积图：单条墨色曲线 + 15% -> 0 的填充，选中点带光晕。
class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.values,
    required this.selectedIndex,
    required this.progress,
    required this.lineColor,
    required this.gridColor,
  });

  final List<double> values;
  final int selectedIndex;
  final double progress;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      grid,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.46),
      Offset(size.width, size.height * 0.46),
      grid,
    );
    if (values.isEmpty) {
      return;
    }
    final count = values.length;
    final step = size.width / count;
    final points = <Offset>[
      for (var index = 0; index < count; index++)
        Offset(
          step * (index + 0.5),
          (size.height - 8) -
              values[index] * (size.height - 22) * progress.clamp(0, 1),
        ),
    ];
    final area = Path()
      ..moveTo(points.first.dx, size.height - 1)
      ..lineTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      area.lineTo(point.dx, point.dy);
    }
    area
      ..lineTo(points.last.dx, size.height - 1)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            lineColor.withValues(alpha: 0.16),
            lineColor.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var index = 0; index < count; index++) {
      final selected = index == selectedIndex;
      if (selected) {
        canvas.drawCircle(
          points[index],
          7,
          Paint()..color = lineColor.withValues(alpha: 0.12),
        );
      }
      canvas.drawCircle(
        points[index],
        selected ? 3.4 : 2,
        Paint()
          ..color = selected ? lineColor : lineColor.withValues(alpha: 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.progress != progress ||
      oldDelegate.lineColor != lineColor;
}

class _ReadingBucketDetail extends StatelessWidget {
  const _ReadingBucketDetail({
    required this.bucket,
    required this.books,
    required this.bookTitles,
    required this.onOpenBook,
  });

  final _ReadingBucket bucket;
  final List<_BookReadingStat> books;
  final Map<String, String> bookTitles;
  final ValueChanged<BookEntry> onOpenBook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final entries = bucket.bookDurations.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final byId = <String, BookEntry>{
      for (final row in books) row.book.id: row.book,
    };
    return Container(
      key: const ValueKey<String>('stats-chart-detail'),
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  _bucketRangeLabel(bucket),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                formatReadingDuration(bucket.duration),
                key: const ValueKey<String>('stats-chart-bucket-duration'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                  fontFeatures: _tabularFigures,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${bucket.sessionCount} 次阅读 · ${bucket.pageTurns} 次翻页 · ${bucket.charactersRead} 字',
              key: const ValueKey('stats-chart-bucket-counts'),
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '该时段没有阅读记录',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            )
          else ...[
            const SizedBox(height: 4),
            for (final entry in entries)
              InkWell(
                key: ValueKey<String>('stats-chart-book-${entry.key}'),
                onTap: byId[entry.key] == null
                    ? null
                    : () => onOpenBook(byId[entry.key]!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          byId[entry.key]?.title ??
                              bookTitles[entry.key] ??
                              '已移出书架的书籍',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatReadingDuration(entry.value),
                        key: ValueKey<String>(
                          'stats-chart-book-duration-${entry.key}',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                          fontFeatures: _tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

int _bucketCount(_ChartPeriod period) => switch (period) {
  _ChartPeriod.day => 7,
  _ChartPeriod.week => 8,
  _ChartPeriod.month => 12,
  _ChartPeriod.year => 5,
};

DateTime _windowAnchor(_ChartPeriod period, DateTime today, int offset) {
  final shift = _bucketCount(period) * offset;
  return switch (period) {
    _ChartPeriod.day => DateTime(today.year, today.month, today.day - shift),
    _ChartPeriod.week => DateTime(
      today.year,
      today.month,
      today.day - shift * 7,
    ),
    _ChartPeriod.month => DateTime(today.year, today.month - shift),
    _ChartPeriod.year => DateTime(today.year - shift),
  };
}

String _windowRangeLabel(List<_ReadingBucket> buckets, DateTime today) {
  final start = buckets.first.start;
  final end = buckets.last.end;
  final lastDay = end.isAfter(today)
      ? today
      : DateTime(end.year, end.month, end.day - 1);
  String label(DateTime date) =>
      start.year == today.year && lastDay.year == today.year
      ? '${date.month}月${date.day}日'
      : '${date.year}/${date.month}/${date.day}';
  return '${label(start)}–${label(lastDay)}';
}

List<_ReadingBucket> _buildReadingBuckets(_ChartPeriod period, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  switch (period) {
    case _ChartPeriod.day:
      return <_ReadingBucket>[
        for (var offset = -6; offset <= 0; offset++)
          _ReadingBucket(
            start: DateTime(today.year, today.month, today.day + offset),
            end: DateTime(today.year, today.month, today.day + offset + 1),
            label: '',
            rangeLabel:
                '${DateTime(today.year, today.month, today.day + offset).month}月'
                '${DateTime(today.year, today.month, today.day + offset).day}日',
          ),
      ];
    case _ChartPeriod.week:
      final monday = DateTime(
        today.year,
        today.month,
        today.day - (today.weekday - 1),
      );
      return <_ReadingBucket>[
        for (var offset = 7; offset >= 0; offset--)
          _weekBucket(
            DateTime(monday.year, monday.month, monday.day - offset * 7),
          ),
      ];
    case _ChartPeriod.month:
      return <_ReadingBucket>[
        for (var offset = 11; offset >= 0; offset--)
          _ReadingBucket(
            start: DateTime(now.year, now.month - offset, 1),
            end: DateTime(now.year, now.month - offset + 1, 1),
            label: '${DateTime(now.year, now.month - offset, 1).month}月',
            rangeLabel:
                '${DateTime(now.year, now.month - offset, 1).year}年'
                '${DateTime(now.year, now.month - offset, 1).month}月',
          ),
      ];
    case _ChartPeriod.year:
      return <_ReadingBucket>[
        for (var offset = 4; offset >= 0; offset--)
          _ReadingBucket(
            start: DateTime(now.year - offset, 1, 1),
            end: DateTime(now.year - offset + 1, 1, 1),
            label: '${now.year - offset}',
            rangeLabel: '${now.year - offset}年',
          ),
      ];
  }
}

_ReadingBucket _weekBucket(DateTime start) {
  final end = DateTime(start.year, start.month, start.day + 7);
  final lastDay = DateTime(end.year, end.month, end.day - 1);
  return _ReadingBucket(
    start: start,
    end: end,
    label: '${start.month}/${start.day}',
    rangeLabel: '${start.month}月${start.day}日–${lastDay.month}月${lastDay.day}日',
  );
}

void _fillReadingBucket(
  _ReadingBucket bucket,
  List<ReadingDayPortion> portions,
) {
  for (final portion in portions) {
    if (portion.date.isBefore(bucket.start) ||
        !portion.date.isBefore(bucket.end)) {
      continue;
    }
    bucket.duration += portion.duration;
    if (portion.duration > Duration.zero) bucket.readingDates.add(portion.date);
    bucket.bookDurations[portion.bookId] =
        (bucket.bookDurations[portion.bookId] ?? Duration.zero) +
        portion.duration;
    bucket.participatingSessions.add(portion.session);
    bucket.pageTurns += portion.pageTurns;
    bucket.charactersRead += portion.charactersRead;
  }
}

String _bucketRangeLabel(_ReadingBucket bucket) => bucket.rangeLabel;

class _HeatmapDay {
  _HeatmapDay({required this.date});

  final DateTime date;
  Duration duration = Duration.zero;
  final Set<ReadingSession> participatingSessions = {};
  int get sessionCount => participatingSessions.length;
  bool estimatedCounts = false;
  int pageTurns = 0;
  int charactersRead = 0;
  final Map<String, Duration> bookDurations = <String, Duration>{};
  final List<_DayReadingSegment> segments = <_DayReadingSegment>[];
}

class _DayReadingSegment {
  const _DayReadingSegment({
    required this.bookId,
    required this.startedAt,
    required this.endedAt,
    required this.duration,
  });

  final String bookId;
  final DateTime startedAt;
  final DateTime endedAt;
  final Duration duration;
}

class _HeatmapSection extends StatelessWidget {
  const _HeatmapSection({required this.stats, required this.onOpenBook});

  final _LibraryStats stats;
  final ValueChanged<BookEntry> onOpenBook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final days = _buildHeatmapDays(stats.insights.portions, DateTime.now());
    final weeks = <List<_HeatmapDay>>[
      for (var week = 0; week < 12; week++)
        <_HeatmapDay>[
          for (var weekday = 0; weekday < 7; weekday++)
            days[week * 7 + weekday],
        ],
    ];
    const weekdays = <String>['一', '', '三', '', '五', '', '日'];
    return _Section(
      title: '阅读热力图',
      detail: '近 12 周',
      caption: '左右滑动查看日期，点击查看当日阅读详情',
      child: Container(
        key: const ValueKey<String>('stats-heatmap'),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 16,
                  child: Column(
                    children: [
                      for (final weekday in weekdays)
                        SizedBox(
                          height: 48,
                          child: Center(
                            child: Text(
                              weekday,
                              style: TextStyle(fontSize: 10, color: muted),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('stats-heatmap-scroll'),
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      children: [
                        for (final week in weeks)
                          SizedBox(
                            width: 48,
                            child: Column(
                              children: [
                                for (final day in week)
                                  _HeatmapCell(
                                    day: day,
                                    onTap: () => _showDayDetail(
                                      context,
                                      day,
                                      onOpenBook,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('少', style: TextStyle(fontSize: 10, color: muted)),
                const SizedBox(width: 6),
                for (final alpha in const <double>[0.18, 0.38, 0.62, 0.9])
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: alpha,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                const SizedBox(width: 2),
                Text('多', style: TextStyle(fontSize: 10, color: muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDayDetail(
    BuildContext context,
    _HeatmapDay day,
    ValueChanged<BookEntry> onOpenBook,
  ) async {
    final titles = <String, BookEntry>{
      for (final row in stats.rows) row.book.id: row.book,
    };
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (_) => _DayReadingSheet(
        day: day,
        books: titles,
        bookTitles: stats.insights.bookTitles,
        onOpenBook: (book) {
          Navigator.of(context).pop();
          onOpenBook(book);
        },
      ),
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({required this.day, required this.onTap});

  final _HeatmapDay day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alpha = day.duration <= Duration.zero
        ? 0.0
        : day.duration < const Duration(minutes: 15)
        ? 0.18
        : day.duration < const Duration(minutes: 30)
        ? 0.38
        : day.duration < const Duration(hours: 1)
        ? 0.62
        : 0.9;
    final color = alpha == 0.0
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.primary.withValues(alpha: alpha);
    final now = DateTime.now();
    final isToday =
        day.date.year == now.year &&
        day.date.month == now.month &&
        day.date.day == now.day;
    return SizedBox(
      key: ValueKey<String>('stats-heatmap-day-${_dateKey(day.date)}'),
      height: 48,
      child: Semantics(
        button: true,
        label:
            '${day.date.year}年${day.date.month}月${day.date.day}日，'
            '${isToday ? '今天，' : ''}'
            '${formatReadingDuration(day.duration)}，${day.sessionCount}次阅读',
        child: Tooltip(
          excludeFromSemantics: true,
          message:
              '${day.date.month}月${day.date.day}日 · '
              '${formatReadingDuration(day.duration)} · '
              '${day.sessionCount} 次',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(3),
            child: Center(
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: isToday
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surface.withValues(alpha: 0.7),
                    width: isToday ? 1.4 : 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayReadingSheet extends StatelessWidget {
  const _DayReadingSheet({
    required this.day,
    required this.books,
    required this.bookTitles,
    required this.onOpenBook,
  });

  final _HeatmapDay day;
  final Map<String, BookEntry> books;
  final Map<String, String> bookTitles;
  final ValueChanged<BookEntry> onOpenBook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final line = theme.colorScheme.outlineVariant;
    final entries = day.bookDurations.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final segments = _mergeDaySegments(day.segments);
    Widget metric(String label, String value, Key valueKey) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: muted)),
          const SizedBox(height: 4),
          Text(
            value,
            key: valueKey,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFeatures: _tabularFigures,
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const ValueKey<String>('stats-day-detail'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${day.date.year}年${day.date.month}月${day.date.day}日',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: metric(
                        '阅读时长',
                        formatReadingDuration(day.duration),
                        const ValueKey<String>('stats-day-detail-duration'),
                      ),
                    ),
                    Container(width: 1, height: 40, color: line),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: metric(
                          '阅读次数',
                          '${day.sessionCount}',
                          const ValueKey<String>('stats-day-detail-sessions'),
                        ),
                      ),
                    ),
                  ],
                ),
                Container(height: 1, color: line),
                Row(
                  children: [
                    Expanded(
                      child: metric(
                        '翻页次数',
                        '${day.pageTurns}',
                        const ValueKey<String>('stats-day-detail-page-turns'),
                      ),
                    ),
                    Container(width: 1, height: 40, color: line),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: metric(
                          '阅读字数',
                          _formatMetricCharacters(day.charactersRead),
                          const ValueKey<String>('stats-day-detail-characters'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (day.estimatedCounts)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '跨日时段的翻页与字数按时长分配。',
                  key: const ValueKey('stats-day-estimated-counts'),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
            const SizedBox(height: 22),
            Text(
              '阅读书目',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '这一天没有阅读记录',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              )
            else
              for (final entry in entries)
                InkWell(
                  key: ValueKey<String>('stats-day-book-${entry.key}'),
                  onTap: books[entry.key] == null
                      ? null
                      : () => onOpenBook(books[entry.key]!),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            books[entry.key]?.title ??
                                bookTitles[entry.key] ??
                                '已移出书架的书籍',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          formatReadingDuration(entry.value),
                          style: TextStyle(
                            fontSize: 12,
                            color: muted,
                            fontFeatures: _tabularFigures,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (segments.isNotEmpty) ...<Widget>[
              const SizedBox(height: 22),
              Text(
                '阅读时段',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              for (final segment in segments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 84,
                        child: Text(
                          _formatTimeRange(segment.startedAt, segment.endedAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: muted,
                            fontFeatures: _tabularFigures,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          books[segment.bookId]?.title ??
                              bookTitles[segment.bookId] ??
                              '已移出书架的书籍',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        formatReadingDuration(segment.duration),
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                          fontFeatures: _tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 合并同一本书相邻的碎片时段（间隔不超过 1 分钟）。
List<_DayReadingSegment> _mergeDaySegments(List<_DayReadingSegment> segments) {
  final sorted = <_DayReadingSegment>[...segments]
    ..sort((left, right) => left.startedAt.compareTo(right.startedAt));
  final merged = <_DayReadingSegment>[];
  for (final segment in sorted) {
    if (merged.isNotEmpty) {
      final last = merged.last;
      final gap = segment.startedAt.difference(last.endedAt);
      if (last.bookId == segment.bookId &&
          !gap.isNegative &&
          gap <= const Duration(minutes: 1)) {
        merged[merged.length - 1] = _DayReadingSegment(
          bookId: last.bookId,
          startedAt: last.startedAt,
          endedAt: segment.endedAt,
          duration: last.duration + segment.duration,
        );
        continue;
      }
    }
    merged.add(segment);
  }
  return merged;
}

List<_HeatmapDay> _buildHeatmapDays(
  List<ReadingDayPortion> portions,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final monday = DateTime(
    today.year,
    today.month,
    today.day - (today.weekday - 1),
  );
  final start = DateTime(monday.year, monday.month, monday.day - 77);
  final days = <_HeatmapDay>[
    for (var offset = 0; offset < 84; offset++)
      _HeatmapDay(date: DateTime(start.year, start.month, start.day + offset)),
  ];
  final byDate = <DateTime, _HeatmapDay>{for (final day in days) day.date: day};
  for (final portion in portions) {
    final day = byDate[portion.date];
    if (day == null) continue;
    day.duration += portion.duration;
    day.bookDurations[portion.bookId] =
        (day.bookDurations[portion.bookId] ?? Duration.zero) + portion.duration;
    day.participatingSessions.add(portion.session);
    day.pageTurns += portion.pageTurns;
    day.charactersRead += portion.charactersRead;
    day.estimatedCounts |= portion.estimatedCounts;
    day.segments.add(
      _DayReadingSegment(
        bookId: portion.bookId,
        startedAt: portion.startedAt,
        endedAt: portion.endedAt,
        duration: portion.duration,
      ),
    );
  }
  return days;
}

String _dateKey(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}';
}

String _formatTimeRange(DateTime start, DateTime end) {
  final from = _formatTime(start);
  final to = _formatTime(end);
  return from == to ? from : '$from–$to';
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
        _ProgressBand.early,
        theme.colorScheme.primary.withValues(alpha: 0.14),
        count(_ProgressBand.early),
      ),
      (
        _ProgressBand.middle,
        theme.colorScheme.primary.withValues(alpha: 0.34),
        count(_ProgressBand.middle),
      ),
      (
        _ProgressBand.advanced,
        theme.colorScheme.primary.withValues(alpha: 0.56),
        count(_ProgressBand.advanced),
      ),
      (
        _ProgressBand.late,
        theme.colorScheme.primary.withValues(alpha: 0.8),
        count(_ProgressBand.late),
      ),
      (
        _ProgressBand.finished,
        theme.colorScheme.primary,
        count(_ProgressBand.finished),
      ),
    ];
    final present = bands.where((band) => band.$3 > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 12,
            child: total == 0
                ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < present.length; index++) ...[
                        if (index > 0)
                          SizedBox(
                            width: 2,
                            child: ColoredBox(
                              color: theme.scaffoldBackgroundColor,
                            ),
                          ),
                        Expanded(
                          flex: present[index].$3,
                          child: ColoredBox(color: present[index].$2),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 18,
          runSpacing: 10,
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
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          key: textKey,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: _tabularFigures,
          ),
        ),
      ],
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.stats, required this.onOpenBook});

  final _LibraryStats stats;
  final ValueChanged<BookEntry> onOpenBook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = stats.rows
        .where((row) => row.book.lastReadAt != null)
        .toList();
    return _Section(
      title: '最近阅读',
      detail: rows.isEmpty ? null : '按最后阅读排序',
      child: rows.isEmpty
          ? const _NoReadingCard()
          : Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < rows.length; index++) ...[
                    if (index > 0)
                      Container(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    _RecentBookRow(
                      stat: rows[index],
                      onOpen: () => onOpenBook(rows[index].book),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _RecentBookRow extends StatelessWidget {
  const _RecentBookRow({required this.stat, required this.onOpen});

  final _BookReadingStat stat;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final book = stat.book;
    final percent = stat.percent;
    return InkWell(
      key: ValueKey<String>('stats-open-${book.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: bookCoverHeroTag(book.id),
              transitionOnUserGestures: true,
              child: BookCoverImage(book: book, width: 42, height: 56),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (book.author.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _positionLabel(book, stat.progress),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  const SizedBox(height: 9),
                  _ProgressLine(percent: percent),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  percent == null ? '--' : '$percent%',
                  key: ValueKey<String>('stats-book-${book.id}'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: _tabularFigures,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _relativeTime(book.lastReadAt),
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 14, color: muted),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 进度条：零值不留填充，极小进度保留 2% 可见宽度。
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.percent});

  final int? percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = percent == null ? 0.0 : (percent! / 100).clamp(0.0, 1.0);
    final visible = percent == null || percent! <= 0
        ? 0.0
        : value < 0.02
        ? 0.02
        : value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Container(
              height: 3,
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            Container(
              height: 3,
              width: constraints.maxWidth * visible,
              color: theme.colorScheme.primary,
            ),
          ],
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '还没有阅读记录，从书架打开一本书吧。',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
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
  final hours = duration.inMinutes / 60;
  final rounded = hours.roundToDouble();
  if ((hours - rounded).abs() < 0.05) {
    return '${rounded.toInt()}时';
  }
  return '${hours.toStringAsFixed(1)}时';
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
