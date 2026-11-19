import 'package:flutter/material.dart';

import '../annotations/annotation.dart';
import '../annotations/annotation_appearance_editor.dart';
import '../icons/app_icon.dart';
import 'decoration_painter.dart';
import 'decoration_highlight.dart';
import 'style_controls.dart';

class ReaderDecorationHighlightEditor extends StatelessWidget {
  const ReaderDecorationHighlightEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.inkMode = false,
  });

  final ReaderDecorationHighlight? value;
  final ValueChanged<ReaderDecorationHighlight?> onChanged;
  final bool inkMode;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _styles(context),
      if (inkMode)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('墨水屏模式：背景与染色显示为黑色实线。'),
        ),
      if (value case final highlight?) ...[
        if (!inkMode) ...[
          const SizedBox(height: 12),
          _colors(context, highlight),
          ReaderStyleColorField(
            label: '自定义颜色',
            color: highlight.color,
            allowClear: false,
            onChanged: (color) =>
                onChanged(highlight.withValues({'color': color})),
          ),
          ReaderStyleSlider(
            key: const ValueKey('decoration-highlight-opacity'),
            label: '高亮透明度',
            value: highlight.effectiveOpacity,
            min: 0,
            max: 1,
            divisions: 100,
            digits: 2,
            onChanged: (opacity) =>
                onChanged(highlight.withValues({'opacity': opacity})),
          ),
          if ([
            ReaderAnnotationStyle.background,
            ReaderAnnotationStyle.halfBackground,
          ].contains(highlight.style))
            ReaderStyleSlider(
              key: const ValueKey('decoration-highlight-radius'),
              label: '高亮圆角',
              value: highlight.borderRadius,
              min: 0,
              max: 12,
              divisions: 12,
              digits: 0,
              suffix: ' dp',
              onChanged: (radius) =>
                  onChanged(highlight.withValues({'borderRadius': radius})),
            ),
        ],
        if (!inkMode &&
            ![
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
        if (!inkMode && highlight.style == ReaderAnnotationStyle.background)
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

  Widget _styles(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= 270 &&
              MediaQuery.textScalerOf(context).scale(12) <= 18
          ? 3
          : 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final style in [null, ...ReaderAnnotationStyle.values])
            SizedBox(
              width: (constraints.maxWidth - (columns - 1) * 8) / columns,
              child: _styleButton(context, style),
            ),
        ],
      );
    },
  );

  Widget _styleButton(BuildContext context, ReaderAnnotationStyle? style) {
    final scheme = Theme.of(context).colorScheme;
    final selected = value?.style == style;
    return Semantics(
      label: style?.label ?? '不设置高亮',
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          key: ValueKey('decoration-highlight-style-${style?.name ?? 'none'}'),
          borderRadius: BorderRadius.circular(4),
          onTap: () => onChanged(
            style == null
                ? null
                : (value ?? const ReaderDecorationHighlight()).withValues({
                    'style': style.name,
                  }),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              children: [
                if (style == null)
                  const AppIcon(AppGlyph.close, size: 22)
                else
                  CustomPaint(
                    size: const Size(52, 22),
                    painter: _HighlightSwatchPainter(
                      (value ?? const ReaderDecorationHighlight()).withValues({
                        'style': style.name,
                      }),
                      scheme.onSurface,
                      inkMode,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  style?.label ?? '不设置',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _colors(BuildContext context, ReaderDecorationHighlight highlight) =>
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final color in ReaderAnnotationAppearanceEditor.colors)
            IconButton(
              key: ValueKey('decoration-highlight-color-${color.value}'),
              tooltip: color.label,
              isSelected: highlight.color == color.value,
              onPressed: () =>
                  onChanged(highlight.withValues({'color': color.value})),
              icon: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Color(color.value),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: highlight.color == color.value
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: highlight.color == color.value ? 2 : 1,
                  ),
                ),
                child: highlight.color == color.value
                    ? const AppIcon(
                        AppGlyph.check,
                        size: 18,
                        color: Colors.black,
                      )
                    : null,
              ),
            ),
        ],
      );
}

class _HighlightSwatchPainter extends CustomPainter {
  _HighlightSwatchPainter(this.highlight, this.textColor, this.inkMode);
  final ReaderDecorationHighlight highlight;
  final Color textColor;
  final bool inkMode;

  @override
  void paint(Canvas canvas, Size size) {
    final text = TextPainter(
      text: TextSpan(
        text: '文字',
        style: TextStyle(
          fontSize: 12,
          color: !inkMode && highlight.style == ReaderAnnotationStyle.tint
              ? Color(highlight.color).withValues(
                  alpha: Color(highlight.color).a * highlight.effectiveOpacity,
                )
              : textColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final origin = Offset((size.width - text.width) / 2, 2);
    final rect = origin & text.size;
    ReaderDecorationPainter.paintHighlight(
      canvas,
      rect,
      highlight,
      foreground: false,
      inkMode: inkMode,
    );
    text.paint(canvas, origin);
    ReaderDecorationPainter.paintHighlight(
      canvas,
      rect,
      highlight,
      foreground: true,
      inkMode: inkMode,
    );
    text.dispose();
  }

  @override
  bool shouldRepaint(_HighlightSwatchPainter oldDelegate) =>
      oldDelegate.highlight != highlight ||
      oldDelegate.textColor != textColor ||
      oldDelegate.inkMode != inkMode;
}
