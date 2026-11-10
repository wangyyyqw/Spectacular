import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:reader_core/api.dart' show CancelToken;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/text/reader_text_overlay.dart';

import 'book_fonts.dart';

/// 字体与装饰准备完成后冻结的一次排版输入，不读取会话的可变设置。
class LayoutSnapshot {
  LayoutSnapshot({
    required this.spineIndex,
    required this.key,
    required this.contentVersion,
    required this.generation,
    required this.width,
    required this.height,
    required this.pageHeight,
    required this.topInset,
    required this.baseStyle,
    required this.overrides,
    required this.textOverlays,
    required this.fontDependency,
    required this.fonts,
    required this.fontFamilies,
    required this.trimTextEdges,
  });

  final int spineIndex;
  final String key;
  final String contentVersion;
  final int generation;
  final double width;
  final double height;
  final double pageHeight;
  final double topInset;
  final ComputedStyle baseStyle;
  final ReaderOverrides overrides;
  final ReaderTextOverlayResolver textOverlays;
  final String fontDependency;
  final BookFontView fonts;
  final Set<String> fontFamilies;
  final bool trimTextEdges;
  late final String overrideFingerprint = overrides.fingerprint;
  late final String typographyFingerprint = textOverlays.typographyFingerprint;
}

/// 每次工作片结束时核验取消和实际依赖；后台一次只占用一帧内的预算。
class LayoutBudget {
  LayoutBudget({required this._priority, required this.isCurrent});

  ChapterLayoutPriority _priority;
  final bool Function() isCurrent;
  final CancelToken token = CancelToken();
  final Completer<void> _cancelled = Completer<void>();
  Completer<void> _promotedToReading = Completer<void>();
  final Stopwatch _slice = Stopwatch()..start();
  int maxSliceMicroseconds = 0;
  int yieldCount = 0;

  ChapterLayoutPriority get priority => _priority;

  set priority(ChapterLayoutPriority next) {
    if (_priority == next) return;
    _priority = next;
    if (next == ChapterLayoutPriority.reading) {
      _promotedToReading.complete();
      _promotedToReading = Completer<void>();
    }
  }

  void promote(ChapterLayoutPriority next) {
    if (next.index < priority.index) priority = next;
  }

  void cancel() {
    token.cancel();
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void check() {
    if (token.isCancelled || !isCurrent()) {
      throw const ChapterLoadCancelled();
    }
  }

  Future<void> checkpoint({bool force = false}) {
    final waiting = checkpointIfNeeded(force: force);
    // 未超预算时同步完成，避免逐行检查产生成千上万个微任务。
    return waiting ?? SynchronousFuture<void>(null);
  }

  /// 密集纯数据遍历每步仍核验预算，未超限时不创建异步任务。
  Future<void>? checkpointIfNeeded({bool force = false}) {
    check();
    final elapsed = _slice.elapsedMicroseconds;
    final background = priority != ChapterLayoutPriority.reading;
    final limit = background ? 2000 : 4000;
    if (!force && elapsed < limit) return null;
    if (elapsed > maxSliceMicroseconds) maxSliceMicroseconds = elapsed;
    yieldCount += 1;
    return _yield(priority == ChapterLayoutPriority.background);
  }

  Future<void> _yield(bool waitForFrame) async {
    if (waitForFrame) {
      await Future.any([
        SchedulerBinding.instance.endOfFrame,
        _cancelled.future,
        _promotedToReading.future,
      ]);
    } else {
      // 邻章预取每片仍限 2ms，但不把数十个片段串成数十帧等待。
      // 零延迟事件给输入、动画和前台抢占机会，随后继续尚未完成的排版。
      await Future<void>.delayed(Duration.zero);
    }
    _slice.reset();
    check();
  }
}

typedef ChapterLayoutRunner = Future<List<PageContent>> Function(
  LayoutSnapshot snapshot,
  LayoutBudget budget,
  bool Function() retainResult,
);

/// 同一布局键共享计算，每个调用者独立取消；几何工作串行使用主 isolate。
class ChapterLayoutScheduler {
  ChapterLayoutScheduler({
    required this.run,
    required this.isCurrent,
    this.onFinished,
  });

  final ChapterLayoutRunner run;
  final bool Function(LayoutSnapshot) isCurrent;
  final void Function(LayoutSnapshot)? onFinished;
  final Map<String, _ChapterJob> _jobs = {};
  _ChapterJob? _running;
  bool _draining = false;
  bool _closed = false;

  bool contains(String key) => _jobs.containsKey(key);

  ChapterLoadHandle schedule(
    LayoutSnapshot snapshot, {
    required ChapterLayoutPriority priority,
    required bool retainResult,
  }) {
    final job = _jobs.putIfAbsent(snapshot.key, () => _ChapterJob(snapshot));
    final waiter = _ChapterWaiter(
      () => _removeIdle(job),
      priority: priority,
      retainResult: retainResult,
    );
    job.waiters.add(waiter);
    job.refreshPriority();
    if (_closed) {
      waiter.cancel();
    } else {
      _preempt(priority);
      unawaited(_drain());
    }
    return waiter;
  }

  void _preempt(ChapterLayoutPriority priority) {
    final running = _running;
    if (running == null ||
        running.budget?.token.isCancelled == true ||
        running.priority.index <= priority.index) {
      return;
    }
    // 低优先级请求可稍后重试，不能挡住当前阅读的最新请求。
    running.budget?.cancel();
    for (final waiter in running.waiters.toList()) {
      waiter.cancel();
    }
  }

  void cancelWhere(bool Function(LayoutSnapshot) matches) {
    for (final job in _jobs.values.toList()) {
      if (!matches(job.snapshot)) continue;
      for (final waiter in job.waiters.toList()) {
        waiter.cancel();
      }
    }
  }

  void _removeIdle(_ChapterJob job) {
    job.waiters.removeWhere((waiter) => waiter.isComplete);
    if (job.waiters.isNotEmpty) {
      job.refreshPriority();
      if (identical(job, _running)) {
        final next = _next();
        if (next != null) _preempt(next.priority);
      }
      return;
    }
    job.budget?.cancel();
    if (identical(_jobs[job.snapshot.key], job)) {
      _jobs.remove(job.snapshot.key);
    }
    if (job.budget == null) onFinished?.call(job.snapshot);
  }

  _ChapterJob? _next() {
    final pending = _jobs.values.where((job) => job != _running).toList();
    if (pending.isEmpty) return null;
    pending.sort((a, b) => a.priority.index.compareTo(b.priority.index));
    return pending.first;
  }

  Future<void> _drain() async {
    if (_draining || _closed) return;
    _draining = true;
    try {
      while (!_closed) {
        final job = _next();
        if (job == null) return;
        _running = job;
        await _runJob(job);
        _running = null;
      }
    } finally {
      _draining = false;
      _running = null;
    }
  }

  Future<void> _runJob(_ChapterJob job) async {
    final budget = job.budget = LayoutBudget(
      priority: job.priority,
      isCurrent: () =>
          job.waiters.any((waiter) => !waiter.isComplete) &&
          isCurrent(job.snapshot),
    );
    try {
      budget.check();
      final pages = await run(job.snapshot, budget, () => job.retainResult);
      budget.check();
      for (final waiter in job.waiters.toList()) {
        waiter.complete(pages);
      }
    } catch (error, stack) {
      for (final waiter in job.waiters.toList()) {
        waiter.completeError(error, stack);
      }
    } finally {
      if (identical(_jobs[job.snapshot.key], job)) {
        _jobs.remove(job.snapshot.key);
      }
      onFinished?.call(job.snapshot);
    }
  }

  void close() {
    _closed = true;
    cancelWhere((_) => true);
  }
}

class _ChapterJob {
  _ChapterJob(this.snapshot);

  final LayoutSnapshot snapshot;
  ChapterLayoutPriority priority = ChapterLayoutPriority.background;
  final Set<_ChapterWaiter> waiters = {};
  LayoutBudget? budget;

  bool get retainResult =>
      waiters.any((waiter) => !waiter.isComplete && waiter.retainResult);

  void refreshPriority() {
    priority = waiters
        .where((waiter) => !waiter.isComplete)
        .map((waiter) => waiter.priority)
        .reduce((first, next) => first.index < next.index ? first : next);
    budget?.priority = priority;
  }
}

class _ChapterWaiter implements ChapterLoadHandle {
  _ChapterWaiter(
    this.onCancel, {
    this.priority = ChapterLayoutPriority.reading,
    this.retainResult = false,
  }) {
    // 句柄可能在调用者 await 之前取消；保留原错误并避免未观察异常。
    unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  final void Function() onCancel;
  final ChapterLayoutPriority priority;
  final bool retainResult;
  final Completer<List<PageContent>> _completion = Completer();
  bool get isComplete => _completion.isCompleted;

  @override
  Future<List<PageContent>> get result => _completion.future;

  @override
  void cancel() {
    completeError(const ChapterLoadCancelled(), StackTrace.current);
    onCancel();
  }

  void complete(List<PageContent> pages) {
    if (!isComplete) _completion.complete(pages);
  }

  void completeError(Object error, StackTrace stack) {
    if (!isComplete) _completion.completeError(error, stack);
  }
}

/// 准备原文和字体的等待者也可立即取消，随后不会进入排版队列。
class PreparingChapterHandle implements ChapterLoadHandle {
  PreparingChapterHandle(
    Future<ChapterLoadHandle> Function(bool Function() isCancelled) prepare, {
    void Function()? onCancel,
  }) {
    _waiter = _ChapterWaiter(() {
      onCancel?.call();
      _scheduled?.cancel();
    });
    unawaited(_prepare(prepare));
  }

  late final _ChapterWaiter _waiter;
  ChapterLoadHandle? _scheduled;

  Future<void> _prepare(
    Future<ChapterLoadHandle> Function(bool Function() isCancelled) prepare,
  ) async {
    try {
      final scheduled = _scheduled = await prepare(() => _waiter.isComplete);
      if (_waiter.isComplete) scheduled.cancel();
      final pages = await scheduled.result;
      _waiter.complete(pages);
    } catch (error, stack) {
      _waiter.completeError(error, stack);
    }
  }

  @override
  Future<List<PageContent>> get result => _waiter.result;

  @override
  void cancel() {
    if (!_waiter.isComplete) _waiter.cancel();
  }
}
