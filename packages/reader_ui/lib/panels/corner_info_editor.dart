import 'package:flutter/material.dart';

import '../page_furniture/corner_info.dart';
import '../theme/reader_section_slider.dart';
import '../theme/reader_ui_style.dart';
import 'reader_settings_sheet.dart';

/// 四角信息设置；保存前只更新面板中的预览。
class CornerInfoEditor extends StatefulWidget {
  const CornerInfoEditor({super.key, required this.info});

  final ReaderCornerInfo info;

  @override
  State<CornerInfoEditor> createState() => _CornerInfoEditorState();
}

class _CornerInfoEditorState extends State<CornerInfoEditor> {
  late ReaderCornerInfo _info = widget.info;
  int _slotIndex = 0;

  ReaderCornerSlot get _slot => ReaderCornerSlot.values[_slotIndex];

  Widget _previewRow(ReaderCornerSlot left, ReaderCornerSlot right) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final slot in [left, right])
          Expanded(
            child: Text(
              _info.contentAt(slot).label,
              key: ValueKey('corner-preview-${slot.name}'),
              semanticsLabel: '${slot.label}：${_info.contentAt(slot).label}',
              textAlign: slot == left ? TextAlign.left : TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: slot == _slot ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: slot == _slot ? FontWeight.w600 : null,
              ),
            ),
          ),
      ],
    );
  }

  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('分别设置阅读页四个边角的显示内容；选择“隐藏”可关闭对应位置。'),
      const SizedBox(height: 16),
      Container(
        key: const ValueKey('corner-settings-preview'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
        ),
        child: Column(
          children: [
            _previewRow(ReaderCornerSlot.topLeft, ReaderCornerSlot.topRight),
            const SizedBox(height: 16),
            _previewRow(
              ReaderCornerSlot.bottomLeft,
              ReaderCornerSlot.bottomRight,
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      ReaderSectionSlider(
        key: const ValueKey('corner-settings-section-tabs'),
        sections: [
          for (final slot in ReaderCornerSlot.values)
            (key: 'corner-${slot.name}', label: slot.label),
        ],
        index: _slotIndex,
        onSelected: (index) => setState(() => _slotIndex = index),
      ),
    ],
  );

  Widget _choices() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${_slot.label}显示', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final content in ReaderCornerContent.values)
            ChoiceChip(
              key: ValueKey('corner-choice-${content.name}'),
              label: Text(content.label),
              selected: _info.contentAt(_slot) == content,
              showCheckmark: true,
              onSelected: (_) =>
                  setState(() => _info = _info.withContent(_slot, content)),
            ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ReaderSettingsSheet(
    key: const ValueKey('corner-settings-fixed-height'),
    header: _header(),
    footer: FilledButton(
      key: const ValueKey('corner-settings-save'),
      onPressed: () => Navigator.of(context).pop(_info),
      child: const Text('保存边角设置'),
    ),
    child: _choices(),
  );
}
