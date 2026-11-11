import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_mobile/storage/db.dart';

import '../support/test_epub.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late LibraryStore library;
  late BookReviewStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('book-reviews');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => dir);
    store = library.reviewStore()!;
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('书评保存后可按书籍读取，并更新原记录', () async {
    final book = await library.importBytes(buildTestEpub(title: '书评测试书'));
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
    await store.save(book.id, rating: 3, content: '准备删除');
    await store.save(book.id, content: '   ');

    expect(await store.snapshot(), isEmpty);
  });

  test('正文按完整字符限制，超限保存不会覆盖已有书评', () async {
    final book = await library.importBytes(buildTestEpub(title: '正文长度'));
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
