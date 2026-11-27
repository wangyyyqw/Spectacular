import 'dart:async';

import 'package:flutter/material.dart';

import '../panels/reader_settings_sheet.dart';
import '../theme/reader_section_slider.dart';
import 'annotation.dart';
import 'annotation_appearance_editor.dart';
import 'annotation_editor_sheet.dart';
import 'annotation_quote_preview.dart';
import 'mark_settings.dart';
import '../theme/reader_frosted_popup.dart';

/// 新建纯文本想法，外观与正文一起保存。
class ReaderNoteComposerSheet extends StatefulWidget {
  /// 创建想法编辑器。
  const ReaderNoteComposerSheet({
    super.key,
    required this.quote,
    this.markSettings = const ReaderMarkSettings(),
    this.initialOpacity,
    this.inkMode = false,
  });

  /// 选中的原文。
  final String quote;

  /// 上次使用的划线外观。
  final ReaderMarkSettings markSettings;

  /// 升级已有划线时保留其透明度。
  final double? initialOpacity;

  /// 墨水屏模式。
  final bool inkMode;
  @override
  State<ReaderNoteComposerSheet> createState() =>
      _ReaderNoteComposerSheetState();
}

class _ReaderNoteComposerSheetState extends State<ReaderNoteComposerSheet> {
  final _controller = TextEditingController();
  late ReaderMarkSettings _settings = widget.markSettings;
  late int _color = widget.markSettings.lastColor;
  late ReaderAnnotationStyle _style = widget.markSettings.lastStyle;
  late double _opacity = widget.initialOpacity ?? _style.defaultOpacity;
  bool _allowPop = false;
  bool _dialogVisible = false;
  bool _closing = false;
  int _sectionIndex = 0;

  List<ReaderAnnotationAppearanceSection> get _sections => widget.inkMode
      ? const [ReaderAnnotationAppearanceSection.line]
      : const [
          ReaderAnnotationAppearanceSection.color,
          ReaderAnnotationAppearanceSection.background,
          ReaderAnnotationAppearanceSection.line,
          ReaderAnnotationAppearanceSection.width,
        ];

  String get _note => _controller.text.trim();
  bool get _dirty =>
      _note.isNotEmpty ||
      _color != widget.markSettings.lastColor ||
      _style != widget.markSettings.lastStyle ||
      _opacity !=
          (widget.initialOpacity ??
              widget.markSettings.lastStyle.defaultOpacity) ||
      _settings != widget.markSettings;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    if (_closing || _dialogVisible) return;
    if (!_dirty) {
      _pop();
      return;
    }
    _dialogVisible = true;
    final discard = await showReaderConfirmDialog(
      context: context,
      title: '放弃未保存的想法？',
      message: '想法内容或划线外观还没有保存，离开后本次输入会丢失。',
      cancelLabel: '继续编辑',
      confirmLabel: '放弃想法',
      cancelKey: const ValueKey<String>('note-discard-cancel'),
      confirmKey: const ValueKey<String>('note-discard-confirm'),
    );
    _dialogVisible = false;
    if (discard && mounted) _pop();
  }

  void _save() => _pop(
    AnnotationEditAction.save(
      color: _color,
      style: _style,
      opacity: _opacity,
      note: _note,
      markSettings: _settings.copyWith(lastColor: _color, lastStyle: _style),
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
      child: ReaderSettingsSheet(
        key: const ValueKey<String>('note-composer-sheet'),
        header: _header(context),
        footer: FilledButton(
          key: const ValueKey<String>('note-composer-save'),
          onPressed: _note.isEmpty ? null : _save,
          child: const Text('保存想法'),
        ),
        child: _content(context),
      ),
    ),
  );

  Widget _header(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AnnotationQuotePreview(
        key: ValueKey<String>(
          widget.inkMode
              ? 'note-composer-ink-preview'
              : 'note-composer-quote-preview',
        ),
        quote: widget.quote,
        color: _color,
        style: _style,
        opacity: _opacity,
        strokeWidth: _settings.strokeWidth,
        inkMode: widget.inkMode,
        thought: true,
      ),
    ],
  );

  Widget _content(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('想法内容', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey<String>('note-composer-input'),
        controller: _controller,
        autofocus: true,
        minLines: 4,
        maxLines: 8,
        textInputAction: TextInputAction.newline,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(hintText: '写下此刻的想法…'),
      ),
      const SizedBox(height: 16),
      ReaderSectionSlider(
        key: const ValueKey<String>('note-composer-section-tabs'),
        sections: [
          for (final section in _sections)
            (
              key: section.name,
              label: switch (section) {
                ReaderAnnotationAppearanceSection.all => '全部设置',
                ReaderAnnotationAppearanceSection.color => '颜色',
                ReaderAnnotationAppearanceSection.background => '背景',
                ReaderAnnotationAppearanceSection.line => '线条',
                ReaderAnnotationAppearanceSection.width => '线宽',
              },
            ),
        ],
        index: _sectionIndex,
        onSelected: (index) => setState(() => _sectionIndex = index),
      ),
      const SizedBox(height: 12),
      ReaderAnnotationAppearanceEditor(
        color: _color,
        style: _style,
        opacity: _opacity,
        settings: _settings,
        inkMode: widget.inkMode,
        section: _sections[_sectionIndex],
        onColor: (value) => setState(() => _color = value),
        onStyle: (value) => setState(() {
          _style = value;
          _opacity = value.defaultOpacity;
        }),
        onOpacity: (value) => setState(() => _opacity = value),
        onSettings: (value) => setState(() => _settings = value),
      ),
    ],
  );
}
