import 'package:flutter/material.dart';

import '../theme/reader_ui_style.dart';

import '../reader_ui_diagnostics.dart';

import '../icons/app_icon.dart';
import '../theme/reader_frosted_popup.dart';
import 'annotation.dart';
import 'annotation_style_painter.dart';
import 'mark_settings.dart';
import 'text_value_dialog.dart';

/// 划线颜色选项。
class AnnotationColorOption {
  /// 创建颜色选项。
  const AnnotationColorOption(this.value, this.label);

  /// ARGB 颜色。
  final int value;

  /// 无障碍名称。
  final String label;
}

/// 划线样式选项。
class AnnotationStyleOption {
  /// 创建样式选项。
  const AnnotationStyleOption(this.value, this.label);

  /// 阅读标记样式。
  final ReaderAnnotationStyle value;

  /// 显示名称。
  final String label;
}

/// 新建想法、划线编辑和全局设置共用的外观控件。
class ReaderAnnotationAppearanceEditor extends StatelessWidget {
  /// 创建外观编辑器。
  const ReaderAnnotationAppearanceEditor({
    super.key,
    required this.color,
    required this.style,
    required this.opacity,
    required this.settings,
    required this.onColor,
    required this.onStyle,
    this.onOpacity,
    required this.onSettings,
    this.inkMode = false,
    this.showOpacity = true,
  });

  /// 五个快捷颜色。
  static const colors = <AnnotationColorOption>[
    AnnotationColorOption(defaultHighlightColor, '黄色'),
    AnnotationColorOption(0xFFA5D6A7, '绿色'),
    AnnotationColorOption(0xFF90CAF9, '蓝色'),
    AnnotationColorOption(0xFFF48FB1, '粉色'),
    AnnotationColorOption(0xFFFFB74D, '橙色'),
  ];

  /// 全量九种划线样式。
  static final styles = <AnnotationStyleOption>[
    for (final style in ReaderAnnotationStyle.values)
      AnnotationStyleOption(style, style.label),
  ];

  /// 当前颜色。
  final int color;

  /// 当前样式。
  final ReaderAnnotationStyle style;

  /// 当前透明度。
  final double opacity;

  /// 全书划线偏好草稿。
  final ReaderMarkSettings settings;

  /// 修改颜色。
  final ValueChanged<int> onColor;

  /// 修改样式。
  final ValueChanged<ReaderAnnotationStyle> onStyle;

  /// 修改透明度。
  final ValueChanged<double>? onOpacity;

  /// 修改全书偏好。
  final ValueChanged<ReaderMarkSettings> onSettings;

  /// 墨水屏隐藏无效的彩色控制。
  final bool inkMode;

  /// 全局设置不单独保存透明度时隐藏该控制。
  final bool showOpacity;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (inkMode)
        const Padding(
          key: ValueKey<String>('annotation-ink-color-hint'),
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('墨水屏模式：划线统一为黑色，背景与染色显示为实线'),
        )
      else ...[
        Text('划线颜色', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        _colors(context),
        if (showOpacity) _opacity(context),
        _styles(
          context,
          '背景',
          ReaderAnnotationStyle.values.take(1).toList()..addAll([
            ReaderAnnotationStyle.halfBackground,
            ReaderAnnotationStyle.tint,
          ]),
        ),
      ],
      _styles(
        context,
        '线条',
        ReaderAnnotationStyle.values
            .where(
              (item) => ![
                ReaderAnnotationStyle.background,
                ReaderAnnotationStyle.halfBackground,
                ReaderAnnotationStyle.tint,
              ].contains(item),
            )
            .toList(),
      ),
      if (!inkMode) ...[
        const SizedBox(height: 14),
        Text('线宽', style: Theme.of(context).textTheme.labelLarge),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in {1.0: '细', 1.8: '标准', 2.6: '粗'}.entries)
              ChoiceChip(
                key: ValueKey<String>('annotation-width-${entry.key}'),
                label: Text(entry.value),
                selected: settings.strokeWidth == entry.key,
                onSelected: (_) =>
                    onSettings(settings.copyWith(strokeWidth: entry.key)),
              ),
          ],
        ),
        SwitchListTile(
          key: const ValueKey<String>('annotation-join-lines'),
          contentPadding: EdgeInsets.zero,
          title: const Text('连续填充行距'),
          subtitle: const Text('仅连接同一文本块的整行底色'),
          value: settings.joinBackgroundLines,
          onChanged: (value) =>
              onSettings(settings.copyWith(joinBackgroundLines: value)),
        ),
      ],
    ],
  );

  Widget _colors(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final option in colors) _colorButton(context, option),
      for (final value in settings.customColors)
        _colorButton(
          context,
          AnnotationColorOption(value, '自定义颜色'),
          custom: true,
        ),
      IconButton(
        key: const ValueKey<String>('annotation-add-color'),
        tooltip: '添加自定义颜色（长按颜色可删除）',
        onPressed: () => _addColor(context),
        icon: const AppIcon(AppGlyph.addCircle),
      ),
    ],
  );

  Widget _colorButton(
    BuildContext context,
    AnnotationColorOption option, {
    bool custom = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: custom ? '自定义颜色，长按删除' : option.label,
      child: Semantics(
        label: option.label,
        selected: color == option.value,
        button: true,
        child: InkWell(
          key: ValueKey<String>(
            'annotation-color-0x${option.value.toRadixString(16).toUpperCase().padLeft(8, '0')}',
          ),
          onTap: () => onColor(option.value),
          onLongPress: custom
              ? () => onSettings(
                  settings.copyWith(
                    customColors: settings.customColors
                        .where((item) => item != option.value)
                        .toList(),
                  ),
                )
              : null,
          borderRadius: BorderRadius.circular(24),
          child: SizedBox.square(
            dimension: 44,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(option.value),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color == option.value
                        ? scheme.onSurface
                        : scheme.outlineVariant,
                    width: color == option.value ? 2 : 1,
                  ),
                ),
                child: color == option.value
                    ? AppIcon(
                        AppGlyph.check,
                        size: 19,
                        color: Color(option.value).computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addColor(BuildContext context) async {
    final selected = await showReaderColorDialog(context, initialColor: color);
    if (selected == null || !context.mounted) return;
    onColor(selected);
    if (settings.customColors.contains(selected)) return;
    if (settings.customColors.length >= 8) {
      if (context.mounted) {
        ReaderUiDiagnostics.record('annotation_color_limit_reached');
      }
      return;
    }
    onSettings(
      settings.copyWith(customColors: [...settings.customColors, selected]),
    );
  }

  Widget _opacity(BuildContext context) => Column(
    children: [
      Row(
        children: [
          const Text('透明度'),
          const Spacer(),
          Text('${(opacity * 100).round()}%'),
        ],
      ),
      Slider(
        key: const ValueKey<String>('annotation-opacity'),
        value: opacity.clamp(0.0, 1.0),
        divisions: 100,
        onChanged: onOpacity,
      ),
    ],
  );

  Widget _styles(
    BuildContext context,
    String label,
    List<ReaderAnnotationStyle> items,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                SizedBox(
                  width: (constraints.maxWidth - 16) / 3,
                  height: 60,
                  child: Material(
                    color: (inkMode ? style.inkStyle : style) == item
                        ? scheme.secondaryContainer
                        : scheme.surfaceContainerLow,
                    borderRadius: ReaderUiStyle.controlRadius,
                    child: InkWell(
                      key: ValueKey<String>('annotation-style-${item.name}'),
                      borderRadius: ReaderUiStyle.controlRadius,
                      onTap: () => onStyle(item),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(38, 14),
                            painter: _StyleSwatchPainter(
                              item,
                              Color(inkMode ? 0xFF000000 : color),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.label,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 以十六进制输入任意 ARGB 颜色。
Future<int?> showReaderColorDialog(
  BuildContext context, {
  required int initialColor,
}) async {
  final result = await showReaderDialog<String>(
    context: context,
    builder: (_) => ReaderTextValueDialog(
      title: '自定义颜色',
      label: 'ARGB 或 RGB 十六进制',
      initialValue: initialColor
          .toRadixString(16)
          .toUpperCase()
          .padLeft(8, '0'),
      inputKey: const ValueKey<String>('reader-color-input'),
      saveKey: const ValueKey<String>('reader-color-save'),
      confirmLabel: '使用颜色',
      maxLength: 9,
      validate: (value) =>
          RegExp(r'^#?(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(value)
          ? null
          : '请输入 6 或 8 位十六进制颜色',
    ),
  );
  if (result == null) return null;
  final text = result.replaceFirst('#', '');
  return int.parse(text.length == 6 ? 'FF$text' : text, radix: 16);
}

class _StyleSwatchPainter extends CustomPainter {
  _StyleSwatchPainter(this.style, this.color);
  final ReaderAnnotationStyle style;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (style == ReaderAnnotationStyle.tint) {
      final text = TextPainter(
        text: TextSpan(
          text: '文字',
          style: TextStyle(color: color, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset.zero);
      return;
    }
    AnnotationStylePainter.paint(
      canvas,
      Offset.zero & size,
      color: color,
      style: style,
    );
  }

  @override
  bool shouldRepaint(_StyleSwatchPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.color != color;
}
