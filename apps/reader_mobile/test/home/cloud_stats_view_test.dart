import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/cloud_stats_view.dart';
import 'package:reader_mobile/home/cloud_reading_calendar.dart';
import 'package:reader_mobile/home/weekday_average_chart.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';

void main() {
  testWidgets('静默刷新期间滚动偏移与内容位置保持不变', (tester) async {
    final snapshot = _snapshot(_period(day: 3, total: 3600));
    Widget page(bool loading) => MaterialApp(
      home: Scaffold(
        body: CloudStatsView(
          stats: snapshot,
          linkedCloudBookIds: const {},
          loading: loading,
          onRefresh: () async {},
          onOpenBook: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(page(false));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final offset = scrollable.position.pixels;
    final extent = scrollable.position.maxScrollExtent;
    await tester.pumpWidget(page(true));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(scrollable.position.pixels, offset);
    expect(scrollable.position.maxScrollExtent, extent);
    await tester.pumpWidget(page(false));
    await tester.pump();
    expect(scrollable.position.pixels, offset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史月份自动刷新保留已有内容直到响应返回', (tester) async {
    final pending = Completer<ReaMicroPeriodStats>();
    var calls = 0;
    Widget page(ReaMicroCloudStats stats) => MaterialApp(
      home: Scaffold(
        body: CloudReadingCalendar(
          stats: stats,
          onLoadMonth: (_) async {
            if (++calls == 1) return _period(day: 7, total: 7200, books: 4);
            return pending.future;
          },
        ),
      ),
    );
    await tester.pumpWidget(page(_snapshot(_period(day: 3, total: 3600))));
    await tester.tap(find.byKey(const ValueKey('stats-calendar-previous')));
    await tester.pumpAndSettle();
    expect(find.text('1 天阅读 · 4 本 · 2 小时'), findsOneWidget);
    final height = tester.getSize(find.byType(CloudReadingCalendar)).height;
    await tester.pumpWidget(page(_snapshot(_period(day: 3, total: 5400))));
    await tester.pump();
    expect(find.text('1 天阅读 · 4 本 · 2 小时'), findsOneWidget);
    expect(tester.getSize(find.byType(CloudReadingCalendar)).height, height);
    pending.complete(_period(day: 7, total: 10800, books: 4));
    await tester.pumpAndSettle();
    expect(find.text('1 天阅读 · 4 本 · 3 小时'), findsOneWidget);
  });

  testWidgets('云日历使用真实月度本数和每日阅读听书汇总', (tester) async {
    final month = _period(day: 3, total: 20 * 3600, books: 23);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CloudReadingCalendar(stats: _snapshot(month))),
      ),
    );
    expect(find.text('1 天阅读 · 23 本 · 20 小时'), findsOneWidget);
    expect(find.text('阅微阅读'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('cloud-calendar-day-2026-11-3')),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026年11月3日'), findsOneWidget);
    expect(find.text('合计 20 小时'), findsOneWidget);
    expect(find.text('阅读 20 小时'), findsOneWidget);
    expect(find.text('听书 0 分钟'), findsOneWidget);
  });

  testWidgets('历史月份请求乱序完成时保留最后选择的月份', (tester) async {
    final october = Completer<ReaMicroPeriodStats>();
    final september = Completer<ReaMicroPeriodStats>();
    final requests = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudReadingCalendar(
            stats: _snapshot(_period(day: 3, total: 60)),
            onLoadMonth: (date) {
              requests.add(date);
              return date.month == 10 ? october.future : september.future;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('stats-calendar-previous')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('stats-calendar-previous')));
    await tester.pump();
    september.complete(_period(day: 7, total: 7200, books: 4));
    await tester.pumpAndSettle();
    october.complete(_period(day: 1, total: 3600, books: 2));
    await tester.pumpAndSettle();
    expect(requests, [DateTime(2026, 10), DateTime(2026, 9)]);
    expect(find.text('2026年9月'), findsOneWidget);
    expect(find.text('1 天阅读 · 4 本 · 2 小时'), findsOneWidget);
  });

  testWidgets('历史月份失败可以重试且不会显示当前月数据', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudReadingCalendar(
            stats: _snapshot(_period(day: 3, total: 7200)),
            onLoadMonth: (_) async {
              if (++calls == 1) throw Exception('离线');
              return _period(day: 1, total: 3600, books: 2);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('stats-calendar-previous')));
    await tester.pumpAndSettle();
    expect(find.text('该月阅读记录加载失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('stats-calendar-summary')), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('1 天阅读 · 2 本 · 1 小时'), findsOneWidget);
  });

  testWidgets('云端每日平均不把超过十二小时的总量拆到次日', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudStatsView(
            stats: _snapshot(_period(day: 3, total: 20 * 3600)),
            linkedCloudBookIds: const {},
            loading: false,
            onRefresh: () async {},
            onOpenBook: (_) {},
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('stats-weekday-average-chart')),
      300,
    );
    final chart = tester.widget<WeekdayAverageChart>(
      find.byType(WeekdayAverageChart),
    );
    expect(chart.dailyTotals, {
      DateTime(2026, 11, 3): const Duration(hours: 20),
    });
    expect(chart.insights.sessions, isEmpty);
  });

  testWidgets('云端统计展示概览、周期趋势和已关联书籍', (tester) async {
    ReaMicroBookRecord? opened;
    final stats = ReaMicroCloudStats(
      overview: const ReaMicroOverview(
        years: <int>[2025, 2026],
        readDays: 42,
        totalDurationSeconds: 7200,
        bookCount: 3,
        finishedBookCount: 1,
        registerTimestamp: 0,
        topBooks: <ReaMicroTopBook>[],
        listeningDurationSeconds: 1200,
        readingDurationSeconds: 6000,
      ),
      week: _period(day: 17, total: 1800),
      month: _period(day: 18, total: 3600),
      year: const ReaMicroPeriodStats(
        days: <ReaMicroDayDuration>[],
        months: <ReaMicroMonthDuration>[
          ReaMicroMonthDuration(
            month: 11,
            durationSeconds: 5400,
            listeningDurationSeconds: 600,
            readingDurationSeconds: 4800,
          ),
        ],
        readDays: 8,
        totalDurationSeconds: 5400,
        bookCount: 2,
        finishedBookCount: 1,
        continuousReadDays: 3,
        averageDailyDurationSeconds: 675,
        topBooks: <ReaMicroTopBook>[
          ReaMicroTopBook(
            cover: '',
            name: '本月常用书',
            durationSeconds: 3600,
            bookId: '21',
            readDays: 4,
            listeningDurationSeconds: 0,
            readingDurationSeconds: 3600,
          ),
        ],
        listeningDurationSeconds: 600,
        readingDurationSeconds: 4800,
      ),
      chart: const <ReaMicroChartPoint>[
        ReaMicroChartPoint(
          day: '2026-11-18',
          durationSeconds: 1800,
          readingDurationSeconds: 1500,
          listeningDurationSeconds: 300,
        ),
      ],
      books: const <ReaMicroBookRecord>[
        ReaMicroBookRecord(
          bookId: 8,
          cloudBookId: 21,
          name: '云端书',
          author: '作者',
          cover: '',
          progress: 0.6,
          totalReadTimeSeconds: 7200,
          readDays: 5,
          finishReadTime: 0,
          listeningDurationSeconds: 0,
          readingDurationSeconds: 7200,
        ),
      ],
      fetchedAt: DateTime(2026, 11, 18, 12, 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudStatsView(
            stats: stats,
            linkedCloudBookIds: const <int>{21},
            loading: false,
            onRefresh: () async {},
            onOpenBook: (record) => opened = record,
          ),
        ),
      ),
    );

    expect(find.text('阅微唯一数据源'), findsNothing);
    expect(find.text('阅读概览'), findsOneWidget);
    expect(find.text('累计阅读'), findsOneWidget);
    expect(find.text('2 小时'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('cloud-stats-book-21')),
      300,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('cloud-stats-book-21')),
    );
    await tester.pumpAndSettle();
    expect(find.text('云端书'), findsWidgets);
    expect(find.text('已关联本地书籍，可打开'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('cloud-stats-book-21')));
    expect(opened?.cloudBookId, 21);
  });
}

ReaMicroPeriodStats _period({
  required int day,
  required int total,
  int books = 1,
}) {
  return ReaMicroPeriodStats(
    days: <ReaMicroDayDuration>[
      ReaMicroDayDuration(
        day: day,
        durationSeconds: total,
        listeningDurationSeconds: 0,
        readingDurationSeconds: total,
      ),
    ],
    months: const <ReaMicroMonthDuration>[],
    readDays: 1,
    totalDurationSeconds: total,
    bookCount: books,
    finishedBookCount: 0,
    continuousReadDays: 1,
    averageDailyDurationSeconds: total,
    topBooks: const <ReaMicroTopBook>[],
    listeningDurationSeconds: 0,
    readingDurationSeconds: total,
  );
}

ReaMicroCloudStats _snapshot(ReaMicroPeriodStats month) => ReaMicroCloudStats(
  overview: const ReaMicroOverview(
    years: [],
    readDays: 1,
    totalDurationSeconds: 7200,
    bookCount: 23,
    finishedBookCount: 0,
    registerTimestamp: 0,
    topBooks: [],
    listeningDurationSeconds: 0,
    readingDurationSeconds: 7200,
  ),
  week: month,
  month: month,
  year: month,
  chart: const [],
  books: const [],
  fetchedAt: DateTime(2026, 11, 20),
);
