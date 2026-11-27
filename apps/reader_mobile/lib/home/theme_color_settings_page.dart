import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';

import '../theme/theme_color_settings.dart';
import '../theme/app_theme.dart';
import 'settings_choice_tile.dart';

/// 全局壁纸与阅读背景独立取色。
class ThemeColorSettingsPage extends StatefulWidget {
  const ThemeColorSettingsPage({
    super.key,
    required this.settings,
    this.themeMode = ThemeMode.system,
    this.uiStyle = AppUiStyle.classic,
    this.onModeChanged,
    this.onStyleChanged,
  });

  final ThemeColorSettings settings;
  final ThemeMode themeMode;
  final AppUiStyle uiStyle;
  final Future<void> Function(ThemeMode)? onModeChanged;
  final Future<void> Function(AppUiStyle)? onStyleChanged;

  @override
  State<ThemeColorSettingsPage> createState() => _ThemeColorSettingsPageState();
}

class _ThemeColorSettingsPageState extends State<ThemeColorSettingsPage> {
  bool _saving = false;
  late ThemeMode _mode = widget.themeMode;
  late AppUiStyle _style = widget.uiStyle;

  Future<void> _save(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('主题外观保存失败，请重试')));
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
      final selectMode = scope?.onModeChanged ?? widget.onModeChanged;
      final selectStyle = scope?.onUiStyleChanged ?? widget.onStyleChanged;
      return ReaderSettingsScaffold(
        title: const Text('主题外观'),
        children: [
          if (selectMode != null ||
              selectStyle != null ||
              selectPreset != null) ...[
            ReaderSectionGroup(
              title: '界面设置',
              children: [
                if (selectMode != null)
                  SettingsChoiceTile<ThemeMode>(
                    title: '界面主题',
                    current: scope?.mode ?? _mode,
                    values: ThemeMode.values,
                    label: (mode) => switch (mode) {
                      ThemeMode.system => '跟随系统',
                      ThemeMode.light => '日间模式',
                      ThemeMode.dark => '夜间模式',
                    },
                    onChanged: _saving
                        ? null
                        : (mode) => _save(() async {
                            await selectMode(mode);
                            _mode = mode;
                          }),
                  ),
                if (selectStyle != null)
                  SettingsChoiceTile<AppUiStyle>(
                    key: const ValueKey('app-ui-style-setting'),
                    title: '界面样式',
                    current: scope?.uiStyle ?? _style,
                    values: AppUiStyle.values,
                    label: (style) => switch (style) {
                      AppUiStyle.classic => '经典',
                      AppUiStyle.material3 => 'Material 3',
                    },
                    onChanged: _saving
                        ? null
                        : (style) => _save(() async {
                            await selectStyle(style);
                            _style = style;
                          }),
                  ),
                if (scope != null && selectPreset != null)
                  SettingsChoiceTile<AppThemePreset>(
                    key: const ValueKey('theme-preset-setting'),
                    title: '配色方案',
                    current: scope.preset,
                    values: AppThemePreset.presets,
                    label: (preset) => preset.name,
                    optionKey: (preset) =>
                        ValueKey('theme-preset-${preset.id}'),
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
