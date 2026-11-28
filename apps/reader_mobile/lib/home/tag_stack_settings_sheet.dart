import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../library/library_store.dart';
import 'tag_delete_confirmation.dart';

/// 当前书架的堆叠标签选择；关闭不保存，取消勾选即可展开对应书籍。
class TagStackSettingsSheet extends StatefulWidget {
  const TagStackSettingsSheet({
    super.key,
    required this.groupName,
    required this.tags,
    required this.counts,
    required this.selected,
    required this.onSave,
    required this.onDelete,
  });

  final String groupName;
  final List<BookTag> tags;
  final Map<String, int> counts;
  final List<String> selected;
  final Future<void> Function(List<String>) onSave;
  final Future<void> Function(BookTag) onDelete;

  @override
  State<TagStackSettingsSheet> createState() => _TagStackSettingsSheetState();
}

class _TagStackSettingsSheetState extends State<TagStackSettingsSheet> {
  late final _selected = List<String>.of(widget.selected);
  late final _tags = List<BookTag>.of(widget.tags);
  bool _saving = false;
  String? _deleting;
  String? _error;
  bool get _busy => _saving || _deleting != null;

  Future<void> _delete(BookTag tag) async {
    if (_busy || !await confirmDeleteBookTag(context, tag) || !mounted) return;
    setState(() {
      _deleting = tag.id;
      _error = null;
    });
    try {
      await widget.onDelete(tag);
      if (!mounted) return;
      setState(() {
        _tags.removeWhere((item) => item.id == tag.id);
        _selected.remove(tag.id);
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is LibraryImportException
              ? error.message
              : '删除失败，标签仍保留，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = null);
    }
  }

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
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: ReaderSheetForm(
      title: const Text('标签堆叠'),
      closeEnabled: !_busy,
      scrollContent: false,
      content: ReorderableListView.builder(
        key: const ValueKey('tag-stacks-order'),
        shrinkWrap: true,
        buildDefaultDragHandles: false,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('仅应用于「${widget.groupName}」'),
            const SizedBox(height: 8),
            Text(
              '同标签至少两本时堆叠。同一本书可出现在多个标签堆叠中。拖动已选标签右侧手柄调整展示顺序。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
        itemCount: _selected.length,
        onReorderItem: (oldIndex, newIndex) {
          if (_busy) return;
          setState(() {
            _selected.insert(newIndex, _selected.removeAt(oldIndex));
          });
        },
        itemBuilder: (_, index) => _tagRow(
          _tags.firstWhere((tag) => tag.id == _selected[index]),
          index: index,
        ),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_tags.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('还没有标签。可在图书详情页添加标签后再设置堆叠。'),
              ),
            for (final tag in _tags)
              if (!_selected.contains(tag.id)) _tagRow(tag),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('tag-stacks-clear'),
          onPressed: _busy || _selected.isEmpty
              ? null
              : () => setState(_selected.clear),
          child: const Text('全部展开'),
        ),
        FilledButton(
          key: const ValueKey('tag-stacks-save'),
          onPressed: _busy ? null : _save,
          child: Text(
            _deleting != null
                ? '正在删除标签…'
                : _saving
                ? '保存中…'
                : '完成',
          ),
        ),
      ],
    ),
  );

  Widget _tagRow(BookTag tag, {int? index}) => Row(
    key: ValueKey('stack-tag-row-${tag.id}'),
    children: [
      Expanded(
        child: CheckboxListTile(
          key: ValueKey('stack-tag-option-${tag.id}'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(tag.name),
          subtitle: Text(
            '${widget.counts[tag.id] ?? 0} 本在本分组'
            '${index == null ? '' : ' · 第 ${index + 1} 位'}',
          ),
          value: index != null,
          onChanged: _busy
              ? null
              : (selected) => setState(() {
                  if (selected == true) {
                    _selected.add(tag.id);
                  } else {
                    _selected.remove(tag.id);
                  }
                }),
        ),
      ),
      IconButton(
        key: ValueKey('stack-tag-delete-${tag.id}'),
        tooltip: '删除标签「${tag.name}」',
        onPressed: _busy ? null : () => _delete(tag),
        icon: const AppIcon(AppGlyph.delete, size: 20),
      ),
      if (index != null)
        ReorderableDragStartListener(
          index: index,
          enabled: !_busy,
          child: Semantics(
            label: '调整「${tag.name}」顺序，当前第 ${index + 1} 位',
            child: SizedBox(
              key: ValueKey('stack-tag-drag-${tag.id}'),
              width: 44,
              height: 48,
              child: const ColoredBox(
                color: Colors.transparent,
                child: Center(child: AppIcon(AppGlyph.dragHandle, size: 20)),
              ),
            ),
          ),
        )
      else
        const SizedBox(width: 44),
    ],
  );
}
