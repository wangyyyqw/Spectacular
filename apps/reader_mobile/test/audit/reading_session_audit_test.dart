import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reading_session_tracker.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';

class _MemorySessionStore implements ReadingSessionStore {
  final List<ReadingSession> items = <ReadingSession>[];
  bool failNext = false;

  @override
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    int pageTurns = 0,
    int charactersRead = 0,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('模拟存储失败');
    }
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
  test('片段保存失败不抛出后台异常，也不跳过下一段有效记录', () async {
    final store = _MemorySessionStore()..failNext = true;
    var now = DateTime(2026, 11, 4, 8);
    final tracker = ReadingSessionTracker(
      store: store,
      bookId: 'book-a',
      now: () => now,
    )..start();
    now = now.add(const Duration(minutes: 1));
    await expectLater(tracker.pause(), completes);

    tracker.start();
    tracker.recordPageTurn(characters: 25);
    now = now.add(const Duration(minutes: 2));
    await tracker.finish();
    expect(store.items, hasLength(1));
    expect(store.items.single.duration, const Duration(minutes: 2));
    expect(store.items.single.charactersRead, 25);
  });

  test('后台间隔不计时，重复启动和结束不会重复记录翻页与字数', () async {
    final store = _MemorySessionStore();
    var now = DateTime(2026, 11, 4, 9);
    final tracker = ReadingSessionTracker(
      store: store,
      bookId: '审计会话',
      now: () => now,
    );
    tracker.start();
    tracker.start();
    tracker.recordPageTurn(count: 2, characters: 40);
    now = now.add(const Duration(seconds: 35));
    final firstWrite = tracker.pause();
    tracker.recordPageTurn(characters: 1000);
    now = now.add(const Duration(hours: 2));
    tracker.start();
    tracker.recordPageTurn(characters: 10);
    now = now.add(const Duration(seconds: 25));
    await tracker.finish();
    await firstWrite;
    await tracker.finish();
    tracker.start();
    tracker.recordPageTurn(characters: 1000);

    expect(store.items, hasLength(2));
    expect(store.items.map((item) => item.duration.inSeconds), [35, 25]);
    expect(store.items.map((item) => item.pageTurns), [2, 1]);
    expect(store.items.map((item) => item.charactersRead), [40, 10]);
  });
}
