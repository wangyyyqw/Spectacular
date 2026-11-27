import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reviews_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';

class _Library extends LibraryStore {
  _Library(this.books) : super.memory();

  final List<BookEntry> books;
  Completer<void>? pendingList;

  @override
  Future<List<BookEntry>> list() async {
    await pendingList?.future;
    return books;
  }

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
  testWidgets('切回已加载的笔记和书评时保留内容，后台完成刷新', (tester) async {
    final library = _Library([_book()]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ReviewsPage(library: library, reviewStore: _Reviews()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reviews-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-pending-book')), findsOneWidget);

    library.pendingList = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('notes-tab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('还没有笔记'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byKey(const ValueKey('reviews-tab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('review-pending-book')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    library.books[0] = _book().copyWith(title: '刷新后的书名');
    library.pendingList!.complete();
    await tester.pumpAndSettle();
    expect(find.text('刷新后的书名'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('书评页默认进入笔记，切换到书评时才查询书评', (tester) async {
    final store = _Reviews();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ReviewsPage(library: _Library([_book()]), reviewStore: store),
      ),
    );
    await tester.pumpAndSettle();

    bool selected(String section) =>
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: find.byKey(ValueKey('$section-tab')),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .selected ??
        false;
    expect(selected('notes'), isTrue);
    expect(selected('reviews'), isFalse);
    expect(selected('booklists'), isFalse);
    expect(find.text('还没有笔记'), findsOneWidget);
    expect(find.byTooltip('刷新笔记'), findsNothing);
    expect(find.byTooltip('刷新书评'), findsNothing);
    expect(find.byTooltip('搜索笔记'), findsOneWidget);
    expect(find.byTooltip('搜索书评'), findsNothing);
    expect(store.snapshots, 0);

    await tester.tap(find.byKey(const ValueKey('booklists-tab')));
    await tester.pumpAndSettle();
    expect(selected('booklists'), isTrue);
    expect(find.text('还没有书单'), findsOneWidget);
    expect(find.byTooltip('搜索书单'), findsOneWidget);
    expect(store.snapshots, 0);

    await tester.tap(find.byKey(const ValueKey('reviews-tab')));
    await tester.pumpAndSettle();
    expect(selected('reviews'), isTrue);
    expect(find.byKey(const ValueKey('review-pending-book')), findsOneWidget);
    expect(find.byTooltip('刷新书评'), findsNothing);
    expect(find.byTooltip('搜索书评'), findsOneWidget);
    expect(store.snapshots, 1);

    await tester.tap(find.byKey(const ValueKey('notes-tab')));
    await tester.pumpAndSettle();
    expect(selected('notes'), isTrue);
    expect(find.text('还没有笔记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('左右滑动切换笔记、书评和书单', (tester) async {
    final store = _Reviews();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ReviewsPage(library: _Library([_book()]), reviewStore: store),
      ),
    );
    await tester.pumpAndSettle();
    final body = find.byKey(const ValueKey('reviews-section-body'));
    expect(
      tester.widget<GestureDetector>(body).onHorizontalDragUpdate,
      isNotNull,
    );

    final gesture = await tester.startGesture(tester.getCenter(body));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    final pages = find.descendant(
      of: body,
      matching: find.byType(FractionalTranslation),
    );
    expect(pages, findsNWidgets(2));
    final oldPageOffset = tester
        .widget<FractionalTranslation>(pages.at(0))
        .translation
        .dx;
    final newPageOffset = tester
        .widget<FractionalTranslation>(pages.at(1))
        .translation
        .dx;
    expect(oldPageOffset, lessThan(0));
    expect(newPageOffset, greaterThan(0));
    expect(newPageOffset - oldPageOffset, closeTo(1, .01));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-pending-book')), findsOneWidget);
    await tester.drag(body, const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(find.text('还没有笔记'), findsOneWidget);

    await tester.drag(body, const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-pending-book')), findsOneWidget);

    await tester.drag(body, const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(find.text('还没有书单'), findsOneWidget);

    await tester.drag(body, const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-pending-book')), findsOneWidget);

    await tester.drag(body, const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(find.text('还没有笔记'), findsOneWidget);

    await tester.drag(body, const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(find.text('还没有笔记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
