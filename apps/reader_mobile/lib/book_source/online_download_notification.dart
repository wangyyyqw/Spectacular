import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 下载通知；未授予通知权限时仍正常下载。
class OnlineDownloadNotification {
  OnlineDownloadNotification(this.title);

  static const _channel = MethodChannel(
    'com.spectacular.reader_mobile/online_download',
  );
  static int _nextId = 2000;
  final String title;
  final int id = _nextId++;
  DateTime? _lastUpdate;

  Future<void> update(
    int completed,
    int total,
    String message, {
    bool done = false,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) return;
    final now = DateTime.now();
    if (!done &&
        _lastUpdate != null &&
        now.difference(_lastUpdate!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastUpdate = now;
    try {
      await _channel.invokeMethod<void>('update', {
        'id': id,
        'title': title,
        'completed': completed,
        'total': total,
        'message': message,
        'done': done,
      });
    } on PlatformException {
      // 通知不可用不阻断章节下载和数据落盘。
    } on MissingPluginException {
      // 桌面测试没有原生通知处理器。
    }
  }
}
