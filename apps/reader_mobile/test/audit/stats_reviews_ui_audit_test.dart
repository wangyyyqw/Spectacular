import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reviews_page.dart';
import 'package:reader_mobile/home/stats_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

class _FinishedLibrary extends LibraryStore {
  _FinishedLibrary() : super.memory();

  @override
  Future<Set<String>> finishedBookIds() async => {
    for (final book in await list()) book.id,
  };
}

class _ReviewStore implements BookReviewStore {
  final Map<String, BookReview> reviews = {};

  @override
  Future<Map<String, BookReview>> snapshot() async => Map.of(reviews);

  @override
  Future<void> save(
    String bookId, {
    int? rating,
    required String content,
  }) async {
    final now = DateTime.now();
    reviews[bookId] = BookReview(
      bookId: bookId,
      rating: rating,
      content: content,
      createdAt: reviews[bookId]?.createdAt ?? now,
      updatedAt: now,
    );
  }

  @override
  Future<void> remove(String bookId) async => reviews.remove(bookId);
}

class _SessionStore implements ReadingSessionStore {
  final List<ReadingSession> sessions = [];

  @override
  Future<List<ReadingSession>> list() async => List.of(sessions);

  @override
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    int pageTurns = 0,
    int charactersRead = 0,
  }) async {
    sessions.add(
      ReadingSession(
        bookId: bookId,
        startedAt: startedAt,
        endedAt: endedAt,
        duration: endedAt.difference(startedAt),
        pageTurns: pageTurns,
        charactersRead: charactersRead,
      ),
    );
  }
}

Widget _shell(Widget child) => MaterialApp(
  theme: ThemeData(
    useMaterial3: false,
    scaffoldBackgroundColor: const Color(0xFFF6F6F4),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF222427),
      onSurface: Color(0xFF222427),
      onSurfaceVariant: Color(0xFF686C71),
      outlineVariant: Color(0xFFE4E5E2),
      surface: Colors.white,
    ),
  ),
  home: child,
);

Future<BookEntry> _importBook(
  WidgetTester tester,
  LibraryStore library,
) async => (await tester.runAsync(
  () => library.importBytes(
    buildTestEpub(title: '新的阅读记录', author: '审计作者', identifier: 'ui-audit-new'),
  ),
))!;

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _saveReview(
  WidgetTester tester,
  String content,
  int rating,
) async {
  await tester.tap(find.byKey(ValueKey<String>('review-rating-$rating')));
  await tester.enterText(
    find.byKey(const ValueKey<String>('review-content')),
    content,
  );
  await tester.tap(find.byKey(const ValueKey<String>('review-save')));
  await tester.pumpAndSettle();
}

Future<void> _openEditor(WidgetTester tester, BookEntry book) async {
  await tester.tap(find.byKey(ValueKey<String>('review-card-${book.id}')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey<String>('review-detail-edit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('统计在窄屏保留图书时长五种周期和按书明细', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final library = LibraryStore.memory();
    final book = await _importBook(tester, library);
    final sessions = _SessionStore();
    final now = DateTime.now();
    await sessions.add(
      bookId: book.id,
      startedAt: DateTime(now.year, now.month, now.day, 10),
      endedAt: DateTime(now.year, now.month, now.day, 10, 30),
      pageTurns: 4,
      charactersRead: 80,
    );
    await tester.pumpWidget(
      _shell(
        StatsPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
          sessionStore: sessions,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('30 分钟'), findsWidgets);
    for (final period in ['day', 'week', 'month', 'quarter', 'year']) {
      final pick = find.byKey(
        const ValueKey('stats-book-duration-pick-period'),
      );
      await _scrollTo(tester, pick);
      await tester.tap(pick);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey<String>('stats-book-duration-period-$period')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('stats-book-duration-total')),
            )
            .data,
        '30 分钟',
      );
      expect(
        find.byKey(ValueKey('stats-book-duration-tag-${book.id}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    final ranking = find.byKey(ValueKey('stats-ranking-${book.id}'));
    await _scrollTo(tester, ranking);
    expect(find.text('新的阅读记录'), findsWidgets);
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('stats-ranking-counts-${book.id}')))
          .data,
      '1 次 · 4 次翻页 · 80 字',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('书评文字分组保留新建、搜索、评分编辑和删除', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final library = _FinishedLibrary();
    final book = await _importBook(tester, library);
    final store = _ReviewStore();
    await tester.pumpWidget(
      _shell(ReviewsPage(library: library, reviewStore: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reviews-tab')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('reviews-filter-pending')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('review-pending-${book.id}')));
    await tester.pumpAndSettle();
    await _saveReview(tester, '最初的读后感', 4);
    expect(store.reviews[book.id]?.rating, 4);
    await tester.tap(
      find.byKey(const ValueKey<String>('reviews-filter-reviewed')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索书评'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('reviews-search-field')),
      '不匹配',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('reviews-no-results')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('reviews-search-field')),
      '最初',
    );
    await tester.pumpAndSettle();
    await _openEditor(tester, book);
    await _saveReview(tester, '修改后的读后感', 5);
    expect(store.reviews[book.id]?.content, '修改后的读后感');
    expect(store.reviews[book.id]?.rating, 5);
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    await _openEditor(tester, book);
    await tester.tap(find.byKey(const ValueKey<String>('review-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(store.reviews, isEmpty);
    await tester.tap(find.byKey(const ValueKey<String>('reviews-filter-all')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey<String>('review-pending-${book.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
