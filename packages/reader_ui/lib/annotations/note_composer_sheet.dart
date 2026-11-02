import 'package:flutter/material.dart';

import 'annotation.dart';

/// 新建笔记时打开的底部编辑弹层。
class ReaderNoteComposerSheet extends StatefulWidget {
  /// 创建笔记编辑弹层。
  const ReaderNoteComposerSheet({super.key, required this.quote});

  /// 当前选中的原文。
  final String quote;

  @override
  State<ReaderNoteComposerSheet> createState() =>
      _ReaderNoteComposerSheetState();
}

class _ReaderNoteComposerSheetState extends State<ReaderNoteComposerSheet> {
  final TextEditingController _controller = TextEditingController();

  String get _trimmedNote => _controller.text.trim();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        key: const ValueKey<String>('note-composer-sheet'),
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _ComposerHandle(),
                const SizedBox(height: 14),
                const _ComposerHeader(),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: Color(defaultHighlightColor).withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.quote,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
                ),
                const SizedBox(height: 16),
                Text('笔记内容', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey<String>('note-composer-input'),
                  controller: _controller,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  textInputAction: TextInputAction.newline,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '写下此刻的想法…',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const ValueKey<String>('note-composer-save'),
                  onPressed: _trimmedNote.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_trimmedNote),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  icon: const Icon(Icons.check, size: 20),
                  label: const Text('保存笔记'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerHandle extends StatelessWidget {
  const _ComposerHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _ComposerHeader extends StatelessWidget {
  const _ComposerHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.edit_note_rounded,
          size: 22,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text('添加笔记', style: theme.textTheme.titleMedium),
        const Spacer(),
        IconButton(
          key: const ValueKey<String>('note-composer-close'),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '关闭',
          icon: const Icon(Icons.close, size: 20),
        ),
      ],
    );
  }
}
