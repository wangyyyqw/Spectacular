import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/library_store.dart';

/// 壁纸与阅读背景取色分别保存，设备不支持动态颜色时沿用默认主题。
class ThemeColorSettings extends ChangeNotifier {
  ThemeColorSettings(this.library);

  static const wallpaperKey = 'app.wallpaperColor';
  static const readerBackgroundKey = 'reader.backgroundColor';
  static const _channel = OptionalMethodChannel(
    'com.spectacular.reader_mobile/theme_color',
  );

  final LibraryStore library;
  bool wallpaperEnabled = false;
  bool readerBackgroundEnabled = false;
  Color? wallpaperSeed;
  bool initialized = false;

  bool get wallpaperSupported => wallpaperSeed != null;

  Future<void> initialize() async {
    wallpaperEnabled = await library.getSetting(wallpaperKey) == 'true';
    readerBackgroundEnabled =
        await library.getSetting(readerBackgroundKey) == 'true';
    await refreshWallpaper();
    initialized = true;
    notifyListeners();
  }

  /// 回到前台时重新获取系统颜色，无需读取壁纸文件或申请相册权限。
  Future<void> refreshWallpaper() async {
    Color? seed;
    try {
      final value = await _channel.invokeMethod<int>('getWallpaperSeed');
      if (value != null) seed = Color(value);
    } on PlatformException {
      // 系统未提供动态颜色时使用默认配色。
    }
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
