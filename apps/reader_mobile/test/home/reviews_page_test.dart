import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reviews_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';

class _FakeLibrary extends LibraryStore {
  _FakeLibrary(
    this.books, {
    Set<String>? finishedIds,
    this.retained = const <BookEntry>[],
  }) : finishedIds = finishedIds ?? {for (final book in books) book.id},
       super.memory();

  final List<BookEntry> books;

  /// 已移出书架但仍保留书评的书籍。
  final List<BookEntry> retained;
  final Set<String> finishedIds;

  @override
  Future<List<BookEntry>> list() async => books;

  @override
  Future<List<BookEntry>> retainedBooks() async => retained;

  @override
  Future<Set<String>> finishedBookIds() async => Set.of(finishedIds);
}

class _MemoryReviewStore implements BookReviewStore {
  final Map<String, BookReview> items = <String, BookReview>{};
  bool failSnapshot = false;
  bool failSave = false;
  Completer<void>? pendingSnapshot;
  Completer<void>? pendingSave;
  int saveCalls = 0;

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
    saveCalls++;
    if (failSave) throw StateError('写入失败');
    await pendingSave?.future;
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
  Future<Map<String, BookReview>> snapshot() async {
    if (failSnapshot) throw StateError('读取失败');
    final snapshot = Map<String, BookReview>.unmodifiable(items);
    await pendingSnapshot?.future;
    return snapshot;
  }
}

BookEntry _book(String id, String title, String author) => BookEntry(
  id: id,
  title: title,
  author: author,
  filePath: '',
  addedAt: DateTime(2026),
);

BookReview _review(
  String bookId,
  String content, {
  int rating = 4,
  DateTime? updatedAt,
}) {
  final time = updatedAt ?? DateTime(2026);
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
  List<BookEntry> retained = const <BookEntry>[],
  Set<String>? finishedIds,
  Size size = const Size(1080, 2400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ReviewsPage(
        library: _FakeLibrary(
          books,
          finishedIds: finishedIds,
          retained: retained,
        ),
        reviewStore: store,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _openReviewsTab(tester);
}

Future<void> _openReviewsTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('reviews-tab')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('仅评分与空白正文归待写，补写正文后进入已写并保留评分', (tester) async {
    final store = _MemoryReviewStore()
      ..items['rated'] = _review('rated', ' \n ', rating: 5)
      ..items['written'] = _review('written', '真正的评价正文');
    await _pumpReviews(
      tester,
      books: [_book('rated', '仅评分', '作者'), _book('written', '有正文', '作者')],
      store: store,
    );
    expect(find.text('已写 1 篇 · 待写 1 本 · 平均 4.5 星'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-card-written')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-pending-rated')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-pending-rated')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-editor')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('review-content')),
      '补写的评价正文',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await tester.pumpAndSettle();
    expect(store.items['rated']?.rating, 5);
    expect(store.items['rated']?.content, '补写的评价正文');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('reviews-summary')),
      -150,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('已写 2 篇 · 待写 0 本 · 平均 4.5 星'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    '桌面书评并排展示、常驻搜索，窄窗编辑抽屉可取消并保存',
    (tester) async {
      final books = [_book('one', '第一本书', '作者甲'), _book('two', '第二本书', '作者乙')];
      final store = _MemoryReviewStore()
        ..items['one'] = _review('one', '第一篇书评')
        ..items['two'] = _review('two', '第二篇书评');
      await _pumpReviews(
        tester,
        books: books,
        store: store,
        size: const Size(2560, 1800),
      );
      final first = find.byKey(const ValueKey('review-card-one'));
      final second = find.byKey(const ValueKey('review-card-two'));
      expect(
        find.byKey(const ValueKey('reviews-desktop-grid')),
        findsOneWidget,
      );
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
      expect(
        tester.getTopLeft(second).dx,
        greaterThan(tester.getTopLeft(first).dx),
      );
      final search = find.byKey(const ValueKey('reviews-search-field'));
      expect(search, findsOneWidget);
      final modifier =
          Theme.of(tester.element(search)).platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      await tester.enterText(search, '第二');
      await tester.pumpAndSettle();
      expect(first, findsNothing);
      expect(second, findsOneWidget);
      tester.view.physicalSize = const Size(1120, 1600);
      await tester.pumpAndSettle();
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(ReaderFrostedSurface), findsOneWidget);
      expect(find.byKey(const ValueKey('review-detail')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('review-detail-edit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('review-editor')), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('review-content')),
        '修订后的桌面书评',
      );
      await tester.tap(find.byKey(const ValueKey('review-editor-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('review-discard-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('修订后的桌面书评'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('review-save')));
      await tester.pumpAndSettle();
      expect(store.items['two']!.content, '修订后的桌面书评');
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('未读完的书不进入待写列表或汇总', (tester) async {
    final unfinished = _book('unfinished', '尚未读完', '作者');
    final finished = _book('finished', '已经读完', '作者');
    final store = _MemoryReviewStore();
    await _pumpReviews(
      tester,
      books: [unfinished, finished],
      store: store,
      finishedIds: {finished.id},
    );

    expect(find.text('已写 0 篇 · 待写 1 本'), findsOneWidget);
    expect(
      find.byKey(ValueKey('review-pending-${unfinished.id}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('review-pending-${finished.id}')),
      findsOneWidget,
    );
    expect(store.saveCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未读完书籍的旧书评保留展示与复制且禁止编辑', (tester) async {
    final book = _book('unfinished-review', '取消读完的书', '作者');
    final review = _review(book.id, '保留下来的旧书评', rating: 5);
    final store = _MemoryReviewStore()..items[book.id] = review;
    await _pumpReviews(tester, books: [book], store: store, finishedIds: {});

    expect(find.text('已写 1 篇 · 待写 0 本 · 平均 5.0 星'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('review-card-${book.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-detail')), findsOneWidget);
    expect(find.byType(ReaderFrostedSurface), findsOneWidget);
    expect(find.text(review.content), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('review-detail-copy')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('review-detail-edit')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('review-editor')), findsNothing);
    expect(store.items[book.id], same(review));
    expect(store.saveCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('移出书架的书评继续展示，详情只读不可编辑', (tester) async {
    final removed = _book('removed-review', '已移出的书', '作者');
    final review = _review(removed.id, '删书后仍要显示的书评', rating: 4);
    final store = _MemoryReviewStore()..items[removed.id] = review;
    await _pumpReviews(
      tester,
      books: const <BookEntry>[],
      retained: [removed],
      store: store,
      finishedIds: const <String>{},
    );

    expect(find.text('已写 1 篇 · 待写 0 本 · 平均 4.0 星'), findsOneWidget);
    expect(find.byKey(ValueKey('review-card-${removed.id}')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('review-card-${removed.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-detail')), findsOneWidget);
    expect(find.text(review.content), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('review-detail-edit')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('review-editor')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('待写列表加载后取消读完，点击旧入口不能新建书评', (tester) async {
    final book = _book('cancel-pending', '待写时取消读完', '作者');
    final finishedIds = {book.id};
    final store = _MemoryReviewStore();
    await _pumpReviews(
      tester,
      books: [book],
      store: store,
      finishedIds: finishedIds,
    );

    finishedIds.clear();
    await tester.tap(find.byKey(ValueKey('review-pending-${book.id}')));
    await tester.pumpAndSettle();
    expect(find.text('标记读完后才能评分或写书评'), findsNothing);
    expect(find.byKey(const ValueKey('review-editor')), findsNothing);
    expect(store.items, isEmpty);
    expect(store.saveCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('书评详情打开后取消读完，已有编辑入口也不能修改书评', (tester) async {
    final book = _book('cancel-detail', '详情打开后取消读完', '作者');
    final review = _review(book.id, '不可覆盖的旧正文');
    final finishedIds = {book.id};
    final store = _MemoryReviewStore()..items[book.id] = review;
    await _pumpReviews(
      tester,
      books: [book],
      store: store,
      finishedIds: finishedIds,
    );
    await tester.tap(find.byKey(ValueKey('review-card-${book.id}')));
    await tester.pumpAndSettle();

    finishedIds.clear();
    await tester.tap(find.byKey(const ValueKey('review-detail-edit')));
    await tester.pumpAndSettle();
    expect(find.text('标记读完后才能评分或写书评'), findsNothing);
    expect(find.byKey(const ValueKey('review-editor')), findsNothing);
    expect(store.items[book.id], same(review));
    expect(store.saveCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小屏大字号下书评汇总、详情和编辑操作均可见', (tester) async {
    final book = _book('large-text', '一本书名较长的作品', '测试作者');
    final store = _MemoryReviewStore()
      ..items[book.id] = _review(book.id, '足够长的正文，用来验证详情和编辑页。', rating: 5);
    await _pumpReviews(
      tester,
      books: [book],
      store: store,
      size: const Size(640, 1600),
      textScale: 1.6,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('review-card-large-text')));
    await tester.pumpAndSettle();
    for (final key in ['review-detail-copy', 'review-detail-edit']) {
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(800));
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('review-detail-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-content')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('review-save'))).bottom,
      lessThanOrEqualTo(800),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('首次书评加载失败可重试，成功后恢复书目列表', (tester) async {
    final book = _book('retry-load', '加载重试', '作者');
    final store = _MemoryReviewStore()..failSnapshot = true;
    await _pumpReviews(tester, books: [book], store: store);
    expect(find.text('书评加载失败，请重试'), findsOneWidget);
    store.failSnapshot = false;
    await tester.tap(find.byKey(const ValueKey('reviews-load-retry')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('review-pending-retry-load')),
      findsOneWidget,
    );
    expect(find.text('书评加载失败，请重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑前读取失败不使用缓存，重试带入最新正文', (tester) async {
    final book = _book('retry-edit', '重试编辑', '作者');
    final store = _MemoryReviewStore();
    await _pumpReviews(tester, books: [book], store: store);
    const content = '列表加载后保存的新正文';
    store.items[book.id] = _review(book.id, content);
    store.failSnapshot = true;

    await tester.tap(find.text('写书评'));
    await tester.pumpAndSettle();
    expect(find.text('书评读取失败，请重试'), findsNothing);
    expect(find.byKey(const ValueKey('review-editor')), findsNothing);
    expect(store.saveCalls, 0);

    store.failSnapshot = false;
    await tester.tap(find.text('写书评'));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('review-content'));
    expect(tester.widget<TextField>(input).controller!.text, content);
  });

  testWidgets('读取编辑快照期间切走再返回，旧请求不弹出编辑器', (tester) async {
    final book = _book('switch-edit', '切换标签', '作者');
    final library = _FakeLibrary([book]);
    final store = _MemoryReviewStore();
    Widget tabs(bool active) => MaterialApp(
      home: IndexedStack(
        index: active ? 0 : 1,
        children: [
          ReviewsPage(library: library, reviewStore: store, active: active),
          const SizedBox.shrink(),
        ],
      ),
    );
    await tester.pumpWidget(tabs(true));
    await tester.pumpAndSettle();
    await _openReviewsTab(tester);
    final pending = Completer<void>();
    store.pendingSnapshot = pending;
    await tester.tap(find.text('写书评'));
    await tester.pump();
    expect(find.byKey(const ValueKey('review-editor')), findsNothing);

    await tester.pumpWidget(tabs(false));
    const content = '切换标签后保存的新正文';
    store.items[book.id] = _review(book.id, content);
    store.pendingSnapshot = null;
    await tester.pumpWidget(tabs(true));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-editor')), findsNothing);
    await tester.tap(find.byKey(ValueKey('review-card-${book.id}')));
    await tester.pumpAndSettle();
    expect(find.text(content), findsOneWidget);
  });

  testWidgets('等待编辑时打开另一本书评，旧编辑器不遮住全文', (tester) async {
    final first = _book('first', '待写的书', '作者');
    final second = _book('second', '已写的书', '作者');
    final store = _MemoryReviewStore()
      ..items[second.id] = _review(second.id, '另一篇书评');
    await _pumpReviews(tester, books: [first, second], store: store);
    final pending = Completer<void>();
    store.pendingSnapshot = pending;
    await tester.tap(find.text('写书评'));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('review-card-${second.id}')));
    await tester.pumpAndSettle();

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-detail')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-editor')), findsNothing);
  });

  testWidgets('读取编辑快照期间卸载页面，迟到的失败不再操作页面', (tester) async {
    final store = _MemoryReviewStore();
    await _pumpReviews(
      tester,
      books: [_book('dispose', '页面卸载', '作者')],
      store: store,
    );
    final pending = Completer<void>();
    store.pendingSnapshot = pending;
    await tester.tap(find.text('写书评'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(StateError('读取失败'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('书评保存失败保留正文和评分，重试成功后才关闭编辑器', (tester) async {
    final book = _book('retry-save', '保存重试', '作者');
    final store = _MemoryReviewStore()..failSave = true;
    await _pumpReviews(tester, books: [book], store: store);
    await tester.tap(find.text('写书评'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-rating-4')));
    await tester.enterText(
      find.byKey(const ValueKey('review-content')),
      '不能丢失的草稿',
    );
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-editor')), findsOneWidget);
    expect(find.text('不能丢失的草稿'), findsOneWidget);
    expect(find.text('保存失败，草稿已保留，请重试'), findsOneWidget);
    expect(store.items, isEmpty);

    store.failSave = false;
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-editor')), findsNothing);
    expect(store.items[book.id]!.content, '不能丢失的草稿');
    expect(store.items[book.id]!.rating, 4);
    expect(store.saveCalls, 2);
  });

  testWidgets('书评写入等待期间禁用重复保存和退出，不弹出放弃草稿确认', (tester) async {
    final book = _book('pending-save', '等待保存', '作者');
    final pending = Completer<void>();
    final store = _MemoryReviewStore()..pendingSave = pending;
    await _pumpReviews(tester, books: [book], store: store);
    await tester.tap(find.text('写书评'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('review-content')),
      '等待中的草稿',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await tester.pump();
    expect(store.saveCalls, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('review-save')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('review-editor-close')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('review-content')))
          .readOnly,
      isTrue,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const ValueKey('review-editor')), findsOneWidget);
    expect(find.text('放弃未保存的书评？'), findsNothing);
    expect(store.saveCalls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-editor')), findsNothing);
    expect(store.items[book.id]!.content, '等待中的草稿');
  });

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
    await _openReviewsTab(tester);

    expect(find.text('已写 0 篇 · 待写 1 本'), findsOneWidget);
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

    expect(find.text('已写 1 篇 · 待写 0 本 · 平均 4.0 星'), findsOneWidget);
    expect(store.items[book.id]?.rating, 4);

    await tester.tap(
      find.byKey(const ValueKey<String>('review-card-review-book')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('review-detail')), findsOneWidget);
    expect(find.text('这是一段新的书评。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('review-detail-edit')));
    await tester.pumpAndSettle();
    final delete = find.byKey(const ValueKey<String>('review-delete'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(store.items, isEmpty);
    expect(
      find.byKey(const ValueKey('review-pending-review-book')),
      findsOneWidget,
    );
  });

  testWidgets('书评详情展示完整正文并可进入编辑', (tester) async {
    final book = _book('detail-book', '详情测试书', '详情作者');
    final longReview = List<String>.filled(30, '完整书评内容').join('，');
    final store = _MemoryReviewStore()
      ..items[book.id] = _review(book.id, longReview, rating: 5);
    await _pumpReviews(tester, books: <BookEntry>[book], store: store);

    await tester.tap(
      find.byKey(const ValueKey<String>('review-card-detail-book')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('review-detail')), findsOneWidget);
    expect(find.text('详情作者'), findsWidgets);
    final detailContent = tester.widget<SelectableText>(
      find.byKey(const ValueKey<String>('review-detail-content')),
    );
    expect(detailContent.data, longReview);

    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('review-detail-copy')));
    await tester.pumpAndSettle();
    expect(clipboard, contains(book.title));
    expect(clipboard, contains(book.author));
    expect(clipboard, contains('评分：5/5'));
    expect(clipboard, endsWith(longReview));

    await tester.tap(find.byKey(const ValueKey<String>('review-detail-edit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('review-editor')), findsOneWidget);
    final editor = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('review-content')),
    );
    expect(editor.controller?.text, longReview);
  });

  testWidgets('键盘弹出时书评操作栏固定在键盘上方', (tester) async {
    final book = _book('keyboard-review', '键盘测试书', '作者');
    final store = _MemoryReviewStore()
      ..items[book.id] = _review(book.id, '需要继续编辑的书评', rating: 4);
    await _pumpReviews(tester, books: <BookEntry>[book], store: store);
    tester.view.devicePixelRatio = 3;
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('review-card-keyboard-review')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('review-detail-edit')));
    await tester.pumpAndSettle();

    final input = find.byKey(const ValueKey<String>('review-content'));
    await tester.showKeyboard(input);
    tester.view.viewInsets = const FakeViewPadding(bottom: 1200);
    await tester.pumpAndSettle();

    const keyboardTop = 400.0;
    for (final key in <String>['review-save', 'review-delete']) {
      final rect = tester.getRect(find.byKey(ValueKey<String>(key)));
      expect(rect.top, greaterThanOrEqualTo(0), reason: '$key 顶部不可见');
      expect(rect.bottom, lessThanOrEqualTo(keyboardTop), reason: '$key 被键盘遮挡');
    }
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

  testWidgets('书评编辑抽屉遮罩与下拉不丢草稿，系统返回仍请求放弃确认', (tester) async {
    final store = _MemoryReviewStore();
    await _pumpReviews(
      tester,
      books: [_book('protected-draft', '受保护的草稿', '作者')],
      store: store,
    );
    await tester.tap(find.text('写书评'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('review-content')),
      '遮罩和拖动后仍应保留',
    );
    await tester.tapAt(const Offset(8, 8));
    await tester.drag(
      find.byKey(const ValueKey('review-editor-close')),
      const Offset(0, 240),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-editor')), findsOneWidget);
    expect(find.text('遮罩和拖动后仍应保留'), findsOneWidget);
    expect(find.text('放弃未保存的书评？'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的书评？'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-discard-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('遮罩和拖动后仍应保留'), findsOneWidget);
    expect(store.items, isEmpty);
    expect(tester.takeException(), isNull);
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

    const summary = '已写 2 篇 · 待写 1 本 · 平均 4.0 星';
    expect(find.text(summary), findsOneWidget);
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
    expect(find.text(summary), findsOneWidget);

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
    expect(find.text(summary), findsOneWidget);
  });

  testWidgets('书评页直接展示已写和待写书评，不再分组筛选', (tester) async {
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

    expect(find.byKey(const ValueKey('reviews-summary')), findsOneWidget);
    for (final filter in ['all', 'reviewed', 'pending']) {
      expect(
        find.byKey(ValueKey<String>('reviews-filter-$filter')),
        findsNothing,
      );
    }
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
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('review-pending-pending-b')),
      findsOneWidget,
    );
  });

  testWidgets('书评页支持最近更新、评分和书名排序', (tester) async {
    final books = <BookEntry>[
      _book('alpha', 'Alpha', '作者甲'),
      _book('beta', 'Beta', '作者乙'),
      _book('gamma', 'Gamma', '作者丙'),
    ];
    final store = _MemoryReviewStore()
      ..items.addAll(<String, BookReview>{
        'alpha': _review(
          'alpha',
          'Alpha 书评',
          rating: 5,
          updatedAt: DateTime(2026, 1, 1),
        ),
        'beta': _review(
          'beta',
          'Beta 书评',
          rating: 2,
          updatedAt: DateTime(2026, 1, 3),
        ),
        'gamma': _review(
          'gamma',
          'Gamma 书评',
          rating: 4,
          updatedAt: DateTime(2026, 1, 2),
        ),
      });
    await _pumpReviews(tester, books: books, store: store);

    double top(String id) =>
        tester.getTopLeft(find.byKey(ValueKey<String>('review-card-$id'))).dy;

    expect(top('beta'), lessThan(top('gamma')));
    expect(top('gamma'), lessThan(top('alpha')));

    await tester.tap(find.byKey(const ValueKey<String>('reviews-sort')));
    await tester.pumpAndSettle();
    for (final sort in ['updated', 'rating', 'title']) {
      expect(find.byKey(ValueKey('reviews-sort-$sort')), findsOneWidget);
    }
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('reviews-sort-updated')))
          .selected,
      isTrue,
    );
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(top('beta'), lessThan(top('gamma')));
    await tester.tap(find.byKey(const ValueKey<String>('reviews-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('reviews-sort-rating')));
    await tester.pumpAndSettle();
    expect(top('alpha'), lessThan(top('gamma')));
    expect(top('gamma'), lessThan(top('beta')));

    await tester.tap(find.byKey(const ValueKey<String>('reviews-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('reviews-sort-title')));
    await tester.pumpAndSettle();
    expect(top('alpha'), lessThan(top('beta')));
    expect(top('beta'), lessThan(top('gamma')));
  });

  testWidgets('书评无匹配时可清除搜索', (tester) async {
    final books = <BookEntry>[
      _book('reviewed', '已写书', '作者甲'),
      _book('pending', '待写书', '作者乙'),
    ];
    final store = _MemoryReviewStore()
      ..items['reviewed'] = _review('reviewed', '一段书评');
    await _pumpReviews(tester, books: books, store: store);

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

    await tester.tap(find.text('清除搜索'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('reviews-no-results')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('reviews-search-field')),
      findsNothing,
    );
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
