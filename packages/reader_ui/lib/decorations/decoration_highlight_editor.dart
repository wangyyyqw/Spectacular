import 'package:flutter/material.dart';

import '../annotations/annotation.dart';
import '../icons/app_icon.dart';
import 'decoration_highlight.dart';
import 'style_controls.dart';

class ReaderDecorationHighlightEditor extends StatelessWidget {
  const ReaderDecorationHighlightEditor({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ReaderDecorationHighlight? value;
  final ValueChanged<ReaderDecorationHighlight?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<ReaderAnnotationStyle?>(
        key: ValueKey('decoration-highlight-style-${value?.style.name}'),
        initialValue: value?.style,
        isExpanded: true,
        icon: const AppIcon(AppGlyph.chevronDown),
        decoration: const InputDecoration(labelText: '高亮样式'),
        items: [
          const DropdownMenuItem(value: null, child: Text('不设置')),
          for (final style in ReaderAnnotationStyle.values)
            DropdownMenuItem(value: style, child: Text(style.label)),
        ],
        onChanged: (style) => onChanged(
          style == null
              ? null
              : (value ?? const ReaderDecorationHighlight()).withValues({
                  'style': style.name,
                }),
        ),
      ),
      if (value case final highlight?) ...[
        ReaderStyleColorField(
          label: '高亮颜色',
          color: highlight.color,
          allowClear: false,
          onChanged: (color) =>
              onChanged(highlight.withValues({'color': color})),
        ),
        ReaderStyleSlider(
          label: '高亮透明度',
          value: highlight.effectiveOpacity,
          min: 0,
          max: 1,
          divisions: 100,
          digits: 2,
          onChanged: (opacity) =>
              onChanged(highlight.withValues({'opacity': opacity})),
        ),
        if (![
          ReaderAnnotationStyle.background,
          ReaderAnnotationStyle.halfBackground,
          ReaderAnnotationStyle.tint,
        ].contains(highlight.style))
          ReaderStyleSlider(
            label: '高亮线宽',
            value: highlight.strokeWidth,
            min: 0.5,
            max: 6,
            divisions: 11,
            suffix: ' dp',
            onChanged: (width) =>
                onChanged(highlight.withValues({'strokeWidth': width})),
          ),
        if (highlight.style == ReaderAnnotationStyle.background)
          SwitchListTile(
            key: const ValueKey('decoration-highlight-join-lines'),
            contentPadding: EdgeInsets.zero,
            title: const Text('跨行背景连块'),
            subtitle: const Text('只连接同一段落内的连续高亮，不跨段或跨页'),
            value: highlight.joinLines,
            onChanged: (join) =>
                onChanged(highlight.withValues({'joinLines': join})),
          ),
      ],
      const SizedBox(height: 12),
    ],
  );
}
