import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/library_store.dart';
import '../reader/book_opener.dart';

enum _ProgressBand {
  unread('未开始'),
  early('0-25%'),
  middle('26-50%'),
  advanced('51-75%'),
  late('76-100%');

  const _ProgressBand(this.label);

  final String label;
}

/// 统计页：书量、阅读进度、近七日阅读与最近阅读。
///
/// 数据全部来自书架、阅读进度和导入期字符统计，不维护额外埋点。
class StatsPage extends StatefulWidget {
  /// 创建页面。
  const StatsPage({
    super.key,
    required this.library,
    required this.progressStore,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 进度存储。
  final ReaderProgressStore progressStore;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late final BookOpener _bookOpener;
  _LibraryStats? _stats;
  int _reloadToken = 0;

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

  Future<void> _reload() async {
    final token = ++_reloadToken;
    final books = await widget.library.list();
    final progress = await widget.progressStore.snapshot();
    final rows = <_BookReadingStat>[];
    var started = 0;
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
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final recent = rows.where((row) {
      final lastReadAt = row.book.lastReadAt;
      return lastReadAt != null && !lastReadAt.isBefore(weekAgo);
    }).length;
    final stats = _LibraryStats(
      rows: rows,
      started: started,
      recent: recent,
      totalCharacters: totalCharacters,
      averageProgress: percentCount == 0
          ? null
          : (percentSum / percentCount).round(),
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
                        label: '近 7 天',
                        value: '${stats.recent}',
                        valueKey: const ValueKey<String>('stats-recent-7-days'),
                      ),
                      const SizedBox(width: 8),
                      _MetricTile(
                        icon: Icons.text_fields,
                        label: '累计字数',
                        value: _formatCharacters(stats.totalCharacters),
                        valueKey: const ValueKey<String>(
                          'stats-total-characters',
                        ),
                      ),
                    ],
                  ),
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
    required this.recent,
    required this.totalCharacters,
    required this.averageProgress,
  });

  final List<_BookReadingStat> rows;
  final int started;
  final int recent;
  final int totalCharacters;
  final int? averageProgress;
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
                  average == null ? '还没有开始阅读' : '已开始 ${stats.started} 本书',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.76,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  average == null ? '从书架打开一本书，进度会同步到这里。' : '保持节奏，继续下一章。',
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
    if (coverPath == null) {
      return placeholder;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        File(coverPath),
        width: 42,
        height: 56,
        fit: BoxFit.cover,
        cacheWidth: 126,
        errorBuilder: (_, _, _) => placeholder,
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
