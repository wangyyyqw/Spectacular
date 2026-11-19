import 'package:flutter/material.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_ui/icons/app_icon.dart';

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
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
    children: [
      Tooltip(
        message: widget.element.path,
        child: SelectableText(
          '<${widget.element.tag}>${widget.element.attributes['id'] == null ? '' : ' #${widget.element.attributes['id']}'}',
        ),
      ),
      if (widget.element.ancestors.isNotEmpty)
        Wrap(
          spacing: 6,
          children: [
            for (final parent in widget.element.ancestors)
              ActionChip(
                label: Text('<${parent.tag}>'),
                onPressed: () => widget.onSelect(parent),
              ),
          ],
        ),
      _classChoices(),
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
      if (_report == null && widget.element.classes.isNotEmpty)
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

  Widget _classChoices() => Wrap(
    spacing: 6,
    children: [
      for (final name in widget.element.classes)
        ChoiceChip(
          label: Text('.$name'),
          selected: name == _class,
          onSelected: (_) => setState(() => _inspect(name)),
        ),
      TextButton(
        onPressed: widget.onEdit,
        child: Text(
          widget.element.classes.isEmpty ? '编辑正文、HTML 或添加 class' : '编辑正文或 HTML',
        ),
      ),
    ],
  );

  Widget _details(ClassStyleReport report) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${report.chapterCount} 个章节 · ${report.elementCount} 个元素'),
      TextButton.icon(
        icon: const AppIcon(AppGlyph.tune),
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
