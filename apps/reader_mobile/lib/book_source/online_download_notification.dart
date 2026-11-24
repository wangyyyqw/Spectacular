import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 与 Windows 下载通知；通知不可用时仍正常下载。
class OnlineDownloadNotification {
  OnlineDownloadNotification(this.title) {
    _active[id] = this;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'cancel' && call.arguments is int) {
        _active[call.arguments]?.cancelled = true;
      }
    });
  }

  static const _channel = MethodChannel(
    'com.spectacular.reader_mobile/online_download',
  );
  static int _nextId = 2000;
  static final _active = <int, OnlineDownloadNotification>{};
  final String title;
  final int id = _nextId++;
  DateTime? _lastUpdate;
  bool cancelled = false;
  String? _lastPhase;
  Future<void> _pending = Future<void>.value();

  void dispose() => _active.remove(id);

  Future<void> update(
    int completed,
    int total,
    String message, {
    bool done = false,
  }) {
    _pending = _pending.then(
      (_) => _update(completed, total, message, done: done),
    );
    return _pending;
  }

  Future<void> _update(
    int completed,
    int total,
    String message, {
    bool done = false,
  }) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.windows)) {
      return;
    }
    final now = DateTime.now();
    final phase = total > 0 ? 'chapters' : message;
    if (!done &&
        phase == _lastPhase &&
        _lastUpdate != null &&
        now.difference(_lastUpdate!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastUpdate = now;
    _lastPhase = phase;
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
