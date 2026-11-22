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

List<ReadingSession> _longAndShortSpans() => [
  for (final day in [17, 18, 19])
    _session('long', DateTime(2026, 11, day, 9), 5, title: '长条'),
  for (final day in [17, 18])
    _session('medium', DateTime(2026, 11, day, 10), 30, title: '两天记录'),
  _session('short', DateTime(2026, 11, 17, 11), 20, title: '书名很长但只阅读了一天的短条记录'),
  _session('later', DateTime(2026, 11, 19, 12), 30, title: '后一天短条'),
];

void main() {
  test('日历隐藏未达标书名，月汇总和单日合计保留所有短时阅读', () {
    final day = DateTime(2026, 11, 20, 8);
    final insights = ReadingInsights(
      [
        ReadingSession(
          bookId: 'shown',
          startedAt: day,
          endedAt: day.add(const Duration(seconds: 3)),
          duration: const Duration(seconds: 3),
        ),
        _session('shown', DateTime(2026, 11, 21, 8), 6),
        ReadingSession(
          bookId: 'hidden',
          startedAt: day.add(const Duration(hours: 1)),
          endedAt: day.add(const Duration(hours: 1, seconds: 7)),
          duration: const Duration(seconds: 7),
        ),
      ],
      now: DateTime(2026, 11, 21),
      minimumBookDayDuration: minimumDisplayedBookDayDuration,
    );
    final month = ReadingCalendarMonth(insights, date: day);
    expect(month.bookCount, 1);
    expect(month.total, const Duration(minutes: 6, seconds: 10));
    expect(
      month.dayDurations[DateTime(2026, 11, 20)],
      const Duration(seconds: 10),
    );
    expect(month.days[DateTime(2026, 11, 20)]!.single.bookId, 'shown');
    expect(
      month.days[DateTime(2026, 11, 20)]!.single.duration,
      const Duration(seconds: 3),
    );
  });

  test('周内条带按跨日长度从上到下排列，不按书名长度或单日时长排列', () {
    final month = _month(_longAndShortSpans(), _now);
    final spans = month.spansForWeek(2);
    final longest = spans.singleWhere((span) => span.bookId == 'long');
    final medium = spans.singleWhere((span) => span.bookId == 'medium');
    final shortest = spans.singleWhere((span) => span.bookId == 'short');
    final later = spans.singleWhere((span) => span.bookId == 'later');
    expect((longest.firstColumn, longest.lastColumn, longest.lane), (2, 4, 0));
    expect(medium.lane, 1);
    expect(shortest.lane, 2);
    expect(later.lane, 1);
    expect(spans.length, 4);
    expect(month.spansForWeek(0), isEmpty);
  });

  test('交错条带优先放长条，四行内完整显示且不重叠、不拆断', () {
    const intervals = [
      (3, 5),
      (0, 1),
      (0, 1),
      (1, 2),
      (2, 3),
      (2, 3),
      (2, 3),
      (4, 5),
      (5, 6),
      (5, 6),
      (1, 1),
      (4, 4),
      (6, 6),
      (6, 6),
    ];
    final month = _month([
      for (var index = 0; index < intervals.length; index++)
        for (
          var column = intervals[index].$1;
          column <= intervals[index].$2;
          column++
        )
          _session('$index', DateTime(2026, 11, column + 1, 9), 10),
    ], _now);
    final spans = month.spansForWeek(0);
    expect(spans.length, intervals.length);
    expect(spans.singleWhere((span) => span.bookId == '0').lane, 0);
    for (final span in spans) {
      expect((
        span.firstColumn,
        span.lastColumn,
      ), intervals[int.parse(span.bookId)]);
      expect(span.lane, inInclusiveRange(0, 3));
    }
    for (var column = 0; column < 7; column++) {
      final active = spans.where(
        (span) => span.firstColumn <= column && span.lastColumn >= column,
      );
      expect(active.map((span) => span.lane).toSet().length, active.length);
      expect(active.length, month.days[DateTime(2026, 11, column + 1)]!.length);
    }
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('窄屏字号 $scale 倍长条在上短条在下，连续范围保持完整', (tester) async {
      await _pump(
        tester,
        _longAndShortSpans(),
        width: 320,
        scale: scale,
        now: DateTime(2026, 11, 19),
      );
      final longest = tester.getRect(_key('bar-2-long-2'));
      final medium = tester.getRect(_key('bar-2-medium-2'));
      final shortest = tester.getRect(_key('bar-2-short-2'));
      final firstDay = tester.getRect(_key('day-2026-11-17'));
      final lastDay = tester.getRect(_key('day-2026-11-19'));
      expect(longest.bottom, lessThan(medium.top));
      expect(medium.bottom, lessThan(shortest.top));
      expect(longest.width, greaterThan(medium.width));
      expect(medium.width, greaterThan(shortest.width));
      expect(longest.left, greaterThan(firstDay.left));
      expect(longest.right, lessThan(lastDay.right));
      expect(tester.takeException(), isNull);
    });
  }

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

  test('单日保留时长最多的四本，跨日沿用原行且不重叠', () {
    final month = _month(_fourThenFiveBooks(), _now);
    final spans = month.spansForWeek(0);
    const expected = [
      ['0', '1', '2', '3'],
      ['4', '3', '2', '1'],
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
      expect(active.every((span) => span.lane < 4), isTrue);
    }
    final fourth = spans.where((span) => span.bookId == '3').toList();
    expect(fourth.map((span) => (span.firstColumn, span.lastColumn)), [(0, 2)]);
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

  testWidgets('月历长书名单行省略，详情保留完整书目和书名', (tester) async {
    const visibleTitle = '一部书名很长且需要在日历条带里省略的作品';
    const title = '一本名称很长很长而且需要在当日明细中完整展示的书籍';
    await _pump(tester, [
      for (var id = 0; id < 6; id++)
        _session(
          '$id',
          DateTime(2026, 11, 15, 9),
          10,
          title: switch (id) {
            0 => visibleTitle,
            5 => title,
            _ => null,
          },
        ),
    ]);
    final preview = tester.widget<Text>(find.text(visibleTitle));
    expect(preview.maxLines, 1);
    expect(preview.overflow, TextOverflow.clip);
    expect(preview.softWrap, isFalse);
    expect(find.text('+2'), findsNothing);
    expect(find.text(title), findsNothing);
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
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.textContaining(title, findRichText: true),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('当日明细按阅读片段显示时分秒时间轴和秒级时长', (tester) async {
    await _pump(tester, [
      ReadingSession(
        bookId: 'vegetarian',
        bookTitle: '素食者',
        startedAt: DateTime(2026, 11, 15, 0, 23, 5),
        endedAt: DateTime(2026, 11, 15, 0, 23, 37),
        duration: const Duration(seconds: 32),
      ),
      ReadingSession(
        bookId: 'vegetarian',
        bookTitle: '素食者',
        startedAt: DateTime(2026, 11, 15, 0, 27),
        endedAt: DateTime(2026, 11, 15, 0, 27, 2),
        duration: const Duration(seconds: 2),
      ),
      ReadingSession(
        bookId: 'radar',
        bookTitle: '现代雷达系统分析与设计',
        startedAt: DateTime(2026, 11, 15, 0, 36, 4),
        endedAt: DateTime(2026, 11, 15, 0, 36, 55),
        duration: const Duration(seconds: 51),
      ),
    ]);
    await _tap(tester, 'day-2026-11-15');

    expect(find.text('00:23:05'), findsOneWidget);
    expect(find.text('00:27:00'), findsOneWidget);
    expect(find.text('00:36:04'), findsOneWidget);
    expect(find.text('32秒'), findsOneWidget);
    expect(find.text('2秒'), findsOneWidget);
    expect(find.text('51秒'), findsOneWidget);
    expect(find.textContaining('《素食者》', findRichText: true), findsNWidgets(2));
    expect(
      find.textContaining('《现代雷达系统分析与设计》', findRichText: true),
      findsOneWidget,
    );
    final line = tester.getRect(
      find.byKey(const ValueKey('stats-calendar-detail-0')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('stats-calendar-detail-1')),
    );
    expect(line.top, lessThan(second.top));
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('五本仅显示四条且不显示 +n，字号 $scale 倍时日期居中', (tester) async {
      await _pump(tester, _fourThenFiveBooks(), width: 320, scale: scale);
      for (var id = 0; id < 4; id++) {
        expect(_key('bar-0-$id-0'), findsOneWidget);
      }
      expect(find.textContaining(RegExp(r'^\+\d+$')), findsNothing);
      final fourth = tester.getRect(_key('bar-0-3-0'));
      final firstNumber = tester.getRect(_key('number-2026-11-1'));
      expect(fourth.bottom, lessThan(firstNumber.top));
      final secondDay = tester.getRect(_key('day-2026-11-2'));
      expect(fourth.right, greaterThan(secondDay.center.dx));
      for (var day = 1; day <= 30; day++) {
        final number = _key('number-2026-11-$day');
        expect(tester.widget<Text>(number).textAlign, TextAlign.center);
        expect(
          tester.getCenter(number).dx,
          tester.getCenter(_key('day-2026-11-$day')).dx,
        );
      }
      await _tap(tester, 'day-2026-11-2');
      expect(find.text('5 本书 · 合计 2 小时 30 分'), findsOneWidget);
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

  testWidgets('紧凑月历将空周收至点击高度，多书周仍完整展开', (tester) async {
    await _pump(tester, _fourThenFiveBooks());
    final month = tester.getRect(_key('month'));
    final summary = tester.getRect(_key('summary'));
    final previous = tester.getRect(_key('previous'));
    final next = tester.getRect(_key('next'));
    expect(month.left, summary.left);
    expect(month.bottom, lessThanOrEqualTo(summary.top));
    expect(previous.right, next.left);
    expect(previous.width, greaterThanOrEqualTo(kMinInteractiveDimension));
    final empty = tester.getRect(_key('day-2026-11-8'));
    final busy = tester.getRect(_key('day-2026-11-1'));
    expect(empty.height, kMinInteractiveDimension);
    expect(busy.height, greaterThan(empty.height));
    await _tap(tester, 'day-2026-11-8');
    expect(find.text('这一天没有阅读记录'), findsOneWidget);
  });

  testWidgets('箭头可浏览空月和跨年月份，今天按钮回到当前月份', (tester) async {
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
    await _tap(tester, 'next');
    await _tap(tester, 'today');
    expect(find.text('2026年2月'), findsOneWidget);
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

  testWidgets('窄屏双倍字号直接显示周末并打开明细，刷新保留所选月份', (tester) async {
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

  testWidgets('日历保留圆角外框，日期格子无边框或底色，今天深色加粗', (tester) async {
    await _pump(tester, []);
    final frame = tester.widget<Material>(
      find.byKey(const ValueKey('stats-reading-calendar')),
    );
    final shape = frame.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(20));
    expect(shape.side.width, 1);
    expect(frame.clipBehavior, Clip.antiAlias);
    final context = tester.element(_key('day-2026-11-15'));
    final scheme = Theme.of(context).colorScheme;
    final todayNumber = tester.widget<Text>(_key('number-2026-11-15'));
    expect(todayNumber.style!.fontWeight, FontWeight.w700);
    expect(todayNumber.style!.color, scheme.onSurface);
    final pastNumber = tester.widget<Text>(_key('number-2026-11-14'));
    expect(pastNumber.style!.fontWeight, FontWeight.w400);
    expect(pastNumber.style!.color, scheme.onSurfaceVariant);
    final futureNumber = tester.widget<Text>(_key('number-2026-11-16'));
    expect(futureNumber.style!.fontWeight, FontWeight.w400);
    expect(futureNumber.style!.color, scheme.outline);
    for (var day = 1; day <= 30; day++) {
      expect(
        find.descendant(
          of: _key('day-2026-11-$day'),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
    }
    final title = tester.getRect(_key('month'));
    final previous = tester.getRect(_key('previous'));
    final next = tester.getRect(_key('next'));
    final today = tester.getRect(_key('today'));
    expect(title.right, lessThan(previous.left));
    expect(previous.center.dy, next.center.dy);
    expect(next.center.dy, today.center.dy);
    expect(next.right, lessThan(today.left));
    expect(today.width, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('查看过去日期和今天的明细后，关闭面板不留下底色或选中状态', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, [
      _session('a', DateTime(2026, 11, 14, 9), 20),
      _session('b', DateTime(2026, 11, 15, 9), 30),
    ]);
    for (final day in [14, 15]) {
      await _tap(tester, 'day-2026-11-$day');
      expect(find.text('2026-11-$day'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      final cell = _key('day-2026-11-$day');
      expect(
        find.descendant(of: cell, matching: find.byType(DecoratedBox)),
        findsNothing,
      );
      expect(
        tester.getSemantics(cell).flagsCollection.isSelected.toBoolOrNull(),
        isNull,
      );
      expect(find.text('2 天阅读 · 2 本 · 50 分钟'), findsOneWidget);
    }
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('窄屏字号 $scale 倍七列都在边框内，左右拖动不移动日历或切月', (tester) async {
      await _pump(tester, _fourThenFiveBooks(), width: 320, scale: scale);
      final frame = find.byKey(const ValueKey('stats-reading-calendar'));
      expect(
        find.descendant(
          of: frame,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                [
                  AxisDirection.left,
                  AxisDirection.right,
                ].contains(widget.axisDirection),
          ),
        ),
        findsNothing,
      );
      expect(find.text('左右滑动查看完整一周'), findsNothing);
      final bounds = tester.getRect(frame);
      for (var day = 1; day <= 30; day++) {
        final rect = tester.getRect(_key('day-2026-11-$day'));
        expect(rect.left, greaterThan(bounds.left));
        expect(rect.right, lessThan(bounds.right));
      }
      final sunday = tester.getRect(_key('day-2026-11-1'));
      final saturday = tester.getRect(_key('day-2026-11-7'));
      for (final distance in [-180.0, 180.0]) {
        await tester.drag(_key('day-2026-11-4'), Offset(distance, 0));
        await tester.pumpAndSettle();
        expect(find.text('2026年11月'), findsOneWidget);
        expect(tester.getRect(_key('day-2026-11-1')), sunday);
        expect(tester.getRect(_key('day-2026-11-7')), saturday);
      }
      await _tap(tester, 'day-2026-11-7');
      expect(find.text('2026-11-07'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('月份下拉可跨年选择空月，今天返回本月并保留原统计', (tester) async {
    await _pump(tester, [_session('a', DateTime(2026, 11, 2, 9), 30)]);
    await _tap(tester, 'pick-month');
    expect(find.text('选择月份'), findsOneWidget);
    await _tap(tester, 'previous-year');
    await _tap(tester, 'pick-2025-12');
    expect(find.text('2025年12月'), findsOneWidget);
    expect(_key('month-picker'), findsNothing);
    expect(find.text('本月暂无阅读记录'), findsOneWidget);
    await _tap(tester, 'today');
    expect(find.text('2026年11月'), findsOneWidget);
    expect(find.text('1 天阅读 · 1 本 · 30 分钟'), findsOneWidget);
    await _tap(tester, 'pick-month');
    await _tap(tester, 'next-year');
    await _tap(tester, 'pick-2027-1');
    expect(find.text('2027年1月'), findsOneWidget);
    await _tap(tester, 'pick-month');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('2027年1月'), findsOneWidget);
    expect(_key('month-picker'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏双倍字号的月份选择器可见并能选择十二月', (tester) async {
    await _pump(tester, [], width: 320, scale: 2);
    await _tap(tester, 'pick-month');
    await _tap(tester, 'pick-2026-12');
    expect(find.text('2026年12月'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
