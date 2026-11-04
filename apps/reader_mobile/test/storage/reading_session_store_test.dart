import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';

void main() {
  late AppDatabase db;
  late DriftReadingSessionStore store;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.warmUp();
    store = DriftReadingSessionStore(db);
  });

  tearDown(() => db.close());

  test('阅读会话按时落库并映射书籍 uuid', () async {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            uuid: 'book-a',
            title: '阅读统计',
            contentDir: 'books/book-a/content',
            createdAt: 1,
          ),
        );
    final start = DateTime(2026, 11, 3, 8);
    await store.add(
      bookId: 'book-a',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 12)),
      pageTurns: 9,
      charactersRead: 1680,
    );

    final items = await store.list();
    expect(items, hasLength(1));
    expect(items.single.bookId, 'book-a');
    expect(items.single.startedAt, start);
    expect(items.single.duration, const Duration(minutes: 12));
    expect(items.single.pageTurns, 9);
    expect(items.single.charactersRead, 1680);
  });

  test('未知书籍或非正时长不写入噪声记录', () async {
    final start = DateTime(2026, 11, 3, 8);
    await store.add(
      bookId: 'missing',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 1)),
    );
    await store.add(bookId: 'missing', startedAt: start, endedAt: start);

    expect(await store.list(), isEmpty);
    expect(await db.select(db.readingSessions).get(), isEmpty);
  });
}
