import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_duration_summary.dart';
import 'reading_calendar_month.dart';
import 'reading_insights.dart';

/// 按月查看实际阅读日期：同一本书连续阅读的日期合并为书名色条，完读当天标记对勾。
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

  void _openDay(ReadingCalendarMonth month, DateTime date) {
    setState(() => _selectedDate = date);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CalendarDaySheet(month: month, date: date),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final month = ReadingCalendarMonth(
      widget.insights,
      date: _visibleMonth,
      bookTitles: widget.bookTitles,
      finishedBookIds: widget.finishedBookIds,
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

const _barHeight = 18.0;
const _laneGap = 3.0;
const _minLanesHeight = (_barHeight + _laneGap) * 3;
const _doneColor = Color(0xFF4E8E47);

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
  final void Function(ReadingCalendarMonth month, DateTime date) onOpen;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final spans = month.spansForWeek(week);
    final laneCount = spans.fold(
      0,
      (count, span) => math.max(count, span.lane + 1),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(child: _cell(context, column)),
            ],
          ),
        ),
        ExcludeSemantics(
          child: IgnorePointer(
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: _minLanesHeight * scale,
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(top: 4 * scale),
                    child: Column(
                      children: [
                        for (var lane = 0; lane < laneCount; lane++)
                          _lane(spans, lane, scale),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var column = 0; column < 7; column++)
                      Expanded(child: _dayLabel(context, column)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _lane(List<ReadingCalendarSpan> spans, int lane, double scale) {
    final laneSpans = [
      for (final span in spans)
        if (span.lane == lane) span,
    ]..sort((a, b) => a.firstColumn.compareTo(b.firstColumn));
    final children = <Widget>[];
    var column = 0;
    for (final span in laneSpans) {
      if (span.firstColumn > column) {
        children.add(Spacer(flex: span.firstColumn - column));
      }
      children.add(
        Expanded(
          flex: span.lastColumn - span.firstColumn + 1,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: scale),
            child: _bar(span, scale),
          ),
        ),
      );
      column = span.lastColumn + 1;
    }
    if (column < 7) children.add(Spacer(flex: 7 - column));
    return Padding(
      padding: EdgeInsets.only(bottom: _laneGap * scale),
      child: Row(children: children),
    );
  }

  Widget _bar(ReadingCalendarSpan span, double scale) {
    final color = _bookColor(span.bookId);
    final done =
        month.finishDays[span.bookId] == month.dateAt(week, span.lastColumn);
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Container(
        key: ValueKey(
          'stats-calendar-bar-$week-${span.bookId}-${span.firstColumn}',
        ),
        constraints: BoxConstraints(minHeight: _barHeight * scale),
        padding: EdgeInsets.fromLTRB(
          4 * scale,
          2 * scale,
          3 * scale,
          2 * scale,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                span.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, height: 1.2, color: color),
              ),
            ),
            if (done) ...[
              const SizedBox(width: 2),
              AppIcon(AppGlyph.check, size: 12, color: color),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, int column) {
    final date = month.dateAt(week, column);
    if (date.month != month.start.month) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final books = month.days[date] ?? const <BookDurationEntry>[];
    final enabled = !date.isAfter(today);
    final isToday = date == today;
    return Semantics(
      label:
          '${date.month}月${date.day}日，'
          '${books.isEmpty ? '暂无阅读记录' : '${books.length} 本书'}',
      selected: date == selected,
      child: InkWell(
        key: ValueKey('stats-calendar-day-${_dateKey(date)}'),
        onTap: enabled ? () => onOpen(month, date) : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: date == selected ? scheme.surfaceContainerHighest : null,
            border: Border.all(
              color: isToday ? scheme.primary : scheme.outlineVariant,
              width: isToday ? 1.5 : 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayLabel(BuildContext context, int column) {
    final date = month.dateAt(week, column);
    if (date.month != month.start.month) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final books = month.days[date] ?? const <BookDurationEntry>[];
    final extra = books.length > 4 ? books.length - 3 : 0;
    final enabled = !date.isAfter(today);
    final isToday = date == today;
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 2, 5, 4),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${date.day}',
              key: ValueKey('stats-calendar-number-${_dateKey(date)}'),
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isToday
                    ? scheme.primary
                    : enabled
                    ? scheme.onSurfaceVariant
                    : scheme.outline,
              ),
            ),
          ),
          if (extra > 0)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '+$extra',
                key: ValueKey('stats-calendar-more-${_dateKey(date)}'),
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarDaySheet extends StatelessWidget {
  const _CalendarDaySheet({required this.month, required this.date});

  final ReadingCalendarMonth month;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final books = month.days[date] ?? const <BookDurationEntry>[];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(context, books),
            const SizedBox(height: 8),
            Expanded(
              child: books.isEmpty
                  ? Center(
                      child: Text(
                        '这一天没有阅读记录',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: books.length,
                      itemBuilder: (context, index) =>
                          _bookRow(context, books[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, List<BookDurationEntry> books) {
    final scheme = Theme.of(context).colorScheme;
    final total = books.fold(Duration.zero, (sum, book) => sum + book.duration);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isoDate(date),
          key: const ValueKey('stats-calendar-detail-date'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${books.length} 本书 · 合计 ${formatReadingDuration(total)}',
          key: const ValueKey('stats-calendar-detail-total'),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _bookRow(BuildContext context, BookDurationEntry book) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey('stats-calendar-detail-${book.bookId}'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6.5, right: 10),
            decoration: BoxDecoration(
              color: _bookColor(book.bookId),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    book.title,
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                ),
                if (month.finishDays[book.bookId] == date) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _doneColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '已读',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatReadingDuration(book.duration),
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

String _isoDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

const _calendarColors = [
  Color(0xFF397665),
  Color(0xFF417786),
  Color(0xFF95634F),
  Color(0xFFA3413F),
  Color(0xFF70658E),
  Color(0xFF77723F),
];

Color _bookColor(String bookId) {
  var hash = 0;
  for (final unit in bookId.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  return _calendarColors[hash % _calendarColors.length];
}
