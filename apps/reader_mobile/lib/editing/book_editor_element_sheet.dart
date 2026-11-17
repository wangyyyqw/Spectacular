import 'package:flutter/material.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_editor_controller.dart';
import 'book_editor_tools.dart';
import 'book_editor_image_dialog.dart';

class BookEditorElementSheet extends StatefulWidget {
  const BookEditorElementSheet({
    super.key,
    required this.editor,
    required this.element,
  });
  final BookEditorController editor;
  final EditableElementRef element;

  @override
  State<BookEditorElementSheet> createState() => _BookEditorElementSheetState();
}

class _BookEditorElementSheetState extends State<BookEditorElementSheet> {
  late EditableElementRef _element = _paragraph(widget.element);
  late final _text = TextEditingController(text: _element.text);
  late final _html = TextEditingController(text: _element.innerXml);
  late int _tab = widget.element.tag == 'img' ? 3 : 0;
  String? _error;

  static EditableElementRef _paragraph(EditableElementRef ref) {
    if (ref.tag == 'img') return ref;
    const blocks = {
      'p',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'li',
      'blockquote',
      'td',
      'th',
      'div',
    };
    var current = ref;
    while (!blocks.contains(current.tag) &&
        current.parent != null &&
        current.parent!.tag != 'body') {
      current = current.parent!;
    }
    return current;
  }

  @override
  void dispose() {
    _text.dispose();
    _html.dispose();
    super.dispose();
  }

  void _apply(VoidCallback action) {
    if (widget.editor.runCommand(action)) {
      Navigator.pop(context);
    } else {
      setState(() => _error = widget.editor.error);
    }
  }

  Future<void> _operation(String value) async {
    try {
      await _performOperation(value);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _performOperation(String value) async {
    final session = widget.editor.session;
    switch (value) {
      case 'delete':
        if (await editorConfirm(
              context,
              '删除此元素？',
              '所选元素及内部内容将从书籍正文中删除，可通过撤销恢复。',
            ) &&
            mounted) {
          _apply(() => session.deleteElement(_element));
        }
      case 'before':
      case 'after':
        final html = await editorPrompt(
          context,
          '插入段落 HTML',
          initial: '<p>新段落</p>',
          multiline: true,
        );
        if (html != null && mounted) {
          _apply(
            () => value == 'before'
                ? session.insertBefore(_element, html)
                : session.insertAfter(_element, html),
          );
        }
      case 'split':
        if (_text.text != _element.text) {
          setState(() => _error = '请先应用正文修改，再在拆分位置放置光标');
          return;
        }
        final offset = _text.selection.baseOffset;
        if (offset <= 0 || offset >= _text.text.length) {
          setState(() => _error = '请在正文中间放置光标后拆分');
          return;
        }
        _apply(() => session.splitAtTextOffset(_element, offset));
      case 'image':
        final alt = await editorPrompt(context, '图片替代文字（alt）');
        if (alt == null || !mounted) return;
        final path = await BookEditorTools(context, widget.editor).pickImage();
        if (path != null && mounted) {
          // 导入资源本身不改正文；用原目标位置重新解析当前版本。
          final current = session
              .editableDocument(_element.path)
              .elementAtOffset(_element.sourceStart);
          if (current != null) {
            _apply(
              () => session.insertImage(current, resourcePath: path, alt: alt),
            );
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height:
          (MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom) *
          .76,
      child: Column(
        children: [
          ListTile(
            title: Text('编辑 <${_element.tag}>'),
            subtitle: Text(
              _element.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: '关闭段落编辑',
              onPressed: () => Navigator.pop(context),
              icon: const AppIcon(AppGlyph.close),
            ),
          ),
          if (_element.parent != null && _element.parent!.tag != 'body')
            TextButton(
              onPressed: () => setState(() {
                _element = _element.parent!;
                _text.text = _element.text;
                _html.text = _element.innerXml;
              }),
              child: Text('选择父元素 <${_element.parent!.tag}>'),
            ),
          Row(
            children: [
              for (final (index, label) in [
                '正文',
                'HTML',
                'class 样式',
                '图片',
              ].indexed)
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => _tab = index),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: _tab == index
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: switch (_tab) {
                0 => TextField(
                  key: const ValueKey('element-text'),
                  controller: _text,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  decoration: const InputDecoration(
                    labelText: '正文',
                    alignLabelWithHint: true,
                  ),
                ),
                1 => TextField(
                  key: const ValueKey('element-html'),
                  controller: _html,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: '元素内部 HTML',
                    alignLabelWithHint: true,
                  ),
                ),
                2 => _classes(),
                _ => _images(),
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  PopupMenuButton<String>(
                    onSelected: _operation,
                    tooltip: '段落操作',
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'before', child: Text('在前面插入段落')),
                      PopupMenuItem(value: 'after', child: Text('在后面插入段落')),
                      PopupMenuItem(value: 'split', child: Text('在正文光标处拆分')),
                      PopupMenuItem(value: 'image', child: Text('在后面插入图片')),
                      PopupMenuItem(value: 'delete', child: Text('删除此元素')),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('增删 / 拆分 / 图片'),
                    ),
                  ),
                  const Spacer(),
                  if (_tab < 2 && _element.tag != 'img')
                    FilledButton(
                      onPressed: () => _apply(
                        () => _tab == 0
                            ? widget.editor.session.replaceText(
                                _element,
                                _text.text,
                              )
                            : widget.editor.session.replaceInnerHtml(
                                _element,
                                _html.text,
                              ),
                      ),
                      child: const Text('应用修改'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _images() {
    final images = _element.document.elements.where(
      (node) =>
          node.tag == 'img' &&
          node.sourceStart >= _element.sourceStart &&
          node.sourceEnd <= _element.sourceEnd,
    );
    return ListView(
      children: [
        for (final image in images)
          ListTile(
            leading: const AppIcon(AppGlyph.image),
            title: Text(
              image.attributes['alt']?.isNotEmpty == true
                  ? image.attributes['alt']!
                  : '未填写替代文字',
            ),
            subtitle: Text(image.attributes['src'] ?? '缺少图片地址'),
            trailing: const AppIcon(AppGlyph.edit),
            onTap: () async {
              final changed = await editBookImage(
                context,
                widget.editor,
                image,
              );
              if (changed && mounted) Navigator.pop(context);
            },
          ),
        if (images.isEmpty) const ListTile(title: Text('此元素中没有图片')),
        TextButton.icon(
          onPressed: () => _operation('image'),
          icon: const AppIcon(AppGlyph.addImage),
          label: const Text('在后面插入图片'),
        ),
      ],
    );
  }

  Widget _classes() => ListView(
    children: [
      const Text('修改同名 class 会影响全书使用它的元素。先检查冲突，再决定是否统一样式。'),
      const SizedBox(height: 12),
      for (final name in _element.classes)
        ListTile(
          title: Text('.$name'),
          trailing: const AppIcon(AppGlyph.chevronRight),
          onTap: () async {
            await BookEditorTools(context, widget.editor).classStyle(name);
            if (mounted &&
                (widget.editor.session.revision != _element.revision ||
                    widget.editor.activePath?.endsWith('.css') == true)) {
              Navigator.pop(context);
            }
          },
        ),
      TextButton.icon(
        icon: const AppIcon(AppGlyph.add),
        label: const Text('添加 class'),
        onPressed: () async {
          final name = await editorPrompt(context, '添加 class 名称');
          if (name == null || !mounted) return;
          if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$').hasMatch(name)) {
            setState(() => _error = '请输入单个合法 class 名称');
            return;
          }
          _apply(() {
            widget.editor.session.checkElement(_element);
            widget.editor.session.transaction(
              '添加 class',
              (tx) => tx.writeText(
                _element.path,
                _element.replaceAttribute(
                  'class',
                  {..._element.classes, name}.join(' '),
                ),
              ),
            );
          });
        },
      ),
    ],
  );
}
