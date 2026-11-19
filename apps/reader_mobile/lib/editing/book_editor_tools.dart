import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:reader_core/editing/class_style_editor.dart';
import 'package:reader_core/editing/class_style_worker.dart';
import 'package:reader_core/editing/epub_edit_session.dart';
import 'package:reader_core/editing/package_editor.dart';
import 'package:reader_core/epub/opf.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_editor_controller.dart';

part 'book_editor_files.dart';
part 'book_editor_file_menu.dart';

/// 等反向动画卸载输入控件后才释放调用方持有的控制器。
Future<T?> _showEditorDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  final result = await navigator.push(route);
  await route.completed;
  return result;
}

Future<String?> editorPrompt(
  BuildContext context,
  String title, {
  String initial = '',
  bool multiline = false,
}) async {
  final input = TextEditingController(text: initial);
  final result = await _showEditorDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 560,
        child: TextField(
          autofocus: true,
          controller: input,
          minLines: multiline ? 5 : 1,
          maxLines: multiline ? 12 : 1,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, input.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  input.dispose();
  return result;
}

Future<bool> editorConfirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await _showEditorDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    ) ??
    false;

/// 工作台与手机段落面板共用的书籍管理命令入口。
class BookEditorTools {
  BookEditorTools(this.context, this.editor);
  final BuildContext context;
  final BookEditorController editor;
  PackageEditor get package => PackageEditor(editor.session);

  Future<void> metadata() async {
    if (!editor.flush()) return;
    const labels = {
      'title': '书名',
      'creator': '作者',
      'language': '语言',
      'description': '简介',
      'publisher': '出版者',
      'subject': '主题',
      'date': '日期',
      'rights': '版权',
    };
    final values = package.metadata;
    final fields = {
      for (final key in labels.keys)
        key: TextEditingController(text: values[key]),
    };
    await _showEditorDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('书籍信息'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final entry in labels.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: fields[entry.key],
                      decoration: InputDecoration(labelText: entry.value),
                      maxLines: entry.key == 'description' ? 3 : 1,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (editor.runCommand(
                () => package.setMetadata({
                  for (final entry in fields.entries)
                    entry.key: entry.value.text,
                }),
              )) {
                Navigator.pop(context);
              }
            },
            child: const Text('应用'),
          ),
        ],
      ),
    );
    for (final controller in fields.values) {
      controller.dispose();
    }
  }

  Future<void> classStyle(String name) async {
    if (!editor.flush()) return;
    final viewportWidth =
        editor.previewSource?.contentWidth ?? MediaQuery.sizeOf(context).width;
    late ClassStyleReport report;
    final inspected = await editor.runAsyncCommand(() async {
      report = await inspectClassStyleAsync(
        editor.session,
        name,
        viewportWidth: viewportWidth,
        isCancelled: () => !context.mounted,
      );
    });
    if (!inspected || !context.mounted) return;
    final fields = <String, TextEditingController>{
      for (final entry in report.declarations.entries)
        entry.key: TextEditingController(text: entry.value),
    };
    for (final key in [
      'font-family',
      'font-size',
      'font-weight',
      'font-style',
      'line-height',
      'text-align',
      'text-indent',
      'color',
      'background-color',
      'margin-top',
      'margin-right',
      'margin-bottom',
      'margin-left',
      'padding-top',
      'padding-right',
      'padding-bottom',
      'padding-left',
      'border-top',
      'border-right',
      'border-bottom',
      'border-left',
      'border-radius',
    ]) {
      fields.putIfAbsent(key, TextEditingController.new);
    }
    String? failure;
    var working = false;
    await _showEditorDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('全书 .$name'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${report.chapterCount} 个章节 · ${report.elementCount} 个元素',
                  ),
                  if (working) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    icon: const AppIcon(AppGlyph.code),
                    label: const Text('高级：打开 CSS 源码'),
                    onPressed: () async {
                      final paths = editor.session.resources
                          .where((item) => item.path.endsWith('.css'))
                          .map((item) => item.path)
                          .toList();
                      final path = await _showEditorDialog<String>(
                        context: context,
                        builder: (context) => SimpleDialog(
                          title: const Text('选择 CSS 文件'),
                          children: [
                            if (paths.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('此书没有 CSS 文件；先应用样式将创建共享样式表。'),
                              ),
                            for (final path in paths)
                              SimpleDialogOption(
                                onPressed: () => Navigator.pop(context, path),
                                child: Text(path),
                              ),
                          ],
                        ),
                      );
                      if (path != null && context.mounted) {
                        editor.showSource(path);
                        Navigator.pop(context);
                      }
                    },
                  ),
                  for (final entry in fields.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: entry.value,
                        decoration: InputDecoration(
                          labelText: entry.key,
                          hintText: report.declarations.containsKey(entry.key)
                              ? '留空移除这项编辑覆盖'
                              : '留空不修改',
                          helperText:
                              report.effectiveValues[entry.key]?.isNotEmpty ==
                                  true
                              ? '当前生效：${report.effectiveValues[entry.key]!.join(' / ')}${report.effectiveValues[entry.key]!.length > 1 ? '（元素间有差异）' : ''}'
                              : null,
                        ),
                      ),
                    ),
                  TextButton.icon(
                    icon: const AppIcon(AppGlyph.add),
                    label: const Text('添加 CSS 属性'),
                    onPressed: () async {
                      final key = await editorPrompt(context, 'CSS 属性名');
                      if (key != null &&
                          key.trim().isNotEmpty &&
                          context.mounted) {
                        setState(
                          () => fields.putIfAbsent(
                            key.trim(),
                            TextEditingController.new,
                          ),
                        );
                      }
                    },
                  ),
                  AppExpansionTile(
                    title: const Text('作者样式来源'),
                    children: [
                      for (final source in report.sources)
                        ListTile(
                          dense: true,
                          title: Text(
                            '${source.selector} { ${source.property}: ${source.value}${source.important ? ' !important' : ''}; }',
                          ),
                          subtitle: Text(
                            '${source.path}${source.media == null ? '' : '\n媒体条件：${source.media}'}',
                          ),
                        ),
                    ],
                  ),
                  if (failure != null)
                    Text(
                      failure!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: working
                  ? null
                  : () async {
                      final proposed = {
                        for (final entry in fields.entries)
                          if (entry.value.text.trim().isNotEmpty ||
                              report.declarations.containsKey(entry.key))
                            entry.key: entry.value.text.trim(),
                      };
                      setState(() => working = true);
                      try {
                        final preview = await inspectClassStyleAsync(
                          editor.session,
                          name,
                          proposed: proposed,
                          viewportWidth: viewportWidth,
                          isCancelled: () => !context.mounted,
                        );
                        if (!context.mounted) return;
                        final unify = preview.conflicts.isEmpty
                            ? false
                            : await _conflicts(preview.conflicts);
                        if (unify == null || !context.mounted) return;
                        final applied = await editor.runAsyncCommand(() async {
                          await applyClassStyleAsync(
                            editor.session,
                            name,
                            proposed,
                            unifyConflicts: unify,
                            viewportWidth: viewportWidth,
                            isCancelled: () => !context.mounted,
                          );
                        });
                        if (!context.mounted) return;
                        if (applied) {
                          Navigator.pop(context);
                        } else {
                          setState(() => failure = editor.error);
                        }
                      } catch (error) {
                        if (context.mounted) setState(() => failure = '$error');
                      } finally {
                        if (context.mounted) setState(() => working = false);
                      }
                    },
              child: const Text('应用全书样式'),
            ),
          ],
        ),
      ),
    );
    for (final field in fields.values) {
      field.dispose();
    }
  }

  Future<bool?> _conflicts(
    List<ClassStyleConflict> conflicts,
  ) => _showEditorDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('存在样式优先级冲突'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Text(
            [
              '普通应用保留作者优先级；统一样式将调整冲突声明，使同名 class 一致。',
              for (final item in conflicts)
                '${item.path}\n${item.selector} · ${item.property}：${item.reason}',
            ].join('\n\n'),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回检查'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('普通应用'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('统一同名样式'),
        ),
      ],
    ),
  );

  Future<void> addResource() async {
    final action = await _showEditorDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('新增内容'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'chapter'),
            child: const Text('空白章节'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'file'),
            child: const Text('导入图片、字体或文件'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == 'file') {
      await _pickResource();
      return;
    }
    if (action != 'chapter') return;
    final path = await editorPrompt(
      context,
      '新章节路径',
      initial: 'Text/chapter-${editor.session.revision + 1}.xhtml',
    );
    if (path == null || !context.mounted) return;
    final title = await editorPrompt(context, '章节标题', initial: '新章节');
    if (title != null &&
        editor.runCommand(() => package.addXhtml(path, title))) {
      editor.showSource(path);
    }
  }

  Future<String?> pickImage() => _pickResource(images: true);

  Future<String?> _pickResource({bool images = false}) async {
    final files = await FilePicker.pickFiles(
      type: images ? FileType.custom : FileType.any,
      allowedExtensions: images
          ? ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg']
          : null,
    );
    if (files.isEmpty || !context.mounted) return null;
    final file = files.single;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return null;
    final path = await editorPrompt(
      context,
      '书内资源路径',
      initial: '${images ? 'Images' : 'Resources'}/${file.name}',
    );
    if (path == null) return null;
    final type = _mediaType(file.name);
    return editor.runCommand(() => package.addResource(path, bytes, type))
        ? path
        : null;
  }

  String _mediaType(String path) =>
      switch (path.toLowerCase().split('.').last) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'svg' => 'image/svg+xml',
        'css' => 'text/css',
        'xhtml' || 'html' => 'application/xhtml+xml',
        'ttf' => 'font/ttf',
        'otf' => 'font/otf',
        'woff' => 'font/woff',
        'woff2' => 'font/woff2',
        _ => 'application/octet-stream',
      };

  Future<void> fileAction(String path, String action) async {
    if (editor.busy) return;
    switch (action) {
      case 'open':
        editor.showSource(path);
      case 'copy-path':
        await Clipboard.setData(ClipboardData(text: path));
      case 'insert-before':
      case 'insert-after':
        await _insertXhtml(path, after: action == 'insert-after');
      case 'rename':
        final next = await editorPrompt(context, '重命名资源并更新引用', initial: path);
        if (next != null &&
            next != path &&
            editor.runCommand(() => package.renameResource(path, next))) {
          editor.showSource(next);
        }
      case 'delete':
        if (await editorConfirm(context, '删除资源？', path)) {
          editor.runCommand(() => package.removeResource(path));
        }
      case 'cover':
        editor.runCommand(() => package.setCover(path));
      case 'replace-image':
        await replaceImageResource(path);
    }
  }

  Future<void> _insertXhtml(String anchor, {required bool after}) async {
    final directory = p.posix.dirname(anchor);
    final paths = editor.session.resources.map((file) => file.path).toSet();
    var number = 1;
    String candidate;
    do {
      candidate = p.posix.join(
        directory,
        'Section${(number++).toString().padLeft(4, '0')}.xhtml',
      );
    } while (paths.contains(candidate));
    final path = await editorPrompt(
      context,
      after ? '在此处之后插入 HTML' : '在此处之前插入 HTML',
      initial: candidate,
    );
    if (path == null || path.trim().isEmpty) return;
    final index = editor.session.spinePaths.indexOf(anchor);
    if (editor.runCommand(
      () => package.addXhtml(
        path,
        p.posix.basenameWithoutExtension(path),
        index: index < 0 ? null : index + (after ? 1 : 0),
      ),
    )) {
      editor.showSource(path);
    }
  }

  Future<bool> replaceImageResource(String path) async {
    final resource = editor.session.resources.firstWhere(
      (item) => item.path == path,
    );
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions:
          _rasterExtensions[_resourceMediaType(resource)] ??
          [path.split('.').last.toLowerCase()],
    );
    if (file == null || !context.mounted) return false;
    if (!await editorConfirm(
      context,
      '替换全书引用的图片资源？',
      '所有引用 $path 的位置都会显示新图片。需要只改一处时，请在段落图片面板导入另一资源。',
    )) {
      return false;
    }
    final bytes = await file.readAsBytes();
    return editor.runCommand(
      () => editor.session.transaction(
        '替换图片资源',
        (tx) => tx.writeBytes(path, bytes),
      ),
    );
  }

  Future<void> chapters() async {
    if (!editor.flush()) return;
    final items = package.chapters.toList();
    await _showEditorDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('章节顺序'),
          content: SizedBox(
            width: 640,
            height: 420,
            child: ReorderableListView.builder(
              itemCount: items.length,
              onReorderItem: (oldIndex, newIndex) => setState(() {
                items.insert(newIndex, items.removeAt(oldIndex));
              }),
              itemBuilder: (context, index) => ListTile(
                key: ValueKey(items[index].path),
                title: Text(items[index].title),
                subtitle: Text(items[index].path),
                leading: Text('${index + 1}'),
                onTap: () {
                  editor.showSource(items[index].path);
                  Navigator.pop(context);
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _splitChapter();
              },
              child: const Text('光标处拆章'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _mergeChapter();
              },
              child: const Text('合并下一章'),
            ),
            FilledButton(
              onPressed: () {
                if (editor.runCommand(
                  () => package.reorderChapters(
                    items.map((e) => e.path).toList(),
                  ),
                )) {
                  Navigator.pop(context);
                }
              },
              child: const Text('应用顺序'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _splitChapter() async {
    final doc = editor.activeDocument;
    if (doc == null) return;
    final lines = doc.code.text.split('\n');
    final selection = doc.code.selection;
    final offset =
        lines
            .take(selection.baseIndex)
            .fold<int>(0, (sum, line) => sum + line.length + 1) +
        selection.baseOffset;
    final path = await editorPrompt(
      context,
      '拆分后的新章节路径',
      initial: '${doc.path.replaceFirst(RegExp(r'\.x?html$'), '')}-2.xhtml',
    );
    if (path != null) {
      editor.runCommand(() => package.splitChapter(doc.path, offset, path));
    }
  }

  Future<void> _mergeChapter() async {
    final items = package.chapters;
    final index = items.indexWhere((item) => item.path == editor.activePath);
    if (index < 0 || index >= items.length - 1) {
      editor.runCommand(() => throw StateError('请先打开有后续章节的 XHTML 文件'));
      return;
    }
    if (await editorConfirm(
      context,
      '合并相邻章节？',
      '${items[index].path}\n${items[index + 1].path}',
    )) {
      editor.runCommand(
        () => package.mergeChapters(items[index].path, items[index + 1].path),
      );
    }
  }

  Future<void> toc() async {
    if (!editor.flush()) return;
    final items = package.toc.toList();
    await _showEditorDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('书籍目录'),
          content: SizedBox(
            width: 640,
            height: 420,
            child: ReorderableListView.builder(
              itemCount: items.length,
              onReorderItem: (old, next) => setState(() {
                items.insert(next, items.removeAt(old));
              }),
              itemBuilder: (context, index) => ListTile(
                key: ObjectKey(items[index]),
                contentPadding: EdgeInsets.only(
                  left: 12.0 + items[index].depth * 16,
                  right: 32,
                ),
                title: Text(items[index].label),
                subtitle: Text(
                  '${items[index].path}${items[index].fragment == null ? '' : '#${items[index].fragment}'}',
                ),
                onTap: () async {
                  final updated = await _tocEntry(items[index]);
                  if (updated != null && context.mounted) {
                    setState(() => items[index] = updated);
                  }
                },
                trailing: IconButton(
                  tooltip: '删除目录项',
                  icon: const AppIcon(AppGlyph.removeCircle),
                  onPressed: () => setState(() => items.removeAt(index)),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (editor.runCommand(package.generateToc)) {
                  Navigator.pop(context);
                }
              },
              child: const Text('从标题生成'),
            ),
            TextButton(
              onPressed: () async {
                final item = await _tocEntry(null);
                if (item != null && context.mounted) {
                  setState(() => items.add(item));
                }
              },
              child: const Text('新增'),
            ),
            FilledButton(
              onPressed: () {
                if (editor.runCommand(() => package.setToc(items))) {
                  Navigator.pop(context);
                }
              },
              child: const Text('应用目录'),
            ),
          ],
        ),
      ),
    );
  }

  Future<EditTocEntry?> _tocEntry(EditTocEntry? entry) async {
    final title = TextEditingController(text: entry?.label);
    final target = TextEditingController(
      text: entry == null
          ? editor.activePath
          : '${entry.path}${entry.fragment == null ? '' : '#${entry.fragment}'}',
    );
    final depth = TextEditingController(text: '${entry?.depth ?? 0}');
    final result = await _showEditorDialog<EditTocEntry>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('目录项'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: target,
              decoration: const InputDecoration(labelText: '书内路径 # 元素 ID'),
            ),
            TextField(
              controller: depth,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '层级（从 0 开始）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parts = target.text.split('#');
              Navigator.pop(
                context,
                EditTocEntry(
                  title.text,
                  parts.first,
                  fragment: parts.length > 1 ? parts.last : null,
                  depth: int.tryParse(depth.text) ?? 0,
                ),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    title.dispose();
    target.dispose();
    depth.dispose();
    return result;
  }

  Future<void> findReplace() async {
    if (!editor.flush()) return;
    final query = TextEditingController();
    final replacement = TextEditingController();
    var regex = false;
    var sensitive = true;
    var matches = <EditSearchMatch>[];
    String? error;
    await _showEditorDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('全书源码查找替换'),
          content: SizedBox(
            width: 680,
            height: 420,
            child: Column(
              children: [
                TextField(
                  controller: query,
                  onChanged: (_) => setState(() {
                    matches = [];
                    error = null;
                  }),
                  decoration: const InputDecoration(labelText: '查找内容'),
                ),
                TextField(
                  controller: replacement,
                  decoration: const InputDecoration(
                    labelText: r'替换为（正则可用 $1 分组）',
                  ),
                ),
                Wrap(
                  children: [
                    FilterChip(
                      label: const Text('正则'),
                      selected: regex,
                      onSelected: (value) => setState(() {
                        regex = value;
                        matches = [];
                      }),
                    ),
                    FilterChip(
                      label: const Text('区分大小写'),
                      selected: sensitive,
                      onSelected: (value) => setState(() {
                        sensitive = value;
                        matches = [];
                      }),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        try {
                          matches = package.find(
                            query.text,
                            regex: regex,
                            caseSensitive: sensitive,
                          );
                          error = null;
                        } catch (failure) {
                          error = '$failure';
                          matches = [];
                        }
                      }),
                      child: const Text('查找'),
                    ),
                  ],
                ),
                Text(error ?? '${matches.length} 处匹配'),
                Expanded(
                  child: ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final item = matches[index];
                      return ListTile(
                        dense: true,
                        title: Text(item.path),
                        subtitle: Text(item.text, maxLines: 1),
                        onTap: () {
                          editor.showSource(item.path, offset: item.start);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: matches.isEmpty
                  ? null
                  : () async {
                      if (!await editorConfirm(
                            context,
                            '替换全部匹配？',
                            '${matches.length} 处匹配将作为一次可撤销操作修改。',
                          ) ||
                          !context.mounted) {
                        return;
                      }
                      if (editor.runCommand(
                        () => package.replaceAll(matches, replacement.text),
                      )) {
                        Navigator.pop(context);
                      } else {
                        setState(() => error = editor.error);
                      }
                    },
              child: const Text('全部替换'),
            ),
          ],
        ),
      ),
    );
    query.dispose();
    replacement.dispose();
  }

  Future<void> history({
    Future<void> Function()? restoreOriginal,
    Future<void> Function()? restorePrevious,
    required VoidCallback onRestored,
  }) async {
    await _showEditorDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑历史'),
        content: SizedBox(
          width: 600,
          height: 340,
          child: ListView(
            children: [
              if (editor.session.history.isEmpty)
                const ListTile(title: Text('本次尚无修改')),
              if (editor.session.historyDiscarded > 0)
                ListTile(
                  title: Text(
                    '较早的 ${editor.session.historyDiscarded} 步已超出撤销缓存，可通过原书或上版恢复',
                  ),
                ),
              for (final item in editor.session.history.reversed)
                ListTile(
                  title: Text(item.label),
                  subtitle: Text(item.changedPaths.join('、')),
                ),
            ],
          ),
        ),
        actions: [
          if (restoreOriginal != null)
            TextButton(
              onPressed: () =>
                  _restore(context, '恢复导入时原书', restoreOriginal, onRestored),
              child: const Text('恢复原书'),
            ),
          if (restorePrevious != null)
            TextButton(
              onPressed: () =>
                  _restore(context, '恢复上一保存版本', restorePrevious, onRestored),
              child: const Text('恢复上版'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(
    BuildContext dialogContext,
    String title,
    Future<void> Function() action,
    VoidCallback onRestored,
  ) async {
    if (!await editorConfirm(
      dialogContext,
      '$title？',
      '当前编辑草稿将被替换；已有阅读记录会按恢复版本重新核验。',
    )) {
      return;
    }
    try {
      await action();
      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);
        onRestored();
      }
    } catch (error) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}
