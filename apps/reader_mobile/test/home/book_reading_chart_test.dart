import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_reading_chart.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/theme/reader_common_widgets.dart';

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

  for (final scale in [1.0, 2.0]) {
    testWidgets('320 宽、$scale 倍字号保留完整标题和图表空间', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: BookReadingChart(
                        endDate: DateTime(2026, 11, 22),
                        durations: const [
                          Duration(minutes: 2),
                          Duration(minutes: 12),
                          Duration(minutes: 6),
                          Duration(hours: 2, minutes: 30),
                          Duration(minutes: 9),
                          Duration(minutes: 25),
                          Duration(minutes: 14),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final card = find.byKey(const ValueKey('book-detail-reading-chart'));
        expect(find.byType(ReaderSectionCard), findsOneWidget);
        final bounds = tester.getRect(card);
        expect(bounds.height, scale == 1 ? 166 : greaterThan(166));
        final title = tester.getRect(find.text('最近 7 天'));
        final subtitle = tester.getRect(find.text('每日阅读时长'));
        expect(bounds.contains(title.topLeft), isTrue);
        expect(bounds.contains(title.bottomRight), isTrue);
        expect(bounds.contains(subtitle.topLeft), isTrue);
        expect(bounds.contains(subtitle.bottomRight), isTrue);
        expect(title.overlaps(subtitle), isFalse);
        final chart = find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.painter != null,
          ),
        );
        expect(chart, findsOneWidget);
        expect(tester.getSize(chart).height, greaterThan(100));
        expect(
          find.bySemanticsLabel(RegExp('横轴 11/16 至 11/22')),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RegExp('纵轴 0 至 2时30分')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('14 分钟')), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });
  }
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
