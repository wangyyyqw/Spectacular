import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';
import 'package:spectacular_epub_tools/local_epub_tools.dart';

import 'editor_icon.dart';

import 'book_editor_controller.dart';
import 'book_editor_toolkit.dart';
import 'book_editor_tools.dart';
import '../diagnostics/reader_log.dart';

part 'book_editor_local_forms.dart';
part 'book_editor_local_navigation.dart';
part 'book_editor_local_health.dart';

Future<T?> _localDrawer<T>(BuildContext context, WidgetBuilder builder) =>
    showReaderDrawer<T>(
      context: context,
      builder: builder,
      waitForDismissal: true,
    );

class BookEditorLocalTools {
  const BookEditorLocalTools(this.context, this.editor, this.title);
  final BuildContext context;
  final BookEditorController editor;
  final String title;

  Future<void> open(LocalEpubTool tool) async {
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
      await _localDrawer<void>(
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
      return _localDrawer<Map<String, Object?>>(
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
      fixes = await _localDrawer<List<String>>(
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
      navigation = await _localDrawer<EpubNavigationDocument>(
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
      points = await _localDrawer<List<int>>(
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
      targets = await _localDrawer<Map<String, Object?>>(
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

class _ToolResultDialog extends StatefulWidget {
  const _ToolResultDialog({
    required this.output,
    required this.tool,
    required this.fileName,
  });
  final BookEditorToolResult output;
  final LocalEpubTool tool;
  final String fileName;

  @override
  State<_ToolResultDialog> createState() => _ToolResultDialogState();
}

class _ToolResultDialogState extends State<_ToolResultDialog> {
  bool _exporting = false;
  bool _exportFailed = false;
  String? _exportMessage;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async =>
          _exporting ? AppExitResponse.cancel : AppExitResponse.exit,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _exportFailed = false;
      _exportMessage = '正在导出文件…';
    });
    try {
      final saved = await _saveToolOutput(
        widget.output.result.files,
        widget.fileName,
      );
      recordAppEvent(
        saved ? 'editor_file_exported' : 'editor_file_export_cancelled',
      );
      if (mounted) {
        setState(() => _exportMessage = saved ? '文件已导出' : '已取消导出，可重新选择保存位置');
      }
    } catch (error, stackTrace) {
      recordAppError(
        'editor_file_export_failed',
        error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _exportFailed = true;
          final reason = error is FileSystemException
              ? error.message
              : '$error';
          _exportMessage = '导出失败：$reason。请检查保存位置后重试。';
        });
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_exporting,
    child: ReaderSheetForm(
      title: Text(
        widget.output.applied
            ? '${widget.tool.label}已应用'
            : '${widget.tool.label}完成',
      ),
      showCloseButton: !_exporting,
      content: SizedBox(
        width: 680,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  '${widget.output.applied ? '已应用到工作副本，可撤销；保存按钮提交到书库。\n\n' : ''}${widget.output.result.message}',
                ),
              ),
            ),
            if (_exporting) const LinearProgressIndicator(),
            if (_exportMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _exportMessage!,
                    style: _exportFailed
                        ? TextStyle(color: Theme.of(context).colorScheme.error)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.tool.output == LocalToolOutput.export)
          TextButton(
            onPressed: _exporting ? null : _export,
            child: Text(_exportFailed ? '重试导出' : '导出文件'),
          ),
        TextButton(
          onPressed: _exporting ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
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
