import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:path/path.dart' as p;
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import 'book_editor_controller.dart';
import 'editor_icon.dart';

Future<bool> editBookImage(
  BuildContext context,
  BookEditorController editor,
  EditableElementRef image,
) => _showImageEditor(context, editor, image);

Future<bool> insertBookImage(
  BuildContext context,
  BookEditorController editor,
  EditableElementRef element, {
  bool after = true,
}) => _showImageEditor(context, editor, element, after: after);

Future<bool> _showImageEditor(
  BuildContext context,
  BookEditorController editor,
  EditableElementRef element, {
  bool? after,
}) async =>
    await showReaderDrawer<bool>(
      context: context,
      builder: (_) =>
          _ImageEditor(editor: editor, element: element, after: after),
      waitForDismissal: true,
    ) ??
    false;

const _imageTypes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
};

class _ImageEditor extends StatefulWidget {
  const _ImageEditor({required this.editor, required this.element, this.after});
  final BookEditorController editor;
  final EditableElementRef element;
  final bool? after;

  @override
  State<_ImageEditor> createState() => _ImageEditorState();
}

class _ImageEditorState extends State<_ImageEditor> {
  late final _alt = TextEditingController(
    text: widget.after == null ? widget.element.attributes['alt'] ?? '' : '',
  );
  final _destination = TextEditingController();
  late final List<EpubEditResource> _resources;
  String? _path, _error, _importType;
  Uint8List? _importBytes, _previewBytes;
  bool _importing = false;
  late bool _after = widget.after ?? true;
  bool get _inserting => widget.after != null;
  bool get _usingImport => _importBytes != null && _path == null;

  @override
  void initState() {
    super.initState();
    _resources = widget.editor.session.resources
        .where(
          (item) =>
              item.mediaType.startsWith('image/') ||
              _imageTypes.containsKey(
                p.posix
                    .extension(item.path)
                    .replaceFirst('.', '')
                    .toLowerCase(),
              ),
        )
        .toList();
    if (!_inserting && widget.element.attributes['src']?.isNotEmpty == true) {
      _path = resolveEditReference(
        widget.element.path,
        widget.element.attributes['src']!,
      ).$1;
    } else {
      _path = _resources.firstOrNull?.path;
    }
    _previewBytes = _path == null
        ? null
        : widget.editor.session.readBytes(_path!);
  }

  @override
  void dispose() {
    _alt.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: _imageTypes.keys.toList(),
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final type =
          _imageTypes[p
              .extension(file.name)
              .replaceFirst('.', '')
              .toLowerCase()];
      if (bytes.isEmpty || type == null) {
        throw const FormatException('请选择支持的图片文件');
      }
      if (!mounted) return;
      setState(() {
        _importBytes = bytes;
        _importType = type;
        _path = null;
        _previewBytes = bytes;
        _destination.text = _importPath(file.name);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _importPath(String name) {
    final directory = _resources.isEmpty
        ? p.posix.join(p.posix.dirname(widget.editor.session.opfPath), 'Images')
        : p.posix.dirname(_resources.first.path);
    final base = p.posix.basename(name.replaceAll('\\', '/'));
    final paths = widget.editor.session.resources
        .map((item) => item.path)
        .toSet();
    var candidate = p.posix.join(directory, base), number = 2;
    while (paths.contains(candidate)) {
      candidate = p.posix.join(
        directory,
        '${p.posix.basenameWithoutExtension(base)}-${number++}${p.posix.extension(base)}',
      );
    }
    return candidate;
  }

  void _choose(String? path) {
    setState(() {
      _path = path;
      _error = null;
      _previewBytes = path == null
          ? _importBytes
          : widget.editor.session.readBytes(path);
    });
  }

  void _apply() {
    if (_importing || widget.editor.busy) return;
    final path = _usingImport ? _destination.text.trim() : _path;
    if (path == null || path.isEmpty) {
      setState(() => _error = '请选择书内图片或导入图片');
      return;
    }
    final changed = widget.editor.runCommand(() {
      if (_inserting) {
        widget.editor.session.insertImage(
          widget.element,
          resourcePath: path,
          alt: _alt.text,
          after: _after,
          imageBytes: _usingImport ? _importBytes : null,
          mediaType: _usingImport ? _importType : null,
        );
      } else {
        widget.editor.session.replaceImage(
          widget.element,
          path,
          alt: _alt.text,
          imageBytes: _usingImport ? _importBytes : null,
          mediaType: _usingImport ? _importType : null,
        );
      }
    });
    if (changed) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = widget.editor.error);
    }
  }

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    title: Text(_inserting ? '插入图片' : '编辑图片'),
    content: SizedBox(
      width: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _resourcePicker(),
          const SizedBox(height: 12),
          _preview(),
          TextButton.icon(
            onPressed: _importing ? null : _import,
            icon: const EditorIcon(EditorGlyph.addImage),
            label: Text(_importing ? '正在读取图片…' : '导入另一张图片'),
          ),
          if (_usingImport) ...[
            TextField(
              key: const ValueKey('image-resource-path'),
              controller: _destination,
              decoration: const InputDecoration(
                labelText: '书内资源路径',
                helperText: '确认后导入；取消不会向书籍添加资源',
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            key: const ValueKey('image-alt'),
            controller: _alt,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '替代文字（alt）',
              helperText: '描述图片内容；装饰图片可留空',
            ),
          ),
          if (_inserting)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _positionPicker(),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('只替换当前图片的引用，其他章节使用的图片不变。'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
        onPressed: _importing ? null : _apply,
        child: Text(_inserting ? '插入图片' : '应用图片修改'),
      ),
    ],
  );

  Widget _resourcePicker() => ReaderDropdownButtonFormField<String>(
    key: ValueKey('image-resource-${_path ?? 'import'}'),
    icon: const EditorIcon(EditorGlyph.chevronDown),
    initialValue: _path ?? (_usingImport ? '' : null),
    isExpanded: true,
    decoration: const InputDecoration(labelText: '书内图片资源'),
    items: [
      if (_importBytes != null)
        const DropdownMenuItem(value: '', child: Text('本次导入的图片')),
      for (final path in {?_path, ..._resources.map((item) => item.path)})
        DropdownMenuItem(
          value: path,
          child: Text(path, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (path) => _choose(path == '' ? null : path),
  );

  Widget _preview() => Container(
    key: const ValueKey('image-preview'),
    height: 160,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    alignment: Alignment.center,
    child: _previewBytes == null
        ? const Text('选择图片后可预览')
        : Image.memory(
            _previewBytes!,
            fit: BoxFit.contain,
            cacheWidth: 640,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('此格式暂不支持预览，插入时保留原始图片。', textAlign: TextAlign.center),
            ),
          ),
  );

  Widget _positionPicker() => ReaderDropdownButtonFormField<bool>(
    key: const ValueKey('image-insert-position'),
    icon: const EditorIcon(EditorGlyph.chevronDown),
    initialValue: _after,
    decoration: const InputDecoration(labelText: '插入位置'),
    items: [
      DropdownMenuItem(
        value: false,
        child: Text(widget.element.tag == 'body' ? '正文开头' : '所选元素之前'),
      ),
      DropdownMenuItem(
        value: true,
        child: Text(widget.element.tag == 'body' ? '正文末尾' : '所选元素之后'),
      ),
    ],
    onChanged: (after) {
      if (after != null) setState(() => _after = after);
    },
  );
}
