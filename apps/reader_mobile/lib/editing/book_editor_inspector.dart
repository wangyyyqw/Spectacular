import 'package:flutter/material.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_ui/icons/app_icon.dart' show AppExpansionTile;

import 'editor_icon.dart';

import 'book_editor_controller.dart';
import 'book_editor_tools.dart';
import 'book_editor_style_rule.dart';

/// 检查结果绑定选中元素和会话版本，失效后由工作台要求重新选择。
class BookEditorInspector extends StatefulWidget {
  const BookEditorInspector({
    super.key,
    required this.editor,
    required this.element,
    required this.onSelect,
    required this.onEdit,
  });
  final BookEditorController editor;
  final EditableElementRef element;
  final ValueChanged<EditableElementRef> onSelect;
  final VoidCallback onEdit;

  @override
  State<BookEditorInspector> createState() => _BookEditorInspectorState();
}

class _BookEditorInspectorState extends State<BookEditorInspector> {
  String? _class;
  Future<ClassStyleReport>? _report;
  late Future<List<EditableStyleRule>> _rules;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant BookEditorInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.element != widget.element) _reset();
  }

  void _reset() {
    _token++;
    final previous = _class;
    _class = null;
    _report = null;
    _rules = Future.sync(
      () =>
          ClassStyleEditor(widget.editor.session)
              .rulesForElement(widget.element),
    );
    final classes = widget.element.classes;
    final name = classes.contains(previous) ? previous : classes.firstOrNull;
    if (name != null) {
      _inspect(name);
    }
  }

  void _inspect(String name) {
    final token = ++_token;
    _class = name;
    _report = inspectClassStyleAsync(
      widget.editor.session,
      name,
      viewportWidth: widget.editor.previewSource?.contentWidth ?? 360,
      isCancelled: () => !mounted || token != _token,
    );
  }

  void _reselectAfterStyle() {
    final chain = [...widget.element.ancestors, widget.element];
    var selected = widget.editor.session
        .editableDocument(widget.element.path)
        .elements
        .first;
    for (final previous in chain.skip(1)) {
      selected = selected.children[previous.parent!.children.indexOf(previous)];
    }
    widget.onSelect(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final element = widget.element;
    final id = element.attributes['id'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _tag('<${element.tag}>', active: true),
                  if (id != null) _tag('#$id'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: widget.onEdit,
              icon: const EditorIcon(EditorGlyph.edit, size: 14),
              label: const Text('编辑元素'),
            ),
          ],
        ),
        if (element.ancestors.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final parent in element.ancestors)
                _tag('<${parent.tag}>', onTap: () => widget.onSelect(parent)),
            ],
          ),
        ],
        const SizedBox(height: 8),
        _classChoices(),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const EditorIcon(EditorGlyph.styleLibrary, size: 16),
            label: const Text('从样式库应用'),
            onPressed: widget.editor.busy
                ? null
                : () async {
                    final changed = await BookEditorTools(
                      context,
                      widget.editor,
                    ).styleLibrary(target: widget.element);
                    if (changed && mounted) _reselectAfterStyle();
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Row(
            children: [
              EditorIcon(
                EditorGlyph.formatPaint,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '作者样式',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        FutureBuilder<List<EditableStyleRule>>(
          future: _rules,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('作者样式读取失败：${snapshot.error}');
            final rules = snapshot.data;
            if (rules == null) return const LinearProgressIndicator();
            if (rules.isEmpty) {
              return const Text('没有直接匹配的作者规则，可编辑 HTML 或添加全书 class 样式。');
            }
            return Column(
              children: [
                for (final rule in rules)
                  BookEditorStyleRule(
                    key: ValueKey('${rule.path}:${rule.start}'),
                    editor: widget.editor,
                    rule: rule,
                    onApplied: _reselectAfterStyle,
                  ),
              ],
            );
          },
        ),
        if (_report == null && element.classes.isNotEmpty)
          const Text('选择一个 class，检查全书生效值与作者声明。'),
        if (_report != null)
          FutureBuilder<ClassStyleReport>(
            future: _report,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('检查未完成：${snapshot.error}');
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return _details(snapshot.data!);
            },
          ),
      ],
    );
  }

  Widget _tag(String label, {VoidCallback? onTap, bool active = false}) {
    final colors = Theme.of(context).colorScheme;
    final text = Text(
      label,
      maxLines: 1,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        height: 1.2,
        color: active ? colors.onPrimary : colors.onSurfaceVariant,
      ),
    );
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: active ? colors.primary : colors.surfaceContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: text,
    );
    if (onTap == null) return tag;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: tag,
    );
  }

  Widget _classChoices() {
    final classes = widget.element.classes;
    if (classes.isEmpty) {
      return Text('未声明 class', style: Theme.of(context).textTheme.labelSmall);
    }
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      children: [
        for (final name in classes)
          ChoiceChip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelPadding: const EdgeInsets.symmetric(horizontal: 2),
            label: Text(
              '.$name',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            selected: name == _class,
            onSelected: (_) => setState(() => _inspect(name)),
          ),
      ],
    );
  }

  Widget _details(ClassStyleReport report) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${report.chapterCount} 个章节 · ${report.elementCount} 个元素'),
      TextButton.icon(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const EditorIcon(EditorGlyph.tune, size: 14),
        label: Text('编辑全书 .${report.className} 属性'),
        onPressed: () => BookEditorTools(
          context,
          widget.editor,
        ).classStyle(report.className),
      ),
      AppExpansionTile(
        title: const Text('计算样式与全书生效值'),
        children: [
          for (final entry in report.effectiveValues.entries)
            SelectableText('${entry.key}: ${entry.value.join(' / ')}'),
          if (report.effectiveValues.values.any((values) => values.length > 1))
            const Text('同名类的元素存在不同生效值，编辑属性时可检查冲突。'),
        ],
      ),
    ],
  );
}
