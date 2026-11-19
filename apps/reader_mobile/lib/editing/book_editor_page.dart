import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_core/editing/editable_document.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/reader_page.dart';

import 'book_editor_controller.dart';
import 'book_editor_local_tools.dart';
import 'book_editor_element_sheet.dart';
import 'book_editor_inspector.dart';
import 'book_editor_preview.dart';
import 'book_editor_source.dart';
import 'book_editor_tools.dart';

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
  double _treeWidth = 232;
  double _sourceRatio = .57;
  int _compactTab = 0;
  bool _canPop = false;
  bool _elementOpen = false;
  bool _initialTargetHandled = false;
  EditableElementRef? _selectedElement;
  bool _inspectorExpanded = false;
  bool _filesPinned = true;
  bool _isDesktop = false;

  @override
  void initState() {
    super.initState();
    editor.addListener(_changed);
    final paths = editor.session.spinePaths;
    if (paths.isNotEmpty && editor.activePath == null) {
      final spine = editor.initialTarget?.spineIndex ?? 0;
      editor.openDocument(paths.elementAtOrNull(spine) ?? paths.first);
    }
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
    _scaffold.currentState?.closeDrawer();
    if (!await editor.save() || !mounted) return;
    setState(() => _canPop = true);
    Navigator.pop(context, true);
  }

  Future<void> _editTarget(ReaderEditTarget target) async {
    if (_elementOpen) return;
    try {
      final element = editor.resolveTarget(target);
      editor.openDocument(element.path, offset: element.sourceStart);
      if (_isDesktop) {
        setState(() {
          _selectedElement = element;
          _inspectorExpanded = true;
        });
        return;
      }
      await _editElement(element);
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  Future<void> _editElement(EditableElementRef element) async {
    if (_elementOpen) return;
    try {
      editor.session.checkElement(element);
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

  Future<void> _locateSource() async {
    final element = await editor.locateSource();
    if (element == null || !mounted) return;
    setState(() {
      _selectedElement = element;
      _inspectorExpanded = true;
      _compactTab = 0;
    });
  }

  void _selectElement(EditableElementRef element) {
    editor.openDocument(element.path, offset: element.sourceStart);
    setState(() => _selectedElement = element);
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
      case 'local-tools':
        await BookEditorLocalTools(context, editor, widget.title).open();
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
    toolbarHeight: 48,
    titleSpacing: 8,
    leading: IconButton(
      tooltip: '退出编辑',
      onPressed: _leave,
      icon: const AppIcon(AppGlyph.arrowBack),
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
      icon: const AppIcon(AppGlyph.folder),
      onPressed: editor.busy ? null : () => _toggleFiles(wide),
    ),
    IconButton(
      tooltip: '全书查找替换',
      icon: const AppIcon(AppGlyph.search),
      onPressed: editor.busy ? null : () => _tool('find'),
    ),
    IconButton(
      tooltip: '校验书籍',
      icon: const AppIcon(AppGlyph.checklist),
      onPressed: editor.busy ? null : () => _tool('validate'),
    ),
    const VerticalDivider(indent: 12, endIndent: 12),
  ];

  List<Widget> _editActions() => [
    IconButton(
      tooltip: '撤销',
      onPressed: editor.busy ? null : editor.undo,
      icon: const AppIcon(AppGlyph.undo),
    ),
    IconButton(
      tooltip: '重做',
      onPressed: editor.busy ? null : editor.redo,
      icon: const AppIcon(AppGlyph.redo),
    ),
    IconButton(
      tooltip: '保存书籍',
      onPressed: editor.busy ? null : _save,
      icon: const AppIcon(AppGlyph.save),
    ),
  ];

  Widget _toolsButton() => PopupMenuButton<String>(
    icon: const AppIcon(AppGlyph.more),
    tooltip: '书籍工具',
    enabled: !editor.busy,
    onSelected: (value) => unawaited(_tool(value)),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'local-tools', child: Text('本地 EPUB 工具')),
      PopupMenuItem(value: 'metadata', child: Text('书籍信息')),
      PopupMenuItem(value: 'chapters', child: Text('章节顺序与拆分合并')),
      PopupMenuItem(value: 'toc', child: Text('目录')),
      PopupMenuItem(value: 'find', child: Text('全书查找替换')),
      PopupMenuItem(value: 'add', child: Text('新增章节或资源')),
      PopupMenuItem(value: 'validate', child: Text('校验书籍')),
      PopupMenuItem(value: 'history', child: Text('编辑历史与恢复')),
      PopupMenuItem(value: 'export', child: Text('导出 EPUB')),
    ],
  );

  Widget _body(double width, bool docked) => Column(
    children: [
      if (_isDesktop) _menus(width >= _dockWidth),
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
          child: _isDesktop ? _desktop(width, docked) : _compact(),
        ),
      ),
    ],
  );

  Widget _menus(bool wide) => SizedBox(
    height: 34,
    width: double.infinity,
    child: MenuBar(
      style: const MenuStyle(
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
      ),
      children: [_fileMenu(), _editMenu(), _toolsMenu(), _viewMenu(wide)],
    ),
  );

  Widget _fileMenu() => SubmenuButton(
    menuChildren: [
      MenuItemButton(
        onPressed: editor.busy ? null : _save,
        child: const Text('保存书籍并返回'),
      ),
      _toolItem('导出 EPUB', 'export'),
      _toolItem('编辑历史与恢复', 'history'),
    ],
    child: const Text('文件'),
  );

  Widget _editMenu() => SubmenuButton(
    menuChildren: [
      MenuItemButton(
        onPressed: editor.busy ? null : editor.undo,
        child: const Text('撤销'),
      ),
      MenuItemButton(
        onPressed: editor.busy ? null : editor.redo,
        child: const Text('重做'),
      ),
      MenuItemButton(
        onPressed: editor.activeDocument?.find.findMode,
        child: const Text('在文档中查找'),
      ),
      _toolItem('全书查找替换', 'find'),
    ],
    child: const Text('编辑'),
  );

  Widget _toolsMenu() => SubmenuButton(
    menuChildren: [
      _toolItem('本地 EPUB 工具', 'local-tools'),
      _toolItem('书籍信息', 'metadata'),
      _toolItem('目录', 'toc'),
      _toolItem('章节顺序与拆分合并', 'chapters'),
      _toolItem('新增章节或资源', 'add'),
      _toolItem('校验书籍', 'validate'),
    ],
    child: const Text('工具'),
  );

  Widget _viewMenu(bool wide) => SubmenuButton(
    menuChildren: [
      MenuItemButton(
        onPressed: () => _toggleFiles(wide),
        child: Text(wide && _filesPinned ? '收起书籍浏览器' : '打开书籍浏览器'),
      ),
      MenuItemButton(
        onPressed: () =>
            setState(() => _inspectorExpanded = !_inspectorExpanded),
        child: Text(_inspectorExpanded ? '折叠样式检查器' : '展开样式检查器'),
      ),
    ],
    child: const Text('视图'),
  );

  Widget _toolItem(String label, String action) => MenuItemButton(
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
          height: 46,
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Tooltip(
                message: '点击段落编辑',
                child: AppIcon(AppGlyph.preview, size: 18),
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
              DropdownButton<bool>(
                icon: const AppIcon(AppGlyph.chevronDown),
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
    final tree = _treeWidth.clamp(200.0, (width * .28).clamp(200.0, 360.0));
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
                setState(() => _treeWidth = (tree + delta).clamp(200, 360)),
          ),
        ],
        SizedBox(width: sourceWidth, child: _source()),
        _divider(
          (delta) => setState(
            () => _sourceRatio =
                (sourceWidth + delta).clamp(332.0, remaining - 272) / remaining,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (_, bounds) => Column(
              children: [
                Expanded(child: _preview()),
                const Divider(height: 1),
                _inspectorToggle(),
                if (_inspectorExpanded)
                  SizedBox(
                    height: (bounds.maxHeight * .36).clamp(0.0, 260.0),
                    child: _selectedElement == null
                        ? const Center(child: Text('点击预览元素或从源码定位，查看样式。'))
                        : BookEditorInspector(
                            editor: editor,
                            element: _selectedElement!,
                            onSelect: _selectElement,
                            onEdit: () =>
                                unawaited(_editElement(_selectedElement!)),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _inspectorToggle() => Tooltip(
    message: _inspectorExpanded ? '折叠样式检查器' : '展开样式检查器',
    child: InkWell(
      onTap: () => setState(() => _inspectorExpanded = !_inspectorExpanded),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            const SizedBox(width: 12),
            const AppIcon(AppGlyph.tune, size: 16),
            const SizedBox(width: 8),
            const Expanded(child: Text('样式检查器')),
            AppIcon(
              _inspectorExpanded ? AppGlyph.chevronDown : AppGlyph.chevronUp,
              size: 18,
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    ),
  );

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
