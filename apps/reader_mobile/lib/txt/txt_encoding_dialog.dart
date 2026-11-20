import 'package:flutter/material.dart';
import 'package:reader_core/txt.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

/// 候选样例由实际导入字节解码得到，选定后使用同一任务重试。
Future<String?> chooseTxtEncoding(
  BuildContext context,
  List<TxtEncodingCandidate> candidates,
) => showDialog<String>(
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
  Widget build(BuildContext context) => ReaderFrostedAlertDialog(
    title: const Text('选择 TXT 编码'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('请选择正文显示正确的编码，然后继续导入。'),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _selected,
            decoration: const InputDecoration(
              labelText: '编码',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final (index, candidate) in widget.candidates.indexed)
                DropdownMenuItem(value: index, child: Text(candidate.name)),
            ],
            onChanged: (value) => setState(() => _selected = value!),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
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
