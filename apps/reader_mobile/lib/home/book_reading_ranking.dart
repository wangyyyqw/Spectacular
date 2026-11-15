import 'package:flutter/material.dart';

import '../library/library_store.dart';
import 'book_cover_image.dart';
import 'reading_insights.dart';

typedef _RankedBook = ({
  String id,
  String title,
  BookEntry? book,
  BookReadingTotals totals,
});

/// 按累计阅读时长排序，封面、次数、翻页和字数共同说明阅读投入。
class BookReadingRanking extends StatelessWidget {
  const BookReadingRanking({
    super.key,
    required this.books,
    required this.totals,
    this.bookTitles = const {},
    required this.onOpen,
  });

  final List<BookEntry> books;
  final Map<String, BookReadingTotals> totals;
  final Map<String, String> bookTitles;
  final ValueChanged<BookEntry> onOpen;

  List<_RankedBook> get _ranked {
    final byId = {for (final book in books) book.id: book};
    return [
      for (final entry in totals.entries)
        (
          id: entry.key,
          title: byId[entry.key]?.title ?? bookTitles[entry.key] ?? '已移出书架的书籍',
          book: byId[entry.key],
          totals: entry.value,
        ),
    ]..sort((left, right) {
      final time = right.totals.duration.compareTo(left.totals.duration);
      return time == 0 ? left.title.compareTo(right.title) : time;
    });
  }

  Future<void> _showAll(BuildContext context, List<_RankedBook> ranked) async {
    final book = await showModalBottomSheet<BookEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '累计阅读排行',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final book in ranked)
                    _RankingRow(
                      book: book,
                      onOpen: book.book == null
                          ? null
                          : () => Navigator.of(context).pop(book.book),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (book != null && context.mounted) {
      onOpen(book);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ranked = _ranked;
    if (ranked.isEmpty) {
      return Text(
        '开始阅读后，这里会按投入时长列出书目。',
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: [
        for (final book in ranked.take(3))
          _RankingRow(
            book: book,
            onOpen: book.book == null ? null : () => onOpen(book.book!),
          ),
        if (ranked.length > 3)
          TextButton(
            key: const ValueKey('stats-ranking-all'),
            onPressed: () => _showAll(context, ranked),
            child: Text('查看全部 ${ranked.length} 本'),
          ),
      ],
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.book, required this.onOpen});

  final _RankedBook book;
  final VoidCallback? onOpen;

  Widget _cover(BuildContext context) => book.book == null
      ? Container(
          width: 36,
          height: 48,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.menu_book_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        )
      : BookCoverImage(book: book.book!, width: 36, height: 48);

  Widget _details(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Text(
          '${book.totals.sessions} 次 · ${book.totals.pageTurns} 次翻页 · ${book.totals.charactersRead} 字',
          key: ValueKey('stats-ranking-counts-${book.id}'),
          maxLines: 2,
          style: TextStyle(fontSize: 11, color: muted),
        ),
        if (book.book == null)
          Text('已移出书架', style: TextStyle(fontSize: 11, color: muted)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('stats-ranking-${book.id}'),
    onTap: onOpen,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          _cover(context),
          const SizedBox(width: 12),
          Expanded(child: _details(context)),
          const SizedBox(width: 10),
          Text(
            formatReadingDuration(book.totals.duration),
            key: ValueKey('stats-ranking-duration-${book.id}'),
            style: const TextStyle(
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );
}
