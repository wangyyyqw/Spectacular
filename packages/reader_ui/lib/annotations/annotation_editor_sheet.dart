import 'package:flutter/material.dart';

import 'annotation.dart';

/// 标注编辑动作。
enum AnnotationEditActionType {
  /// 更换高亮颜色。
  recolor,

  /// 保存笔记正文。
  saveNote,

  /// 删除高亮或笔记。
  remove,
}

/// 标注编辑弹层返回结果。
class AnnotationEditAction {
  const AnnotationEditAction._(this.type, {this.color, this.note});

  /// 更换颜色。
  const AnnotationEditAction.recolor(int color)
    : this._(AnnotationEditActionType.recolor, color: color);

  /// 保存笔记。
  const AnnotationEditAction.saveNote(String note)
    : this._(AnnotationEditActionType.saveNote, note: note);

  /// 删除标注。
  const AnnotationEditAction.remove() : this._(AnnotationEditActionType.remove);

  /// 动作类型。
  final AnnotationEditActionType type;

  /// 新颜色（仅换色时有效）。
  final int? color;

  /// 新笔记正文（仅保存笔记时有效）。
  final String? note;
}

/// 高亮颜色选项。
class AnnotationColorOption {
  const AnnotationColorOption(this.value, this.label);

  /// ARGB 颜色。
  final int value;

  /// 无障碍与提示文案。
  final String label;
}

/// 点击已有高亮后打开的编辑弹层。
class ReaderAnnotationEditorSheet extends StatefulWidget {
  /// 创建标注编辑弹层。
  const ReaderAnnotationEditorSheet({super.key, required this.annotation});

  /// 可选高亮颜色。
  static const colors = <AnnotationColorOption>[
    AnnotationColorOption(defaultHighlightColor, '黄色'),
    AnnotationColorOption(0xFFA5D6A7, '绿色'),
    AnnotationColorOption(0xFF90CAF9, '蓝色'),
    AnnotationColorOption(0xFFF48FB1, '粉色'),
    AnnotationColorOption(0xFFFFB74D, '橙色'),
  ];

  /// 当前标注。
  final ReaderAnnotation annotation;

  @override
  State<ReaderAnnotationEditorSheet> createState() =>
      _ReaderAnnotationEditorSheetState();
}

class _ReaderAnnotationEditorSheetState
    extends State<ReaderAnnotationEditorSheet> {
  late final TextEditingController _noteController;
  bool _allowPop = false;
  bool _discardDialogVisible = false;
  bool _closing = false;

  bool get _isNote => widget.annotation.type == ReaderAnnotationType.note;

  String get _trimmedNote => _noteController.text.trim();

  String get _initialNote => widget.annotation.note?.trim() ?? '';

  bool get _noteDraftChanged => _trimmedNote != _initialNote;

  bool get _noteChanged =>
      _trimmedNote.isNotEmpty && _trimmedNote != _initialNote;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.annotation.note ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _finish(AnnotationEditAction action) {
    if (_closing) {
      return;
    }
    _closing = true;
    if (_allowPop) {
      Navigator.of(context).pop(action);
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(action);
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
        title: const Text('放弃未保存的笔记修改？'),
        content: const Text('笔记内容还没有保存，离开后本次修改会丢失。'),
        actions: [
          TextButton(
            key: const ValueKey<String>('annotation-discard-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            key: const ValueKey<String>('annotation-discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放弃修改'),
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
    if (!_noteDraftChanged) {
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
    final currentColor = widget.annotation.color ?? defaultHighlightColor;
    return PopScope(
      canPop: !_noteDraftChanged || _allowPop,
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
          key: const ValueKey<String>('annotation-editor-sheet'),
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
                  const _SheetHandle(),
                  const SizedBox(height: 14),
                  _SheetHeader(isNote: _isNote, onClose: _close),
                  _AnnotationPreview(
                    annotation: widget.annotation,
                    currentColor: currentColor,
                  ),
                  if (_isNote) ...[
                    const SizedBox(height: 16),
                    _AnnotationNoteEditor(
                      controller: _noteController,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text('高亮颜色', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 10),
                  _ColorChoices(
                    currentColor: currentColor,
                    onSelected: (color) =>
                        _finish(AnnotationEditAction.recolor(color)),
                  ),
                  const SizedBox(height: 18),
                  if (_isNote) ...[
                    FilledButton.icon(
                      key: const ValueKey<String>('annotation-save-note'),
                      onPressed: _noteChanged
                          ? () => _finish(
                              AnnotationEditAction.saveNote(_trimmedNote),
                            )
                          : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('保存笔记'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _RemoveAnnotationButton(
                    isNote: _isNote,
                    onRemove: () =>
                        _finish(const AnnotationEditAction.remove()),
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

class _AnnotationNoteEditor extends StatelessWidget {
  const _AnnotationNoteEditor({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('笔记内容', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey<String>('annotation-note-input'),
          controller: controller,
          onChanged: onChanged,
          minLines: 3,
          maxLines: 6,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: '写下此刻的想法…',
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

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

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.isNote, required this.onClose});

  final bool isNote;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          isNote ? Icons.sticky_note_2_outlined : Icons.border_color_outlined,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(isNote ? '笔记' : '高亮', style: theme.textTheme.titleMedium),
        const Spacer(),
        IconButton(
          onPressed: onClose,
          tooltip: '关闭',
          icon: const Icon(Icons.close, size: 20),
        ),
      ],
    );
  }
}

class _AnnotationPreview extends StatelessWidget {
  const _AnnotationPreview({
    required this.annotation,
    required this.currentColor,
  });

  final ReaderAnnotation annotation;
  final int currentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Color(currentColor).withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            annotation.quote,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        ),
      ],
    );
  }
}

class _ColorChoices extends StatelessWidget {
  const _ColorChoices({required this.currentColor, required this.onSelected});

  final int currentColor;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final option in ReaderAnnotationEditorSheet.colors)
          _ColorChoice(
            option: option,
            selected: option.value == currentColor,
            onTap: () => onSelected(option.value),
          ),
      ],
    );
  }
}

class _RemoveAnnotationButton extends StatelessWidget {
  const _RemoveAnnotationButton({required this.isNote, required this.onRemove});

  final bool isNote;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      key: const ValueKey<String>('annotation-remove'),
      onPressed: onRemove,
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.error,
        side: BorderSide(
          color: theme.colorScheme.error.withValues(alpha: 0.45),
        ),
        minimumSize: const Size.fromHeight(44),
      ),
      icon: const Icon(Icons.delete_outline, size: 20),
      label: Text(isNote ? '删除笔记' : '取消高亮'),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AnnotationColorOption option;
  final bool selected;
  final VoidCallback onTap;

  String get _keyValue =>
      '0x${option.value.toRadixString(16).toUpperCase().padLeft(8, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      child: InkResponse(
        key: ValueKey<String>('annotation-color-$_keyValue'),
        onTap: onTap,
        radius: 24,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Color(option.value),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 20, color: Color(0xFF1D1B20))
              : null,
        ),
      ),
    );
  }
}
