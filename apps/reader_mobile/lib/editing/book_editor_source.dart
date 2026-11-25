import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

import 'editor_icon.dart';

import 'book_editor_controller.dart';
import 'book_editor_find_bar.dart';
import 'book_editor_search.dart';
import 'book_editor_tools.dart';
import 'xhtml_chunk_analyzer.dart';

export 'book_editor_find_bar.dart';

enum EditorSourceBottomTab { find, inspector }

class BookEditorSource extends StatefulWidget {
  const BookEditorSource({
    super.key,
    required this.controller,
    this.onLocate,
    this.onCursorChanged,
    required this.search,
    this.followPreview = true,
    this.onFollowPreviewChanged,
    this.bottomTab = EditorSourceBottomTab.find,
    this.onBottomTabChanged,
    this.inspector,
  });
  final BookEditorController controller;
  final VoidCallback? onLocate;
  final VoidCallback? onCursorChanged;
  final BookEditorSearch search;
  final bool followPreview;
  final ValueChanged<bool>? onFollowPreviewChanged;
  final EditorSourceBottomTab bottomTab;
  final ValueChanged<EditorSourceBottomTab>? onBottomTabChanged;
  final Widget? inspector;

  @override
  State<BookEditorSource> createState() => _BookEditorSourceState();
}

class _BookEditorSourceState extends State<BookEditorSource> {
  final _codeFocus = FocusNode();
  Timer? _cursorFollow;
  BookEditorDocument? _displayedDocument;
  bool _wrap = true;

  @override
  void initState() {
    super.initState();
    _codeFocus.addListener(_followCursor);
  }

  void _followCursor() {
    _cursorFollow?.cancel();
    if (widget.onCursorChanged == null ||
        !_codeFocus.hasFocus ||
        !widget.followPreview ||
        widget.controller.busy ||
        !widget.controller.session.previewPaths.contains(
          widget.controller.activePath,
        )) {
      return;
    }
    _cursorFollow = Timer(const Duration(milliseconds: 160), () {
      if (mounted && _codeFocus.hasFocus && widget.followPreview) {
        widget.onCursorChanged?.call();
      }
    });
  }

  @override
  void dispose() {
    _cursorFollow?.cancel();
    _codeFocus.dispose();
    super.dispose();
  }

  void _focusSource() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.activeDocument != null) {
        _codeFocus.requestFocus();
      }
    });
  }

  void _showSource(String path) {
    if (widget.controller.busy) return;
    widget.controller.showSource(path);
    _focusSource();
  }

  void _switchDocument(int direction) {
    final editor = widget.controller;
    if (editor.busy || editor.documents.length < 2) return;
    final paths = editor.documents.keys.toList();
    final current = paths.indexOf(editor.activePath!);
    _showSource(paths[(current + direction) % paths.length]);
  }

  void _closeDocument(String path) {
    final editor = widget.controller;
    if (editor.busy) return;
    editor.closeDocument(path);
    _focusSource();
  }

  Future<void> _goToLine() async {
    final editor = widget.controller;
    final doc = editor.activeDocument;
    if (editor.busy || doc == null) return;
    final position = doc.code.unfoldLineSelection;
    final input = await editorPrompt(
      context,
      '跳转到行（1–${doc.code.lineCount}）',
      initial: '${position.extentIndex + 1}:${position.extentOffset + 1}',
    );
    if (input == null || !mounted || editor.activeDocument != doc) return;
    final match = RegExp(r'^\s*(\d+)(?::(\d+))?\s*$').firstMatch(input);
    final line = match == null ? null : int.tryParse(match[1]!);
    final column = match?[2] == null ? 1 : int.tryParse(match![2]!);
    if (line == null ||
        line < 1 ||
        line > doc.code.lineCount ||
        column == null ||
        column < 1) {
      setState(() => _navigationError = '请输入有效的行号，或“行号:列号”。');
      return;
    }
    final lines = doc.code.text.split('\n');
    final offset =
        lines
            .take(line - 1)
            .fold<int>(0, (total, text) => total + text.length + 1) +
        (column - 1).clamp(0, lines[line - 1].replaceAll('\r', '').length);
    editor.openDocument(doc.path, offset: offset);
    setState(() => _navigationError = null);
    _focusSource();
  }

  String? _navigationError;

  @override
  Widget build(BuildContext context) {
    final editor = widget.controller;
    final doc = editor.activeDocument;
    if (_displayedDocument != doc) {
      _displayedDocument = doc;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.controller.activeDocument == doc) {
          doc?.code.makeCursorVisible();
        }
      });
    }
    final source = Material(
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (_, bounds) => Column(
          children: [
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final file in editor.documents.values) _tab(file),
                ],
              ),
            ),
            const Divider(height: 1),
            if (doc == null)
              const Expanded(child: Center(child: Text('从书籍浏览器打开正文、样式或包文件')))
            else ...[
              if (_navigationError case final message?)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (doc.error != null)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    '校验未通过，预览保留上次有效内容。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(child: _code(doc)),
            ],
            const Divider(height: 1),
            if (doc != null && widget.inspector != null) _bottomSwitch(),
            if (doc != null &&
                widget.inspector != null &&
                widget.bottomTab == EditorSourceBottomTab.inspector)
              SizedBox(
                height: (bounds.maxHeight * .42).clamp(0.0, 280.0),
                child: widget.inspector,
              )
            else
              ListenableBuilder(
                listenable: widget.search,
                builder: (_, _) => widget.search.opened
                    ? ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (bounds.maxHeight * .48).clamp(0.0, 380.0),
                        ),
                        child: _findBar(),
                      )
                    : _findHint(),
              ),
            if (doc != null) _status(doc),
          ],
        ),
      ),
    );
    final macOS = Theme.of(context).platform == TargetPlatform.macOS;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyG,
          meta: macOS,
          control: !macOS,
          includeRepeats: false,
        ): () =>
            unawaited(_goToLine()),
        const SingleActivator(LogicalKeyboardKey.keyZ, alt: true): () =>
            setState(() => _wrap = !_wrap),
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          includeRepeats: false,
        ): () =>
            _switchDocument(1),
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
          includeRepeats: false,
        ): () =>
            _switchDocument(-1),
        SingleActivator(
          LogicalKeyboardKey.keyW,
          meta: macOS,
          control: !macOS,
          includeRepeats: false,
        ): () {
          if (editor.activePath case final path?) _closeDocument(path);
        },
      },
      child: source,
    );
  }

  Widget _bottomSwitch() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 34,
      width: double.infinity,
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _bottomTab(EditorSourceBottomTab.find, EditorGlyph.search, '查找替换'),
          _bottomTab(
            EditorSourceBottomTab.inspector,
            EditorGlyph.tune,
            '样式检查器',
          ),
        ],
      ),
    );
  }

  Widget _bottomTab(EditorSourceBottomTab tab, EditorGlyph icon, String label) {
    final colors = Theme.of(context).colorScheme;
    final selected = widget.bottomTab == tab;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => tab == EditorSourceBottomTab.find
              ? _openFind()
              : widget.onBottomTabChanged?.call(tab),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? colors.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                EditorIcon(
                  icon,
                  size: 14,
                  color: selected
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected
                        ? colors.onSecondaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _findBar() => EditorFindBar(
    search: widget.search,
    onClose: () {
      widget.search.close();
      _focusSource();
    },
  );

  Widget _findHint() {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 10),
          EditorIcon(
            EditorGlyph.search,
            size: 16,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '查找或替换正文与资源',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: _openFind, child: const Text('开始查找')),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  void _openFind({bool replace = false}) {
    widget.onBottomTabChanged?.call(EditorSourceBottomTab.find);
    widget.search.focus();
    if (replace) widget.search.replaceFocus.requestFocus();
  }

  Widget _tab(BookEditorDocument doc) {
    final editor = widget.controller;
    final active = doc.path == editor.activePath;
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onSecondaryTapDown: (details) => unawaited(
        showBookEditorFileMenu(
          context,
          editor,
          doc.path,
          details.globalPosition,
        ),
      ),
      child: Material(
        color: active ? colors.surfaceContainerLow : colors.surface,
        child: Row(
          children: [
            Tooltip(
              message: doc.path,
              child: Semantics(
                selected: active,
                child: InkWell(
                  key: ValueKey('document-${doc.path}'),
                  onTap: () => _showSource(doc.path),
                  child: Container(
                    alignment: Alignment.centerLeft,
                    constraints: const BoxConstraints(maxWidth: 190),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '${doc.path.split('/').last}${editor.documentDirty(doc.path) ? ' •' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: active
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '关闭 ${doc.path.split('/').last}',
              constraints: const BoxConstraints.tightFor(width: 28, height: 32),
              padding: EdgeInsets.zero,
              icon: const EditorIcon(EditorGlyph.close, size: 14),
              onPressed: () => _closeDocument(doc.path),
            ),
            const VerticalDivider(width: 1),
          ],
        ),
      ),
    );
  }

  Widget _code(BookEditorDocument doc) {
    final css = doc.path.toLowerCase().endsWith('.css');
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Listener(
      onPointerUp: (_) => _followCursor(),
      child: CodeEditor(
        key: ValueKey(doc.path),
        controller: doc.code,
        findController: doc.find,
        focusNode: _codeFocus,
        readOnly: widget.controller.busy,
        autofocus: false,
        wordWrap: _wrap,
        onChanged: (_) => _followCursor(),
        shortcutOverrideActions: {
          CodeShortcutFindIntent: CallbackAction<CodeShortcutFindIntent>(
            onInvoke: (_) {
              _openFind();
              return null;
            },
          ),
          CodeShortcutReplaceIntent: CallbackAction<CodeShortcutReplaceIntent>(
            onInvoke: (_) {
              _openFind(replace: true);
              return null;
            },
          ),
        },
        chunkAnalyzer: css
            ? const DefaultCodeChunkAnalyzer()
            : const XhtmlChunkAnalyzer(),
        padding: const EdgeInsets.all(10),
        style: CodeEditorStyle(
          fontSize: 13,
          fontFamily: 'monospace',
          highlightColor: dark
              ? const Color(0x8CFFC107)
              : const Color(0x99FFB300),
          codeTheme: CodeHighlightTheme(
            languages: {
              if (css)
                'css': CodeHighlightThemeMode(mode: langCss)
              else
                'xml': CodeHighlightThemeMode(mode: langXml),
            },
            theme: dark ? githubDarkTheme : githubTheme,
          ),
        ),
        indicatorBuilder: (_, editing, chunks, notifier) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DefaultCodeLineNumber(controller: editing, notifier: notifier),
            DefaultCodeChunkIndicator(
              width: 16,
              controller: chunks,
              notifier: notifier,
            ),
          ],
        ),
        findBuilder: (_, _, _) => const PreferredSize(
          preferredSize: Size.zero,
          child: SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _status(BookEditorDocument doc) => SizedBox(
    height: 28,
    child: Row(
      children: [
        const SizedBox(width: 10),
        Expanded(
          child: Tooltip(
            message: doc.path,
            child: ListenableBuilder(
              listenable: doc.code,
              builder: (context, _) {
                final cursor = doc.code.unfoldLineSelection;
                return Text(
                  '行 ${cursor.extentIndex + 1} · 列 ${cursor.extentOffset + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                );
              },
            ),
          ),
        ),
        IconButton(
          tooltip: '跳转到行',
          icon: const EditorIcon(EditorGlyph.gotoLine, size: 18),
          onPressed: widget.controller.busy ? null : _goToLine,
        ),
        IconButton(
          tooltip: '在文档中查找',
          icon: const EditorIcon(EditorGlyph.search, size: 18),
          onPressed: _openFind,
        ),
        TextButton.icon(
          onPressed: () => setState(() => _wrap = !_wrap),
          icon: const EditorIcon(EditorGlyph.wrap, size: 16),
          label: Text(_wrap ? '关闭换行' : '自动换行'),
        ),
        IconButton(
          tooltip: widget.followPreview ? '暂停预览跟随' : '开启预览跟随',
          isSelected: widget.followPreview,
          onPressed: widget.onFollowPreviewChanged == null
              ? null
              : () => widget.onFollowPreviewChanged!(!widget.followPreview),
          icon: const EditorIcon(EditorGlyph.preview, size: 18),
        ),
        IconButton(
          tooltip: '定位到预览',
          icon: const EditorIcon(EditorGlyph.locate, size: 18),
          onPressed: widget.controller.busy ? null : widget.onLocate,
        ),
      ],
    ),
  );
}
