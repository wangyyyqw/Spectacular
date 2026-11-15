import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/hourly_reading_chart.dart';
import 'package:reader_mobile/home/reading_insights.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';

ReadingSession _session({
  String bookId = 'a',
  required DateTime start,
  required Duration duration,
}) => ReadingSession(
  bookId: bookId,
  startedAt: start,
  endedAt: start.add(duration),
  duration: duration,
);

Future<void> _pumpChart(
  WidgetTester tester,
  ReadingInsights insights,
  DateTime date, {
  double width = 360,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1200));
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
            child: HourlyReadingChart(insights: insights, date: date),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('跨小时会话按墙上时间比例分摊且总时长守恒', () {
    final insights = ReadingInsights([
      _session(
        start: DateTime(2026, 11, 10, 9, 30),
        duration: const Duration(minutes: 90),
      ),
    ], now: DateTime(2026, 11, 15));

    final hours = hourlyReadingDurations(insights, DateTime(2026, 11, 10));

    expect(hours[9], const Duration(minutes: 30));
    expect(hours[10], const Duration(minutes: 60));
    expect(
      hours.fold<Duration>(Duration.zero, (sum, duration) => sum + duration),
      const Duration(minutes: 90),
    );
  });

  test('只累计目标日期，并保留跨午夜拆分后的当日份额', () {
    final insights = ReadingInsights([
      ReadingSession(
        bookId: 'a',
        startedAt: DateTime(2026, 11, 10, 23, 30),
        endedAt: DateTime(2026, 11, 11, 0, 30),
        duration: const Duration(hours: 1),
      ),
      _session(
        start: DateTime(2026, 11, 11, 14),
        duration: const Duration(minutes: 20),
      ),
    ], now: DateTime(2026, 11, 15));

    final first = hourlyReadingDurations(insights, DateTime(2026, 11, 10));
    final second = hourlyReadingDurations(insights, DateTime(2026, 11, 11));

    expect(first[23], const Duration(minutes: 30));
    expect(
      first.fold<Duration>(Duration.zero, (sum, duration) => sum + duration),
      const Duration(minutes: 30),
    );
    expect(second[0], const Duration(minutes: 30));
    expect(second[14], const Duration(minutes: 20));
    expect(
      second.fold<Duration>(Duration.zero, (sum, duration) => sum + duration),
      const Duration(minutes: 50),
    );
  });

  testWidgets('小时图显示 24 个小时，默认选中最长时段并可点击切换', (tester) async {
    final insights = ReadingInsights([
      _session(
        start: DateTime(2026, 11, 10, 9, 30),
        duration: const Duration(minutes: 90),
      ),
      _session(
        start: DateTime(2026, 11, 10, 20),
        duration: const Duration(minutes: 15),
      ),
    ], now: DateTime(2026, 11, 15));
    await _pumpChart(tester, insights, DateTime(2026, 11, 10));

    expect(
      find.byKey(const ValueKey<String>('stats-hourly-reading-chart')),
      findsOneWidget,
    );
    for (var hour = 0; hour < 24; hour++) {
      expect(
        find.byKey(ValueKey<String>('stats-hourly-label-$hour')),
        findsOneWidget,
      );
    }
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-hourly-selected-hour')),
          )
          .data,
      '10 时',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey<String>('stats-hourly-selected-duration'),
            ),
          )
          .data,
      '1 小时',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-hourly-total')),
          )
          .data,
      '合计 1 小时 45 分',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('stats-hourly-label-20')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-hourly-selected-hour')),
          )
          .data,
      '20 时',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey<String>('stats-hourly-selected-duration'),
            ),
          )
          .data,
      '15 分钟',
    );
  });

  testWidgets('空日期保留完整小时结构并显示空状态', (tester) async {
    final insights = ReadingInsights(const [], now: DateTime(2026, 11, 15));
    await _pumpChart(tester, insights, DateTime(2026, 11, 10));

    for (var hour = 0; hour < 24; hour++) {
      expect(
        find.byKey(ValueKey<String>('stats-hourly-label-$hour')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('stats-hourly-empty')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey<String>('stats-hourly-selected-duration'),
            ),
          )
          .data,
      '0 分钟',
    );
  });

  testWidgets('窄屏大字号不溢出', (tester) async {
    final insights = ReadingInsights([
      _session(
        start: DateTime(2026, 11, 10, 23),
        duration: const Duration(minutes: 45),
      ),
    ], now: DateTime(2026, 11, 15));
    await _pumpChart(
      tester,
      insights,
      DateTime(2026, 11, 10),
      width: 320,
      textScale: 1.6,
    );

    expect(
      find.byKey(const ValueKey<String>('stats-hourly-reading-chart')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
