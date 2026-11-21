import '../diagnostics/reader_log.dart';
import '../storage/reading_session_store.dart';

/// 跟踪阅读页前台停留时间，应用进入后台时自动暂停。
class ReadingSessionTracker {
  /// 创建跟踪器。
  ReadingSessionTracker({
    required ReadingSessionStore store,
    required this.bookId,
    DateTime Function()? now,
  }) : store = store is DriftReadingSessionStore
           ? store.bindBook(bookId)
           : store,
       _now = now ?? DateTime.now;

  /// 会话存储。
  final ReadingSessionStore store;

  /// 当前书籍 uuid。
  final String bookId;

  final DateTime Function() _now;
  _ReadingSegment? _active;
  final _sessionStarts = <int>{};
  final _unsaved = <_ReadingSegment, ReadingSession>{};
  Future<void> _pending = Future<void>.value();
  bool _finished = false;
  Duration _completedDuration = Duration.zero;

  /// 本次打开期间的有效前台时长，包含已暂停片段和正在计时的片段。
  Duration get elapsed {
    final startedAt = _active?.startedAt;
    final active = startedAt == null
        ? Duration.zero
        : _now().difference(startedAt);
    return _completedDuration + (active.isNegative ? Duration.zero : active);
  }

  /// 开始或继续计时；重复调用不会重置起点。
  void start() {
    if (_finished || _active != null) {
      return;
    }
    final active = _ReadingSegment(_now());
    _active = active;
    _sessionStarts.add(active.startedAt.millisecondsSinceEpoch);
  }

  /// 历史基线加载晚于定时保存时，按本次片段身份排除重复累计。
  bool ownsSession(ReadingSession session) =>
      session.bookId == bookId &&
      _sessionStarts.contains(session.startedAt.millisecondsSinceEpoch);

  /// 记录翻页；[characters] 为离开页面时的非空白字符数。
  void recordPageTurn({int count = 1, int characters = 0}) {
    final active = _active;
    if (_finished || active == null || count <= 0) {
      return;
    }
    active.pageTurns += count;
    if (characters > 0) {
      active.charactersRead += characters;
    }
  }

  /// 阅读中原位保存当前片段；后台不计时，失败片段留待下一次重试。
  Future<void> checkpoint() {
    final active = _active;
    if (active != null && store is ReadingSessionCheckpointStore) {
      _queue(active, _now());
    }
    return _savePending();
  }

  /// 暂停并提交当前片段。
  Future<void> pause() {
    final active = _active;
    if (active == null) {
      return _savePending();
    }
    _active = null;
    final endedAt = _now();
    final duration = endedAt.difference(active.startedAt);
    if (duration > Duration.zero) {
      _completedDuration += duration;
      _queue(active, endedAt);
    }
    return _savePending();
  }

  void _queue(_ReadingSegment active, DateTime endedAt) {
    final duration = endedAt.difference(active.startedAt);
    if (duration <= Duration.zero) return;
    _unsaved[active] = ReadingSession(
      bookId: bookId,
      startedAt: active.startedAt,
      endedAt: endedAt,
      duration: duration,
      pageTurns: active.pageTurns,
      charactersRead: active.charactersRead,
    );
  }

  Future<void> _savePending() {
    _pending = _pending.then<void>((_) async {
      while (_unsaved.isNotEmpty) {
        final active = _unsaved.keys.first;
        final snapshot = _unsaved[active]!;
        try {
          await _save(active, snapshot);
          // 写入期间可能到达更新的快照，不能把尚未落盘的尾段一起删除。
          if (identical(_unsaved[active], snapshot)) _unsaved.remove(active);
        } catch (error) {
          await ReaderLog.instance.log(
            'reading_session_save_error',
            fields: {
              'status': 'failed',
              if (error is ReadingSessionSaveException) 'reason': error.reason,
              'error': error,
            },
          );
          break;
        }
      }
    });
    return _pending;
  }

  Future<void> _save(_ReadingSegment active, ReadingSession snapshot) async {
    if (store case ReadingSessionCheckpointStore checkpoints) {
      active.sessionId = await checkpoints.save(
        snapshot,
        sessionId: active.sessionId,
      );
    } else {
      await store.add(
        bookId: snapshot.bookId,
        startedAt: snapshot.startedAt,
        endedAt: snapshot.endedAt,
        pageTurns: snapshot.pageTurns,
        charactersRead: snapshot.charactersRead,
      );
    }
  }

  /// 结束跟踪；之后不会再次计时。
  Future<void> finish() async {
    if (_finished) {
      await _savePending();
      return;
    }
    _finished = true;
    await pause();
    if (_unsaved.isNotEmpty) await _savePending();
  }
}

/// 一次连续前台阅读的身份和累计计数，快照更新沿用同一数据库记录。
class _ReadingSegment {
  _ReadingSegment(this.startedAt);

  final DateTime startedAt;
  int? sessionId;
  int pageTurns = 0;
  int charactersRead = 0;
}
