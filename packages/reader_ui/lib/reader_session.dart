import 'dart:math' as math;

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

/// 重排锚点（P2-31）：块级 CFI + 块内字符偏移（近似行）。
class ReaderAnchor {
  /// 创建锚点；[cfi] 为空表示没有可恢复位置。
  const ReaderAnchor({this.cfi, this.charOffset = 0});

  /// 块级 CFI。
  final String? cfi;

  /// 块内字符偏移（首行起点）。
  final int charOffset;

  /// 是否为空锚点。
  bool get isEmpty => cfi == null;
}

/// 可应用正文区尺寸的章节源（旋转/窗口变化，P2-31）。
abstract interface class ResizableChapterSource implements ReaderChapterSource {
  /// 应用正文区尺寸；返回是否真的发生变化（变化后调用方重新加载章节）。
  Future<bool> applyContentSize({
    required double width,
    required double height,
  });
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

  double? _contentWidth;
  double? _contentHeight;
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

  /// 重排锚点（P2-31）：块级 CFI + 块内字符偏移（近似行）。
  ReaderAnchor _anchorOf(PageContent? page) {
    for (final slice in page?.slices ?? const <PageBlockSlice>[]) {
      if (slice.startLine != 0) {
        continue;
      }
      final cfi = slice.block.startCfi;
      if (cfi != null && cfi.isNotEmpty) {
        return ReaderAnchor(cfi: cfi, charOffset: _lineStartOffset(slice));
      }
    }
    for (final slice in page?.slices ?? const <PageBlockSlice>[]) {
      final cfi = slice.block.startCfi;
      if (cfi != null && cfi.isNotEmpty) {
        return ReaderAnchor(cfi: cfi, charOffset: _lineStartOffset(slice));
      }
    }
    return const ReaderAnchor();
  }

  static int _lineStartOffset(PageBlockSlice slice) {
    final layout = slice.block.layout;
    if (slice.startLine < 0 || slice.startLine >= layout.lines.length) {
      return 0;
    }
    return layout.lines[slice.startLine].start;
  }

  /// 应用阅读器设置：指纹变化时重排章节并按锚点恢复位置（§21、§17.4）。
  Future<void> applyOverrides(ReaderOverrides next) async {
    if (next.fingerprint == _overrides.fingerprint) {
      _overrides = next;
      return;
    }
    final currentPage = _pager?.current?.content;
    final spine = currentPage?.spineIndex ?? 0;
    final anchor = _anchorOf(currentPage);
    _overrides = next;
    final src = source;
    if (src is! RestylableChapterSource) {
      _notify();
      return;
    }
    final generation = ++_generation;
    await _reloadChapter(
      generation: generation,
      spine: spine,
      anchor: anchor,
      prepare: () => src.applyOverrides(next),
    );
  }

  /// 应用新的正文区尺寸（旋转/窗口变化，P2-31）。
  ///
  /// 尺寸变化时重排当前章节并按锚点恢复；尺寸未变时直接返回。
  Future<void> applyContentSize({
    required double width,
    required double height,
  }) async {
    if (_contentWidth == width && _contentHeight == height) {
      return;
    }
    _contentWidth = width;
    _contentHeight = height;
    final src = source;
    if (src is! ResizableChapterSource) {
      return;
    }
    final currentPage = _pager?.current?.content;
    final spine = currentPage?.spineIndex ?? 0;
    final anchor = _anchorOf(currentPage);
    final generation = ++_generation;
    final changed = await src.applyContentSize(width: width, height: height);
    if (!changed || generation != _generation) {
      return;
    }
    await _reloadChapter(generation: generation, spine: spine, anchor: anchor);
  }

  /// 重载当前章节并回到锚点；失败时不丢弃旧页（避免闪空白）。
  Future<void> _reloadChapter({
    required int generation,
    required int spine,
    required ReaderAnchor anchor,
    Future<void> Function()? prepare,
  }) async {
    _loading = true;
    _notify();
    try {
      if (prepare != null) {
        await prepare();
        if (generation != _generation) {
          return;
        }
      }
      final pages = await source.loadChapter(spine);
      if (generation != _generation) {
        return;
      }
      final pager = VirtualPager(
        spineCount: source.chapterCount,
        loader: source.loadChapter,
      );
      await pager.initialize();
      if (generation != _generation) {
        return;
      }
      await pager.goTo(spine, _locatePage(pages, anchor));
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

  /// 在新分页里按锚点定位：优先找包含「块 CFI + 近似行」的页，
  /// 找不到该行时退化为块所在页，再退化为 CFI ≥ 目标的页。
  static int _locatePage(List<PageContent> pages, ReaderAnchor anchor) {
    if (pages.isEmpty) {
      return 0;
    }
    final cfi = anchor.cfi;
    final target = cfi == null ? null : EpubCfi.parse(cfi);
    if (target == null) {
      return pages.first.pageIndex;
    }
    var fallback = -1;
    for (final page in pages) {
      for (final slice in page.slices) {
        final value = slice.block.startCfi;
        if (value == null) {
          continue;
        }
        final parsed = EpubCfi.parse(value);
        if (parsed == null) {
          continue;
        }
        final comparison = parsed.compareTo(target);
        if (comparison == 0) {
          if (_sliceContainsOffset(slice, anchor.charOffset)) {
            return page.pageIndex;
          }
          if (fallback < 0) {
            fallback = page.pageIndex;
          }
        } else if (comparison > 0 && fallback < 0) {
          fallback = page.pageIndex;
        }
      }
    }
    return fallback >= 0 ? fallback : pages.last.pageIndex;
  }

  static bool _sliceContainsOffset(PageBlockSlice slice, int offset) {
    final layout = slice.block.layout;
    final last = math.min(slice.endLine, layout.lines.length);
    for (var i = slice.startLine; i < last; i++) {
      final line = layout.lines[i];
      if (offset >= line.start && offset <= line.end) {
        return true;
      }
    }
    return false;
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
