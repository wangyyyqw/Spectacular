import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// 多看单页卷曲的片元着色器；起手前完成加载，在屏幕片元内反查纸面与法线。
class DuokanCurlShader {
  static const profileOffset = 17;
  static const profileCapacity = 24;
  static const shadowPlaneOffset = profileOffset + profileCapacity * 4;
  static const shadowEdgesOffset = shadowPlaneOffset + 3;

  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram>? _pending;

  static ui.FragmentProgram? get program => _program;

  static Future<ui.FragmentProgram> load() {
    final loaded = _program;
    return loaded == null ? _pending ??= _load() : Future.value(loaded);
  }

  static Future<ui.FragmentProgram> _load() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      const packaged = 'packages/reader_ui/shaders/duokan_curl.frag';
      final asset = manifest.listAssets().contains(packaged)
          ? packaged
          : 'shaders/duokan_curl.frag';
      return _program = await ui.FragmentProgram.fromAsset(asset);
    } finally {
      _pending = null;
    }
  }
}
