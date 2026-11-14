import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      '1 小时',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-weekday-petal-value-2')),
          )
          .data,
      '30 分钟',
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
      '1 小时',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-weekday-petal-value-1')),
          )
          .data,
      '1 小时',
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
}
