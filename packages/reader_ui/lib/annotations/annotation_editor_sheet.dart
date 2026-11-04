import 'dart:async';

import 'package:flutter/material.dart';

import 'annotation.dart';
import 'annotation_style_painter.dart';

/// 标注编辑动作。
enum AnnotationEditActionType {
  /// 保存颜色、样式或笔记修改。
  save,

  /// 删除笔记正文并保留高亮。
  removeNote,

  /// 删除高亮或笔记。
  remove,
}

/// 标注编辑弹层返回结果。
class AnnotationEditAction {
  const AnnotationEditAction._({
    required this.type,
    this.color,
    this.style,
    this.note,
  });

  /// 保存当前修改。
  const AnnotationEditAction.save({
    required int color,
    required ReaderAnnotationStyle style,
    String? note,
  }) : this._(
         type: AnnotationEditActionType.save,
         color: color,
         style: style,
         note: note,
       );

  /// 删除标注。
  const AnnotationEditAction.remove()
    : this._(type: AnnotationEditActionType.remove);

  /// 删除笔记正文并保留高亮。
  const AnnotationEditAction.removeNote({
    required int color,
    required ReaderAnnotationStyle style,
  }) : this._(
         type: AnnotationEditActionType.removeNote,
         color: color,
         style: style,
       );

  /// 动作类型。
  final AnnotationEditActionType type;

  /// 新颜色。
  final int? color;

  /// 新样式。
  final ReaderAnnotationStyle? style;

  /// 新笔记正文；null 表示本次不修改笔记。
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

/// 高亮样式选项。
class AnnotationStyleOption {
  const AnnotationStyleOption(this.value, this.label);

  /// 装饰样式。
  final ReaderAnnotationStyle value;

  /// 无障碍与提示文案。
  final String label;
}

/// 点击已有高亮后打开的编辑弹层。
class ReaderAnnotationEditorSheet extends StatefulWidget {
  /// 创建标注编辑弹层。
  const ReaderAnnotationEditorSheet({
    super.key,
    required this.annotation,
    this.inkMode = false,
  });

  /// 可选高亮颜色。
  static const colors = <AnnotationColorOption>[
    AnnotationColorOption(defaultHighlightColor, '黄色'),
    AnnotationColorOption(0xFFA5D6A7, '绿色'),
    AnnotationColorOption(0xFF90CAF9, '蓝色'),
    AnnotationColorOption(0xFFF48FB1, '粉色'),
    AnnotationColorOption(0xFFFFB74D, '橙色'),
  ];

  /// 可选高亮样式。
  static const styles = <AnnotationStyleOption>[
    AnnotationStyleOption(ReaderAnnotationStyle.background, '底色'),
    AnnotationStyleOption(ReaderAnnotationStyle.underline, '直线'),
    AnnotationStyleOption(ReaderAnnotationStyle.wavyUnderline, '波浪线'),
    AnnotationStyleOption(ReaderAnnotationStyle.dashedUnderline, '虚线'),
  ];

  /// 当前标注。
  final ReaderAnnotation annotation;

  /// 墨水屏模式：高亮统一按黑色绘制，不再提供无效的颜色选择。
  final bool inkMode;

  @override
  State<ReaderAnnotationEditorSheet> createState() =>
      _ReaderAnnotationEditorSheetState();
}

class _ReaderAnnotationEditorSheetState
    extends State<ReaderAnnotationEditorSheet> {
  late final TextEditingController _noteController;
  bool _allowPop = false;
  bool _discardDialogVisible = false;
  bool _removeDialogVisible = false;
  bool _removeNoteDialogVisible = false;
  bool _closing = false;
  bool _showNoteEditor = false;
  bool _autofocusNoteEditor = false;
  late int _selectedColor;
  late ReaderAnnotationStyle _selectedStyle;

  bool get _isNote => widget.annotation.type == ReaderAnnotationType.note;

  bool get _canEditNote => _isNote || _showNoteEditor;

  String get _trimmedNote => _noteController.text.trim();

  String get _initialNote => widget.annotation.note?.trim() ?? '';

  bool get _noteDraftChanged => _trimmedNote != _initialNote;

  bool get _noteChanged =>
      _trimmedNote.isNotEmpty && _trimmedNote != _initialNote;

  int get _currentColor => _selectedColor;

  ReaderAnnotationStyle get _currentStyle => _selectedStyle;

  bool get _appearanceChanged =>
      _currentColor != (widget.annotation.color ?? defaultHighlightColor) ||
      _currentStyle != widget.annotation.style;

  bool get _hasChanges => _appearanceChanged || _noteDraftChanged;

  bool get _canSave {
    if (_isNote) {
      return _trimmedNote.isNotEmpty && (_noteChanged || _appearanceChanged);
    }
    if (_showNoteEditor && _trimmedNote.isNotEmpty) {
      return true;
    }
    return _appearanceChanged;
  }

  String? get _actionNote =>
      _isNote || _trimmedNote.isNotEmpty ? _trimmedNote : null;

  String get _saveLabel {
    if (_isNote) {
      return '保存笔记';
    }
    return _trimmedNote.isNotEmpty ? '保存为笔记' : '保存修改';
  }

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.annotation.note ?? '');
    _selectedColor = widget.annotation.color ?? defaultHighlightColor;
    _selectedStyle = widget.annotation.style;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _finish(AnnotationEditAction action) async {
    if (_closing) {
      return;
    }
    if (action.type == AnnotationEditActionType.removeNote) {
      final remove = await _confirmRemoveNoteOnly();
      if (!remove || !mounted) {
        return;
      }
    }
    if (action.type == AnnotationEditActionType.remove && _isNote) {
      final remove = await _confirmRemoveNote();
      if (!remove || !mounted) {
        return;
      }
    }
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

  Future<bool> _confirmRemoveNote() async {
    if (_removeDialogVisible) {
      return false;
    }
    _removeDialogVisible = true;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条笔记？'),
        content: Text(_noteDraftChanged ? '笔记正文和尚未保存的修改都会被永久删除。' : '删除后无法恢复。'),
        actions: [
          TextButton(
            key: const ValueKey<String>('annotation-remove-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>('annotation-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除笔记'),
          ),
        ],
      ),
    );
    _removeDialogVisible = false;
    return remove == true;
  }

  Future<bool> _confirmRemoveNoteOnly() async {
    if (_removeNoteDialogVisible) {
      return false;
    }
    _removeNoteDialogVisible = true;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记正文？'),
        content: const Text('高亮会保留，删除后笔记正文无法恢复。'),
        actions: [
          TextButton(
            key: const ValueKey<String>('annotation-remove-note-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>('annotation-remove-note-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除正文'),
          ),
        ],
      ),
    );
    _removeNoteDialogVisible = false;
    return remove == true;
  }

  void _selectColor(int color) {
    if (color == _currentColor) {
      return;
    }
    setState(() => _selectedColor = color);
  }

  void _selectStyle(ReaderAnnotationStyle style) {
    if (style == _currentStyle) {
      return;
    }
    setState(() => _selectedStyle = style);
  }

  Future<bool> _confirmDiscard() async {
    if (_discardDialogVisible) {
      return false;
    }
    _discardDialogVisible = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _noteDraftChanged ? '放弃未保存的笔记修改？' : '放弃未保存的修改？',
        ),
        content: Text(
          _noteDraftChanged
              ? '笔记内容还没有保存，离开后本次修改会丢失。'
              : '颜色或样式还没有保存，离开后本次修改会丢失。',
        ),
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
    if (!_hasChanges) {
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
    final currentColor = _currentColor;
    final currentStyle = _currentStyle;
    return PopScope(
      canPop: !_hasChanges || _allowPop,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
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
                          currentStyle: currentStyle,
                          inkMode: widget.inkMode,
                        ),
                        if (!_isNote && !_showNoteEditor) ...[
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            key: const ValueKey<String>(
                              'annotation-add-note',
                            ),
                            onPressed: () => setState(() {
                              _showNoteEditor = true;
                              _autofocusNoteEditor = true;
                            }),
                            icon: const Icon(Icons.note_add_outlined, size: 20),
                            label: const Text('为这条高亮添加笔记'),
                          ),
                        ],
                        if (_canEditNote) ...[
                          const SizedBox(height: 16),
                          _AnnotationNoteEditor(
                            controller: _noteController,
                            autofocus: _autofocusNoteEditor,
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                        const SizedBox(height: 18),
                        if (widget.inkMode)
                          const _InkModeColorHint()
                        else ...[
                          Text('高亮颜色', style: theme.textTheme.labelLarge),
                          const SizedBox(height: 10),
                          _ColorChoices(
                            currentColor: currentColor,
                            onSelected: _selectColor,
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text('高亮样式', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 10),
                        _StyleChoices(
                          currentColor: widget.inkMode
                              ? 0xFF000000
                              : currentColor,
                          currentStyle: currentStyle,
                          inkMode: widget.inkMode,
                          onSelected: _selectStyle,
                        ),
                      ],
                    ),
                  ),
                ),
                _AnnotationActionsFooter(
                  isNote: _isNote,
                  saveKey: ValueKey<String>(
                    _canEditNote
                        ? 'annotation-save-note'
                        : 'annotation-save-changes',
                  ),
                  saveLabel: _saveLabel,
                  onSave: _canSave
                      ? () => unawaited(
                          _finish(
                            AnnotationEditAction.save(
                              color: _currentColor,
                              style: _currentStyle,
                              note: _canEditNote ? _actionNote : null,
                            ),
                          ),
                        )
                      : null,
                  onRemoveNote: _isNote
                      ? () => unawaited(
                          _finish(
                            AnnotationEditAction.removeNote(
                              color: _currentColor,
                              style: _currentStyle,
                            ),
                          ),
                        )
                      : null,
                  onRemove: () => unawaited(
                    _finish(const AnnotationEditAction.remove()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnotationActionsFooter extends StatelessWidget {
  const _AnnotationActionsFooter({
    required this.isNote,
    required this.saveKey,
    required this.saveLabel,
    required this.onSave,
    required this.onRemoveNote,
    required this.onRemove,
  });

  final bool isNote;
  final Key saveKey;
  final String saveLabel;
  final VoidCallback? onSave;
  final VoidCallback? onRemoveNote;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              key: saveKey,
              onPressed: onSave,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              icon: const Icon(Icons.check, size: 20),
              label: Text(saveLabel),
            ),
            if (onRemoveNote != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey<String>('annotation-remove-note'),
                onPressed: onRemoveNote,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                icon: const Icon(Icons.notes_outlined, size: 20),
                label: const Text('删除笔记正文，保留高亮'),
              ),
            ],
            const SizedBox(height: 10),
            _RemoveAnnotationButton(isNote: isNote, onRemove: onRemove),
          ],
        ),
      ),
    );
  }
}

class _AnnotationNoteEditor extends StatelessWidget {
  const _AnnotationNoteEditor({
    required this.controller,
    required this.autofocus,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool autofocus;
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
          autofocus: autofocus,
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
    required this.currentStyle,
    required this.inkMode,
  });

  final ReaderAnnotation annotation;
  final int currentColor;
  final ReaderAnnotationStyle currentStyle;
  final bool inkMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewColor = inkMode ? 0xFF000000 : currentColor;
    final previewStyle =
        inkMode && currentStyle == ReaderAnnotationStyle.background
        ? ReaderAnnotationStyle.underline
        : currentStyle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: previewStyle == ReaderAnnotationStyle.background
                ? Color(previewColor).withValues(alpha: 0.22)
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: CustomPaint(
            painter: previewStyle == ReaderAnnotationStyle.background
                ? null
                : _AnnotationPreviewPainter(
                    color: Color(previewColor),
                    style: previewStyle,
                  ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Text(
                annotation.quote,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InkModeColorHint extends StatelessWidget {
  const _InkModeColorHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey<String>('annotation-ink-color-hint'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text('墨水屏模式：高亮统一为黑色'),
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

class _StyleChoices extends StatelessWidget {
  const _StyleChoices({
    required this.currentColor,
    required this.currentStyle,
    required this.inkMode,
    required this.onSelected,
  });

  final int currentColor;
  final ReaderAnnotationStyle currentStyle;
  final bool inkMode;
  final ValueChanged<ReaderAnnotationStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 墨水屏没有底色形态：底色本身会绘制为实线，因此只显示三种线型，
    // 并把原有的底色标注视为已选中实线。
    final options = inkMode
        ? ReaderAnnotationEditorSheet.styles
              .where(
                (option) => option.value != ReaderAnnotationStyle.background,
              )
              .toList(growable: false)
        : ReaderAnnotationEditorSheet.styles;
    final effectiveStyle =
        inkMode && currentStyle == ReaderAnnotationStyle.background
        ? ReaderAnnotationStyle.underline
        : currentStyle;
    return Row(
      children: [
        for (var index = 0; index < options.length; index += 1) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: _StyleChoice(
              option: options[index],
              color: Color(currentColor),
              selected: options[index].value == effectiveStyle,
              onTap: () => onSelected(options[index].value),
              background: theme.colorScheme.surfaceContainerLow,
              selectedBackground: theme.colorScheme.primaryContainer,
              borderColor: theme.colorScheme.outlineVariant,
              selectedBorderColor: theme.colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }
}

class _StyleChoice extends StatelessWidget {
  const _StyleChoice({
    required this.option,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.background,
    required this.selectedBackground,
    required this.borderColor,
    required this.selectedBorderColor,
  });

  final AnnotationStyleOption option;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final Color background;
  final Color selectedBackground;
  final Color borderColor;
  final Color selectedBorderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('annotation-style-${option.value.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? selectedBackground : background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? selectedBorderColor : borderColor,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 34,
                  height: 14,
                  child: CustomPaint(
                    painter: _StyleSamplePainter(
                      color: color,
                      style: option.value,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleSamplePainter extends CustomPainter {
  const _StyleSamplePainter({required this.color, required this.style});

  final Color color;
  final ReaderAnnotationStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    AnnotationStylePainter.paint(
      canvas,
      Offset.zero & size,
      color: color,
      style: style,
      fillAlpha: 0.35,
      strokeAlpha: 1,
      strokeWidth: 1.8,
    );
  }

  @override
  bool shouldRepaint(_StyleSamplePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.style != style;
}

class _AnnotationPreviewPainter extends CustomPainter {
  const _AnnotationPreviewPainter({required this.color, required this.style});

  final Color color;
  final ReaderAnnotationStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    AnnotationStylePainter.paint(
      canvas,
      Rect.fromLTRB(14, 0, size.width - 14, size.height - 7),
      color: color,
      style: style,
      strokeWidth: 2,
    );
  }

  @override
  bool shouldRepaint(_AnnotationPreviewPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.style != style;
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
      label: Text(isNote ? '删除笔记与高亮' : '取消高亮'),
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
