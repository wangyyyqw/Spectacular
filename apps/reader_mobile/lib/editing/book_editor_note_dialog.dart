import 'package:flutter/material.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import 'book_editor_controller.dart';

/// 在目标文字处添加脚注，或编辑该标记对应的标准 EPUB 注释。
Future<bool> editBookNote(
  BuildContext context,
  BookEditorController editor,
  EditableElementRef target, {
  int? sourceOffset,
}) async =>
    await showReaderDrawer<bool>(
      context: context,
      waitForDismissal: true,
      builder: (_) => _NoteEditor(
        editor: editor,
        target: target,
        sourceOffset: sourceOffset,
      ),
    ) ??
    false;

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({
    required this.editor,
    required this.target,
    this.sourceOffset,
  });

  final BookEditorController editor;
  final EditableElementRef target;
  final int? sourceOffset;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  final _label = TextEditingController(text: '[注]');
  final _body = TextEditingController();
  late final _notes = EpubNoteEditor(widget.editor.session);
  EpubEditableNote? _existing;
  String? _error;
  String _placement = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    try {
      _existing = _notes.read(widget.target);
      if (_existing case final note?) {
        _label.text = note.label;
        _body.text = note.bodyHtml;
      } else {
        final point = _notes.insertion(
          widget.target,
          sourceOffset: widget.sourceOffset,
        );
        _placement = point.atCursor
            ? '标记插入当前文字光标处，注释正文放在本章末尾。'
            : widget.sourceOffset != null
            ? '光标不在可插入的文字边界，标记将放到所选元素末尾；原文保持不变。'
            : '标记插入所选元素末尾，注释正文放在本章末尾。';
      }
      _ready = true;
    } catch (error) {
      _error = '$error';
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _body.dispose();
    super.dispose();
  }

  void _apply() {
    final applied = widget.editor.runCommand(() {
      if (_existing case final note?) {
        _notes.update(note, bodyHtml: _body.text);
      } else {
        _notes.create(
          widget.target,
          label: _label.text,
          text: _body.text,
          sourceOffset: widget.sourceOffset,
        );
      }
    });
    if (applied) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = widget.editor.error ?? '当前操作尚未完成，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = _existing != null;
    return ReaderSheetForm(
      title: Text(editing ? '编辑 EPUB 注释' : '添加 EPUB 注释'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            TextField(
              key: const ValueKey('note-label'),
              controller: _label,
              readOnly: editing,
              decoration: InputDecoration(
                labelText: '标记',
                helperText: editing ? '保留原标记及其行内格式' : '例如 [1]、① 或 注',
              ),
            ),
            TextField(
              key: ValueKey(editing ? 'note-html' : 'note-text'),
              controller: _body,
              minLines: 5,
              maxLines: 12,
              decoration: InputDecoration(
                labelText: editing ? '注释内容 HTML' : '注释内容',
                helperText: editing
                    ? '沿用作者 HTML；请保留返回正文的链接及其属性。'
                    : '按普通文字输入，换行会保留。',
              ),
            ),
            if (!editing) Text(_placement),
            if (editing) Text('所在文件：${_existing!.definition.path}'),
            if (_error case final error?)
              SelectableText(
                error,
                key: const ValueKey('note-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('note-apply'),
          onPressed: _ready ? _apply : null,
          child: Text(editing ? '应用注释修改' : '添加注释'),
        ),
      ],
    );
  }
}
