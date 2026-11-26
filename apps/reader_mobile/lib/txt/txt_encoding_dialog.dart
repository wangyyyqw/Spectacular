import 'package:flutter/material.dart';
import 'package:reader_core/txt.dart';
import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

/// 候选样例由实际导入字节解码得到，选定后使用同一任务重试。
Future<String?> chooseTxtEncoding(
  BuildContext context,
  List<TxtEncodingCandidate> candidates,
) => showReaderDrawer<String>(
  context: context,
  builder: (_) => _EncodingDialog(candidates: candidates),
);

class _EncodingDialog extends StatefulWidget {
  const _EncodingDialog({required this.candidates});
  final List<TxtEncodingCandidate> candidates;

  @override
  State<_EncodingDialog> createState() => _EncodingDialogState();
}

class _EncodingDialogState extends State<_EncodingDialog> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    title: const Text('选择 TXT 编码'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('请选择正文显示正确的编码，然后继续导入。'),
          const SizedBox(height: 16),
          ReaderDropdownButtonFormField<int>(
            initialValue: _selected,
            decoration: const InputDecoration(labelText: '编码'),
            items: [
              for (final (index, candidate) in widget.candidates.indexed)
                DropdownMenuItem(value: index, child: Text(candidate.name)),
            ],
            onChanged: (value) => setState(() => _selected = value!),
          ),
          const SizedBox(height: 16),
          Container(
            height: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: ReaderUiStyle.controlRadius,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: SingleChildScrollView(
              child: SelectableText(widget.candidates[_selected].sample),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, widget.candidates[_selected].name),
        child: const Text('继续导入'),
      ),
    ],
  );
}
