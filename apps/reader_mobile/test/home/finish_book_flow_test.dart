import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reviews_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/book_opener.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/rating/reader_rating.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

class _FailingReviews implements BookReviewStore {
  _FailingReviews(this.delegate);

  final BookReviewStore delegate;
  bool fail = true;

  @override
  Future<Map<String, BookReview>> snapshot() => delegate.snapshot();

  @override
  Future<void> remove(String bookId) => delegate.remove(bookId);

  @override
  Future<void> save(
    String bookId, {
    num? rating,
    required String content,
  }) async {
    if (fail) throw const FormatException('书评写入失败，请重试');
    await delegate.save(bookId, rating: rating, content: content);
  }
}

Future<ReaderSession> _openBook(
  WidgetTester tester,
  LibraryStore library,
  DriftProgressStore progress, {
  BookReviewStore? reviews,
  BookReviewLoader? loadReview,
  BookReviewSaver? saveReview,
}) async {
  final book = (await tester.runAsync(
    () => library.importBytes(buildTestEpub(title: '读完流程验收')),
  ))!;
  final opener = BookOpener(
    library: library,
    progressStore: progress,
    loadFinishedReview: loadReview,
    saveFinishedReview: saveReview,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => reviews == null
                    ? opener.open(context, book)
                    : Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => EpubReaderPage(
                            sourcePath: book.filePath,
                            book: book,
                            bookId: book.id,
                            bookTitle: book.title,
                            contentRevision: book.contentRevision,
                            store: progress,
                            reviewStore: reviews,
                          ),
                        ),
                      ),
                child: const Text('打开验收书'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ReviewsPage(library: library),
                  ),
                ),
                child: const Text('查看书评'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开验收书'));
  await pumpReaderUntil(tester, find.byType(ReaderView));
  await tester.pumpAndSettle();
  return tester.widget<PageTurnView>(find.byType(PageTurnView)).session;
}

Future<void> _openFinish(WidgetTester tester) async {
  final rect = tester.getRect(find.byType(ReaderView));
  await tester.tapAt(Offset(rect.right - 8, rect.center.dy));
  await pumpReaderUntil(tester, _key('reader-finish-page'));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, String key) async {
  await tester.tap(_key(key));
  await pumpReaderUntilComplete(
    tester,
    () => _key('reader-finish-page').evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
}

void main() {
  late Directory directory;
  late AppDatabase database;
  late LibraryStore library;
  late DriftProgressStore progress;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('finish-book-flow');
    database = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(
      database: database,
      directoryProvider: () async => directory,
    );
    progress = DriftProgressStore(database);
  });

  tearDown(() async {
    await database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('读完页显示已有阅微半星评价，修改后同时保存本地和云端', (tester) async {
    num? savedRating;
    String? savedContent;
    final session = await _openBook(
      tester,
      library,
      progress,
      loadReview: (id) async => BookReview(
        bookId: id,
        rating: 3.5,
        content: '已有阅微书评',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      saveReview: (id, rating, content) async {
        savedRating = rating;
        savedContent = content;
      },
    );
    await _openFinish(tester);
    expect(
      tester.widget<ReaderRatingPicker>(find.byType(ReaderRatingPicker)).rating,
      3.5,
    );
    expect(find.text('已有阅微书评'), findsOneWidget);
    await tester.tap(_key('book-detail-finish-rating-half-9'));
    await tester.pump();
    await _save(tester, 'book-detail-finish-save');
    expect(savedRating, 4.5);
    expect(savedContent, '已有阅微书评');
    expect(session.progress!.finished, isTrue);
    final review = (await tester.runAsync(
      () => library.reviewStore()!.snapshot(),
    ))![session.bookId]!;
    expect(review.rating, 4.5);
    expect(review.content, '已有阅微书评');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('末页再翻打开读完页，取消和回翻不修改正文位置或读完状态', (tester) async {
    final session = await _openBook(tester, library, progress);
    expect(session.atBookEnd, isTrue);
    final before = session.progress!;
    expect(before.finished, isFalse);
    await _openFinish(tester);
    expect(session.progress!.finished, isFalse);
    expect(find.text('评分（可选）'), findsOneWidget);
    await tester.tap(find.byTooltip('返回正文末页'));
    await tester.pumpAndSettle();
    expect(session.progress, before);
    await _openFinish(tester);
    await tester.drag(find.text('标记读完'), const Offset(280, 0));
    await tester.pumpAndSettle();
    expect(_key('reader-finish-page'), findsNothing);
    expect(session.progress, before);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('小屏大字号和键盘下保留操作入口，退出确认不提前标记读完', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final session = await _openBook(tester, library, progress);
    await _openFinish(tester);
    await tester.enterText(_key('book-detail-finish-review'), '尚未保存的书评');
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_key('finish-book-only').hitTestable(), findsOneWidget);
    expect(_key('book-detail-finish-save').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('返回正文末页'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的书评？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(session.progress!.finished, isFalse);
    expect(await library.reviewStore()!.snapshot(), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('仅标记读完后退出阅读，书评页可补评分和书评', (tester) async {
    final session = await _openBook(tester, library, progress);
    final before = session.progress!;
    final id = session.bookId;
    await _openFinish(tester);
    await _save(tester, 'finish-book-only');
    expect(session.progress, before.withFinished(true));
    expect(await progress.load(id), before.withFinished(true));
    expect(await library.reviewStore()!.snapshot(), isEmpty);
    Navigator.of(tester.element(find.byType(ReaderView))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看书评'));
    await tester.pumpAndSettle();
    await tester.tap(_key('reviews-tab'));
    await tester.pumpAndSettle();
    expect(_key('review-pending-$id'), findsOneWidget);
    await tester.tap(_key('review-pending-$id'));
    await tester.pumpAndSettle();
    await tester.tap(_key('review-rating-4'));
    await tester.enterText(_key('review-content'), '之后补写的书评。');
    await tester.tap(_key('review-save'));
    await tester.pumpAndSettle();
    final review = (await library.reviewStore()!.snapshot())[id]!;
    expect(review.rating, 4);
    expect(review.content, '之后补写的书评。');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('书末页同时保存评分和书评，重开带入已读完信息', (tester) async {
    final session = await _openBook(tester, library, progress);
    final before = session.progress!;
    final id = session.bookId;
    await _openFinish(tester);
    await tester.tap(_key('book-detail-finish-rating-5'));
    await tester.enterText(_key('book-detail-finish-review'), '读完后值得记录。');
    await _save(tester, 'book-detail-finish-save');
    expect(session.progress, before.withFinished(true));
    final review = (await library.reviewStore()!.snapshot())[id]!;
    expect(review.rating, 5);
    expect(review.content, '读完后值得记录。');
    await _openFinish(tester);
    expect(find.text('已读完'), findsOneWidget);
    expect(_key('finish-book-only'), findsNothing);
    expect(
      tester
          .widget<TextField>(_key('book-detail-finish-review'))
          .controller!
          .text,
      review.content,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('书评写入失败整体回滚读完标记，草稿保留并支持重试', (tester) async {
    final reviews = _FailingReviews(library.reviewStore()!);
    final session = await _openBook(
      tester,
      library,
      progress,
      reviews: reviews,
    );
    final id = session.bookId;
    await _openFinish(tester);
    await tester.tap(_key('book-detail-finish-rating-3'));
    await tester.enterText(_key('book-detail-finish-review'), '失败后保留的草稿');
    await tester.tap(_key('book-detail-finish-save'));
    await tester.pumpAndSettle();
    expect(find.text('书评写入失败，请重试'), findsOneWidget);
    expect(session.progress!.finished, isFalse);
    expect((await progress.load(id))?.finished ?? false, isFalse);
    expect(await library.reviewStore()!.snapshot(), isEmpty);
    expect(
      tester
          .widget<TextField>(_key('book-detail-finish-review'))
          .controller!
          .text,
      '失败后保留的草稿',
    );
    reviews.fail = false;
    await _save(tester, 'book-detail-finish-save');
    expect((await progress.load(id))!.finished, isTrue);
    expect((await library.reviewStore()!.snapshot())[id]!.rating, 3);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
