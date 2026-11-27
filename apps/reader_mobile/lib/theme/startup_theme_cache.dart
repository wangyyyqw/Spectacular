import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// 原生启动层与 Flutter 首帧共享的上次配色，不包含书库数据。
class StartupThemeCache {
  const StartupThemeCache({
    required this.wallpaperEnabled,
    required this.mode,
    this.seed,
    this.preset = AppThemePreset.clearBlue,
  });

  static const channel = OptionalMethodChannel(
    'com.spectacular.reader_mobile/theme_color',
  );

  final bool wallpaperEnabled;
  final ThemeMode mode;
  final Color? seed;
  final AppThemePreset preset;

  static Future<StartupThemeCache?> read() async {
    try {
      final values = await channel.invokeMapMethod<String, Object?>(
        'getStartupTheme',
      );
      if (values == null) return null;
      final seed = values['seed'];
      return StartupThemeCache(
        preset: AppThemePreset.byId(values['preset'] as String?),
        wallpaperEnabled: values['wallpaperEnabled'] == true,
        mode: ThemeMode.values.firstWhere(
          (mode) => mode.name == values['mode'],
          orElse: () => ThemeMode.system,
        ),
        seed: seed is int ? Color(seed) : null,
      );
    } on PlatformException {
      return null;
    }
  }

  Future<void> save() async {
    ThemeData theme(Brightness brightness) => buildAppTheme(
      preset: preset,
      brightness: brightness,
      colorScheme: wallpaperEnabled && seed != null
          ? ColorScheme.fromSeed(seedColor: seed!, brightness: brightness)
          : null,
    );
    final light = theme(Brightness.light);
    final dark = theme(Brightness.dark);
    try {
      await channel.invokeMethod<void>('cacheStartupTheme', {
        'preset': preset.id,
        'wallpaperEnabled': wallpaperEnabled,
        'mode': mode.name,
        'seed': seed?.toARGB32(),
        'lightBackground': light.scaffoldBackgroundColor.toARGB32(),
        'darkBackground': dark.scaffoldBackgroundColor.toARGB32(),
        'lightForeground': light.colorScheme.onSurface.toARGB32(),
        'darkForeground': dark.colorScheme.onSurface.toARGB32(),
      });
    } on PlatformException {
      // 不支持原生缓存的平台仍使用书库中的偏好和种子缓存。
    }
  }
}
