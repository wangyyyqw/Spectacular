import 'package:reader_core/layout/paginator.dart';

/// 章节页加载器。
typedef SpinePagesLoader = Future<List<PageContent>> Function(int spineIndex);

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
    this.prefetchRadius = 1,
  }) : assert(spineCount >= 0);

  final int spineCount;
  final SpinePagesLoader loader;

  /// 从已加载章节中提供的前后邻页数，不触发额外整章排版。
  final int prefetchRadius;

  /// 导航会话保留的章节页窗口；与章节源分页缓存保持同一上限。
  static const int loadedSpineLimit = 5;

  final Map<int, List<PageContent>> _spinePages = {};
  final List<int> _spineOrder = <int>[];
  final Map<int, int> _spinePageCounts = <int, int>{};
  final Map<int, int> _pageOffsets = <int, int>{};
  final Map<int, Future<void>> _pendingLoads = {};
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

  /// 未加载邻章可能有内容；导航时才确认并跳过空章。
  bool get hasPrevious => _hasPageInDirection(-1);
  bool get hasNext => _hasPageInDirection(1);

  /// 只提供真实相邻且已加载的页，不跨过未加载章节的断档。
  List<VirtualPage> get prefetchedPages {
    final result = <VirtualPage>[];
    for (final direction in [-1, 1]) {
      var position = _currentReal;
      for (
        var distance = 0;
        position != null && distance < prefetchRadius;
        distance++
      ) {
        position = _cachedAdjacent(position, direction);
        if (position != null) result.add(_pageAt(position));
      }
    }
    return result;
  }

  /// 直接加载目标章；空章按书籍顺序向后找，不遍历目标之前的章节。
  Future<void> initialize({int startSpine = 0, int startPage = 0}) async {
    if (_initialized) return;
    final token = ++_navigationToken;
    final target = startSpine.clamp(0, spineCount == 0 ? 0 : spineCount - 1);
    await _findPage(target, startPage < 0 ? 0 : startPage, 1, token);
    if (token == _navigationToken) _initialized = true;
  }

  Future<bool> next() => _movePage(1);
  Future<bool> previous() => _movePage(-1);

  /// 准备真实邻页但不改变阅读位置；空章按内容顺序跳过。
  Future<VirtualPage?> prepareAdjacent(int direction) async {
    assert(direction == -1 || direction == 1);
    final origin = _currentReal;
    if (origin == null) return null;
    final cached = _cachedAdjacent(origin, direction);
    if (cached != null) return _pageAt(cached);
    for (
      var spine = origin.$1 + direction;
      spine >= 0 && spine < spineCount;
      spine += direction
    ) {
      await _loadSpine(spine);
      final pages = _spinePages[spine]!;
      if (pages.isNotEmpty) {
        return _pageAt((spine, direction < 0 ? pages.length - 1 : 0));
      }
    }
    return null;
  }

  /// 动画结束时原子提交；来源改变或目标过期时拒绝提交。
  bool commitPrepared(PageContent origin, VirtualPage target) {
    if (!identical(current?.content, origin)) return false;
    final pages = _spinePages[target.spineIndex];
    if (pages == null ||
        target.pageIndex >= pages.length ||
        !identical(pages[target.pageIndex], target.content)) {
      return false;
    }
    _navigationToken++;
    _commitCurrent((target.spineIndex, target.pageIndex));
    return true;
  }

  /// 跳到章内页；越界页码钳制，空章沿 [emptyDirection] 查找。
  Future<bool> goTo(int spineIndex, int pageIndex, {int emptyDirection = 1}) {
    _ensureInitialized();
    assert(emptyDirection == 1 || emptyDirection == -1);
    return _findPage(
      spineIndex,
      pageIndex < 0 ? 0 : pageIndex,
      emptyDirection,
      ++_navigationToken,
    );
  }

  /// 使在途导航失效；已完成的章节加载仍可作为缓存复用。
  void cancelPendingNavigation() => _navigationToken++;

  Future<bool> _movePage(int direction) {
    _ensureInitialized();
    final token = ++_navigationToken;
    final position = _currentReal;
    if (position == null) return Future.value(false);
    final index = position.$2 + direction;
    final pages = _spinePages[position.$1]!;
    if (index >= 0 && index < pages.length) {
      _currentReal = (position.$1, index);
      return Future.value(true);
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

  Future<void> _loadSpine(int spine) async {
    if (_spinePages.containsKey(spine)) {
      _touchSpine(spine);
      return;
    }
    final pending = _pendingLoads.putIfAbsent(spine, () async {
      final pages = await loader(spine);
      _spinePages[spine] = List<PageContent>.unmodifiable(pages);
      _recordPageCount(spine, pages.length);
      _touchSpine(spine);
      _trimSpinePages();
    });
    try {
      await pending;
    } finally {
      _pendingLoads.removeWhere(
        (key, value) => key == spine && identical(value, pending),
      );
    }
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
    while (_spinePages.length > loadedSpineLimit) {
      final removeAt = _spineOrder.indexWhere((spine) => spine != currentSpine);
      if (removeAt < 0) break;
      _spinePages.remove(_spineOrder.removeAt(removeAt));
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
    for (
      var spine = position.$1 + direction;
      spine >= 0 && spine < spineCount;
      spine += direction
    ) {
      final pages = _spinePages[spine];
      if (pages == null || pages.isNotEmpty) return true;
    }
    return false;
  }

  (int, int)? _cachedAdjacent((int, int) position, int direction) {
    final index = position.$2 + direction;
    if (index >= 0 && index < _spinePages[position.$1]!.length) {
      return (position.$1, index);
    }
    for (
      var spine = position.$1 + direction;
      spine >= 0 && spine < spineCount;
      spine += direction
    ) {
      final pages = _spinePages[spine];
      if (pages == null) return null;
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
