import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:reader_ui/icons/app_icon.dart';
import 'package:spectacular_epub_tools/local_epub_tools.dart';

import 'book_editor_controller.dart';
import 'book_editor_toolkit.dart';
import 'book_editor_tools.dart';

part 'book_editor_local_forms.dart';
part 'book_editor_local_navigation.dart';
part 'book_editor_local_health.dart';

Future<T?> _localDialog<T>(BuildContext context, WidgetBuilder builder) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await navigator.push(route);
  await route.completed;
  return result;
}

class BookEditorLocalTools {
  const BookEditorLocalTools(this.context, this.editor, this.title);
  final BuildContext context;
  final BookEditorController editor;
  final String title;

  Future<void> open([LocalEpubTool? selected]) async {
    final tool =
        selected ??
        await _localDialog<LocalEpubTool>(context, (_) => const _ToolPicker());
    if (tool == null || !context.mounted) return;
    switch (tool) {
      case LocalEpubTool.health:
        await _health();
      case LocalEpubTool.navigation:
        await _navigation();
      case LocalEpubTool.split:
        await _split();
      case LocalEpubTool.encryptFont:
        await _fontEncryption();
      default:
        final options = await _options(tool);
        if (options != null && context.mounted) await _execute(tool, options);
    }
  }

  Future<void> _execute(
    LocalEpubTool tool,
    Map<String, Object?> options,
  ) async {
    final output = await BookEditorToolkit(editor).run(tool, options: options);
    if (output == null) return;
    try {
      if (!context.mounted) return;
      await _localDialog<void>(
        context,
        (_) => _ToolResultDialog(output: output, tool: tool, fileName: title),
      );
    } finally {
      await output.dispose();
    }
  }

  Future<Map<String, Object?>?> _options(LocalEpubTool tool) async {
    if (tool == LocalEpubTool.merge) {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );
      if (files.isEmpty || !context.mounted) return null;
      final paths = files.map((file) => file.path).whereType<String>().toList();
      if (paths.length != files.length) {
        throw const FileSystemException('无法读取所选 EPUB 文件');
      }
      final name = await editorPrompt(context, '合并后书名', initial: title);
      return name == null ? null : {'inputPaths': paths, 'title': name};
    }
    if (_formTools.contains(tool)) {
      return _localDialog<Map<String, Object?>>(
        context,
        (_) => _ToolOptionsDialog(tool: tool, title: title, editor: editor),
      );
    }
    if (tool.output != LocalToolOutput.workingCopy) return {};
    final accepted = await editorConfirm(
      context,
      tool.label,
      '${tool.description}。\n只修改当前工作副本，可一步撤销；保存前不会覆盖书架原书。',
    );
    return accepted ? {} : null;
  }

  Future<void> _health() async {
    final output = await BookEditorToolkit(editor).run(LocalEpubTool.health);
    if (output == null) return;
    List<String>? fixes;
    try {
      if (!context.mounted) return;
      fixes = await _localDialog<List<String>>(
        context,
        (_) => _HealthDialog(
          report: output.result.data! as EpubHealthReport,
          fileName: title,
        ),
      );
    } finally {
      await output.dispose();
    }
    if (fixes?.isNotEmpty == true && context.mounted) {
      await _execute(LocalEpubTool.repair, {'selectedFixIds': fixes});
    }
  }

  Future<void> _navigation() async {
    final output = await BookEditorToolkit(editor)
        .run(LocalEpubTool.navigation);
    if (output == null) return;
    EpubNavigationDocument? navigation;
    try {
      if (!context.mounted) return;
      navigation = await _localDialog<EpubNavigationDocument>(
        context,
        (_) => _NavigationDialog(
          document: output.result.data! as EpubNavigationDocument,
          editor: editor,
        ),
      );
    } finally {
      await output.dispose();
    }
    if (navigation != null && context.mounted) {
      await _execute(LocalEpubTool.saveNavigation, {'navigation': navigation});
    }
  }

  Future<void> _split() async {
    final output = await BookEditorToolkit(editor)
        .run(LocalEpubTool.splitTargets);
    if (output == null) return;
    List<int>? points;
    try {
      if (!context.mounted) return;
      final targets = output.result.data! as List<SplitTarget>;
      points = await _localDialog<List<int>>(
        context,
        (_) => _SplitDialog(targets: targets),
      );
    } finally {
      await output.dispose();
    }
    if (points != null && context.mounted) {
      await _execute(LocalEpubTool.split, {'splitPoints': points});
    }
  }

  Future<void> _fontEncryption() async {
    final output = await BookEditorToolkit(editor)
        .run(LocalEpubTool.fontTargets);
    if (output == null) return;
    Map<String, Object?>? targets;
    try {
      if (!context.mounted) return;
      targets = await _localDialog<Map<String, Object?>>(
        context,
        (_) => _FontTargetDialog(
          targets: output.result.data! as FontEncryptTargets,
        ),
      );
    } finally {
      await output.dispose();
    }
    if (targets != null && context.mounted) {
      await _execute(LocalEpubTool.encryptFont, targets);
    }
  }
}

class _ToolPicker extends StatelessWidget {
  const _ToolPicker();

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 5,
    child: AlertDialog(
      title: const Text('本地 EPUB 工具'),
      content: SizedBox(
        width: 760,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('使用当前有效工作副本。修改可撤销，导出不会覆盖原书。'),
            const SizedBox(height: 12),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: '转换'),
                Tab(text: '结构'),
                Tab(text: '图片'),
                Tab(text: '字体'),
                Tab(text: '注释与正文'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final category in ['转换', '结构', '图片', '字体', '注释与正文'])
                    ListView(
                      children: [
                        for (final tool in LocalEpubTool.visible.where(
                          (tool) => tool.category == category,
                        ))
                          ListTile(
                            title: Text(tool.label),
                            subtitle: Text(tool.description),
                            trailing: const AppIcon(AppGlyph.chevronRight),
                            onTap: () => Navigator.pop(context, tool),
                          ),
                      ],
                    ),
                ],
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
      ],
    ),
  );
}

class _ToolResultDialog extends StatelessWidget {
  const _ToolResultDialog({
    required this.output,
    required this.tool,
    required this.fileName,
  });
  final BookEditorToolResult output;
  final LocalEpubTool tool;
  final String fileName;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(output.applied ? '${tool.label}已应用' : '${tool.label}完成'),
    content: SizedBox(
      width: 680,
      height: 380,
      child: SingleChildScrollView(
        child: SelectableText(
          '${output.applied ? '已应用到工作副本，可撤销；保存按钮提交到书库。\n\n' : ''}${output.result.message}',
        ),
      ),
    ),
    actions: [
      if (tool.output == LocalToolOutput.export)
        TextButton(
          onPressed: () async {
            try {
              final saved = await _saveToolOutput(
                output.result.files,
                fileName,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(saved ? '文件已导出' : '已取消导出')),
                );
              }
            } on FileSystemException catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('导出失败：${error.message}')),
                );
              }
            }
          },
          child: const Text('导出文件'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}

Future<bool> _saveToolOutput(List<String> files, String title) async {
  if (files.length == 1) {
    final extension = p.extension(files.single).substring(1);
    final location = await getSaveLocation(
      suggestedName: '${_safeTitle(title)}.$extension',
      acceptedTypeGroups: [
        XTypeGroup(label: extension, extensions: [extension]),
      ],
    );
    if (location == null) return false;
    await XFile(files.single).saveTo(location.path);
    return true;
  }
  final directory = await getDirectoryPath(confirmButtonText: '导出分册');
  if (directory == null) return false;
  final targets = [
    for (final (index, _) in files.indexed)
      File(p.join(directory, '${_safeTitle(title)}_${index + 1}.epub')),
  ];
  for (final target in targets) {
    if (await target.exists()) {
      throw FileSystemException('分册已存在，不覆盖已有文件', target.path);
    }
  }
  for (final (index, file) in files.indexed) {
    await XFile(file).saveTo(targets[index].path);
  }
  return true;
}

String _safeTitle(String title) =>
    title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
