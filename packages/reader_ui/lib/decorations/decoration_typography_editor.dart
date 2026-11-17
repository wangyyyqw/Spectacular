import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../panels/settings_panel.dart' show ReaderFontOption;
import 'decoration_style.dart';
import 'style_controls.dart';

/// 只有手工装饰可以编辑的字体度量属性。
class ReaderDecorationTypographyEditor extends StatelessWidget {
  /// 创建字体编辑器。
  const ReaderDecorationTypographyEditor({
    super.key,
    required this.style,
    required this.fonts,
    required this.onChanged,
  });

  /// 当前样式。
  final ReaderDecorationStyle style;

  /// 已安装的字体，注册由编辑面板统一处理。
  final List<ReaderFontOption> fonts;

  /// 提交草稿。
  final ValueChanged<ReaderDecorationStyle> onChanged;
  void _set(String name, Object? value) =>
      onChanged(style.withValues({name: value}));
  @override
  Widget build(BuildContext context) => Column(
    children: [
      DropdownButtonFormField<String>(
        key: const ValueKey<String>('decoration-font'),
        icon: const AppIcon(AppGlyph.chevronDown),
        initialValue: style.fontFamily ?? '',
        isExpanded: true,
        decoration: const InputDecoration(labelText: '字体'),
        items: [
          const DropdownMenuItem(value: '', child: Text('跟随正文')),
          for (final font in fonts)
            DropdownMenuItem(value: font.family, child: Text(font.label)),
          if (style.fontFamily != null &&
              !fonts.any((font) => font.family == style.fontFamily))
            DropdownMenuItem(
              value: style.fontFamily,
              child: const Text('原字体不可用'),
            ),
        ],
        onChanged: (value) => _set('fontFamily', value == '' ? null : value),
      ),
      const SizedBox(height: 14),
      ReaderStyleSlider(
        key: const ValueKey<String>('decoration-font-size'),
        label: '字号',
        value: style.fontSizeScale * 100,
        min: 75,
        max: 200,
        divisions: 125,
        digits: 0,
        suffix: '%',
        onChanged: (value) => _set('fontSizeScale', value / 100),
      ),
      DropdownButtonFormField<int>(
        key: const ValueKey<String>('decoration-weight'),
        icon: const AppIcon(AppGlyph.chevronDown),
        initialValue: style.fontWeight ?? 0,
        decoration: const InputDecoration(labelText: '字重'),
        items: [
          const DropdownMenuItem(value: 0, child: Text('跟随正文')),
          for (var weight = 100; weight <= 900; weight += 100)
            DropdownMenuItem(value: weight, child: Text('$weight')),
        ],
        onChanged: (value) => _set('fontWeight', value == 0 ? null : value),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        key: const ValueKey<String>('decoration-italic'),
        icon: const AppIcon(AppGlyph.chevronDown),
        initialValue: style.italic == null
            ? 'inherit'
            : style.italic!
            ? 'italic'
            : 'normal',
        decoration: const InputDecoration(labelText: '斜体'),
        items: const [
          DropdownMenuItem(value: 'inherit', child: Text('跟随正文')),
          DropdownMenuItem(value: 'normal', child: Text('正常')),
          DropdownMenuItem(value: 'italic', child: Text('斜体')),
        ],
        onChanged: (value) =>
            _set('italic', value == 'inherit' ? null : value == 'italic'),
      ),
      const SizedBox(height: 14),
      ReaderStyleSlider(
        label: '字距',
        value: style.letterSpacingEm,
        min: -0.05,
        max: 0.2,
        divisions: 25,
        digits: 2,
        suffix: ' em',
        onChanged: (value) => _set('letterSpacingEm', value),
      ),
      ReaderStyleColorField(
        label: '文字色',
        color: style.color,
        onChanged: (value) => _set('color', value),
      ),
    ],
  );
}
