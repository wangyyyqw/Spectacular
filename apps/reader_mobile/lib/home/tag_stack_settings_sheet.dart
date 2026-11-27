import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../library/library_store.dart';

/// 当前书架的堆叠标签选择；关闭不保存，取消勾选即可展开对应书籍。
class TagStackSettingsSheet extends StatefulWidget {
  const TagStackSettingsSheet({
    super.key,
    required this.groupName,
    required this.tags,
    required this.counts,
    required this.selected,
    required this.onSave,
  });

  final String groupName;
  final List<BookTag> tags;
  final Map<String, int> counts;
  final List<String> selected;
  final Future<void> Function(List<String>) onSave;

  @override
  State<TagStackSettingsSheet> createState() => _TagStackSettingsSheetState();
}

class _TagStackSettingsSheetState extends State<TagStackSettingsSheet> {
  late final _selected = List<String>.of(widget.selected);
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(List.of(_selected));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = '堆叠设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    title: const Text('标签堆叠'),
    closeEnabled: !_saving,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('仅应用于「${widget.groupName}」'),
        const SizedBox(height: 8),
        Text(
          '同标签至少两本时堆叠。多个标签重叠时，先选的标签优先，每本书只显示一次。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (widget.tags.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('这个分组还没有标签。可在图书详情页添加标签后再设置堆叠。'),
          ),
        for (final tag in widget.tags)
          CheckboxListTile(
            key: ValueKey('stack-tag-option-${tag.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(tag.name),
            subtitle: Text(
              '${widget.counts[tag.id] ?? 0} 本'
              '${_selected.contains(tag.id) ? ' · 优先级 ${_selected.indexOf(tag.id) + 1}' : ''}',
            ),
            value: _selected.contains(tag.id),
            onChanged: _saving
                ? null
                : (selected) => setState(() {
                    if (selected == true) {
                      _selected.add(tag.id);
                    } else {
                      _selected.remove(tag.id);
                    }
                  }),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      TextButton(
        key: const ValueKey('tag-stacks-clear'),
        onPressed: _saving || _selected.isEmpty
            ? null
            : () => setState(_selected.clear),
        child: const Text('全部展开'),
      ),
      FilledButton(
        key: const ValueKey('tag-stacks-save'),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '保存中…' : '完成'),
      ),
    ],
  );
}
