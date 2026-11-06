import 'package:flutter/material.dart';

import 'decoration_style.dart';
import 'style_controls.dart';

/// 手工装饰的四边边框与绘制内边距。
class ReaderDecorationBorderEditor extends StatefulWidget {
  /// 创建边框编辑器。
  const ReaderDecorationBorderEditor({
    super.key,
    required this.style,
    required this.onChanged,
  });

  /// 当前草稿。
  final ReaderDecorationStyle style;

  /// 修改样式。
  final ValueChanged<ReaderDecorationStyle> onChanged;
  @override
  State<ReaderDecorationBorderEditor> createState() =>
      _ReaderDecorationBorderEditorState();
}

class _ReaderDecorationBorderEditorState
    extends State<ReaderDecorationBorderEditor> {
  late bool _unified = _sameSides(widget.style);
  @override
  void didUpdateWidget(covariant ReaderDecorationBorderEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSides(widget.style)) {
      _unified = false;
    } else if (!_sameSides(oldWidget.style)) {
      _unified = true;
    }
  }

  static bool _sameSides(ReaderDecorationStyle style) {
    final sides = [
      style.borderTop,
      style.borderRight,
      style.borderBottom,
      style.borderLeft,
    ];
    return sides.every(
      (side) =>
          side.width == sides.first.width && side.color == sides.first.color,
    );
  }

  void _set(String name, Object? value) =>
      widget.onChanged(widget.style.withValues({name: value}));
  void _side(String field, ReaderDecorationBorderSide value) =>
      widget.onChanged(
        widget.style.withValues({
          if (_unified)
            for (final name in [
              'borderTop',
              'borderRight',
              'borderBottom',
              'borderLeft',
            ])
              name: value.toJson()
          else
            field: value.toJson(),
        }),
      );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ReaderBorderStyleField(
        value: widget.style.borderStyle,
        onChanged: (value) => _set('borderStyle', value.name),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('统一四边边框'),
        value: _unified,
        onChanged: (value) {
          setState(() => _unified = value);
          if (value) _side('borderTop', widget.style.borderTop);
        },
      ),
      if (_unified)
        _controls('四边', 'borderTop', widget.style.borderTop)
      else ...[
        _controls('上边', 'borderTop', widget.style.borderTop),
        _controls('右边', 'borderRight', widget.style.borderRight),
        _controls('下边', 'borderBottom', widget.style.borderBottom),
        _controls('左边', 'borderLeft', widget.style.borderLeft),
      ],
      const Divider(),
      const Text('内边距只扩展绘制盒，不改变行宽或分页；上下内边距按行距截断。'),
      const SizedBox(height: 12),
      for (final entry in {
        'paddingTop': ('上内边距', widget.style.paddingTop),
        'paddingRight': ('右内边距', widget.style.paddingRight),
        'paddingBottom': ('下内边距', widget.style.paddingBottom),
        'paddingLeft': ('左内边距', widget.style.paddingLeft),
      }.entries)
        ReaderStyleSlider(
          label: entry.value.$1,
          value: entry.value.$2,
          min: 0,
          max: 12,
          divisions: 12,
          digits: 0,
          suffix: ' dp',
          onChanged: (value) => _set(entry.key, value),
        ),
    ],
  );

  Widget _controls(
    String label,
    String name,
    ReaderDecorationBorderSide side,
  ) => Column(
    children: [
      ReaderStyleSlider(
        label: '$label宽度',
        value: side.width,
        min: 0,
        max: 6,
        divisions: 12,
        suffix: ' dp',
        onChanged: (value) => _side(
          name,
          ReaderDecorationBorderSide(width: value, color: side.color),
        ),
      ),
      ReaderStyleColorField(
        label: '$label颜色',
        color: side.color,
        allowClear: false,
        onChanged: (value) {
          if (value != null) {
            _side(
              name,
              ReaderDecorationBorderSide(width: side.width, color: value),
            );
          }
        },
      ),
    ],
  );
}
