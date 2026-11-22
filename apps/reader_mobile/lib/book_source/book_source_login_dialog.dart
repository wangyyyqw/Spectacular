import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:flutter/material.dart';

import 'book_source_login_config.dart';
import 'book_source_models.dart';
import 'online_book_controller.dart';

/// 按源声明显示登录表单，动作执行时保留尚未提交的输入。
class BookSourceLoginDialog extends StatefulWidget {
  const BookSourceLoginDialog({
    super.key,
    required this.source,
    required this.controller,
    required this.rows,
  });

  final BookSource source;
  final OnlineBookController controller;
  final List<BookSourceLoginField> rows;

  @override
  State<BookSourceLoginDialog> createState() => _BookSourceLoginDialogState();
}

class _BookSourceLoginDialogState extends State<BookSourceLoginDialog> {
  late List<BookSourceLoginField> _rows;
  late Map<String, String> _values;
  final Map<String, TextEditingController> _inputs = {};
  bool _busy = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _values = widget.controller.cookieStore.loginInfo(widget.source);
    _setRows(widget.rows);
  }

  void _setRows(List<BookSourceLoginField> rows) {
    _rows = rows;
    for (final row in rows.where((row) => row.input)) {
      _values.putIfAbsent(row.name, () => row.defaultValue);
      if (!const {'select', 'toggle'}.contains(row.type)) {
        _inputs.putIfAbsent(
          row.name,
          () => TextEditingController(text: _values[row.name]),
        );
      }
    }
  }

  Map<String, String> _currentValues() => {
    ..._values,
    for (final entry in _inputs.entries) entry.key: entry.value.text,
  };

  Future<void> _runAction(BookSourceLoginField row) async {
    if (_busy || row.action.isEmpty) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final result = await widget.controller.runLoginAction(
        widget.source,
        _currentValues(),
        row.action,
      );
      if (!mounted) return;
      if (result.success) {
        _values.addAll(widget.controller.cookieStore.loginInfo(widget.source));
        for (final entry in _inputs.entries) {
          entry.value.text = _values[entry.key] ?? entry.value.text;
        }
        if (result.rebuildView) {
          final rows = await widget.controller.auth.rowsFor(
            widget.source,
            widget.controller.cookieStore,
          );
          if (!mounted) return;
          _setRows(rows);
        }
      }
      setState(() => _message = result.message);
    } on Object {
      if (mounted) setState(() => _message = '书源操作失败，请检查网络和书源配置');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final input in _inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  Widget _row(BookSourceLoginField row) {
    final key = ValueKey('online-login-field-${row.name}');
    if (row.type == 'button') {
      return OutlinedButton(
        key: ValueKey('online-login-action-${row.name}'),
        onPressed: _busy || row.action.isEmpty ? null : () => _runAction(row),
        child: Text(row.label),
      );
    }
    if (const {'select', 'toggle'}.contains(row.type)) {
      final value = _values[row.name];
      return ReaderDropdownButtonFormField<String>(
        key: ValueKey('${key.value}-${value ?? ''}'),
        initialValue: row.options.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: row.label),
        items: [
          for (final option in row.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: _busy
            ? null
            : (value) {
                if (value == null) return;
                setState(() => _values[row.name] = value);
                _runAction(row);
              },
      );
    }
    return TextField(
      key: key,
      controller: _inputs[row.name],
      enabled: !_busy,
      obscureText: row.secret,
      autocorrect: false,
      enableSuggestions: !row.secret,
      keyboardType: switch (row.type) {
        'number' => TextInputType.number,
        'email' => TextInputType.emailAddress,
        'tel' || 'phone' => TextInputType.phone,
        _ => TextInputType.text,
      },
      decoration: InputDecoration(labelText: row.label),
      onSubmitted: row.action.isEmpty ? null : (_) => _runAction(row),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text('登录 ${widget.source.name}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final row in _rows) ...[
                      if (row.wrapBefore) SizedBox(width: constraints.maxWidth),
                      SizedBox(
                        width: row.basisPercent >= 1
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 24) * row.basisPercent,
                        child: _row(row),
                      ),
                    ],
                  ],
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_message),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('online-login-submit'),
          onPressed: _busy
              ? null
              : () => Navigator.pop(context, _currentValues()),
          child: const Text('登录'),
        ),
      ],
    ),
  );
}
