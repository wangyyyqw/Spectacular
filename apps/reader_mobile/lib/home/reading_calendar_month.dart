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
    Set<String> finishedBookIds = const {},
  }) : start = DateTime(date.year, date.month) {
    final end = DateTime(start.year, start.month + 1);
    final titles = {...insights.bookTitles, ...bookTitles};
    final totals = <DateTime, Map<String, Duration>>{};
    final monthTotals = <String, Duration>{};
    for (final portion in insights.portions) {
      if (portion.date.isBefore(start) ||
          !portion.date.isBefore(end) ||
          portion.duration <= Duration.zero) {
        continue;
      }
      final books = totals.putIfAbsent(portion.date, () => {});
      books[portion.bookId] =
          (books[portion.bookId] ?? Duration.zero) + portion.duration;
      monthTotals[portion.bookId] =
          (monthTotals[portion.bookId] ?? Duration.zero) + portion.duration;
    }
    days = Map.unmodifiable({
      for (final day in totals.entries)
        day.key: _entries(day.value, titles, insights.visibleBookIds),
    });
    dayDurations = Map.unmodifiable({
      for (final day in totals.entries)
        day.key: day.value.values.fold(
          Duration.zero,
          (sum, value) => sum + value,
        ),
    });
    monthBooks = _entries(monthTotals, titles, insights.visibleBookIds);
    total = monthTotals.values.fold(
      Duration.zero,
      (sum, duration) => sum + duration,
    );
    bookCount = monthBooks.length;
    final lastDays = <String, DateTime>{};
    for (final portion in insights.portions) {
      if (portion.duration <= Duration.zero ||
          !insights.visibleBookIds.contains(portion.bookId) ||
          !finishedBookIds.contains(portion.bookId)) {
        continue;
      }
      final last = lastDays[portion.bookId];
      if (last == null || portion.date.isAfter(last)) {
        lastDays[portion.bookId] = portion.date;
      }
    }
    finishDays = Map.unmodifiable(lastDays);
  }

  static const maxVisibleBooks = 4;

  final DateTime start;
  late final Map<DateTime, List<BookDurationEntry>> days;
  late final Map<DateTime, Duration> dayDurations;
  late final List<BookDurationEntry> monthBooks;
  late final Duration total;
  late final int bookCount;

  /// 已读完书目的完读日，取最后一次有效阅读所在日期（库内无完读时间）。
  late final Map<String, DateTime> finishDays;

  int get offset => start.weekday % 7;
  int get dayCount => DateTime(start.year, start.month + 1, 0).day;
  int get weekCount => (offset + dayCount + 6) ~/ 7;
  DateTime dateAt(int week, int column) =>
      DateTime(start.year, start.month, week * 7 + column - offset + 1);

  /// 单日保留阅读时长最多的四本，连续条带按跨度优先排在上方。
  List<ReadingCalendarSpan> spansForWeek(int week) {
    final spans = <ReadingCalendarSpan>[];
    var previous = <String, ReadingCalendarSpan>{};
    for (var column = 0; column < 7; column++) {
      final current = _daySpans(
        days[dateAt(week, column)] ?? const [],
        column,
        previous,
      );
      for (final span in current) {
        if (span.firstColumn < column) spans.remove(previous[span.bookId]);
        spans.add(span);
      }
      previous = {for (final span in current) span.bookId: span};
    }
    return _orderSpans(spans);
  }
}

List<ReadingCalendarSpan> _orderSpans(List<ReadingCalendarSpan> spans) {
  final ordered = spans.toList()
    ..sort((a, b) {
      final length = (b.lastColumn - b.firstColumn).compareTo(
        a.lastColumn - a.firstColumn,
      );
      if (length != 0) return length;
      final start = a.firstColumn.compareTo(b.firstColumn);
      return start != 0 ? start : a.lane.compareTo(b.lane);
    });
  final laneCount = spans.fold(
    0,
    (count, span) => span.lane >= count ? span.lane + 1 : count,
  );
  final lanes = _spanLanes(ordered, laneCount);
  final laneBySpan = {
    for (var index = 0; index < ordered.length; index++)
      ordered[index]: lanes[index],
  };
  return [
    for (final span in spans)
      ReadingCalendarSpan(
        bookId: span.bookId,
        title: span.title,
        firstColumn: span.firstColumn,
        lastColumn: span.lastColumn,
        lane: laneBySpan[span]!,
      ),
  ];
}

List<int> _spanLanes(List<ReadingCalendarSpan> spans, int laneCount) {
  final occupied = List.filled(laneCount, 0);
  final lanes = List.filled(spans.length, 0);
  bool assign(int index) {
    if (index == spans.length) return true;
    final span = spans[index];
    final mask =
        ((1 << (span.lastColumn - span.firstColumn + 1)) - 1) <<
        span.firstColumn;
    for (var lane = 0; lane < laneCount; lane++) {
      if (occupied[lane] & mask != 0) continue;
      occupied[lane] |= mask;
      lanes[index] = lane;
      if (assign(index + 1)) return true;
      occupied[lane] ^= mask;
    }
    return false;
  }

  assign(0);
  return lanes;
}

List<BookDurationEntry> _entries(
  Map<String, Duration> durations,
  Map<String, String> titles,
  Set<String> visibleBookIds,
) => List<BookDurationEntry>.unmodifiable(
  <BookDurationEntry>[
    for (final entry in durations.entries)
      if (visibleBookIds.contains(entry.key))
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

List<ReadingCalendarSpan> _daySpans(
  List<BookDurationEntry> books,
  int column,
  Map<String, ReadingCalendarSpan> previous,
) {
  const limit = ReadingCalendarMonth.maxVisibleBooks;
  final visible = books.take(limit);
  final available = {for (var lane = 0; lane < limit; lane++) lane};
  final lanes = <String, int>{};
  for (final book in visible) {
    final lane = previous[book.bookId]?.lane;
    if (lane != null && available.remove(lane)) lanes[book.bookId] = lane;
  }
  for (final book in visible.where((book) => !lanes.containsKey(book.bookId))) {
    lanes[book.bookId] = available.first;
    available.remove(available.first);
  }
  return [
    for (final book in visible)
      ReadingCalendarSpan(
        bookId: book.bookId,
        title: book.title,
        firstColumn: previous[book.bookId]?.lane == lanes[book.bookId]
            ? previous[book.bookId]!.firstColumn
            : column,
        lastColumn: column,
        lane: lanes[book.bookId]!,
      ),
  ];
}
