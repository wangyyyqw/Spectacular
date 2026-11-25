import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/locator.dart';
import 'package:reader_mobile/home/book_duration_chart.dart';
import 'package:reader_mobile/home/reading_book_color.dart';
import 'package:reader_mobile/home/reading_calendar.dart';
import 'package:reader_mobile/home/stats_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';
import '../support/reader_pump.dart';
import '../support/color_cover.dart';

class _FakeLibrary extends LibraryStore {
  _FakeLibrary(this.books, this.weights) : super.memory();

  List<BookEntry> books;
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

  List<ReadingSession> items;

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

class _PendingSessionStore extends _FakeSessionStore {
  _PendingSessionStore(super.items);

  Completer<List<ReadingSession>>? pending;
  int listCalls = 0;

  @override
  Future<List<ReadingSession>> list() {
    listCalls++;
    return pending?.future ?? super.list();
  }
}

class _ObservedSessions extends ListBase<ReadingSession> {
  _ObservedSessions(this.items);

  final List<ReadingSession> items;
  int reads = 0;

  @override
  int get length {
    reads++;
    return items.length;
  }

  @override
  set length(int value) => throw UnsupportedError('只读样本');

  @override
  ReadingSession operator [](int index) {
    reads++;
    return items[index];
  }

  @override
  void operator []=(int index, ReadingSession value) =>
      throw UnsupportedError('只读样本');
}

ReadingSession _todaySession(int minutes) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day, 8);
  return ReadingSession(
    bookId: 'a',
    startedAt: start,
    endedAt: start.add(Duration(minutes: minutes)),
    duration: Duration(minutes: minutes),
  );
}

BookEntry _book(
  String id,
  String title, {
  DateTime? lastReadAt,
  int? spineCount,
  String? coverPath,
}) {
  return BookEntry(
    id: id,
    title: title,
    author: '',
    filePath: '',
    addedAt: DateTime(2026, 1, 1),
    lastReadAt: lastReadAt,
    spineCount: spineCount,
    coverPath: coverPath,
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

Future<void> _selectPeriod(WidgetTester tester, String period) async {
  await _tapControl(tester, 'stats-book-duration-period-$period');
}

Future<void> _tapControl(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await _scrollTo(tester, target, 180);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets('移除每日平均花瓣区块，保留其他统计内容：$platform', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: StatsPage(
            library: _FakeLibrary([_book('a', '保留的阅读记录')], const {}),
            progressStore: _FakeProgressStore({}),
            sessionStore: _FakeSessionStore([_todaySession(20)]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('每日平均'), findsNothing);
      expect(find.text('按星期'), findsNothing);
      expect(find.text('仅计有阅读记录的日期'), findsNothing);
      for (final key in [
        'stats-weekday-average-chart',
        'stats-weekday-petal-surface',
        'stats-weekday-detail-label',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
      for (final title in ['图书时长', '阅读日历', '阅读排行', '最近阅读']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(_valueOf(tester, 'stats-book-duration-total'), '20 分钟');
      expect(
        find.byKey(const ValueKey('stats-reading-calendar')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('stats-ranking-a')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('统计页从真实封面取色并统一传给图表和日历，更换封面后更新', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('stats-cover-color-'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final first = (await tester.runAsync(
      () => createColorCover(directory, 'first', const Color(0xFFB83235)),
    ))!;
    final next = (await tester.runAsync(
      () => createColorCover(directory, 'next', const Color(0xFF28795B)),
    ))!;
    final now = DateTime(2026, 11, 24, 20);
    final library = _FakeLibrary([
      _book('a', '封面取色书籍', coverPath: first.path),
      _book('b', '相近封面书籍', coverPath: first.path),
    ], const {});
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StatsPage(
          library: library,
          progressStore: _FakeProgressStore({}),
          sessionStore: _FakeSessionStore([
            for (final id in ['a', 'b'])
              ReadingSession(
                bookId: id,
                startedAt: DateTime(2026, 11, 24, 8),
                endedAt: DateTime(2026, 11, 24, 8, 30),
                duration: const Duration(minutes: 30),
              ),
          ]),
          now: now,
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(BookDurationChart));
    await pumpReaderUntilComplete(
      tester,
      () =>
          tester
              .widget<BookDurationChart>(find.byType(BookDurationChart))
              .bookColors
              .length ==
          2,
    );
    final chart = tester.widget<BookDurationChart>(
      find.byType(BookDurationChart),
    );
    final before = chart.bookColors['a']!;
    final hue = HSLColor.fromColor(before).hue;
    expect(hue, anyOf(lessThan(20), greaterThan(340)));
    expect(chart.bookColors.values.toSet(), hasLength(2));
    expect(
      tester.widget<ReadingCalendar>(find.byType(ReadingCalendar)).bookColors,
      chart.bookColors,
    );
    library.books = [
      _book('a', '封面取色书籍', coverPath: next.path),
      library.books.last,
    ];
    await tester.tap(find.byKey(const ValueKey('stats-refresh')));
    await pumpReaderUntilComplete(
      tester,
      () =>
          tester
              .widget<BookDurationChart>(find.byType(BookDurationChart))
              .bookColors['a'] !=
          before,
    );
    final updated = tester
        .widget<BookDurationChart>(find.byType(BookDurationChart))
        .bookColors;
    expect(
      tester.widget<ReadingCalendar>(find.byType(ReadingCalendar)).bookColors,
      updated,
    );
    expect(HSLColor.fromColor(updated['a']!).hue, inInclusiveRange(130, 175));
    expect(tester.takeException(), isNull);
  });

  testWidgets('首次进入先显示统计内容，封面配色解码完成后补入', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pendingColor = Completer<Color?>();
    final cache = ReadingBookColorCache(
      loadCoverColor: (path) => pendingColor.future,
    );
    final now = DateTime(2026, 11, 24, 20);
    final start = DateTime(now.year, now.month, now.day, 8);
    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(
          library: _FakeLibrary([
            _book('a', '慢取色书籍', coverPath: '/tmp/slow-cover.png'),
          ], const {}),
          progressStore: _FakeProgressStore(const {}),
          sessionStore: _FakeSessionStore([
            ReadingSession(
              bookId: 'a',
              startedAt: start,
              endedAt: start.add(const Duration(minutes: 10)),
              duration: const Duration(minutes: 10),
            ),
          ]),
          bookColorCache: cache,
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('慢取色书籍'), findsWidgets);
    expect(
      tester
          .widget<BookDurationChart>(find.byType(BookDurationChart))
          .bookColors,
      isEmpty,
    );

    pendingColor.complete(const Color(0xFFB83235));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BookDurationChart>(find.byType(BookDurationChart))
          .bookColors['a'],
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('切入等待和切出复用统计图表，刷新成功更新且失败保留旧内容', (tester) async {
    tester.view
      // 移除花瓣区块后页面变短，使用较矮窗口继续覆盖滚动位置保留。
      ..physicalSize = const Size(1280, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = _FakeLibrary([_book('a', '第一本')], const {});
    final progress = _FakeProgressStore(const {});
    final sessions = _PendingSessionStore([_todaySession(5)]);
    Widget page(bool active, int refreshToken) => MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: StatsPage(
        library: library,
        progressStore: progress,
        sessionStore: sessions,
        active: active,
        refreshToken: refreshToken,
      ),
    );
    await tester.pumpWidget(page(true, 0));
    await tester.pumpAndSettle();
    await _selectPeriod(tester, 'week');
    await _tapControl(tester, 'stats-calendar-previous');
    final range = _valueOf(tester, 'stats-book-duration-range');
    final month = _valueOf(tester, 'stats-calendar-month');
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(40);
    await tester.pumpAndSettle();
    final rebuilt = <Type>[];
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtBefore) {
      previous?.call(element, builtBefore);
      if (element.widget is BookDurationChart ||
          element.widget is ReadingCalendar) {
        rebuilt.add(element.widget.runtimeType);
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    await tester.pumpWidget(page(false, 0));
    await tester.pumpAndSettle();
    final pending = sessions.pending = Completer<List<ReadingSession>>();
    await tester.pumpWidget(page(true, 1));
    await tester.pumpAndSettle();
    expect(sessions.listCalls, 2);
    expect(rebuilt, isEmpty);
    expect(scroll.position.pixels, 40);
    expect(_valueOf(tester, 'stats-book-duration-total'), '5 分钟');

    final originalBook = library.books.single;
    final originalSession = sessions.items.single;
    library.books = [_book('a', '第一本')];
    sessions.items = [_todaySession(5)];
    expect(identical(library.books.single, originalBook), isFalse);
    expect(identical(sessions.items.single, originalSession), isFalse);
    pending.complete(sessions.items);
    sessions.pending = null;
    await tester.pumpAndSettle();
    expect(rebuilt, isEmpty, reason: '新对象的值相同，返回刷新仍复用图表');
    await tester.tap(find.byKey(const ValueKey('stats-refresh')));
    await tester.pumpAndSettle();
    expect(sessions.listCalls, 3);
    expect(rebuilt, isEmpty, reason: '显式刷新仍重新查询，但不重建相同内容');

    final changed = sessions.pending = Completer<List<ReadingSession>>();
    await tester.tap(find.byKey(const ValueKey('stats-refresh')));
    await tester.pump();
    changed.complete([_todaySession(10)]);
    await tester.pumpAndSettle();
    expect(rebuilt, containsAll([BookDurationChart, ReadingCalendar]));
    expect(_valueOf(tester, 'stats-book-duration-total'), '10 分钟');
    expect(_valueOf(tester, 'stats-book-duration-range'), range);
    expect(_valueOf(tester, 'stats-calendar-month'), month);
    expect(scroll.position.pixels, 40);
    rebuilt.clear();
    final failed = sessions.pending = Completer<List<ReadingSession>>();
    await tester.tap(find.byKey(const ValueKey('stats-refresh')));
    await tester.pump();
    failed.completeError(StateError('读取失败'));
    await tester.pumpAndSettle();
    expect(rebuilt, isEmpty);
    expect(_valueOf(tester, 'stats-book-duration-total'), '10 分钟');
    expect(find.text('统计刷新失败，请稍后重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('相同数据跨自然日刷新，书籍进度与权重变化仍更新', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final day = DateTime(2026, 11, 15, 12);
    final library = _FakeLibrary(
      [_book('a', '旧书名')],
      {
        'a': ProgressWeights.fromCharCounts([1, 1]),
      },
    );
    final progress = _FakeProgressStore({
      'a': const ReaderProgress(spineIndex: 1, pageIndex: 0),
    });
    final sessions = _PendingSessionStore([
      ReadingSession(
        bookId: 'a',
        startedAt: day.subtract(const Duration(hours: 4)),
        endedAt: day.subtract(const Duration(hours: 3, minutes: 54)),
        duration: const Duration(minutes: 6),
      ),
    ]);
    Widget page(DateTime now) => MaterialApp(
      home: StatsPage(
        library: library,
        progressStore: progress,
        sessionStore: sessions,
        now: now,
      ),
    );
    await tester.pumpWidget(page(day));
    await tester.pumpAndSettle();
    expect(_valueOf(tester, 'stats-book-duration-total'), '6 分钟');
    final original = tester.widget<BookDurationChart>(
      find.byType(BookDurationChart),
    );
    library.weights['a'] = ProgressWeights.fromCharCounts([1, 3]);
    await tester.tap(find.byKey(const ValueKey('stats-refresh')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BookDurationChart>(find.byType(BookDurationChart)),
      isNot(same(original)),
    );
    await _scrollTo(tester, find.byKey(const ValueKey('stats-book-a')), 300);
    expect(_valueOf(tester, 'stats-book-a'), '25%');

    library.books = [
      library.books.single.copyWith(title: '新书名', contentRevision: '修订2'),
    ];
    progress.items['a'] = const ReaderProgress(
      spineIndex: 1,
      pageIndex: 1,
      readingPercent: .6,
      finished: true,
    );
    await tester.tap(find.byKey(const ValueKey('stats-refresh')));
    await tester.pumpAndSettle();
    expect(_valueOf(tester, 'stats-book-a'), '60%');
    expect(find.text('新书名'), findsWidgets);
    expect(find.text('旧书名'), findsNothing);

    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    final sameHour = tester.widget<BookDurationChart>(
      find.byType(BookDurationChart),
    );
    await tester.pumpWidget(page(day.add(const Duration(minutes: 1))));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BookDurationChart>(find.byType(BookDurationChart)),
      same(sameHour),
    );
    await tester.pumpWidget(page(day.add(const Duration(hours: 1))));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BookDurationChart>(find.byType(BookDurationChart)),
      isNot(same(sameHour)),
      reason: '最近阅读的小时标签变化需要更新',
    );
    final previousDay = tester.widget<BookDurationChart>(
      find.byType(BookDurationChart),
    );
    await tester.pumpWidget(page(day.add(const Duration(days: 1))));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BookDurationChart>(find.byType(BookDurationChart)),
      isNot(same(previousDay)),
    );
    expect(_valueOf(tester, 'stats-book-duration-range'), '今天 · 2026年11月16日');
    expect(
      find.byKey(const ValueKey('stats-book-duration-total')),
      findsNothing,
    );
    expect(find.text('该时段没有阅读记录'), findsOneWidget);
    expect(sessions.listCalls, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('隐藏时完成的刷新不遍历会话，重入读取最新数据', (tester) async {
    final library = _FakeLibrary([_book('a', '第一本')], const {});
    final progress = _FakeProgressStore(const {});
    final sessions = _PendingSessionStore([_todaySession(5)]);
    Widget page(bool active) => MaterialApp(
      home: StatsPage(
        library: library,
        progressStore: progress,
        sessionStore: sessions,
        active: active,
      ),
    );
    await tester.pumpWidget(page(true));
    await tester.pumpAndSettle();
    final chart = tester.widget<BookDurationChart>(
      find.byType(BookDurationChart),
    );
    final pending = sessions.pending = Completer<List<ReadingSession>>();
    await tester.tap(find.byKey(const ValueKey('stats-refresh')));
    await tester.pump();
    expect(sessions.listCalls, 2);
    await tester.pumpWidget(page(false));
    final stale = _ObservedSessions([_todaySession(15)]);
    pending.complete(stale);
    sessions.pending = null;
    await tester.pumpAndSettle();
    expect(stale.reads, 0);
    expect(
      tester.widget<BookDurationChart>(find.byType(BookDurationChart)),
      same(chart),
    );
    expect(_valueOf(tester, 'stats-book-duration-total'), '5 分钟');

    sessions.items
      ..clear()
      ..add(_todaySession(20));
    await tester.pumpWidget(page(true));
    await tester.pumpAndSettle();
    expect(sessions.listCalls, 3);
    expect(_valueOf(tester, 'stats-book-duration-total'), '20 分钟');
    expect(tester.takeException(), isNull);
  });

  testWidgets('复用统计内容仍响应主题字号和平台，保留周期月份', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = _FakeLibrary([_book('a', '第一本')], const {});
    final progress = _FakeProgressStore(const {});
    final sessions = _PendingSessionStore([_todaySession(5)]);
    Widget page(ThemeData theme, double scale) => MaterialApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: StatsPage(
        library: library,
        progressStore: progress,
        sessionStore: sessions,
      ),
    );
    final day = buildAppTheme().copyWith(platform: TargetPlatform.windows);
    final night = buildAppTheme(brightness: Brightness.dark)
        .copyWith(platform: TargetPlatform.windows);
    await tester.pumpWidget(page(day, 1));
    await tester.pumpAndSettle();
    await _selectPeriod(tester, 'week');
    await _tapControl(tester, 'stats-calendar-previous');
    final range = _valueOf(tester, 'stats-book-duration-range');
    final month = _valueOf(tester, 'stats-calendar-month');
    final chartState = tester.state(find.byType(BookDurationChart));
    final calendarState = tester.state(find.byType(ReadingCalendar));

    await tester.pumpWidget(page(night, 2));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(BookDurationChart)), same(chartState));
    expect(tester.state(find.byType(ReadingCalendar)), same(calendarState));
    expect(_valueOf(tester, 'stats-book-duration-range'), range);
    expect(_valueOf(tester, 'stats-calendar-month'), month);
    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey('stats-reading-calendar')),
          )
          .color,
      night.colorScheme.surface,
    );
    final monthText = find.descendant(
      of: find.byKey(const ValueKey('stats-calendar-month')),
      matching: find.byType(RichText),
    );
    expect(tester.widget<RichText>(monthText).textScaler.scale(12), 24);
    expect(
      find.byKey(const ValueKey('stats-desktop-sections')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      page(night.copyWith(platform: TargetPlatform.android), 1),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stats-desktop-sections')), findsNothing);
    expect(sessions.listCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '桌面统计宽窗双栏、窄窗单栏，缩放保留所选统计周期',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: StatsPage(
            library: _FakeLibrary([], const {}),
            progressStore: _FakeProgressStore({}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('stats-desktop-sections')),
        findsOneWidget,
      );
      final duration = find.text('图书时长');
      final calendar = find.text('阅读日历');
      expect(tester.getTopLeft(duration).dy, tester.getTopLeft(calendar).dy);
      expect(
        tester.getTopLeft(calendar).dx,
        greaterThan(tester.getTopLeft(duration).dx),
      );
      await _selectPeriod(tester, 'week');
      final weekRange = _valueOf(tester, 'stats-book-duration-range');
      expect(weekRange, contains('周'));
      tester.view.physicalSize = const Size(600, 900);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(calendar).dy,
        greaterThan(tester.getTopLeft(duration).dy),
      );
      expect(_valueOf(tester, 'stats-book-duration-range'), weekRange);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('首屏直接展示图书时长，移除摘要与概览且周切换使用真实会话', (tester) async {
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
    await _selectPeriod(tester, 'week');
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
    expect(find.text('合计 25 分钟'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stats-calendar-detail-0')),
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
    await _scrollTo(tester, find.text('阅读排行'), 180);
    expect(find.text('阅读热力图'), findsNothing);
    expect(find.text('阅读习惯'), findsNothing);
    expect(find.byKey(const ValueKey('stats-heatmap')), findsNothing);
    expect(find.byKey(const ValueKey('stats-current-streak')), findsNothing);
    expect(find.text('每日平均'), findsNothing);
    expect(
      find.byKey(const ValueKey('stats-weekday-average-chart')),
      findsNothing,
    );
    final calendarBottom = tester.getBottomLeft(
      find.byKey(const ValueKey('stats-reading-calendar')),
    );
    final rankingTop = tester.getTopLeft(find.text('阅读排行'));
    expect(rankingTop.dy - calendarBottom.dy, inExclusiveRange(0, 90));
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

  testWidgets('未达展示条件时排行和最近阅读保留空结构，仍批量查询进度与字数', (tester) async {
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
    expect(find.byKey(const ValueKey<String>('stats-open-a')), findsNothing);
    expect(find.byKey(const ValueKey<String>('stats-open-b')), findsNothing);
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
    final now = DateTime.now();

    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(
          library: library,
          progressStore: progress,
          sessionStore: _FakeSessionStore([
            ReadingSession(
              bookId: entry.id,
              startedAt: now.subtract(const Duration(minutes: 6)),
              endedAt: now,
              duration: const Duration(minutes: 6),
            ),
          ]),
        ),
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

  testWidgets('门槛仅筛书目，跨书不能凑门槛，全部短会话仍计入总时长', (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 8);
    final sessions = [
      ReadingSession(
        bookId: 'a',
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 2, seconds: 59)),
        duration: const Duration(minutes: 2, seconds: 59),
      ),
      ReadingSession(
        bookId: 'b',
        startedAt: start.add(const Duration(hours: 1)),
        endedAt: start.add(const Duration(hours: 1, minutes: 2)),
        duration: const Duration(minutes: 2),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(
          library: _FakeLibrary([
            _book('a', '累计样本甲'),
            _book('b', '累计样本乙'),
          ], const {}),
          progressStore: _FakeProgressStore(const {}),
          sessionStore: _FakeSessionStore(sessions),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('该时段暂无符合展示条件的书目'), findsOneWidget);
    expect(find.textContaining('单书单日超过 5 分钟进入榜单'), findsOneWidget);
    expect(_valueOf(tester, 'stats-book-duration-total'), '5 分钟');
    sessions.add(
      ReadingSession(
        bookId: 'a',
        startedAt: start.add(const Duration(hours: 2)),
        endedAt: start.add(const Duration(hours: 2, seconds: 1)),
        duration: const Duration(seconds: 1),
      ),
    );
    await _tapControl(tester, 'stats-refresh');
    expect(_valueOf(tester, 'stats-book-duration-total'), '5 分钟');
    expect(
      find.byKey(const ValueKey('stats-book-duration-value-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('stats-book-duration-value-b')),
      findsNothing,
    );
    sessions.add(
      ReadingSession(
        bookId: 'a',
        startedAt: start.add(const Duration(hours: 3)),
        endedAt: start.add(const Duration(hours: 3, minutes: 3)),
        duration: const Duration(minutes: 3),
      ),
    );
    await _tapControl(tester, 'stats-refresh');
    expect(_valueOf(tester, 'stats-book-duration-total'), '8 分钟');
    expect(_valueOf(tester, 'stats-book-duration-value-a'), '6 分钟');
    expect(
      find.byKey(const ValueKey('stats-book-duration-value-b')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stats-book-duration-legend')),
        matching: find.text('短时阅读'),
      ),
      findsNothing,
    );
    await _tapControl(tester, 'stats-book-duration-all');
    final complete = tester.widget<BookDurationListPage>(
      find.byType(BookDurationListPage),
    );
    expect(complete.summary.entries.map((entry) => entry.bookId), ['a', 'b']);
    expect(complete.summary.total, const Duration(minutes: 8));
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await _tapControl(
      tester,
      'stats-calendar-day-${now.year}-${now.month}-${now.day}',
    );
    expect(find.text('合计 8 分钟'), findsOneWidget);
    Navigator.of(tester.element(find.text('合计 8 分钟'))).pop();
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const ValueKey('stats-ranking-a')), 180);
    expect(_valueOf(tester, 'stats-ranking-duration-a'), '6 分钟');
    expect(find.byKey(const ValueKey('stats-ranking-b')), findsNothing);
    expect(_valueOf(tester, 'stats-ranking-counts-a'), '3 次 · 0 次翻页 · 0 字');
    await _scrollTo(tester, find.text('最近阅读'), 180);
    expect(find.byKey(const ValueKey('stats-open-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('stats-open-b')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('统计页隐藏未达标书目，跨日期的短时阅读仍保留在总时长', (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 8);
    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(
          library: _FakeLibrary([
            _book('short', '短记录样本'),
            _book('kept', '超过五分钟样本'),
          ], const {}),
          progressStore: _FakeProgressStore(const {}),
          sessionStore: _FakeSessionStore([
            ReadingSession(
              bookId: 'short',
              startedAt: start.subtract(const Duration(days: 1)),
              endedAt: start
                  .subtract(const Duration(days: 1))
                  .add(const Duration(minutes: 4, seconds: 59)),
              duration: const Duration(minutes: 4, seconds: 59),
            ),
            ReadingSession(
              bookId: 'kept',
              startedAt: start,
              endedAt: start.add(const Duration(minutes: 5, seconds: 1)),
              duration: const Duration(minutes: 5, seconds: 1),
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectPeriod(tester, 'week');
    expect(_valueOf(tester, 'stats-book-duration-total'), '10 分钟');
    expect(_valueOf(tester, 'stats-book-duration-value-kept'), '6 分钟');
    expect(
      find.byKey(const ValueKey('stats-book-duration-value-short')),
      findsNothing,
    );
  });

  testWidgets('最近阅读仅展示单书单日达标书目，短记录和无会话书目均隐藏', (tester) async {
    final now = DateTime.now();
    final keptEnd = now.subtract(const Duration(days: 2));
    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(
          library: _FakeLibrary([
            _book('short', '短记录样本', lastReadAt: now),
            _book('kept', '超过五分钟样本', lastReadAt: now),
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
              startedAt: keptEnd.subtract(const Duration(minutes: 6)),
              endedAt: keptEnd,
              duration: const Duration(minutes: 6),
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('最近阅读'), 300);
    expect(find.byKey(const ValueKey('stats-open-short')), findsNothing);
    expect(find.text('2 天前'), findsOneWidget);
    expect(find.byKey(const ValueKey('stats-open-legacy')), findsNothing);
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
