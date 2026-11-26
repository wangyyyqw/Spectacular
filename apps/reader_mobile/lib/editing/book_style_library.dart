import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import 'book_style_presets.dart';
import 'book_style_preview.dart';
import 'editor_icon.dart';

typedef BookStyleChoice = ({
  BookStylePreset preset,
  String? className,
  bool important,
});

Future<BookStyleChoice?> showBookStyleLibrary(
  BuildContext context, {
  EditableElementRef? target,
  bool pickOnly = false,
  Future<bool> Function(BookStyleChoice choice)? onApply,
}) => showReaderDrawer<BookStyleChoice>(
  context: context,
  maxWidth: 880,
  waitForDismissal: true,
  builder: (_) =>
      _StyleLibrary(target: target, pickOnly: pickOnly, onApply: onApply),
);

class _StyleLibrary extends StatefulWidget {
  const _StyleLibrary({this.target, required this.pickOnly, this.onApply});
  final EditableElementRef? target;
  final bool pickOnly;
  final Future<bool> Function(BookStyleChoice choice)? onApply;

  @override
  State<_StyleLibrary> createState() => _StyleLibraryState();
}

class _StyleLibraryState extends State<_StyleLibrary> {
  final _search = TextEditingController();
  final _listScroll = ScrollController();
  final _detailScroll = ScrollController();
  BookStylePreset _selected = bookStylePresets.first;
  String _category = '全部';
  String? _class;
  bool _important = false;
  bool _working = false;
  String? _error;
  String? _notice;

  List<BookStylePreset> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return bookStylePresets
        .where(
          (preset) =>
              (_category == '全部' || preset.category == _category) &&
              '${preset.name} ${preset.description} ${preset.css}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
  }

  void _filter() => setState(() {
    final results = _filtered;
    if (results.isNotEmpty && !results.contains(_selected)) {
      _selected = results.first;
    }
    _notice = null;
  });

  Future<void> _apply() async {
    final choice = (
      preset: _selected,
      className: _class,
      important: _important,
    );
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final applied = await widget.onApply?.call(choice) ?? true;
      if (mounted && applied) Navigator.pop(context, choice);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _selected.css));
      if (mounted) setState(() => _notice = '已复制 ${_selected.name} 的 CSS 声明');
    } catch (error) {
      if (mounted) setState(() => _error = '复制失败：$error');
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _listScroll.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working,
    child: ReaderSheetForm(
      title: const Text('样式库'),
      onClose: _working ? () {} : () => Navigator.pop(context),
      scrollContent: false,
      content: SizedBox(
        height: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _filters(),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (_, bounds) {
                  final items = _list();
                  final details = _details();
                  return bounds.maxWidth >= 620
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 220, child: items),
                            const VerticalDivider(width: 25),
                            Expanded(child: details),
                          ],
                        )
                      : Column(
                          children: [
                            SizedBox(
                              height: (_filtered.length * 56.0).clamp(
                                72.0,
                                bounds.maxHeight > 400 ? 156.0 : 96.0,
                              ),
                              child: items,
                            ),
                            const Divider(height: 20),
                            Expanded(child: details),
                          ],
                        );
                },
              ),
            ),
            if (_working) const LinearProgressIndicator(),
            if (_error case final error?)
              Text(
                error,
                key: const ValueKey('style-library-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_notice case final notice?)
              Semantics(liveRegion: true, child: Text(notice)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton.icon(
          onPressed: _working || _filtered.isEmpty ? null : _copy,
          icon: const EditorIcon(EditorGlyph.code, size: 18),
          label: const Text('复制 CSS'),
        ),
        FilledButton(
          key: const ValueKey('style-library-apply'),
          onPressed:
              _working ||
                  _filtered.isEmpty ||
                  (!widget.pickOnly && widget.target == null)
              ? null
              : _apply,
          child: Text(
            widget.pickOnly
                ? '填入样式'
                : _class == null
                ? '应用到当前元素'
                : '检查全书影响',
          ),
        ),
      ],
    ),
  );

  Widget _filters() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const ValueKey('style-library-search'),
        controller: _search,
        readOnly: _working,
        onChanged: (_) => _filter(),
        decoration: InputDecoration(
          labelText: '搜索内置样式',
          hintText: '正文、标题、引文或 CSS 属性',
          prefixIcon: const Padding(
            padding: EdgeInsets.all(12),
            child: EditorIcon(EditorGlyph.search, size: 18),
          ),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空样式搜索',
                  onPressed: _working
                      ? null
                      : () {
                          _search.clear();
                          _filter();
                        },
                  icon: const EditorIcon(EditorGlyph.close, size: 18),
                ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final category in [
            '全部',
            ...bookStylePresets.map((preset) => preset.category).toSet(),
          ])
            ChoiceChip(
              label: Text(category),
              selected: _category == category,
              onSelected: _working
                  ? null
                  : (_) {
                      _category = category;
                      _filter();
                    },
            ),
        ],
      ),
    ],
  );

  Widget _list() {
    final results = _filtered;
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('没有匹配的样式'),
            TextButton(
              onPressed: () {
                _search.clear();
                _category = '全部';
                _filter();
              },
              child: const Text('显示全部样式'),
            ),
          ],
        ),
      );
    }
    return Scrollbar(
      controller: _listScroll,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _listScroll,
        itemCount: results.length,
        itemBuilder: (_, index) {
          final preset = results[index];
          final selected = _selected == preset;
          return ListTile(
            key: ValueKey('style-preset-${preset.id}'),
            dense: true,
            selected: selected,
            selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
            title: Text(preset.name),
            subtitle: Text(preset.category),
            trailing: selected
                ? const EditorIcon(EditorGlyph.check, size: 16)
                : null,
            onTap: _working
                ? null
                : () => setState(() {
                    _selected = preset;
                    _notice = null;
                    _error = null;
                  }),
          );
        },
      ),
    );
  }

  Widget _details() {
    if (_filtered.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Scrollbar(
      controller: _detailScroll,
      thumbVisibility: true,
      child: ListView(
        controller: _detailScroll,
        children: [
          Text(_selected.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(_selected.description),
          const SizedBox(height: 12),
          BookStylePreview(preset: _selected),
          const SizedBox(height: 6),
          Text('内置文字示例 · 应用后以正文预览为准', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          if (!widget.pickOnly) _scope(),
          if (widget.pickOnly) const Text('填入后可继续修改，点击“应用全书样式”才写入 EPUB。'),
          ExpansionTile(
            key: ValueKey('style-css-${_selected.id}'),
            tilePadding: EdgeInsets.zero,
            title: const Text('查看 CSS 声明'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  _selected.css,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scope() {
    final target = widget.target;
    if (target == null) {
      return const Text('打开 HTML 并把光标放在正文元素内，或点击预览段落后再应用。也可以先复制 CSS。');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '应用范围 · <${target.tag}> · ${target.path.split('/').last}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: const Text('当前元素'),
              selected: _class == null,
              onSelected: _working
                  ? null
                  : (_) => setState(() => _class = null),
            ),
            for (final name in target.classes)
              ChoiceChip(
                label: Text('全书 .$name'),
                selected: _class == name,
                onSelected: _working
                    ? null
                    : (_) => setState(() => _class = name),
              ),
          ],
        ),
        if (_class == null) ...[
          const Text('合并所列属性，保留正文和其他样式。'),
          CheckboxListTile(
            key: const ValueKey('style-library-important'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('覆盖作者高优先级声明'),
            subtitle: const Text('为此元素的预设声明添加 !important'),
            value: _important,
            onChanged: _working
                ? null
                : (value) => setState(() => _important = value!),
          ),
        ] else
          const Text('下一步查看受影响章节与元素，可调整属性并处理冲突后再应用。'),
      ],
    );
  }
}
