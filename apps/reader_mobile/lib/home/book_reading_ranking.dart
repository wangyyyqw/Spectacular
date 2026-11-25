import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../library/library_store.dart';
import 'book_cover_image.dart';
import 'reading_insights.dart';
import 'reading_book_list.dart';

/// 阅读排行和最近阅读使用相同的封面卡片与完整列表抽屉。
class BookReadingRanking extends StatelessWidget {
  const BookReadingRanking({
    super.key,
    required this.books,
    required this.totals,
    this.bookTitles = const {},
    this.percents = const {},
    required this.onOpen,
  });
  final List<BookEntry> books;
  final Map<String, BookReadingTotals> totals;
  final Map<String, String> bookTitles;
  final Map<String, int?> percents;
  final ValueChanged<BookEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final book in books) book.id: book};
    if (totals.isEmpty) {
      return Text(
        '开始阅读后，这里会按投入时长列出书目。',
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return ReadingBookList(
      title: '阅读排行',
      allKey: const ValueKey('stats-ranking-all'),
      initialSort: ReadingBookSort.duration,
      books: [
        for (final entry in totals.entries)
          ReadingBookItem(
            id: entry.key,
            title:
                byId[entry.key]?.title ?? bookTitles[entry.key] ?? '已移出书架的书籍',
            author: byId[entry.key]?.author ?? '已移出书架',
            duration: entry.value.duration,
            days: entry.value.readingDays.length,
            recentOrder: entry.value.lastEndedAt?.millisecondsSinceEpoch ?? 0,
            percent: percents[entry.key],
            percentKey: ValueKey('stats-ranking-percent-${entry.key}'),
            rowKey: ValueKey('stats-ranking-${entry.key}'),
            durationKey: ValueKey('stats-ranking-duration-${entry.key}'),
            onOpen: byId[entry.key] == null
                ? null
                : () => onOpen(byId[entry.key]!),
            coverBuilder: (width, height) => byId[entry.key] == null
                ? SizedBox(
                    width: width,
                    height: height,
                    child: const ColoredBox(
                      color: Color(0xFFE0E0E0),
                      child: AppIcon(AppGlyph.menuBook, size: 20),
                    ),
                  )
                : BookCoverImage(
                    book: byId[entry.key]!,
                    width: width,
                    height: height,
                  ),
          ),
      ],
    );
  }
}
