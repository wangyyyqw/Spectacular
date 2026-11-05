import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/reader_theme.dart';

/// 配色草稿只在保存时应用，取消保留原主题。
class CustomThemeDialog extends StatefulWidget {
  const CustomThemeDialog({super.key, required this.theme});

  final ReaderTheme theme;

  @override
  State<CustomThemeDialog> createState() => _CustomThemeDialogState();
}

class _CustomThemeDialogState extends State<CustomThemeDialog> {
  late Color _background = widget.theme.background;
  late Color _text = widget.theme.text;
  bool _editingText = false;
  String? _error;
  late final TextEditingController _hex = TextEditingController(
    text: _rgb(_background),
  );

  Color get _color => _editingText ? _text : _background;
  ReaderTheme get _draft =>
      ReaderTheme.custom(background: _background, text: _text);
  String _rgb(Color color) => (color.toARGB32() & 0xFFFFFF)
      .toRadixString(16)
      .padLeft(6, '0')
      .toUpperCase();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setColor(Color color) {
    setState(() {
      if (_editingText) {
        _text = color;
      } else {
        _background = color;
      }
      _error = null;
      _hex.text = _rgb(color);
    });
  }

  void _changeHex(String value) {
    if (value.length != 6) {
      setState(() => _error = '请输入六位颜色值');
      return;
    }
    setState(() {
      final color = Color(0xFF000000 | int.parse(value, radix: 16));
      if (_editingText) {
        _text = color;
      } else {
        _background = color;
      }
      _error = null;
    });
  }

  Widget _channel(String label, int shift) {
    final rgb = _color.toARGB32();
    final value = (rgb >> shift) & 255;
    return Row(
      children: [
        Text(label),
        Expanded(
          child: Slider(
            key: ValueKey('custom-color-$label'),
            value: value.toDouble(),
            min: 0,
            max: 255,
            onChanged: (next) => _setColor(
              Color((rgb & ~(255 << shift)) | (next.round() << shift)),
            ),
          ),
        ),
        SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.right)),
      ],
    );
  }

  Widget _preview() => Container(
    key: const ValueKey('custom-theme-preview'),
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _background,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      '清风徐来，水波不兴。\n在这里预览正文与背景的颜色。',
      style: TextStyle(color: _text, fontSize: 16, height: 1.7),
    ),
  );

  Widget _hexInput() => TextField(
    key: const ValueKey('custom-color-hex'),
    controller: _hex,
    decoration: InputDecoration(
      labelText: '颜色值',
      prefixText: '#',
      errorText: _error,
    ),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
      LengthLimitingTextInputFormatter(6),
    ],
    onChanged: _changeHex,
  );

  Widget _controls() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('背景色')),
          ButtonSegment(value: true, label: Text('文字色')),
        ],
        selected: {_editingText},
        onSelectionChanged: (selected) => setState(() {
          _editingText = selected.single;
          _error = null;
          _hex.text = _rgb(_color);
        }),
      ),
      const SizedBox(height: 12),
      _hexInput(),
      _channel('红', 16),
      _channel('绿', 8),
      _channel('蓝', 0),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义主题'),
    content: SizedBox(
      width: 340,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _preview(),
            const SizedBox(height: 16),
            _controls(),
            Text(
              _draft.luminance >= 4.5 ? '文字与背景清晰可辨' : '当前颜色接近，建议拉大明暗差异',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('custom-theme-save'),
        onPressed: _error == null ? () => Navigator.pop(context, _draft) : null,
        child: const Text('保存'),
      ),
    ],
  );
}
