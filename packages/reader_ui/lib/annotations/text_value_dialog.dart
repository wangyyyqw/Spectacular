import 'package:flutter/material.dart';

import '../theme/reader_frosted_popup.dart';

/// 由弹窗自身管理输入控制器，避免退场动画读取已释放对象。
class ReaderTextValueDialog extends StatefulWidget {
  /// 创建带校验的单值输入弹窗。
  const ReaderTextValueDialog({
    super.key,
    required this.title,
    required this.label,
    required this.initialValue,
    required this.validate,
    this.confirmLabel = '保存',
    this.inputKey,
    this.saveKey,
    this.maxLength,
  });

  /// 弹窗标题。
  final String title;

  /// 输入名称。
  final String label;

  /// 初始值。
  final String initialValue;

  /// 返回空值表示校验通过，否则显示错误文案。
  final String? Function(String) validate;

  /// 确认按钮文案。
  final String confirmLabel;

  /// 输入框定位键。
  final Key? inputKey;

  /// 保存按钮定位键。
  final Key? saveKey;

  /// 可选最大长度。
  final int? maxLength;
  @override
  State<ReaderTextValueDialog> createState() => _ReaderTextValueDialogState();
}

class _ReaderTextValueDialogState extends State<ReaderTextValueDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);
  String? _error;
  bool _closing = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_closing) return;
    final value = _controller.text.trim();
    final error = widget.validate(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _closing = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => ReaderFrostedAlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: widget.inputKey,
      controller: _controller,
      autofocus: true,
      maxLength: widget.maxLength,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      decoration: InputDecoration(labelText: widget.label, errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: widget.saveKey,
        onPressed: _save,
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
