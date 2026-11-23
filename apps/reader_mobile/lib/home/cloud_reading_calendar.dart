import 'package:flutter/material.dart';

import '../rea_micro/rea_micro_models.dart';
import 'reading_calendar_month_picker.dart';
import 'reading_insights.dart';

/// 阅微月度日历：只展示接口提供的逐日时长和月度书籍数。
class CloudReadingCalendar extends StatefulWidget {
  const CloudReadingCalendar({
    super.key,
    required this.stats,
    this.onLoadMonth,
  });

  final ReaMicroCloudStats stats;
  final Future<ReaMicroPeriodStats> Function(DateTime)? onLoadMonth;

  @override
  State<CloudReadingCalendar> createState() => _CloudReadingCalendarState();
}

class _CloudReadingCalendarState extends State<CloudReadingCalendar>
    with AutomaticKeepAliveClientMixin<CloudReadingCalendar> {
  late DateTime _month;
  ReaMicroPeriodStats? _data;
  String? _error;
  int _request = 0;

  @override
  bool get wantKeepAlive => true;

  DateTime get _snapshotMonth {
    final date = widget.stats.monthDate ?? widget.stats.fetchedAt;
    return DateTime(date.year, date.month);
  }

  @override
  void initState() {
    super.initState();
    _month = _snapshotMonth;
    _data = widget.stats.month;
  }

  @override
  void didUpdateWidget(CloudReadingCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stats, widget.stats)) {
      _showMonth(_month, preserveData: true);
    }
  }

  Future<void> _showMonth(DateTime month, {bool preserveData = false}) async {
    final request = ++_request;
    setState(() {
      _month = DateTime(month.year, month.month);
      _error = null;
      if (_month == _snapshotMonth) {
        _data = widget.stats.month;
      } else if (!preserveData) {
        _data = null;
      }
    });
    if (_month == _snapshotMonth) return;
    final loader = widget.onLoadMonth;
    if (loader == null) {
      setState(() => _error = '暂无法加载该月阅读记录');
      return;
    }
    try {
      final result = await loader(_month);
      if (!mounted || request != _request) return;
      setState(() => _data = result);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _error = '该月阅读记录加载失败');
    }
  }

  Future<void> _pickMonth() async {
    final month = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReadingCalendarMonthPicker(selected: _month),
    );
    if (mounted && month != null) await _showMonth(month);
  }

  void _openDay(DateTime date, ReaMicroDayDuration day) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${date.year}年${date.month}月${date.day}日'),
            const SizedBox(height: 16),
            Text('合计 ${_duration(day.durationSeconds)}'),
            Text('阅读 ${_duration(day.readingDurationSeconds)}'),
            Text('听书 ${_duration(day.listeningDurationSeconds)}'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final days = <int, ReaMicroDayDuration>{
      for (final day in _data?.days ?? const <ReaMicroDayDuration>[])
        if (day.day >= 1 && day.day <= daysInMonth && day.durationSeconds > 0)
          day.day: day,
    };
    final offset = _month.weekday % 7;
    final cells = ((offset + daysInMonth + 6) ~/ 7) * 7;
    final maximum = days.values.fold<int>(
      1,
      (max, day) => day.durationSeconds > max ? day.durationSeconds : max,
    );
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
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  key: const ValueKey('stats-calendar-pick-month'),
                  onPressed: _pickMonth,
                  child: Text(
                    '${_month.year}年${_month.month}月',
                    key: const ValueKey('stats-calendar-month'),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const ValueKey('stats-calendar-previous'),
                      tooltip: '上个月',
                      onPressed: () =>
                          _showMonth(DateTime(_month.year, _month.month - 1)),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      key: const ValueKey('stats-calendar-next'),
                      tooltip: '下个月',
                      onPressed: () =>
                          _showMonth(DateTime(_month.year, _month.month + 1)),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    TextButton(
                      key: const ValueKey('stats-calendar-today'),
                      onPressed: () {
                        final now = DateTime.now();
                        _showMonth(DateTime(now.year, now.month));
                      },
                      child: const Text('今天'),
                    ),
                  ],
                ),
              ],
            ),
            if (_data != null)
              Text(
                '${days.length} 天阅读 · ${_data!.bookCount} 本 · '
                '${_duration(_data!.totalDurationSeconds)}',
                key: const ValueKey('stats-calendar-summary'),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: 12),
            if (_error != null)
              Row(
                children: [
                  Expanded(child: Text(_error!)),
                  TextButton(
                    onPressed: () => _showMonth(_month),
                    child: const Text('重试'),
                  ),
                ],
              )
            else if (_data == null)
              const LinearProgressIndicator()
            else ...[
              Row(
                children: [
                  for (final label in ['日', '一', '二', '三', '四', '五', '六'])
                    Expanded(child: Center(child: Text(label))),
                ],
              ),
              const SizedBox(height: 6),
              for (var row = 0; row < cells ~/ 7; row++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var column = 0; column < 7; column++)
                      Expanded(
                        child: _cell(
                          row * 7 + column - offset + 1,
                          daysInMonth,
                          days,
                          maximum,
                        ),
                      ),
                  ],
                ),
              if (days.isEmpty)
                const Text('本月暂无阅读记录', style: TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cell(
    int number,
    int daysInMonth,
    Map<int, ReaMicroDayDuration> days,
    int maximum,
  ) {
    if (number < 1 || number > daysInMonth) {
      return const SizedBox(height: 64);
    }
    final day = days[number];
    final date = DateTime(_month.year, _month.month, number);
    final scheme = Theme.of(context).colorScheme;
    final label = day == null ? '暂无记录' : _duration(day.durationSeconds);
    return Semantics(
      label: '${date.year}年${date.month}月$number日，$label',
      button: day != null,
      child: InkWell(
        key: ValueKey(
          'cloud-calendar-day-${_month.year}-${_month.month}-$number',
        ),
        onTap: day == null ? null : () => _openDay(date, day),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: day == null
                ? null
                : scheme.primary.withValues(
                    alpha: 0.08 + 0.22 * day.durationSeconds / maximum,
                  ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              Text('$number'),
              const SizedBox(height: 4),
              if (day != null)
                Text(
                  _duration(day.durationSeconds),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _duration(int seconds) =>
    formatReadingDuration(Duration(seconds: seconds));
