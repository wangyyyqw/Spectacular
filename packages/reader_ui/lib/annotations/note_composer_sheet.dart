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
  bool _allowPop = false;
  bool _discardDialogVisible = false;
  bool _closing = false;

  String get _trimmedNote => _controller.text.trim();

  bool get _dirty => _trimmedNote.isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(String note) {
    if (_closing) {
      return;
    }
    _closing = true;
    if (_allowPop) {
      Navigator.of(context).pop(note);
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(note);
      }
    });
  }

  Future<bool> _confirmDiscard() async {
    if (_discardDialogVisible) {
      return false;
    }
    _discardDialogVisible = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存的笔记？'),
        content: const Text('笔记内容还没有保存，离开后本次输入会丢失。'),
        actions: [
          TextButton(
            key: const ValueKey<String>('note-discard-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            key: const ValueKey<String>('note-discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放弃笔记'),
          ),
        ],
      ),
    );
    _discardDialogVisible = false;
    return discard == true;
  }

  Future<void> _close() async {
    if (_closing) {
      return;
    }
    if (!_dirty) {
      _closing = true;
      Navigator.of(context).pop();
      return;
    }
    final discard = await _confirmDiscard();
    if (!discard || !mounted) {
      return;
    }
    _closing = true;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_dirty || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _close();
        }
      },
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
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
                  _ComposerHeader(onClose: _close),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: Color(defaultHighlightColor)
                          .withValues(alpha: 0.22),
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
                        : () => _finish(_trimmedNote),
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
  const _ComposerHeader({required this.onClose});

  final VoidCallback onClose;

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
          onPressed: onClose,
          tooltip: '关闭',
          icon: const Icon(Icons.close, size: 20),
        ),
      ],
    );
  }
}
