import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

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
  Widget build(BuildContext context) => ReaderSheetForm(
    key: const ValueKey('stats-calendar-month-picker'),
    title: const Text('选择月份'),
    contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _yearNavigation(),
        const SizedBox(height: 12),
        _months(),
      ],
    ),
  );

  Widget _yearNavigation() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: ReaderUiStyle.controlRadius,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .8)),
      ),
      child: Row(
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
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('stats-calendar-next-year'),
            tooltip: '下一年',
            onPressed: () => setState(() => _year++),
            icon: const AppIcon(AppGlyph.chevronRight),
          ),
        ],
      ),
    );
  }

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
          foregroundColor: selected
              ? scheme.onPrimaryContainer
              : scheme.onSurface,
          backgroundColor: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow,
          side: BorderSide(
            color: selected
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: .75),
            width: selected ? 1.5 : 1,
          ),
          shape: ReaderUiStyle.controlShape,
        ),
        child: Text(
          '$month月',
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
