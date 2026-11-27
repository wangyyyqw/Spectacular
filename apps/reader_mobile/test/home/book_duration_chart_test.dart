import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_duration_chart.dart';
import 'package:reader_mobile/home/book_duration_summary.dart';
import 'package:reader_mobile/home/reading_insights.dart';
import 'package:reader_mobile/home/voxel_duration_chart.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';

final _now = DateTime(2026, 11, 15, 20);

ReadingSession _session(String id, DateTime start, int minutes) =>
    ReadingSession(
      bookId: id,
      bookTitle: '书籍 $id',
      startedAt: start,
      endedAt: start.add(Duration(minutes: minutes)),
      duration: Duration(minutes: minutes),
    );

Future<void> _pump(
  WidgetTester tester,
  List<ReadingSession> sessions, {
  double width = 360,
  double scale = 1,
  Map<String, String> titles = const {},
  Map<String, Color> bookColors = const {},
  bool applyThreshold = false,
  bool initialTimeOfDay = false,
  DateTime? now,
}) async {
  final current = now ?? _now;
  tester.view.physicalSize = Size(width, 1100);
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
          child: BookDurationChart(
            insights: ReadingInsights(
              sessions,
              now: current,
              minimumBookDayDuration: applyThreshold
                  ? minimumDisplayedBookDayDuration
                  : Duration.zero,
            ),
            now: current,
            bookTitles: titles,
            bookColors: bookColors,
            startWithTimeOfDay: initialTimeOfDay,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String suffix) =>
    find.byKey(ValueKey('stats-book-duration-$suffix'));
Finder _legendText(String text) =>
    find.descendant(of: _key('legend'), matching: find.text(text));
String _text(WidgetTester tester, String suffix) =>
    tester.widget<Text>(_key(suffix)).data!;

Future<void> _tap(WidgetTester tester, String suffix) async {
  await tester.ensureVisible(_key(suffix));
  await tester.tap(_key(suffix));
  await tester.pumpAndSettle();
}

Finder _legendRows() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return widget is InkWell &&
      key is ValueKey<String> &&
      key.value.startsWith('stats-book-duration-tag-');
});

Color _dotColor(WidgetTester tester, Finder root) {
  final dot = find.descendant(
    of: root,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
    ),
  );
  return (tester.widget<Container>(dot).decoration! as BoxDecoration).color!;
}

Future<void> _selectPeriod(WidgetTester tester, String period) async {
  await _tap(tester, 'period-$period');
}

void main() {
  testWidgets('封面配色贯穿书柱、时段色段、书目色点与完整列表', (tester) async {
    const colors = {'a': Color(0xFF28795B), 'b': Color(0xFF285BAA)};
    await _pump(tester, [
      _session('a', DateTime(2026, 11, 15, 8), 30),
      _session('b', DateTime(2026, 11, 15, 9), 10),
    ], bookColors: colors);
    final chart = tester.widget<VoxelDurationChart>(
      find.byType(VoxelDurationChart),
    );
    expect(chart.bars.first.color, colors['a']);
    expect(chart.bars.last.color, colors['b']);
    expect(_dotColor(tester, _key('tag-a')), colors['a']);
    for (final segment in chart.timeBars.expand((bar) => bar.segments)) {
      expect(segment.color, colors[segment.key]);
    }
    await _tap(tester, 'chart-mode');
    await _tap(tester, 'tag-a');
    expect(_dotColor(tester, _key('selection')), colors['a']);
    await _tap(tester, 'all');
    expect(
      tester
          .widget<BookDurationListPage>(find.byType(BookDurationListPage))
          .bookColors,
      colors,
    );
    expect(_dotColor(tester, _key('list-row-1')), colors['a']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('滚动离开图表再返回时保留周期和下方图书列表', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              BookDurationChart(
                insights: ReadingInsights([
                  for (var i = 1; i <= 7; i++)
                    _session('$i', DateTime(2026, 11, 9, i), i * 10),
                ], now: _now),
                now: _now,
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectPeriod(tester, 'week');
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(_text(tester, 'range'), '本周 · 2026/11/9 – 2026/11/15');
    expect(_key('bars'), findsOneWidget);
    expect(_legendRows(), findsNWidgets(3));
    expect(_key('tag-other'), findsNothing);
    expect(
      tester
          .widget<VoxelDurationChart>(find.byType(VoxelDurationChart))
          .bars
          .map((bar) => bar.id),
      ['7', '6', '5', '4', '3'],
    );
  });

  testWidgets('日周月年展示对应图书、合计和占比，并阻止浏览未来', (tester) async {
    await _pump(tester, [
      _session('today', DateTime(2026, 11, 15, 8), 10),
      _session('week', DateTime(2026, 11, 9, 8), 20),
      _session('month', DateTime(2026, 11, 8, 8), 30),
      _session('quarter', DateTime(2026, 10, 1, 8), 40),
      _session('year', DateTime(2026, 9, 30, 8), 50),
      _session('previousYear', DateTime(2025, 12, 31, 8), 60),
    ]);
    for (final (period, total, count) in [
      ('day', '10 分钟', 1),
      ('week', '30 分钟', 2),
      ('month', '1 小时', 3),
      ('year', '2 小时 30 分', 5),
    ]) {
      await _selectPeriod(tester, period);
      expect(_text(tester, 'total'), total);
      expect(find.text('$count 本书'), findsOneWidget);
      expect(tester.widget<IconButton>(_key('next')).onPressed, isNull);
      expect(tester.takeException(), isNull);
    }
    await _selectPeriod(tester, 'total');
    expect(find.text('3 小时 30 分 · 阅读 6 天'), findsOneWidget);
    expect(find.text('2026年阅读最久 · 2 小时 30 分'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(_key('previous'), findsNothing);
    await _selectPeriod(tester, 'week');
    expect(_text(tester, 'value-week'), '20 分钟');
    expect(_key('tag-year'), findsNothing);
    await _selectPeriod(tester, 'day');
    expect(_text(tester, 'value-today'), '10 分钟');
    expect(_key('period-quarter'), findsNothing);
  });

  testWidgets('历史周期可往返、返回当前，刷新保留所选周期且只累计一次', (tester) async {
    final sessions = [
      _session('today', DateTime(2026, 11, 15, 8), 10),
      _session('yesterday', DateTime(2026, 11, 14, 8), 20),
    ];
    await _pump(tester, sessions);
    await _tap(tester, 'previous');
    expect(_text(tester, 'range'), '2026年11月14日');
    expect(_text(tester, 'total'), '20 分钟');
    expect(tester.widget<IconButton>(_key('previous')).onPressed, isNull);
    sessions.add(_session('yesterday', DateTime(2026, 11, 14, 10), 5));
    await _pump(tester, sessions);
    expect(_text(tester, 'range'), '2026年11月14日');
    expect(_text(tester, 'total'), '25 分钟');
    await _tap(tester, 'next');
    expect(_text(tester, 'total'), '10 分钟');
    await _tap(tester, 'previous');
    await _tap(tester, 'next');
    expect(_text(tester, 'range'), '今天 · 2026年11月15日');
    await _tap(tester, 'previous');
    await _selectPeriod(tester, 'week');
    expect(_text(tester, 'range'), '本周 · 2026/11/9 – 2026/11/15');
    expect(_text(tester, 'total'), '35 分钟');
  });

  testWidgets('无记录的周期显示空状态，历史空隙仍可往前浏览', (tester) async {
    await _pump(tester, [_session('old', DateTime(2026, 11, 13, 8), 10)]);
    expect(_key('empty'), findsOneWidget);
    expect(_key('bars'), findsNothing);
    await _tap(tester, 'previous');
    expect(_key('empty'), findsOneWidget);
    await _tap(tester, 'previous');
    expect(_text(tester, 'total'), '10 分钟');
    expect(tester.widget<IconButton>(_key('previous')).onPressed, isNull);
    await _pump(tester, []);
    expect(_key('empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('柱图前五本、列表前三本，其余不分组且更多展示同期全量书籍', (tester) async {
    await _pump(
      tester,
      [
        for (var i = 1; i <= 7; i++)
          _session('$i', DateTime(2026, 11, 15, i), i * 10),
      ],
      titles: {'7': '书架中的新书名'},
    );
    expect(_legendText('书架中的新书名'), findsOneWidget);
    expect(_text(tester, 'total'), '4 小时 40 分');
    expect(_legendRows(), findsNWidgets(3));
    expect(_key('tag-other'), findsNothing);
    expect(_key('bar-other'), findsNothing);
    expect(_key('bar-short-reading'), findsNothing);
    expect(
      tester
          .widget<VoxelDurationChart>(find.byType(VoxelDurationChart))
          .bars
          .map((bar) => bar.id),
      ['7', '6', '5', '4', '3'],
    );
    expect(_key('bar-3'), findsOneWidget);
    expect(_key('tag-3'), findsNothing);
    expect(_key('tag-4'), findsNothing);
    expect(_key('tag-1'), findsNothing);
    expect(find.text('更多 · 7 本'), findsOneWidget);
    await _tap(tester, 'all');
    expect(_key('list-page'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(_text(tester, 'list-range'), '2026年11月15日');
    expect(_text(tester, 'list-summary'), '7 本书 · 合计 4 小时 40 分');
    for (var i = 1; i <= 7; i++) {
      expect(
        find.byKey(ValueKey('stats-book-duration-list-row-$i')),
        findsOneWidget,
      );
    }
    expect(find.text('书籍 1'), findsOneWidget);
    expect(find.text('10 分钟 · 3.6%'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(_key('list-page'), findsNothing);
    expect(_text(tester, 'range'), '今天 · 2026年11月15日');
  });

  testWidgets('书目列表按周期时长排列并显示占比', (tester) async {
    await _pump(tester, [
      _session('a', DateTime(2026, 11, 15, 8), 100),
      _session('b', DateTime(2026, 11, 15, 9), 80),
      _session('c', DateTime(2026, 11, 15, 10), 60),
      _session('d', DateTime(2026, 11, 15, 11), 40),
      for (var i = 1; i <= 6; i++)
        _session('small$i', DateTime(2026, 11, 15, 12 + i ~/ 2), 10),
    ]);
    final chart = tester.getRect(_key('bars'));
    final list = tester.getRect(_key('legend'));
    expect(list.top, greaterThanOrEqualTo(chart.bottom));
    final rows = find.descendant(of: _key('legend'), matching: _legendRows());
    expect(rows, findsNWidgets(3));
    var previousBottom = chart.bottom;
    Rect? firstTag;
    for (final (id, share) in [
      ('a', '29.4%'),
      ('b', '23.5%'),
      ('c', '17.6%'),
    ]) {
      final tag = tester.getRect(_key('tag-$id'));
      firstTag ??= tag;
      expect(tag.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(tag.top, greaterThanOrEqualTo(previousBottom));
      expect(tag.left, firstTag.left);
      expect(tag.right, firstTag.right);
      expect(_text(tester, 'share-$id'), share);
      previousBottom = tag.bottom;
    }
    expect(_key('tag-d'), findsNothing);
    expect(_key('tag-other'), findsNothing);
    final voxel = tester.widget<VoxelDurationChart>(
      find.byType(VoxelDurationChart),
    );
    expect(voxel.bars.map((bar) => bar.id), ['a', 'b', 'c', 'd', 'small1']);
    expect(
      voxel.timeBars
          .expand((bar) => bar.segments)
          .map((segment) => segment.key)
          .toSet(),
      {'a', 'b', 'c', 'd', 'small1'},
    );
    expect(
      voxel.timeBars.fold(Duration.zero, (sum, bar) => sum + bar.duration),
      const Duration(minutes: 290),
    );
    await _tap(tester, 'all');
    expect(_key('list-page'), findsOneWidget);
    expect(_text(tester, 'list-summary'), '10 本书 · 合计 5 小时 40 分');
  });

  testWidgets('柱图可切换为一天时段，跨时段按分钟拆分并保留书目贡献', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(tester, [
        _session('a', DateTime(2026, 11, 15, 1), 90),
        _session('b', DateTime(2026, 11, 15, 3, 30), 40),
      ]);
      await tester.ensureVisible(_key('chart-mode'));
      await tester.tap(_key('chart-mode'));
      await tester.pump();
      expect(_key('morph'), findsOneWidget);
      await tester.pumpAndSettle();

      expect(_key('morph'), findsNothing);
      for (var hour = 0; hour < 24; hour += 2) {
        expect(_key('time-bar-$hour-${hour + 2}'), findsOneWidget);
      }
      expect(find.bySemanticsLabel('0-2 时，共 1 小时，书籍 a 1 小时'), findsOneWidget);
      expect(
        find.bySemanticsLabel('2-4 时，共 1 小时，书籍 a 30 分钟，书籍 b 30 分钟'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('4-6 时，共 10 分钟，书籍 b 10 分钟'), findsOneWidget);

      await tester.tap(_key('chart-mode'));
      await tester.pumpAndSettle();
      expect(_key('bar-a'), findsOneWidget);
      expect(_key('time-bar-0-2'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('柱图默认显示时段分布，点击切换为按书统计', (tester) async {
    await _pump(tester, [
      _session('a', DateTime(2026, 11, 15, 1), 90),
      _session('b', DateTime(2026, 11, 15, 3, 30), 40),
    ], initialTimeOfDay: true);

    expect(_key('time-bar-0-2'), findsOneWidget);
    expect(_key('bar-a'), findsNothing);
    expect(find.text('一天时段'), findsOneWidget);

    await _tap(tester, 'chart-mode');
    expect(_key('bar-a'), findsOneWidget);
    expect(_key('time-bar-0-2'), findsNothing);
    expect(find.text('总阅读时长'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('周视图的时段按周一到周日分段，不复用一天的小时', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(tester, [
        _session('a', DateTime(2026, 11, 9, 1), 60),
        _session('b', DateTime(2026, 11, 10, 3), 40),
      ]);
      await _selectPeriod(tester, 'week');
      await _tap(tester, 'chart-mode');
      expect(find.text('一周分布'), findsOneWidget);
      for (final day in ['周一', '周二', '周三', '周四', '周五', '周六', '周日']) {
        expect(_key('time-bar-$day'), findsOneWidget);
      }
      expect(_key('time-bar-0-2'), findsNothing);
      expect(find.bySemanticsLabel('周一，共 1 小时，书籍 a 1 小时'), findsOneWidget);
      expect(find.bySemanticsLabel('周二，共 40 分钟，书籍 b 40 分钟'), findsOneWidget);
      expect(find.bySemanticsLabel('周三，没有阅读记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final (date, days) in [
    (DateTime(2025, 2, 28), 28),
    (DateTime(2024, 2, 29), 29),
    (DateTime(2026, 11, 30), 30),
    (DateTime(2026, 12, 31), 31),
  ]) {
    testWidgets('月视图按自然月显示 $days 天并按午夜拆分阅读时长', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          [
            _session('a', DateTime(date.year, date.month, 0, 23, 30), 60),
            _session('b', DateTime(date.year, date.month, days, 23, 30), 60),
          ],
          now: date,
          initialTimeOfDay: true,
          bookColors: const {'a': Colors.red, 'b': Colors.blue},
        );
        await _selectPeriod(tester, 'month');
        final chart = tester.widget<VoxelDurationChart>(
          find.byType(VoxelDurationChart),
        );
        expect(chart.period, BookDurationPeriod.month);
        expect(chart.timeBars, hasLength(days));
        expect(chart.timeBars.first.duration, const Duration(minutes: 30));
        expect(chart.timeBars.last.duration, const Duration(minutes: 30));
        expect(chart.timeBars.first.segments.single.color, Colors.red);
        expect(chart.timeBars.last.segments.single.color, Colors.blue);
        expect(_text(tester, 'total'), '1 小时');
        expect(_text(tester, 'chart-value'), '2 天');
        expect(find.text('月内分布'), findsOneWidget);
        expect(find.bySemanticsLabel('1日，共 30 分钟，书籍 a 30 分钟'), findsOneWidget);
        expect(find.bySemanticsLabel('2日，没有阅读记录'), findsOneWidget);
        expect(_key('time-bar-$days日'), findsOneWidget);
        expect(_key('time-bar-${days + 1}日'), findsNothing);
        expect(_key('time-bar-0-2'), findsNothing);
        await _tap(tester, 'chart-mode');
        expect(find.byTooltip('切换为按日期分布'), findsOneWidget);
        expect(_key('bar-a'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('年视图按十二个月聚合，跨年记录分别计入对应年份', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(
        tester,
        [
          _session('a', DateTime(2025, 12, 31, 23, 30), 60),
          _session('a', DateTime(2026, 1, 20, 10), 20),
          _session('b', DateTime(2026, 6, 15, 8), 40),
          _session('b', DateTime(2026, 12, 31, 23, 30), 60),
        ],
        now: DateTime(2026, 12, 31),
        initialTimeOfDay: true,
      );
      await _selectPeriod(tester, 'year');
      final chart = tester.widget<VoxelDurationChart>(
        find.byType(VoxelDurationChart),
      );
      expect(chart.period, BookDurationPeriod.year);
      expect(chart.timeBars, hasLength(12));
      expect(chart.timeBars.first.duration, const Duration(minutes: 50));
      expect(chart.timeBars[5].duration, const Duration(minutes: 40));
      expect(chart.timeBars.last.duration, const Duration(minutes: 30));
      expect(_text(tester, 'total'), '2 小时');
      expect(_text(tester, 'chart-value'), '3 个月');
      expect(find.text('全年分布'), findsOneWidget);
      expect(find.bySemanticsLabel('1月，共 50 分钟，书籍 a 50 分钟'), findsOneWidget);
      expect(find.bySemanticsLabel('2月，没有阅读记录'), findsOneWidget);
      await _tap(tester, 'previous');
      expect(_text(tester, 'range'), '2025年');
      expect(_text(tester, 'total'), '30 分钟');
      expect(tester.widget<IconButton>(_key('previous')).onPressed, isNull);
      await _tap(tester, 'next');
      expect(_text(tester, 'range'), '今年 · 2026年');
      expect(tester.widget<IconButton>(_key('next')).onPressed, isNull);
      await _tap(tester, 'chart-mode');
      expect(find.byTooltip('切换为按月份分布'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('月视图可跨年往返、刷新保留月份并展示同期全部书籍', (tester) async {
    final sessions = [
      _session('a', DateTime(2025, 12, 31, 23, 30), 60),
      _session('b', DateTime(2026, 1, 15, 8), 20),
      _session('short', DateTime(2026, 1, 15, 9), 1),
    ];
    final now = DateTime(2026, 1, 31);
    await _pump(tester, sessions, now: now, applyThreshold: true);
    await _selectPeriod(tester, 'month');
    expect(_text(tester, 'range'), '本月 · 2026年1月');
    expect(_text(tester, 'total'), '51 分钟');
    expect(_key('tag-short'), findsNothing);
    await _tap(tester, 'all');
    expect(_text(tester, 'list-range'), '2026年1月');
    expect(_text(tester, 'list-summary'), '3 本书 · 合计 51 分钟');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await _tap(tester, 'previous');
    expect(_text(tester, 'range'), '2025年12月');
    expect(_text(tester, 'total'), '30 分钟');
    sessions.add(_session('a', DateTime(2025, 12, 30, 8), 10));
    await _pump(tester, sessions, now: now, applyThreshold: true);
    expect(_text(tester, 'range'), '2025年12月');
    expect(_text(tester, 'total'), '40 分钟');
    expect(tester.widget<IconButton>(_key('previous')).onPressed, isNull);
    await _tap(tester, 'next');
    expect(_text(tester, 'range'), '本月 · 2026年1月');
    expect(tester.widget<IconButton>(_key('next')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('月和年无记录时显示空状态，空月份仍可浏览到已有记录', (tester) async {
    await _pump(tester, [
      _session('a', DateTime(2025, 12, 15, 8), 30),
    ], now: DateTime(2026, 2, 15));
    await _selectPeriod(tester, 'year');
    expect(_key('empty'), findsOneWidget);
    await _selectPeriod(tester, 'month');
    expect(_key('empty'), findsOneWidget);
    await _tap(tester, 'previous');
    expect(_text(tester, 'range'), '2026年1月');
    expect(_key('empty'), findsOneWidget);
    await _tap(tester, 'previous');
    expect(_text(tester, 'range'), '2025年12月');
    expect(_text(tester, 'total'), '30 分钟');
    expect(tester.takeException(), isNull);
  });

  for (final period in ['day', 'week', 'month', 'year']) {
    testWidgets('320 宽、2 倍字号下 $period 柱图刻度不重叠且周期可读屏', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          [
            for (var day = 1; day <= 31; day++)
              _session('a', DateTime(2026, 10, day, 8), day),
          ],
          now: DateTime(2026, 10, 31),
          width: 320,
          scale: 2,
          initialTimeOfDay: true,
        );
        await _selectPeriod(tester, period);
        final label = {
          'day': '日',
          'week': '周',
          'month': '月',
          'year': '年',
        }[period]!;
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          matchesSemantics(
            label: label,
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            hasTapAction: true,
          ),
        );
        final ticks = switch (period) {
          'day' => [
            for (var hour = 0; hour < 24; hour += 2) '$hour-${hour + 2}',
          ],
          'week' => ['一', '二', '三', '四', '五', '六', '日'],
          'month' => ['1', '5', '10', '15', '20', '25', '31'],
          _ => [for (var month = 1; month <= 12; month++) '$month'],
        };
        Rect? previous;
        for (final tick in ticks) {
          final rect = tester.getRect(
            find.ancestor(
              of: find.descendant(of: _key('bars'), matching: find.text(tick)),
              matching: find.byType(FittedBox),
            ),
          );
          if (previous != null) {
            expect(previous.right, lessThanOrEqualTo(rect.left + .001));
          }
          previous = rect;
        }
        final lastBarKey = switch (period) {
          'week' => '周日',
          'month' => '31日',
          'year' => '12月',
          _ => ticks.last,
        };
        expect(_key('time-bar-$lastBarKey'), findsOneWidget);
        final plot = tester.getRect(_key('plot'));
        expect(tester.getRect(_key('y-axis')).right, closeTo(plot.left, .01));
        Rect? previousYTick;
        for (var index = 0; index <= 3; index++) {
          final tick = tester.getRect(
            find.ancestor(
              of: _key('y-tick-$index'),
              matching: find.byType(FittedBox),
            ),
          );
          expect(tick.right, lessThan(plot.left));
          expect(tick.top, greaterThanOrEqualTo(plot.top));
          expect(
            tester.widget<Text>(_key('y-tick-$index')).textAlign,
            TextAlign.center,
          );
          expect(
            tester
                .widget<FittedBox>(
                  find.ancestor(
                    of: _key('y-tick-$index'),
                    matching: find.byType(FittedBox),
                  ),
                )
                .alignment,
            Alignment.center,
          );
          if (previousYTick != null) {
            expect(tick.overlaps(previousYTick), isFalse);
          }
          previousYTick = tick;
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('320 宽、2 倍字号下一天时段柱图不溢出', (tester) async {
    await _pump(
      tester,
      [_session('long', DateTime(2026, 11, 15, 0), 600)],
      width: 320,
      scale: 2,
    );
    await tester.ensureVisible(_key('chart-mode'));
    await tester.tap(_key('chart-mode'));
    await tester.pumpAndSettle();
    expect(_key('time-bar-0-2'), findsOneWidget);
    expect(_key('time-bar-8-10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final count in [4, 5, 6]) {
    testWidgets('$count 本书只展示前三条，柱图最多五本，更多不丢书籍', (tester) async {
      await _pump(tester, [
        for (var i = 1; i <= count; i++)
          _session('$i', DateTime(2026, 11, 15, 8), (count + 1 - i) * 10),
      ]);
      final rows = find.descendant(of: _key('legend'), matching: _legendRows());
      expect(rows, findsNWidgets(3));
      for (var i = 1; i <= 3; i++) {
        expect(_key('tag-$i'), findsOneWidget);
      }
      expect(_key('tag-5'), findsNothing);
      expect(_key('tag-4'), findsNothing);
      expect(_key('tag-other'), findsNothing);
      expect(
        tester
            .widget<VoxelDurationChart>(find.byType(VoxelDurationChart))
            .bars
            .length,
        count < 5 ? count : 5,
      );
      await _tap(tester, 'all');
      expect(
        tester
            .widget<BookDurationListPage>(find.byType(BookDurationListPage))
            .summary
            .entries
            .length,
        count,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('少于六本书也能打开完整列表，长书名与占比可查看', (tester) async {
    const title = '一本需要完整显示的很长很长的中文图书名称';
    await _pump(
      tester,
      [
        _session('a', DateTime(2026, 11, 15, 8), 30),
        _session('b', DateTime(2026, 11, 15, 9), 10),
      ],
      titles: {'a': title},
    );
    await _tap(tester, 'all');
    expect(_key('list-page'), findsOneWidget);
    expect(
      find.descendant(of: _key('list-page'), matching: find.text(title)),
      findsOneWidget,
    );
    expect(find.text('30 分钟 · 75.0%'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'total'), '40 分钟');
  });

  testWidgets('前五和前三保留门槛，更多包含同期未达门槛书籍且无合并分组', (tester) async {
    await _pump(tester, [
      for (var index = 1; index <= 6; index++)
        _session('$index', DateTime(2026, 11, 15, 8), index * 10),
      _session('brief', DateTime(2026, 11, 15, 9), 4),
    ], applyThreshold: true);
    final voxel = tester.widget<VoxelDurationChart>(
      find.byType(VoxelDurationChart),
    );
    expect(voxel.bars.map((bar) => bar.id), ['6', '5', '4', '3', '2']);
    expect(_legendRows(), findsNWidgets(3));
    expect(_key('tag-3'), findsNothing);
    expect(_key('bar-brief'), findsNothing);
    expect(_key('bar-other'), findsNothing);
    expect(_key('bar-short-reading'), findsNothing);
    expect(find.text('短时阅读'), findsNothing);
    expect(_text(tester, 'total'), '3 小时 34 分');
    expect(find.text('更多 · 7 本'), findsOneWidget);
    await _tap(tester, 'all');
    final complete = tester.widget<BookDurationListPage>(
      find.byType(BookDurationListPage),
    );
    expect(complete.summary.entries.map((entry) => entry.bookId), [
      '6',
      '5',
      '4',
      '3',
      '2',
      '1',
      'brief',
    ]);
    expect(complete.summary.total, const Duration(minutes: 214));
    expect(tester.takeException(), isNull);
  });

  testWidgets('只有未达门槛的阅读也能从更多查看完整汇总', (tester) async {
    await _pump(tester, [
      _session('a', DateTime(2026, 11, 15, 8), 2),
      _session('b', DateTime(2026, 11, 15, 9), 3),
    ], applyThreshold: true);
    expect(_key('empty'), findsOneWidget);
    expect(_key('bars'), findsNothing);
    expect(find.text('更多 · 2 本'), findsOneWidget);
    await _tap(tester, 'all');
    final complete = tester.widget<BookDurationListPage>(
      find.byType(BookDurationListPage),
    );
    expect(complete.summary.entries.map((entry) => entry.bookId), ['b', 'a']);
    expect(complete.summary.total, const Duration(minutes: 5));
  });

  testWidgets('切换日周重新按该周期排名，更多只包含该周期的书籍', (tester) async {
    await _pump(tester, [
      for (var index = 0; index < 7; index++)
        _session('$index', DateTime(2026, 11, 15, 8), 70 - index * 10),
      _session('6', DateTime(2026, 11, 9, 8), 200),
      _session('7', DateTime(2026, 11, 9, 12), 150),
    ]);
    expect(
      tester
          .widget<VoxelDurationChart>(find.byType(VoxelDurationChart))
          .bars
          .map((bar) => bar.id),
      ['0', '1', '2', '3', '4'],
    );
    expect(_key('tag-0'), findsOneWidget);
    expect(_key('tag-6'), findsNothing);
    await _tap(tester, 'all');
    expect(
      tester
          .widget<BookDurationListPage>(find.byType(BookDurationListPage))
          .summary
          .entries
          .length,
      7,
    );
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await _selectPeriod(tester, 'week');
    expect(
      tester
          .widget<VoxelDurationChart>(find.byType(VoxelDurationChart))
          .bars
          .map((bar) => bar.id),
      ['6', '7', '0', '1', '2'],
    );
    expect(_key('tag-6'), findsOneWidget);
    expect(_key('tag-7'), findsOneWidget);
    expect(_key('tag-1'), findsNothing);
    await _tap(tester, 'all');
    expect(
      tester
          .widget<BookDurationListPage>(find.byType(BookDurationListPage))
          .summary
          .entries
          .length,
      8,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('第五根柱可选中，刷新仍在前五时保留，跌出前五后清除', (tester) async {
    final sessions = [
      for (var index = 1; index <= 6; index++)
        _session('$index', DateTime(2026, 11, 15, 8), 70 - index * 10),
    ];
    await _pump(tester, sessions);
    await _tap(tester, 'bar-5');
    expect(_key('selection'), findsOneWidget);
    await _pump(tester, sessions);
    expect(_key('selection'), findsOneWidget);
    sessions.add(_session('6', DateTime(2026, 11, 15, 12), 20));
    await _pump(tester, sessions);
    expect(_key('selection'), findsNothing);
    expect(_key('bar-5'), findsNothing);
  });

  testWidgets('点选书名或柱体显示相同详情，重复点选和切换日期清除选中', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(tester, [
        _session('a', DateTime(2026, 11, 15, 8), 30),
        _session('b', DateTime(2026, 11, 15, 9), 10),
        _session('a', DateTime(2026, 11, 14, 8), 5),
      ]);
      await _tap(tester, 'tag-a');
      expect(_text(tester, 'chart-value'), '本书占比 75.0%');
      expect(find.text('30 分钟 · 占比 75.0%'), findsOneWidget);
      expect(find.bySemanticsLabel('柱状图，书籍 a，30 分钟，占比 75.0%'), findsOneWidget);
      expect(
        tester.getSemantics(_key('tag-a')),
        matchesSemantics(
          label: '书籍 a，30 分钟，占比 75.0%',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      expect(_text(tester, 'total'), '40 分钟');
      await _tap(tester, 'tag-a');
      expect(_key('selection'), findsNothing);
      await _tap(tester, 'bar-a');
      expect(_text(tester, 'chart-value'), '本书占比 75.0%');
      await _tap(tester, 'previous');
      expect(_key('selection'), findsNothing);
      expect(_text(tester, 'total'), '5 分钟');
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('刷新后选中书籍消失时清除详情，重新出现不恢复旧选择', (tester) async {
    final sessions = [_session('a', DateTime(2026, 11, 15, 8), 30)];
    await _pump(tester, sessions);
    await _tap(tester, 'tag-a');
    expect(_key('selection'), findsOneWidget);
    await _pump(tester, []);
    expect(_key('selection'), findsNothing);
    await _pump(tester, sessions);
    expect(_key('selection'), findsNothing);
    expect(_text(tester, 'chart-value'), '1 本书');
  });

  testWidgets('书架名称改变同值排名后，刷新按实际可见书目保留或清除选择', (tester) async {
    final sessions = [
      for (final id in ['a', 'b', 'c', 'd', 'e', 'f'])
        _session(id, DateTime(2026, 11, 15, 8), 10),
    ];
    final titles = {'f': '1 排在首位的书'};
    await _pump(tester, sessions, titles: titles);
    await _tap(tester, 'tag-f');
    await _pump(tester, sessions, titles: titles);
    expect(_key('selection'), findsOneWidget);
    expect(_text(tester, 'chart-value'), '本书占比 16.7%');
    await _pump(tester, sessions);
    expect(_key('tag-f'), findsNothing);
    expect(_key('selection'), findsNothing);
    expect(_text(tester, 'chart-value'), '前 5 本 · 共 6 本');
  });

  for (final (width, scale) in [
    (320.0, 1.0),
    (320.0, 1.3),
    (320.0, 2.0),
    (800.0, 1.0),
  ]) {
    testWidgets('${width.toInt()} 宽度、$scale 倍字号可显示长书名、极小占比并提供读屏标签', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        const title = '这是一本需要完整换行显示且不会遮挡时长数字的很长的中文书名';
        await _pump(
          tester,
          [
            _session('long', DateTime(2026, 11, 15, 0), 600),
            ReadingSession(
              bookId: 'tiny',
              startedAt: DateTime(2026, 11, 15, 20),
              endedAt: DateTime(2026, 11, 15, 20, 0, 1),
              duration: const Duration(seconds: 1),
            ),
          ],
          width: width,
          scale: scale,
          titles: {'long': title},
        );
        expect(_legendText(title), findsOneWidget);
        expect(_text(tester, 'value-tiny'), '<1 分钟');
        expect(find.bySemanticsLabel('$title，10 小时，占比 100.0%'), findsOneWidget);
        final total = tester.widget<Text>(_key('total'));
        expect(total.style!.fontSize, greaterThanOrEqualTo(20));
        expect(total.style!.fontWeight, FontWeight.w600);
        final longTag = tester.getRect(_key('tag-long'));
        final bars = tester.getRect(_key('bars'));
        expect(longTag.overlaps(bars), isFalse);
        expect(_key('bar-long'), findsOneWidget);
        expect(_key('bar-tiny'), findsOneWidget);
        expect(_key('total'), findsOneWidget);
        final timeRect = tester.getRect(_key('total'));
        expect(bars.contains(timeRect.center), isTrue);
        await _tap(tester, 'tag-long');
        expect(
          find.descendant(of: _key('selection'), matching: find.text(title)),
          findsOneWidget,
        );
        expect(_text(tester, 'chart-value'), '本书占比 100.0%');
        expect(_text(tester, 'total'), '10 小时 1 分');
        await tester.ensureVisible(_key('period-day'));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.bySemanticsLabel('日')),
          matchesSemantics(
            label: '日',
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            hasTapAction: true,
          ),
        );
        await _tap(tester, 'period-week');
        expect(_text(tester, 'range'), contains('周'));
        expect(
          tester.getSemantics(find.bySemanticsLabel('周')),
          matchesSemantics(
            label: '周',
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            hasTapAction: true,
          ),
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}
