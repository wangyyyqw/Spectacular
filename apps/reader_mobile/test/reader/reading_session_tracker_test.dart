import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';
import 'package:reader_mobile/home/reading_insights.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/reading_session_tracker.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';

import '../support/test_epub.dart';

class _MemorySessionStore implements ReadingSessionStore {
  final List<ReadingSession> items = <ReadingSession>[];

  @override
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    int pageTurns = 0,
    int charactersRead = 0,
  }) async {
    items.add(
      ReadingSession(
        bookId: bookId,
        startedAt: startedAt,
        endedAt: endedAt,
        duration: endedAt.difference(startedAt),
        pageTurns: pageTurns,
        charactersRead: charactersRead,
      ),
    );
  }

  @override
  Future<List<ReadingSession>> list() async => List.of(items);
}

void main() {
  test('累计有效前台秒数，暂停不计时，恢复后接续满一分钟', () async {
    final store = _MemorySessionStore();
    var now = DateTime.utc(2026, 11, 21);
    final tracker = ReadingSessionTracker(
      store: store,
      bookId: 'book-1',
      now: () => now,
    );
    tracker.start();
    now = now.add(const Duration(seconds: 35));
    expect(tracker.elapsed, const Duration(seconds: 35));
    await tracker.pause();
    now = now.add(const Duration(minutes: 5));
    expect(tracker.elapsed, const Duration(seconds: 35));
    tracker.start();
    now = now.add(const Duration(seconds: 25));
    expect(tracker.elapsed, const Duration(minutes: 1));
    await tracker.pause();
    expect(tracker.elapsed, const Duration(minutes: 1));
    expect(
      store.items.fold<Duration>(
        Duration.zero,
        (total, item) => total + item.duration,
      ),
      const Duration(minutes: 1),
    );
  });

  test('进入后台暂停，恢复后开启新片段，结束时提交剩余时长', () async {
    final store = _MemorySessionStore();
    var now = DateTime(2026, 11, 3, 8);
    final tracker = ReadingSessionTracker(
      store: store,
      bookId: 'book-a',
      now: () => now,
    )..start();

    now = now.add(const Duration(minutes: 10));
    await tracker.pause();
    now = now.add(const Duration(hours: 1));
    tracker.start();
    now = now.add(const Duration(minutes: 5));
    await tracker.finish();
    await tracker.finish();

    expect(store.items, hasLength(2));
    expect(store.items[0].duration, const Duration(minutes: 10));
    expect(store.items[1].duration, const Duration(minutes: 5));
    expect(
      store.items.fold<Duration>(
        Duration.zero,
        (total, item) => total + item.duration,
      ),
      const Duration(minutes: 15),
    );
  });

  test('短于最小记录时长的片段不落库', () async {
    final store = _MemorySessionStore();
    var now = DateTime(2026, 11, 3, 8);
    final tracker = ReadingSessionTracker(
      store: store,
      bookId: 'book-a',
      now: () => now,
      minimumDuration: const Duration(seconds: 2),
    )..start();

    now = now.add(const Duration(seconds: 1));
    await tracker.finish();

    expect(store.items, isEmpty);
  });

  test('翻页次数与阅读字数随片段落库，暂停后重新累计', () async {
    final store = _MemorySessionStore();
    var now = DateTime(2026, 11, 3, 8);
    final tracker = ReadingSessionTracker(
      store: store,
      bookId: 'book-a',
      now: () => now,
    )..start();

    tracker.recordPageTurn(characters: 12);
    tracker.recordPageTurn(characters: 8);
    now = now.add(const Duration(minutes: 3));
    await tracker.pause();

    tracker.start();
    tracker.recordPageTurn(characters: 20);
    now = now.add(const Duration(minutes: 2));
    await tracker.finish();

    expect(store.items, hasLength(2));
    expect(store.items[0].pageTurns, 2);
    expect(store.items[0].charactersRead, 20);
    expect(store.items[1].pageTurns, 1);
    expect(store.items[1].charactersRead, 20);
  });

  test('多次短前台片段累计超过两小时，书架汇总不因暂停少计', () async {
    final root = await Directory.systemTemp.createTemp('session-short-total-');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => root,
    );
    final book = await library.importBytes(
      buildTestEpub(identifier: 'session-short-total'),
    );
    var now = DateTime(2026, 11, 21, 8);
    final store = library.readingSessionStore()!;
    final tracker = ReadingSessionTracker(
      store: store,
      bookId: book.id,
      now: () => now,
    )..start();
    now = now.add(const Duration(minutes: 65));
    await tracker.pause();
    for (var index = 0; index < 21; index++) {
      now = now.add(const Duration(minutes: 2));
      tracker.start();
      now = now.add(const Duration(minutes: 3));
      await tracker.pause();
    }
    await tracker.finish();

    const total = Duration(hours: 2, minutes: 8);
    final sessions = await store.list();
    expect(sessions, hasLength(22));
    expect(
      sessions.fold(Duration.zero, (sum, session) => sum + session.duration),
      total,
    );
    final durations = await library.bookReadingDurations(
      minimumCountedSessionDuration,
    );
    expect(durations[book.id], total);
    expect(formatReadingDuration(durations[book.id]!), '2 小时 8 分');
  });

  test('跟踪器在计时前绑定原书，真实改版重键和原标识重导入不改变时段归属', () async {
    final root = await Directory.systemTemp.createTemp(
      'session-tracker-binding-',
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => root,
    );
    final bytes = buildTestEpub(identifier: 'session-original');
    final original = await library.importBytes(bytes);
    final originalKey = (await db.select(db.books).get()).single.id;
    var now = DateTime(2026, 11, 15, 8);
    final tracker = ReadingSessionTracker(
      store: library.readingSessionStore()!,
      bookId: original.id,
      now: () => now,
    )..start();
    final updated = await library.updateBytes(
      original.id,
      buildTestEpub(identifier: 'session-updated'),
    );
    final reimported = await library.importBytes(bytes);
    tracker.recordPageTurn(characters: 42);
    now = now.add(const Duration(minutes: 2));

    await tracker.finish();

    final saved = (await db.select(db.readingSessions).get()).single;
    expect(saved.bookId, originalKey);
    expect(saved.charactersRead, 42);
    final session = (await library.readingSessionStore()!.list()).single;
    expect(session.bookId, updated.id);
    expect(session.bookId, isNot(reimported.id));
  });

  test('无法归属的时段留下明确诊断，生命周期完成且不记录书名或原文', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    ReaderLog.instance.resetForTest();
    addTearDown(ReaderLog.instance.resetForTest);
    const privateIdentity = '无法归属的私密书名';
    var now = DateTime(2026, 11, 15, 8);
    final tracker = ReadingSessionTracker(
      store: DriftReadingSessionStore(db),
      bookId: privateIdentity,
      now: () => now,
    )..start();
    now = now.add(const Duration(minutes: 2));

    await expectLater(tracker.finish(), completes);

    expect(await db.select(db.readingSessions).get(), isEmpty);
    final diagnostic = await ReaderLog.instance.exportText();
    expect(diagnostic, contains('reading_session_save_error'));
    expect(diagnostic, contains('reason_enum=bookMissing'));
    expect(diagnostic, isNot(contains(privateIdentity)));
  });
}
