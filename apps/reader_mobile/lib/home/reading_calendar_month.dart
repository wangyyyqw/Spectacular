import 'book_duration_summary.dart';
import 'reading_insights.dart';

/// 一本书在同一周内连续阅读的日期条带，首尾列均包含在内。
class ReadingCalendarSpan {
  const ReadingCalendarSpan({
    required this.bookId,
    required this.title,
    required this.firstColumn,
    required this.lastColumn,
    required this.lane,
  });

  final String bookId;
  final String title;
  final int firstColumn;
  final int lastColumn;
  final int lane;
}

/// 按本地自然日汇总书目；复用已跨午夜拆分的有效会话。
class ReadingCalendarMonth {
  ReadingCalendarMonth(
    ReadingInsights insights, {
    required DateTime date,
    Map<String, String> bookTitles = const {},
  }) : start = DateTime(date.year, date.month) {
    final end = DateTime(start.year, start.month + 1);
    final totals = <DateTime, Map<String, Duration>>{};
    for (final portion in insights.portions) {
      if (portion.date.isBefore(start) ||
          !portion.date.isBefore(end) ||
          portion.duration <= Duration.zero) {
        continue;
      }
      final books = totals.putIfAbsent(portion.date, () => {});
      books[portion.bookId] =
          (books[portion.bookId] ?? Duration.zero) + portion.duration;
    }
    days = Map.unmodifiable({
      for (final day in totals.entries)
        day.key: _entries(day.value, {...insights.bookTitles, ...bookTitles}),
    });
    final entries = days.values.expand((entries) => entries);
    total = entries.fold(Duration.zero, (sum, entry) => sum + entry.duration);
    bookCount = entries.map((entry) => entry.bookId).toSet().length;
  }

  final DateTime start;
  late final Map<DateTime, List<BookDurationEntry>> days;
  late final Duration total;
  late final int bookCount;

  int get offset => start.weekday % 7;
  int get dayCount => DateTime(start.year, start.month + 1, 0).day;
  int get weekCount => (offset + dayCount + 6) ~/ 7;
  DateTime dateAt(int week, int column) =>
      DateTime(start.year, start.month, week * 7 + column - offset + 1);

  /// 连续条带先按起始日、长度和书籍身份排序，再放入最早可用行。
  List<ReadingCalendarSpan> spansForWeek(int week) {
    final columns = <String, List<int>>{};
    final titles = <String, String>{};
    for (var column = 0; column < 7; column++) {
      for (final book in days[dateAt(week, column)] ?? <BookDurationEntry>[]) {
        columns.putIfAbsent(book.bookId, () => []).add(column);
        titles[book.bookId] = book.title;
      }
    }
    final runs =
        <({String id, int first, int last})>[
          for (final entry in columns.entries) ..._runs(entry.key, entry.value),
        ]..sort((a, b) {
          final first = a.first.compareTo(b.first);
          if (first != 0) return first;
          final length = (b.last - b.first).compareTo(a.last - a.first);
          return length == 0 ? a.id.compareTo(b.id) : length;
        });
    final laneEnds = <int>[];
    return [for (final run in runs) _place(run, titles[run.id]!, laneEnds)];
  }
}

List<BookDurationEntry> _entries(
  Map<String, Duration> durations,
  Map<String, String> titles,
) => List<BookDurationEntry>.unmodifiable(
  <BookDurationEntry>[
    for (final entry in durations.entries)
      BookDurationEntry(
        bookId: entry.key,
        title: titles[entry.key] ?? '已移出书架的书籍',
        duration: entry.value,
      ),
  ]..sort((a, b) {
    final duration = b.duration.compareTo(a.duration);
    return duration == 0 ? a.bookId.compareTo(b.bookId) : duration;
  }),
);

Iterable<({String id, int first, int last})> _runs(
  String id,
  List<int> columns,
) sync* {
  var first = columns.first;
  var last = first;
  for (final column in columns.skip(1)) {
    if (column != last + 1) {
      yield (id: id, first: first, last: last);
      first = column;
    }
    last = column;
  }
  yield (id: id, first: first, last: last);
}

ReadingCalendarSpan _place(
  ({String id, int first, int last}) run,
  String title,
  List<int> laneEnds,
) {
  var lane = laneEnds.indexWhere((last) => last < run.first);
  if (lane == -1) {
    lane = laneEnds.length;
    laneEnds.add(run.last);
  } else {
    laneEnds[lane] = run.last;
  }
  return ReadingCalendarSpan(
    bookId: run.id,
    title: title,
    firstColumn: run.first,
    lastColumn: run.last,
    lane: lane,
  );
}
