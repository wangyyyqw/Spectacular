import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';

import '../theme/theme_color_settings.dart';
import '../theme/app_theme.dart';
import 'settings_choice_tile.dart';

/// 全局壁纸与阅读背景独立取色。
class ThemeColorSettingsPage extends StatefulWidget {
  const ThemeColorSettingsPage({super.key, required this.settings});

  final ThemeColorSettings settings;

  @override
  State<ThemeColorSettingsPage> createState() => _ThemeColorSettingsPageState();
}

class _ThemeColorSettingsPageState extends State<ThemeColorSettingsPage> {
  bool _saving = false;

  Future<void> _save(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('取色设置保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.settings,
    builder: (context, _) {
      final settings = widget.settings;
      final scope = AppThemeScope.maybeOf(context);
      final selectPreset = scope?.onPresetChanged;
      return ReaderSettingsScaffold(
        title: const Text('主题取色'),
        children: [
          if (scope != null && selectPreset != null) ...[
            ReaderSectionGroup(
              title: '软件配色',
              children: [
                SettingsChoiceTile<AppThemePreset>(
                  key: const ValueKey('theme-preset-setting'),
                  title: '配色方案',
                  current: scope.preset,
                  values: AppThemePreset.presets,
                  label: (preset) => preset.name,
                  optionKey: (preset) => ValueKey('theme-preset-${preset.id}'),
                  optionBuilder: (preset) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppGlyph.palette,
                        size: 18,
                        color: preset
                            .previewFor(Theme.of(context).brightness)
                            .accent,
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(preset.name)),
                    ],
                  ),
                  onChanged: _saving
                      ? null
                      : (preset) => _save(() => selectPreset(preset)),
                ),
              ],
            ),
            const SizedBox(height: ReaderUiTokens.spacingXl),
          ],
          ReaderSectionGroup(
            title: '动态配色',
            children: [
              ReaderSwitchListTile(
                key: const ValueKey('wallpaper-color-switch'),
                title: const Text('全局壁纸取色'),
                value: settings.wallpaperEnabled,
                onChanged:
                    _saving ||
                        !settings.initialized ||
                        !settings.wallpaperSupported
                    ? null
                    : (value) =>
                          _save(() => settings.setWallpaperEnabled(value)),
              ),
              ReaderSwitchListTile(
                key: const ValueKey('reader-background-color-switch'),
                title: const Text('阅读背景取色'),
                value: settings.readerBackgroundEnabled,
                onChanged: _saving || !settings.initialized
                    ? null
                    : (value) => _save(
                        () => settings.setReaderBackgroundEnabled(value),
                      ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
