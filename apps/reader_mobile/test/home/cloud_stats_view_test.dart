import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/cloud_stats_view.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';

void main() {
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

    expect(find.text('阅微唯一数据源'), findsOneWidget);
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

    await tester.tap(
      find.byKey(const ValueKey<String>('cloud-stats-book-21')),
    );
    expect(opened?.cloudBookId, 21);
  });
}

ReaMicroPeriodStats _period({required int day, required int total}) {
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
    bookCount: 1,
    finishedBookCount: 0,
    continuousReadDays: 1,
    averageDailyDurationSeconds: total,
    topBooks: const <ReaMicroTopBook>[],
    listeningDurationSeconds: 0,
    readingDurationSeconds: total,
  );
}
