import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_duration_summary.dart';
import 'package:reader_mobile/home/reading_insights.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';

ReadingSession _session(String id, DateTime start, int minutes) =>
    ReadingSession(
      bookId: id,
      bookTitle: '历史书名 $id',
      startedAt: start,
      endedAt: start.add(Duration(minutes: minutes)),
      duration: Duration(minutes: minutes),
    );

void main() {
  test('榜单保留门槛，全量汇总可查看未达门槛书籍且总时长一致', () {
    final now = DateTime(2026, 11, 15, 20);
    final insights = ReadingInsights(
      [
        _session('shown', DateTime(2026, 11, 15, 8), 10),
        _session('brief', DateTime(2026, 11, 15, 9), 4),
        _session('old', DateTime(2026, 11, 8, 9), 30),
      ],
      now: now,
      minimumBookDayDuration: minimumDisplayedBookDayDuration,
    );
    for (final period in [BookDurationPeriod.day, BookDurationPeriod.week]) {
      final ranked = BookDurationSummary(insights, period: period, date: now);
      final complete = BookDurationSummary(
        insights,
        period: period,
        date: now,
        applyBookThreshold: false,
      );
      expect(ranked.entries.map((entry) => entry.bookId), ['shown']);
      expect(complete.entries.map((entry) => entry.bookId), ['shown', 'brief']);
      expect(ranked.totalBookCount, 2);
      expect(complete.totalBookCount, 2);
      expect(ranked.total, const Duration(minutes: 14));
      expect(complete.total, ranked.total);
    }
  });

  test('书目按任一单日超过五分钟展示，历史秒级阅读和隐藏书目时长均不丢失', () {
    final now = DateTime(2026, 11, 21, 12);
    final shortStart = DateTime(2026, 11, 20, 8);
    final insights = ReadingInsights(
      [
        ReadingSession(
          bookId: 'shown',
          startedAt: shortStart,
          endedAt: shortStart.add(const Duration(seconds: 3)),
          duration: const Duration(seconds: 3),
        ),
        _session('shown', DateTime(2026, 11, 21, 8), 6),
        _session('hidden', DateTime(2026, 11, 20, 9), 4),
        _session('hidden', DateTime(2026, 11, 21, 9), 4),
      ],
      now: now,
      minimumBookDayDuration: minimumDisplayedBookDayDuration,
    );
    final month = BookDurationSummary(
      insights,
      period: BookDurationPeriod.month,
      date: now,
    );
    expect(month.entries.single.bookId, 'shown');
    expect(
      month.entries.single.duration,
      const Duration(minutes: 6, seconds: 3),
    );
    expect(month.total, const Duration(minutes: 14, seconds: 3));
    final yesterday = BookDurationSummary(
      insights,
      period: BookDurationPeriod.day,
      date: shortStart,
    );
    expect(yesterday.entries.single.duration, const Duration(seconds: 3));
    expect(yesterday.total, const Duration(minutes: 4, seconds: 3));
  });

  test('五种周期只计入各自自然边界内的阅读时长', () {
    final now = DateTime(2026, 11, 15, 20);
    final insights = ReadingInsights([
      _session('today', DateTime(2026, 11, 15, 8), 10),
      _session('week', DateTime(2026, 11, 9, 8), 20),
      _session('month', DateTime(2026, 11, 8, 8), 30),
      _session('quarter', DateTime(2026, 10, 1, 8), 40),
      _session('year', DateTime(2026, 9, 30, 8), 50),
      _session('past', DateTime(2025, 12, 31, 8), 60),
    ], now: now);
    for (final (period, minutes) in [
      (BookDurationPeriod.day, 10),
      (BookDurationPeriod.week, 30),
      (BookDurationPeriod.month, 60),
      (BookDurationPeriod.quarter, 100),
      (BookDurationPeriod.year, 150),
    ]) {
      final summary = BookDurationSummary(insights, period: period, date: now);
      expect(summary.total, Duration(minutes: minutes), reason: period.label);
      expect(
        summary.entries.first.duration >= summary.entries.last.duration,
        isTrue,
      );
    }
  });

  for (final (start, periods) in [
    (
      DateTime(2026, 11, 15, 23, 30),
      [BookDurationPeriod.day, BookDurationPeriod.week],
    ),
    (
      DateTime(2026, 3, 31, 23, 30),
      [BookDurationPeriod.month, BookDurationPeriod.quarter],
    ),
    (DateTime(2026, 12, 31, 23, 30), [BookDurationPeriod.year]),
  ]) {
    test(
      '跨越 ${periods.map((period) => period.label).join('/')} 边界按有效时长分摊且守恒',
      () {
        final session = ReadingSession(
          bookId: 'cross',
          startedAt: start,
          endedAt: start.add(const Duration(hours: 1)),
          duration: const Duration(minutes: 20),
        );
        final insights = ReadingInsights([session], now: session.endedAt);
        for (final period in periods) {
          final before = BookDurationSummary(
            insights,
            period: period,
            date: start,
          );
          final after = BookDurationSummary(
            insights,
            period: period,
            date: session.endedAt,
          );
          expect(before.entries.single.duration, const Duration(minutes: 10));
          expect(after.entries.single.duration, const Duration(minutes: 10));
          expect(before.total + after.total, session.duration);
        }
      },
    );
  }

  test('跨年周、闰日、月末与季度前后切换不漂移', () {
    const week = BookDurationPeriod.week;
    expect(week.startOf(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
    expect(week.rangeLabel(DateTime(2026, 12, 28)), '2026/12/28 – 2027/1/3');
    expect(
      BookDurationPeriod.day.shift(DateTime(2024, 2, 28), 1),
      DateTime(2024, 2, 29),
    );
    const month = BookDurationPeriod.month;
    final start = month.startOf(DateTime(2024, 3, 31));
    expect(month.shift(start, -1), DateTime(2024, 2));
    expect(month.shift(month.shift(start, -1), 1), start);
    const quarter = BookDurationPeriod.quarter;
    expect(quarter.startOf(DateTime(2026, 12, 31)), DateTime(2026, 10));
    expect(quarter.shift(DateTime(2026, 10), 1), DateTime(2027));
    expect(quarter.shift(DateTime(2026), -1), DateTime(2025, 10));
    expect(quarter.rangeLabel(DateTime(2026, 10)), '2026年 第4季度');
  });

  test('同名书不合并，优先使用书架书名且保留移出书架的历史记录', () {
    final now = DateTime(2026, 11, 15);
    final insights = ReadingInsights([
      _session('a', now, 10),
      _session('a', now.add(const Duration(hours: 1)), 20),
      _session('b', now.add(const Duration(hours: 2)), 30),
      _session('removed', now.add(const Duration(hours: 3)), 5),
    ], now: now);
    final summary = BookDurationSummary(
      insights,
      period: BookDurationPeriod.day,
      date: now,
      bookTitles: {'a': '同名书', 'b': '同名书'},
    );
    expect(summary.entries.map((entry) => entry.bookId), ['a', 'b', 'removed']);
    expect(summary.entries.map((entry) => entry.title), [
      '同名书',
      '同名书',
      '历史书名 removed',
    ]);
    expect(summary.entries.first.duration, const Duration(minutes: 30));
    expect(summary.total, const Duration(minutes: 65));
  });

  test('空周期、零时长与无效会话不产生图书占比', () {
    final now = DateTime(2026, 11, 15);
    final insights = ReadingInsights([
      _session('old', DateTime(2026, 11, 14, 9), 10),
      _session('zero', now, 0),
      _session('invalid', now, -10),
    ], now: now);
    final summary = BookDurationSummary(
      insights,
      period: BookDurationPeriod.day,
      date: now,
    );
    expect(summary.entries, isEmpty);
    expect(summary.total, Duration.zero);
  });
}
