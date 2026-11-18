import 'dart:async';

import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';

/// 章节页加载器。
typedef SpinePagesLoader = Future<List<PageContent>> Function(int spineIndex);
typedef ProgressiveSpineLoader = ProgressiveChapterLoadHandle Function(
  int spineIndex,
  ChapterLayoutPriority priority,
);

/// 已加载窗口中的页位置；跨窗口定位应使用章节号与章内页号。
class VirtualPage {
  const VirtualPage({
    required this.virtualIndex,
    required this.spineIndex,
    required this.pageIndex,
    required this.content,
  });

  /// 已加载章节按顺序排列后的索引，不代表尚未排版的全书页码。
  final int virtualIndex;
  final int spineIndex;
  final int pageIndex;
  final PageContent content;

  @override
  String toString() => 'VirtualPage($virtualIndex: $spineIndex/$pageIndex)';
}

/// 按目标章节加载的稀疏页窗口；翻页始终按真实章节顺序查找。
class VirtualPager {
  VirtualPager({
    required this.spineCount,
    required this.loader,
    this.prefetchLoader,
    this.backgroundLoader,
    this.progressiveLoader,
    this.onPagesAvailable,
    this.onPageCountChanged,
    this.prefetchRadius = 1,
  }) : assert(spineCount >= 0);

  final int spineCount;
  final SpinePagesLoader loader;
  final SpinePagesLoader? prefetchLoader;
  final SpinePagesLoader? backgroundLoader;
  final ProgressiveSpineLoader? progressiveLoader;
  final void Function()? onPagesAvailable;
  final void Function()? onPageCountChanged;

  /// 当前页前后各自预热的真实邻页数。
  final int prefetchRadius;

  /// 导航会话保留的章节页窗口；与章节源分页缓存保持同一上限。
  static const int loadedSpineLimit = 5;

  /// 本项目的前向内容储备，独立于前后各两张的位图窗口。
  static const int turnPrefetchPageBudget = 4;

  final Map<int, List<PageContent>> _spinePages = {};
  final List<int> _spineOrder = <int>[];
  final Map<int, int> _spinePageCounts = <int, int>{};
  final Map<int, int> _chapterPageCounts = <int, int>{};
  final Map<int, int> _pageOffsets = <int, int>{};
  final Map<int, Future<void>> _pendingLoads = {};
  final Set<int> _pendingPrefetchSpines = {};
  final Set<int> _partialSpines = {};
  final Map<int, ProgressiveChapterLoadHandle> _progressiveLoads = {};
  final Map<int, StreamSubscription<List<PageContent>>> _pageSubscriptions = {};
  final Map<int, StreamSubscription<int>> _countSubscriptions = {};
  final Map<ProgressiveChapterLoadHandle, List<ChapterLayoutPriority>>
  _pageWaitPriorities = {};
  final Set<VirtualPage> _preparedTargets = Set<VirtualPage>.identity();
  (int, int)? _currentReal;
  bool _initialized = false;
  int _navigationToken = 0;
  int _mappedPageCount = 0;
  int? _maxMappedSpine;

  bool get isInitialized => _initialized;
  Set<int> get loadedSpines => Set<int>.unmodifiable(_spinePages.keys);
  Map<int, List<PageContent>> get spinePages => Map.unmodifiable(_spinePages);
  int get currentVirtualPage => _currentReal == null
      ? 0
      : (_pageOffsets[_currentReal!.$1] ?? 0) + _currentReal!.$2;
  VirtualPage? get current =>
      _currentReal == null ? null : _pageAt(_currentReal!);
  int get mappedPageCount => _mappedPageCount;

  bool isChapterComplete(int spine) =>
      _spinePages.containsKey(spine) && !_partialSpines.contains(spine);

  /// 同一版面的准确总数可以先于完整结果交付，并在页窗口移出后复用。
  int pageCountOf(int spine) => _chapterPageCounts[spine] ?? 0;

  Future<List<PageContent>> completeChapter(
    int spine, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
  }) async {
    final prefetch = priority != ChapterLayoutPriority.reading;
    // 完整消费者直接走完整入口；已有渐进作业则接管，避免重复构块。
    await _loadSpine(
      spine,
      prefetch: prefetch,
      progressive: _partialSpines.contains(spine),
    );
    await _waitForPage(spine, -1, prefetch: prefetch);
    return _spinePages[spine]!;
  }

  /// 未加载邻章可能有内容；导航时才确认并跳过空章。
  bool get hasPrevious => _hasPageInDirection(-1);
  bool get hasNext => _hasPageInDirection(1);

  /// 只提供真实相邻且已加载的页，不跨过未加载章节的断档。
  List<VirtualPage> get prefetchedPages {
    final result = <VirtualPage>[];
    var previous = _currentReal;
    var next = _currentReal;
    for (var distance = 0; distance < prefetchRadius; distance++) {
      if (previous != null) {
        previous = _cachedAdjacent(previous, -1);
        if (previous != null) result.add(_pageAt(previous));
      }
      if (next != null) {
        next = _cachedAdjacent(next, 1);
        if (next != null) result.add(_pageAt(next));
      }
    }
    return result;
  }

  /// 直接加载目标章；空章按书籍顺序向后找，不遍历目标之前的章节。
  Future<void> initialize({int startSpine = 0, int startPage = 0}) async {
    if (_initialized) return;
    final token = _beginNavigation();
    final target = startSpine.clamp(0, spineCount == 0 ? 0 : spineCount - 1);
    final found = await _findPage(
      target,
      startPage < 0 ? 0 : startPage,
      1,
      token,
    );
    if (!found && token == _navigationToken && target > 0) {
      // 目标章缺失且其后没有可读章节时，冷开必须回退到前面最近的完好章。
      await _findPage(target - 1, -1, -1, token);
    }
    if (token == _navigationToken) _initialized = true;
  }

  Future<bool> next() => _movePage(1);
  Future<bool> previous() => _movePage(-1);

  /// 准备真实邻页但不改变阅读位置；空章按内容顺序跳过。
  /// [retainTarget] 保护活动目标章，直到提交、导航失效或显式释放。
  Future<VirtualPage?> prepareAdjacent(
    int direction, {
    bool prefetch = false,
    int distance = 1,
    bool Function()? shouldContinue,
    bool retainTarget = false,
  }) async {
    assert(direction == -1 || direction == 1);
    assert(distance > 0);
    final origin = _currentReal;
    final token = _navigationToken;
    if (origin == null) return null;
    bool valid() =>
        token == _navigationToken &&
        origin == _currentReal &&
        (shouldContinue?.call() ?? true);
    var position = origin;
    for (var step = 0; step < distance; step++) {
      if (!valid()) return null;
      var adjacent = _cachedAdjacent(position, direction);
      if (adjacent == null &&
          direction > 0 &&
          !isChapterComplete(position.$1)) {
        await _waitForPage(position.$1, position.$2 + 1, prefetch: prefetch);
        if (!valid()) return null;
        adjacent = _cachedAdjacent(position, direction);
      }
      var spine = position.$1 + direction;
      while (adjacent == null && spine >= 0 && spine < spineCount) {
        if (!valid()) return null;
        await _loadSpine(spine, prefetch: prefetch);
        await _waitForPage(spine, direction < 0 ? -1 : 0, prefetch: prefetch);
        if (!valid()) return null;
        adjacent = _loadedEdge(spine, direction);
        spine += direction;
      }
      if (adjacent == null) return null;
      position = adjacent;
    }
    final target = _pageAt(position);
    if (retainTarget) _preparedTargets.add(target);
    return target;
  }

  (int, int)? _loadedEdge(int spine, int direction) {
    final pages = _spinePages[spine]!;
    if (pages.isEmpty) return null;
    return (spine, direction < 0 ? pages.length - 1 : 0);
  }

  /// 补一个非空邻章；空闲准备从章界开始，紧急储备按已就绪页数判断。
  Future<PageContent?> prefetchChapter(
    int direction, {
    bool Function()? shouldContinue,
    int pageBudget = turnPrefetchPageBudget,
    bool fromChapterBoundary = false,
    ChapterLayoutPriority priority = ChapterLayoutPriority.prefetch,
  }) async {
    assert(direction == -1 || direction == 1);
    assert(pageBudget > 0);
    final origin = _currentReal;
    final token = _navigationToken;
    if (origin == null) return null;
    final start = fromChapterBoundary
        ? origin.$1 + direction
        : _spineBeyondReadyPages(direction, pageBudget);
    if (start == null) return null;
    for (
      var spine = start;
      spine >= 0 && spine < spineCount;
      spine += direction
    ) {
      if (token != _navigationToken ||
          origin != _currentReal ||
          !(shouldContinue?.call() ?? true)) {
        return null;
      }
      await _loadSpine(spine, prefetch: true, priority: priority);
      await _waitForPage(
        spine,
        direction < 0
            ? -1
            : spine == origin.$1
            ? origin.$2 + pageBudget
            : 0,
        prefetch: true,
        priority: priority,
      );
      if (token != _navigationToken ||
          origin != _currentReal ||
          !(shouldContinue?.call() ?? true)) {
        return null;
      }
      final pages = _spinePages[spine];
      if (pages != null && pages.isNotEmpty) {
        return direction > 0 ? pages.first : pages.last;
      }
    }
    return null;
  }

  int? _spineBeyondReadyPages(int direction, int limit) {
    var position = _currentReal!;
    for (var count = 0; count < limit; count++) {
      final next = _cachedAdjacent(position, direction);
      if (next == null) {
        // 已发布尾页尚非章尾；储备请求接管本章余页，不跨过未排正文。
        return direction > 0 && !isChapterComplete(position.$1)
            ? position.$1
            : position.$1 + direction;
      }
      position = next;
    }
    return null;
  }

  /// 来源已取消这些低优先级等待者，新请求不得复用它们尚未完成的 Future。
  void discardCancelledPrefetch(Iterable<int> spines) {
    for (final spine in spines) {
      if (_pendingPrefetchSpines.remove(spine)) _pendingLoads.remove(spine);
      _progressiveLoads.remove(spine);
      unawaited(_pageSubscriptions.remove(spine)?.cancel());
      unawaited(_countSubscriptions.remove(spine)?.cancel());
    }
  }

  /// 动画结束时原子提交；来源改变或目标过期时拒绝提交。
  bool commitPrepared(PageContent origin, VirtualPage target) {
    if (!identical(current?.content, origin)) {
      releasePrepared(target);
      return false;
    }
    final pages = _spinePages[target.spineIndex];
    if (pages == null ||
        target.pageIndex >= pages.length ||
        !identical(pages[target.pageIndex], target.content)) {
      releasePrepared(target);
      return false;
    }
    _beginNavigation();
    _commitCurrent((target.spineIndex, target.pageIndex));
    return true;
  }

  /// 按准备结果身份释放，重复释放不会撤销同章新目标的保护。
  void releasePrepared(VirtualPage target) {
    if (_preparedTargets.remove(target)) _trimSpinePages();
  }

  /// 跳到章内页；越界页码钳制，空章沿 [emptyDirection] 查找。
  Future<bool> goTo(int spineIndex, int pageIndex, {int emptyDirection = 1}) {
    _ensureInitialized();
    assert(emptyDirection == 1 || emptyDirection == -1);
    if (spineIndex < 0 || spineIndex >= spineCount) {
      return Future<bool>.value(false);
    }
    final token = _beginNavigation();
    return _goToWithFallback(
      spineIndex,
      pageIndex < 0 ? 0 : pageIndex,
      emptyDirection,
      token,
    );
  }

  Future<bool> _goToWithFallback(
    int spineIndex,
    int pageIndex,
    int emptyDirection,
    int token,
  ) async {
    if (await _findPage(spineIndex, pageIndex, emptyDirection, token)) {
      return true;
    }
    if (token != _navigationToken) return false;
    return _findPage(spineIndex - emptyDirection, -1, -emptyDirection, token);
  }

  /// 使在途导航失效；已完成的章节加载仍可作为缓存复用。
  void cancelPendingNavigation() {
    _beginNavigation();
    _trimSpinePages();
  }

  int _beginNavigation() {
    _preparedTargets.clear();
    return ++_navigationToken;
  }

  Future<bool> _movePage(int direction) async {
    _ensureInitialized();
    final token = _beginNavigation();
    final position = _currentReal;
    if (position == null) return false;
    final index = position.$2 + direction;
    if (direction > 0 && !isChapterComplete(position.$1)) {
      await _waitForPage(position.$1, index, prefetch: false);
      if (token != _navigationToken) return false;
    }
    final pages = _spinePages[position.$1]!;
    if (index >= 0 && index < pages.length) {
      _currentReal = (position.$1, index);
      return true;
    }
    return _findPage(
      position.$1 + direction,
      direction < 0 ? -1 : 0,
      direction,
      token,
    );
  }

  Future<bool> _findPage(int spine, int page, int direction, int token) async {
    for (; spine >= 0 && spine < spineCount; spine += direction) {
      await _loadSpine(spine);
      await _waitForPage(spine, page, prefetch: false);
      if (token != _navigationToken) return false;
      final pages = _spinePages[spine]!;
      if (pages.isEmpty) continue;
      final index = page < 0
          ? pages.length - 1
          : page.clamp(0, pages.length - 1);
      _commitCurrent((spine, index));
      return true;
    }
    return false;
  }

  Future<void> _loadSpine(
    int spine, {
    bool prefetch = false,
    bool progressive = true,
    ChapterLayoutPriority? priority,
  }) async {
    if (progressive && progressiveLoader != null && !isChapterComplete(spine)) {
      final handle =
          _progressiveLoads[spine] ??
          _startProgressive(spine, prefetch, priority);
      final requested =
          priority ??
          (prefetch
              ? ChapterLayoutPriority.prefetch
              : ChapterLayoutPriority.reading);
      if (handle.availablePages.isEmpty &&
          requested.index < handle.priority.index) {
        handle.setPriority(requested);
      }
      final pages = await handle.firstPages;
      if (identical(_progressiveLoads[spine], handle)) {
        _storeSpine(spine, pages, complete: handle.isComplete);
      }
      return;
    }
    if (_spinePages.containsKey(spine)) {
      _touchSpine(spine);
      return;
    }
    var pending = _pendingLoads[spine];
    final promote =
        !prefetch &&
        prefetchLoader != null &&
        _pendingPrefetchSpines.contains(spine);
    if (pending == null || promote) {
      // 同章前台等待者提升共享作业，替换 Future 后旧结果不能覆盖新结果。
      late final Future<void> request;
      final load = priority == ChapterLayoutPriority.background
          ? backgroundLoader ?? prefetchLoader ?? loader
          : prefetch
          ? prefetchLoader ?? loader
          : loader;
      request = load(spine).then((pages) {
        if (identical(_pendingLoads[spine], request)) {
          _storeSpine(spine, pages);
        }
      });
      _pendingLoads[spine] = pending = request;
      if (prefetch) {
        _pendingPrefetchSpines.add(spine);
      } else {
        _pendingPrefetchSpines.remove(spine);
      }
    }
    try {
      await pending;
    } finally {
      _pendingLoads.removeWhere(
        (key, value) => key == spine && identical(value, pending),
      );
      if (!_pendingLoads.containsKey(spine)) {
        _pendingPrefetchSpines.remove(spine);
      }
    }
    // 被前台接管的旧预取也等待新结果，避免把尚未发布的章节视为已就绪。
    final replacement = _pendingLoads[spine];
    if (replacement != null && !identical(replacement, pending)) {
      await replacement;
    }
  }

  ProgressiveChapterLoadHandle _startProgressive(
    int spine,
    bool prefetch,
    ChapterLayoutPriority? priority,
  ) {
    final handle = progressiveLoader!(
      spine,
      priority ??
          (prefetch
              ? ChapterLayoutPriority.prefetch
              : ChapterLayoutPriority.reading),
    );
    _progressiveLoads[spine] = handle;
    _partialSpines.add(spine);
    _countSubscriptions[spine] = handle.pageCountUpdates.listen((count) {
      if (identical(_progressiveLoads[spine], handle)) {
        _storePageCount(spine, count);
      }
    });
    if (handle.pageCount case final count?) _storePageCount(spine, count);
    _pageSubscriptions[spine] = handle.updates.listen((pages) {
      if (identical(_progressiveLoads[spine], handle)) {
        _storeSpine(spine, pages, complete: handle.isComplete);
      }
    });
    unawaited(
      handle.result.then<void>(
        (pages) {
          if (identical(_progressiveLoads[spine], handle)) {
            _storeSpine(spine, pages);
            _progressiveLoads.remove(spine);
            unawaited(_pageSubscriptions.remove(spine)?.cancel());
            unawaited(_countSubscriptions.remove(spine)?.cancel());
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_progressiveLoads[spine], handle)) {
            _progressiveLoads.remove(spine);
            unawaited(_pageSubscriptions.remove(spine)?.cancel());
            unawaited(_countSubscriptions.remove(spine)?.cancel());
          }
        },
      ),
    );
    return handle;
  }

  Future<void> _waitForPage(
    int spine,
    int page, {
    required bool prefetch,
    ChapterLayoutPriority? priority,
  }) async {
    bool ready() =>
        isChapterComplete(spine) ||
        (page >= 0 && (_spinePages[spine]?.length ?? 0) > page);
    if (ready()) return;
    await _loadSpine(spine, prefetch: prefetch, priority: priority);
    if (ready()) return;
    final handle = _progressiveLoads[spine]!;
    final priorities = _pageWaitPriorities.putIfAbsent(handle, () => []);
    final requested =
        priority ??
        (prefetch
            ? ChapterLayoutPriority.prefetch
            : ChapterLayoutPriority.reading);
    priorities.add(requested);
    _refreshWaitPriority(handle, priorities);
    try {
      await _awaitPagePublication(handle, ready);
    } finally {
      priorities.remove(requested);
      _refreshWaitPriority(handle, priorities);
      if (priorities.isEmpty) _pageWaitPriorities.remove(handle);
    }
  }

  Future<void> _awaitPagePublication(
    ProgressiveChapterLoadHandle handle,
    bool Function() ready,
  ) async {
    final completion = Completer<void>();
    final subscription = handle.updates.listen((_) {
      if (ready() && !completion.isCompleted) completion.complete();
    });
    unawaited(
      handle.result.then<void>(
        (_) {
          if (!completion.isCompleted) completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!completion.isCompleted) completion.completeError(error, stack);
        },
      ),
    );
    try {
      await completion.future;
    } finally {
      await subscription.cancel();
    }
  }

  void _refreshWaitPriority(
    ProgressiveChapterLoadHandle handle,
    List<ChapterLayoutPriority> priorities,
  ) => handle.setPriority(
    priorities.fold(
      ChapterLayoutPriority.background,
      (first, next) => first.index < next.index ? first : next,
    ),
  );

  void _storeSpine(int spine, List<PageContent> pages, {bool complete = true}) {
    final previous = _spinePages[spine];
    final wasComplete = isChapterComplete(spine);
    // 同配置下被取消的后台作业可重启；此前可见页仍保留原身份。
    if (previous != null && !wasComplete) {
      if (pages.length < previous.length) return;
      pages = [...previous, ...pages.skip(previous.length)];
    }
    _spinePages[spine] = List<PageContent>.unmodifiable(pages);
    if (complete) _partialSpines.remove(spine);
    _recordPageCount(spine, pages.length);
    _touchSpine(spine);
    _trimSpinePages();
    if (complete) _storePageCount(spine, pages.length);
    // 普通完整章由原预热等待者消费；空章通知会重复启动跨章扫描。
    if (pages.isNotEmpty &&
        (!complete || previous != null && !wasComplete) &&
        (previous?.length != pages.length || wasComplete != complete)) {
      onPagesAvailable?.call();
    }
  }

  void _storePageCount(int spine, int count) {
    if (_chapterPageCounts[spine] == count) return;
    _chapterPageCounts[spine] = count;
    onPageCountChanged?.call();
  }

  void _commitCurrent((int, int) position) {
    _currentReal = position;
    _touchSpine(position.$1);
    _trimSpinePages();
  }

  void _touchSpine(int spine) {
    _spineOrder.remove(spine);
    _spineOrder.add(spine);
  }

  void _trimSpinePages() {
    final currentSpine = _currentReal?.$1;
    final preparedSpines = {
      for (final target in _preparedTargets) target.spineIndex,
    };
    while (_spinePages.length > loadedSpineLimit) {
      final removeAt = _spineOrder.indexWhere(
        (spine) => spine != currentSpine && !preparedSpines.contains(spine),
      );
      if (removeAt < 0) break;
      final spine = _spineOrder.removeAt(removeAt);
      _spinePages.remove(spine);
      _partialSpines.remove(spine);
      _progressiveLoads.remove(spine)?.cancel();
      unawaited(_pageSubscriptions.remove(spine)?.cancel());
      unawaited(_countSubscriptions.remove(spine)?.cancel());
    }
  }

  void _recordPageCount(int spine, int count) {
    final previous = _spinePageCounts[spine];
    if (previous == count && _pageOffsets.containsKey(spine)) return;
    final maxMapped = _maxMappedSpine;
    if (previous == null && (maxMapped == null || spine > maxMapped)) {
      _spinePageCounts[spine] = count;
      _pageOffsets[spine] = _mappedPageCount;
      _mappedPageCount += count;
      _maxMappedSpine = spine;
      return;
    }
    _spinePageCounts[spine] = count;
    _rebuildMapping();
  }

  /// 映射扩展时当前位置仍以真实章页保存，不随前方新增章节漂移。
  void _rebuildMapping() {
    _pageOffsets.clear();
    _mappedPageCount = 0;
    final spines = _spinePageCounts.keys.toList()..sort();
    for (final spine in spines) {
      _pageOffsets[spine] = _mappedPageCount;
      _mappedPageCount += _spinePageCounts[spine]!;
    }
    _maxMappedSpine = spines.isEmpty ? null : spines.last;
  }

  VirtualPage _pageAt((int, int) position) => VirtualPage(
    virtualIndex: (_pageOffsets[position.$1] ?? 0) + position.$2,
    spineIndex: position.$1,
    pageIndex: position.$2,
    content: _spinePages[position.$1]![position.$2],
  );

  bool _hasPageInDirection(int direction) {
    final position = _currentReal;
    if (position == null) return false;
    final index = position.$2 + direction;
    if (index >= 0 && index < _spinePages[position.$1]!.length) return true;
    if (direction > 0 && !isChapterComplete(position.$1)) return true;
    for (
      var spine = position.$1 + direction;
      spine >= 0 && spine < spineCount;
      spine += direction
    ) {
      final pages = _spinePages[spine];
      if (pages == null || pages.isNotEmpty || !isChapterComplete(spine)) {
        return true;
      }
    }
    return false;
  }

  (int, int)? _cachedAdjacent((int, int) position, int direction) {
    final index = position.$2 + direction;
    if (index >= 0 && index < _spinePages[position.$1]!.length) {
      return (position.$1, index);
    }
    if (direction > 0 && !isChapterComplete(position.$1)) return null;
    for (
      var spine = position.$1 + direction;
      spine >= 0 && spine < spineCount;
      spine += direction
    ) {
      final pages = _spinePages[spine];
      if (pages == null || (direction < 0 && !isChapterComplete(spine))) {
        return null;
      }
      if (pages.isNotEmpty) {
        return (spine, direction < 0 ? pages.length - 1 : 0);
      }
    }
    return null;
  }

  void _ensureInitialized() {
    if (!_initialized) throw StateError('VirtualPager 尚未 initialize()');
  }
}
