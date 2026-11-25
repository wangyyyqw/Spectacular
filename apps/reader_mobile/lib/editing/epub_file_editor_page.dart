import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_editor_controller.dart';
import 'book_editor_page.dart';
import 'epub_export.dart';

/// 本地文件编辑入口，打开和输出 EPUB 均不写入书库。
class EpubFileEditorPage extends StatefulWidget {
  const EpubFileEditorPage({
    super.key,
    this.active = true,
    this.pickFile = _pickFile,
    this.saveFile = EpubExport.save,
  });

  final bool active;
  final Future<String?> Function() pickFile;
  final Future<bool> Function(File source, {required String fileName}) saveFile;

  static Future<String?> _pickFile() async => (await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'EPUB 电子书', extensions: ['epub']),
    ],
  ))?.path;

  @override
  State<EpubFileEditorPage> createState() => _EpubFileEditorPageState();
}

class _EpubFileEditorPageState extends State<EpubFileEditorPage> {
  final _keyboardFocus = FocusNode();
  bool _opening = false;
  String? _error;

  @override
  void didUpdateWidget(EpubFileEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) _keyboardFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening || !widget.active) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final selected = await widget.pickFile();
      if (selected != null && mounted && widget.active) {
        await _editFile(selected);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '打开 EPUB 失败：$error');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _editFile(String selected) async {
    final session = await EpubEditSession.open(File(selected));
    if (!mounted || !widget.active) {
      session.close();
      return;
    }
    final title = path.basenameWithoutExtension(selected);
    final controller = BookEditorController(
      session: session,
      commit: (session) => _save(session, title),
      export: (session) => _save(session, title),
    );
    final route = MaterialPageRoute<bool>(
      builder: (_) => BookEditorPage(controller: controller, title: title),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
  }

  Future<void> _save(EpubEditSession session, String title) async {
    final directory = await EpubExport.createTemporaryDirectory();
    try {
      final output = File('${directory.path}/edited.epub');
      await EpubWriter.write(session, output);
      if (!await widget.saveFile(output, fileName: '${title}_已编辑.epub')) {
        throw const EditorExportCancelled();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      if (widget.active)
        SingleActivator(
          LogicalKeyboardKey.keyO,
          meta: Theme.of(context).platform == TargetPlatform.macOS,
          control: Theme.of(context).platform != TargetPlatform.macOS,
        ): () =>
            unawaited(_open()),
    },
    child: ExcludeFocus(
      excluding: !widget.active,
      child: Focus(
        focusNode: _keyboardFocus,
        autofocus: widget.active,
        child: Scaffold(
          appBar: AppBar(title: const Text('编辑')),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppGlyph.editNote,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '直接编辑本地 EPUB',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '从文件管理器选择 EPUB，修改正文、样式或书籍资源。保存时选择输出位置，无需导入书架。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const ValueKey('editor-open-file'),
                      onPressed: _opening ? null : _open,
                      icon: const AppIcon(AppGlyph.folder),
                      label: Text(_opening ? '正在打开 EPUB…' : '打开 EPUB 文件'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 20),
                      SelectableText(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
