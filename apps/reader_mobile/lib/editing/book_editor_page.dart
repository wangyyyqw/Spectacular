import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_core/editing/editable_document.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:spectacular_epub_tools/local_epub_tools.dart';

import 'editor_icon.dart';

import 'book_editor_controller.dart';
import 'book_editor_local_tools.dart';
import 'book_editor_element_sheet.dart';
import 'book_editor_inspector.dart';
import 'book_editor_preview.dart';
import 'book_editor_source.dart';
import 'book_editor_search.dart';
import 'book_editor_new_html.dart';
import 'book_editor_image_dialog.dart';
import 'book_editor_note_dialog.dart';
import 'book_editor_tools.dart';
import '../diagnostics/reader_log.dart';
import '../home/desktop_shortcuts_dialog.dart';

/// 桌面编辑工作台：按窗口可用空间停靠书籍浏览器、源码和手机预览。
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
  static const _splitWidth = 720.0;
  static const _dockWidth = 1000.0;
  BookEditorController get editor => widget.controller;
  final _scaffold = GlobalKey<ScaffoldState>();
  final _sourceKey = GlobalKey();
  final _previewKey = GlobalKey();
  double _treeWidth = 208;
  double _sourceRatio = .57;
  int _compactTab = 0;
  bool _canPop = false;
  bool _savedInSession = false;
  bool _elementOpen = false;
  bool _initialTargetHandled = false;
  EditableElementRef? _selectedElement;
  EditorSourceBottomTab _sourceBottom = EditorSourceBottomTab.find;
  bool _filesPinned = true;
  bool _isDesktop = false;
  bool _confirmingLeave = false;
  String? _messageText;
  late final AppLifecycleListener _lifecycle;
  late final BookEditorSearch _search;
  bool _followPreview = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _requestExit);
    editor.addListener(_changed);
    final paths = editor.session.spinePaths;
    if (paths.isNotEmpty && editor.activePath == null) {
      final spine = editor.initialTarget?.spineIndex ?? 0;
      editor.openDocument(paths.elementAtOrNull(spine) ?? paths.first);
    }
    _search = BookEditorSearch(editor);
  }

  void _changed() {
    if (editor.hasPendingText ||
        _selectedElement?.revision != editor.session.revision) {
      _selectedElement = null;
    }
    if (editor.sourceRequested) {
      editor.sourceRequested = false;
      _compactTab = 1;
      if (_selectedElement?.path != editor.activePath) _selectedElement = null;
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
    _search.dispose();
    _lifecycle.dispose();
    editor.removeListener(_changed);
    super.dispose();
  }

  Future<void> _leave() async {
    final saved = await _confirmLeave();
    if (saved == null || !mounted) return;
    setState(() => _canPop = true);
    Navigator.pop(context, saved || _savedInSession);
  }

  Future<AppExitResponse> _requestExit() async => await _confirmLeave() == null
      ? AppExitResponse.cancel
      : AppExitResponse.exit;

  /// 返回是否保存；取消、保存失败或正在处理时不允许退出。
  Future<bool?> _confirmLeave() async {
    if (editor.busy || _confirmingLeave) return null;
    _confirmingLeave = true;
    try {
      if (!editor.dirty) return false;
      final choice = await _chooseLeave();
      if (!mounted || choice == null) return null;
      if (choice == 'save') {
        FocusManager.instance.primaryFocus?.unfocus();
        return await editor.save() ? true : null;
      }
      if (choice == 'discard') {
        return await editor.discard() ? false : null;
      }
      await editor.persistDraft();
      return false;
    } catch (error) {
      if (mounted) _message('$error');
      return null;
    } finally {
      _confirmingLeave = false;
    }
  }

  Future<String?> _chooseLeave() => showReaderDialog<String>(
    context: context,
    builder: (context) => ReaderFrostedAlertDialog(
      title: const Text('如何处理未保存的修改？'),
      content: Text(
        editor.saveDraft == null
            ? '保存可选择 EPUB 的输出位置；放弃会丢失本次未保存的修改，原文件不变。'
            : '保存会更新书籍；保留草稿可下次继续；放弃会删除本次草稿，不能恢复。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('继续编辑'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'discard'),
          child: const Text('放弃修改并退出'),
        ),
        if (editor.saveDraft != null)
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

  Future<void> _save({bool close = false}) async {
    if (editor.busy) return;
    final focus = FocusManager.instance.primaryFocus;
    _scaffold.currentState?.closeDrawer();
    if (!await editor.save() || !mounted) return;
    _savedInSession = true;
    if (close) {
      setState(() => _canPop = true);
      Navigator.pop(context, true);
    } else {
      _message('书籍已保存');
      if (focus?.context != null && focus!.canRequestFocus) {
        focus.requestFocus();
      }
    }
  }

  Future<void> _editTarget(ReaderEditTarget target) async {
    if (_elementOpen) return;
    try {
      final element = editor.resolveTarget(target);
      editor.openDocument(element.path, offset: element.sourceStart);
      final doc = editor.activeDocument!;
      final start = doc.code.selection;
      editor.openDocument(element.path, offset: element.sourceEnd);
      final end = doc.code.selection;
      doc.code.selection = CodeLineSelection(
        baseIndex: end.extentIndex,
        baseOffset: end.extentOffset,
        extentIndex: start.baseIndex,
        extentOffset: start.baseOffset,
      );
      doc.code.makeCursorVisible();
      setState(() {
        _selectedElement = element;
        if (!_isDesktop) _compactTab = 1;
      });
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  Future<void> _editElement(EditableElementRef element) async {
    if (_elementOpen) return;
    try {
      editor.session.checkElement(element);
      _elementOpen = true;
      await showReaderBottomSheet<void>(
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

  void _openDocumentFind({bool all = false}) {
    setState(() {
      _sourceBottom = EditorSourceBottomTab.find;
      _compactTab = 1;
    });
    if (!all) _search.setScope(EditorSearchScope.current);
    _search.focus(all: all);
  }

  Future<void> _locateSource() async {
    final element = await editor.locateSource();
    if (element == null || !mounted) return;
    setState(() {
      _selectedElement = element;
      _compactTab = 0;
    });
  }

  Future<void> _followSource() async {
    final element = await editor.locateSource(reportErrors: false);
    if (element != null &&
        mounted &&
        _sourceBottom == EditorSourceBottomTab.inspector) {
      setState(() => _selectedElement = element);
    }
  }

  Future<void> _localTool(LocalEpubTool tool) async {
    if (editor.busy) return;
    try {
      await BookEditorLocalTools(context, editor, widget.title).open(tool);
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  Future<void> _insertContent(String action) async {
    if (editor.busy || !editor.flush()) return;
    final path = editor.activePath;
    final offset = editor.sourceOffset;
    if (path == null ||
        offset == null ||
        !editor.session.previewPaths.contains(path)) {
      _message('请先打开正文 HTML，将光标放在要插入的位置。');
      return;
    }
    final element = editor.session
        .editableDocument(path)
        .elementAtOffset(offset);
    if (element == null ||
        (element.tag != 'body' &&
            !element.ancestors.any((node) => node.tag == 'body'))) {
      _message('请把光标放到 body 正文或点击预览中的目标段落。');
      return;
    }
    if (action == 'insert-image') {
      await insertBookImage(context, editor, element);
    } else {
      await editBookNote(context, editor, element, sourceOffset: offset);
    }
  }

  void _selectElement(EditableElementRef element) {
    editor.openDocument(element.path, offset: element.sourceStart);
    setState(() => _selectedElement = element);
  }

  void _message(String text) {
    recordAppEvent('editor_message', fields: {'message': text});
    setState(() => _messageText = text);
  }

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
        _openDocumentFind(all: true);
      case 'add':
        await tools.addResource();
      case 'new-html':
        await createBookHtml(context, editor);
      case 'style-library':
        await tools.styleLibrary(target: _selectedElement);
      case 'insert-image':
      case 'edit-note':
        await _insertContent(action);
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
    await showReaderDialog<void>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, bounds) {
      _isDesktop = bounds.maxWidth >= _splitWidth;
      final wide = bounds.maxWidth >= _dockWidth;
      return PopScope(
        canPop: _canPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_leave());
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(
              LogicalKeyboardKey.f1,
              includeRepeats: false,
            ): () =>
                unawaited(showDesktopShortcuts(context)),
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _openDocumentFind,
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                _openDocumentFind,
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
                unawaited(_save()),
            const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
                unawaited(_save()),
            const SingleActivator(
              LogicalKeyboardKey.keyS,
              control: true,
              shift: true,
              includeRepeats: false,
            ): () =>
                unawaited(_tool('export')),
            const SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
              shift: true,
              includeRepeats: false,
            ): () =>
                unawaited(_tool('export')),
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
          child: Actions(
            actions: {
              CodeShortcutSaveIntent: CallbackAction<CodeShortcutSaveIntent>(
                onInvoke: (_) {
                  unawaited(_save());
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                key: _scaffold,
                appBar: _toolbar(wide),
                drawer: _isDesktop && !wide
                    ? Drawer(width: 268, child: SafeArea(child: _files()))
                    : null,
                body: _body(bounds.maxWidth, wide && _filesPinned),
              ),
            ),
          ),
        ),
      );
    },
  );

  AppBar _toolbar(bool wide) => AppBar(
    toolbarHeight: 40,
    leadingWidth: 40,
    titleSpacing: 8,
    leading: IconButton(
      tooltip: '退出编辑',
      onPressed: _leave,
      icon: const EditorIcon(EditorGlyph.arrowBack),
    ),
    title: Tooltip(
      message: widget.title,
      child: Text(
        '${widget.title}${editor.dirty ? ' · 未保存' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
    actions: [
      if (_isDesktop) ..._desktopActions(wide),
      ..._editActions(),
      if (!_isDesktop) _toolsButton(),
    ],
  );

  List<Widget> _desktopActions(bool wide) => [
    IconButton(
      tooltip: wide && _filesPinned ? '收起书籍浏览器' : '打开书籍浏览器',
      icon: const EditorIcon(EditorGlyph.folder),
      onPressed: editor.busy ? null : () => _toggleFiles(wide),
    ),
    IconButton(
      tooltip: '全书查找替换',
      icon: const EditorIcon(EditorGlyph.search),
      onPressed: editor.busy ? null : () => _tool('find'),
    ),
    IconButton(
      tooltip: '校验书籍',
      icon: const EditorIcon(EditorGlyph.checklist),
      onPressed: editor.busy ? null : () => _tool('validate'),
    ),
    const VerticalDivider(indent: 12, endIndent: 12),
  ];

  List<Widget> _editActions() => [
    IconButton(
      tooltip: '撤销',
      onPressed: editor.busy ? null : editor.undo,
      icon: const EditorIcon(EditorGlyph.undo),
    ),
    IconButton(
      tooltip: '重做',
      onPressed: editor.busy ? null : editor.redo,
      icon: const EditorIcon(EditorGlyph.redo),
    ),
    IconButton(
      tooltip: '保存书籍',
      onPressed: editor.busy ? null : _save,
      icon: const EditorIcon(EditorGlyph.save),
    ),
  ];

  Widget _toolsButton() => PopupMenuButton<String>(
    icon: const EditorIcon(EditorGlyph.more),
    tooltip: '书籍工具',
    enabled: !editor.busy,
    onSelected: (value) => unawaited(_tool(value)),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'metadata', child: Text('书籍信息')),
      PopupMenuItem(value: 'chapters', child: Text('章节顺序与拆分合并')),
      PopupMenuItem(value: 'toc', child: Text('目录')),
      PopupMenuItem(value: 'find', child: Text('全书查找替换')),
      PopupMenuItem(value: 'add', child: Text('新增章节或资源')),
      PopupMenuItem(value: 'style-library', child: Text('样式库')),
      PopupMenuItem(value: 'validate', child: Text('校验书籍')),
      PopupMenuItem(value: 'history', child: Text('编辑历史与恢复')),
      PopupMenuItem(value: 'export', child: Text('导出 EPUB')),
    ],
  );

  Widget _body(double width, bool docked) => Column(
    children: [
      if (_isDesktop) _menus(width >= _dockWidth),
      _toolCategories(),
      if (editor.busy || editor.previewLoading)
        const LinearProgressIndicator(minHeight: 2),
      if (_messageText case final message?)
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(message, maxLines: 3),
                ),
              ),
              IconButton(
                tooltip: '关闭操作结果',
                onPressed: () => setState(() => _messageText = null),
                icon: const EditorIcon(EditorGlyph.close, size: 18),
              ),
            ],
          ),
        ),
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
          child: _isDesktop ? _desktop(width, docked) : _compact(),
        ),
      ),
    ],
  );

  Widget _menus(bool wide) => SizedBox(
    height: 30,
    width: double.infinity,
    child: MenuBar(
      style: const MenuStyle(
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
      ),
      children: [_fileMenu(), _editMenu(), _viewMenu(wide)],
    ),
  );

  Widget _fileMenu() => SubmenuButton(
    menuChildren: [
      MenuItemButton(
        leadingIcon: const EditorIcon(EditorGlyph.save, size: 18),
        onPressed: editor.busy ? null : _save,
        shortcut: SingleActivator(
          LogicalKeyboardKey.keyS,
          meta: Theme.of(context).platform == TargetPlatform.macOS,
          control: Theme.of(context).platform != TargetPlatform.macOS,
        ),
        child: const Text('保存书籍'),
      ),
      MenuItemButton(
        onPressed: editor.busy ? null : () => _save(close: true),
        child: const Text('保存并退出编辑'),
      ),
      _toolItem('导出 EPUB', 'export'),
      _toolItem('新增章节或资源', 'add'),
      _toolItem('新建空白 HTML', 'new-html'),
      _toolItem('编辑历史与恢复', 'history'),
      MenuItemButton(
        shortcut: const SingleActivator(LogicalKeyboardKey.f1),
        onPressed: () => showDesktopShortcuts(context),
        child: const Text('编辑器快捷键'),
      ),
    ],
    child: const Text('文件'),
  );

  Widget _editMenu() => SubmenuButton(
    menuChildren: [
      MenuItemButton(
        leadingIcon: const EditorIcon(EditorGlyph.undo, size: 18),
        onPressed: editor.busy ? null : editor.undo,
        child: const Text('撤销'),
      ),
      MenuItemButton(
        leadingIcon: const EditorIcon(EditorGlyph.redo, size: 18),
        onPressed: editor.busy ? null : editor.redo,
        child: const Text('重做'),
      ),
      MenuItemButton(
        leadingIcon: const EditorIcon(EditorGlyph.search, size: 18),
        onPressed: _openDocumentFind,
        child: const Text('在文档中查找'),
      ),
      _toolItem('全书查找替换', 'find'),
      _toolItem('样式库', 'style-library'),
    ],
    child: const Text('编辑'),
  );

  Widget _toolCategories() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Container(
      key: const ValueKey('editor-tools-toolbar'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: [
          for (final (label, icon) in [
            ('转换', EditorGlyph.convert),
            ('结构', EditorGlyph.structure),
            ('图片', EditorGlyph.image),
            ('字体', EditorGlyph.textFields),
            ('注释与正文', EditorGlyph.annotations),
          ])
            _categoryButton(label, icon),
          TextButton.icon(
            key: const ValueKey('editor-style-library'),
            onPressed: editor.busy
                ? null
                : () => unawaited(_tool('style-library')),
            icon: const EditorIcon(EditorGlyph.styleLibrary, size: 20),
            label: const Text('样式库'),
          ),
        ],
      ),
    ),
  );

  Widget _categoryButton(String label, EditorGlyph icon) => MenuAnchor(
    menuChildren: [
      if (label == '结构') ...[
        _toolItem('新建空白 HTML', 'new-html'),
        _toolItem('书籍信息', 'metadata'),
        _toolItem('目录', 'toc'),
        _toolItem('章节顺序与拆分合并', 'chapters'),
        _toolItem('校验书籍', 'validate'),
        const Divider(height: 1),
      ],
      if (label == '图片') ...[
        _toolItem('插入图片', 'insert-image'),
        const Divider(height: 1),
      ],
      if (label == '注释与正文') ...[
        _toolItem('设置 EPUB 注释', 'edit-note'),
        const Divider(height: 1),
      ],
      for (final tool in LocalEpubTool.visible.where(
        (tool) => tool.category == label,
      ))
        MenuItemButton(
          leadingIcon: EditorIcon(switch (tool) {
            LocalEpubTool.split => EditorGlyph.split,
            LocalEpubTool.merge => EditorGlyph.merge,
            LocalEpubTool.reformat => EditorGlyph.format,
            _ => icon,
          }, size: 18),
          onPressed: editor.busy ? null : () => unawaited(_localTool(tool)),
          child: Tooltip(message: tool.description, child: Text(tool.label)),
        ),
    ],
    builder: (context, menu, _) => TextButton.icon(
      key: ValueKey('editor-category-$label'),
      onPressed: editor.busy
          ? null
          : () => menu.isOpen ? menu.close() : menu.open(),
      icon: EditorIcon(icon, size: 20),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 6),
          const EditorIcon(EditorGlyph.chevronDown, size: 12),
        ],
      ),
    ),
  );

  Widget _viewMenu(bool wide) => SubmenuButton(
    menuChildren: [
      MenuItemButton(
        leadingIcon: const EditorIcon(EditorGlyph.folder, size: 18),
        onPressed: () => _toggleFiles(wide),
        child: Text(wide && _filesPinned ? '收起书籍浏览器' : '打开书籍浏览器'),
      ),
      MenuItemButton(
        leadingIcon: const EditorIcon(EditorGlyph.tune, size: 18),
        onPressed: () =>
            setState(() => _sourceBottom = EditorSourceBottomTab.inspector),
        child: const Text('样式检查器'),
      ),
    ],
    child: const Text('视图'),
  );

  Widget _toolItem(String label, String action) => MenuItemButton(
    leadingIcon: EditorIcon(switch (action) {
      'export' => EditorGlyph.export,
      'history' => EditorGlyph.history,
      'metadata' => EditorGlyph.metadata,
      'toc' => EditorGlyph.toc,
      'chapters' => EditorGlyph.structure,
      'add' => EditorGlyph.add,
      'new-html' => EditorGlyph.code,
      'insert-image' => EditorGlyph.addImage,
      'edit-note' => EditorGlyph.editNote,
      'style-library' => EditorGlyph.styleLibrary,
      'validate' => EditorGlyph.checklist,
      _ => EditorGlyph.replace,
    }, size: 18),
    onPressed: editor.busy ? null : () => unawaited(_tool(action)),
    child: Text(label),
  );

  void _toggleFiles(bool wide) {
    if (wide) {
      setState(() => _filesPinned = !_filesPinned);
    } else {
      _scaffold.currentState?.openDrawer();
    }
  }

  Widget _preview() {
    final source = editor.previewSource;
    return Column(
      key: _previewKey,
      children: [
        SizedBox(
          height: 36,
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Tooltip(
                message: '点击预览段落定位源码；样式检查器查看对应样式',
                child: EditorIcon(EditorGlyph.preview, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '手机预览',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '1080 × 2400',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              ReaderDropdownButton<bool>(
                icon: const EditorIcon(EditorGlyph.chevronDown),
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
        if (editor.hasPendingText || editor.hasErrors)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              editor.hasErrors ? '源码校验未通过，显示上次有效预览' : '正在等待源码校验…',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: source == null
              ? Center(child: Text(editor.previewLoading ? '正在生成预览…' : '预览不可用'))
              : BookEditorPreview(
                  key: ValueKey(
                    'preview-${editor.previewRevision}-${editor.useReadingSettings}',
                  ),
                  source: source,
                  bookTitle: widget.title,
                  revision: editor.previewRevision,
                  target: editor.previewTarget,
                  navigation: editor.previewNavigation,
                  settings: editor.useReadingSettings
                      ? editor.readingSettings
                      : null,
                  onLocationChanged: editor.rememberPreviewLocation,
                  onEditTarget: (target) => unawaited(_editTarget(target)),
                ),
        ),
      ],
    );
  }

  Widget _files() => BookEditorFiles(
    editor: editor,
    onOpen: () {
      if (_scaffold.currentState?.isDrawerOpen == true) {
        _scaffold.currentState!.closeDrawer();
      }
      if (!_isDesktop) setState(() => _compactTab = 1);
    },
  );

  Widget _source() => BookEditorSource(
    key: _sourceKey,
    controller: editor,
    onLocate: () => unawaited(_locateSource()),
    onCursorChanged: () => unawaited(_followSource()),
    search: _search,
    followPreview: _followPreview,
    onFollowPreviewChanged: (follow) => setState(() => _followPreview = follow),
    bottomTab: _sourceBottom,
    onBottomTabChanged: (tab) => setState(() => _sourceBottom = tab),
    inspector: _inspector(),
  );

  Widget _inspector() => _selectedElement == null
      ? const Center(child: Text('点击预览元素或从源码定位，查看样式。'))
      : BookEditorInspector(
          editor: editor,
          element: _selectedElement!,
          onSelect: _selectElement,
          onEdit: () => unawaited(_editElement(_selectedElement!)),
        );

  Widget _compact() => Column(
    children: [
      SizedBox(
        height: 48,
        child: Row(
          children: [
            for (final (index, label) in ['预览', '源码', '文件'].indexed)
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _compactTab = index),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: _compactTab == index
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
          index: _compactTab,
          children: [_preview(), _source(), _files()],
        ),
      ),
    ],
  );

  Widget _desktop(double width, bool docked) {
    final tree = _treeWidth.clamp(176.0, (width * .28).clamp(176.0, 320.0));
    final remaining = width - (docked ? tree + 6 : 0) - 6;
    final sourceWidth = (remaining * _sourceRatio).clamp(
      332.0,
      remaining - 272,
    );
    return Row(
      children: [
        if (docked) ...[
          SizedBox(width: tree, child: _files()),
          _divider(
            (delta) =>
                setState(() => _treeWidth = (tree + delta).clamp(176, 320)),
          ),
        ],
        SizedBox(width: sourceWidth, child: _source()),
        _divider(
          (delta) => setState(
            () => _sourceRatio =
                (sourceWidth + delta).clamp(332.0, remaining - 272) / remaining,
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
