import 'package:flutter/foundation.dart';
import 'package:reader_core/layout/paginator.dart';

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
  bool _loading = false;
  Object? _error;
  bool _disposed = false;

  /// 是否加载中。
  bool get loading => _loading;

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
      final saved = await store.load(bookId);
      if (saved != null) {
        await pager.goTo(saved.spineIndex, saved.pageIndex);
      }
      _pager = pager;
      _loading = false;
      _notify();
      await _persist();
    } catch (error) {
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
    final changed = await pager.next();
    if (changed) {
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
    final changed = await pager.previous();
    if (changed) {
      _notify();
      await _persist();
    }
    return changed;
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
    _disposed = true;
    super.dispose();
  }
}
