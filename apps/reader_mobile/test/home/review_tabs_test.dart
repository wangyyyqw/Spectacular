import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reviews_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';

class _Library extends LibraryStore {
  _Library(this.books) : super.memory();

  final List<BookEntry> books;

  @override
  Future<List<BookEntry>> list() async => books;

  @override
  Future<Set<String>> finishedBookIds() async => {
    for (final book in books) book.id,
  };
}

class _Reviews implements BookReviewStore {
  int snapshots = 0;

  @override
  Future<Map<String, BookReview>> snapshot() async {
    snapshots++;
    return const {};
  }

  @override
  Future<void> save(
    String bookId, {
    int? rating,
    required String content,
  }) async {}

  @override
  Future<void> remove(String bookId) async {}
}

BookEntry _book() => BookEntry(
  id: 'book',
  title: '无笔记也无书评',
  author: '作者',
  filePath: '',
  addedAt: DateTime(2026),
);

void main() {
  testWidgets('书评页默认进入笔记，切换到书评时才查询书评', (tester) async {
    final store = _Reviews();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ReviewsPage(library: _Library([_book()]), reviewStore: store),
      ),
    );
    await tester.pumpAndSettle();

    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.controller!.index, 0);
    expect(find.text('还没有笔记'), findsOneWidget);
    expect(find.byTooltip('刷新笔记'), findsOneWidget);
    expect(find.byTooltip('搜索书评'), findsNothing);
    expect(store.snapshots, 0);

    await tester.tap(find.byKey(const ValueKey('reviews-tab')));
    await tester.pumpAndSettle();
    expect(tabs.controller!.index, 1);
    expect(find.text('已写 0 篇 · 待写 1 本'), findsOneWidget);
    expect(find.byTooltip('刷新书评'), findsOneWidget);
    expect(find.byTooltip('搜索书评'), findsOneWidget);
    expect(store.snapshots, 1);

    await tester.tap(find.byKey(const ValueKey('notes-tab')));
    await tester.pumpAndSettle();
    expect(tabs.controller!.index, 0);
    expect(find.text('还没有笔记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
