import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reading_session_tracker.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';

class _MemorySessionStore implements ReadingSessionStore {
  final List<ReadingSession> items = <ReadingSession>[];

  @override
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    items.add(
      ReadingSession(
        bookId: bookId,
        startedAt: startedAt,
        endedAt: endedAt,
        duration: endedAt.difference(startedAt),
      ),
    );
  }

  @override
  Future<List<ReadingSession>> list() async => List.of(items);
}

void main() {
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
}
