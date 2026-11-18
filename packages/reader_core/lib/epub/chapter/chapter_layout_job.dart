import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:reader_core/api.dart' show CancelToken;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';
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
    ContentSideInsets? sideInsets,
    required this.baseStyle,
    required this.overrides,
    required this.textOverlays,
    required this.fontDependency,
    required this.fonts,
    required this.fontFamilies,
    this.fontFaces = const [],
    required this.trimTextEdges,
  }) : sideInsets =
           sideInsets ??
           (
             left: overrides.padding?.left ?? 0,
             right: overrides.padding?.right ?? 0,
           );

  final int spineIndex;
  final String key;
  final String contentVersion;
  final int generation;
  final double width;
  final double height;
  final double pageHeight;
  final double topInset;
  final ContentSideInsets sideInsets;
  final ComputedStyle baseStyle;
  final ReaderOverrides overrides;
  final ReaderTextOverlayResolver textOverlays;
  final String fontDependency;
  final BookFontView fonts;
  final Set<String> fontFamilies;

  /// 作业只读 face 声明集合；依赖检查与级联改写使用同一章节范围。
  final List<CssFontFace> fontFaces;
  final bool trimTextEdges;
  late final String overrideFingerprint = overrides.fingerprint;
  late final String typographyFingerprint = textOverlays.typographyFingerprint;
}

/// 每次工作片结束时核验取消和实际依赖，后台片段交给框架空闲队列。
class LayoutBudget {
  LayoutBudget({
    required this._priority,
    required this.isCurrent,
    this.publishPages,
    this.wantsProgressivePages,
    this.waitForBackground,
  });

  ChapterLayoutPriority _priority;
  final bool Function() isCurrent;
  final void Function(List<PageContent>)? publishPages;
  final bool Function()? wantsProgressivePages;
  final Future<void>? Function()? waitForBackground;
  final CancelToken token = CancelToken();
  final Completer<void> _cancelled = Completer<void>();
  Completer<void> _promoted = Completer<void>();
  final Stopwatch _slice = Stopwatch()..start();
  int maxSliceMicroseconds = 0;
  int yieldCount = 0;

  ChapterLayoutPriority get priority => _priority;

  set priority(ChapterLayoutPriority next) {
    if (_priority == next) return;
    final previous = _priority;
    _priority = next;
    if (next.index < previous.index) {
      _promoted.complete();
      _promoted = Completer<void>();
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
    final idle = priority == ChapterLayoutPriority.background;
    final limit = switch (priority) {
      ChapterLayoutPriority.reading => 4000,
      ChapterLayoutPriority.prefetch => 2000,
      ChapterLayoutPriority.background => 1000,
    };
    if (!force &&
        elapsed < limit &&
        (!idle || waitForBackground?.call() == null)) {
      return null;
    }
    if (elapsed > maxSliceMicroseconds) maxSliceMicroseconds = elapsed;
    yieldCount += 1;
    return _yield(idle);
  }

  Future<void> _yield(bool idle) async {
    if (idle) {
      await _waitForIdle();
    } else {
      // 需要的邻页优先于空闲工作，仍让出事件循环处理输入。
      await Future<void>.delayed(Duration.zero);
    }
    _slice.reset();
    check();
  }

  Future<void> _waitForIdle() async {
    while (priority == ChapterLayoutPriority.background) {
      final paused = waitForBackground?.call();
      await Future.any([
        paused ??
            SchedulerBinding.instance.scheduleTask<void>(
              () {},
              Priority.idle,
              debugLabel: '章节空闲排版',
            ),
        _cancelled.future,
        _promoted.future,
      ]);
      check();
      if (paused == null && waitForBackground?.call() == null) return;
    }
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
  Completer<void>? _backgroundResumed;

  Future<void>? get backgroundResumeSignal => _backgroundResumed?.future;

  void setBackgroundPaused(bool paused) {
    if (paused) {
      _backgroundResumed ??= Completer<void>();
    } else {
      _backgroundResumed?.complete();
      _backgroundResumed = null;
    }
  }

  bool contains(String key) => _jobs.containsKey(key);

  ProgressiveChapterLoadHandle schedule(
    LayoutSnapshot snapshot, {
    required ChapterLayoutPriority priority,
    required bool retainResult,
    bool progressive = false,
  }) {
    final job = _jobs.putIfAbsent(snapshot.key, () => _ChapterJob(snapshot));
    final waiter = _ChapterWaiter(
      () => _removeIdle(job),
      onPriorityChanged: () {
        job.refreshPriority();
        _preempt(job.priority, requestedJob: job);
        unawaited(_drain());
      },
      priority: priority,
      retainResult: retainResult,
      progressive: progressive,
    );
    job.waiters.add(waiter);
    if (job.pages.isNotEmpty) waiter.publish(job.pages);
    job.refreshPriority();
    if (_closed) {
      waiter.cancel();
    } else {
      _preempt(priority, requestedJob: job);
      unawaited(_drain());
    }
    return waiter;
  }

  void _preempt(ChapterLayoutPriority priority, {_ChapterJob? requestedJob}) {
    final running = _running;
    if (running == null ||
        identical(running, requestedJob) ||
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
    job.waiters.removeWhere((waiter) => waiter.isSettled);
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
          job.waiters.any((waiter) => !waiter.isSettled) &&
          isCurrent(job.snapshot),
      wantsProgressivePages: () =>
          job.waiters.any((waiter) => waiter.progressive && !waiter.isSettled),
      publishPages: job.publish,
      waitForBackground: () => backgroundResumeSignal,
    );
    try {
      budget.check();
      if (budget.priority == ChapterLayoutPriority.background) {
        await budget.checkpoint(force: true);
      }
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
  List<PageContent> pages = const [];

  bool get retainResult =>
      waiters.any((waiter) => !waiter.isSettled && waiter.retainResult);

  void publish(List<PageContent> next) {
    pages = next;
    for (final waiter in waiters.toList()) {
      waiter.publish(next);
    }
    refreshPriority();
  }

  void refreshPriority() {
    final active = waiters.where((waiter) => !waiter.isSettled);
    if (active.isEmpty) return;
    priority = active
        .map((waiter) => waiter.priority)
        .reduce((first, next) => first.index < next.index ? first : next);
    budget?.priority = priority;
  }
}

class _ChapterWaiter implements ProgressiveChapterLoadHandle {
  _ChapterWaiter(
    this.onCancel, {
    this.onPriorityChanged,
    this.priority = ChapterLayoutPriority.reading,
    this.retainResult = false,
    this.progressive = false,
  }) {
    // 句柄可能在调用者 await 之前取消；保留原错误并避免未观察异常。
    unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    unawaited(
      firstPages.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  final void Function() onCancel;
  final void Function()? onPriorityChanged;
  @override
  ChapterLayoutPriority priority;
  final bool retainResult;
  final bool progressive;
  final Completer<List<PageContent>> _completion = Completer();
  final Completer<List<PageContent>> _first = Completer();
  final _updates = StreamController<List<PageContent>>.broadcast(sync: true);
  bool _complete = false;
  bool get isSettled => _completion.isCompleted;
  @override
  List<PageContent> availablePages = const [];
  @override
  bool get isComplete => _complete;

  @override
  Future<List<PageContent>> get firstPages => _first.future;

  @override
  Stream<List<PageContent>> get updates => _updates.stream;

  @override
  void setPriority(ChapterLayoutPriority next) {
    if (isSettled || priority == next) return;
    priority = next;
    onPriorityChanged?.call();
  }

  void publish(List<PageContent> pages) {
    if (isSettled) return;
    availablePages = pages;
    if (!_first.isCompleted) {
      // 首页交付后释放前台预算，余章继续由同一作业后台构块。
      if (progressive) priority = ChapterLayoutPriority.background;
      _first.complete(pages);
    }
    _updates.add(pages);
  }

  @override
  Future<List<PageContent>> get result => _completion.future;

  @override
  void cancel() {
    completeError(const ChapterLoadCancelled(), StackTrace.current);
    onCancel();
  }

  void complete(List<PageContent> pages) {
    if (isSettled) return;
    _complete = true;
    availablePages = pages;
    if (!_first.isCompleted) _first.complete(pages);
    _completion.complete(pages);
    _updates.add(pages);
    unawaited(_updates.close());
  }

  void completeError(Object error, StackTrace stack) {
    if (isSettled) return;
    if (!_first.isCompleted) _first.completeError(error, stack);
    _completion.completeError(error, stack);
    unawaited(_updates.close());
  }
}

/// 准备原文和字体的等待者也可立即取消，随后不会进入排版队列。
class PreparingChapterHandle implements ProgressiveChapterLoadHandle {
  PreparingChapterHandle(
    Future<ChapterLoadHandle> Function(bool Function() isCancelled) prepare, {
    void Function()? onCancel,
    void Function(ChapterLayoutPriority)? onPriorityChanged,
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
  }) {
    _waiter = _ChapterWaiter(
      () {
        onCancel?.call();
        _scheduled?.cancel();
      },
      priority: priority,
      onPriorityChanged: () => onPriorityChanged?.call(_waiter.priority),
    );
    unawaited(_prepare(prepare));
  }

  late final _ChapterWaiter _waiter;
  ChapterLoadHandle? _scheduled;
  StreamSubscription<List<PageContent>>? _subscription;

  Future<void> _prepare(
    Future<ChapterLoadHandle> Function(bool Function() isCancelled) prepare,
  ) async {
    try {
      final scheduled = _scheduled = await prepare(() => _waiter.isSettled);
      if (_waiter.isSettled) scheduled.cancel();
      if (scheduled is ProgressiveChapterLoadHandle) {
        if (scheduled.availablePages.isEmpty) {
          scheduled.setPriority(_waiter.priority);
        }
        _subscription = scheduled.updates.listen((pages) {
          _relayPages(scheduled, pages);
        });
        if (scheduled.availablePages.isNotEmpty) {
          _relayPages(scheduled, scheduled.availablePages);
        }
      }
      final pages = await scheduled.result;
      _waiter.complete(pages);
    } catch (error, stack) {
      _waiter.completeError(error, stack);
    } finally {
      await _subscription?.cancel();
    }
  }

  void _relayPages(
    ProgressiveChapterLoadHandle scheduled,
    List<PageContent> pages,
  ) {
    _waiter.priority = scheduled.priority;
    if (scheduled.isComplete) {
      _waiter.complete(pages);
    } else {
      _waiter.publish(pages);
    }
  }

  @override
  Future<List<PageContent>> get result => _waiter.result;

  @override
  Future<List<PageContent>> get firstPages => _waiter.firstPages;
  @override
  List<PageContent> get availablePages => _waiter.availablePages;
  @override
  Stream<List<PageContent>> get updates => _waiter.updates;
  @override
  bool get isComplete => _waiter.isComplete;
  @override
  ChapterLayoutPriority get priority => _waiter.priority;
  @override
  void setPriority(ChapterLayoutPriority next) {
    _waiter.setPriority(next);
    final scheduled = _scheduled;
    if (scheduled is ProgressiveChapterLoadHandle) scheduled.setPriority(next);
  }

  @override
  void cancel() {
    if (!_waiter.isSettled) _waiter.cancel();
  }
}
