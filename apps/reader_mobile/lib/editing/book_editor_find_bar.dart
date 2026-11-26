import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_ui/theme/reader_drawer_style.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

import 'book_editor_search.dart';
import 'editor_icon.dart';

/// 查找、文件范围和命中列表都留在源码下方，切换结果不关闭面板。
class EditorFindBar extends StatefulWidget {
  const EditorFindBar({super.key, required this.search, this.onClose});

  final BookEditorSearch search;
  final VoidCallback? onClose;

  @override
  State<EditorFindBar> createState() => _EditorFindBarState();
}

class _EditorFindBarState extends State<EditorFindBar> {
  final _fileFilter = TextEditingController();
  final _resultScroll = ScrollController();
  int _visibleMatch = -1;
  bool _choosingFiles = false;
  BookEditorSearch get search => widget.search;

  @override
  void dispose() {
    _fileFilter.dispose();
    _resultScroll.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      (widget.onClose ?? search.close)();
      return KeyEventResult.handled;
    }
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (search.queryFocus.hasFocus) {
      search.move(HardwareKeyboard.instance.isShiftPressed);
    } else if (search.replaceFocus.hasFocus) {
      unawaited(search.replaceCurrent());
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: search,
    builder: (context, _) {
      _revealMatch();
      return Focus(
        canRequestFocus: false,
        onKeyEvent: _handleKey,
        child: Material(
          key: const ValueKey('editor-find-bottom-bar'),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _queryRow(),
                  const SizedBox(height: 4),
                  _replaceRow(),
                  _options(),
                  if (_choosingFiles) _filePicker(),
                  if (search.searching)
                    const LinearProgressIndicator(minHeight: 2),
                  _summary(),
                  if (search.matches.isNotEmpty) _results(),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  void _revealMatch() {
    if (_visibleMatch == search.index) return;
    _visibleMatch = search.index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_resultScroll.hasClients || search.index < 0) return;
      final position = _resultScroll.position;
      final top = search.index * 48.0;
      final bottom = top + 48;
      final offset = top < position.pixels
          ? top
          : bottom > position.pixels + position.viewportDimension
          ? bottom - position.viewportDimension
          : position.pixels;
      _resultScroll.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
    });
  }

  InputDecoration _decoration(String hint) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: ReaderDrawerStyle.searchSurfaceOf(theme),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      border: border,
      enabledBorder: border,
    );
  }

  Widget _queryRow() => Row(
    children: [
      const SizedBox(
        width: 34,
        child: Text('查找', style: TextStyle(fontSize: 12)),
      ),
      Expanded(
        child: TextField(
          key: const ValueKey('editor-search-query'),
          controller: search.query,
          focusNode: search.queryFocus,
          style: const TextStyle(fontSize: 13),
          decoration: _decoration('查找内容'),
          onSubmitted: (_) => search.move(false),
        ),
      ),
      _icon(
        '上一处',
        EditorGlyph.chevronUp,
        search.matches.isEmpty ? null : () => search.move(true),
      ),
      _icon(
        '下一处',
        EditorGlyph.chevronDown,
        search.matches.isEmpty ? null : () => search.move(false),
      ),
      _icon('关闭查找', EditorGlyph.close, widget.onClose ?? search.close),
    ],
  );

  Widget _replaceRow() {
    final enabled =
        !search.editor.busy &&
        !search.searching &&
        search.matches.isNotEmpty &&
        search.error == null;
    return Row(
      children: [
        const SizedBox(
          width: 34,
          child: Text('替换', style: TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: TextField(
            key: const ValueKey('editor-search-replacement'),
            controller: search.replacement,
            focusNode: search.replaceFocus,
            style: const TextStyle(fontSize: 13),
            decoration: _decoration('替换为'),
            onSubmitted: (_) => unawaited(search.replaceCurrent()),
          ),
        ),
        TextButton(
          onPressed: enabled ? search.replaceCurrent : null,
          child: const Text('替换'),
        ),
        TextButton(
          onPressed: enabled ? search.replaceAll : null,
          child: const Text('全部替换'),
        ),
      ],
    );
  }

  Widget _options() => Wrap(
    spacing: 6,
    runSpacing: 2,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      PopupMenuButton<EditorSearchScope>(
        tooltip: '查找范围',
        initialValue: search.scope,
        onSelected: (scope) {
          search.setScope(scope);
          setState(() => _choosingFiles = scope == EditorSearchScope.selected);
        },
        itemBuilder: (_) => [
          for (final scope in EditorSearchScope.values)
            PopupMenuItem(value: scope, child: Text(scope.label)),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const EditorIcon(EditorGlyph.filter, size: 14),
              const SizedBox(width: 4),
              Text(
                search.scope.label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const EditorIcon(EditorGlyph.chevronDown, size: 14),
            ],
          ),
        ),
      ),
      if (search.scope == EditorSearchScope.selected)
        TextButton(
          onPressed: () => setState(() => _choosingFiles = !_choosingFiles),
          child: Text('${search.selectedPaths.length} 个文档'),
        ),
      FilterChip(
        label: const Text('正则'),
        selected: search.regex,
        onSelected: search.setRegex,
      ),
      FilterChip(
        label: const Text('区分大小写'),
        selected: search.caseSensitive,
        onSelected: search.setCaseSensitive,
      ),
      FilterChip(
        label: const Text('循环匹配'),
        selected: search.wrap,
        onSelected: search.setWrap,
      ),
    ],
  );

  Widget _filePicker() {
    final filter = _fileFilter.text.trim().toLowerCase();
    final files = search.searchableResources
        .where((file) => file.path.toLowerCase().contains(filter))
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fileFilter,
                decoration: _decoration('筛选搜索文档'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            TextButton(
              onPressed: () => search.setSelectedPaths({
                ...search.selectedPaths,
                ...files.map((file) => file.path),
              }),
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: () => search.setSelectedPaths({}),
              child: const Text('清空'),
            ),
          ],
        ),
        SizedBox(
          height: files.isEmpty ? 36 : (files.length * 32.0).clamp(32, 112),
          child: files.isEmpty
              ? const Center(child: Text('没有匹配的文档'))
              : ListView.builder(
                  itemCount: files.length,
                  itemExtent: 32,
                  itemBuilder: (_, index) {
                    final path = files[index].path;
                    return CheckboxListTile(
                      key: ValueKey('search-file-$path'),
                      value: search.selectedPaths.contains(path),
                      onChanged: (selected) => search.setSelectedPaths({
                        ...search.selectedPaths.where((item) => item != path),
                        if (selected == true) path,
                      }),
                      title: Tooltip(
                        message: path,
                        child: Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _summary() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Semantics(
      liveRegion: true,
      child: Text(
        search.error ??
            (search.searching
                ? '正在查找…'
                : search.query.text.isEmpty
                ? '选择范围后输入内容，结果会显示在这里'
                : search.matches.isEmpty
                ? '没有匹配结果'
                : '${search.matches.length} 处匹配 · ${search.matches.map((item) => item.path).toSet().length} 个文档'),
        key: const ValueKey('editor-search-summary'),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: search.error == null
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Theme.of(context).colorScheme.error,
        ),
      ),
    ),
  );

  Widget _results() => SizedBox(
    height: (search.matches.length * 48.0).clamp(48, 144),
    child: ListView.builder(
      key: const ValueKey('editor-search-results'),
      controller: _resultScroll,
      itemCount: search.matches.length,
      itemExtent: 48,
      itemBuilder: (_, index) => _result(search.matches[index], index),
    ),
  );

  Widget _result(EditSearchMatch match, int index) {
    final source = search.sources[match.path]!;
    final start = (match.start - 24).clamp(0, source.length);
    final end = (match.end + 32).clamp(0, source.length);
    final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
    final column =
        match.start -
        (match.start == 0 ? 0 : source.lastIndexOf('\n', match.start - 1) + 1) +
        1;
    String clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ');
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      key: ValueKey('search-result-$index'),
      dense: true,
      selected: index == search.index,
      selectedTileColor: colors.secondaryContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      title: Tooltip(
        message: match.path,
        child: Text(
          '${p.posix.basename(match.path)} · $line:$column',
          style: Theme.of(context).textTheme.labelSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: clean(source.substring(start, match.start))),
            TextSpan(
              text: clean(match.text),
              style: TextStyle(
                backgroundColor: colors.tertiaryContainer,
                color: colors.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: clean(source.substring(match.end, end))),
          ],
        ),
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => search.openMatch(index),
    );
  }

  Widget _icon(String tooltip, EditorGlyph glyph, VoidCallback? onPressed) =>
      IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 28, height: 32),
        padding: EdgeInsets.zero,
        icon: EditorIcon(glyph, size: 16),
        onPressed: onPressed,
      );
}
