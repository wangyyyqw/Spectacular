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

BookEntry _book(String id, String title, String author) => BookEntry(
  id: id,
  title: title,
  author: author,
  filePath: '',
  addedAt: DateTime(2026),
);

BookReview _review(String bookId, String content, {int rating = 4}) {
  final time = DateTime(2026);
  return BookReview(
    bookId: bookId,
    rating: rating,
    content: content,
    createdAt: time,
    updatedAt: time,
  );
}

Future<void> _pumpReviews(
  WidgetTester tester, {
  required List<BookEntry> books,
  required _MemoryReviewStore store,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ReviewsPage(library: _FakeLibrary(books), reviewStore: store),
    ),
  );
  await tester.pumpAndSettle();
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

  testWidgets('未保存书评关闭前确认，可继续编辑或放弃修改', (tester) async {
    final book = _book('draft-book', '草稿测试书', '作者');
    final store = _MemoryReviewStore();
    await _pumpReviews(tester, books: <BookEntry>[book], store: store);

    await tester.tap(find.text('写书评'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('review-content')),
      '还没有保存的草稿',
    );
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    expect(find.text('放弃未保存的书评？'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('review-discard-cancel')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('review-editor')), findsOneWidget);
    expect(find.text('还没有保存的草稿'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('review-discard-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('review-editor')), findsNothing);
    expect(store.items, isEmpty);
  });

  testWidgets('书评搜索支持书名、作者和正文且不改变顶部汇总', (tester) async {
    final books = <BookEntry>[
      _book('star', '星河', '刘慈欣'),
      _book('alive', '活着', '余华'),
      _book('stationery', '山茶文具店', '小川糸'),
    ];
    final store = _MemoryReviewStore()
      ..items.addAll(<String, BookReview>{
        'star': _review('star', '宇宙的尺度令人敬畏。'),
        'alive': _review('alive', '生命力穿过苦难。'),
      });
    await _pumpReviews(tester, books: books, store: store);

    expect(find.text('已写 2 / 3 本'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索书评'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('reviews-search-field')),
      '刘慈欣',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('review-card-star')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('review-card-alive')),
      findsNothing,
    );
    expect(find.text('已写 1'), findsOneWidget);
    expect(find.text('已写 2 / 3 本'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('reviews-search-field')),
      '宇宙',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('review-card-star')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('reviews-search-field')),
      '余华',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('review-card-alive')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('reviews-search-field')),
      '星河',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('review-card-star')),
      findsOneWidget,
    );
    expect(find.text('已写 2 / 3 本'), findsOneWidget);
  });

  testWidgets('书评页可按已写和待写状态筛选', (tester) async {
    final books = <BookEntry>[
      _book('reviewed-a', '已写甲', '作者甲'),
      _book('reviewed-b', '已写乙', '作者乙'),
      _book('pending-a', '待写甲', '作者丙'),
      _book('pending-b', '待写乙', '作者丁'),
    ];
    final store = _MemoryReviewStore()
      ..items.addAll(<String, BookReview>{
        'reviewed-a': _review('reviewed-a', '甲的书评'),
        'reviewed-b': _review('reviewed-b', '乙的书评'),
      });
    await _pumpReviews(tester, books: books, store: store);

    expect(find.text('全部 4'), findsOneWidget);
    expect(find.text('已写 2'), findsOneWidget);
    expect(find.text('待写 2'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('reviews-filter-reviewed')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('review-card-reviewed-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('review-card-reviewed-b')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('review-pending-pending-a')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('reviews-filter-pending')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('review-card-reviewed-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('review-pending-pending-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('review-pending-pending-b')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('reviews-filter-all')));
    await tester.pumpAndSettle();
    final allChip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey<String>('reviews-filter-all')),
    );
    expect(allChip.selected, isTrue);
    expect(
      find.byKey(const ValueKey<String>('review-card-reviewed-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('review-pending-pending-a')),
      findsOneWidget,
    );
  });

  testWidgets('书评无匹配时可清除搜索与筛选', (tester) async {
    final books = <BookEntry>[
      _book('reviewed', '已写书', '作者甲'),
      _book('pending', '待写书', '作者乙'),
    ];
    final store = _MemoryReviewStore()
      ..items['reviewed'] = _review('reviewed', '一段书评');
    await _pumpReviews(tester, books: books, store: store);

    await tester.tap(
      find.byKey(const ValueKey<String>('reviews-filter-reviewed')),
    );
    await tester.tap(find.byTooltip('搜索书评'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('reviews-search-field')),
      '不存在',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('reviews-no-results')),
      findsOneWidget,
    );
    expect(find.text('没有找到相关书评'), findsOneWidget);
    expect(find.text('没有书名、作者或书评正文包含“不存在”'), findsOneWidget);

    await tester.tap(find.text('清除搜索与筛选'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('reviews-no-results')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('reviews-search-field')),
      findsNothing,
    );
    final allChip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey<String>('reviews-filter-all')),
    );
    expect(allChip.selected, isTrue);
    expect(
      find.byKey(const ValueKey<String>('review-card-reviewed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('review-pending-pending')),
      findsOneWidget,
    );
  });
}
