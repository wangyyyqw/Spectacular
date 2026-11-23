import '../theme/reader_dropdown.dart';

import 'package:flutter/material.dart';

import '../annotations/annotation_appearance_editor.dart';
import '../icons/app_icon.dart';
import 'decoration_style.dart';

class ReaderDecorationImageFitField extends StatelessWidget {
  const ReaderDecorationImageFitField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final ReaderDecorationImageFit value;
  final ValueChanged<ReaderDecorationImageFit> onChanged;

  @override
  Widget build(BuildContext context) =>
      ReaderDropdownButtonFormField<ReaderDecorationImageFit>(
        key: ValueKey('decoration-image-fit-${value.name}'),
        initialValue: value,
        isExpanded: true,
        icon: const AppIcon(AppGlyph.chevronDown),
        decoration: const InputDecoration(labelText: '图片铺放方式'),
        items: [
          for (final fit in ReaderDecorationImageFit.values)
            DropdownMenuItem(value: fit, child: Text(fit.label)),
        ],
        onChanged: (fit) {
          if (fit != null) onChanged(fit);
        },
      );
}

/// 装饰面板共用的数值滑杆。
class ReaderStyleSlider extends StatelessWidget {
  /// 创建滑杆。
  const ReaderStyleSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.suffix = '',
    this.digits = 1,
  });

  /// 属性名称。
  final String label;

  /// 当前值。
  final double value;

  /// 下限。
  final double min;

  /// 上限。
  final double max;

  /// 可选离散档数。
  final int? divisions;

  /// 单位。
  final String suffix;

  /// 小数位。
  final int digits;

  /// 修改回调。
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text('${value.toStringAsFixed(digits)}$suffix'),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: '${value.toStringAsFixed(digits)}$suffix',
        onChanged: onChanged,
      ),
    ],
  );
}

/// 任意颜色与继承/关闭控制。
class ReaderStyleColorField extends StatelessWidget {
  /// 创建颜色属性控件。
  const ReaderStyleColorField({
    super.key,
    required this.label,
    required this.color,
    required this.onChanged,
    this.clearLabel = '跟随原文',
    this.allowClear = true,
  });

  /// 属性名称。
  final String label;

  /// 空值表示继承或关闭。
  final int? color;

  /// 修改回调。
  final ValueChanged<int?> onChanged;

  /// 清除后的含义。
  final String clearLabel;

  /// 是否允许清除。
  final bool allowClear;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      TextButton.icon(
        onPressed: () async {
          final selected = await showReaderColorDialog(
            context,
            initialColor: color ?? 0xFF374151,
          );
          if (selected != null && context.mounted) onChanged(selected);
        },
        icon: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color == null ? Colors.transparent : Color(color!),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        label: Text(
          color == null
              ? clearLabel
              : '#${color!.toRadixString(16).toUpperCase().padLeft(8, '0')}',
        ),
      ),
      if (allowClear && color != null)
        IconButton(
          tooltip: clearLabel,
          onPressed: () => onChanged(null),
          icon: const AppIcon(AppGlyph.close, size: 18),
        ),
    ],
  );
}

/// 四种边框线型选择器。
class ReaderBorderStyleField extends StatelessWidget {
  /// 创建线型控件。
  const ReaderBorderStyleField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// 当前线型。
  final ReaderDecorationBorderStyle value;

  /// 修改回调。
  final ValueChanged<ReaderDecorationBorderStyle> onChanged;
  @override
  Widget build(BuildContext context) =>
      ReaderDropdownButtonFormField<ReaderDecorationBorderStyle>(
        icon: const AppIcon(AppGlyph.chevronDown),
        initialValue: value,
        decoration: const InputDecoration(labelText: '边框线型'),
        items: [
          for (final item in ReaderDecorationBorderStyle.values)
            DropdownMenuItem(value: item, child: Text(item.label)),
        ],
        onChanged: (item) {
          if (item != null) onChanged(item);
        },
      );
}
