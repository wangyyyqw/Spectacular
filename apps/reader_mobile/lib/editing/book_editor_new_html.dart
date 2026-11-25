import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:reader_core/editing/package_editor.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import 'book_editor_controller.dart';
import 'editor_icon.dart';

/// 在同一表单选择空白正文的路径、标题、阅读顺序和样式来源。
Future<String?> createBookHtml(
  BuildContext context,
  BookEditorController editor, {
  String? anchor,
  bool after = true,
}) async {
  if (editor.busy || !editor.flush()) return null;
  final path = await showReaderDrawer<String>(
    context: context,
    waitForDismissal: true,
    builder: (_) => _NewHtmlForm(editor: editor, anchor: anchor, after: after),
  );
  if (path != null && context.mounted) {
    editor.showSource(path);
    final source = editor.session.readText(path);
    editor.openDocument(
      path,
      offset: source.indexOf('<body>') + '<body>\n    '.length,
    );
  }
  return path;
}

enum _InsertAt { before, after, end }

class _NewHtmlForm extends StatefulWidget {
  const _NewHtmlForm({required this.editor, this.anchor, required this.after});
  final BookEditorController editor;
  final String? anchor;
  final bool after;

  @override
  State<_NewHtmlForm> createState() => _NewHtmlFormState();
}

class _NewHtmlFormState extends State<_NewHtmlForm> {
  final _path = TextEditingController();
  final _title = TextEditingController();
  late final _chapters = widget.editor.session.spinePaths;
  late String _reference;
  late _InsertAt _position;
  late String _suggested;
  bool _inheritStyles = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final anchor = widget.anchor ?? widget.editor.activePath;
    _reference = _chapters.contains(anchor) ? anchor! : _chapters.last;
    _position = _chapters.contains(anchor)
        ? (widget.after ? _InsertAt.after : _InsertAt.before)
        : _InsertAt.end;
    _path.text = _suggested = _suggestPath();
  }

  String _suggestPath() {
    final directory = p.posix.dirname(_reference);
    final paths = widget.editor.session.resources
        .map((file) => file.path)
        .toSet();
    var number = 1;
    String candidate;
    do {
      candidate = p.posix.join(
        directory,
        'Section${(number++).toString().padLeft(4, '0')}.xhtml',
      );
    } while (paths.contains(candidate));
    return candidate;
  }

  void _setReference(String path) {
    if (path == _reference) return;
    final suggested = _path.text == _suggested;
    _reference = path;
    _suggested = _suggestPath();
    if (suggested) _path.text = _suggested;
  }

  @override
  void dispose() {
    _path.dispose();
    _title.dispose();
    super.dispose();
  }

  void _create() {
    final path = _path.text.trim();
    if (!const {
      '.xhtml',
      '.html',
      '.htm',
    }.contains(p.posix.extension(path).toLowerCase())) {
      setState(() => _error = '文件路径需以 .xhtml、.html 或 .htm 结尾');
      return;
    }
    final index = _position == _InsertAt.end
        ? _chapters.length
        : _chapters.indexOf(_reference) +
              (_position == _InsertAt.after ? 1 : 0);
    final created = widget.editor.runCommand(
      () => PackageEditor(widget.editor.session).addXhtml(
        path,
        _title.text,
        index: index,
        blank: true,
        stylesFrom: _inheritStyles ? _reference : null,
      ),
    );
    if (created) {
      Navigator.pop(context, path);
    } else {
      setState(() => _error = widget.editor.error ?? '新建 HTML 失败，请检查输入');
    }
  }

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    title: const Text('新建空白 HTML'),
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('new-html-path'),
            controller: _path,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '书内文件路径',
              helperText: '相对 EPUB 根目录，例如 OEBPS/Text/Section0001.xhtml',
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('new-html-title'),
            controller: _title,
            decoration: const InputDecoration(
              labelText: '文档标题（可选）',
              helperText: '留空时使用文件名；正文保持空白',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<_InsertAt>(
            key: const ValueKey('new-html-position'),
            initialValue: _position,
            decoration: const InputDecoration(labelText: '插入位置'),
            icon: const EditorIcon(EditorGlyph.chevronDown, size: 18),
            items: const [
              DropdownMenuItem(value: _InsertAt.before, child: Text('参考章节之前')),
              DropdownMenuItem(value: _InsertAt.after, child: Text('参考章节之后')),
              DropdownMenuItem(value: _InsertAt.end, child: Text('书籍末尾')),
            ],
            onChanged: (value) => setState(() {
              _position = value!;
              if (value == _InsertAt.end) _setReference(_chapters.last);
            }),
          ),
          const SizedBox(height: 12),
          if (_position != _InsertAt.end)
            DropdownButtonFormField<String>(
              key: ValueKey('new-html-reference-$_reference'),
              initialValue: _reference,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '参考章节'),
              icon: const EditorIcon(EditorGlyph.chevronDown, size: 18),
              items: [
                for (final path in _chapters)
                  DropdownMenuItem(
                    value: path,
                    child: Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _setReference(value!)),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('沿用参考章节样式'),
            subtitle: Text(_reference, maxLines: 2),
            value: _inheritStyles,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) => setState(() => _inheritStyles = value!),
          ),
          if (_error != null)
            Text(
              _error!,
              key: const ValueKey('new-html-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _create, child: const Text('创建 HTML')),
    ],
  );
}
