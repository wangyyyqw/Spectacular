import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/reader_ui_style.dart';

import '../icons/app_icon.dart';
import 'annotation.dart';
import 'annotation_appearance_editor.dart';
import 'annotation_quote_preview.dart';
import 'mark_settings.dart';
import '../theme/reader_frosted_popup.dart';
import '../theme/reader_frosted_surface.dart';

export 'annotation_appearance_editor.dart'
    show AnnotationColorOption, AnnotationStyleOption;

/// 标注编辑动作。
enum AnnotationEditActionType {
  /// 保存外观和想法正文。
  save,

  /// 只删除想法正文，保留划线。
  removeNote,

  /// 删除完整标注。
  remove,
}

/// 标注编辑弹层返回的原子修改。
class AnnotationEditAction {
  const AnnotationEditAction._({
    required this.type,
    this.color,
    this.style,
    this.opacity,
    this.note,
    this.markSettings,
  });

  /// 保存划线和可选想法正文。
  const AnnotationEditAction.save({
    required int color,
    required ReaderAnnotationStyle style,
    double? opacity,
    String? note,
    ReaderMarkSettings? markSettings,
  }) : this._(
         type: AnnotationEditActionType.save,
         color: color,
         style: style,
         opacity: opacity,
         note: note,
         markSettings: markSettings,
       );

  /// 删除标注。
  const AnnotationEditAction.remove()
    : this._(type: AnnotationEditActionType.remove);

  /// 删除想法但保留当前划线外观。
  const AnnotationEditAction.removeNote({
    required int color,
    required ReaderAnnotationStyle style,
    double? opacity,
    ReaderMarkSettings? markSettings,
  }) : this._(
         type: AnnotationEditActionType.removeNote,
         color: color,
         style: style,
         opacity: opacity,
         markSettings: markSettings,
       );

  /// 操作类型。
  final AnnotationEditActionType type;

  /// 标记颜色。
  final int? color;

  /// 标记样式。
  final ReaderAnnotationStyle? style;

  /// 标记透明度。
  final double? opacity;

  /// 想法正文；空值表示不修改正文。
  final String? note;

  /// 随保存一起提交的划线偏好。
  final ReaderMarkSettings? markSettings;
}

/// 点击划线或想法后打开的编辑面板。
class ReaderAnnotationEditorSheet extends StatefulWidget {
  /// 创建标注编辑器。
  const ReaderAnnotationEditorSheet({
    super.key,
    required this.annotation,
    this.markSettings = const ReaderMarkSettings(),
    this.inkMode = false,
  });

  /// 五个预设颜色。
  static const colors = ReaderAnnotationAppearanceEditor.colors;

  /// 九种划线样式。
  static final styles = ReaderAnnotationAppearanceEditor.styles;

  /// 正在编辑的标注。
  final ReaderAnnotation annotation;

  /// 全书划线偏好。
  final ReaderMarkSettings markSettings;

  /// 墨水屏模式。
  final bool inkMode;

  @override
  State<ReaderAnnotationEditorSheet> createState() =>
      _ReaderAnnotationEditorSheetState();
}

class _ReaderAnnotationEditorSheetState
    extends State<ReaderAnnotationEditorSheet> {
  late final TextEditingController _noteController;
  late int _color;
  late ReaderAnnotationStyle _style;
  late double _opacity;
  late ReaderMarkSettings _settings;
  bool _showNoteEditor = false;
  bool _autofocus = false;
  bool _allowPop = false;
  bool _dialogVisible = false;
  bool _closing = false;

  bool get _isThought => widget.annotation.type == ReaderAnnotationType.thought;
  bool get _canEditNote => _isThought || _showNoteEditor;
  String get _note => _noteController.text.trim();
  bool get _noteChanged => _note != (widget.annotation.note?.trim() ?? '');
  bool get _appearanceChanged =>
      _color != (widget.annotation.color ?? defaultHighlightColor) ||
      _style != widget.annotation.style ||
      _opacity != widget.annotation.effectiveOpacity;
  bool get _settingsChanged =>
      _settings.strokeWidth != widget.markSettings.strokeWidth ||
      _settings.joinBackgroundLines !=
          widget.markSettings.joinBackgroundLines ||
      !listEquals(_settings.customColors, widget.markSettings.customColors);
  bool get _dirty => _noteChanged || _appearanceChanged || _settingsChanged;
  bool get _canSave => (!_canEditNote || _note.isNotEmpty) && _dirty;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.annotation.note ?? '');
    _color = widget.annotation.color ?? defaultHighlightColor;
    _style = widget.annotation.style;
    _opacity = widget.annotation.effectiveOpacity;
    _settings = widget.markSettings;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  ReaderMarkSettings get _savedSettings =>
      _settings.copyWith(lastColor: _color, lastStyle: _style);

  Future<bool> _confirm({
    required String title,
    required String content,
    required String confirm,
    required String keyPrefix,
  }) async {
    if (_dialogVisible) return false;
    _dialogVisible = true;
    final result = await showReaderConfirmDialog(
      context: context,
      title: title,
      message: content,
      cancelLabel: keyPrefix == 'annotation-discard' ? '继续编辑' : '取消',
      confirmLabel: confirm,
      destructive: true,
      cancelKey: ValueKey<String>('$keyPrefix-cancel'),
      confirmKey: ValueKey<String>('$keyPrefix-confirm'),
    );
    _dialogVisible = false;
    return result;
  }

  void _pop([AnnotationEditAction? action]) {
    if (_closing) return;
    _closing = true;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(action);
    });
  }

  Future<void> _close() async {
    if (_closing) return;
    if (_dirty &&
        !await _confirm(
          title: _noteChanged ? '放弃未保存的想法修改？' : '放弃未保存的修改？',
          content: _noteChanged
              ? '想法内容还没有保存，离开后本次修改会丢失。'
              : '颜色、样式或划线偏好还没有保存，离开后本次修改会丢失。',
          confirm: '放弃修改',
          keyPrefix: 'annotation-discard',
        )) {
      return;
    }
    if (mounted) _pop();
  }

  Future<void> _finish(AnnotationEditAction action) async {
    if (_closing) return;
    if (action.type == AnnotationEditActionType.removeNote &&
        !await _confirm(
          title: '只删除这条想法？',
          content: '划线会保留，删除后想法正文无法恢复。',
          confirm: '只删除想法',
          keyPrefix: 'annotation-remove-note',
        )) {
      return;
    }
    if (action.type == AnnotationEditActionType.remove &&
        _isThought &&
        !await _confirm(
          title: '删除这条标注？',
          content: _noteChanged
              ? '想法正文、划线和尚未保存的修改都会被永久删除。'
              : '想法正文和划线会一起删除，删除后无法恢复。',
          confirm: '删除标注',
          keyPrefix: 'annotation-remove',
        )) {
      return;
    }
    if (mounted) _pop(action);
  }

  void _save() => unawaited(
    _finish(
      AnnotationEditAction.save(
        color: _color,
        style: _style,
        opacity: _opacity,
        note: _canEditNote ? _note : null,
        markSettings: _savedSettings,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty || _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        key: const ValueKey<String>('annotation-editor-sheet'),
        color: ReaderFrostedSurface.panelColorOf(context),
        borderRadius: ReaderUiStyle.sheetRadiusOf(Theme.of(context)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 8, 8),
                child: Row(
                  children: [
                    AppIcon(
                      _isThought ? AppGlyph.note : AppGlyph.highlighter,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isThought ? '想法' : '划线',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: _close,
                      tooltip: '关闭',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      icon: const AppIcon(AppGlyph.close, size: 20),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: _content(context),
                ),
              ),
              _actions(context),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      AnnotationQuotePreview(
        quote: widget.annotation.quote,
        color: _color,
        style: _style,
        opacity: _opacity,
        strokeWidth: _settings.strokeWidth,
        inkMode: widget.inkMode,
        thought: _canEditNote,
      ),
      if (!_canEditNote) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey<String>('annotation-add-note'),
          onPressed: () => setState(() {
            _showNoteEditor = true;
            _autofocus = true;
          }),
          icon: const AppIcon(AppGlyph.noteAdd),
          label: const Text('为这条划线添加想法'),
        ),
      ],
      if (_canEditNote) ...[
        const SizedBox(height: 16),
        Text('想法内容', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey<String>('annotation-note-input'),
          controller: _noteController,
          autofocus: _autofocus,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(hintText: '写下此刻的想法…'),
        ),
      ],
      const SizedBox(height: 16),
      ReaderAnnotationAppearanceEditor(
        color: _color,
        style: _style,
        opacity: _opacity,
        settings: _settings,
        inkMode: widget.inkMode,
        onColor: (value) => setState(() => _color = value),
        onStyle: (value) => setState(() {
          _style = value;
          if (widget.annotation.opacity == null) {
            _opacity = value.defaultOpacity;
          }
        }),
        onOpacity: (value) => setState(() => _opacity = value),
        onSettings: (value) => setState(() => _settings = value),
      ),
    ],
  );

  Widget _actions(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            key: ValueKey<String>(
              _canEditNote ? 'annotation-save-note' : 'annotation-save-changes',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            onPressed: _canSave ? _save : null,
            icon: const AppIcon(AppGlyph.check),
            label: Text(
              _isThought
                  ? '保存想法'
                  : _note.isNotEmpty
                  ? '保存为想法'
                  : '保存修改',
            ),
          ),
          if (_isThought) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey<String>('annotation-remove-note'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: () => unawaited(
                _finish(
                  AnnotationEditAction.removeNote(
                    color: _color,
                    style: _style,
                    opacity: _opacity,
                    markSettings: _savedSettings,
                  ),
                ),
              ),
              icon: const AppIcon(AppGlyph.article),
              label: const Text('只删除想法，保留划线'),
            ),
          ],
          TextButton.icon(
            key: const ValueKey<String>('annotation-remove'),
            onPressed: () =>
                unawaited(_finish(const AnnotationEditAction.remove())),
            icon: AppIcon(
              AppGlyph.delete,
              color: Theme.of(context).colorScheme.error,
            ),
            label: Text(
              _isThought ? '删除标注' : '删除划线',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    ),
  );
}
