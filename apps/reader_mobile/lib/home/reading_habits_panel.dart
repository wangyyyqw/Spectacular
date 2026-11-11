import 'package:flutter/material.dart';

import 'reading_insights.dart';

/// 阅读习惯：连续天数、单次时长和真实阅读时段分布。
class ReadingHabitsPanel extends StatelessWidget {
  const ReadingHabitsPanel({super.key, required this.insights});

  final ReadingInsights insights;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _streak(context),
      const SizedBox(height: 18),
      _totals(),
      const SizedBox(height: 22),
      _periods(context),
      const SizedBox(height: 14),
      _speed(context),
    ],
  );

  Widget _totals() => Column(
    children: [
      _metrics(
        _HabitMetric(
          label: '阅读次数',
          value: '${insights.sessions.length} 次',
          id: 'sessions',
        ),
        _HabitMetric(
          label: '最长单次',
          value: formatReadingDuration(insights.longestSession),
          id: 'longest-session',
        ),
      ),
      const Divider(height: 24),
      _metrics(
        _HabitMetric(
          label: '阅读日均',
          value: formatReadingDuration(insights.averageDay),
          id: 'average-day',
        ),
        _HabitMetric(
          label: '平均单次',
          value: formatReadingDuration(insights.averageSession),
          id: 'average-session',
        ),
      ),
    ],
  );

  Widget _speed(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        insights.charactersPerMinute == null
            ? '阅读记录不足，暂不估算阅读速度。'
            : '平均 ${insights.charactersPerMinute} 字/分',
        key: const ValueKey('stats-reading-speed'),
        style: const TextStyle(fontSize: 13),
      ),
      const SizedBox(height: 4),
      Text(
        '字数按翻过页面累计，重复阅读也会计入；速度按前台时长估算。',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    ],
  );

  Widget _streak(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: _HabitMetric(
          label: '连续阅读',
          value: '${insights.currentStreak} 天',
          id: 'current-streak',
          size: 28,
        ),
      ),
      Text(
        '最长 ${insights.longestStreak} 天',
        key: const ValueKey('stats-longest-streak'),
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  Widget _metrics(_HabitMetric left, _HabitMetric right) => Row(
    children: [
      Expanded(child: left),
      const SizedBox(width: 16),
      Expanded(child: right),
    ],
  );

  static const _periodNames = ['凌晨', '上午', '下午', '晚上'];
  static const _periodRanges = ['00–06', '06–12', '12–18', '18–24'];

  Widget _periods(BuildContext context) {
    final max = insights.readingPeriods.fold<int>(
      0,
      (value, duration) =>
          duration.inMicroseconds > value ? duration.inMicroseconds : value,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          insights.preferredPeriod == null
              ? '常读时段'
              : '常读时段：${_periodNames[insights.preferredPeriod!]}',
          key: const ValueKey('stats-preferred-period'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _periodNames.length; i++)
          _periodRow(context, i, max),
      ],
    );
  }

  Widget _periodRow(BuildContext context, int index, int max) {
    final style = TextStyle(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              '${_periodNames[index]} ${_periodRanges[index]}',
              style: style,
            ),
          ),
          Expanded(child: _periodBar(context, index, max)),
          const SizedBox(width: 12),
          SizedBox(
            width: 62,
            child: Text(
              formatReadingDuration(insights.readingPeriods[index]),
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodBar(BuildContext context, int index, int max) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label:
          '${_periodNames[index]}阅读时长，${formatReadingDuration(insights.readingPeriods[index])}',
      child: ExcludeSemantics(
        child: LinearProgressIndicator(
          value: max == 0
              ? 0
              : insights.readingPeriods[index].inMicroseconds / max,
          minHeight: 4,
          color: scheme.primary.withValues(
            alpha: index == insights.preferredPeriod ? .85 : .3,
          ),
          backgroundColor: scheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class _HabitMetric extends StatelessWidget {
  const _HabitMetric({
    required this.label,
    required this.value,
    required this.id,
    this.size = 20,
  });

  final String label;
  final String value;
  final String id;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          key: ValueKey('stats-$id'),
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ],
  );
}
