import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_core/editing/epub_editing.dart';

import 'editor_icon.dart';

import 'book_editor_controller.dart';
import 'css_completion_input.dart';

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final border = OutlineInputBorder(
      borderRadius: ReaderUiStyle.controlRadiusOf(theme),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: ReaderUiStyle.cardRadiusOf(theme),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              EditorIcon(
                EditorGlyph.code,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.rule.path.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                key: ValueKey(
                  'apply-style-${widget.rule.path}-${widget.rule.start}',
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: widget.editor.busy || _input.text == widget.rule.text
                    ? null
                    : _apply,
                child: const Text('应用到样式表'),
              ),
            ],
          ),
          Text(
            widget.rule.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
          if (widget.rule.media != null)
            Text(
              '@media ${widget.rule.media}',
              style: theme.textTheme.labelSmall,
            ),
          const SizedBox(height: 8),
          CssTextCompletion(
            controller: _input,
            readOnly: widget.editor.busy,
            onAccepted: () => setState(() => _error = null),
            builder: (focus) => TextField(
              key: ValueKey(
                'style-css-${widget.rule.path}-${widget.rule.start}',
              ),
              controller: _input,
              focusNode: focus,
              readOnly: widget.editor.busy,
              minLines: 3,
              maxLines: 8,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: colors.surface,
                contentPadding: const EdgeInsets.all(8),
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(
                  borderSide: BorderSide(color: colors.primary),
                ),
                errorText: _error,
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
        ],
      ),
    );
  }
}
