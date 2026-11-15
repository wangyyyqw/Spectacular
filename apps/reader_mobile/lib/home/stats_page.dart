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

/// 统计页：图书时长、习惯与按书排行，保留完整统计数据汇总。
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
                  _Section(
                    title: '图书时长',
                    showDivider: false,
                    child: BookDurationChart(
                      insights: stats.insights,
                      bookTitles: {
                        for (final row in stats.rows)
                          row.book.id: row.book.title,
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

/// 统计数据接口继续保留，顶部摘要与概览移除后仍按原口径填充全部字段。
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
    this.showDivider = true,
    required this.child,
  });

  final String title;
  final String? detail;
  final String? caption;
  final bool showDivider;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDivider) ...[
          const SizedBox(height: 30),
          Container(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 14),
        ],
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
        block(12, width: 64),
        const SizedBox(height: 16),
        block(48),
        const SizedBox(height: 12),
        block(48),
        const SizedBox(height: 24),
        Center(child: block(160, width: 160)),
        const SizedBox(height: 24),
        block(56),
        const SizedBox(height: 16),
        block(56),
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
