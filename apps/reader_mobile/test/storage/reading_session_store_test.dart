import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reading_insights.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

Future<Map<String, Object>> _savedReadingData(AppDatabase db) async => {
  'books': [for (final row in await db.select(db.books).get()) row.toJson()],
  'sessions': [
    for (final row in await db.select(db.readingSessions).get()) row.toJson(),
  ],
  'progress': [
    for (final row in await db.select(db.readingProgress).get()) row.toJson(),
  ],
  'annotations': [
    for (final row in await db.select(db.annotations).get()) row.toJson(),
  ],
};

Future<void> _addNotes(LibraryStore library, String bookId) async {
  final annotations = library.annotationStore(bookId)!;
  await annotations.add(
    type: ReaderAnnotationType.mark,
    startCfi: 'epubcfi(/6/2!/4/2/1:1)',
    endCfi: 'epubcfi(/6/2!/4/2/1:3)',
    quote: '保留划线',
    color: 0xFFFFEB3B,
  );
  await annotations.add(
    type: ReaderAnnotationType.thought,
    startCfi: 'epubcfi(/6/2!/4/2/1:4)',
    endCfi: 'epubcfi(/6/2!/4/2/1:6)',
    quote: '保留笔记',
    note: '统计更新后仍需保留的想法',
  );
  await library
      .bookmarkStore(bookId)!
      .add(cfi: 'epubcfi(/6/2!/4/2/1:8)', spineIndex: 0, label: '保留的书签');
}

Future<int> _insertSessionBook(AppDatabase db, String uuid) => db
    .into(db.books)
    .insert(
      BooksCompanion.insert(
        uuid: uuid,
        contentRevision: 'session-content',
        title: '会话绑定测试书',
        contentDir: 'books/$uuid/content',
        createdAt: 1,
      ),
    );

Future<void> _rekeySessionBook(
  AppDatabase db,
  int bookId,
  String oldId,
  String newId,
) => db.transaction(() async {
  await (db.update(db.books)..where((table) => table.id.equals(bookId))).write(
    BooksCompanion(uuid: Value(newId)),
  );
  await db
      .into(db.bookIdAliases)
      .insert(BookIdAliasesCompanion.insert(aliasId: oldId, bookId: bookId));
});

void main() {
  late AppDatabase db;
  late DriftReadingSessionStore store;
  Directory? persistedDirectory;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.warmUp();
    store = DriftReadingSessionStore(db);
  });

  tearDown(() async {
    await db.close();
    persistedDirectory?.deleteSync(recursive: true);
    persistedDirectory = null;
  });

  test('阅读会话按时落库并映射书籍 uuid', () async {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            uuid: 'book-a',
            contentRevision: 'test-content',
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
    expect(items.single.bookTitle, '阅读统计');
    expect(items.single.startedAt, start);
    expect(items.single.duration, const Duration(minutes: 12));
    expect(items.single.pageTurns, 9);
    expect(items.single.charactersRead, 1680);
  });

  test('移出书架的历史会话仍参与统计，保留原时长和计数并按时间排序', () async {
    final currentId = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            uuid: 'current',
            contentRevision: 'current-content',
            title: '当前书籍',
            contentDir: 'books/current/content',
            createdAt: 1,
          ),
        );
    final removedId = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            uuid: 'removed',
            contentRevision: 'removed-content',
            title: '历史书籍',
            contentDir: 'books/removed/content',
            createdAt: 1,
            deletedAt: const Value(2),
          ),
        );
    final start = DateTime(2026, 11, 3, 8);
    for (final record in [(currentId, 1), (removedId, 0)]) {
      await db
          .into(db.readingSessions)
          .insert(
            ReadingSessionsCompanion.insert(
              bookId: record.$1,
              startedAt: start
                  .add(Duration(days: record.$2))
                  .millisecondsSinceEpoch,
              endedAt: start
                  .add(Duration(days: record.$2, hours: 1))
                  .millisecondsSinceEpoch,
              durationMs: const Duration(minutes: 20).inMilliseconds,
              pageTurns: const Value(7),
              charactersRead: const Value(1234),
            ),
          );
    }
    final before = await _savedReadingData(db);
    final sessions = await store.list();
    expect(sessions.map((session) => session.bookId), ['removed', 'current']);
    expect(sessions.map((session) => session.bookTitle), ['历史书籍', '当前书籍']);
    final insights = ReadingInsights(sessions, now: start);
    expect(insights.totalReading, const Duration(minutes: 40));
    expect(insights.pageTurns, 14);
    expect(insights.charactersRead, 2468);
    expect(await _savedReadingData(db), before, reason: '读取历史统计不能改写原记录');
  });

  test('数据库重开后读取统计保留书籍、进度、笔记、批注与书签', () async {
    await db.close();
    persistedDirectory = Directory.systemTemp.createTempSync('reading-data');
    final file = File('${persistedDirectory!.path}/reader.sqlite');
    db = AppDatabase(NativeDatabase(file));
    LibraryStore library() => LibraryStore(
      database: db,
      directoryProvider: () async => persistedDirectory!,
    );
    final firstLibrary = library();
    final book = await firstLibrary.importBytes(buildTestEpub(title: '当前书籍'));
    final archived = await firstLibrary.importBytes(
      buildTestEpub(title: '历史书籍'),
    );
    final progressStore = DriftProgressStore(db);
    for (final entry in [book, archived]) {
      await progressStore.save(
        entry.id,
        ReaderProgress(
          spineIndex: 0,
          pageIndex: 2,
          cfi: 'epubcfi(/6/2!/4/2/1:3)',
          contentRevision: entry.contentRevision,
          readingPercent: 0.25,
          scrollOffset: 18,
        ),
      );
    }
    await _addNotes(firstLibrary, book.id);
    final savedProgress = await progressStore.load(book.id);
    final start = DateTime(2026, 11, 14, 9);
    final sessions = firstLibrary.readingSessionStore()!;
    await sessions.add(
      bookId: book.id,
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 5)),
      pageTurns: 2,
      charactersRead: 60,
    );
    await sessions.add(
      bookId: archived.id,
      startedAt: start.subtract(const Duration(days: 1)),
      endedAt: start
          .subtract(const Duration(days: 1))
          .add(const Duration(minutes: 20)),
      pageTurns: 8,
      charactersRead: 400,
    );
    await firstLibrary.remove(archived.id);
    final before = await _savedReadingData(db);
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    final reopenedLibrary = library();
    final insights = ReadingInsights(
      await reopenedLibrary.readingSessionStore()!.list(),
      now: start,
    );
    expect(insights.totalReading, const Duration(minutes: 25));
    expect(insights.todayReading, const Duration(minutes: 5));
    expect(insights.pageTurns, 10);
    expect(insights.charactersRead, 460);
    expect((await reopenedLibrary.list()).single.id, book.id);
    expect(await reopenedLibrary.readBytes(book), isNotEmpty);
    expect(await DriftProgressStore(db).load(book.id), savedProgress);
    final notes = await reopenedLibrary.annotationStore(book.id)!.list();
    expect(notes.map((note) => note.type).toSet(), {
      ReaderAnnotationType.mark,
      ReaderAnnotationType.thought,
    });
    expect(notes.singleWhere((note) => note.note != null).note, '统计更新后仍需保留的想法');
    expect(
      (await reopenedLibrary.bookmarkStore(book.id)!.list()).single.label,
      '保留的书签',
    );
    expect(await _savedReadingData(db), before);
    expect(db.schemaVersion, 2);
  });

  test('未知书籍明确返回身份失败，非正时长仍不写入噪声记录', () async {
    final start = DateTime(2026, 11, 3, 8);
    await expectLater(
      store.add(
        bookId: 'missing',
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 1)),
      ),
      throwsA(
        isA<ReadingSessionSaveException>().having(
          (error) => error.reason,
          '身份失败原因',
          ReadingSessionSaveFailure.bookMissing,
        ),
      ),
    );
    await store.add(bookId: 'missing', startedAt: start, endedAt: start);

    expect(await store.list(), isEmpty);
    expect(await db.select(db.readingSessions).get(), isEmpty);
  });

  test('结束时旧标识只剩唯一别名，普通追加会话仍可解析改版后的书籍', () async {
    final bookId = await _insertSessionBook(db, 'before-rekey');
    await _rekeySessionBook(db, bookId, 'before-rekey', 'after-rekey');
    final start = DateTime(2026, 11, 15, 8);

    await store.add(
      bookId: 'before-rekey',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 2)),
    );

    expect((await db.select(db.readingSessions).get()).single.bookId, bookId);
    expect((await store.list()).single.bookId, 'after-rekey');
  });

  test('会话开始时绑定的整数主键，在软删除后仍保留完整时段', () async {
    final bookId = await _insertSessionBook(db, 'soft-removed');
    final bound = store.bindBook('soft-removed');
    await (db.update(db.books)..where((table) => table.id.equals(bookId)))
        .write(const BooksCompanion(deletedAt: Value(2)));
    final start = DateTime(2026, 11, 15, 8);

    await bound.add(
      bookId: 'soft-removed',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 2)),
      pageTurns: 3,
      charactersRead: 120,
    );

    final saved = (await db.select(db.readingSessions).get()).single;
    expect(saved.bookId, bookId);
    expect(saved.durationMs, const Duration(minutes: 2).inMilliseconds);
    expect(saved.pageTurns, 3);
    expect(saved.charactersRead, 120);
  });

  test('旧标识重新导入产生新书记录，开始时绑定的时段仍属于改版原书', () async {
    final originalId = await _insertSessionBook(db, 'reused-id');
    final bound = store.bindBook('reused-id');
    await _rekeySessionBook(db, originalId, 'reused-id', 'rekeyed-original');
    final reimportedId = await _insertSessionBook(db, 'reused-id');
    final start = DateTime(2026, 11, 15, 8);

    await bound.add(
      bookId: 'reused-id',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 2)),
    );

    final saved = (await db.select(db.readingSessions).get()).single;
    expect(saved.bookId, originalId);
    expect(saved.bookId, isNot(reimportedId));
    expect((await store.list()).single.bookId, 'rekeyed-original');
  });

  test('已绑定记录被真正删除时明确失败，不能将时段归给新出现的同名书', () async {
    final originalId = await _insertSessionBook(db, 'hard-removed');
    final bound = store.bindBook('hard-removed');
    await (db.delete(
      db.books,
    )..where((table) => table.id.equals(originalId))).go();
    await _insertSessionBook(db, 'hard-removed');
    final start = DateTime(2026, 11, 15, 8);

    await expectLater(
      bound.add(
        bookId: 'hard-removed',
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 2)),
      ),
      throwsA(
        isA<ReadingSessionSaveException>().having(
          (error) => error.reason,
          '身份失败原因',
          ReadingSessionSaveFailure.bookMissing,
        ),
      ),
    );

    expect(await db.select(db.readingSessions).get(), isEmpty);
  });
}
