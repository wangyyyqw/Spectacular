import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/library_store.dart';
import 'book_cover_image.dart';
import 'book_duration_chart.dart';
import 'desktop_layout.dart';
import 'reading_calendar.dart';
import 'reading_insights.dart';
import 'book_reading_ranking.dart';
import 'weekday_average_chart.dart';
import '../reader/book_opener.dart';
import '../storage/reading_session_store.dart';

/// 统计页：图书时长、阅读日历、每日平均与按书排行，保留完整统计数据汇总。
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
    this.now,
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

  /// 测试可固定当前时间；正常使用设备时间。
  final DateTime? now;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late final BookOpener _bookOpener;
  _StatsContent? _content;
  List<Record> _snapshot = const [];
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
    if (oldWidget.active && !widget.active) {
      _dirty = true;
      _reloadToken++;
    }
    final becameActive = !oldWidget.active && widget.active;
    if ((becameActive && _dirty) ||
        oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.sessionStore != widget.sessionStore ||
        oldWidget.now != widget.now) {
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
    if (!widget.active) {
      _dirty = true;
      return;
    }
    _dirty = false;
    final token = ++_reloadToken;
    try {
      final books = await widget.library.list();
      if (!_acceptsReload(token)) return;
      final progress = await widget.progressStore.snapshot();
      if (!_acceptsReload(token)) return;
      final weightsByBook = await widget.library.progressWeightsForBooks(
        books.map((book) => book.id),
      );
      if (!_acceptsReload(token)) return;
      final storedSessions =
          await (_sessionStore?.list() ??
              Future<List<ReadingSession>>.value(const []));
      // 已切走或被新刷新取代的读取结果不再聚合，也不重建隐藏图表。
      if (!_acceptsReload(token)) return;
      final now = widget.now ?? DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final insights = ReadingInsights(
        storedSessions,
        now: now,
        minimumDayDuration: minimumCountedDayDuration,
      );
      final sessions = insights.sessions;
      final readingByDay = insights.byDay;
      final rows = <_BookReadingStat>[];
      final sessionBookIds = {
        for (final session in storedSessions) session.bookId,
      };
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
          _BookReadingStat(
            book: book,
            progress: current,
            percent: percent,
            recentReadAt: sessionBookIds.contains(book.id)
                ? insights.byBook[book.id]?.lastEndedAt
                : book.lastReadAt,
          ),
        );
      }
      rows.sort((left, right) {
        final leftTime = left.recentReadAt;
        final rightTime = right.recentReadAt;
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
      if (storedSessions.isNotEmpty) {
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
        hasReadingSessions: storedSessions.isNotEmpty,
      );
      final snapshot = _statsSnapshot(now, stats, storedSessions);
      if (listEquals(_snapshot, snapshot)) return;
      setState(() {
        _snapshot = snapshot;
        _content = _StatsContent(
          stats: stats,
          onOpenBook: _openBook,
          now: widget.now,
        );
        _error = null;
      });
    } catch (_) {
      if (!_acceptsReload(token)) return;
      if (_content == null) {
        setState(() => _error = '统计加载失败');
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('统计刷新失败，请稍后重试')));
      }
    }
  }

  bool _acceptsReload(int token) =>
      mounted && widget.active && token == _reloadToken;

  Future<void> _openBook(BookEntry entry) async {
    await _bookOpener.open(context, entry);
    if (mounted) {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;
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
            icon: const AppIcon(AppGlyph.refresh),
          ),
        ],
        bottom: const _AppBarHairline(),
      ),
      body: content == null
          ? _error == null
                ? const _StatsSkeleton()
                : _StatsError(onRetry: _reload)
          : RefreshIndicator(onRefresh: _reload, child: content),
    );
  }
}

/// 快照未变时复用内容；主题、字号和平台仍由内容自己的依赖触发更新。
class _StatsContent extends StatelessWidget {
  const _StatsContent({
    required this.stats,
    required this.onOpenBook,
    this.now,
  });

  final _LibraryStats stats;
  final Future<void> Function(BookEntry) onOpenBook;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final desktop = usesDesktopLayout(context);
    final sections = _sections(desktop);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: desktop ? 1280 : 680),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            desktop ? 28 : 20,
            20,
            desktop ? 28 : 20,
            36,
          ),
          children: [
            if (desktop)
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 800 ? 2 : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 32) / columns;
                  return Wrap(
                    key: const ValueKey('stats-desktop-sections'),
                    spacing: 32,
                    runSpacing: 32,
                    children: [
                      for (final section in sections)
                        SizedBox(width: width, child: section),
                    ],
                  );
                },
              )
            else
              ...sections,
            _RecentSection(stats: stats, onOpenBook: onOpenBook),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(bool desktop) {
    final titles = {for (final row in stats.rows) row.book.id: row.book.title};
    return [
      _Section(
        title: '图书时长',
        showDivider: false,
        child: BookDurationChart(
          insights: stats.insights,
          bookTitles: titles,
          now: now,
        ),
      ),
      _Section(
        title: '阅读日历',
        showDivider: !desktop,
        child: ReadingCalendar(
          insights: stats.insights,
          bookTitles: titles,
          now: now,
          finishedBookIds: {
            for (final row in stats.rows)
              if (row.progress?.finished ?? false) row.book.id,
          },
        ),
      ),
      _Section(
        title: '每日平均',
        detail: '按星期',
        caption: '仅计有阅读记录的日期',
        showDivider: !desktop,
        child: WeekdayAverageChart(insights: stats.insights),
      ),
      _Section(
        title: '阅读排行',
        detail: '按累计时长',
        showDivider: !desktop,
        child: BookReadingRanking(
          books: [for (final row in stats.rows) row.book],
          totals: stats.insights.byBook,
          bookTitles: stats.insights.bookTitles,
          onOpen: onOpenBook,
        ),
      ),
    ];
  }
}

/// 按值比较，权重变化通过实际百分比与总字数体现；保留原始会话全部字段。
List<Record> _statsSnapshot(
  DateTime now,
  _LibraryStats stats,
  List<ReadingSession> sessions,
) => [
  (DateTime(now.year, now.month, now.day), stats.totalCharacters),
  for (final row in stats.rows)
    (
      (
        row.book.id,
        row.book.title,
        row.book.author,
        row.book.description,
        row.book.filePath,
        row.book.addedAt,
        row.book.lastReadAt,
        row.book.spineCount,
        row.book.readabilityLevel,
        row.book.coverPath,
        row.book.contentRevision,
        row.book.importOutcome,
      ),
      row.progress,
      row.percent,
      row.recentReadAt,
      _relativeTime(row.recentReadAt, now: now),
    ),
  for (final session in sessions)
    (
      session.bookId,
      session.bookTitle,
      session.startedAt,
      session.endedAt,
      session.duration,
      session.pageTurns,
      session.charactersRead,
    ),
];

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
    required this.recentReadAt,
  });

  final BookEntry book;
  final ReaderProgress? progress;
  final int? percent;

  /// 最近阅读时间：取达标日期内的会话结束时间，无会话的历史书沿用最后阅读时间。
  final DateTime? recentReadAt;
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
          const SizedBox(height: 24),
          Container(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Semantics(
                container: true,
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
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
        const SizedBox(height: 12),
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
    return Center(
      child: SizedBox(
        width: 680,
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          children: [
            Align(alignment: Alignment.centerLeft, child: block(20, width: 64)),
            const SizedBox(height: 12),
            block(48),
            const SizedBox(height: 12),
            block(48),
            const SizedBox(height: 12),
            Center(child: block(160, width: 160)),
            const SizedBox(height: 12),
            for (var index = 0; index < 5; index++) ...[
              block(44),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
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
            AppIcon(AppGlyph.error, size: 32, color: muted),
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

class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.stats, required this.onOpenBook});

  final _LibraryStats stats;
  final ValueChanged<BookEntry> onOpenBook;

  @override
  Widget build(BuildContext context) {
    final rows = stats.rows.where((row) => row.recentReadAt != null).toList();
    return _Section(
      title: '最近阅读',
      detail: rows.isEmpty ? null : '按最后阅读排序',
      child: rows.isEmpty
          ? const _NoReadingCard()
          : Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  _RecentBookRow(
                    stat: rows[index],
                    onOpen: () => onOpenBook(rows[index].book),
                  ),
                ],
              ],
            ),
    );
  }
}

class _RecentBookRow extends StatelessWidget {
  const _RecentBookRow({required this.stat, required this.onOpen});

  final _BookReadingStat stat;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey<String>('stats-open-${stat.book.id}'),
    onTap: onOpen,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hero(
            tag: bookCoverHeroTag(stat.book.id),
            transitionOnUserGestures: true,
            child: BookCoverImage(book: stat.book, width: 40, height: 54),
          ),
          const SizedBox(width: 12),
          Expanded(child: _details(context)),
        ],
      ),
    ),
  );

  Widget _details(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headline(),
        if (stat.book.author.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            stat.book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          _positionLabel(stat.book, stat.progress),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, height: 1.4, color: muted),
        ),
        const SizedBox(height: 8),
        _footer(context),
      ],
    );
  }

  Widget _headline() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          stat.book.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Text(
        stat.percent == null ? '--' : '${stat.percent}%',
        key: ValueKey<String>('stats-book-${stat.book.id}'),
        style: const TextStyle(
          fontSize: 13,
          height: 1.4,
          fontWeight: FontWeight.w600,
          fontFeatures: _tabularFigures,
        ),
      ),
    ],
  );

  Widget _footer(BuildContext context) => Row(
    children: [
      Expanded(child: _ProgressLine(percent: stat.percent)),
      const SizedBox(width: 12),
      Text(
        _relativeTime(stat.recentReadAt),
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(width: 2),
      AppIcon(
        AppGlyph.chevronRight,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ],
  );
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
          AppIcon(
            AppGlyph.autoStories,
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

String _relativeTime(DateTime? time, {DateTime? now}) {
  if (time == null) {
    return '';
  }
  final delta = (now ?? DateTime.now()).difference(time);
  if (delta.isNegative || delta.inMinutes < 1) return '刚刚';
  if (delta.inHours < 1) return '${delta.inMinutes} 分钟前';
  if (delta.inDays < 1) return '${delta.inHours} 小时前';
  return '${delta.inDays} 天前';
}
