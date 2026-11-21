import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_drawer_style.dart';

class EditorFindBar extends StatefulWidget {
  const EditorFindBar({
    super.key,
    required this.controller,
    required this.editing,
    this.readOnly = false,
    this.onFindAll,
    this.onClose,
  });

  final CodeFindController controller;
  final CodeLineEditingController editing;
  final bool readOnly;
  final VoidCallback? onFindAll;
  final VoidCallback? onClose;

  @override
  State<EditorFindBar> createState() => _EditorFindBarState();
}

class _EditorFindBarState extends State<EditorFindBar> {
  bool _wrap = true;
  CodeFindController get find => widget.controller;
  bool get _ready =>
      !widget.readOnly &&
      find.findInputController.text.isNotEmpty &&
      find.value?.option.regExp != null &&
      find.value?.result != null &&
      find.value?.searching != true;

  void _move(bool previous) {
    final result = find.value?.result;
    if (result == null || result.matches.isEmpty) return;
    if (!_wrap &&
        (previous
            ? result.index <= 0
            : result.index >= result.matches.length - 1)) {
      return;
    }
    previous ? find.previousMatch() : find.nextMatch();
  }

  String _replacement(Match match) => find.value?.option.regex != true
      ? find.replaceInputController.text
      : find.replaceInputController.text.replaceAllMapped(RegExp(r'\$(\d+)'), (
          group,
        ) {
          final index = int.parse(group[1]!);
          return index <= match.groupCount ? match[index] ?? '' : group[0]!;
        });

  void _replaceCurrent() {
    if (!_ready) return;
    if (find.value!.option.regex != true) {
      find.replaceMatch();
      return;
    }
    final selection = find.value?.result?.currentMatch;
    if (selection == null) return;
    final lines = widget.editing.text.split('\n');
    final offset =
        lines
            .take(selection.baseIndex)
            .fold<int>(0, (total, line) => total + line.length + 1) +
        selection.baseOffset;
    final match = find.value!.option.regExp!.matchAsPrefix(
      widget.editing.text,
      offset,
    );
    if (match == null) return;
    final original = find.replaceInputController.text;
    find.replaceInputController.text = _replacement(match);
    find.replaceMatch();
    find.replaceInputController.text = original;
  }

  void _replaceAll() {
    if (!_ready) return;
    if (find.value!.option.regex) {
      widget.editing.text = widget.editing.text.replaceAllMapped(
        find.value!.option.regExp!,
        _replacement,
      );
    } else {
      find.replaceAllMatches();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = find.value;
    if (value == null) return const SizedBox.shrink();
    final result = value.result;
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide.none,
    );
    final searchFieldDecoration = InputDecoration(
      isDense: true,
      filled: true,
      fillColor: ReaderDrawerStyle.searchSurfaceOf(theme),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
    );
    return Material(
      key: const ValueKey('editor-find-bottom-bar'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  const SizedBox(
                    width: 34,
                    child: Text('查找', style: TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: Material(
                      color: ReaderDrawerStyle.searchSurfaceOf(theme),
                      borderRadius: border.borderRadius,
                      elevation: 3,
                      surfaceTintColor: Colors.transparent,
                      shadowColor: ReaderDrawerStyle.searchShadowOf(theme),
                      child: TextField(
                        controller: find.findInputController,
                        focusNode: find.findInputFocusNode,
                        style: const TextStyle(fontSize: 13),
                        decoration: searchFieldDecoration.copyWith(
                          hintText: '文档内查找',
                        ),
                        onSubmitted: (_) => _move(false),
                      ),
                    ),
                  ),
                  _icon('上一处', AppGlyph.chevronUp, () => _move(true)),
                  _icon('下一处', AppGlyph.chevronDown, () => _move(false)),
                  _icon('关闭查找', AppGlyph.close, widget.onClose ?? find.close),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  const SizedBox(
                    width: 34,
                    child: Text('替换', style: TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: find.replaceInputController,
                      focusNode: find.replaceInputFocusNode,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: '替换为',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                      ),
                      onSubmitted: (_) => _replaceCurrent(),
                    ),
                  ),
                  TextButton(
                    onPressed: _ready ? _replaceCurrent : null,
                    child: const Text('替换'),
                  ),
                  TextButton(
                    onPressed: _ready ? _replaceAll : null,
                    child: const Text('全部替换'),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<bool>(
                  value: value.option.regex,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: false, child: Text('普通模式')),
                    DropdownMenuItem(value: true, child: Text('正则模式')),
                  ],
                  onChanged: (regex) {
                    if (regex != value.option.regex) find.toggleRegex();
                  },
                ),
                FilterChip(
                  label: const Text('区分大小写'),
                  selected: value.option.caseSensitive,
                  onSelected: (_) => find.toggleCaseSensitive(),
                ),
                FilterChip(
                  label: const Text('循环匹配'),
                  selected: _wrap,
                  onSelected: (enabled) => setState(() => _wrap = enabled),
                ),
                Text(
                  result == null || result.matches.isEmpty
                      ? '0 处'
                      : '${result.index + 1} / ${result.matches.length}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (widget.onFindAll != null)
                  TextButton(
                    onPressed: widget.onFindAll,
                    child: const Text('全书查找'),
                  ),
              ],
            ),
            if (value.option.regex && value.option.regExp == null)
              Text(
                '正则表达式无效，请检查括号和转义。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _icon(String tooltip, AppGlyph glyph, VoidCallback onPressed) =>
      IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 28, height: 30),
        padding: EdgeInsets.zero,
        icon: AppIcon(glyph, size: 16),
        onPressed: onPressed,
      );
}
