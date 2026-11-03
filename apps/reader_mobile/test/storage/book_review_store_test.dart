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
