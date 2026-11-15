import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_duration_chart.dart';
import 'package:reader_mobile/home/reading_insights.dart';
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
}) async {
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
            insights: ReadingInsights(sessions, now: _now),
            now: _now,
            bookTitles: titles,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String suffix) =>
    find.byKey(ValueKey('stats-book-duration-$suffix'));
String _text(WidgetTester tester, String suffix) =>
    tester.widget<Text>(_key(suffix)).data!;

Future<void> _tap(WidgetTester tester, String suffix) async {
  await tester.ensureVisible(_key(suffix));
  await tester.tap(_key(suffix));
  await tester.pumpAndSettle();
}

void main() {
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
                    _session('$i', DateTime(2026, 10, 1, i), i * 10),
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
    await _tap(tester, 'period-quarter');
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(_text(tester, 'range'), '本季度 · 2026年 第4季度');
    expect(_key('ring'), findsOneWidget);
    expect(_key('tag-other'), findsOneWidget);
  });

  testWidgets('五种周期展示对应图书、合计和占比，并阻止浏览未来', (tester) async {
    await _pump(tester, [
      _session('today', DateTime(2026, 11, 15, 8), 10),
      _session('week', DateTime(2026, 11, 9, 8), 20),
      _session('month', DateTime(2026, 11, 8, 8), 30),
      _session('quarter', DateTime(2026, 10, 1, 8), 40),
      _session('year', DateTime(2026, 9, 30, 8), 50),
    ]);
    for (final (period, total, count) in [
      ('day', '10 分钟', 1),
      ('week', '30 分钟', 2),
      ('month', '1 小时', 3),
      ('quarter', '1 小时 40 分', 4),
      ('year', '2 小时 30 分', 5),
    ]) {
      await _tap(tester, 'period-$period');
      expect(_text(tester, 'total'), total);
      expect(find.text('$count 本书'), findsOneWidget);
      expect(tester.widget<IconButton>(_key('next')).onPressed, isNull);
      expect(tester.takeException(), isNull);
    }
    await _tap(tester, 'period-quarter');
    expect(_text(tester, 'value-quarter'), '40 分钟');
    expect(_key('tag-year'), findsNothing);
    await _tap(tester, 'period-day');
    expect(_text(tester, 'value-today'), '10 分钟');
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
    await _tap(tester, 'current');
    expect(_text(tester, 'range'), '今天 · 2026年11月15日');
    await _tap(tester, 'previous');
    await _tap(tester, 'period-quarter');
    expect(_text(tester, 'range'), '本季度 · 2026年 第4季度');
    expect(_text(tester, 'total'), '35 分钟');
  });

  testWidgets('无记录的周期显示空状态，历史空隙仍可往前浏览', (tester) async {
    await _pump(tester, [_session('old', DateTime(2026, 11, 13, 8), 10)]);
    expect(_key('empty'), findsOneWidget);
    expect(_key('ring'), findsNothing);
    await _tap(tester, 'previous');
    expect(_key('empty'), findsOneWidget);
    await _tap(tester, 'previous');
    expect(_text(tester, 'total'), '10 分钟');
    expect(tester.widget<IconButton>(_key('previous')).onPressed, isNull);
    await _pump(tester, []);
    expect(_key('empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多书合并其他，点击后进入当前周期完整时长列表', (tester) async {
    await _pump(
      tester,
      [
        for (var i = 1; i <= 7; i++)
          _session('$i', DateTime(2026, 11, 15, i), i * 10),
      ],
      titles: {'7': '书架中的新书名'},
    );
    expect(find.text('书架中的新书名'), findsOneWidget);
    expect(_text(tester, 'total'), '4 小时 40 分');
    expect(find.text('其他3本'), findsOneWidget);
    expect(_text(tester, 'value-other'), '1 小时');
    expect(_key('tag-1'), findsNothing);
    await _tap(tester, 'tag-other');
    expect(_key('list-page'), findsOneWidget);
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
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_text(tester, 'range'), '今天 · 2026年11月15日');
  });

  testWidgets('四本书和其他按顺序左对齐排列在圆环下方，时长占比可见', (tester) async {
    await _pump(tester, [
      _session('a', DateTime(2026, 11, 15, 8), 100),
      _session('b', DateTime(2026, 11, 15, 9), 80),
      _session('c', DateTime(2026, 11, 15, 10), 60),
      _session('d', DateTime(2026, 11, 15, 11), 40),
      for (var i = 1; i <= 6; i++)
        _session('small$i', DateTime(2026, 11, 15, 12 + i ~/ 2), 10),
    ]);
    final ring = tester.getRect(_key('ring'));
    final list = tester.getRect(_key('legend'));
    expect(list.top, greaterThanOrEqualTo(ring.bottom));
    final rows = find.descendant(
      of: _key('legend'),
      matching: find.byType(InkWell),
    );
    expect(rows, findsNWidgets(5));
    var previousBottom = ring.bottom;
    for (final (id, share) in [
      ('a', '29.4%'),
      ('b', '23.5%'),
      ('c', '17.6%'),
      ('d', '11.8%'),
      ('other', '17.6%'),
    ]) {
      final tag = tester.getRect(_key('tag-$id'));
      expect(tag.top, greaterThanOrEqualTo(previousBottom));
      expect(tag.left, list.left);
      expect(tag.right, list.right);
      expect(_text(tester, 'share-$id'), '占比 $share');
      previousBottom = tag.bottom;
    }
    expect(_text(tester, 'value-other'), '1 小时');
    final other = _key('tag-other');
    await tester.ensureVisible(other);
    await tester.tap(other);
    await tester.pumpAndSettle();
    expect(_key('list-page'), findsOneWidget);
    expect(_text(tester, 'list-summary'), '10 本书 · 合计 5 小时 40 分');
  });

  for (final count in [4, 5, 6]) {
    testWidgets('$count 本书最多展示四本书名，第五本起合并为其他', (tester) async {
      await _pump(tester, [
        for (var i = 1; i <= count; i++)
          _session('$i', DateTime(2026, 11, 15, 8), (count + 1 - i) * 10),
      ]);
      final rows = find.descendant(
        of: _key('legend'),
        matching: find.byType(InkWell),
      );
      expect(rows, findsNWidgets(count == 4 ? 4 : 5));
      for (var i = 1; i <= 4; i++) {
        expect(_key('tag-$i'), findsOneWidget);
      }
      expect(_key('tag-5'), findsNothing);
      if (count == 4) {
        expect(_key('tag-other'), findsNothing);
      } else {
        expect(find.text('其他${count - 4}本'), findsOneWidget);
        expect(_text(tester, 'value-other'), count == 5 ? '10 分钟' : '30 分钟');
        await _tap(tester, 'tag-other');
        expect(find.text('书籍 5'), findsOneWidget);
      }
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
    expect(find.text(title), findsOneWidget);
    expect(find.text('30 分钟 · 75.0%'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_text(tester, 'total'), '40 分钟');
  });

  testWidgets('点选书名或扇区显示相同详情，重复点选和切换日期清除选中', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(tester, [
        _session('a', DateTime(2026, 11, 15, 8), 30),
        _session('b', DateTime(2026, 11, 15, 9), 10),
        _session('a', DateTime(2026, 11, 14, 8), 5),
      ]);
      await _tap(tester, 'tag-a');
      expect(_text(tester, 'ring-value'), '本书占比 75.0%');
      expect(find.text('30 分钟 · 占比 75.0%'), findsOneWidget);
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
      final ring = tester.getRect(_key('ring'));
      await tester.tapAt(Offset(ring.right - 9, ring.center.dy));
      await tester.pumpAndSettle();
      expect(_text(tester, 'ring-value'), '本书占比 75.0%');
      await _tap(tester, 'previous');
      expect(_key('selection'), findsNothing);
      expect(_text(tester, 'total'), '5 分钟');
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('历史选择器跨空档跳转、按周期去重，并保留历史日期', (tester) async {
    await _pump(tester, [
      _session('a', DateTime(2026, 11, 15, 8), 30),
      _session('b', DateTime(2025, 2, 18, 8), 10),
      _session('b', DateTime(2025, 2, 18, 10), 15),
      _session('future', DateTime(2027, 1, 1, 8), 5),
    ]);
    await _tap(tester, 'pick-period');
    expect(find.byType(ListTile), findsNWidgets(2));
    await _tap(tester, 'history-${DateTime(2025, 2, 18).toIso8601String()}');
    expect(_text(tester, 'range'), '2025年2月18日');
    expect(_text(tester, 'total'), '25 分钟');
    for (final period in ['week', 'month', 'quarter', 'year', 'day']) {
      await _tap(tester, 'period-$period');
      expect(_text(tester, 'total'), '25 分钟');
    }
    expect(_text(tester, 'range'), '2025年2月18日');
    await _tap(tester, 'current');
    expect(_text(tester, 'range'), '今天 · 2026年11月15日');
    expect(tester.takeException(), isNull);
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
    expect(_text(tester, 'ring-value'), '1 本书');
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
    expect(_text(tester, 'ring-value'), '本书占比 16.7%');
    await _pump(tester, sessions);
    expect(_key('tag-f'), findsNothing);
    expect(_key('selection'), findsNothing);
    expect(_text(tester, 'ring-value'), '6 本书');
  });

  testWidgets('历史选择器取消不改变日期，空记录也能返回当前周期', (tester) async {
    await _pump(tester, []);
    await _tap(tester, 'pick-period');
    expect(find.byType(ListTile), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(_key('period-picker'), findsNothing);
    expect(_text(tester, 'range'), '今天 · 2026年11月15日');
    expect(_key('empty'), findsOneWidget);
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
        expect(find.text(title), findsOneWidget);
        expect(_text(tester, 'value-tiny'), '<1 分钟');
        expect(find.bySemanticsLabel('$title，10 小时，占比 100.0%'), findsOneWidget);
        final total = tester.widget<Text>(_key('total'));
        expect(total.style!.fontSize, greaterThanOrEqualTo(24));
        final longTag = tester.getRect(_key('tag-long'));
        final ring = tester.getRect(_key('ring'));
        expect(longTag.overlaps(ring), isFalse);
        expect(_key('total'), findsOneWidget);
        final timeRect = tester.getRect(_key('total'));
        expect(timeRect.center.dx, closeTo(ring.center.dx, .01));
        expect(timeRect.left, greaterThan(ring.left + 18));
        expect(timeRect.right, lessThan(ring.right - 18));
        expect(timeRect.top, greaterThan(ring.top + 18));
        expect(timeRect.bottom, lessThan(ring.bottom - 18));
        await _tap(tester, 'tag-long');
        expect(
          find.descendant(of: _key('selection'), matching: find.text(title)),
          findsOneWidget,
        );
        expect(_text(tester, 'ring-value'), '本书占比 100.0%');
        expect(_text(tester, 'total'), '10 小时 1 分');
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
        await _tap(tester, 'period-quarter');
        expect(
          tester.getSemantics(find.bySemanticsLabel('季度')),
          matchesSemantics(
            label: '季度',
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
