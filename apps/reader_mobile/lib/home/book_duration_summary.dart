import 'reading_insights.dart';

/// 图书时长按本地自然日、周、月、季度或年汇总，周一为一周起点。
enum BookDurationPeriod {
  day('日', '今天'),
  week('周', '本周'),
  month('月', '本月'),
  quarter('季度', '本季度'),
  year('年', '今年');

  const BookDurationPeriod(this.label, this.currentLabel);

  final String label;
  final String currentLabel;

  DateTime startOf(DateTime date) {
    final local = date.toLocal();
    return switch (this) {
      day => DateTime(local.year, local.month, local.day),
      week => DateTime(local.year, local.month, local.day - local.weekday + 1),
      month => DateTime(local.year, local.month),
      quarter => DateTime(local.year, (local.month - 1) ~/ 3 * 3 + 1),
      year => DateTime(local.year),
    };
  }

  /// 用日历偏移，避免月末、闰年及夏令时改变周期边界。
  DateTime shift(DateTime start, int offset) => switch (this) {
    day => DateTime(start.year, start.month, start.day + offset),
    week => DateTime(start.year, start.month, start.day + offset * 7),
    month => DateTime(start.year, start.month + offset),
    quarter => DateTime(start.year, start.month + offset * 3),
    year => DateTime(start.year + offset),
  };

  String rangeLabel(DateTime start) {
    final last = shift(start, 1).subtract(const Duration(microseconds: 1));
    return switch (this) {
      day => '${start.year}年${start.month}月${start.day}日',
      week => '${_dateLabel(start)} – ${_dateLabel(last)}',
      month => '${start.year}年${start.month}月',
      quarter => '${start.year}年 第${(start.month - 1) ~/ 3 + 1}季度',
      year => '${start.year}年',
    };
  }
}

String _dateLabel(DateTime date) => '${date.year}/${date.month}/${date.day}';

/// 单本书在指定周期内的有效阅读时长；同名书按身份分别统计。
class BookDurationEntry {
  const BookDurationEntry({
    required this.bookId,
    required this.title,
    required this.duration,
  });

  final String bookId;
  final String title;
  final Duration duration;
}

class BookDurationSummary {
  BookDurationSummary(
    ReadingInsights insights, {
    required BookDurationPeriod period,
    required DateTime date,
    Map<String, String> bookTitles = const {},
    // 完整列表不筛门槛；总时长在两种口径下都保留全部有效阅读。
    bool applyBookThreshold = true,
  }) : start = period.startOf(date) {
    final end = period.shift(start, 1);
    final durations = <String, Duration>{};
    for (final portion in insights.portions) {
      if (portion.date.isBefore(start) ||
          !portion.date.isBefore(end) ||
          portion.duration <= Duration.zero) {
        continue;
      }
      durations[portion.bookId] =
          (durations[portion.bookId] ?? Duration.zero) + portion.duration;
    }
    entries = List.unmodifiable(
      <BookDurationEntry>[
        for (final entry in durations.entries)
          if (!applyBookThreshold ||
              insights.visibleBookIds.contains(entry.key))
            BookDurationEntry(
              bookId: entry.key,
              title:
                  bookTitles[entry.key] ??
                  insights.bookTitles[entry.key] ??
                  '已移出书架的书籍',
              duration: entry.value,
            ),
      ]..sort(_compareEntries),
    );
    total = durations.values.fold(Duration.zero, (sum, value) => sum + value);
    totalBookCount = durations.length;
  }

  final DateTime start;
  late final List<BookDurationEntry> entries;
  late final Duration total;

  /// 不受展示门槛影响的同期书籍数量。
  late final int totalBookCount;
}

int _compareEntries(BookDurationEntry left, BookDurationEntry right) {
  final time = right.duration.compareTo(left.duration);
  if (time != 0) return time;
  final title = left.title.compareTo(right.title);
  return title == 0 ? left.bookId.compareTo(right.bookId) : title;
}
