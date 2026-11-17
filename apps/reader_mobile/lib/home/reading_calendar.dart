import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_duration_summary.dart';
import 'reading_calendar_month.dart';
import 'reading_insights.dart';

/// 按月查看实际阅读日期，连续阅读的书目在一周内合并展示。
class ReadingCalendar extends StatefulWidget {
  const ReadingCalendar({
    super.key,
    required this.insights,
    this.bookTitles = const {},
    this.finishedBookIds = const {},
    this.now,
  });

  final ReadingInsights insights;
  final Map<String, String> bookTitles;
  final Set<String> finishedBookIds;
  final DateTime? now;

  @override
  State<ReadingCalendar> createState() => _ReadingCalendarState();
}

class _ReadingCalendarState extends State<ReadingCalendar>
    with AutomaticKeepAliveClientMixin<ReadingCalendar> {
  DateTime? _month;
  DateTime? _selectedDate;

  DateTime get _today {
    final now = widget.now ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _currentMonth => DateTime(_today.year, _today.month);
  DateTime get _visibleMonth => _month ?? _currentMonth;

  @override
  bool get wantKeepAlive => true;

  void _showMonth(DateTime month) => setState(() {
    _month = month == _currentMonth ? null : month;
    _selectedDate = null;
  });

  void _shiftMonth(int offset) =>
      _showMonth(DateTime(_visibleMonth.year, _visibleMonth.month + offset));

  void _openDay(DateTime date, List<BookDurationEntry> books) {
    setState(() => _selectedDate = date);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CalendarDaySheet(
        date: date,
        books: books,
        finishedBookIds: widget.finishedBookIds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final month = ReadingCalendarMonth(
      widget.insights,
      date: _visibleMonth,
      bookTitles: widget.bookTitles,
    );
    return Column(
      key: const ValueKey('stats-reading-calendar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _navigation(),
        const SizedBox(height: 4),
        _summary(month),
        const SizedBox(height: 16),
        _grid(month),
        if (month.days.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('本月暂无阅读记录', style: TextStyle(fontSize: 12)),
          ),
        if (month.monthBooks.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CalendarLegend(month: month),
        ],
      ],
    );
  }

  Widget _summary(ReadingCalendarMonth month) => Text(
    '${month.days.length} 天阅读 · ${month.bookCount} 本 · '
    '${formatReadingDuration(month.total)}',
    key: const ValueKey('stats-calendar-summary'),
    style: TextStyle(
      fontSize: 12,
      height: 1.4,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  Widget _navigation() => Row(
    children: [
      IconButton(
        key: const ValueKey('stats-calendar-previous'),
        tooltip: '上个月',
        onPressed: () => _shiftMonth(-1),
        icon: const AppIcon(AppGlyph.chevronLeft),
      ),
      Expanded(child: _monthButton()),
      IconButton(
        key: const ValueKey('stats-calendar-next'),
        tooltip: '下个月',
        onPressed: () => _shiftMonth(1),
        icon: const AppIcon(AppGlyph.chevronRight),
      ),
    ],
  );

  Widget _monthButton() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 15),
    child: Text(
      '${_visibleMonth.year}年${_visibleMonth.month}月',
      key: const ValueKey('stats-calendar-month'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  Widget _grid(ReadingCalendarMonth month) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final width = math.max(constraints.maxWidth, 336.0 * scale);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            key: const ValueKey('stats-calendar-scroll'),
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: width, child: _weeks(month)),
          ),
          if (width > constraints.maxWidth)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('左右滑动查看完整一周', style: TextStyle(fontSize: 11)),
            ),
        ],
      );
    },
  );

  Widget _weeks(ReadingCalendarMonth month) => Column(
    children: [
      _weekdays(context),
      for (var week = 0; week < month.weekCount; week++)
        _CalendarWeek(
          month: month,
          week: week,
          today: _today,
          selected: _selectedDate,
          onOpen: _openDay,
        ),
    ],
  );
}

Widget _weekdays(BuildContext context) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Row(
    children: [
      for (final label in ['日', '一', '二', '三', '四', '五', '六'])
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ],
  ),
);

const _weekBaseHeight = 44.0;
const _laneHeight = 7.0;
const _barHeight = 4.0;

class _CalendarWeek extends StatelessWidget {
  const _CalendarWeek({
    required this.month,
    required this.week,
    required this.today,
    required this.selected,
    required this.onOpen,
  });

  final ReadingCalendarMonth month;
  final int week;
  final DateTime today;
  final DateTime? selected;
  final void Function(DateTime, List<BookDurationEntry>) onOpen;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final spans = month.spansForWeek(week);
    final lanes = spans.fold(
      0,
      (count, span) => math.max(count, span.lane + 1),
    );
    return SizedBox(
      height: (_weekBaseHeight + lanes * _laneHeight) * scale,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(child: _day(context, column, scale)),
              ],
            ),
            for (final span in spans)
              _bar(span, constraints.maxWidth / 7, scale),
          ],
        ),
      ),
    );
  }

  Widget _bar(ReadingCalendarSpan span, double columnWidth, double scale) {
    final padding = 4 * scale;
    return Positioned(
      left: span.firstColumn * columnWidth + padding / 2,
      top: padding + span.lane * _laneHeight * scale,
      width: (span.lastColumn - span.firstColumn + 1) * columnWidth - padding,
      height: _barHeight * scale,
      child: _CalendarBar(span: span, week: week, month: month),
    );
  }

  Widget _day(BuildContext context, int column, double scale) {
    final date = month.dateAt(week, column);
    if (date.month != month.start.month) return const SizedBox.shrink();
    final books = month.days[date] ?? const <BookDurationEntry>[];
    final enabled = !date.isAfter(today);
    final extra = books.length > 4 ? books.length - 3 : 0;
    return Semantics(
      label:
          '${date.month}月${date.day}日，'
          '${books.isEmpty ? '暂无阅读记录' : '${books.length} 本书'}',
      selected: date == selected,
      child: InkWell(
        key: ValueKey('stats-calendar-day-${_dateKey(date)}'),
        onTap: enabled ? () => onOpen(date, books) : null,
        child: _dayCell(context, date, extra, scale),
      ),
    );
  }

  Widget _dayCell(
    BuildContext context,
    DateTime date,
    int extra,
    double scale,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: date == selected ? scheme.surfaceContainerHighest : null,
        border: Border.all(color: scheme.outlineVariant, width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Stack(
        children: [
          if (extra > 0)
            Positioned(
              top: 3 * _laneHeight * scale,
              left: 0,
              right: 0,
              child: _overflow(context, date, extra),
            ),
          Align(
            alignment: Alignment.bottomLeft,
            child: _dayNumber(context, date, !date.isAfter(today)),
          ),
        ],
      ),
    );
  }

  Widget _overflow(BuildContext context, DateTime date, int count) => Text(
    '+$count 本',
    key: ValueKey('stats-calendar-more-${_dateKey(date)}'),
    maxLines: 1,
    style: TextStyle(
      fontSize: 10,
      height: 1.2,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  Widget _dayNumber(BuildContext context, DateTime date, bool enabled) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = date == today;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Container(
        padding: isToday ? const EdgeInsets.symmetric(horizontal: 4) : null,
        decoration: isToday
            ? BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: Text(
          '${date.day}',
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: isToday
                ? scheme.onPrimary
                : enabled
                ? scheme.onSurfaceVariant
                : scheme.outline,
          ),
        ),
      ),
    );
  }
}

class _CalendarBar extends StatelessWidget {
  const _CalendarBar({
    required this.span,
    required this.week,
    required this.month,
  });
  final ReadingCalendarSpan span;
  final int week;
  final ReadingCalendarMonth month;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: DecoratedBox(
        key: ValueKey(
          'stats-calendar-bar-$week-${span.bookId}-${span.firstColumn}',
        ),
        decoration: BoxDecoration(
          color: _bookColor(Theme.of(context).colorScheme, month, span.bookId),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({required this.month});
  final ReadingCalendarMonth month;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rest = month.monthBooks.skip(_calendarColors.length);
    return Column(
      key: const ValueKey('stats-calendar-legend'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in month.monthBooks.take(_calendarColors.length))
          _legendRow(
            context,
            entry.title,
            entry.duration,
            _bookColor(scheme, month, entry.bookId),
          ),
        if (rest.isNotEmpty)
          _legendRow(
            context,
            '其他 ${rest.length} 本',
            rest.fold(Duration.zero, (sum, entry) => sum + entry.duration),
            scheme.outline,
          ),
      ],
    );
  }

  Widget _legendRow(
    BuildContext context,
    String title,
    Duration duration,
    Color color,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 4,
          margin: const EdgeInsets.only(top: 6, right: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 12, height: 1.4)),
        ),
        const SizedBox(width: 12),
        Text(
          formatReadingDuration(duration),
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _CalendarDaySheet extends StatelessWidget {
  const _CalendarDaySheet({
    required this.date,
    required this.books,
    required this.finishedBookIds,
  });
  final DateTime date;
  final List<BookDurationEntry> books;
  final Set<String> finishedBookIds;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(context),
            const SizedBox(height: 12),
            Expanded(
              child: books.isEmpty
                  ? const Center(child: Text('这一天没有阅读记录'))
                  : ListView.separated(
                      itemCount: books.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _bookRow(context, books[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(BuildContext context) {
    final total = books.fold(Duration.zero, (sum, book) => sum + book.duration);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${date.year}年${date.month}月${date.day}日',
          key: const ValueKey('stats-calendar-detail-date'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          '${books.length} 本书 · 合计 ${formatReadingDuration(total)}',
          key: const ValueKey('stats-calendar-detail-total'),
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _bookRow(BuildContext context, BookDurationEntry book) => Padding(
    key: ValueKey('stats-calendar-detail-${book.bookId}'),
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          book.title,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        _bookMeta(context, book),
      ],
    ),
  );

  Widget _bookMeta(BuildContext context, BookDurationEntry book) => Wrap(
    spacing: 12,
    children: [
      Text(
        formatReadingDuration(book.duration),
        style: const TextStyle(
          fontSize: 12,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      if (finishedBookIds.contains(book.bookId))
        Text(
          '当前已读完',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
    ],
  );
}

String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

const _calendarColors = [
  Color(0xFF397665),
  Color(0xFF417786),
  Color(0xFF95634F),
  Color(0xFF87596B),
  Color(0xFF70658E),
  Color(0xFF77723F),
];

Color _bookColor(
  ColorScheme scheme,
  ReadingCalendarMonth month,
  String bookId,
) {
  final rank = month.monthBooks.indexWhere((entry) => entry.bookId == bookId);
  return rank >= 0 && rank < _calendarColors.length
      ? _calendarColors[rank]
      : scheme.outline;
}
