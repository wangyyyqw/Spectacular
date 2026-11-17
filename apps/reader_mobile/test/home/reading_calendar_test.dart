import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reading_calendar.dart';
import 'package:reader_mobile/home/reading_calendar_month.dart';
import 'package:reader_mobile/home/reading_insights.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/icons/app_icon.dart';

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

List<ReadingSession> _fourThenFiveBooks() => [
  for (var id = 0; id < 4; id++)
    _session('$id', DateTime(2026, 11, 1, 9), 40 - id * 10),
  for (var id = 0; id < 5; id++)
    _session('$id', DateTime(2026, 11, 2, 9), id * 10 + 10),
  _session('3', DateTime(2026, 11, 3, 9), 10),
];

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

  test('四本全部保留，五本取时长前三本，跨日换行不会漏书或重叠', () {
    final month = _month(_fourThenFiveBooks(), _now);
    final spans = month.spansForWeek(0);
    const expected = [
      ['0', '1', '2', '3'],
      ['4', '3', '2'],
      ['3'],
    ];
    for (var column = 0; column < 3; column++) {
      final active = spans.where(
        (span) => span.firstColumn <= column && span.lastColumn >= column,
      );
      expect(
        active.map((span) => span.bookId),
        unorderedEquals(expected[column]),
      );
      expect(active.map((span) => span.lane).toSet().length, active.length);
      expect(active.every((span) => span.lane < (column == 1 ? 3 : 4)), isTrue);
    }
    final fourth = spans.where((span) => span.bookId == '3').toList();
    expect(fourth.map((span) => (span.firstColumn, span.lastColumn)), [
      (0, 0),
      (1, 2),
    ]);
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
    expect(
      find.descendant(of: _key('bar-0-a-0'), matching: find.byType(AppIcon)),
      findsOneWidget,
    );
    final day = tester.getRect(_key('day-2026-11-2'));
    await tester.tapAt(Offset(day.center.dx, bar.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('2026-11-02'), findsOneWidget);
    expect(find.text('1 本书 · 合计 20 分钟'), findsOneWidget);
    expect(find.text('已读'), findsOneWidget);
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
    expect(find.text('+3'), findsOneWidget);
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
    expect(
      find.descendant(of: find.byType(BottomSheet), matching: find.text(title)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('四本显示四条、五本显示三条和剩余数量，字号 $scale 倍不重叠', (tester) async {
      await _pump(tester, _fourThenFiveBooks(), width: 320, scale: scale);
      expect(_key('more-2026-11-1'), findsNothing);
      for (var id = 0; id < 4; id++) {
        expect(_key('bar-0-$id-0'), findsOneWidget);
      }
      expect(find.text('+2'), findsOneWidget);
      final fourth = tester.getRect(_key('bar-0-3-0'));
      final firstNumber = tester.getRect(_key('number-2026-11-1'));
      expect(fourth.bottom, lessThan(firstNumber.top));
      final overflow = tester.getRect(_key('more-2026-11-2'));
      final lastOnSecondDay = tester.getRect(_key('bar-0-2-0'));
      expect(lastOnSecondDay.bottom, lessThan(overflow.top));
      expect(
        overflow.bottom,
        lessThan(tester.getRect(_key('day-2026-11-2')).bottom),
      );
      await _tap(tester, 'day-2026-11-1');
      expect(find.text('4 本书 · 合计 1 小时 40 分'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('仅绘制本月日期格子，月首与月末仍按星期对齐', (tester) async {
    for (final date in [DateTime(2026, 11, 15), DateTime(2024, 2, 29)]) {
      await _pump(tester, [], now: date);
      final month = _month([], date);
      final cells = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'stats-calendar-day-',
            ),
      );
      expect(cells, findsNWidgets(month.dayCount));
      final first = _key('day-${date.year}-${date.month}-1');
      final nextWeek = _key('day-${date.year}-${date.month}-8');
      expect(tester.getRect(first).left, tester.getRect(nextWeek).left);
      final outside = [
        month.start.subtract(const Duration(days: 1)),
        DateTime(date.year, date.month + 1),
      ];
      for (final day in outside) {
        expect(_key('day-${day.year}-${day.month}-${day.day}'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('箭头可浏览空月和跨年月份，月份标题不打开选择面板', (tester) async {
    await _pump(tester, [
      _session('a', DateTime(2025, 12, 31, 9), 10),
    ], now: DateTime(2026, 2, 15));
    expect(tester.widget<IconButton>(_key('next')).onPressed, isNotNull);
    expect(find.text('本月暂无阅读记录'), findsOneWidget);
    await _tap(tester, 'previous');
    expect(find.text('2026年1月'), findsOneWidget);
    await _tap(tester, 'previous');
    expect(find.text('2025年12月'), findsOneWidget);
    await _tap(tester, 'previous');
    expect(find.text('2025年11月'), findsOneWidget);
    expect(find.text('本月暂无阅读记录'), findsOneWidget);
    for (var index = 0; index < 3; index++) {
      await _tap(tester, 'next');
    }
    expect(find.text('2026年2月'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('选择月份'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有会话也能切换前后月份及跨年，十二月一日正确对齐周二', (tester) async {
    await _pump(tester, []);
    await _tap(tester, 'previous');
    expect(find.text('2026年10月'), findsOneWidget);
    await _tap(tester, 'next');
    await _tap(tester, 'next');
    expect(find.text('2026年12月'), findsOneWidget);
    expect(find.text('0 天阅读 · 0 本 · 0 分钟'), findsOneWidget);
    expect(
      tester.getCenter(_key('day-2026-12-1')).dx,
      tester.getCenter(find.text('二')).dx,
    );
    expect(_key('day-2026-12-31'), findsOneWidget);
    expect(tester.widget<InkWell>(_key('day-2026-12-1')).onTap, isNull);
    await _tap(tester, 'next');
    expect(find.text('2027年1月'), findsOneWidget);
    await _tap(tester, 'previous');
    expect(find.text('2026年12月'), findsOneWidget);
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
