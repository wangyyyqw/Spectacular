import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_duration_summary.dart';
import 'reading_calendar_month.dart';
import 'reading_calendar_month_picker.dart';
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

  Future<void> _pickMonth() async {
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReadingCalendarMonthPicker(selected: _visibleMonth),
    );
    if (mounted && selected != null) _showMonth(selected);
  }

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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('stats-reading-calendar'),
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _monthHeader(month),
            const SizedBox(height: 12),
            _weeks(month),
            if (month.days.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('本月暂无阅读记录', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
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

  Widget _monthHeader(ReadingCalendarMonth month) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final compact = constraints.maxWidth < 110 * scale + 152;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact) ...[
            _monthButton(month),
            Align(alignment: Alignment.centerRight, child: _monthNavigation()),
          ] else
            Row(
              children: [
                Expanded(child: _monthButton(month)),
                _monthNavigation(),
              ],
            ),
          const SizedBox(height: 4),
          _summary(month),
        ],
      );
    },
  );

  Widget _monthButton(ReadingCalendarMonth month) => TextButton(
    key: const ValueKey('stats-calendar-pick-month'),
    onPressed: _pickMonth,
    style: TextButton.styleFrom(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.zero,
      minimumSize: const Size(48, 48),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '${month.start.year}年${month.start.month}月',
            key: const ValueKey('stats-calendar-month'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 4),
        const AppIcon(AppGlyph.chevronDown, size: 18),
      ],
    ),
  );

  Widget _monthNavigation() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: const ValueKey('stats-calendar-previous'),
        tooltip: '上个月',
        onPressed: () => _shiftMonth(-1),
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        padding: EdgeInsets.zero,
        icon: const AppIcon(AppGlyph.chevronLeft),
      ),
      IconButton(
        key: const ValueKey('stats-calendar-next'),
        tooltip: '下个月',
        onPressed: () => _shiftMonth(1),
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        padding: EdgeInsets.zero,
        icon: const AppIcon(AppGlyph.chevronRight),
      ),
      const SizedBox(width: 8),
      TextButton(
        key: const ValueKey('stats-calendar-today'),
        onPressed: () => _showMonth(_currentMonth),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
          shape: const StadiumBorder(),
        ),
        child: const Text('今天', style: TextStyle(fontSize: 13)),
      ),
    ],
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

Widget _weekdays(BuildContext context) => Container(
  color: Theme.of(context).colorScheme.surfaceContainerHighest,
  padding: const EdgeInsets.symmetric(vertical: 6),
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
            child: _weekContent(context, spans, laneCount, scale),
          ),
        ),
      ],
    );
  }

  Widget _weekContent(
    BuildContext context,
    List<ReadingCalendarSpan> spans,
    int laneCount,
    double scale,
  ) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (laneCount > 0) SizedBox(height: 4 * scale),
        for (var lane = 0; lane < laneCount; lane++) _lane(spans, lane, scale),
        Row(
          children: [
            for (var column = 0; column < 7; column++)
              Expanded(child: _dayLabel(context, column)),
          ],
        ),
      ],
    ),
  );

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
            padding: const EdgeInsets.symmetric(horizontal: 1),
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
        padding: EdgeInsets.fromLTRB(4, 2 * scale, 3, 2 * scale),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                span.title,
                maxLines: 1,
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
            color: date == selected
                ? scheme.surfaceContainerHighest
                : isToday
                ? scheme.primary.withValues(alpha: 0.06)
                : null,
          ),
        ),
      ),
    );
  }

  Widget _dayLabel(BuildContext context, int column) {
    final date = month.dateAt(week, column);
    if (date.month != month.start.month) return const SizedBox.shrink();
    final extra =
        (month.days[date]?.length ?? 0) - ReadingCalendarMonth.maxVisibleBooks;
    final number = _dayNumber(context, date);
    final more = _extraBooks(context, date, extra);
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 2, 5, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
          if (more != null && constraints.maxWidth < 34 * scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerLeft, child: number),
                Align(alignment: Alignment.centerRight, child: more),
              ],
            );
          }
          return Stack(
            children: [
              Align(alignment: Alignment.centerLeft, child: number),
              if (more != null)
                Align(alignment: Alignment.centerRight, child: more),
            ],
          );
        },
      ),
    );
  }

  Widget _dayNumber(BuildContext context, DateTime date) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = date == today;
    return Text(
      '${date.day}',
      key: ValueKey('stats-calendar-number-${_dateKey(date)}'),
      style: TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: isToday
            ? scheme.primary
            : date.isAfter(today)
            ? scheme.outline
            : scheme.onSurfaceVariant,
      ),
    );
  }

  Widget? _extraBooks(BuildContext context, DateTime date, int extra) =>
      extra > 0
      ? Text(
          '+$extra',
          key: ValueKey('stats-calendar-more-${_dateKey(date)}'),
          style: TextStyle(
            fontSize: 10,
            height: 1.2,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        )
      : null;
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
