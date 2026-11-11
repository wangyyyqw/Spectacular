import 'dart:async';

import 'package:reader_core/source/chapter_source.dart';

/// 同键准备共享计算，每个等待者独立取消和提高优先级。
abstract interface class ChapterPreparationHandle<T>
    implements ReaderPreparationHandle<T> {
  void promote(ChapterLayoutPriority priority);
}

ChapterPreparationHandle<T> completedPreparation<T>(T value) =>
    _PreparationWaiter<T>(() {}, () {})..complete(value);

ChapterPreparationHandle<T> cancelledPreparation<T>() =>
    _PreparationWaiter<T>(() {}, () {})
      ..completeError(const ChapterLoadCancelled(), StackTrace.current);

ChapterPreparationHandle<T> mapPreparation<S, T>(
  ChapterPreparationHandle<S> handle,
  T Function(S) convert,
) => _MappedPreparationHandle(handle, convert);

Future<T> awaitPreparation<T>(
  ChapterPreparationHandle<T> handle, {
  Future<void>? cancelSignal,
}) async {
  var waiting = true;
  if (cancelSignal != null) {
    unawaited(
      cancelSignal.then<void>(
        (_) {
          if (waiting) handle.cancel();
        },
        onError: (Object _, StackTrace _) {
          if (waiting) handle.cancel();
        },
      ),
    );
  }
  try {
    return await handle.result;
  } finally {
    waiting = false;
  }
}

/// 仅传递一次准备的存活状态和优先级，不携带文档或阅读设置。
class PreparationTask {
  PreparationTask._(this._priority);

  ChapterLayoutPriority _priority;
  bool _active = true;
  final _ended = Completer<void>();
  final _children = <ChapterPreparationHandle<dynamic>>{};

  ChapterLayoutPriority get priority => _priority;
  bool get isActive => _active;
  Future<void> get cancelSignal => _ended.future;

  void check() {
    if (!_active) throw const ChapterLoadCancelled();
  }

  Future<T> wait<T>(ChapterPreparationHandle<T> handle) async {
    if (!_active) {
      handle.cancel();
      throw const ChapterLoadCancelled();
    }
    _children.add(handle);
    _setChildPriority(handle, _priority);
    try {
      return await waitFuture(handle.result);
    } finally {
      _children.remove(handle);
      handle.cancel();
    }
  }

  Future<T> waitFuture<T>(Future<T> future) async {
    check();
    final value = await Future.any<T>([
      future,
      cancelSignal.then<T>((_) => throw const ChapterLoadCancelled()),
    ]);
    check();
    return value;
  }

  void _setPriority(ChapterLayoutPriority next) {
    if (_priority == next) return;
    _priority = next;
    for (final child in _children.toList()) {
      _setChildPriority(child, next);
    }
  }

  void _setChildPriority(
    ChapterPreparationHandle<dynamic> child,
    ChapterLayoutPriority priority,
  ) {
    if (child is _PreparationWaiter) {
      child.setPriority(priority);
    } else if (child is _MappedPreparationHandle) {
      child.setPriority(priority);
    } else {
      child.promote(priority);
    }
  }

  void _finish() {
    if (!_active) return;
    _active = false;
    _ended.complete();
    for (final child in _children.toList()) {
      child.cancel();
    }
    _children.clear();
  }
}

/// 一次只运行一项准备；更高优先级请求可抢占不同键的旧任务。
class ChapterPreparationScheduler {
  final _jobs = <String, _PreparationJob<dynamic>>{};
  _PreparationJob<dynamic>? _running;
  bool _draining = false;
  bool _closed = false;
  Completer<void>? _idle;

  Future<void> get idle => _idle?.future ?? Future.value();

  ChapterPreparationHandle<T> schedule<T>(
    String key,
    Future<T> Function(PreparationTask task) run, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
  }) {
    if (_closed) return cancelledPreparation<T>();
    final job = _jobFor(key, run);
    late final _PreparationWaiter<T> waiter;
    waiter = _PreparationWaiter<T>(
      () => _removeWaiter(job),
      () => _reprioritize(job),
      priority: priority,
    );
    job.waiters.add(waiter);
    _reprioritize(job);
    _preempt(job);
    _runIfNeeded();
    return waiter;
  }

  _PreparationJob<T> _jobFor<T>(
    String key,
    Future<T> Function(PreparationTask task) run,
  ) {
    final existing = _jobs[key];
    if (existing != null) return existing as _PreparationJob<T>;
    final job = _PreparationJob<T>(key, run);
    _jobs[key] = job;
    return job;
  }

  void _reprioritize(_PreparationJob<dynamic> job) {
    if (job.waiters.isEmpty) return;
    job.priority = job.waiters
        .where((waiter) => !waiter.isComplete)
        .map((waiter) => waiter.priority)
        .reduce((first, next) => first.index < next.index ? first : next);
    job.task?._setPriority(job.priority);
    final next = _next();
    if (next != null) _preempt(next);
  }

  void _preempt(_PreparationJob<dynamic> next) {
    final running = _running;
    if (running == null ||
        identical(running, next) ||
        running.priority.index <= next.priority.index) {
      return;
    }
    _cancelJob(running);
  }

  void _removeWaiter(_PreparationJob<dynamic> job) {
    job.waiters.removeWhere((waiter) => waiter.isComplete);
    if (job.waiters.isNotEmpty) {
      _reprioritize(job);
      return;
    }
    job.task?._finish();
    if (identical(_jobs[job.key], job)) _jobs.remove(job.key);
  }

  void _cancelJob(_PreparationJob<dynamic> job) {
    for (final waiter in job.waiters.toList()) {
      waiter.cancel();
    }
  }

  _PreparationJob<dynamic>? _next() {
    _PreparationJob<dynamic>? next;
    for (final job in _jobs.values) {
      if (identical(job, _running) || job.waiters.isEmpty) continue;
      if (next == null || job.priority.index < next.priority.index) next = job;
    }
    return next;
  }

  void _runIfNeeded() {
    if (_closed || _draining || _jobs.isEmpty) return;
    _draining = true;
    _idle = Completer<void>();
    unawaited(Future<void>.microtask(_drain));
  }

  Future<void> _drain() async {
    try {
      while (!_closed) {
        final next = _next();
        if (next == null) break;
        _running = next;
        await _run(next);
        _running = null;
      }
    } finally {
      _running = null;
      _draining = false;
      _idle?.complete();
      _runIfNeeded();
    }
  }

  Future<void> _run(_PreparationJob<dynamic> job) async {
    final task = job.task = PreparationTask._(job.priority);
    try {
      task.check();
      final value = await job.run(task);
      task.check();
      for (final waiter in job.waiters.toList()) {
        waiter.complete(value);
      }
    } catch (error, stack) {
      for (final waiter in job.waiters.toList()) {
        waiter.completeError(error, stack);
      }
    } finally {
      task._finish();
      if (identical(_jobs[job.key], job)) _jobs.remove(job.key);
    }
  }

  void cancelAll() {
    for (final job in _jobs.values.toList()) {
      _cancelJob(job);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    cancelAll();
  }
}

class _PreparationJob<T> {
  _PreparationJob(this.key, this.run);
  final String key;
  final Future<T> Function(PreparationTask task) run;
  final waiters = <_PreparationWaiter<T>>{};
  PreparationTask? task;
  ChapterLayoutPriority priority = ChapterLayoutPriority.background;
}

class _PreparationWaiter<T> implements ChapterPreparationHandle<T> {
  _PreparationWaiter(
    this.onCancel,
    this.onPriorityChanged, {
    this.priority = ChapterLayoutPriority.reading,
  }) {
    unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  final void Function() onCancel;
  final void Function() onPriorityChanged;
  final _completion = Completer<T>();
  ChapterLayoutPriority priority;
  bool get isComplete => _completion.isCompleted;

  @override
  Future<T> get result => _completion.future;

  @override
  void cancel() {
    if (isComplete) return;
    completeError(const ChapterLoadCancelled(), StackTrace.current);
    onCancel();
  }

  @override
  void promote(ChapterLayoutPriority next) {
    if (next.index < priority.index) setPriority(next);
  }

  void setPriority(ChapterLayoutPriority next) {
    if (isComplete || priority == next) return;
    priority = next;
    onPriorityChanged();
  }

  void complete(T value) {
    if (!isComplete) _completion.complete(value);
  }

  void completeError(Object error, StackTrace stack) {
    if (!isComplete) _completion.completeError(error, stack);
  }
}

class _MappedPreparationHandle<S, T> implements ChapterPreparationHandle<T> {
  _MappedPreparationHandle(this.source, T Function(S) convert)
    : result = source.result.then(convert) {
    unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  final ChapterPreparationHandle<S> source;
  @override
  final Future<T> result;

  @override
  void cancel() => source.cancel();

  @override
  void promote(ChapterLayoutPriority priority) => source.promote(priority);

  void setPriority(ChapterLayoutPriority priority) {
    if (source is _PreparationWaiter) {
      (source as _PreparationWaiter).setPriority(priority);
    } else if (source is _MappedPreparationHandle) {
      (source as _MappedPreparationHandle).setPriority(priority);
    } else {
      source.promote(priority);
    }
  }
}
