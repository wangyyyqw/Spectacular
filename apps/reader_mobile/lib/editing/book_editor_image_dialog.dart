import 'package:flutter/material.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import 'book_editor_controller.dart';
import 'book_editor_tools.dart';

Future<bool> editBookImage(
  BuildContext context,
  BookEditorController editor,
  EditableElementRef image,
) async =>
    await showReaderDialog<bool>(
      context: context,
      builder: (_) => _ImageEditor(editor: editor, image: image),
    ) ??
    false;

class _ImageEditor extends StatefulWidget {
  const _ImageEditor({required this.editor, required this.image});
  final BookEditorController editor;
  final EditableElementRef image;
  @override
  State<_ImageEditor> createState() => _ImageEditorState();
}

class _ImageEditorState extends State<_ImageEditor> {
  late String _path = resolveEditReference(
    widget.image.path,
    widget.image.attributes['src'] ?? '',
  ).$1;
  late final _alt = TextEditingController(
    text: widget.image.attributes['alt'] ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _alt.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    try {
      final path = await BookEditorTools(context, widget.editor).pickImage();
      if (path != null && mounted) setState(() => _path = path);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _apply() {
    if (widget.editor.runCommand(
      () => widget.editor.session.replaceImage(
        widget.image,
        _path,
        alt: _alt.text,
      ),
    )) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = widget.editor.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paths = {
      _path,
      ...widget.editor.session.resources
          .where((item) => item.mediaType.startsWith('image/'))
          .map((item) => item.path),
    };
    return ReaderFrostedAlertDialog(
      title: const Text('编辑图片'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              icon: const AppIcon(AppGlyph.chevronDown),
              initialValue: _path,
              key: ValueKey(_path),
              isExpanded: true,
              decoration: const InputDecoration(labelText: '书内图片资源'),
              items: [
                for (final path in paths)
                  DropdownMenuItem(
                    value: path,
                    child: Text(path, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (path) {
                if (path != null) setState(() => _path = path);
              },
            ),
            TextField(
              key: const ValueKey('image-alt'),
              controller: _alt,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '替代文字（alt）',
                helperText: '描述图片内容；装饰图片可留空',
              ),
            ),
            TextButton.icon(
              onPressed: _import,
              icon: const AppIcon(AppGlyph.addImage),
              label: const Text('导入另一张图片'),
            ),
            const Text('这里只替换当前图片元素的引用，不改变同一资源在其他章节的引用。'),
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
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _apply, child: const Text('应用图片修改')),
      ],
    );
  }
}
