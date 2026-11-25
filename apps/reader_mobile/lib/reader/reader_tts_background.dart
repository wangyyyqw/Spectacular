import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 通知栏、锁屏与耳机按钮复用同一套听书操作。
enum ReaderTtsMediaCommand { play, pause, stop }

/// Android 前台服务只负责系统播放会话，不另建语音引擎或文本游标。
class ReaderTtsBackgroundPlayback {
  ReaderTtsBackgroundPlayback({required this.bookTitle});

  static const channel = MethodChannel(
    'com.spectacular.reader_mobile/tts_playback',
  );

  final String bookTitle;
  Future<void> Function(ReaderTtsMediaCommand command)? onCommand;
  bool _active = false;
  Future<void> _transition = Future.value();
  ({String phase, String chapterTitle})? _published;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _serialize(Future<void> Function() action) {
    final operation = _transition.then((_) => action());
    _transition = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// 等待服务进入前台并取得音频焦点，再开始合成和朗读。
  Future<void> start() => !supported
      ? Future.value()
      : _serialize(() async {
          channel.setMethodCallHandler(_handleCommand);
          // 前台通知可能先于 start 回调出现，此时暂停和结束也必须生效。
          _active = true;
          try {
            await channel.invokeMethod<void>('start', {'bookTitle': bookTitle});
            _published = null;
          } catch (_) {
            _active = false;
            channel.setMethodCallHandler(null);
            rethrow;
          }
        });

  Future<void> _handleCommand(MethodCall call) async {
    if (!_active) return;
    final command = switch (call.method) {
      'play' => ReaderTtsMediaCommand.play,
      'pause' => ReaderTtsMediaCommand.pause,
      'stop' => ReaderTtsMediaCommand.stop,
      _ => throw MissingPluginException('不支持的听书操作：${call.method}'),
    };
    await onCommand?.call(command);
  }

  /// 字词高亮不反复刷新系统通知，只发布阶段和章节变化。
  Future<void> update({required String phase, required String chapterTitle}) {
    if (!supported) return Future.value();
    final next = (phase: phase, chapterTitle: chapterTitle);
    return _serialize(() async {
      if (!_active) return;
      if (phase != 'loading' && phase != 'playing' && phase != 'paused') {
        await _stopNative();
        return;
      }
      if (_published == next) return;
      await channel.invokeMethod<void>('update', {
        'phase': phase,
        'chapterTitle': chapterTitle,
      });
      _published = next;
    });
  }

  Future<void> activate() => !supported
      ? Future.value()
      : _serialize(() async {
          if (!_active) throw StateError('听书后台服务已结束，请重新开始朗读');
          await channel.invokeMethod<void>('activate');
        });

  Future<void> _stopNative() async {
    if (!_active) return;
    _active = false;
    _published = null;
    try {
      await channel.invokeMethod<void>('stop');
    } finally {
      channel.setMethodCallHandler(null);
    }
  }

  Future<void> stop() => !supported ? Future.value() : _serialize(_stopNative);

  Future<void> dispose() async {
    await stop();
    onCommand = null;
  }
}
