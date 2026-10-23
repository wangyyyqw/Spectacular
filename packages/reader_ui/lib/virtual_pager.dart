import 'package:reader_core/layout/paginator.dart';

/// 章节页加载器。
typedef SpinePagesLoader = Future<List<PageContent>> Function(int spineIndex);

/// 虚拟页位置。
class VirtualPage {
  /// 创建位置。
  const VirtualPage({
    required this.virtualIndex,
    required this.spineIndex,
    required this.pageIndex,
    required this.content,
  });

  /// 连续虚拟页号。
  final int virtualIndex;

  /// 章节序号。
  final int spineIndex;

  /// 章内页序号。
  final int pageIndex;

  /// 页内容。
  final PageContent content;

  @override
  String toString() => 'VirtualPage($virtualIndex: $spineIndex/$pageIndex)';
}

/// 虚拟页窗口：把按章分页的页映射为连续页码，并前后预取 1 页。
class VirtualPager {
  /// 创建窗口。
  VirtualPager({
    required this.spineCount,
    required this.loader,
    this.prefetchRadius = 1,
  }) : assert(spineCount >= 0);

  /// 章节总数。
  final int spineCount;

  /// 章节页加载器。
  final SpinePagesLoader loader;

  /// 前后预取页数（最小版固定 1）。
  final int prefetchRadius;

  final Map<int, List<PageContent>> _spinePages = <int, List<PageContent>>{};
  final Set<int> _loadedSpines = <int>{};
  final Map<int, (int, int)> _virtualToReal = <int, (int, int)>{};
  final Map<(int, int), int> _realToVirtual = <(int, int), int>{};
  final List<(int, int)> _ordered = <(int, int)>[];
  int _currentVirtual = 0;
  bool _initialized = false;

  /// 是否已初始化。
  bool get isInitialized => _initialized;

  /// 已加载章。
  Set<int> get loadedSpines => Set<int>.unmodifiable(_loadedSpines);

  /// 章 → 页（只含已加载章）。
  Map<int, List<PageContent>> get spinePages =>
      Map<int, List<PageContent>>.unmodifiable(_spinePages);

  /// 当前虚拟页号。
  int get currentVirtualPage => _currentVirtual;

  /// 当前页。
  VirtualPage? get current {
    final real = _virtualToReal[_currentVirtual];
    if (real == null) {
      return null;
    }
    final page = _spinePages[real.$1]?[real.$2];
    if (page == null) {
      return null;
    }
    return VirtualPage(
      virtualIndex: _currentVirtual,
      spineIndex: real.$1,
      pageIndex: real.$2,
      content: page,
    );
  }

  /// 已映射总页数。
  int get mappedPageCount => _ordered.length;

  /// 是否有上一页。
  bool get hasPrevious => _currentVirtual > 0;

  /// 是否有下一页。
  bool get hasNext => _currentVirtual < _ordered.length - 1;

  /// 预取页（当前 ±1，已映射范围内）。
  List<VirtualPage> get prefetchedPages {
    final result = <VirtualPage>[];
    for (var offset = -prefetchRadius; offset <= prefetchRadius; offset++) {
      if (offset == 0) {
        continue;
      }
      final index = _currentVirtual + offset;
      final real = _virtualToReal[index];
      if (real == null) {
        continue;
      }
      final page = _spinePages[real.$1]?[real.$2];
      if (page != null) {
        result.add(
          VirtualPage(
            virtualIndex: index,
            spineIndex: real.$1,
            pageIndex: real.$2,
            content: page,
          ),
        );
      }
    }
    return result;
  }

  /// 初始化；[startSpine] 之前章节会顺序加载用于计算连续页码。
  Future<void> initialize({int startSpine = 0}) async {
    if (_initialized) {
      return;
    }
    final target = startSpine.clamp(0, spineCount == 0 ? 0 : spineCount - 1);
    for (var spine = 0; spine <= target; spine++) {
      await _loadSpine(spine);
    }
    _rebuildMapping();
    final first = _realToVirtual[(target, 0)];
    _currentVirtual = first ?? 0;
    _initialized = true;
    await _prefetchAround();
  }

  /// 下一页。
  Future<bool> next() async {
    _ensureInitialized();
    if (hasNext) {
      _currentVirtual += 1;
      await _prefetchAround();
      return true;
    }
    final currentPage = current;
    if (currentPage == null) {
      return false;
    }
    var nextSpine = currentPage.spineIndex + 1;
    while (nextSpine < spineCount) {
      await _loadSpine(nextSpine);
      _rebuildMapping();
      if (_currentVirtual < _ordered.length - 1) {
        _currentVirtual += 1;
        await _prefetchAround();
        return true;
      }
      nextSpine += 1;
    }
    return false;
  }

  /// 上一页。
  Future<bool> previous() async {
    _ensureInitialized();
    if (hasPrevious) {
      _currentVirtual -= 1;
      await _prefetchAround();
      return true;
    }
    return false;
  }

  /// 跳到指定章页。
  Future<bool> goTo(int spineIndex, int pageIndex) async {
    _ensureInitialized();
    if (spineIndex < 0 || spineIndex >= spineCount) {
      return false;
    }
    for (var spine = 0; spine <= spineIndex; spine++) {
      if (!_loadedSpines.contains(spine)) {
        await _loadSpine(spine);
      }
    }
    _rebuildMapping();
    final target = _realToVirtual[(spineIndex, pageIndex)];
    if (target == null) {
      return false;
    }
    _currentVirtual = target;
    await _prefetchAround();
    return true;
  }

  Future<void> _loadSpine(int spine) async {
    if (_loadedSpines.contains(spine)) {
      return;
    }
    final pages = await loader(spine);
    _spinePages[spine] = List<PageContent>.unmodifiable(pages);
    _loadedSpines.add(spine);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('VirtualPager 尚未 initialize()');
    }
  }

  void _rebuildMapping() {
    _virtualToReal.clear();
    _realToVirtual.clear();
    _ordered.clear();
    for (var spine = 0; spine < spineCount; spine++) {
      final pages = _spinePages[spine];
      if (pages == null) {
        break;
      }
      for (var page = 0; page < pages.length; page++) {
        final index = _ordered.length;
        _ordered.add((spine, page));
        _virtualToReal[index] = (spine, page);
        _realToVirtual[(spine, page)] = index;
      }
    }
    if (_currentVirtual >= _ordered.length) {
      _currentVirtual = _ordered.isEmpty ? 0 : _ordered.length - 1;
    }
  }

  Future<void> _prefetchAround() async {
    final page = current;
    if (page == null) {
      return;
    }
    final pages = _spinePages[page.spineIndex];
    if (pages == null || pages.isEmpty) {
      return;
    }
    // 页级预取由已加载页列表直接覆盖；章边界预取相邻章，绝不越过 0..spineCount-1。
    if (page.pageIndex == pages.length - 1 &&
        page.spineIndex + 1 < spineCount) {
      await _loadSpine(page.spineIndex + 1);
      _rebuildMapping();
    }
    if (page.pageIndex == 0 && page.spineIndex > 0) {
      await _loadSpine(page.spineIndex - 1);
      _rebuildMapping();
    }
  }
}
