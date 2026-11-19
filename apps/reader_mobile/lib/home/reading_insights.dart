import '../storage/reading_session_store.dart';

/// 书籍详情与书评时长只计入不少于该时长的阅读会话。
const minimumCountedSessionDuration = Duration(minutes: 5);
const minimumCountedDayDuration = Duration(minutes: 5);

/// 一次会话在某个自然日内的有效部分。
class ReadingDayPortion {
  const ReadingDayPortion({
    required this.session,
    required this.startedAt,
    required this.endedAt,
    required this.duration,
    required this.pageTurns,
    required this.charactersRead,
    required this.estimatedCounts,
  });

  final ReadingSession session;
  String get bookId => session.bookId;
  final DateTime startedAt;
  final DateTime endedAt;
  final Duration duration;
  final int pageTurns;
  final int charactersRead;
  final bool estimatedCounts;

  DateTime get date => DateTime(startedAt.year, startedAt.month, startedAt.day);
}

/// 一本书的累计实际阅读记录。
class BookReadingTotals {
  Duration duration = Duration.zero;
  int sessions = 0;
  int pageTurns = 0;
  int charactersRead = 0;
  DateTime? lastEndedAt;

  void add(ReadingSession session) {
    duration += session.duration;
    sessions++;
    pageTurns += _nonNegative(session.pageTurns);
    charactersRead += _nonNegative(session.charactersRead);
    final last = lastEndedAt;
    if (last == null || session.endedAt.isAfter(last)) {
      lastEndedAt = session.endedAt;
    }
  }
}

/// 由有效会话构建的统计快照，保留逐日明细和阅读习惯接口供统计功能复用。
class ReadingInsights {
  ReadingInsights(
    Iterable<ReadingSession> input, {
    required DateTime now,
    Duration minimumDayDuration = Duration.zero,
  }) {
    final validSessions = input
        .where(
          (session) =>
              session.duration > Duration.zero &&
              session.endedAt.isAfter(session.startedAt),
        )
        .toList(growable: false);
    final allPortions = validSessions.expand(_splitByDay).toList();
    for (final portion in allPortions) {
      byDay[portion.date] =
          (byDay[portion.date] ?? Duration.zero) + portion.duration;
    }
    byDay.removeWhere((_, duration) => duration < minimumDayDuration);
    portions = allPortions
        .where((portion) => byDay.containsKey(portion.date))
        .toList(growable: false);
    sessions = _sessionsForPortions(portions);
    for (final session in sessions) {
      totalReading += session.duration;
      if (session.duration > longestSession) longestSession = session.duration;
      byBook.putIfAbsent(session.bookId, BookReadingTotals.new).add(session);
      final title = session.bookTitle?.trim();
      if (title != null && title.isNotEmpty) bookTitles[session.bookId] = title;
    }
    for (final portion in portions) {
      _addReadingPeriods(portion);
    }
    final today = DateTime(now.year, now.month, now.day);
    todayReading = byDay[today] ?? Duration.zero;
    final days = byDay.keys.toList()..sort();
    longestStreak = _longestStreak(days);
    currentStreak = _currentStreak(days, today);
  }

  late final List<ReadingSession> sessions;
  late final List<ReadingDayPortion> portions;
  final Map<DateTime, Duration> byDay = {};
  final Map<String, BookReadingTotals> byBook = {};
  final Map<String, String> bookTitles = {};
  final List<Duration> readingPeriods = List.filled(4, Duration.zero);
  Duration totalReading = Duration.zero;
  Duration todayReading = Duration.zero;
  Duration longestSession = Duration.zero;
  int longestStreak = 0;
  int currentStreak = 0;

  int get pageTurns =>
      byBook.values.fold(0, (sum, book) => sum + book.pageTurns);
  int get charactersRead =>
      byBook.values.fold(0, (sum, book) => sum + book.charactersRead);
  Duration get averageDay => _average(totalReading, byDay.length);
  Duration get averageSession => _average(totalReading, sessions.length);
  int? get charactersPerMinute =>
      charactersRead > 0 && totalReading.inMinutes >= 1
      ? (charactersRead / (totalReading.inMilliseconds / 60000)).round()
      : null;

  int? get preferredPeriod {
    if (totalReading == Duration.zero) return null;
    var best = 0;
    for (var i = 1; i < readingPeriods.length; i++) {
      if (readingPeriods[i] > readingPeriods[best]) best = i;
    }
    return best;
  }

  void _addReadingPeriods(ReadingDayPortion portion) {
    var cursor = portion.startedAt;
    final end = portion.endedAt;
    while (cursor.isBefore(end)) {
      var boundary = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        (cursor.hour ~/ 6 + 1) * 6,
      );
      if (!boundary.isAfter(cursor)) {
        boundary = cursor.add(const Duration(hours: 6));
      }
      final next = end.isBefore(boundary) ? end : boundary;
      final period = cursor.hour ~/ 6;
      readingPeriods[period] += _scaledDuration(portion.session, cursor, next);
      cursor = next;
    }
  }
}

List<ReadingSession> _sessionsForPortions(List<ReadingDayPortion> portions) {
  final bySession = <ReadingSession, List<ReadingDayPortion>>{};
  for (final portion in portions) {
    bySession.putIfAbsent(portion.session, () => []).add(portion);
  }
  return bySession.entries
      .map((entry) {
        final session = entry.key;
        final kept = entry.value;
        final duration = kept.fold(
          Duration.zero,
          (sum, part) => sum + part.duration,
        );
        if (duration == session.duration) return session;
        return ReadingSession(
          bookId: session.bookId,
          bookTitle: session.bookTitle,
          startedAt: kept.first.startedAt,
          endedAt: kept.last.endedAt,
          duration: duration,
          pageTurns: kept.fold(0, (sum, part) => sum + part.pageTurns),
          charactersRead: kept.fold(
            0,
            (sum, part) => sum + part.charactersRead,
          ),
        );
      })
      .toList(growable: false);
}

Duration _average(Duration total, int count) => count == 0
    ? Duration.zero
    : Duration(microseconds: total.inMicroseconds ~/ count);

/// 跨午夜的计数按时长分配并守恒；不把整段翻页字数重复记入两天。
Iterable<ReadingDayPortion> _splitByDay(ReadingSession session) sync* {
  var cursor = session.startedAt.toLocal();
  final end = session.endedAt.toLocal();
  final span = end.difference(cursor).inMicroseconds;
  final countPages = _nonNegative(session.pageTurns);
  final countChars = _nonNegative(session.charactersRead);
  var pages = 0;
  var characters = 0;
  final lastDate = end.subtract(const Duration(microseconds: 1));
  final split = _dayNumber(cursor) != _dayNumber(lastDate);
  while (cursor.isBefore(end)) {
    final midnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
    final next = end.isBefore(midnight) ? end : midnight;
    final fraction = next.difference(session.startedAt).inMicroseconds / span;
    final nextPages = (countPages * fraction).round();
    final nextChars = (countChars * fraction).round();
    yield ReadingDayPortion(
      session: session,
      startedAt: cursor,
      endedAt: next,
      duration: _scaledDuration(session, cursor, next),
      pageTurns: nextPages - pages,
      charactersRead: nextChars - characters,
      estimatedCounts: split,
    );
    pages = nextPages;
    characters = nextChars;
    cursor = next;
  }
}

Duration _scaledDuration(ReadingSession session, DateTime start, DateTime end) {
  final span = session.endedAt.difference(session.startedAt).inMicroseconds;
  // 先除后乘，避免一小时级会话的两个微秒整数相乘溢出。
  int cumulative(DateTime time) =>
      (session.duration.inMicroseconds *
              (time.difference(session.startedAt).inMicroseconds / span))
          .round();
  return Duration(microseconds: cumulative(end) - cumulative(start));
}

int _nonNegative(int value) => value < 0 ? 0 : value;

/// 用日历日期比较连续天数，避免夏令时的 23/25 小时日破坏连续记录。
int _dayNumber(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

int _longestStreak(List<DateTime> days) {
  var current = 0;
  var longest = 0;
  int? previous;
  for (final day in days) {
    final number = _dayNumber(day);
    current = previous == number - 1 ? current + 1 : 1;
    if (current > longest) longest = current;
    previous = number;
  }
  return longest;
}

int _currentStreak(List<DateTime> days, DateTime today) {
  final numbers = days.map(_dayNumber).toSet();
  var cursor = _dayNumber(today);
  if (!numbers.contains(cursor)) cursor--;
  var count = 0;
  while (numbers.contains(cursor)) {
    count++;
    cursor--;
  }
  return count;
}

String formatReadingDuration(Duration duration) {
  if (duration <= Duration.zero) {
    return '0 分钟';
  }
  if (duration.inSeconds < 60) {
    return '<1 分钟';
  }
  final minutes = (duration.inSeconds / 60).ceil();
  if (minutes < 60) {
    return '$minutes 分钟';
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
}
