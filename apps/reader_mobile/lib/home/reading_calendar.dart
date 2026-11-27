import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/app_semantic_colors.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import 'book_duration_summary.dart';
import 'reading_calendar_month.dart';
import 'reading_calendar_month_picker.dart';
import 'reading_book_color.dart';
import 'reading_insights.dart';

/// 按月查看实际阅读日期：同一本书连续阅读的日期合并为书名色条，完读当天标记对勾。
class ReadingCalendar extends StatefulWidget {
  const ReadingCalendar({
    super.key,
    required this.insights,
    this.bookTitles = const {},
    this.bookColors = const {},
    this.finishedBookIds = const {},
    this.now,
  });

  final ReadingInsights insights;
  final Map<String, String> bookTitles;
  final Map<String, Color> bookColors;
  final Set<String> finishedBookIds;
  final DateTime? now;

  @override
  State<ReadingCalendar> createState() => _ReadingCalendarState();
}

class _ReadingCalendarState extends State<ReadingCalendar>
    with AutomaticKeepAliveClientMixin<ReadingCalendar> {
  DateTime? _month;

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
  });

  void _shiftMonth(int offset) =>
      _showMonth(DateTime(_visibleMonth.year, _visibleMonth.month + offset));

  Future<void> _pickMonth() async {
    final selected = await showReaderDrawer<DateTime>(
      context: context,
      builder: (_) => ReadingCalendarMonthPicker(selected: _visibleMonth),
    );
    if (mounted && selected != null) _showMonth(selected);
  }

  void _openDay(ReadingCalendarMonth month, DateTime date) {
    final portions =
        <ReadingDayPortion>[
          for (final portion in widget.insights.portions)
            if (portion.duration > Duration.zero &&
                portion.startedAt.year == date.year &&
                portion.startedAt.month == date.month &&
                portion.startedAt.day == date.day)
              portion,
        ]..sort((a, b) {
          final started = a.startedAt.compareTo(b.startedAt);
          if (started != 0) return started;
          final ended = a.endedAt.compareTo(b.endedAt);
          return ended != 0 ? ended : a.bookId.compareTo(b.bookId);
        });
    showReaderDrawer<void>(
      context: context,
      builder: (context) => _CalendarDaySheet(
        date: date,
        portions: portions,
        bookTitles: {...widget.insights.bookTitles, ...widget.bookTitles},
        bookColors: widget.bookColors,
        finishedBookIds: {
          for (final entry in month.finishDays.entries)
            if (entry.value.year == date.year &&
                entry.value.month == date.month &&
                entry.value.day == date.day)
              entry.key,
        },
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
      finishedBookIds: widget.finishedBookIds,
    );
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('stats-reading-calendar'),
      color: scheme.surface,
      shape: ReaderUiStyle.cardShapeOf(Theme.of(context)),
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
      final compact = constraints.maxWidth < 110 * scale + 96;
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
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
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
          bookColors: widget.bookColors,
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

class _CalendarWeek extends StatelessWidget {
  const _CalendarWeek({
    required this.month,
    required this.week,
    required this.today,
    required this.bookColors,
    required this.onOpen,
  });

  final ReadingCalendarMonth month;
  final int week;
  final DateTime today;
  final Map<String, Color> bookColors;
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
                Expanded(child: _cell(column)),
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
        for (var lane = 0; lane < laneCount; lane++)
          _lane(context, spans, lane, scale),
        Row(
          children: [
            for (var column = 0; column < 7; column++)
              Expanded(child: _dayLabel(context, column)),
          ],
        ),
      ],
    ),
  );

  Widget _lane(
    BuildContext context,
    List<ReadingCalendarSpan> spans,
    int lane,
    double scale,
  ) {
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
            child: _bar(context, span, scale),
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

  Widget _bar(BuildContext context, ReadingCalendarSpan span, double scale) {
    final color = readingBookColor(
      span.bookId,
      brightness: Theme.of(context).brightness,
      bookColors: bookColors,
    );
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
                overflow: TextOverflow.clip,
                softWrap: false,
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

  Widget _cell(int column) {
    final date = month.dateAt(week, column);
    if (date.month != month.start.month) return const SizedBox.shrink();
    final books = month.days[date] ?? const <BookDurationEntry>[];
    final enabled = !date.isAfter(today);
    return Semantics(
      label:
          '${date.month}月${date.day}日，'
          '${books.isEmpty ? (month.dayDurations.containsKey(date) ? '书目未达展示条件' : '暂无阅读记录') : '${books.length} 本书'}',
      child: InkWell(
        key: ValueKey('stats-calendar-day-${_dateKey(date)}'),
        onTap: enabled ? () => onOpen(month, date) : null,
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _dayLabel(BuildContext context, int column) {
    final date = month.dateAt(week, column);
    if (date.month != month.start.month) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final isToday = date == today;
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 2, 5, 4),
      child: Text(
        '${date.day}',
        key: ValueKey('stats-calendar-number-${_dateKey(date)}'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: isToday
              ? scheme.onSurface
              : date.isAfter(today)
              ? scheme.outline
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CalendarDaySheet extends StatelessWidget {
  const _CalendarDaySheet({
    required this.date,
    required this.portions,
    required this.bookTitles,
    required this.bookColors,
    required this.finishedBookIds,
  });

  final DateTime date;
  final List<ReadingDayPortion> portions;
  final Map<String, String> bookTitles;
  final Map<String, Color> bookColors;
  final Set<String> finishedBookIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = portions.fold(
      Duration.zero,
      (sum, portion) => sum + portion.duration,
    );
    final bookDurations = <String, Duration>{};
    for (final portion in portions) {
      bookDurations[portion.bookId] =
          (bookDurations[portion.bookId] ?? Duration.zero) + portion.duration;
    }
    final rankedBooks = bookDurations.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final bookCount = bookDurations.length;
    final span = portions.isEmpty
        ? null
        : '${_formatTimelineClock(portions.first.startedAt)}'
              '–${_formatTimelineClock(portions.last.endedAt)}';
    final lastIndexByBook = <String, int>{
      for (var index = 0; index < portions.length; index++)
        portions[index].bookId: index,
    };
    return SizedBox(
      height: math.min(MediaQuery.sizeOf(context).height * 0.76, 700),
      child: ReaderSheetForm(
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              _isoDate(date),
              key: const ValueKey('stats-calendar-detail-date'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                _weekdayLabel(date),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        scrollContent: false,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summaryCard(
              context,
              total: total,
              bookCount: bookCount,
              span: span,
              rankedBooks: rankedBooks,
            ),
            const SizedBox(height: 14),
            if (portions.isNotEmpty) ...[
              Text(
                '阅读时间轴',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: portions.isEmpty
                  ? const ReaderEmptyState(
                      icon: AppIcon(AppGlyph.autoStories),
                      title: '这一天没有阅读记录',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: portions.length,
                      itemBuilder: (context, index) =>
                          _timelineRow(context, index, lastIndexByBook),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(
    BuildContext context, {
    required Duration total,
    required int bookCount,
    required String? span,
    required List<MapEntry<String, Duration>> rankedBooks,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totalMicros = total.inMicroseconds;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: ReaderUiStyle.cardRadiusOf(theme),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                '合计 ${formatReadingDuration(total)}',
                key: const ValueKey('stats-calendar-detail-total'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (finishedBookIds.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppSemanticColors.of(context).successContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '完读 ${finishedBookIds.length} 本',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppSemanticColors.of(context).onSuccessContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            [
              '$bookCount 本书',
              '${portions.length} 段阅读',
              if (span != null) '时段 $span',
            ].join(' · '),
            key: const ValueKey('stats-calendar-detail-meta'),
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (totalMicros > 0 && rankedBooks.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 5,
                child: Row(
                  children: [
                    for (var i = 0; i < rankedBooks.length; i++) ...[
                      if (i > 0) const SizedBox(width: 1.5),
                      Expanded(
                        flex: math.max(
                          1,
                          (rankedBooks[i].value.inMicroseconds * 1000 ~/
                              totalMicros),
                        ),
                        child: ColoredBox(
                          color: readingBookColor(
                            rankedBooks[i].key,
                            brightness: scheme.brightness,
                            bookColors: bookColors,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _timelineRow(
    BuildContext context,
    int index,
    Map<String, int> lastIndexByBook,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final portion = portions[index];
    final bookId = portion.bookId;
    final isLast = index == portions.length - 1;
    final finished =
        finishedBookIds.contains(bookId) && lastIndexByBook[bookId] == index;
    final title = bookTitles[bookId]?.trim();
    final displayTitle = title == null || title.isEmpty ? '已移出书架的书籍' : title;
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
    final timeWidth = (50 * textScale.clamp(1.0, 1.8)).toDouble();
    final lineColor = scheme.outlineVariant.withValues(alpha: 0.75);
    final bookColor = readingBookColor(
      bookId,
      brightness: scheme.brightness,
      bookColors: bookColors,
    );
    return IntrinsicHeight(
      key: ValueKey('stats-calendar-detail-$index'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: timeWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.topLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: Text(
                    _formatTimelineTime(portion.startedAt),
                    key: ValueKey('stats-calendar-time-$index'),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 16,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                if (!isLast)
                  Positioned(
                    left: 7.5,
                    top: index == 0 ? 17 : 0,
                    bottom: 0,
                    child: Container(width: 1, color: lineColor),
                  ),
                if (isLast && index > 0)
                  Positioned(
                    left: 7.5,
                    top: 0,
                    height: 17,
                    child: Container(width: 1, color: lineColor),
                  ),
                Positioned(
                  top: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: bookColor.withValues(alpha: .18),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: bookColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: .78),
                  borderRadius: ReaderUiStyle.controlRadiusOf(theme),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: .72),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '阅读',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          TextSpan(
                            text: '《$displayTitle》',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: .75,
                              ),
                            ),
                          ),
                          child: Text(
                            _formatTimelineDuration(portion.duration),
                            key: ValueKey('stats-calendar-duration-$index'),
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        if (finished)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppSemanticColors.of(context).success,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '已读',
                              style: TextStyle(
                                fontSize: 10,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                                color: AppSemanticColors.of(context).onSuccess,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _weekdayLabel(DateTime date) => switch (date.weekday) {
  DateTime.monday => '周一',
  DateTime.tuesday => '周二',
  DateTime.wednesday => '周三',
  DateTime.thursday => '周四',
  DateTime.friday => '周五',
  DateTime.saturday => '周六',
  _ => '周日',
};

String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

String _isoDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _formatTimelineTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _formatTimelineClock(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}';
}

String _formatTimelineDuration(Duration duration) {
  if (duration <= Duration.zero) return '0秒';
  final seconds = math.max(1, (duration.inMilliseconds / 1000).round());
  if (seconds < 60) return '$seconds秒';
  final minutes = seconds ~/ 60;
  final restSeconds = seconds % 60;
  if (minutes < 60) {
    return restSeconds == 0 ? '$minutes分钟' : '$minutes分$restSeconds秒';
  }
  final hours = minutes ~/ 60;
  final restMinutes = minutes % 60;
  return restMinutes == 0 ? '$hours小时' : '$hours小时$restMinutes分';
}
