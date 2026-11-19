import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

class ReadingCalendarMonthPicker extends StatefulWidget {
  const ReadingCalendarMonthPicker({super.key, required this.selected});

  final DateTime selected;

  @override
  State<ReadingCalendarMonthPicker> createState() =>
      _ReadingCalendarMonthPickerState();
}

class _ReadingCalendarMonthPickerState
    extends State<ReadingCalendarMonthPicker> {
  late int _year = widget.selected.year;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      key: const ValueKey('stats-calendar-month-picker'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '选择月份',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _yearNavigation(),
          const SizedBox(height: 12),
          _months(),
        ],
      ),
    ),
  );

  Widget _yearNavigation() => Row(
    children: [
      IconButton(
        key: const ValueKey('stats-calendar-previous-year'),
        tooltip: '上一年',
        onPressed: () => setState(() => _year--),
        icon: const AppIcon(AppGlyph.chevronLeft),
      ),
      Expanded(
        child: Text(
          '$_year年',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      IconButton(
        key: const ValueKey('stats-calendar-next-year'),
        tooltip: '下一年',
        onPressed: () => setState(() => _year++),
        icon: const AppIcon(AppGlyph.chevronRight),
      ),
    ],
  );

  Widget _months() => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: EdgeInsets.zero,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisExtent: math.max(
        48,
        MediaQuery.textScalerOf(context).scale(14) * 1.4 + 16,
      ),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
    ),
    itemCount: 12,
    itemBuilder: (context, index) => _monthButton(index + 1),
  );

  Widget _monthButton(int month) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected == DateTime(_year, month);
    return Semantics(
      selected: selected,
      child: TextButton(
        key: ValueKey('stats-calendar-pick-$_year-$month'),
        onPressed: () => Navigator.of(context).pop(DateTime(_year, month)),
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          backgroundColor: selected ? scheme.primaryContainer : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text('$month月'),
      ),
    );
  }
}
