import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_reading_chart.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';

void main() {
  test('最近 7 天按日期升序汇总目标书籍', () {
    final now = DateTime(2026, 11, 22, 20);
    final durations = recentBookReadingDurations(
      <ReadingSession>[
        _session('book-a', DateTime(2026, 11, 20, 10), 15),
        _session('book-b', DateTime(2026, 11, 20, 11), 90),
        _session('book-a', DateTime(2026, 11, 22, 9), 30),
        _session('book-a', DateTime(2026, 11, 14, 9), 120),
      ],
      bookId: 'book-a',
      now: now,
    );

    expect(durations, const <Duration>[
      Duration.zero,
      Duration.zero,
      Duration.zero,
      Duration.zero,
      Duration(minutes: 15),
      Duration.zero,
      Duration(minutes: 30),
    ]);
  });

  testWidgets('单折线图显示最近 7 天阅读时长语义', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: BookReadingChart(
              endDate: DateTime(2026, 11, 22),
              durations: const <Duration>[
                Duration(minutes: 2),
                Duration(minutes: 12),
                Duration(minutes: 6),
                Duration(minutes: 18),
                Duration(minutes: 9),
                Duration(minutes: 25),
                Duration(minutes: 14),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('book-detail-reading-chart')),
      findsOneWidget,
    );
    expect(find.text('最近 7 天'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('横轴 11/16 至 11/22')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('纵轴 0 至 25分')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('14 分钟')),
      findsOneWidget,
      reason: '语义摘要应包含最近一天的阅读时长',
    );
    semantics.dispose();
  });
}

ReadingSession _session(String bookId, DateTime startedAt, int minutes) {
  final endedAt = startedAt.add(Duration(minutes: minutes));
  return ReadingSession(
    bookId: bookId,
    startedAt: startedAt,
    endedAt: endedAt,
    duration: endedAt.difference(startedAt),
  );
}
