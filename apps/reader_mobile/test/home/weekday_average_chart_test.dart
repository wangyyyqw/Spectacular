import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/hourly_reading_chart.dart';
import 'package:reader_mobile/home/reading_insights.dart';
import 'package:reader_mobile/home/weekday_average_chart.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';

ReadingSession _session(DateTime start, Duration duration) => ReadingSession(
  bookId: 'a',
  startedAt: start,
  endedAt: start.add(duration),
  duration: duration,
);

Future<void> _pumpChart(
  WidgetTester tester,
  ReadingInsights insights, {
  double width = 360,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: WeekdayAverageChart(insights: insights),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('云端逐日汇总使用本机真实记录显示小时分布', (tester) async {
    final date = DateTime(2026, 11, 3);
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekdayAverageChart(
            insights: ReadingInsights(const [], now: date),
            dailyTotals: {date: const Duration(hours: 2)},
            onLoadHourlyInsights: () async {
              loads++;
              return ReadingInsights([
                _session(
                  DateTime(2026, 11, 3, 9, 30),
                  const Duration(hours: 1),
                ),
              ], now: date);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 0);
    await tester.tap(find.byKey(const ValueKey('stats-weekday-open-hourly')));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(
      find.byKey(const ValueKey('stats-hourly-reading-chart')),
      findsOneWidget,
    );
    expect(find.text('合计 1 小时'), findsOneWidget);
    expect(find.text('阅微当日累计 2 小时\n小时分布来自本机阅读记录'), findsOneWidget);
    final chart = tester.widget<HourlyReadingChart>(
      find.byType(HourlyReadingChart),
    );
    final durations = hourlyReadingDurations(chart.insights, date);
    expect(durations[9], const Duration(minutes: 30));
    expect(durations[10], const Duration(minutes: 30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('按星期汇总实际阅读日均并允许切换选中日', (tester) async {
    const duration = Duration(minutes: 60);
    final insights = ReadingInsights([
      _session(DateTime(2026, 11, 2, 9), duration),
      _session(DateTime(2026, 11, 9, 9), duration),
      _session(DateTime(2026, 11, 3, 9), const Duration(minutes: 30)),
    ], now: DateTime(2026, 11, 14));
    await _pumpChart(tester, insights);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-weekday-petal-value-1')),
          )
          .data,
      '1\n小时',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-weekday-petal-value-2')),
          )
          .data,
      '30\n分钟',
    );
    final label = find.byKey(const ValueKey<String>('stats-weekday-label-2'));
    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-weekday-detail-label')),
          )
          .data,
      '周二日均',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-weekday-detail-days')),
          )
          .data,
      '1 个阅读日',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-weekday-detail-value')),
          )
          .data,
      '30 分钟',
    );
  });

  testWidgets('跨午夜记录分摊到两个星期且空记录不生成花瓣', (tester) async {
    final insights = ReadingInsights([
      ReadingSession(
        bookId: 'a',
        startedAt: DateTime(2026, 11, 8, 23),
        endedAt: DateTime(2026, 11, 9, 1),
        duration: const Duration(hours: 2),
      ),
    ], now: DateTime(2026, 11, 14));
    await _pumpChart(tester, insights);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-weekday-petal-value-0')),
          )
          .data,
      '1\n小时',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-weekday-petal-value-1')),
          )
          .data,
      '1\n小时',
    );
    expect(
      find.byKey(const ValueKey<String>('stats-weekday-petal-value-2')),
      findsNothing,
    );
  });

  testWidgets('中心显示全部阅读日的总日均', (tester) async {
    final insights = ReadingInsights([
      _session(DateTime(2026, 11, 2, 9), const Duration(minutes: 72)),
      _session(DateTime(2026, 11, 3, 9), const Duration(minutes: 48)),
    ], now: DateTime(2026, 11, 14));
    await _pumpChart(tester, insights);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-weekday-average-value')),
          )
          .data,
      '1小时',
    );
  });

  testWidgets('窄屏大字号不溢出，空数据保留完整星期结构', (tester) async {
    final insights = ReadingInsights(const [], now: DateTime(2026, 11, 14));
    await _pumpChart(tester, insights, width: 320, textScale: 1.6);

    expect(
      find.byKey(const ValueKey<String>('stats-weekday-average-chart')),
      findsOneWidget,
    );
    for (var weekday = 0; weekday < 7; weekday++) {
      expect(
        find.byKey(ValueKey<String>('stats-weekday-label-$weekday')),
        findsOneWidget,
      );
    }
    expect(find.text('还没有阅读记录，开始阅读后会在这里按星期汇总。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击有阅读记录的星期花瓣进入最近阅读日的小时图', (tester) async {
    final insights = ReadingInsights([
      _session(DateTime(2026, 11, 2, 9), const Duration(hours: 1)),
      _session(DateTime(2026, 11, 9, 9), const Duration(minutes: 30)),
    ], now: DateTime(2026, 11, 15));
    await _pumpChart(tester, insights);

    final button = tester.getCenter(
      find.byKey(const ValueKey<String>('stats-weekday-petal-surface')),
    );
    final angle = 2 * math.pi / 7;
    await tester.tapAt(
      button + Offset(70 * math.sin(angle), -70 * math.cos(angle)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HourlyReadingPage), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-hourly-page-date')),
          )
          .data,
      '2026年11月9日 · 周一',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-hourly-total')),
          )
          .data,
      '合计 30 分钟',
    );
  });

  testWidgets('七个星期花瓣分别进入最近阅读日的小时图', (tester) async {
    final insights = ReadingInsights([
      for (var weekday = 0; weekday < 7; weekday++)
        _session(
          DateTime(2026, 11, 2 + (weekday + 6) % 7, 9),
          const Duration(minutes: 10),
        ),
    ], now: DateTime(2026, 11, 15));
    await _pumpChart(tester, insights);

    final center = tester.getCenter(
      find.byKey(const ValueKey<String>('stats-weekday-petal-surface')),
    );
    const labels = <String>['日', '一', '二', '三', '四', '五', '六'];
    for (var index = 0; index < 7; index++) {
      final angle = index * 2 * math.pi / 7;
      await tester.tapAt(
        center + Offset(70 * math.sin(angle), -70 * math.cos(angle)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HourlyReadingPage), findsOneWidget);
      final date = DateTime(2026, 11, 2 + (index + 6) % 7);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('stats-hourly-page-date')),
            )
            .data,
        '${date.year}年${date.month}月${date.day}日 · 周${labels[index]}',
      );

      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(HourlyReadingPage), findsNothing);
    }
  });

  testWidgets('窄屏双倍字号下小时分布入口随选中星期切换并打开最近阅读日', (tester) async {
    const duration = Duration(hours: 12, minutes: 34);
    final insights = ReadingInsights([
      _session(DateTime(2026, 11, 2, 9), duration),
      _session(DateTime(2026, 11, 9, 9), duration),
      _session(DateTime(2026, 11, 10, 9), const Duration(minutes: 30)),
    ], now: DateTime(2026, 11, 15));
    await _pumpChart(tester, insights, width: 320, textScale: 2);
    final action = find.byKey(const ValueKey('stats-weekday-open-hourly'));
    await tester.tap(find.byKey(const ValueKey('stats-weekday-label-2')));
    await tester.pumpAndSettle();
    expect(find.text('最近阅读日 11月10日'), findsOneWidget);
    expect(action, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stats-weekday-label-3')));
    await tester.pumpAndSettle();
    expect(action, findsNothing);

    await tester.tap(find.byKey(const ValueKey('stats-weekday-label-1')));
    await tester.pumpAndSettle();
    expect(find.text('最近阅读日 11月9日'), findsOneWidget);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byType(HourlyReadingPage), findsOneWidget);
    expect(find.text('2026年11月9日 · 周一'), findsOneWidget);
    expect(find.text('合计 12 小时 34 分'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
