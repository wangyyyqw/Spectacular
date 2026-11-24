import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../theme/theme_color_settings.dart';

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
      return ReaderSheetForm(
        title: const Text('主题取色'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                child: Column(
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
                          : (value) => _save(
                              () => settings.setWallpaperEnabled(value),
                            ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
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
              ),
            ],
          ),
        ),
      );
    },
  );
}
