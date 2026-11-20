import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_detail_page.dart';
import 'package:reader_mobile/home/reviews_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

class _FakeCoverLibrary extends LibraryStore {
  _FakeCoverLibrary() : super.memory();

  bool replaced = false;

  @override
  Future<BookEntry> replaceCover(
    String id,
    Uint8List bytes, {
    required String extension,
  }) async {
    replaced = true;
    return (await bookById(id))!;
  }
}

class _FailingReviewStore implements BookReviewStore {
  _FailingReviewStore(this.delegate);

  final BookReviewStore delegate;
  bool failSave = true;

  @override
  Future<Map<String, BookReview>> snapshot() => delegate.snapshot();

  @override
  Future<void> remove(String bookId) => delegate.remove(bookId);

  @override
  Future<void> save(
    String bookId, {
    int? rating,
    required String content,
  }) async {
    await delegate.save(bookId, rating: rating, content: content);
    if (failSave) throw StateError('写入失败');
  }
}

void main() {
  late Directory dir;
  late AppDatabase db;
  late LibraryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('book-detail-page');
    db = AppDatabase(NativeDatabase.memory());
    store = LibraryStore(database: db, directoryProvider: () async => dir);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('详情页隐藏图书信息与导入报告，保留阅读记录', (tester) async {
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await store.importBytes(buildWarningEpub());
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(entry: entry, library: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('图书信息'), findsNothing);
    expect(find.text('章节'), findsNothing);
    expect(find.text('导入'), findsNothing);
    expect(find.text('最近阅读'), findsNothing);
    expect(find.text('可读性'), findsNothing);
    expect(find.text('导入报告'), findsNothing);
    expect(find.text('E_MANIFEST_MEDIA_TYPE_INFERRED'), findsNothing);
    expect(find.text('阅读记录'), findsOneWidget);
  });

  testWidgets('读完信息支持长书评，保存失败保留草稿且不提前标记读完', (tester) async {
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await store.importBytes(buildTestEpub(title: '读完保存重试'));
    });
    final reviews = _FailingReviewStore(store.reviewStore()!);
    final progress = DriftProgressStore(db);
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(
          entry: entry,
          library: store,
          progressStore: progress,
          reviewStore: reviews,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mark = find.byKey(const ValueKey('book-detail-mark-finished'));
    await tester.scrollUntilVisible(
      mark,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(mark);
    await tester.pumpAndSettle();
    final content = List.filled(1500, '字').join();
    await tester.tap(find.byKey(const ValueKey('book-detail-finish-rating-5')));
    await tester.enterText(
      find.byKey(const ValueKey('book-detail-finish-review')),
      content,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('book-detail-finish-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('book-detail-finish-sheet')),
      findsOneWidget,
    );
    expect(find.text('保存失败，草稿已保留，请重试'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('book-detail-finish-review')),
          )
          .controller!
          .text,
      content,
    );
    expect(await progress.load(entry.id), isNull);
    expect(await reviews.snapshot(), isEmpty);
    expect(await store.finishedBookIds(), isEmpty);
    reviews.failSave = false;
    await tester.tap(find.byKey(const ValueKey('book-detail-finish-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('book-detail-finish-sheet')),
      findsNothing,
    );
    expect((await progress.load(entry.id))!.finished, isTrue);
    expect(await store.finishedBookIds(), {entry.id});
    final saved = (await reviews.snapshot())[entry.id]!;
    expect(saved.rating, 5);
    expect(saved.content, content);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情页可编辑资料、新建标签并切换标签', (tester) async {
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await store.importBytes(
        buildTestEpub(title: '旧书名', identifier: 'detail-edit'),
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(entry: entry, library: store),
      ),
    );
    await tester.pumpAndSettle();

    final coverRect = tester.getRect(
      find.byKey(const ValueKey<String>('book-detail-page-cover')),
    );
    expect(
      tester
          .getRect(
            find.byKey(const ValueKey<String>('book-detail-title-field')),
          )
          .left,
      greaterThanOrEqualTo(coverRect.right),
    );
    expect(
      tester
          .getRect(
            find.byKey(const ValueKey<String>('book-detail-author-field')),
          )
          .left,
      greaterThanOrEqualTo(coverRect.right),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('book-detail-title-field')),
      '新书名',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('book-detail-author-field')),
      '新作者',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('book-detail-description-field')),
      '新的简介',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('book-detail-save')));
    await tester.pumpAndSettle();

    late BookEntry updated;
    await tester.runAsync(() async {
      updated = (await store.bookById(entry.id))!;
    });
    expect(updated.title, '新书名');
    expect(updated.author, '新作者');
    expect(updated.description, '新的简介');

    final tagField = find.byKey(
      const ValueKey<String>('book-detail-new-tag-field'),
    );
    await tester.scrollUntilVisible(
      tagField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(tagField, '科幻');
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('book-detail-add-tag')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('book-detail-add-tag')));
    await tester.pumpAndSettle();

    late List<BookTag> tags;
    await tester.runAsync(() async {
      tags = await store.bookTags(entry.id);
    });
    expect(tags.single.name, '科幻');
    final chip = find.byKey(
      ValueKey<String>('book-detail-tag-${tags.single.id}'),
    );
    expect(chip, findsOneWidget);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      tags = await store.bookTags(entry.id);
    });
    expect(tags, isEmpty, reason: '再次点击标签应取消关联');
  });

  testWidgets('详情页点击封面调用存储并完成更新', (tester) async {
    final coverStore = _FakeCoverLibrary();
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await coverStore.importBytes(
        buildTestEpub(title: '换封面', identifier: 'detail-cover'),
      );
    });
    final png = Uint8List.fromList(<int>[1, 2, 3]);

    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(
          entry: entry,
          library: coverStore,
          pickCover: () async => (bytes: png, extension: 'png'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('book-detail-page-cover')),
    );
    await tester.pumpAndSettle();

    expect(coverStore.replaced, isTrue);
    expect(find.text('封面已更新'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情页按书汇总阅读时长、次数和翻页', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    late BookEntry entry;
    late BookEntry other;
    await tester.runAsync(() async {
      entry = await store.importBytes(
        buildTestEpub(title: '记录书', identifier: 'detail-stats'),
      );
      other = await store.importBytes(
        buildTestEpub(title: '另一本', identifier: 'detail-stats-other'),
      );
      final sessions = store.readingSessionStore()!;
      await sessions.add(
        bookId: entry.id,
        startedAt: yesterday.add(const Duration(hours: 20)),
        endedAt: yesterday.add(const Duration(hours: 21)),
        pageTurns: 5,
        charactersRead: 100,
      );
      await sessions.add(
        bookId: entry.id,
        startedAt: yesterday.add(const Duration(hours: 23, minutes: 30)),
        endedAt: today.add(const Duration(minutes: 30)),
        pageTurns: 3,
        charactersRead: 80,
      );
      await sessions.add(
        bookId: entry.id,
        startedAt: today.add(const Duration(hours: 9)),
        endedAt: today.add(const Duration(hours: 9, minutes: 10)),
        pageTurns: 2,
        charactersRead: 40,
      );
      await sessions.add(
        bookId: other.id,
        startedAt: today.add(const Duration(hours: 10)),
        endedAt: today.add(const Duration(hours: 11)),
        pageTurns: 99,
        charactersRead: 999,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(entry: entry, library: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('book-detail-total-duration')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    String valueOf(String key) =>
        tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

    expect(valueOf('book-detail-total-duration'), '2 小时 10 分');
    expect(valueOf('book-detail-session-count'), '3');
    expect(valueOf('book-detail-reading-days'), '2');
    expect(valueOf('book-detail-page-turns'), '10');
    expect(valueOf('book-detail-characters-read'), '220');

    final todayKey = _dateKey(today);
    final yesterdayKey = _dateKey(yesterday);
    await tester.scrollUntilVisible(
      find.byKey(ValueKey<String>('book-detail-daily-$yesterdayKey')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      valueOf('book-detail-daily-duration-$todayKey'),
      '40 分钟',
      reason: '跨午夜会话的今日部分应计入今日时长',
    );
    expect(valueOf('book-detail-daily-detail-$todayKey'), '1 次 · 翻页 2 · 40 字');
    expect(valueOf('book-detail-daily-duration-$yesterdayKey'), '1 小时 30 分');
    expect(
      valueOf('book-detail-daily-detail-$yesterdayKey'),
      '2 次 · 翻页 8 · 180 字',
    );
  });

  testWidgets('详情页阅读记录不汇总低于五分钟的会话', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await store.importBytes(
        buildTestEpub(title: '短会话书', identifier: 'detail-short-session'),
      );
      final sessions = store.readingSessionStore()!;
      await sessions.add(
        bookId: entry.id,
        startedAt: today.add(const Duration(hours: 9)),
        endedAt: today.add(const Duration(hours: 9, minutes: 4, seconds: 59)),
        pageTurns: 9,
        charactersRead: 900,
      );
      await sessions.add(
        bookId: entry.id,
        startedAt: today.add(const Duration(hours: 10)),
        endedAt: today.add(const Duration(hours: 10, minutes: 5)),
        pageTurns: 1,
        charactersRead: 10,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(entry: entry, library: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('book-detail-total-duration')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    String valueOf(String key) =>
        tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

    expect(valueOf('book-detail-total-duration'), '5 分钟');
    expect(valueOf('book-detail-session-count'), '1');
    expect(valueOf('book-detail-page-turns'), '1');
    expect(valueOf('book-detail-characters-read'), '10');
  });

  testWidgets('详情页可标记读完并保存评分与书评', (tester) async {
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await store.importBytes(
        buildTestEpub(title: '读完标记', identifier: 'detail-finished'),
      );
    });
    final progress = DriftProgressStore(db);

    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(
          entry: entry,
          library: store,
          progressStore: progress,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _saveDetailReview(tester, rating: 5, content: '值得反复阅读。');

    late ReaderProgress? savedProgress;
    late Map<String, BookReview> reviews;
    await tester.runAsync(() async {
      savedProgress = await progress.load(entry.id);
      reviews = await store.reviewStore()!.snapshot();
    });
    expect(savedProgress?.finished, isTrue);
    expect(await store.finishedBookIds(), {entry.id});
    expect(reviews[entry.id]?.rating, 5);
    expect(reviews[entry.id]?.content, '值得反复阅读。');
    expect(find.text('已读完'), findsOneWidget);
    expect(find.text('值得反复阅读。'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('book-detail-edit-finished')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('book-detail-edit-finished')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('book-detail-finish-review')),
          )
          .controller
          ?.text,
      '值得反复阅读。',
    );
  });

  testWidgets('仅标记读完不保存评分或草稿，随后可到书评页补写', (tester) async {
    final progress = DriftProgressStore(db);
    final entry = (await tester.runAsync(() async {
      final book = await store.importBytes(buildTestEpub(title: '稍后写书评'));
      await progress.save(
        book.id,
        const ReaderProgress(spineIndex: 0, pageIndex: 2, readingPercent: 0.4),
      );
      return book;
    }))!;
    final before = (await progress.load(entry.id))!;
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(
          entry: entry,
          library: store,
          progressStore: progress,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mark = find.byKey(const ValueKey('book-detail-mark-finished'));
    await tester.scrollUntilVisible(
      mark,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(mark);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('book-detail-finish-rating-5')));
    await tester.enterText(
      find.byKey(const ValueKey('book-detail-finish-review')),
      '暂不提交的草稿',
    );
    final onlyFinish = find.byKey(const ValueKey('finish-book-only'));
    expect(find.widgetWithText(OutlinedButton, '仅标记读完'), findsOneWidget);
    await tester.tap(onlyFinish);
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的书评？'), findsOneWidget);
    expect(await progress.load(entry.id), before);
    expect(await store.reviewStore()!.snapshot(), isEmpty);
    await tester.tap(find.widgetWithText(TextButton, '继续编辑'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('book-detail-finish-review')),
          )
          .controller!
          .text,
      '暂不提交的草稿',
    );
    await tester.tap(onlyFinish);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '放弃修改'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('book-detail-finish-sheet')),
      findsNothing,
    );
    expect((await progress.load(entry.id))!.withFinished(false), before);
    expect(await store.finishedBookIds(), {entry.id});
    expect(await store.reviewStore()!.snapshot(), isEmpty);

    await tester.pumpWidget(MaterialApp(home: ReviewsPage(library: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reviews-tab')));
    await tester.pumpAndSettle();
    expect(find.text('已写 0 篇 · 待写 1 本'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('review-pending-${entry.id}')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('review-content')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('review-rating-4')));
    await tester.enterText(
      find.byKey(const ValueKey('review-content')),
      '读完后补写的书评',
    );
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await tester.pumpAndSettle();
    final saved = (await store.reviewStore()!.snapshot())[entry.id]!;
    expect(saved.rating, 4);
    expect(saved.content, '读完后补写的书评');
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情取消读完保留原评分和书评，书评页禁止编辑', (tester) async {
    final entry = (await tester.runAsync(
      () => store.importBytes(buildTestEpub(title: '取消读完后只读')),
    ))!;
    final progress = DriftProgressStore(db);
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(
          entry: entry,
          library: store,
          progressStore: progress,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _saveDetailReview(tester, rating: 5, content: '保留评分和正文');
    final originalProgress = (await progress.load(entry.id))!;
    final originalReview = (await db.select(db.bookReviews).get()).single;
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    final unmark = find.byKey(const ValueKey('book-detail-unmark-finished'));
    await tester.ensureVisible(unmark);
    await tester.pumpAndSettle();
    await tester.tap(unmark);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('book-detail-unmark-confirm')));
    await tester.pumpAndSettle();
    expect(await progress.load(entry.id), originalProgress.withFinished(false));
    expect(await store.finishedBookIds(), isEmpty);
    expect((await db.select(db.bookReviews).get()).single, originalReview);
    expect(
      find.byKey(const ValueKey('book-detail-edit-finished')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('book-detail-mark-finished')),
      findsOneWidget,
    );

    await tester.pumpWidget(MaterialApp(home: ReviewsPage(library: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reviews-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('review-pending-${entry.id}')), findsNothing);
    await tester.tap(find.byKey(ValueKey('review-card-${entry.id}')));
    await tester.pumpAndSettle();
    expect(find.text('保留评分和正文'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('review-detail-edit')),
          )
          .onPressed,
      isNull,
    );
    expect((await db.select(db.bookReviews).get()).single, originalReview);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情保存书评后切回已加载的书评页，只改星级保留最新正文', (tester) async {
    final entry = (await tester.runAsync(
      () => store.importBytes(buildTestEpub(title: '跨页书评')),
    ))!;
    final progress = DriftProgressStore(db);
    Widget tabs(bool reviewsActive) => MaterialApp(
      home: IndexedStack(
        index: reviewsActive ? 0 : 1,
        children: [
          ReviewsPage(library: store, active: reviewsActive),
          BookDetailPage(entry: entry, library: store, progressStore: progress),
        ],
      ),
    );

    await tester.pumpWidget(tabs(true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reviews-tab')));
    await tester.pumpAndSettle();
    expect(find.text('写书评'), findsNothing);
    expect(find.byKey(ValueKey('review-pending-${entry.id}')), findsNothing);

    await tester.pumpWidget(tabs(false));
    await tester.pumpAndSettle();
    const content = '详情页写入的正文';
    await _saveDetailReview(tester, rating: 5, content: content);
    final reviews = store.reviewStore()!;
    expect((await reviews.snapshot())[entry.id]?.content, content);

    await tester.pumpWidget(tabs(true));
    await tester.pumpAndSettle();
    expect(find.text('已写 1'), findsOneWidget);
    expect(find.text('写书评'), findsNothing);
    await tester.tap(find.byKey(ValueKey('review-card-${entry.id}')));
    await tester.pumpAndSettle();
    expect(find.text(content), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-detail-edit')));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('review-content'));
    expect(tester.widget<TextField>(input).controller!.text, content);
    await tester.tap(find.byKey(const ValueKey('review-rating-4')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await tester.pumpAndSettle();
    final saved = (await reviews.snapshot())[entry.id]!;
    expect(saved.rating, 4);
    expect(saved.content, content);
  });
}

Future<void> _saveDetailReview(
  WidgetTester tester, {
  required int rating,
  required String content,
}) async {
  final mark = find.byKey(const ValueKey('book-detail-mark-finished'));
  await tester.scrollUntilVisible(
    mark,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(mark);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('book-detail-finish-rating-$rating')));
  await tester.enterText(
    find.byKey(const ValueKey('book-detail-finish-review')),
    content,
  );
  await tester.tap(find.byKey(const ValueKey('book-detail-finish-save')));
  await tester.pumpAndSettle();
}

String _dateKey(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
