import 'package:flutter/foundation.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/position/cfi.dart';

import 'virtual_pager.dart';

/// 阅读进度：章序号 + 章内页序号。
class ReaderProgress {
  /// 创建进度。
  const ReaderProgress({required this.spineIndex, required this.pageIndex});

  /// 章节序号。
  final int spineIndex;

  /// 章内页序号。
  final int pageIndex;

  @override
  bool operator ==(Object other) =>
      other is ReaderProgress &&
      other.spineIndex == spineIndex &&
      other.pageIndex == pageIndex;

  @override
  int get hashCode => Object.hash(spineIndex, pageIndex);

  @override
  String toString() => 'ReaderProgress($spineIndex,$pageIndex)';
}

/// 阅读进度存储。
abstract interface class ReaderProgressStore {
  /// 读取进度。
  Future<ReaderProgress?> load(String bookId);

  /// 保存进度。
  Future<void> save(String bookId, ReaderProgress progress);
}

/// 内存进度存储（测试/未接持久化时使用）。
class MemoryReaderProgressStore implements ReaderProgressStore {
  final Map<String, ReaderProgress> _items = <String, ReaderProgress>{};

  @override
  Future<ReaderProgress?> load(String bookId) async => _items[bookId];

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    _items[bookId] = progress;
  }
}

/// 章节页来源。
abstract interface class ReaderChapterSource {
  /// 章节数。
  int get chapterCount;

  /// 加载一章的页。
  Future<List<PageContent>> loadChapter(int spineIndex);
}

/// 支持按设置重排的章节源（P2-24）：字号/行高/页边距变化后原地重排。
abstract interface class RestylableChapterSource
    implements ReaderChapterSource {
  /// 应用阅读器覆盖设置；调用方随后应重新加载章节。
  Future<void> applyOverrides(ReaderOverrides overrides);
}

/// 最小阅读会话：打开/恢复、翻页、保存进度。
class ReaderSession extends ChangeNotifier {
  /// 创建会话。
  ReaderSession({
    required this.source,
    required this.store,
    required this.bookId,
  });

  /// 章节来源。
  final ReaderChapterSource source;

  /// 进度存储。
  final ReaderProgressStore store;

  /// 书籍标识。
  final String bookId;

  VirtualPager? _pager;
  ReaderOverrides _overrides = const ReaderOverrides();
  bool _loading = false;

  /// 异步任务代号：取消或开始新任务后，旧任务不再回写状态（P2-27）。
  int _generation = 0;
  Object? _error;
  bool _disposed = false;

  /// 是否加载中。
  bool get loading => _loading;

  /// 首屏是否已就绪（有可绘制内容）。
  bool get hasContent => page != null;

  /// 整书进度（按章节位置估算，0～1），用于加载态进度条。
  double get bookProgress {
    final value = progress;
    if (value == null) {
      return 0;
    }
    final count = source.chapterCount;
    if (count <= 0) {
      return 0;
    }
    return ((value.spineIndex + 1) / count).clamp(0.0, 1.0);
  }

  /// 取消尚未完成的打开/重排/翻页任务。
  ///
  /// 取消后旧任务不会再改写 [page]、[error]、[loading]，可安全重新打开。
  void cancelPendingLoads() {
    _generation += 1;
    _loading = false;
    _notify();
  }

  /// 打开错误。
  Object? get error => _error;

  /// 当前页。
  PageContent? get page => _pager?.current?.content;

  /// 当前进度。
  ReaderProgress? get progress {
    final current = _pager?.current;
    if (current == null) {
      return null;
    }
    return ReaderProgress(
      spineIndex: current.spineIndex,
      pageIndex: current.pageIndex,
    );
  }

  /// 当前虚拟页号。
  int get currentVirtualPage => _pager?.currentVirtualPage ?? 0;

  /// 已映射页数。
  int get mappedPageCount => _pager?.mappedPageCount ?? 0;

  /// 当前页文本（用于测试/无障碍）。
  String get currentText {
    final value = page;
    if (value == null) {
      return '';
    }
    final buffer = StringBuffer();
    for (final slice in value.slices) {
      for (var i = slice.startLine; i < slice.endLine; i++) {
        final line = slice.block.layout.lines[i];
        buffer.write(slice.block.layout.text.substring(line.start, line.end));
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  /// 打开并恢复进度。
  Future<void> open() async {
    if (_loading || _pager != null) {
      return;
    }
    final generation = ++_generation;
    _loading = true;
    _error = null;
    _notify();
    try {
      if (source.chapterCount <= 0) {
        throw StateError('书籍没有章节');
      }
      final pager = VirtualPager(
        spineCount: source.chapterCount,
        loader: source.loadChapter,
      );
      await pager.initialize();
      if (generation != _generation) {
        return;
      }
      final saved = await store.load(bookId);
      if (generation != _generation) {
        return;
      }
      if (saved != null) {
        await pager.goTo(saved.spineIndex, saved.pageIndex);
        if (generation != _generation) {
          return;
        }
      }
      _pager = pager;
      _loading = false;
      _notify();
      await _persist();
    } catch (error) {
      if (generation != _generation) {
        return;
      }
      _error = error;
      _loading = false;
      _notify();
    }
  }

  /// 下一页。
  Future<bool> next() async {
    final pager = _pager;
    if (pager == null) {
      return false;
    }
    final generation = _generation;
    final changed = await pager.next();
    if (changed && generation == _generation) {
      _notify();
      await _persist();
    }
    return changed;
  }

  /// 上一页。
  Future<bool> previous() async {
    final pager = _pager;
    if (pager == null) {
      return false;
    }
    final generation = _generation;
    final changed = await pager.previous();
    if (changed && generation == _generation) {
      _notify();
      await _persist();
    }
    return changed;
  }

  /// 当前设置。
  ReaderOverrides get overrides => _overrides;

  /// 当前布局指纹（P2-24）。
  String get layoutFingerprint => _overrides.fingerprint;

  /// 应用阅读器设置：指纹变化时重排章节并按 CFI 恢复位置（§21、§17.4）。
  Future<void> applyOverrides(ReaderOverrides next) async {
    if (next.fingerprint == _overrides.fingerprint) {
      _overrides = next;
      return;
    }
    final generation = ++_generation;
    final currentPage = _pager?.current?.content;
    final spine = currentPage?.spineIndex ?? 0;
    final targetCfi = _firstCfiOf(currentPage);
    _overrides = next;
    final src = source;
    if (src is! RestylableChapterSource) {
      _notify();
      return;
    }
    _loading = true;
    _notify();
    try {
      await src.applyOverrides(next);
      if (generation != _generation) {
        return;
      }
      final pages = await src.loadChapter(spine);
      if (generation != _generation) {
        return;
      }
      final pager = VirtualPager(
        spineCount: src.chapterCount,
        loader: src.loadChapter,
      );
      await pager.initialize();
      if (generation != _generation) {
        return;
      }
      await pager.goTo(spine, _locatePage(pages, targetCfi));
      if (generation != _generation) {
        return;
      }
      _pager = pager;
      _error = null;
    } catch (error) {
      if (generation != _generation) {
        return;
      }
      _error = error;
    } finally {
      if (generation == _generation) {
        _loading = false;
        _notify();
        await _persist();
      }
    }
  }

  /// 当前页的定位 CFI：优先取「在本页起始的块」，纯续页时退化为第一片。
  static String? _firstCfiOf(PageContent? page) {
    if (page == null) {
      return null;
    }
    for (final slice in page.slices) {
      if (slice.startLine != 0) {
        continue;
      }
      final cfi = slice.block.startCfi;
      if (cfi != null && cfi.isNotEmpty) {
        return cfi;
      }
    }
    for (final slice in page.slices) {
      final cfi = slice.block.startCfi;
      if (cfi != null && cfi.isNotEmpty) {
        return cfi;
      }
    }
    return null;
  }

  /// 在新分页结果里找第一个起点 CFI ≥ [cfi] 的页；找不到则取末页。
  static int _locatePage(List<PageContent> pages, String? cfi) {
    if (pages.isEmpty) {
      return 0;
    }
    final target = cfi == null ? null : EpubCfi.parse(cfi);
    if (target == null) {
      return pages.first.pageIndex;
    }
    for (final page in pages) {
      for (final slice in page.slices) {
        final value = slice.block.startCfi;
        if (value == null) {
          continue;
        }
        final parsed = EpubCfi.parse(value);
        if (parsed != null && parsed.compareTo(target) >= 0) {
          return page.pageIndex;
        }
      }
    }
    return pages.last.pageIndex;
  }

  Future<void> _persist() async {
    final value = progress;
    if (value != null) {
      await store.save(bookId, value);
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _generation += 1; // 丢弃未完成任务
    _disposed = true;
    super.dispose();
  }
}
