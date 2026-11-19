import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late LibraryStore library;
  late BookReviewStore store;
  late DriftProgressStore progress;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('book-reviews');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => dir);
    store = library.reviewStore()!;
    progress = DriftProgressStore(db);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('内存书库默认没有已读完书籍', () async {
    final memory = LibraryStore.memory();
    await memory.importBytes(buildTestEpub(title: '内存未读完'));
    expect(await memory.finishedBookIds(), isEmpty);
  });

  for (final draft in [
    (label: '仅评分', rating: 4, content: ''),
    (label: '仅正文', rating: null, content: '尚未读完的书评'),
    (label: '评分和正文', rating: 5, content: '尚未读完的书评'),
  ]) {
    test('未读完时拒绝保存${draft.label}，标记读完后允许保存', () async {
      final book = await library.importBytes(buildTestEpub(title: draft.label));
      for (final hasProgress in [false, true]) {
        if (hasProgress) {
          await progress.save(
            book.id,
            const ReaderProgress(spineIndex: 0, pageIndex: 1),
          );
        }
        await expectLater(
          store.save(book.id, rating: draft.rating, content: draft.content),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              '拒绝原因',
              '标记读完后才能评分或写书评',
            ),
          ),
        );
        expect(await store.snapshot(), isEmpty);
        expect(await db.select(db.bookReviews).get(), isEmpty);
        expect(await library.finishedBookIds(), isEmpty);
      }

      await progress.save(
        book.id,
        const ReaderProgress(spineIndex: 0, pageIndex: 1, finished: true),
      );
      await store.save(book.id, rating: draft.rating, content: draft.content);
      final saved = (await store.snapshot())[book.id]!;
      expect(saved.rating, draft.rating);
      expect(saved.content, draft.content);
      expect(await library.finishedBookIds(), {book.id});
    });
  }

  test('取消读完保留旧书评且拒绝修改，重新标记后可编辑', () async {
    final book = await library.importBytes(buildTestEpub(title: '取消读完'));
    const finished = ReaderProgress(
      spineIndex: 0,
      pageIndex: 2,
      finished: true,
    );
    await progress.save(book.id, finished);
    await store.save(book.id, rating: 5, content: '不可丢失的旧书评');
    final original = (await db.select(db.bookReviews).get()).single;

    await progress.save(book.id, finished.withFinished(false));
    expect(await library.finishedBookIds(), isEmpty);
    final retained = (await store.snapshot())[book.id]!;
    expect(retained.rating, 5);
    expect(retained.content, '不可丢失的旧书评');
    for (final draft in [
      (rating: 1, content: ''),
      (rating: null, content: '不应覆盖的正文'),
      (rating: 2, content: '不应覆盖的正文'),
    ]) {
      await expectLater(
        store.save(book.id, rating: draft.rating, content: draft.content),
        throwsA(isA<FormatException>()),
      );
      expect((await db.select(db.bookReviews).get()).single, original);
    }

    await progress.save(book.id, finished);
    await store.save(book.id, rating: 4, content: '重新读完后的书评');
    final updated = (await store.snapshot())[book.id]!;
    expect(updated.rating, 4);
    expect(updated.content, '重新读完后的书评');
    expect(updated.createdAt, retained.createdAt);
  });

  test('书评保存后可按书籍读取，并更新原记录', () async {
    final book = await library.importBytes(buildTestEpub(title: '书评测试书'));
    await progress.save(
      book.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0, finished: true),
    );
    await store.save(book.id, rating: 4, content: '  值得重读的故事。  ');

    var review = (await store.snapshot())[book.id]!;
    expect(review.rating, 4);
    expect(review.content, '值得重读的故事。');
    final createdAt = review.createdAt;

    await store.save(book.id, rating: 5, content: '再读更有味道。');
    review = (await store.snapshot())[book.id]!;
    expect(review.rating, 5);
    expect(review.content, '再读更有味道。');
    expect(review.createdAt, createdAt);
    expect((await db.select(db.bookReviews).get()), hasLength(1));
  });

  test('评分与正文都为空时删除书评', () async {
    final book = await library.importBytes(buildTestEpub(title: '删除书评'));
    await progress.save(
      book.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0, finished: true),
    );
    await store.save(book.id, rating: 3, content: '准备删除');
    await store.save(book.id, content: '   ');

    expect(await store.snapshot(), isEmpty);
  });

  test('正文按完整字符限制，超限保存不会覆盖已有书评', () async {
    final book = await library.importBytes(buildTestEpub(title: '正文长度'));
    await progress.save(
      book.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0, finished: true),
    );
    final content = List.filled(BookReview.maxContentLength, '👨‍👩‍👧').join();
    await store.save(book.id, rating: 4, content: content);
    expect((await store.snapshot())[book.id]!.content, content);

    await expectLater(
      store.save(book.id, rating: 5, content: '$content字'),
      throwsA(isA<FormatException>()),
    );
    final unchanged = (await store.snapshot())[book.id]!;
    expect(unchanged.content, content);
    expect(unchanged.rating, 4);
  });

  test('已移除的书籍不能静默保存书评，原书评仍可随重新导入恢复', () async {
    final book = await library.importBytes(buildTestEpub(title: '移除后保存'));
    await progress.save(
      book.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0, finished: true),
    );
    await store.save(book.id, content: '原来的书评');
    await library.remove(book.id);
    await expectLater(
      store.save(book.id, content: '不应保存的修改'),
      throwsA(isA<FormatException>()),
    );
    expect(await store.snapshot(), isEmpty);
    await library.importBytes(buildTestEpub(title: '移除后保存'));
    expect((await store.snapshot())[book.id]!.content, '原来的书评');
  });

  test('删书后隐藏书评，重新导入同一本书后恢复', () async {
    final book = await library.importBytes(buildTestEpub(title: '级联书评'));
    await progress.save(
      book.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0, finished: true),
    );
    await store.save(book.id, rating: 5, content: '会随书删除');

    await library.remove(book.id);

    expect(await db.select(db.bookReviews).get(), hasLength(1));
    expect(await store.snapshot(), isEmpty);

    final restored = await library.importBytes(buildTestEpub(title: '级联书评'));
    expect(restored.id, book.id);
    final review = (await store.snapshot())[book.id]!;
    expect(review.rating, 5);
    expect(review.content, '会随书删除');
  });
}
