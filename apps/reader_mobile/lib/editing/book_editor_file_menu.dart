part of 'book_editor_tools.dart';

List<PopupMenuEntry<String>> bookEditorFileMenuItems(
  BuildContext context,
  BookEditorController editor,
  String path,
) {
  final resource = editor.session.resources.firstWhere(
    (file) => file.path == path,
  );
  final file = _BrowserFile(resource);
  final protected =
      path == editor.session.opfPath || path.startsWith('META-INF/');
  return [
    PopupMenuItem(
      enabled: false,
      child: Text(path, style: Theme.of(context).textTheme.bodySmall),
    ),
    const PopupMenuDivider(),
    if (file.source) const PopupMenuItem(value: 'open', child: Text('打开源码')),
    if (file.group == _FileGroup.text) ...[
      const PopupMenuItem(value: 'insert-before', child: Text('在此处之前插入 HTML')),
      const PopupMenuItem(value: 'insert-after', child: Text('在此处之后插入 HTML')),
      const PopupMenuDivider(),
    ],
    PopupMenuItem(
      value: 'rename',
      enabled: !protected,
      child: const Text('重命名'),
    ),
    PopupMenuItem(
      value: 'delete',
      enabled: !protected,
      child: const Text('删除'),
    ),
    const PopupMenuItem(value: 'copy-path', child: Text('复制文件路径')),
    if (file.group == _FileGroup.images)
      const PopupMenuItem(value: 'cover', child: Text('设为封面')),
    if (file.raster)
      const PopupMenuItem(value: 'replace-image', child: Text('替换图片资源（全书）')),
  ];
}

Future<void> showBookEditorFileMenu(
  BuildContext context,
  BookEditorController editor,
  String path,
  Offset position,
) async {
  if (editor.busy) return;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final point = overlay.globalToLocal(position);
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      point & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: bookEditorFileMenuItems(context, editor, path),
  );
  if (action != null && context.mounted) {
    await BookEditorTools(context, editor).fileAction(path, action);
  }
}
