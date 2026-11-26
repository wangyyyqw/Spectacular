import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

import '../theme/app_theme.dart';

/// 软件配色方案选择抽屉：两列色板预览卡，点击后实时切换并保存。
class ThemePresetPickerSheet extends StatelessWidget {
  const ThemePresetPickerSheet({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final AppThemePreset selected;
  final ValueChanged<AppThemePreset> onSelect;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ReaderSheetForm(
      title: const Text('配色方案'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 280 ? 2 : 1;
          final gap = 12.0;
          final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '应用界面、弹层与阅读菜单共用所选配色，书籍正文主题独立设置。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: <Widget>[
                  for (final preset in AppThemePreset.presets)
                    SizedBox(
                      width: itemWidth,
                      child: _PresetCard(
                        preset: preset,
                        brightness: brightness,
                        selected: preset.id == selected.id,
                        onTap: () => onSelect(preset),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          );
        },
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.brightness,
    required this.selected,
    required this.onTap,
  });

  final AppThemePreset preset;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final preview = preset.previewFor(brightness);
    final previewScheme = preset.colorsFor(brightness);
    return Semantics(
      button: true,
      selected: selected,
      label: '${preset.name}配色方案',
      child: Material(
        key: ValueKey<String>('theme-preset-${preset.id}'),
        color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: ReaderUiStyle.controlRadius,
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SwatchPreview(
                  canvas: preview.canvas,
                  surface: preview.surface,
                  accent: preview.accent,
                  border: previewScheme.outlineVariant,
                  textHint: previewScheme.onSurface.withValues(alpha: .35),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        preset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: selected
                              ? colors.onPrimaryContainer
                              : colors.onSurface,
                        ),
                      ),
                    ),
                    if (selected)
                      AppIcon(
                        AppGlyph.check,
                        size: 16,
                        color: colors.onPrimaryContainer,
                      ),
                  ],
                ),
                if (preset.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    preset.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: selected
                          ? colors.onPrimaryContainer.withValues(alpha: .8)
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwatchPreview extends StatelessWidget {
  const _SwatchPreview({
    required this.canvas,
    required this.surface,
    required this.accent,
    required this.border,
    required this.textHint,
  });

  final Color canvas;
  final Color surface;
  final Color accent;
  final Color border;
  final Color textHint;

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: canvas,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: border),
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 4,
                  width: 36,
                  decoration: BoxDecoration(
                    color: textHint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 3,
                  width: 24,
                  decoration: BoxDecoration(
                    color: border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
