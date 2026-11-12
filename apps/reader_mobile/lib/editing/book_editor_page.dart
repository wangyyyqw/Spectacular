import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_core/editing/package_editor.dart';
import 'package:reader_ui/reader_page.dart';

import 'book_editor_controller.dart';
import 'book_editor_element_sheet.dart';
import 'book_editor_preview.dart';
import 'book_editor_source.dart';
import 'book_editor_tools.dart';

/// 手机共享预览与段落编辑，宽屏展开为文件、源码、预览三个区域。
class BookEditorPage extends StatefulWidget {
  const BookEditorPage({
    super.key,
    required this.controller,
    required this.title,
    this.restoreOriginal,
    this.restorePrevious,
  });
  final BookEditorController controller;
  final String title;
  final Future<void> Function()? restoreOriginal;
  final Future<void> Function()? restorePrevious;

  @override
  State<BookEditorPage> createState() => _BookEditorPageState();
}

class _BookEditorPageState extends State<BookEditorPage> {
  BookEditorController get editor => widget.controller;
  double _treeWidth = 210;
  double _sourceRatio = .53;
  int _mobileTab = 0;
  bool _canPop = false;
  bool _elementOpen = false;
  bool _initialTargetHandled = false;

  @override
  void initState() {
    super.initState();
    editor.addListener(_changed);
    final chapters = PackageEditor(editor.session).chapters;
    if (chapters.isNotEmpty && editor.activePath == null) {
      editor.openDocument(chapters.first.path);
    }
  }

  void _changed() {
    if (editor.sourceRequested) {
      editor.sourceRequested = false;
      _mobileTab = 1;
    }
    if (mounted) setState(() {});
    if (!_initialTargetHandled &&
        editor.editInitialTarget &&
        editor.previewSource != null &&
        editor.initialTarget != null) {
      _initialTargetHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_editTarget(editor.initialTarget!));
      });
    }
  }

  @override
  void dispose() {
    editor.removeListener(_changed);
    super.dispose();
  }

  Future<void> _leave() async {
    if (editor.busy) return;
    if (editor.dirty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('如何处理未保存的修改？'),
          content: const Text('保存会更新书籍；保留草稿可下次继续；放弃会删除本次草稿，不能恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('放弃修改并退出'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'keep'),
              child: const Text('保留草稿并退出'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('保存书籍'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'save') {
        await _save();
        return;
      }
      if (choice == 'discard') {
        if (!await editor.discard()) return;
      } else {
        try {
          await editor.persistDraft();
        } catch (error) {
          if (mounted) _message('$error');
          return;
        }
      }
    }
    if (!mounted) return;
    setState(() => _canPop = true);
    Navigator.pop(context, false);
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!await editor.save() || !mounted) return;
    setState(() => _canPop = true);
    Navigator.pop(context, true);
  }

  Future<void> _editTarget(ReaderEditTarget target) async {
    if (_elementOpen) return;
    try {
      final element = editor.resolveTarget(target);
      editor.openDocument(element.path, offset: element.sourceStart);
      _elementOpen = true;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) =>
            BookEditorElementSheet(editor: editor, element: element),
      );
    } catch (error) {
      if (mounted) _message('$error');
    } finally {
      _elementOpen = false;
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _tool(String action) async {
    if (editor.busy) return;
    try {
      await _performTool(action);
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  Future<void> _performTool(String action) async {
    final tools = BookEditorTools(context, editor);
    switch (action) {
      case 'metadata':
        await tools.metadata();
      case 'toc':
        await tools.toc();
      case 'chapters':
        await tools.chapters();
      case 'find':
        await tools.findReplace();
      case 'add':
        await tools.addResource();
      case 'validate':
        await _validate();
      case 'history':
        await tools.history(
          restoreOriginal: widget.restoreOriginal,
          restorePrevious: widget.restorePrevious,
          onRestored: () {
            _canPop = true;
            Navigator.pop(context, true);
          },
        );
      case 'export':
        if (await editor.exportBook() && mounted) _message('导出完成');
    }
  }

  Future<void> _validate() async {
    if (!editor.runCommand(editor.session.validate)) return;
    final warnings = editor.session.validationWarnings;
    if (warnings.isEmpty) {
      _message('校验通过');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('校验通过，原书仍有告警'),
        content: SingleChildScrollView(child: Text(warnings.join('\n\n'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_leave());
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(_save()),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(_save()),
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): () =>
            unawaited(_tool('find')),
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: true,
          shift: true,
        ): () =>
            unawaited(_tool('find')),
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '退出编辑',
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            '${widget.title}${editor.dirty ? ' · 未保存' : ''}',
            maxLines: 1,
          ),
          actions: [
            IconButton(
              tooltip: '撤销',
              onPressed: editor.busy ? null : editor.undo,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: '重做',
              onPressed: editor.busy ? null : editor.redo,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: '保存书籍',
              onPressed: editor.busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: '书籍工具',
              onSelected: (value) => unawaited(_tool(value)),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'metadata', child: Text('书籍信息')),
                PopupMenuItem(value: 'chapters', child: Text('章节顺序与拆分合并')),
                PopupMenuItem(value: 'toc', child: Text('目录')),
                PopupMenuItem(value: 'find', child: Text('全书查找替换')),
                PopupMenuItem(value: 'add', child: Text('新增章节或资源')),
                PopupMenuItem(value: 'validate', child: Text('校验书籍')),
                PopupMenuItem(value: 'history', child: Text('编辑历史与恢复')),
                PopupMenuItem(value: 'export', child: Text('导出 EPUB')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (editor.busy || editor.previewLoading)
              const LinearProgressIndicator(minHeight: 2),
            if (editor.error ?? editor.draftError case final error?)
              MaterialBanner(
                content: Text(error, maxLines: 3),
                actions: [
                  TextButton(
                    onPressed: () {
                      editor.error = null;
                      _changed();
                    },
                    child: const Text('收起'),
                  ),
                ],
              ),
            Expanded(
              child: AbsorbPointer(
                absorbing: editor.busy,
                child: LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 960
                      ? _desktop(constraints.maxWidth)
                      : _mobile(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _preview() {
    final source = editor.previewSource;
    if (source == null) return const Center(child: Text('正在生成预览…'));
    return Column(
      children: [
        SizedBox(
          height: 42,
          child: Row(
            children: [
              const SizedBox(width: 8),
              const Text('预览样式'),
              const SizedBox(width: 8),
              const Tooltip(
                message: '点击段落编辑',
                child: Icon(Icons.touch_app_outlined, size: 18),
              ),
              const Spacer(),
              DropdownButton<bool>(
                value: editor.useReadingSettings,
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(value: false, child: Text('书籍原始样式')),
                  if (editor.readingSettings != null)
                    const DropdownMenuItem(value: true, child: Text('当前阅读设置')),
                ],
                onChanged: (value) => editor.setPreviewSettings(value ?? false),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: BookEditorPreview(
            key: ValueKey(
              'preview-${editor.previewRevision}-${editor.useReadingSettings}',
            ),
            source: source,
            revision: editor.previewRevision,
            target: editor.previewTarget,
            settings: editor.useReadingSettings ? editor.readingSettings : null,
            onLocationChanged: (target) => editor.previewTarget = target,
            onEditTarget: (target) => unawaited(_editTarget(target)),
          ),
        ),
      ],
    );
  }

  Widget _files() => BookEditorFiles(
    editor: editor,
    onOpen: () {
      if (MediaQuery.sizeOf(context).width < 960) {
        setState(() => _mobileTab = 1);
      }
    },
  );

  Widget _mobile() => Column(
    children: [
      SizedBox(
        height: 48,
        child: Row(
          children: [
            for (final (index, label) in ['预览', '源码', '文件'].indexed)
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _mobileTab = index),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: _mobileTab == index
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: IndexedStack(
          index: _mobileTab,
          children: [
            _preview(),
            BookEditorSource(controller: editor),
            _files(),
          ],
        ),
      ),
    ],
  );

  Widget _desktop(double width) {
    final tree = _treeWidth.clamp(160.0, width * .3);
    final remaining = width - tree - 12;
    return Row(
      children: [
        SizedBox(width: tree, child: _files()),
        _divider(
          (delta) => setState(
            () => _treeWidth = (tree + delta).clamp(160, width * .3),
          ),
        ),
        SizedBox(
          width: remaining * _sourceRatio,
          child: BookEditorSource(controller: editor),
        ),
        _divider(
          (delta) => setState(
            () =>
                _sourceRatio = (_sourceRatio + delta / remaining).clamp(.3, .7),
          ),
        ),
        Expanded(child: _preview()),
      ],
    );
  }

  Widget _divider(ValueChanged<double> drag) => Semantics(
    label: '调整分栏宽度',
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => drag(details.delta.dx),
        child: const SizedBox(width: 6, child: VerticalDivider(width: 1)),
      ),
    ),
  );
}
