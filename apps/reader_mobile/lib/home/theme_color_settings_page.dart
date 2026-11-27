import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';

import '../theme/theme_color_settings.dart';
import '../theme/app_theme.dart';

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
              footer: '开启全局壁纸取色后，优先使用壁纸颜色；关闭后恢复所选方案。书籍正文配色不受影响。',
              children: [
                ListTile(
                  key: const ValueKey('theme-preset-setting'),
                  leading: const AppIcon(AppGlyph.palette),
                  title: const Text('配色方案'),
                  subtitle: Text(scope.preset.name),
                  trailing: const AppIcon(AppGlyph.chevronRight),
                  onTap: _saving
                      ? null
                      : () async {
                          final brightness = Theme.of(context).brightness;
                          final preset =
                              await showReaderActionSheet<AppThemePreset>(
                                context: context,
                                title: '配色方案',
                                actions: [
                                  for (final preset in AppThemePreset.presets)
                                    ReaderSheetAction(
                                      key: ValueKey(
                                        'theme-preset-${preset.id}',
                                      ),
                                      value: preset,
                                      title: preset.name,
                                      subtitle: preset.subtitle,
                                      selected: preset == scope.preset,
                                      icon: AppIcon(
                                        AppGlyph.palette,
                                        color: preset
                                            .previewFor(brightness)
                                            .accent,
                                      ),
                                    ),
                                ],
                              );
                          if (mounted && preset != null) {
                            await _save(() => selectPreset(preset));
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: ReaderUiTokens.spacingXl),
          ],
          ReaderSectionGroup(
            title: '动态配色',
            footer: '壁纸取色应用于全局界面；阅读背景取色只调整阅读内菜单与弹层，保留正文配色。',
            children: [
              ReaderSwitchListTile(
                key: const ValueKey('wallpaper-color-switch'),
                title: const Text('全局壁纸取色'),
                subtitle: Text(
                  !settings.initialized
                      ? '正在读取系统颜色'
                      : settings.wallpaperSupported
                      ? '跟随系统壁纸颜色，应用于全局界面'
                      : '需要 Android 12 或更高版本的系统动态颜色',
                ),
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
                subtitle: const Text('根据阅读背景颜色或图片调整菜单与弹层配色，保留正文配色'),
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
