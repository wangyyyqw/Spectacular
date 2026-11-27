import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

class ParagraphEditSheet extends StatefulWidget {
  const ParagraphEditSheet({super.key, required this.open, required this.save});

  final Future<EpubParagraphEdit> Function() open;
  final Future<void> Function(EpubParagraphEdit edit, String input) save;

  @override
  State<ParagraphEditSheet> createState() => _ParagraphEditSheetState();
}

class _ParagraphEditSheetState extends State<ParagraphEditSheet> {
  final _input = TextEditingController();
  EpubParagraphEdit? _edit;
  String? _openError;
  bool _saving = false;
  bool _dirty = false;
  bool _confirming = false;
  String? _toast;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final edit = await widget.open();
      if (!mounted) {
        edit.session.close();
        return;
      }
      _edit = edit;
      _input.text = edit.initialText;
      setState(() {});
    } catch (error) {
      if (mounted) setState(() => _openError = '无法编辑：$error');
    }
  }

  Future<void> _save() async {
    final edit = _edit;
    if (_saving || edit == null) return;
    if (_input.text == edit.initialText) {
      Navigator.pop(context, false);
      return;
    }
    _timer?.cancel();
    setState(() {
      _saving = true;
      _toast = null;
    });
    try {
      await widget.save(edit, _input.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _toast = '未保存：$error';
      });
      _timer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _toast = null);
      });
    }
  }

  Future<void> _cancel() async {
    if (_saving || _confirming) return;
    if (_dirty) {
      _confirming = true;
      final discard = await showReaderConfirmDialog(
        context: context,
        title: '放弃段落修改？',
        message: '本次输入还没有保存。',
        cancelLabel: '继续编辑',
        confirmLabel: '放弃修改',
        destructive: true,
      );
      _confirming = false;
      if (!discard || !mounted) return;
    }
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _edit?.session.close();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edit = _edit;
    final theme = Theme.of(context);
    return PopScope<bool>(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_cancel());
      },
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          ReaderSheetForm(
            title: const Text('编辑段落'),
            content: _openError != null
                ? Text(_openError!)
                : edit == null
                ? const Center(child: CircularProgressIndicator())
                : TextField(
                    controller: _input,
                    onChanged: (value) {
                      final dirty = value != edit.initialText;
                      if (_dirty != dirty) setState(() => _dirty = dirty);
                    },
                    readOnly: _saving,
                    minLines: 4,
                    maxLines: 12,
                    style: edit.isHtml
                        ? theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                          )
                        : null,
                    decoration: InputDecoration(
                      labelText: edit.isHtml ? 'HTML 源码' : '正文',
                      alignLabelWithHint: true,
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: _saving ? null : _cancel,
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: _saving || edit == null ? null : _save,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ],
          ),
          if (_toast case final message?)
            Positioned(
              top: 4,
              left: 16,
              right: 16,
              child: IgnorePointer(
                child: Semantics(
                  liveRegion: true,
                  child: Material(
                    color: theme.colorScheme.inverseSurface,
                    borderRadius: ReaderUiStyle.controlRadiusOf(theme),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onInverseSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
