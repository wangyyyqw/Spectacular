import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

/// 本地和阅微记录共用的列表数据；最近顺序由各数据源提供。
class ReadingBookItem {
  const ReadingBookItem({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.days,
    this.daysCumulative = false,
    required this.recentOrder,
    required this.coverBuilder,
    this.percent,
    this.statusIcon,
    this.statusLabel,
    this.linked = false,
    this.finished = false,
    this.onOpen,
    this.onHide,
    this.rowKey,
    this.percentKey,
    this.durationKey,
  });

  final String id;
  final String title;
  final String author;
  final Duration duration;
  final int days;
  final bool daysCumulative;
  final int recentOrder;
  final int? percent;
  final Widget Function(double width, double height) coverBuilder;
  final IconData? statusIcon;
  final String? statusLabel;
  final bool linked;
  final bool finished;
  final VoidCallback? onOpen;
  final VoidCallback? onHide;
  final Key? rowKey;
  final Key? percentKey;
  final Key? durationKey;
}

enum ReadingBookSort {
  recent('最近阅读'),
  duration('阅读时长'),
  days('阅读天数');

  const ReadingBookSort(this.label);
  final String label;
}

List<ReadingBookItem> _sorted(
  List<ReadingBookItem> books,
  ReadingBookSort sort,
) => List<ReadingBookItem>.of(books)
  ..sort((left, right) {
    final compared = switch (sort) {
      ReadingBookSort.recent => right.recentOrder.compareTo(left.recentOrder),
      ReadingBookSort.duration => right.duration.compareTo(left.duration),
      ReadingBookSort.days => right.days.compareTo(left.days),
    };
    return compared != 0 ? compared : left.id.compareTo(right.id);
  });

/// 卡片预览固定按时长展示前三本，完整列表在抽屉中切换排序。
class ReadingBookList extends StatelessWidget {
  const ReadingBookList({
    super.key,
    required this.books,
    required this.title,
    required this.allKey,
    this.initialSort = ReadingBookSort.recent,
  });

  final List<ReadingBookItem> books;
  final String title;
  final Key allKey;
  final ReadingBookSort initialSort;

  Future<void> _showAll(BuildContext context) async {
    final selected = await showReaderDrawer<ReadingBookItem>(
      context: context,
      builder: (_) => _AllReadingBooks(
        books: books,
        title: title,
        initialSort: initialSort,
      ),
    );
    if (selected != null && context.mounted) selected.onOpen?.call();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _sorted(books, ReadingBookSort.duration).take(3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final book in visible) ...[
          ReadingBookTile(item: book),
          const SizedBox(height: 8),
        ],
        if (books.isNotEmpty)
          TextButton(
            key: allKey,
            style: TextButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              shape: ReaderUiStyle.controlShapeOf(Theme.of(context)),
            ),
            onPressed: () => _showAll(context),
            child: Text('查看全部 · ${books.length} 本'),
          ),
      ],
    );
  }
}

class _AllReadingBooks extends StatefulWidget {
  const _AllReadingBooks({
    required this.books,
    required this.title,
    required this.initialSort,
  });

  final List<ReadingBookItem> books;
  final String title;
  final ReadingBookSort initialSort;

  @override
  State<_AllReadingBooks> createState() => _AllReadingBooksState();
}

class _AllReadingBooksState extends State<_AllReadingBooks> {
  late ReadingBookSort _sort = widget.initialSort;
  late final List<ReadingBookItem> _books = List.of(widget.books);

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted(_books, _sort);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    '全部',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                PopupMenuButton<ReadingBookSort>(
                  key: const ValueKey('reading-books-sort'),
                  tooltip: '切换排序',
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (_) => [
                    for (final value in ReadingBookSort.values)
                      PopupMenuItem(
                        value: value,
                        child: Semantics(
                          checked: value == _sort,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: value == _sort
                                    ? const Icon(Icons.check, size: 18)
                                    : null,
                              ),
                              Text(value.label),
                            ],
                          ),
                        ),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_sort.label),
                        const Icon(Icons.arrow_drop_down, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              key: const ValueKey('reading-books-all-list'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: sorted.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final book = sorted[index];
                return ReadingBookTile(
                  item: book,
                  showDays: false,
                  onOpen: book.onOpen == null
                      ? null
                      : () => Navigator.pop(context, book),
                  onHide: book.onHide == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          book.onHide!.call();
                        },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 书名、作者、统计三行与封面等高，右侧显示进度、关联和隐藏入口。
class ReadingBookTile extends StatelessWidget {
  const ReadingBookTile({
    super.key,
    required this.item,
    this.showDays = true,
    this.onOpen,
    this.onHide,
  });

  final ReadingBookItem item;
  final bool showDays;
  final VoidCallback? onOpen;
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final height = 66.0 * scale;
    return Material(
      shape: ReaderUiStyle.cardShapeOf(theme),
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: item.rowKey ?? ValueKey('reading-book-${item.id}'),
        onTap: onOpen ?? item.onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              item.coverBuilder(46 * scale, height),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: height,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.percent == null ? '--' : '${item.percent}%',
                            key: item.percentKey,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.author.isEmpty ? '未知作者' : item.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: muted,
                              ),
                            ),
                          ),
                          if (item.statusIcon != null) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: item.statusLabel ?? '',
                              child: SizedBox(
                                width: 20,
                                child: Center(
                                  child: Icon(
                                    item.statusIcon,
                                    size: 16,
                                    color: item.linked
                                        ? theme.colorScheme.primary
                                        : muted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              '${formatBookReadingDuration(item.duration)}'
                              '${showDays ? ' · ${item.daysCumulative ? '累计' : ''}读了 ${item.days} 天' : ''}'
                              '${item.finished ? ' · 已读完' : ''}',
                              key: item.durationKey,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: muted,
                              ),
                            ),
                          ),
                          if ((onHide ?? item.onHide) != null) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: IconButton(
                                key: ValueKey('reading-book-hide-${item.id}'),
                                tooltip: '隐藏阅读记录',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: onHide ?? item.onHide,
                                icon: Icon(
                                  Icons.visibility_off_outlined,
                                  size: 16,
                                  color: item.linked
                                      ? theme.colorScheme.primary
                                      : muted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String formatBookReadingDuration(Duration duration) {
  final minutes = duration.inMinutes;
  if (duration <= Duration.zero) return '0 分钟';
  if (minutes < 1) return '<1 分钟';
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
}
