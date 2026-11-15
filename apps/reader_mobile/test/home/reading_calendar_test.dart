import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reading_calendar.dart';
import 'package:reader_mobile/home/reading_calendar_month.dart';
import 'package:reader_mobile/home/reading_insights.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';

final _now = DateTime(2026, 11, 15, 20);

ReadingSession _session(
  String id,
  DateTime start,
  int minutes, {
  String? title,
}) => ReadingSession(
  bookId: id,
  bookTitle: title ?? '书籍 $id',
  startedAt: start,
  endedAt: start.add(Duration(minutes: minutes)),
  duration: Duration(minutes: minutes),
);

ReadingCalendarMonth _month(List<ReadingSession> sessions, DateTime date) =>
    ReadingCalendarMonth(ReadingInsights(sessions, now: _now), date: date);

Finder _key(String suffix) => find.byKey(ValueKey('stats-calendar-$suffix'));

Future<void> _pump(
  WidgetTester tester,
  List<ReadingSession> sessions, {
  double width = 360,
  double scale = 1,
  DateTime? now,
  Set<String> finished = const {},
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ReadingCalendar(
            insights: ReadingInsights(sessions, now: now ?? _now),
            now: now ?? _now,
            finishedBookIds: finished,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String suffix) async {
  await tester.ensureVisible(_key(suffix));
  await tester.pumpAndSettle();
  await tester.tap(_key(suffix));
  await tester.pumpAndSettle();
}

void main() {
  test('日历按自然日跨月分摊，同名书分开且书架名称优先', () {
    final sessions = [
      _session('a', DateTime(2026, 10, 31, 23, 50), 20, title: '旧名称'),
      _session('a', DateTime(2026, 11, 1, 8), 10),
      _session('b', DateTime(2026, 11, 1, 9), 15, title: '新名称'),
    ];
    final insights = ReadingInsights(sessions, now: _now);
    final month = ReadingCalendarMonth(
      insights,
      date: _now,
      bookTitles: {'a': '新名称'},
    );
    expect(month.total, const Duration(minutes: 35));
    expect(month.bookCount, 2);
    expect(month.days[DateTime(2026, 11, 1)]!.map((b) => b.title), [
      '新名称',
      '新名称',
    ]);
    expect(
      month.days[DateTime(2026, 11, 1)]!.first.duration,
      const Duration(minutes: 20),
    );
    expect(
      _month(sessions, DateTime(2026, 10)).total,
      const Duration(minutes: 10),
    );
  });

  test('连续阅读合并成条带，断档和跨周重新分段且同日条带不重叠', () {
    final month = _month([
      for (final day in [1, 2, 4, 6, 7, 8])
        _session('a', DateTime(2026, 11, day, 9), 10),
      for (final day in [2, 3, 4, 5])
        _session('b', DateTime(2026, 11, day, 9), 10),
    ], _now);
    final spans = month.spansForWeek(0);
    expect(
      spans
          .where((s) => s.bookId == 'a')
          .map((s) => (s.firstColumn, s.lastColumn)),
      [(0, 1), (3, 3), (5, 6)],
    );
    expect(month.spansForWeek(1).single.firstColumn, 0);
    for (var column = 0; column < 7; column++) {
      final active = spans.where(
        (s) => s.firstColumn <= column && s.lastColumn >= column,
      );
      expect(active.map((s) => s.lane).toSet().length, active.length);
    }
  });

  test('闰年和六行月份保留正确日历边界', () {
    final leap = _month([], DateTime(2024, 2));
    expect(leap.dayCount, 29);
    expect(leap.dateAt(0, 4), DateTime(2024, 2, 1));
    final sixWeeks = _month([], DateTime(2026, 8));
    expect(sixWeeks.weekCount, 6);
    expect(sixWeeks.dateAt(5, 1), DateTime(2026, 8, 31));
  });

  testWidgets('月历条带覆盖连续日期，点条带对应日期查看当天真实时长', (tester) async {
    await _pump(
      tester,
      [
        _session('a', DateTime(2026, 11, 1, 9), 10),
        _session('a', DateTime(2026, 11, 2, 9), 20),
      ],
      finished: {'a'},
    );
    final bar = tester.getRect(_key('bar-0-a-0'));
    final day = tester.getRect(_key('day-2026-11-2'));
    await tester.tapAt(Offset(day.center.dx, bar.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('2026年11月2日'), findsOneWidget);
    expect(find.text('1 本书 · 合计 20 分钟'), findsOneWidget);
    expect(find.text('当前已读完'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多书当天显示三条和额外数量，详情保留所有书目与完整名称', (tester) async {
    const title = '一本名称很长很长而且需要在当日明细中完整展示的书籍';
    await _pump(tester, [
      for (var id = 0; id < 6; id++)
        _session(
          '$id',
          DateTime(2026, 11, 15, 9),
          10,
          title: id == 5 ? title : null,
        ),
    ]);
    expect(find.text('+3 本'), findsOneWidget);
    await _tap(tester, 'day-2026-11-15');
    expect(find.text('6 本书 · 合计 1 小时'), findsOneWidget);
    await tester.scrollUntilVisible(
      _key('detail-5'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text(title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('跨年月份导航、空月和月份选择器可用，不能进入未来月份', (tester) async {
    await _pump(tester, [
      _session('a', DateTime(2025, 12, 31, 9), 10),
    ], now: DateTime(2026, 2, 15));
    expect(tester.widget<IconButton>(_key('next')).onPressed, isNull);
    expect(find.text('本月暂无阅读记录'), findsOneWidget);
    await _tap(tester, 'previous');
    expect(find.text('2026年1月'), findsOneWidget);
    await _tap(tester, 'previous');
    expect(find.text('2025年12月'), findsOneWidget);
    expect(tester.widget<IconButton>(_key('previous')).onPressed, isNull);
    await _tap(tester, 'month-picker');
    await _tap(tester, 'month-2026-2-1');
    expect(find.text('2026年2月'), findsOneWidget);
    await _tap(tester, 'day-2026-2-1');
    expect(find.text('这一天没有阅读记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏双倍字号可横向浏览周末并打开明细，刷新保留所选月份', (tester) async {
    final sessions = [_session('a', DateTime(2026, 10, 31, 9), 30)];
    await _pump(tester, sessions, width: 320, scale: 2);
    await _tap(tester, 'previous');
    sessions.add(_session('b', DateTime(2026, 10, 31, 10), 10));
    await _pump(tester, sessions, width: 320, scale: 2);
    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('1 天阅读 · 2 本 · 40 分钟'), findsOneWidget);
    await _tap(tester, 'day-2026-10-31');
    expect(find.text('2 本书 · 合计 40 分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
