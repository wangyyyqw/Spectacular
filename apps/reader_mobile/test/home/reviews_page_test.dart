import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reviews_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/book_review_store.dart';

class _FakeLibrary extends LibraryStore {
  _FakeLibrary(this.books) : super.memory();

  final List<BookEntry> books;

  @override
  Future<List<BookEntry>> list() async => books;
}

class _MemoryReviewStore implements BookReviewStore {
  final Map<String, BookReview> items = <String, BookReview>{};

  @override
  Future<void> remove(String bookId) async {
    items.remove(bookId);
  }

  @override
  Future<void> save(
    String bookId, {
    int? rating,
    required String content,
  }) async {
    final now = DateTime.now();
    final existing = items[bookId];
    items[bookId] = BookReview(
      bookId: bookId,
      rating: rating,
      content: content.trim(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  @override
  Future<Map<String, BookReview>> snapshot() async =>
      Map<String, BookReview>.unmodifiable(items);
}

void main() {
  testWidgets('书评页可新增、展示并删除书评', (tester) async {
    final book = BookEntry(
      id: 'review-book',
      title: '测试书',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    );
    final store = _MemoryReviewStore();

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewsPage(library: _FakeLibrary([book]), reviewStore: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有书评'), findsOneWidget);
    expect(find.text('待写书评'), findsOneWidget);
    await tester.tap(find.text('写书评'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('review-rating-4')));
    await tester.enterText(
      find.byKey(const ValueKey<String>('review-content')),
      '这是一段新的书评。',
    );
    final save = find.byKey(const ValueKey<String>('review-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.text('我的书评'), findsOneWidget);
    expect(find.text('这是一段新的书评。'), findsOneWidget);
    expect(store.items[book.id]?.rating, 4);

    await tester.tap(
      find.byKey(const ValueKey<String>('review-card-review-book')),
    );
    await tester.pumpAndSettle();
    final delete = find.byKey(const ValueKey<String>('review-delete'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(store.items, isEmpty);
    expect(find.textContaining('还没有书评'), findsOneWidget);
  });
}
