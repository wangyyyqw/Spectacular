import 'package:flutter/foundation.dart';

import '../storage/reading_session_store.dart';

/// 跟踪阅读页前台停留时间，应用进入后台时自动暂停。
class ReadingSessionTracker {
  /// 创建跟踪器。
  ReadingSessionTracker({
    required this.store,
    required this.bookId,
    DateTime Function()? now,
    this.minimumDuration = const Duration(seconds: 1),
  }) : _now = now ?? DateTime.now;

  /// 会话存储。
  final ReadingSessionStore store;

  /// 当前书籍 uuid。
  final String bookId;

  /// 小于该时长的片段不落库，避免生命周期抖动产生噪声。
  final Duration minimumDuration;

  final DateTime Function() _now;
  DateTime? _startedAt;
  Future<void> _pending = Future<void>.value();
  bool _finished = false;
  int _pageTurns = 0;
  int _charactersRead = 0;

  /// 开始或继续计时；重复调用不会重置起点。
  void start() {
    if (_finished || _startedAt != null) {
      return;
    }
    _startedAt = _now();
  }

  /// 记录翻页；[characters] 为离开页面时的非空白字符数。
  void recordPageTurn({int count = 1, int characters = 0}) {
    if (_finished || _startedAt == null || count <= 0) {
      return;
    }
    _pageTurns += count;
    if (characters > 0) {
      _charactersRead += characters;
    }
  }

  /// 暂停并提交当前片段。
  Future<void> pause() {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return _pending;
    }
    _startedAt = null;
    final endedAt = _now();
    final pageTurns = _pageTurns;
    final charactersRead = _charactersRead;
    _pageTurns = 0;
    _charactersRead = 0;
    if (endedAt.difference(startedAt) < minimumDuration) {
      return _pending;
    }
    _pending = _pending.then<void>((_) async {
      try {
        await store.add(
          bookId: bookId,
          startedAt: startedAt,
          endedAt: endedAt,
          pageTurns: pageTurns,
          charactersRead: charactersRead,
        );
      } catch (error) {
        // 就地处理本段写失败，避免错误链跳过下一段或逸出生命周期回调。
        debugPrint('阅读时长记录失败：$error');
      }
    });
    return _pending;
  }

  /// 结束跟踪；之后不会再次计时。
  Future<void> finish() async {
    if (_finished) {
      return;
    }
    _finished = true;
    await pause();
  }
}
