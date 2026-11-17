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

Future<void> _scrollTo(
  WidgetTester tester,
  Finder target,
  double distance,
) async {
  await tester.scrollUntilVisible(
    target,
    distance,
    scrollable: find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await tester.pumpAndSettle();
}

String _valueOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

Future<void> _tapControl(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await _scrollTo(tester, target, 180);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首屏直接展示图书时长，移除摘要与概览且季度切换使用真实会话', (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 8);
    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(
          library: _FakeLibrary([_book('a', '图书时长样本')], const {}),
          progressStore: _FakeProgressStore(const {}),
          sessionStore: _FakeSessionStore([
            ReadingSession(
              bookId: 'a',
              startedAt: start,
              endedAt: start.add(const Duration(minutes: 25)),
              duration: const Duration(minutes: 25),
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('概览'), findsNothing);
    expect(find.byKey(const ValueKey('stats-today-reading')), findsNothing);
    expect(find.byKey(const ValueKey('stats-total-reading')), findsNothing);
    expect(find.byKey(const ValueKey('stats-total-books')), findsNothing);
    expect(find.text('近 7 天阅读时长'), findsNothing);
    expect(find.byKey(const ValueKey('stats-chart-period')), findsNothing);
    expect(find.byKey(const ValueKey('stats-chart-detail')), findsNothing);
    final appBarBottom = tester.getBottomLeft(find.byType(AppBar));
    final durationTop = tester.getTopLeft(find.text('图书时长'));
    expect(durationTop.dy - appBarBottom.dy, inInclusiveRange(16, 32));
    await _tapControl(tester, 'stats-book-duration-period-quarter');
    expect(find.text('图书时长'), findsOneWidget);
    expect(_valueOf(tester, 'stats-book-duration-total'), '25 分钟');
    expect(_valueOf(tester, 'stats-book-duration-value-a'), '25 分钟');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stats-book-duration-tag-a')),
        matching: find.text('图书时长样本'),
      ),
      findsOneWidget,
    );
    await _tapControl(
      tester,
      'stats-calendar-day-${now.year}-${now.month}-${now.day}',
    );
    expect(find.text('1 本书 · 合计 25 分钟'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stats-calendar-detail-a')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('已移出书架的书保留名称与时长，并进入阅读排行', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(
          library: _FakeLibrary([_book('current', '当前书籍')], const {}),
          progressStore: _FakeProgressStore(const {}),
          sessionStore: _FakeSessionStore([
            for (final record in [('current', 10), ('archived', 30)])
              ReadingSession(
                bookId: record.$1,
                bookTitle: record.$1 == 'archived' ? '历史保留的书' : '当前书籍',
                startedAt: today.add(const Duration(hours: 9)),
                endedAt: today.add(Duration(hours: 9, minutes: record.$2)),
                duration: Duration(minutes: record.$2),
              ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_valueOf(tester, 'stats-book-duration-total'), '40 分钟');
    final ranking = find.byKey(const ValueKey('stats-ranking-archived'));
    await _scrollTo(tester, ranking, 180);
    expect(_valueOf(tester, 'stats-ranking-duration-archived'), '30 分钟');
    expect(
      find.descendant(of: ranking, matching: find.text('历史保留的书')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: ranking, matching: find.text('已移出书架')),
      findsOneWidget,
    );
    expect(tester.widget<InkWell>(ranking).onTap, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小屏双倍字号下长书名、排行与最近阅读不溢出，保留精简后的区块', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: StatsPage(
          library: _FakeLibrary([
            _book('a', '一本包含很长很长中文书名的阅读记录和统计样本', lastReadAt: now),
          ], const {}),
          progressStore: _FakeProgressStore(const {}),
          sessionStore: _FakeSessionStore([
            ReadingSession(
              bookId: 'a',
              startedAt: today.add(const Duration(hours: 9)),
              endedAt: today.add(const Duration(hours: 10)),
              duration: const Duration(hours: 1),
              pageTurns: 123,
              charactersRead: 54321,
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_valueOf(tester, 'stats-book-duration-total'), '1 小时');
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('stats-weekday-latest-date')),
      180,
    );
    expect(find.text('阅读热力图'), findsNothing);
    expect(find.text('阅读习惯'), findsNothing);
    expect(find.byKey(const ValueKey('stats-heatmap')), findsNothing);
    expect(find.byKey(const ValueKey('stats-current-streak')), findsNothing);
    final averageBottom = tester.getBottomLeft(
      find.byKey(const ValueKey('stats-weekday-average-chart')),
    );
    final rankingTop = tester.getTopLeft(find.text('阅读排行'));
    expect(rankingTop.dy - averageBottom.dy, inExclusiveRange(0, 90));
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('stats-ranking-counts-a')),
      180,
    );
    expect(_valueOf(tester, 'stats-ranking-duration-a'), '1 小时');
    await _scrollTo(tester, find.byKey(const ValueKey('stats-open-a')), 180);
    expect(find.text('最近阅读'), findsOneWidget);
    expect(_valueOf(tester, 'stats-book-a'), '--');
    expect(tester.takeException(), isNull);
  });

  testWidgets('按书排行显示有效会话的详细数据', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessions = [
      ReadingSession(
        bookId: 'a',
        startedAt: DateTime(today.year, today.month, today.day - 1, 9),
        endedAt: DateTime(today.year, today.month, today.day - 1, 9, 30),
        duration: const Duration(minutes: 30),
        pageTurns: 3,
        charactersRead: 300,
      ),
      ReadingSession(
        bookId: 'a',
        startedAt: today.add(const Duration(hours: 14)),
        endedAt: today.add(const Duration(hours: 14, minutes: 20)),
        duration: const Duration(minutes: 20),
        pageTurns: 2,
        charactersRead: 200,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(
          library: _FakeLibrary([_book('a', '详细统计')], const {}),
          progressStore: _FakeProgressStore(const {}),
          sessionStore: _FakeSessionStore(sessions),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('stats-ranking-duration-a')),
      180,
    );
    expect(_valueOf(tester, 'stats-ranking-duration-a'), '50 分钟');
    expect(
      find.byKey(const ValueKey('stats-ranking-counts-a')),
      findsOneWidget,
    );
    expect(find.text('2 次 · 5 次翻页 · 500 字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('阅读排行直接衔接最近阅读，保留进度与字数查询接口', (tester) async {
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

    expect(library.progressWeightCalls, 0, reason: '统计页应批量读取进度权重');
    expect(library.batchProgressWeightCalls, 1);
    await _scrollTo(tester, find.text('开始阅读后，这里会按投入时长列出书目。'), 300);
    expect(find.text('阅读分布'), findsNothing);
    expect(find.byKey(const ValueKey('stats-band-unread')), findsNothing);
    expect(find.byKey(const ValueKey('stats-band-finished')), findsNothing);
    final rankingBottom = tester.getBottomLeft(
      find.text('开始阅读后，这里会按投入时长列出书目。'),
    );
    final recentTop = tester.getTopLeft(find.text('最近阅读'));
    expect(recentTop.dy - rankingBottom.dy, inExclusiveRange(0, 90));
    await _scrollTo(
      tester,
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
      find.byKey(const ValueKey('stats-book-duration-total')),
      findsNothing,
    );

    sessions.add(
      ReadingSession(
        bookId: 'a',
        startedAt: today.add(const Duration(hours: 9)),
        endedAt: today.add(const Duration(hours: 9, minutes: 5)),
        duration: const Duration(minutes: 5),
      ),
    );
    await tester.pumpWidget(buildPage(1));
    await tester.pumpAndSettle();

    expect(_valueOf(tester, 'stats-book-duration-total'), '5 分钟');
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
    await _scrollTo(
      tester,
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

  testWidgets('统计页不计入低于 5 分钟的阅读记录，满 5 分钟的记录保留', (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 8);
    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(
          library: _FakeLibrary([
            _book('short', '短记录样本'),
            _book('kept', '满五分钟样本'),
          ], const {}),
          progressStore: _FakeProgressStore(const {}),
          sessionStore: _FakeSessionStore([
            ReadingSession(
              bookId: 'short',
              startedAt: start,
              endedAt: start.add(const Duration(minutes: 4, seconds: 59)),
              duration: const Duration(minutes: 4, seconds: 59),
            ),
            ReadingSession(
              bookId: 'kept',
              startedAt: start,
              endedAt: start.add(const Duration(minutes: 5)),
              duration: const Duration(minutes: 5),
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapControl(tester, 'stats-book-duration-period-quarter');
    expect(_valueOf(tester, 'stats-book-duration-total'), '5 分钟');
    expect(_valueOf(tester, 'stats-book-duration-value-kept'), '5 分钟');
    expect(
      find.byKey(const ValueKey('stats-book-duration-value-short')),
      findsNothing,
    );
  });

  testWidgets('最近阅读只按满五分钟的会话排列，短记录的书不列出，无会话的历史书保留', (tester) async {
    final now = DateTime.now();
    final keptEnd = now.subtract(const Duration(days: 2));
    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(
          library: _FakeLibrary([
            _book('short', '短记录样本', lastReadAt: now),
            _book('kept', '满五分钟样本', lastReadAt: now),
            _book(
              'legacy',
              '无会话样本',
              lastReadAt: now.subtract(const Duration(days: 3)),
            ),
          ], const {}),
          progressStore: _FakeProgressStore(const {}),
          sessionStore: _FakeSessionStore([
            ReadingSession(
              bookId: 'short',
              startedAt: now.subtract(const Duration(minutes: 4, seconds: 59)),
              endedAt: now,
              duration: const Duration(minutes: 4, seconds: 59),
            ),
            ReadingSession(
              bookId: 'kept',
              startedAt: keptEnd.subtract(const Duration(minutes: 5)),
              endedAt: keptEnd,
              duration: const Duration(minutes: 5),
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('最近阅读'), 300);
    expect(find.byKey(const ValueKey('stats-open-short')), findsNothing);
    expect(find.text('2 天前'), findsOneWidget);
    expect(find.text('3 天前'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('stats-open-kept'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('stats-open-legacy'))).dy,
      ),
    );
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
