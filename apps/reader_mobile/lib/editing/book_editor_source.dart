import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_editor_controller.dart';
import 'book_editor_find_bar.dart';
import 'book_editor_tools.dart';
import 'xhtml_chunk_analyzer.dart';

export 'book_editor_find_bar.dart';

class BookEditorSource extends StatefulWidget {
  const BookEditorSource({
    super.key,
    required this.controller,
    this.onLocate,
    this.onCursorChanged,
    this.onFindAll,
  });
  final BookEditorController controller;
  final VoidCallback? onLocate;
  final VoidCallback? onCursorChanged;
  final VoidCallback? onFindAll;

  @override
  State<BookEditorSource> createState() => _BookEditorSourceState();
}

class _BookEditorSourceState extends State<BookEditorSource> {
  final _codeFocus = FocusNode();
  Timer? _cursorFollow;
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
        widget.controller.busy ||
        !widget.controller.session.previewPaths.contains(
          widget.controller.activePath,
        )) {
      return;
    }
    _cursorFollow = Timer(const Duration(milliseconds: 160), () {
      if (mounted && _codeFocus.hasFocus) widget.onCursorChanged?.call();
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

  @override
  Widget build(BuildContext context) {
    final editor = widget.controller;
    final doc = editor.activeDocument;
    final source = ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
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
            if (doc.error != null)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  '校验未通过，预览保留上次有效内容。',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(child: _code(doc)),
            const Divider(height: 1),
            ValueListenableBuilder<CodeFindValue?>(
              valueListenable: doc.find,
              builder: (_, value, _) => value == null
                  ? const SizedBox.shrink()
                  : EditorFindBar(
                      controller: doc.find,
                      editing: doc.code,
                      readOnly: editor.busy,
                      onFindAll: widget.onFindAll,
                      onClose: () {
                        doc.find.close();
                        _focusSource();
                      },
                    ),
            ),
            _status(doc),
          ],
        ],
      ),
    );
    final macOS = Theme.of(context).platform == TargetPlatform.macOS;
    return CallbackShortcuts(
      bindings: {
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
              icon: const AppIcon(AppGlyph.close, size: 14),
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
        chunkAnalyzer: css
            ? const DefaultCodeChunkAnalyzer()
            : const XhtmlChunkAnalyzer(),
        padding: const EdgeInsets.all(10),
        style: CodeEditorStyle(
          fontSize: 13,
          fontFamily: 'monospace',
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
          tooltip: '在文档中查找',
          icon: const AppIcon(AppGlyph.search, size: 18),
          onPressed: doc.find.findMode,
        ),
        TextButton(
          onPressed: () => setState(() => _wrap = !_wrap),
          child: Text(_wrap ? '关闭换行' : '自动换行'),
        ),
        IconButton(
          tooltip: '定位到预览',
          icon: const AppIcon(AppGlyph.locate, size: 18),
          onPressed: widget.controller.busy ? null : widget.onLocate,
        ),
      ],
    ),
  );
}
