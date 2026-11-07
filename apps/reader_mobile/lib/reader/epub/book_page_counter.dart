import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:reader_ui/reader_session.dart';

/// 持久化一套完整布局键下已完成的章节页数，不保存页面或归档句柄。
abstract interface class BookPageCountStore {
  Future<Map<int, int>> load(String layoutKey);
  Future<void> save(String layoutKey, Map<int, int> counts);
}

/// 与阅读操作分离的逐章计页；实际分页仍由宿主的同一调度器执行。
class BookPageCounter {
  BookPageCounter({
    required int chapterCount,
    required bool Function(int) isMissing,
    required this.schedule,
    BookPageCountStore? store,
  }) : _isMissing = isMissing,
       // 保留公开 store 命名参数，重绑只能经过 bindStore。
       // ignore: prefer_initializing_formals
       _store = store,
       _spines = List<int>.unmodifiable([
         for (var spine = 0; spine < chapterCount; spine++)
           if (!isMissing(spine)) spine,
       ]) {
    _readableSpines = _spines.toSet();
    _state = ValueNotifier(_snapshot());
  }

  static const Duration _notificationInterval = Duration(milliseconds: 250);
  static const Duration _preemptedDelay = Duration(milliseconds: 16);
  final bool Function(int) _isMissing;
  final ChapterLoadHandle Function(int) schedule;
  BookPageCountStore? _store;
  final List<int> _spines;
  late final Set<int> _readableSpines;
  late final ValueNotifier<BookPageCountState> _state;
  final _recent = <String, Map<int, int>>{};
  final _clock = Stopwatch()..start();
  Map<int, int> _counts = {};
  final Set<int> _failed = {};
  String _layoutKey = '';
  int _completedPages = 0;
  int _generation = 0;
  int _storeRevision = 0;
  int _lastPublishedMs = -250;
  bool _cacheReady = false;
  bool _active = false;
  bool _closed = false;
  Future<void>? _restoreTask;
  Future<void>? _worker;
  Future<void> _saveQueue = Future.value();
  ChapterLoadHandle? _current;
  int? _currentSpine;
  Timer? _notificationTimer;
  Timer? _saveTimer;
  Object? _persistenceError;

  ValueListenable<BookPageCountState> get state => _state;

  /// 缓存读写失败仅影响下次复用，已经完成的实际计页仍然有效。
  Object? get persistenceError => _persistenceError;

  /// 晚绑定存储时重新恢复缓存，保留通知器及已完成的实测计数。
  Future<void> bindStore(BookPageCountStore store) {
    if (_closed) return Future.value();
    if (identical(_store, store)) return _restoreTask ?? Future.value();
    _saveNow();
    _store = store;
    _storeRevision += 1;
    _persistenceError = null;
    if (_layoutKey.isEmpty) return Future.value();
    _generation += 1;
    _current?.cancel();
    // 当前内存副本仍在 _counts 中；移除它才能真正读取新绑定的存储。
    _recent.remove(_layoutKey);
    _cacheReady = false;
    _notify(immediate: true);
    return _startRestore();
  }

  Future<void> useLayout(String layoutKey) {
    if (_closed) return Future.value();
    if (_layoutKey == layoutKey) return _restoreTask ?? Future.value();
    _saveNow();
    _rememberCurrent();
    _generation += 1;
    _current?.cancel();
    _layoutKey = layoutKey;
    _counts = {};
    _failed.clear();
    _completedPages = 0;
    _cacheReady = false;
    _notify(immediate: true);
    return _startRestore();
  }

  Future<void> _startRestore() {
    final layoutKey = _layoutKey;
    final generation = _generation;
    late final Future<void> task;
    task = _restore(layoutKey, generation).whenComplete(() {
      if (identical(_restoreTask, task)) _restoreTask = null;
    });
    _restoreTask = task;
    return task;
  }

  Future<void> _restore(String layoutKey, int generation) async {
    Map<int, int> cached = _recent.remove(layoutKey) ?? {};
    final target = _store;
    if (cached.isEmpty && target != null) {
      try {
        cached = await target.load(layoutKey);
      } catch (error) {
        if (_closed || generation != _generation) return;
        _persistenceError = error;
      }
    }
    if (_closed || generation != _generation) return;
    // 当前章可能在读缓存期间完成，实测结果必须覆盖持久化的旧值。
    _counts = {
      for (final entry in cached.entries)
        if (_readableSpines.contains(entry.key) && entry.value >= 0)
          entry.key: entry.value,
      ..._counts,
    };
    _completedPages = _counts.values.fold(0, (sum, count) => sum + count);
    _cacheReady = true;
    _rememberCurrent();
    _notify();
    _scheduleSave();
    _runIfNeeded();
  }

  /// 首屏和前台章节结果直接计入，后台不会为同一章重复排版。
  void recordChapter(String layoutKey, int spine, int pageCount) {
    if (_closed ||
        layoutKey != _layoutKey ||
        !_readableSpines.contains(spine)) {
      return;
    }
    if (pageCount < 0) {
      throw ArgumentError.value(pageCount, 'pageCount', '页数不能为负');
    }
    final previous = _counts[spine];
    _failed.remove(spine);
    _counts[spine] = pageCount;
    _completedPages += pageCount - (previous ?? 0);
    if (_currentSpine == spine) _current?.cancel();
    _rememberCurrent();
    _notify();
    _scheduleSave();
    _runIfNeeded();
  }

  void setActive(bool active) {
    if (_closed || active == _active) return;
    _active = active;
    if (active) {
      _failed.clear();
      _notify(immediate: true);
      _runIfNeeded();
    } else {
      _current?.cancel();
      _notify(immediate: true);
      _saveNow();
    }
  }

  bool get _complete =>
      _cacheReady && _counts.length == _spines.length && _failed.isEmpty;

  int? get _nextSpine {
    for (final spine in _spines) {
      if (!_counts.containsKey(spine) && !_failed.contains(spine)) return spine;
    }
    return null;
  }

  void _runIfNeeded() {
    if (_closed ||
        !_active ||
        !_cacheReady ||
        _worker != null ||
        _nextSpine == null) {
      return;
    }
    final generation = _generation;
    late final Future<void> task;
    // 先登记 worker 再开始遍历，避免缺章分支同步记录时重入另一个计页任务。
    task = Future<void>.microtask(() => _countChapters(generation))
        .whenComplete(() {
          if (identical(_worker, task)) _worker = null;
          _runIfNeeded();
        });
    _worker = task;
  }

  Future<void> _countChapters(int generation) async {
    while (!_closed && _active && generation == _generation) {
      final spine = _nextSpine;
      if (spine == null) return;
      if (_isMissing(spine)) {
        recordChapter(_layoutKey, spine, 0);
        continue;
      }
      await _countOne(spine, generation);
    }
  }

  Future<void> _countOne(int spine, int generation) async {
    ChapterLoadHandle? handle;
    try {
      _currentSpine = spine;
      handle = _current = schedule(spine);
      final pageCount = (await handle.result).length;
      if (!_closed && _active && generation == _generation) {
        recordChapter(_layoutKey, spine, pageCount);
      }
    } on ChapterLoadCancelled {
      if (!_closed && _active && generation == _generation) {
        // 前台抢占后不标记失败，也不在同一事件循环里忙于重新申请。
        await Future<void>.delayed(_preemptedDelay);
      }
    } catch (_) {
      if (!_closed &&
          generation == _generation &&
          !_counts.containsKey(spine)) {
        _failed.add(spine);
        _notify(immediate: _nextSpine == null);
      }
    } finally {
      if (identical(_current, handle)) {
        _current = null;
        _currentSpine = null;
      }
    }
  }

  BookPageCountState _snapshot() => BookPageCountState(
    layoutKey: _layoutKey,
    completedPages: _completedPages,
    completedChapters: _counts.length,
    totalChapters: _spines.length,
    status: _status,
    failedSpines: _failed,
  );

  BookPageCountStatus get _status {
    if (_complete) return BookPageCountStatus.complete;
    if (_layoutKey.isEmpty) return BookPageCountStatus.idle;
    if (!_active || _nextSpine == null && _failed.isNotEmpty) {
      return BookPageCountStatus.paused;
    }
    return BookPageCountStatus.running;
  }

  void _notify({bool immediate = false}) {
    if (_closed) return;
    final elapsed = _clock.elapsedMilliseconds - _lastPublishedMs;
    if (immediate || elapsed >= _notificationInterval.inMilliseconds) {
      _notificationTimer?.cancel();
      _notificationTimer = null;
      _publish();
    } else {
      _notificationTimer ??= Timer(
        Duration(milliseconds: _notificationInterval.inMilliseconds - elapsed),
        () {
          _notificationTimer = null;
          _publish();
        },
      );
    }
  }

  void _publish() {
    if (_closed) return;
    final next = _snapshot();
    if (_state.value == next) return;
    _lastPublishedMs = _clock.elapsedMilliseconds;
    _state.value = next;
  }

  void _rememberCurrent() {
    if (_layoutKey.isEmpty || !_cacheReady) return;
    _recent.remove(_layoutKey);
    _recent[_layoutKey] = Map<int, int>.of(_counts);
    while (_recent.length > 2) {
      _recent.remove(_recent.keys.first);
    }
  }

  void _scheduleSave() {
    if (_complete) {
      _saveNow();
      return;
    }
    if (_store == null || _closed) return;
    _saveTimer ??= Timer(_notificationInterval, () {
      _saveTimer = null;
      _saveNow();
    });
  }

  void _saveNow() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final target = _store;
    if (target == null || _layoutKey.isEmpty || !_cacheReady) return;
    final storeRevision = _storeRevision;
    final key = _layoutKey;
    final counts = Map<int, int>.unmodifiable(_counts);
    _saveQueue = _saveQueue.then((_) async {
      try {
        await target.save(key, counts);
      } catch (error) {
        if (storeRevision == _storeRevision) _persistenceError = error;
      }
    });
  }

  /// 等待已完成章节的计数落盘；失败可由 [persistenceError] 查询。
  Future<void> flush() async {
    // 缓存恢复后再合并前台结果，避免局部快照覆盖已经完成的章节。
    while (!_closed) {
      final restoring = _restoreTask;
      if (restoring == null) break;
      await restoring;
    }
    if (!_closed) _saveNow();
    await _saveQueue;
  }

  /// 停止任务并释放通知器；需要落盘时应先等待 [flush]。
  void close() {
    if (_closed) return;
    _active = false;
    _current?.cancel();
    _saveNow();
    _closed = true;
    _generation += 1;
    _notificationTimer?.cancel();
    _notificationTimer = null;
    _state.dispose();
    _clock.stop();
  }
}
