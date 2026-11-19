import 'package:flutter/material.dart';
import 'package:reader_core/editing/epub_editing.dart';

import 'book_editor_controller.dart';

class BookEditorStyleRule extends StatefulWidget {
  const BookEditorStyleRule({
    super.key,
    required this.editor,
    required this.rule,
    this.onApplied,
  });
  final BookEditorController editor;
  final EditableStyleRule rule;
  final VoidCallback? onApplied;

  @override
  State<BookEditorStyleRule> createState() => _BookEditorStyleRuleState();
}

class _BookEditorStyleRuleState extends State<BookEditorStyleRule> {
  late final _input = TextEditingController(text: widget.rule.text);
  String? _error;

  @override
  void didUpdateWidget(covariant BookEditorStyleRule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_input.text == oldWidget.rule.text) _input.text = widget.rule.text;
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _apply() {
    final applied = widget.editor.runCommand(
      () =>
          ClassStyleEditor(widget.editor.session)
              .replaceStyleRule(widget.rule, _input.text),
    );
    if (mounted) setState(() => _error = applied ? null : widget.editor.error);
    if (applied) widget.onApplied?.call();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message: widget.rule.path,
                child: Text(
                  widget.rule.path.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
            TextButton(
              key: ValueKey(
                'apply-style-${widget.rule.path}-${widget.rule.start}',
              ),
              onPressed: widget.editor.busy || _input.text == widget.rule.text
                  ? null
                  : _apply,
              child: const Text('应用到样式表'),
            ),
          ],
        ),
        if (widget.rule.media != null)
          Text(
            '@media ${widget.rule.media}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        TextField(
          key: ValueKey('style-css-${widget.rule.path}-${widget.rule.start}'),
          controller: _input,
          readOnly: widget.editor.busy,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.4,
          ),
          decoration: InputDecoration(
            labelText: widget.rule.selector,
            isDense: true,
            contentPadding: const EdgeInsets.all(8),
            errorText: _error,
            errorMaxLines: 3,
          ),
          onChanged: (_) => setState(() => _error = null),
        ),
      ],
    ),
  );
}
