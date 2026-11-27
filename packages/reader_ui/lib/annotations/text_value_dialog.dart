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
    this.hintText,
    this.disableWhenEmpty = false,
    this.submitOnEnter = false,
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

  final String? hintText;

  /// 名称输入为空时禁用保存；其他输入仍在提交时显示校验错误。
  final bool disableWhenEmpty;

  /// 名称表单可通过键盘完成键提交。
  final bool submitOnEnter;
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
    if (widget.disableWhenEmpty && value.isEmpty) return;
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
      textInputAction: widget.submitOnEnter ? TextInputAction.done : null,
      onSubmitted: widget.submitOnEnter ? (_) => _save() : null,
      onChanged: (_) {
        if (_error != null || widget.disableWhenEmpty) {
          setState(() => _error = null);
        }
      },
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: widget.saveKey,
        onPressed: widget.disableWhenEmpty && _controller.text.trim().isEmpty
            ? null
            : _save,
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
