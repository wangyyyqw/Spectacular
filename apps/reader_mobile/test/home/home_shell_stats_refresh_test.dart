import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/locator.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_ui/reader_session.dart';

class _FakeLibrary extends LibraryStore {
  _FakeLibrary() : super.memory();

  final List<ReadingSession> sessions = <ReadingSession>[];
  late final _FakeSessionStore sessionStore = _FakeSessionStore(sessions);

  @override
  Future<List<BookEntry>> list() async => const <BookEntry>[];

  @override
  Future<ProgressWeights> progressWeights(String bookId) async =>
      ProgressWeights.fromCharCounts(const <int>[]);

  @override
  ReadingSessionStore? readingSessionStore() => sessionStore;
}

class _FakeSessionStore implements ReadingSessionStore {
  _FakeSessionStore(this.items);

  final List<ReadingSession> items;
  int listCalls = 0;

  @override
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    int pageTurns = 0,
    int charactersRead = 0,
  }) async {}

  @override
  Future<List<ReadingSession>> list() async {
    listCalls += 1;
    return List<ReadingSession>.of(items);
  }
}

void main() {
  testWidgets('点击底部统计标签时重新读取阅读会话', (tester) async {
    final library = _FakeLibrary();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(library.sessionStore.listCalls, 0, reason: '隐藏的统计页不应在启动时读取阅读会话');
    final navigation = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    for (final index in <int>[0, 1, 2, 3]) {
      expect(navigation.items[index].icon, isNot(isA<Icon>()));
      expect(navigation.items[index].activeIcon, isNot(isA<Icon>()));
    }

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(library.sessionStore.listCalls, 1);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-book-duration-total')),
          )
          .data,
      '3 分钟',
    );
  });
}
