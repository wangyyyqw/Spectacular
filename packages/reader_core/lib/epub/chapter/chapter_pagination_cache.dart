import 'dart:async';

import '../../cache/chapter_pagination_store.dart';
import '../../util/bounded_cache.dart';
import 'chapter_layout_cache.dart';

/// 准确页数先保留，页索引随后补齐；写入不阻塞首页或完整章节交付。
class ChapterPaginationCache {
  ChapterPaginationCache(this.store);

  final ChapterPaginationStore? store;
  final _entries = BoundedCache<String, ChapterPaginationData>(128);
  final Map<String, Future<void>> _writes = {};
  int hits = 0;
  int failures = 0;

  Future<ChapterPaginationData?> read(String key) async {
    final cached = _entries[key];
    if (cached != null) return cached;
    if (store == null) return null;
    try {
      final loaded = await store!.read(key);
      if (loaded == null) return null;
      hits += 1;
      return _entries[key] ?? (_entries[key] = loaded);
    } catch (_) {
      // 缓存不可用时沿用正式分页，不影响书籍打开和阅读。
      failures += 1;
      return null;
    }
  }

  void rememberCount(String key, int count) {
    final previous = _entries[key];
    if (previous?.pageCount == count) return;
    _remember(ChapterPaginationData(key: key, pageCount: count));
  }

  void rememberLayout(CompletedChapterLayout layout) {
    final previous = _entries[layout.key];
    if (previous?.pageCount == layout.pages.length &&
        identical(previous?.pageIndex, layout.pageIndex)) {
      return;
    }
    _remember(
      ChapterPaginationData(
        key: layout.key,
        pageCount: layout.pages.length,
        pageIndex: layout.pageIndex,
      ),
    );
  }

  void _remember(ChapterPaginationData data) {
    _entries[data.key] = data;
    if (store == null) return;
    late final Future<void> writing;
    writing = (_writes[data.key] ?? Future<void>.value())
        .then((_) => store!.write(data))
        .catchError((Object _) {
          failures += 1;
        })
        .whenComplete(() {
          if (identical(_writes[data.key], writing)) _writes.remove(data.key);
        });
    _writes[data.key] = writing;
    unawaited(writing);
  }

  Future<void> get writesStopped => Future.wait(_writes.values).then((_) {});
}
