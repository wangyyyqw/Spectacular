import 'dart:collection';

import 'package:reader_core/layout/paginator.dart';

/// 页缓存键：章节 + 章内页索引。
class PageKey {
  /// 创建键。
  const PageKey(this.spineIndex, this.pageIndex);

  /// 章节序号。
  final int spineIndex;

  /// 章内页序号。
  final int pageIndex;

  @override
  bool operator ==(Object other) =>
      other is PageKey &&
      other.spineIndex == spineIndex &&
      other.pageIndex == pageIndex;

  @override
  int get hashCode => Object.hash(spineIndex, pageIndex);

  @override
  String toString() => 'PageKey($spineIndex,$pageIndex)';
}

/// 页加载回调。
typedef PageLoader = Future<PageContent> Function(
  int spineIndex,
  int pageIndex,
);

/// 当前章 ±N 页的 LRU 缓存，负责相邻页预取与去重加载。
class PageCache {
  /// 创建缓存。
  ///
  /// [capacity] 设为覆盖一次 10 页往返，保证“第二次经过”命中；
  /// [prefetchRadius] 是相邻页预取半径（技术方案默认 ±2）。
  PageCache({
    required this.loader,
    this.capacity = 16,
    this.prefetchRadius = 2,
  }) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', '必须大于 0');
    }
  }

  /// 页加载回调。
  final PageLoader loader;

  /// 缓存容量。
  final int capacity;

  /// 相邻页预取半径。
  final int prefetchRadius;

  final LinkedHashMap<PageKey, PageContent> _pages =
      LinkedHashMap<PageKey, PageContent>();
  final Map<PageKey, Future<PageContent>> _pending =
      <PageKey, Future<PageContent>>{};
  int _hits = 0;
  int _misses = 0;
  int _loaderCalls = 0;

  /// 当前缓存页数。
  int get length => _pages.length;

  /// 命中次数。
  int get hits => _hits;

  /// 未命中次数。
  int get misses => _misses;

  /// 实际调用 loader 的次数。
  int get loaderCalls => _loaderCalls;

  /// 总体命中率（0..1）。
  double get hitRate {
    final total = _hits + _misses;
    return total == 0 ? 0 : _hits / total;
  }

  /// 取页；命中直接返回，未命中调用 loader。
  Future<PageContent> get(int spineIndex, int pageIndex) {
    final key = PageKey(spineIndex, pageIndex);
    final cached = _pages.remove(key);
    if (cached != null) {
      _pages[key] = cached;
      _hits += 1;
      return Future<PageContent>.value(cached);
    }

    _misses += 1;
    final pending = _pending[key];
    if (pending != null) {
      return pending;
    }

    _loaderCalls += 1;
    final future = _load(key, spineIndex, pageIndex);
    _pending[key] = future;
    return future;
  }

  Future<PageContent> _load(PageKey key, int spineIndex, int pageIndex) async {
    try {
      final page = await loader(spineIndex, pageIndex);
      _put(key, page);
      return page;
    } finally {
      _pending.remove(key)?.ignore();
    }
  }

  /// 预取当前页前后 [prefetchRadius] 页；失败静默（loader 抛错不影响翻页）。
  Future<void> prefetchAround({
    required int spineIndex,
    required int pageIndex,
    int? pageCount,
  }) async {
    for (var offset = -prefetchRadius; offset <= prefetchRadius; offset++) {
      if (offset == 0) {
        continue;
      }
      final target = pageIndex + offset;
      if (target < 0) {
        continue;
      }
      if (pageCount != null && target >= pageCount) {
        continue;
      }
      if (_pages.containsKey(PageKey(spineIndex, target)) ||
          _pending.containsKey(PageKey(spineIndex, target))) {
        continue;
      }
      try {
        await get(spineIndex, target);
      } catch (_) {
        // 预取失败留待按需加载重试。
      }
    }
  }

  /// 主动放入一页。
  void put(int spineIndex, int pageIndex, PageContent page) {
    _put(PageKey(spineIndex, pageIndex), page);
  }

  /// 是否已缓存。
  bool contains(int spineIndex, int pageIndex) =>
      _pages.containsKey(PageKey(spineIndex, pageIndex));

  /// 只保留给定页（翻页时保留当前 ±2 页）。
  void evictExcept(Set<PageKey> keep) {
    _pages.removeWhere((key, _) => !keep.contains(key));
  }

  /// 清空全部缓存与统计（字号/边距/字体变化时调用）。
  void clear() {
    _pages.clear();
    _pending.clear();
    _hits = 0;
    _misses = 0;
    _loaderCalls = 0;
  }

  void _put(PageKey key, PageContent page) {
    _pages.remove(key);
    _pages[key] = page;
    while (_pages.length > capacity) {
      _pages.remove(_pages.keys.first);
    }
  }
}
