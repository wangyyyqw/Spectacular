import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/library_store.dart';
import 'startup_theme_cache.dart';

/// 壁纸与阅读背景取色分别保存，设备不支持动态颜色时沿用默认主题。
class ThemeColorSettings extends ChangeNotifier {
  ThemeColorSettings(this.library, {StartupThemeCache? startupTheme})
    : wallpaperEnabled = startupTheme?.wallpaperEnabled ?? false,
      wallpaperSeed = startupTheme?.seed;

  static const wallpaperKey = 'app.wallpaperColor';
  static const readerBackgroundKey = 'reader.backgroundColor';
  static const wallpaperSeedKey = 'app.wallpaperSeed';
  static const _channel = OptionalMethodChannel(
    'com.spectacular.reader_mobile/theme_color',
  );

  final LibraryStore library;
  bool wallpaperEnabled;
  bool readerBackgroundEnabled = false;
  Color? wallpaperSeed;
  bool initialized = false;
  bool _disposed = false;
  Future<void>? _refreshing;

  bool get wallpaperSupported => wallpaperSeed != null;

  Future<void> initialize() async {
    wallpaperEnabled = await library.getSetting(wallpaperKey) == 'true';
    readerBackgroundEnabled =
        await library.getSetting(readerBackgroundKey) == 'true';
    final cached = int.tryParse(
      await library.getSetting(wallpaperSeedKey) ?? '',
    );
    if (cached != null) wallpaperSeed = Color(cached);
    // 已有缓存时立即恢复界面，系统取色随后校正，不阻塞开屏。
    final hasCache = wallpaperSeed != null;
    if (!hasCache) await refreshWallpaper();
    if (_disposed) return;
    initialized = true;
    notifyListeners();
    if (hasCache) unawaited(refreshWallpaper());
  }

  /// 回到前台时重新获取系统颜色，无需读取壁纸文件或申请相册权限。
  Future<void> refreshWallpaper() => _refreshing ??= _refreshWallpaper()
      .whenComplete(() => _refreshing = null);

  Future<void> _refreshWallpaper() async {
    Color? seed;
    try {
      final value = await _channel.invokeMethod<int>('getWallpaperSeed');
      if (value != null) seed = Color(value);
    } on PlatformException {
      // 临时获取失败时保留上次结果；系统明确返回空值时清除缓存。
      return;
    }
    if (_disposed) return;
    await library.setSetting(wallpaperSeedKey, '${seed?.toARGB32() ?? ''}');
    if (_disposed) return;
    if (wallpaperSeed != seed) {
      wallpaperSeed = seed;
      notifyListeners();
    }
  }

  Future<void> setWallpaperEnabled(bool value) async {
    if (value && !wallpaperSupported) return;
    await library.setSetting(wallpaperKey, '$value');
    wallpaperEnabled = value;
    notifyListeners();
  }

  Future<void> setReaderBackgroundEnabled(bool value) async {
    await library.setSetting(readerBackgroundKey, '$value');
    readerBackgroundEnabled = value;
    notifyListeners();
  }

  ColorScheme? wallpaperScheme(Brightness brightness) =>
      wallpaperEnabled && wallpaperSeed != null
      ? ColorScheme.fromSeed(seedColor: wallpaperSeed!, brightness: brightness)
      : null;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 让设置页与导航栈中的阅读页共享两个独立取色选项。
class ThemeColorScope extends InheritedNotifier<ThemeColorSettings> {
  const ThemeColorScope({
    super.key,
    required ThemeColorSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static ThemeColorSettings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeColorScope>()?.notifier;
}
