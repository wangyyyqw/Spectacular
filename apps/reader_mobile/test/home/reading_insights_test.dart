import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reading_insights.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';

ReadingSession _session(
  String book,
  DateTime start,
  Duration duration, {
  int pages = 0,
  int characters = 0,
}) => ReadingSession(
  bookId: book,
  startedAt: start,
  endedAt: start.add(duration),
  duration: duration,
  pageTurns: pages,
  charactersRead: characters,
);

void main() {
  test('摘要界面移除后仍可读取今日、累计、逐日时长和翻页字数接口', () {
    final stats = ReadingInsights([
      _session(
        'a',
        DateTime(2026, 11, 15, 9),
        const Duration(minutes: 12),
        pages: 12,
        characters: 400,
      ),
      _session(
        'a',
        DateTime(2026, 11, 14, 9),
        const Duration(minutes: 30),
        pages: 8,
        characters: 300,
      ),
      _session(
        'b',
        DateTime(2026, 11, 5, 9),
        const Duration(minutes: 45),
        pages: 5,
        characters: 200,
      ),
    ], now: DateTime(2026, 11, 15));
    expect(stats.todayReading, const Duration(minutes: 12));
    expect(stats.totalReading, const Duration(minutes: 87));
    expect(stats.byDay, {
      DateTime(2026, 11, 15): const Duration(minutes: 12),
      DateTime(2026, 11, 14): const Duration(minutes: 30),
      DateTime(2026, 11, 5): const Duration(minutes: 45),
    });
    expect(stats.pageTurns, 25);
    expect(stats.charactersRead, 900);
  });

  test('一小时及跨多日会话分段不溢出，日统计和时段统计与累计守恒', () {
    for (final duration in [
      const Duration(hours: 1),
      const Duration(hours: 36),
    ]) {
      final session = _session(
        'long',
        DateTime(2026, 11, 11, 23),
        duration,
        pages: 36,
        characters: 54321,
      );
      final stats = ReadingInsights([session], now: DateTime(2026, 11, 13));
      expect(
        stats.portions.every((part) => part.duration > Duration.zero),
        isTrue,
      );
      expect(
        stats.byDay.values.fold(Duration.zero, (sum, value) => sum + value),
        duration,
      );
      expect(
        stats.readingPeriods.fold(Duration.zero, (sum, value) => sum + value),
        duration,
      );
      expect(stats.byBook['long']!.duration, duration);
      expect(
        stats.portions.fold<int>(0, (sum, part) => sum + part.pageTurns),
        36,
      );
      expect(
        stats.portions.fold<int>(0, (sum, part) => sum + part.charactersRead),
        54321,
      );
    }
  });

  test('跨午夜的时长、翻页和字数按自然日分配且累计守恒', () {
    final session = _session(
      'a',
      DateTime(2026, 11, 11, 23, 50),
      const Duration(minutes: 20),
      pages: 5,
      characters: 101,
    );
    final stats = ReadingInsights([session], now: DateTime(2026, 11, 12, 8));
    expect(stats.byDay[DateTime(2026, 11, 11)], const Duration(minutes: 10));
    expect(stats.todayReading, const Duration(minutes: 10));
    expect(stats.portions.fold<int>(0, (sum, part) => sum + part.pageTurns), 5);
    expect(
      stats.portions.fold<int>(0, (sum, part) => sum + part.charactersRead),
      101,
    );
    expect(stats.portions.every((part) => part.estimatedCounts), isTrue);
    expect(stats.portions.map((part) => part.session).toSet(), {session});
    expect(
      stats.readingPeriods.fold<Duration>(
        Duration.zero,
        (sum, duration) => sum + duration,
      ),
      stats.totalReading,
    );
    expect(stats.currentStreak, 2);
    expect(stats.longestStreak, 2);
  });

  test('连续阅读从今天或昨天计算，日均、单次与按书汇总来自有效会话', () {
    final stats = ReadingInsights([
      _session('a', DateTime(2026, 11, 8, 19), const Duration(minutes: 10)),
      _session(
        'a',
        DateTime(2026, 11, 9, 20),
        const Duration(minutes: 20),
        pages: 2,
        characters: 400,
      ),
      _session(
        'b',
        DateTime(2026, 11, 11, 21),
        const Duration(minutes: 30),
        pages: 3,
        characters: 500,
      ),
    ], now: DateTime(2026, 11, 12));
    expect(stats.currentStreak, 1);
    expect(stats.longestStreak, 2);
    expect(stats.averageDay, const Duration(minutes: 20));
    expect(stats.averageSession, const Duration(minutes: 20));
    expect(stats.longestSession, const Duration(minutes: 30));
    expect(stats.preferredPeriod, 3);
    expect(stats.readingPeriods, [
      Duration.zero,
      Duration.zero,
      Duration.zero,
      const Duration(hours: 1),
    ]);
    expect(stats.charactersPerMinute, 15);
    expect(stats.byBook['a']!.sessions, 2);
    expect(stats.byBook['a']!.duration, const Duration(minutes: 30));
  });

  test('热力图移除后逐日片段仍保留书籍、时段、次数来源与阅读计数', () {
    final date = DateTime(2026, 11, 15);
    final first = _session(
      'a',
      DateTime(2026, 11, 15, 9),
      const Duration(minutes: 30),
      pages: 12,
      characters: 400,
    );
    final second = _session(
      'b',
      DateTime(2026, 11, 15, 14),
      const Duration(minutes: 15),
      pages: 3,
      characters: 100,
    );
    final stats = ReadingInsights([first, second], now: date);
    final portions = stats.portions.where((part) => part.date == date).toList();
    expect(stats.byDay[date], const Duration(minutes: 45));
    expect(portions.map((part) => part.session).toSet(), {first, second});
    expect(portions.map((part) => part.bookId), ['a', 'b']);
    expect(portions.first.startedAt, first.startedAt);
    expect(portions.first.endedAt, first.endedAt);
    expect(portions.first.duration, first.duration);
    expect(portions.fold<int>(0, (sum, part) => sum + part.pageTurns), 15);
    expect(
      portions.fold<int>(0, (sum, part) => sum + part.charactersRead),
      500,
    );
  });

  test('无效会话不污染时长，未翻页时不显示虚假的速度', () {
    final time = DateTime(2026, 11, 12);
    final stats = ReadingInsights([
      ReadingSession(
        bookId: 'bad',
        startedAt: time,
        endedAt: time,
        duration: const Duration(minutes: 30),
        pageTurns: 5,
      ),
      _session('negative', time, const Duration(minutes: -5)),
      _session(
        'a',
        time,
        const Duration(seconds: 30),
        pages: -1,
        characters: -10,
      ),
    ], now: time);
    expect(stats.sessions, hasLength(1));
    expect(stats.totalReading, const Duration(seconds: 30));
    expect(stats.pageTurns, 0);
    expect(stats.charactersRead, 0);
    expect(stats.charactersPerMinute, isNull);
  });
}
