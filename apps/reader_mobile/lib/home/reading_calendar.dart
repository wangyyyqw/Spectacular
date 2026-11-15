import 'dart:math' as math;

import 'package:flutter/material.dart';

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

  List<DateTime> get _months => {
    _currentMonth,
    for (final day in widget.insights.byDay.keys)
      if (!day.isAfter(_today)) DateTime(day.year, day.month),
  }.toList()..sort((a, b) => b.compareTo(a));

  @override
  bool get wantKeepAlive => true;

  void _showMonth(DateTime month) => setState(() {
    _month = month == _currentMonth ? null : month;
    _selectedDate = null;
  });

  void _shiftMonth(int offset) =>
      _showMonth(DateTime(_visibleMonth.year, _visibleMonth.month + offset));

  Future<void> _pickMonth() async {
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CalendarMonthPicker(
        months: _months,
        selected: _visibleMonth,
        current: _currentMonth,
      ),
    );
    if (mounted && selected != null) _showMonth(selected);
  }

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
        onPressed: _visibleMonth.isAfter(_months.last)
            ? () => _shiftMonth(-1)
            : null,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      Expanded(child: _monthButton()),
      IconButton(
        key: const ValueKey('stats-calendar-next'),
        tooltip: '下个月',
        onPressed: _visibleMonth.isBefore(_currentMonth)
            ? () => _shiftMonth(1)
            : null,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ],
  );

  Widget _monthButton() => TextButton(
    key: const ValueKey('stats-calendar-month-picker'),
    onPressed: _pickMonth,
    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
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
    final lineHeight = 18 * scale;
    final spans = month.spansForWeek(week);
    final lanes = spans.fold(
      1,
      (count, span) => math.max(count, span.lane + 1),
    );
    final hasOverflow = Iterable<int>.generate(7).any(
      (column) => (month.days[month.dateAt(week, column)]?.length ?? 0) > 4,
    );
    final contentHeight = math.max(
      lanes * lineHeight,
      hasOverflow ? 3 * lineHeight + 12 * scale : 0.0,
    );
    final height = math.max(48.0 * scale, 8 + contentHeight + 18 * scale);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(child: _day(context, column, lineHeight)),
              ],
            ),
            for (final span in spans)
              _bar(span, constraints.maxWidth / 7, lineHeight),
          ],
        ),
      ),
    );
  }

  Widget _bar(
    ReadingCalendarSpan span,
    double columnWidth,
    double lineHeight,
  ) => Positioned(
    left: span.firstColumn * columnWidth + 2,
    top: 4 + span.lane * lineHeight,
    width: (span.lastColumn - span.firstColumn + 1) * columnWidth - 4,
    height: lineHeight - 2,
    child: _CalendarBar(span: span, week: week),
  );

  Widget _day(BuildContext context, int column, double lineHeight) {
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
        child: _dayCell(context, date, extra, lineHeight),
      ),
    );
  }

  Widget _dayCell(
    BuildContext context,
    DateTime date,
    int extra,
    double lineHeight,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: date == today
            ? scheme.onSurface.withValues(alpha: 0.08)
            : date == selected
            ? scheme.surfaceContainerHighest
            : null,
        border: Border.all(color: scheme.outlineVariant, width: 0.5),
      ),
      padding: const EdgeInsets.all(4),
      child: Stack(
        children: [
          if (extra > 0)
            Positioned(
              top: 3 * lineHeight,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(
        '${date.day}',
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          fontWeight: date == today ? FontWeight.w600 : FontWeight.w400,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: date == today
              ? scheme.onSurface
              : enabled
              ? scheme.onSurfaceVariant
              : scheme.outline,
        ),
      ),
    );
  }
}

class _CalendarBar extends StatelessWidget {
  const _CalendarBar({required this.span, required this.week});
  final ReadingCalendarSpan span;
  final int week;

  @override
  Widget build(BuildContext context) {
    final color = _bookColor(span.bookId);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey(
            'stats-calendar-bar-$week-${span.bookId}-${span.firstColumn}',
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            border: Border(left: BorderSide(color: color, width: 2)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            span.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, height: 1.3, color: color),
          ),
        ),
      ),
    );
  }
}

class _CalendarMonthPicker extends StatelessWidget {
  const _CalendarMonthPicker({
    required this.months,
    required this.selected,
    required this.current,
  });
  final List<DateTime> months;
  final DateTime selected;
  final DateTime current;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.6,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            '选择月份',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final month in months)
                ListTile(
                  key: ValueKey('stats-calendar-month-${_dateKey(month)}'),
                  selected: month == selected,
                  title: Text(
                    '${month.year}年${month.month}月${month == current ? ' · 本月' : ''}',
                  ),
                  trailing: month == selected
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(context).pop(month),
                ),
            ],
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

Color _bookColor(String id) {
  const colors = [
    Color(0xFF397665),
    Color(0xFF417786),
    Color(0xFF95634F),
    Color(0xFF87596B),
    Color(0xFF70658E),
    Color(0xFF77723F),
  ];
  final hash = id.codeUnits.fold(
    0,
    (hash, code) => (hash * 31 + code) & 0x7fffffff,
  );
  return colors[hash % colors.length];
}
