import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/locator.dart';
import 'package:reader_mobile/home/stats_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';
import '../support/reader_pump.dart';

class _FakeLibrary extends LibraryStore {
  _FakeLibrary(this.books, this.weights) : super.memory();

  final List<BookEntry> books;
  final Map<String, ProgressWeights> weights;
  int progressWeightCalls = 0;
  int batchProgressWeightCalls = 0;

  @override
  Future<List<BookEntry>> list() async => books;

  @override
  Future<ProgressWeights> progressWeights(String bookId) async {
    progressWeightCalls += 1;
    return weights[bookId] ?? ProgressWeights.fromCharCounts(const <int>[]);
  }

  @override
  Future<Map<String, ProgressWeights>> progressWeightsForBooks(
    Iterable<String> bookIds,
  ) async {
    batchProgressWeightCalls += 1;
    return <String, ProgressWeights>{
      for (final id in bookIds) id: ?weights[id],
    };
  }
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

class _FailingLibrary extends LibraryStore {
  _FailingLibrary() : super.memory();

  @override
  Future<List<BookEntry>> list() async => throw StateError('boom');
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
      'a': const ReaderProgress(
        spineIndex: 1,
        pageIndex: 0,
        readingPercent: 0.6,
      ),
      'b': const ReaderProgress(spineIndex: 0, pageIndex: 0, readingPercent: 0),
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
      '1 天',
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
    expect(library.progressWeightCalls, 0, reason: '统计页应批量读取进度权重');
    expect(library.batchProgressWeightCalls, 1);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('stats-band-unread')),
      300,
    );
    expect(find.text('已开始 2 本 · 已读完 0 本'), findsOneWidget);
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
      '3 天',
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
        pageTurns: 12,
        charactersRead: 400,
      ),
      ReadingSession(
        bookId: 'a',
        startedAt: DateTime(today.year, today.month, today.day - 1, 9),
        endedAt: DateTime(today.year, today.month, today.day - 1, 9, 30),
        duration: const Duration(minutes: 30),
        pageTurns: 8,
        charactersRead: 300,
      ),
      ReadingSession(
        bookId: 'b',
        startedAt: DateTime(today.year, today.month, today.day - 10, 9),
        endedAt: DateTime(today.year, today.month, today.day - 10, 9, 45),
        duration: const Duration(minutes: 45),
        pageTurns: 5,
        charactersRead: 200,
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
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('stats-page-turns')))
          .data,
      '25',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-characters-read')),
          )
          .data,
      '900',
    );
    expect(find.text('近 7 天阅读'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-recent-7-days')),
          )
          .data,
      '2 天',
    );
    expect(find.text('近 7 天阅读时长'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-activity-summary')),
          )
          .data,
      '42 分钟 · 2 天',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-activity-count-6')),
          )
          .data,
      '12分',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-activity-count-5')),
          )
          .data,
      '30分',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-activity-caption')),
          )
          .data,
      '按实际前台阅读时长统计',
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

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('stats-band-finished')),
      300,
    );
    expect(find.text('已开始 2 本 · 已读完 1 本'), findsOneWidget);
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
    final progress = MemoryReaderProgressStore();
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
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey<String>('reader-page')),
    );

    expect(find.byKey(const ValueKey<String>('reader-page')), findsOneWidget);
  });

  testWidgets('阅读图表支持日周月年切换并展示时段书目', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );
    final fiveWeeksAgo = DateTime(
      monday.year,
      monday.month,
      monday.day - 33,
      9,
    );
    // 五周前可能仍在上个月；月、年样本远离较短时段，避免月初或年初混入。
    final threeMonthsAgo = DateTime(now.year, now.month - 3, 15, 9);
    final twoYearsAgo = DateTime(now.year - 2, now.month, 15, 9);
    final sessions = <ReadingSession>[
      ReadingSession(
        bookId: 'a',
        startedAt: today.add(const Duration(hours: 9)),
        endedAt: today.add(const Duration(hours: 9, minutes: 30)),
        duration: const Duration(minutes: 30),
      ),
      ReadingSession(
        bookId: 'b',
        startedAt: today.add(const Duration(hours: 10)),
        endedAt: today.add(const Duration(hours: 10, minutes: 15)),
        duration: const Duration(minutes: 15),
      ),
      ReadingSession(
        bookId: 'a',
        startedAt: DateTime(today.year, today.month, today.day - 1, 9),
        endedAt: DateTime(today.year, today.month, today.day - 1, 9, 10),
        duration: const Duration(minutes: 10),
      ),
      ReadingSession(
        bookId: 'b',
        startedAt: fiveWeeksAgo,
        endedAt: fiveWeeksAgo.add(const Duration(minutes: 20)),
        duration: const Duration(minutes: 20),
      ),
      ReadingSession(
        bookId: 'c',
        startedAt: threeMonthsAgo,
        endedAt: threeMonthsAgo.add(const Duration(minutes: 25)),
        duration: const Duration(minutes: 25),
      ),
      ReadingSession(
        bookId: 'c',
        startedAt: twoYearsAgo,
        endedAt: twoYearsAgo.add(const Duration(minutes: 30)),
        duration: const Duration(minutes: 30),
      ),
    ];
    final library = _FakeLibrary([
      _book('a', '第一本'),
      _book('b', '第二本'),
      _book('c', '第三本'),
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('stats-chart-period')),
      300,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('stats-chart-period')),
    );
    await tester.pumpAndSettle();

    String valueOf(String key) =>
        tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

    expect(valueOf('stats-activity-summary'), '55 分钟 · 2 天');
    expect(valueOf('stats-chart-bucket-duration'), '45 分钟');
    expect(valueOf('stats-chart-book-duration-a'), '30 分钟');
    expect(valueOf('stats-chart-book-duration-b'), '15 分钟');
    expect(
      find.byKey(const ValueKey<String>('stats-chart-book-c')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('stats-chart-period-week')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('stats-chart-bar-week-2')),
    );
    await tester.pumpAndSettle();
    expect(valueOf('stats-chart-bucket-duration'), '20 分钟');
    expect(valueOf('stats-chart-book-duration-b'), '20 分钟');
    expect(
      find.byKey(const ValueKey<String>('stats-chart-book-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('stats-chart-book-c')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('stats-chart-period-month')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('stats-chart-bar-month-8')),
    );
    await tester.pumpAndSettle();
    expect(valueOf('stats-chart-bucket-duration'), '25 分钟');
    expect(valueOf('stats-chart-book-duration-c'), '25 分钟');
    expect(
      find.byKey(const ValueKey<String>('stats-chart-book-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('stats-chart-book-b')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('stats-chart-period-year')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('stats-chart-bar-year-2')),
    );
    await tester.pumpAndSettle();
    expect(valueOf('stats-chart-bucket-duration'), '30 分钟');
    expect(valueOf('stats-chart-book-duration-c'), '30 分钟');
    expect(
      find.byKey(const ValueKey<String>('stats-chart-book-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('stats-chart-book-b')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('stats-chart-period-day')),
    );
    await tester.pumpAndSettle();
    expect(valueOf('stats-chart-bucket-duration'), '45 分钟');
    await tester.tap(
      find.byKey(const ValueKey<String>('stats-chart-bar-day-5')),
    );
    await tester.pumpAndSettle();
    expect(valueOf('stats-chart-bucket-duration'), '10 分钟');
    expect(valueOf('stats-chart-book-duration-a'), '10 分钟');
    expect(
      find.byKey(const ValueKey<String>('stats-chart-book-b')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('stats-chart-book-c')),
      findsNothing,
    );
  });

  testWidgets('点击阅读热力图查看当日详细数据', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessions = <ReadingSession>[
      ReadingSession(
        bookId: 'a',
        startedAt: today.add(const Duration(hours: 9)),
        endedAt: today.add(const Duration(hours: 9, minutes: 30)),
        duration: const Duration(minutes: 30),
        pageTurns: 12,
        charactersRead: 400,
      ),
      ReadingSession(
        bookId: 'b',
        startedAt: today.add(const Duration(hours: 14)),
        endedAt: today.add(const Duration(hours: 14, minutes: 15)),
        duration: const Duration(minutes: 15),
        pageTurns: 3,
        charactersRead: 100,
      ),
    ];
    final library = _FakeLibrary([
      _book('a', '第一本'),
      _book('b', '第二本'),
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
    final dayKey = ValueKey<String>('stats-heatmap-day-${_dateKey(today)}');
    await tester.scrollUntilVisible(find.byKey(dayKey), 300);
    await tester.ensureVisible(find.byKey(dayKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(dayKey));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-day-detail-duration')),
          )
          .data,
      '45 分钟',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-day-detail-sessions')),
          )
          .data,
      '2',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-day-detail-page-turns')),
          )
          .data,
      '15',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-day-detail-characters')),
          )
          .data,
      '500',
    );
    expect(find.text('第一本'), findsWidgets);
  });

  testWidgets('首次加载失败时显示重试入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(
          library: _FailingLibrary(),
          progressStore: _FakeProgressStore(const {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('统计加载失败'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('stats-retry')), findsOneWidget);
  });
}

String _dateKey(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
