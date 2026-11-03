import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/locator.dart';
import 'package:reader_mobile/home/stats_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/file_progress_store.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

class _FakeLibrary extends LibraryStore {
  _FakeLibrary(this.books, this.weights) : super.memory();

  final List<BookEntry> books;
  final Map<String, ProgressWeights> weights;

  @override
  Future<List<BookEntry>> list() async => books;

  @override
  Future<ProgressWeights> progressWeights(String bookId) async =>
      weights[bookId] ?? ProgressWeights.fromCharCounts(const <int>[]);
}

class _FakeProgressStore implements ReaderProgressStore {
  _FakeProgressStore(this.items);

  final Map<String, ReaderProgress> items;

  @override
  Future<void> clear(String bookId) async {
    items.remove(bookId);
  }

  @override
  Future<ReaderProgress?> load(String bookId) async => items[bookId];

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    items[bookId] = progress;
  }

  @override
  Future<Map<String, ReaderProgress>> snapshot() async =>
      Map<String, ReaderProgress>.unmodifiable(items);
}

class _FakeSessionStore implements ReadingSessionStore {
  _FakeSessionStore(this.items);

  final List<ReadingSession> items;

  @override
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {}

  @override
  Future<List<ReadingSession>> list() async => items;
}

BookEntry _book(
  String id,
  String title, {
  DateTime? lastReadAt,
  int? spineCount,
}) {
  return BookEntry(
    id: id,
    title: title,
    author: '',
    filePath: '',
    addedAt: DateTime(2026, 1, 1),
    lastReadAt: lastReadAt,
    spineCount: spineCount,
  );
}

void main() {
  testWidgets('统计页展示真实进度、近七日阅读和累计字数', (tester) async {
    final now = DateTime.now();
    final books = [
      _book(
        'a',
        '第一本',
        lastReadAt: now.subtract(const Duration(days: 1)),
        spineCount: 2,
      ),
      _book(
        'b',
        '第二本',
        lastReadAt: now.subtract(const Duration(days: 10)),
        spineCount: 2,
      ),
      _book('c', '第三本', spineCount: 2),
    ];
    final library = _FakeLibrary(books, {
      'a': ProgressWeights.fromCharCounts([60, 40]),
      'b': ProgressWeights.fromCharCounts([50, 50]),
      'c': ProgressWeights.fromCharCounts([25, 25]),
    });
    final progress = _FakeProgressStore({
      'a': const ReaderProgress(spineIndex: 1, pageIndex: 0),
      'b': const ReaderProgress(spineIndex: 0, pageIndex: 0),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(library: library, progressStore: progress),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('stats-total-books')))
          .data,
      '3',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-recent-7-days')),
          )
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-activity-summary')),
          )
          .data,
      '1 天活跃 · 1 本书',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-activity-count-6')),
          )
          .data,
      '0',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-activity-count-5')),
          )
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-total-characters')),
          )
          .data,
      '250',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-average-progress')),
          )
          .data,
      '30%',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('stats-band-unread')),
      300,
    );
    expect(find.text('2 / 3 本已开始'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('stats-band-unread')))
          .data,
      '未开始 1 本',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('stats-band-early')))
          .data,
      '0-25% 1 本',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-band-advanced')),
          )
          .data,
      '51-75% 1 本',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('stats-book-a')),
      300,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('stats-book-a')))
          .data,
      '60%',
    );
  });

  testWidgets('近七天活跃图按自然日汇总阅读书籍', (tester) async {
    final now = DateTime.now();
    final books = [
      _book('today', '今天', lastReadAt: now),
      _book(
        'yesterday',
        '昨天',
        lastReadAt: now.subtract(const Duration(days: 1)),
      ),
      _book(
        'three-days',
        '三天前',
        lastReadAt: now.subtract(const Duration(days: 3)),
      ),
      _book('old', '更早', lastReadAt: now.subtract(const Duration(days: 8))),
    ];
    final library = _FakeLibrary(books, const {});
    final progress = _FakeProgressStore(const {});

    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(library: library, progressStore: progress),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-activity-summary')),
          )
          .data,
      '3 天活跃 · 3 本书',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-activity-count-6')),
          )
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-activity-count-5')),
          )
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-activity-count-3')),
          )
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-recent-7-days')),
          )
          .data,
      '3',
    );
  });

  testWidgets('统计页汇总今日、累计阅读时长与阅读天数', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessions = [
      ReadingSession(
        bookId: 'a',
        startedAt: today.add(const Duration(hours: 9)),
        endedAt: today.add(const Duration(hours: 9, minutes: 12)),
        duration: const Duration(minutes: 12),
      ),
      ReadingSession(
        bookId: 'a',
        startedAt: DateTime(today.year, today.month, today.day - 1, 9),
        endedAt: DateTime(today.year, today.month, today.day - 1, 9, 30),
        duration: const Duration(minutes: 30),
      ),
      ReadingSession(
        bookId: 'b',
        startedAt: DateTime(today.year, today.month, today.day - 10, 9),
        endedAt: DateTime(today.year, today.month, today.day - 10, 9, 45),
        duration: const Duration(minutes: 45),
      ),
    ];
    final library = _FakeLibrary([
      _book('a', '第一本', lastReadAt: now),
    ], const {});

    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(
          library: library,
          progressStore: _FakeProgressStore(const {}),
          sessionStore: _FakeSessionStore(sessions),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-today-reading')),
          )
          .data,
      '12 分钟',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-reading-days')),
          )
          .data,
      '共 3 天',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-total-reading')),
          )
          .data,
      '累计 1 小时 27 分',
    );
  });

  testWidgets('切回统计页时按刷新令牌重新读取阅读会话', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessions = <ReadingSession>[];
    final library = _FakeLibrary([_book('a', '第一本')], const {});

    Widget buildPage(int refreshToken) {
      return MaterialApp(
        home: StatsPage(
          library: library,
          progressStore: _FakeProgressStore(const {}),
          sessionStore: _FakeSessionStore(sessions),
          refreshToken: refreshToken,
        ),
      );
    }

    await tester.pumpWidget(buildPage(0));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-today-reading')),
          )
          .data,
      '--',
    );

    sessions.add(
      ReadingSession(
        bookId: 'a',
        startedAt: today.add(const Duration(hours: 9)),
        endedAt: today.add(const Duration(hours: 9, minutes: 2)),
        duration: const Duration(minutes: 2),
      ),
    );
    await tester.pumpWidget(buildPage(1));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-today-reading')),
          )
          .data,
      '2 分钟',
    );
  });

  testWidgets('统计页单独展示已读完书籍', (tester) async {
    final now = DateTime.now();
    final books = [
      _book('done', '读完的书', lastReadAt: now, spineCount: 2),
      _book('reading', '在读的书', lastReadAt: now, spineCount: 2),
    ];
    final library = _FakeLibrary(books, {
      'done': ProgressWeights.fromCharCounts([50, 50]),
      'reading': ProgressWeights.fromCharCounts([50, 50]),
    });
    final progress = _FakeProgressStore({
      'done': const ReaderProgress(spineIndex: 1, pageIndex: 0, finished: true),
      'reading': const ReaderProgress(spineIndex: 0, pageIndex: 0),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(library: library, progressStore: progress),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已开始 2 本 · 已读完 1 本'), findsOneWidget);
    expect(find.text('完成一本书也值得记录。'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('stats-band-finished')),
      300,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-band-finished')),
          )
          .data,
      '已读完 1 本',
    );
  });

  testWidgets('点击最近阅读卡片可直接续读', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await library.importBytes(buildTestEpub(title: '续读书'));
      await library.touchLastRead(entry.id);
    });
    final progress = FileReaderProgressStore.memory();
    await progress.save(
      entry.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(library: library, progressStore: progress),
      ),
    );
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.scrollUntilVisible(
      find.byKey(ValueKey<String>('stats-open-${entry.id}')),
      300,
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Hero && widget.tag == bookCoverHeroTag(entry.id),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(ValueKey<String>('stats-open-${entry.id}')));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const ValueKey<String>('reader-page')), findsOneWidget);
  });
}
