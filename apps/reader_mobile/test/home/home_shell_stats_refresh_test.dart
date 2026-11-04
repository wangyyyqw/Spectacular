import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/locator.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/file_progress_store.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';

class _FakeLibrary extends LibraryStore {
  _FakeLibrary() : super.memory();

  final List<ReadingSession> sessions = <ReadingSession>[];

  @override
  Future<List<BookEntry>> list() async => const <BookEntry>[];

  @override
  Future<ProgressWeights> progressWeights(String bookId) async =>
      ProgressWeights.fromCharCounts(const <int>[]);

  @override
  ReadingSessionStore? readingSessionStore() => _FakeSessionStore(sessions);
}

class _FakeSessionStore implements ReadingSessionStore {
  _FakeSessionStore(this.items);

  final List<ReadingSession> items;

  @override
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    int pageTurns = 0,
    int charactersRead = 0,
  }) async {}

  @override
  Future<List<ReadingSession>> list() async => List<ReadingSession>.of(items);
}

void main() {
  testWidgets('点击底部统计标签时重新读取阅读会话', (tester) async {
    final library = _FakeLibrary();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          library: library,
          progressStore: FileReaderProgressStore.memory(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final now = DateTime.now();
    library.sessions.add(
      ReadingSession(
        bookId: 'book-a',
        startedAt: now.subtract(const Duration(minutes: 3)),
        endedAt: now,
        duration: const Duration(minutes: 3),
      ),
    );

    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-today-reading')),
          )
          .data,
      '3 分钟',
    );
  });
}
