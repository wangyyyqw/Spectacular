import 'package:flutter/material.dart';

import '../page_furniture/corner_info.dart';

/// 四角位置预览；选择后即时应用，宿主负责保存。
class CornerInfoEditor extends StatelessWidget {
  const CornerInfoEditor({
    super.key,
    required this.info,
    required this.onChanged,
  });

  final ReaderCornerInfo info;
  final ValueChanged<ReaderCornerInfo>? onChanged;

  Future<void> _choose(BuildContext context, ReaderCornerSlot slot) async {
    final selected = await showModalBottomSheet<ReaderCornerContent>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: _ContentChoices(slot: slot, selected: info.contentAt(slot)),
      ),
    );
    if (selected != null) onChanged?.call(info.withContent(slot, selected));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _row(context, ReaderCornerSlot.topLeft, ReaderCornerSlot.topRight),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '点击位置选择信息',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          _row(
            context,
            ReaderCornerSlot.bottomLeft,
            ReaderCornerSlot.bottomRight,
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    ReaderCornerSlot left,
    ReaderCornerSlot right,
  ) => Row(
    children: [
      Expanded(child: _button(context, left)),
      const SizedBox(width: 12),
      Expanded(child: _button(context, right)),
    ],
  );

  Widget _button(BuildContext context, ReaderCornerSlot slot) => OutlinedButton(
    key: ValueKey('settings-corner-${_slotKey(slot)}'),
    onPressed: onChanged == null ? null : () => _choose(context, slot),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(slot.label, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 2),
        Text(info.contentAt(slot).label, style: const TextStyle(fontSize: 13)),
      ],
    ),
  );

  String _slotKey(ReaderCornerSlot slot) => switch (slot) {
    ReaderCornerSlot.topLeft => 'top-left',
    ReaderCornerSlot.topRight => 'top-right',
    ReaderCornerSlot.bottomLeft => 'bottom-left',
    ReaderCornerSlot.bottomRight => 'bottom-right',
  };
}

class _ContentChoices extends StatelessWidget {
  const _ContentChoices({required this.slot, required this.selected});

  final ReaderCornerSlot slot;
  final ReaderCornerContent selected;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${slot.label}显示',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final content in ReaderCornerContent.values)
              ListTile(
                key: ValueKey('corner-choice-${content.name}'),
                title: Text(content.label),
                selected: selected == content,
                trailing: selected == content ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(content),
              ),
          ],
        ),
      ),
    ],
  );
}
