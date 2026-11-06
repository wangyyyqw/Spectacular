import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/scroll_layout.dart';
import 'package:reader_core/perf/trace.dart';
import 'package:reader_core/position/cfi.dart';

import 'virtual_pager.dart';

typedef _ContentSizeRequest = ({
  double width,
  double height,
  double topInset,
  bool preview,
});
typedef _OverrideRequest = ({ReaderOverrides overrides, int generation});

/// 阅读进度：章序号 + 章内页序号。
class ReaderProgress {
  /// 创建进度。
  const ReaderProgress({
    required this.spineIndex,
    required this.pageIndex,
    this.finished = false,
    this.scrollOffset,
    this.cfi,
    this.contentRevision,
    this.approximate = false,
  });

  /// 章节序号。
  final int spineIndex;

  /// 章内页序号。
  final int pageIndex;

  /// 是否已到达全书最后一页。
  final bool finished;

  /// 连续滚动模式在当前页切片内的垂直偏移；分页模式为 null。
  final double? scrollOffset;

  /// 当前内容的文字锚点；页号仅作为同版本的快速恢复提示。
  final String? cfi;

  /// 锚点所属原 EPUB 的内容摘要。
  final String? contentRevision;

  /// 此次位置来自旧版页号或比例兜底。
  final bool approximate;

  @override
  bool operator ==(Object other) =>
      other is ReaderProgress &&
      other.spineIndex == spineIndex &&
      other.pageIndex == pageIndex &&
      other.finished == finished &&
      other.scrollOffset == scrollOffset &&
      other.cfi == cfi &&
      other.contentRevision == contentRevision &&
      other.approximate == approximate;

  @override
  int get hashCode => Object.hash(
    spineIndex,
    pageIndex,
    finished,
    scrollOffset,
    cfi,
    contentRevision,
    approximate,
  );

  @override
  String toString() =>
      'ReaderProgress($spineIndex,$pageIndex,$finished,$scrollOffset)';
}

/// 阅读进度存储。
abstract interface class ReaderProgressStore {
  /// 读取进度。
  Future<ReaderProgress?> load(String bookId);

  /// 保存进度。
  Future<void> save(String bookId, ReaderProgress progress);

  /// 清除某书进度（删书时调用）。
  Future<void> clear(String bookId);

  /// 全部进度快照（统计页用）。
  Future<Map<String, ReaderProgress>> snapshot();
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

  @override
  Future<void> clear(String bookId) async {
    _items.remove(bookId);
  }

  @override
  Future<Map<String, ReaderProgress>> snapshot() async =>
      Map<String, ReaderProgress>.unmodifiable(_items);
}

/// 章节页来源。
abstract interface class ReaderChapterSource {
  /// 章节数。
  int get chapterCount;

  /// 加载一章的页。
  Future<List<PageContent>> loadChapter(int spineIndex);
}

/// 书签（P4-13）：位置用 CFI 存，重排后仍能定位。
class ReaderBookmark {
  /// 创建书签。
  const ReaderBookmark({
    required this.id,
    required this.cfi,
    required this.spineIndex,
    required this.label,
    required this.createdAt,
    this.relocationStatus,
    this.relocationReason,
    this.currentQuote,
  });

  /// 唯一标识。
  final String id;

  /// 位置 CFI（重排稳定的唯一坐标）。
  final String cfi;

  /// 章节序号（列表排序/展示用，可由 CFI 推导）。
  final int spineIndex;

  /// 展示标签（章节名 + 页码）。
  final String label;

  /// 创建时间。
  final DateTime createdAt;

  /// 跨版本位置的验证状态；待确认记录不得按旧 CFI 直接跳转。
  final String? relocationStatus;
  final String? relocationReason;
  final String? currentQuote;

  bool get needsRelocation =>
      relocationStatus != null &&
      relocationStatus != 'verified' &&
      relocationStatus != 'relocated';
}

/// 支持将历史书签关联到用户指定的新版位置。
abstract interface class RelocatableBookmarkStore {
  Future<void> relocate(String id, {required String cfi});
}

/// 书签存储（P4-13）：阅读页通过它读写书签，app 层用数据库实现。
abstract interface class ReaderBookmarkStore {
  /// 全部书签（按位置排序）。
  Future<List<ReaderBookmark>> list();

  /// 添加书签；同一位置（同 CFI）已存在时不重复添加，返回 null。
  Future<ReaderBookmark?> add({
    required String cfi,
    required int spineIndex,
    required String label,
  });

  /// 删除书签。
  Future<void> remove(String id);
}

/// 能提供目录的章节源（P4-11）：章节数之外的目录树。
abstract interface class TocChapterSource implements ReaderChapterSource {
  /// 目录项（嵌套结构，每项自带目标 spine 序号）。
  List<TocEntry> get toc;
}

/// 目录项 + 层级（P4-11：面板按层级缩进展示）。
typedef TocRow = ({TocEntry entry, int depth});

/// 把目录树展开成线性行（深度优先，depth 从 1 起）。
List<TocRow> flattenToc(List<TocEntry> entries, {int depth = 1}) {
  final rows = <TocRow>[];
  for (final entry in entries) {
    rows.add((entry: entry, depth: depth));
    if (entry.children.isNotEmpty) {
      rows.addAll(flattenToc(entry.children, depth: depth + 1));
    }
  }
  return rows;
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

/// 已准备的翻页目标；准备期间不修改当前页或保存阅读进度。
class PreparedPageTurn {
  const PreparedPageTurn({
    required this.origin,
    required this.target,
    required this.generation,
  });

  final PageContent origin;
  final VirtualPage target;
  final int generation;
}

/// 可应用正文区尺寸的章节源（旋转/窗口变化，P2-31）。
abstract interface class ResizableChapterSource implements ReaderChapterSource {
  /// 应用正文区尺寸及整页到正文的上内缩（含安全区与页眉槽）。
  /// 返回是否真的发生变化，变化后调用方重新加载章节。
  Future<bool> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
  });
}

/// 最小阅读会话：打开/恢复、翻页、保存进度。
class ReaderSession extends ChangeNotifier {
  /// 创建会话。
  ReaderSession({
    required this.source,
    required this.store,
    required this.bookId,
    this.persistInterval = defaultPersistInterval,
    this.contentRevision,
  });

  /// 进度写入节流间隔（P4-10，§76.6）。
  static const Duration defaultPersistInterval = Duration(seconds: 2);

  /// 章节来源。
  final ReaderChapterSource source;

  /// 进度存储。
  final ReaderProgressStore store;

  /// 书籍标识。
  final String bookId;

  /// 原 EPUB 文件的内容摘要，用于拒绝旧会话覆盖新版位置。
  final String? contentRevision;

  /// 进度写入节流间隔：间隔内的连续翻页合并成一次写库。
  final Duration persistInterval;

  VirtualPager? _pager;
  ReaderOverrides _overrides = const ReaderOverrides();
  bool _loading = false;
  int _pageTurns = 0;
  int _charactersRead = 0;

  /// 异步任务代号：取消或开始新任务后，旧任务不再回写状态（P2-27）。
  int _generation = 0;

  /// 版面或外部定位变化时递增，供动画丢弃过期准备结果。
  int get generation => _generation;

  /// 已加载的真实邻页；预热不触发正文重新测量。
  List<PageContent> get adjacentPages => [
    for (final page in _pager?.prefetchedPages ?? const <VirtualPage>[])
      page.content,
  ];

  /// 准备邻页；加载失败交给调用方处理，原页继续可读。
  Future<PreparedPageTurn?> preparePageTurn(bool next) async {
    final pager = _pager;
    final origin = page;
    final generation = _generation;
    if (pager == null || origin == null || _loading) return null;
    final target = await pager.prepareAdjacent(next ? 1 : -1);
    if (_disposed ||
        generation != _generation ||
        !identical(origin, page) ||
        target == null) {
      return null;
    }
    return PreparedPageTurn(
      origin: origin,
      target: target,
      generation: generation,
    );
  }

  /// 视觉收尾完成后提交一次；取消、跳转或重排均使旧目标失效。
  bool commitPageTurn(PreparedPageTurn turn) {
    if (_disposed ||
        turn.generation != _generation ||
        !(_pager?.commitPrepared(turn.origin, turn.target) ?? false)) {
      return false;
    }
    _recordPageTurn(turn.origin);
    _clearScrollPosition();
    _notify();
    _persist();
    return true;
  }

  /// 加载连续滚动所需的一章；复用章节源的排版缓存，不改变当前位置。
  Future<ScrollChapterLayout> loadScrollChapter(int spineIndex) async {
    if (spineIndex < 0 || spineIndex >= source.chapterCount) {
      throw RangeError.index(spineIndex, source, 'spineIndex');
    }
    return ScrollChapterLayout.fromPages(
      spineIndex,
      await source.loadChapter(spineIndex),
    );
  }

  /// 同步连续滚动的页号与页内偏移；页面内容本身不重新分页。
  Future<bool> commitScrollPosition(
    int spineIndex,
    int pageIndex,
    double scrollOffset,
  ) async {
    final pager = _pager;
    if (_disposed || _loading || pager == null) return false;
    final offset = scrollOffset.isFinite
        ? math.max(0.0, scrollOffset).toDouble()
        : 0.0;
    final previous = progress;
    if (previous?.spineIndex == spineIndex &&
        previous?.pageIndex == pageIndex &&
        previous?.scrollOffset == offset) {
      return true;
    }
    final generation = _generation;
    final pageChanged =
        previous?.spineIndex != spineIndex || previous?.pageIndex != pageIndex;
    final origin = page;
    if (pageChanged) {
      final changed = await pager.goTo(spineIndex, pageIndex);
      if (!changed || _disposed || generation != _generation) return false;
    }
    _scrollSpineIndex = spineIndex;
    _scrollPageIndex = pageIndex;
    _scrollOffset = offset;
    _restoredApproximate = false;
    if (pageChanged) {
      _recordPageTurn(origin);
      _notify();
    }
    _persist();
    return true;
  }

  void _clearScrollPosition() {
    _scrollSpineIndex = null;
    _scrollPageIndex = null;
    _scrollOffset = null;
    _restoredApproximate = false;
  }

  double? _contentWidth;
  double? _contentHeight;
  double _contentTopInset = 0;
  _ContentSizeRequest? _pendingContentSize;
  Future<void>? _contentSizeTask;
  _OverrideRequest? _pendingOverride;
  Future<void>? _overridesTask;
  Future<void>? _reloadTask;
  ReaderAnchor? _contentSizePreviewAnchor;
  ReaderProgress? _contentSizePreviewProgress;
  (double?, double?, double)? _contentSizeBeforePreview;

  /// 当前正文区高度（分页依据；测试与诊断用）。
  double? get contentHeight => _contentHeight;
  Object? _error;
  bool _restoredFinished = false;
  // 更新后的未读完进度可能仍落在末页；恢复和重排不能代替真实导航。
  bool _suppressRestoredFinished = false;
  bool _restoredApproximate = false;

  bool get approximateRestoration => _restoredApproximate;
  bool _disposed = false;
  Timer? _persistTimer;
  Future<void>? _persistTask;
  ReaderProgress? _lastPersisted;
  int _persistWrites = 0;
  int _jumpToken = 0;
  String? _jumpLoadingTitle;
  int? _scrollSpineIndex;
  int? _scrollPageIndex;
  double? _scrollOffset;

  /// 已写库次数（节流验收用：连续翻 100 页应 ≤5 次）。
  int get persistWriteCount => _persistWrites;

  /// 本次会话已完成的翻页次数。
  int get pageTurns => _pageTurns;

  /// 本次会话已翻过页面的非空白字符数。
  ///
  /// 按离开页面时的可见文本估算；回翻会重复计入。
  int get charactersRead => _charactersRead;

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
    _pendingContentSize = null;
    _pendingOverride = null;
    _jumpToken += 1;
    _jumpLoadingTitle = null;
    _pager?.cancelPendingNavigation();
    _loading = false;
    _notify();
  }

  /// 打开错误。
  Object? get error => _error;

  /// 当前页。
  PageContent? get page => _pager?.current?.content;

  /// 目录（源不支持目录时为空）。
  List<TocEntry> get toc {
    final source = this.source;
    return source is TocChapterSource ? source.toc : const <TocEntry>[];
  }

  /// 当前视口首个可见行的 CFI（书签/标注锚点用；无 CFI 时返回 null）。
  String? get currentCfi {
    final value = page;
    if (value == null) {
      return null;
    }
    final hit = _hitAtScrollOffset(value);
    final blockCfi = hit?.slice.block.startCfi;
    if (hit != null && blockCfi != null) {
      return cfiWithCharOffset(
        blockCfi,
        (cfiCharOffset(blockCfi) ?? 0) + hit.line.start,
      );
    }
    final anchor = _anchorOf(value);
    final anchorCfi = anchor.cfi;
    if (anchorCfi == null) {
      return null;
    }
    return anchor.charOffset == 0
        ? anchorCfi
        : cfiWithCharOffset(
            anchorCfi,
            (cfiCharOffset(anchorCfi) ?? 0) + anchor.charOffset,
          );
  }

  /// 当前视口首个可见行的文本；没有可定位行时为空。
  String get currentLineText {
    final value = page;
    if (value == null) {
      return '';
    }
    final hit = _hitAtScrollOffset(value) ?? _firstHit(value);
    if (hit == null) {
      return '';
    }
    final text = hit.slice.block.layout.text;
    final start = hit.line.start.clamp(0, text.length);
    final end = hit.line.end.clamp(start, text.length);
    return text.substring(start, end).trim();
  }

  /// 跳到指定 CFI（书签跳转用，P4-13）：解析 spine 后在目标章内定位页。
  ///
  /// 与 [jumpToChapter] 共用 jumpToken 防竞态与跳转浮层。
  Future<bool> jumpToCfi(
    String cfi, {
    String? title,
    bool continuous = false,
  }) async {
    if (_pager == null) {
      return false;
    }
    final parsed = EpubCfi.parse(cfi);
    final spine = parsed == null ? null : spineIndexOfCfi(parsed);
    if (spine == null || spine >= source.chapterCount) {
      return false;
    }
    final token = ++_jumpToken;
    _jumpLoadingTitle = title ?? '书签位置';
    _notify();
    final trace = readerTraceEnabled
        ? ReaderTrace.instance.start(
            ReaderTraceName.chapterJump,
            bookId: bookId,
          )
        : null;
    try {
      if (_loading || _contentSizeTask != null) await _waitForReload();
      if (_disposed || token != _jumpToken) return false;
      _generation += 1;
      _clearScrollPosition();
      final pager = _pager!;
      final origin = pager.current;
      final changed = await pager.goTo(spine, 0);
      if (token != _jumpToken) {
        return false;
      }
      // 章节已分页：按 CFI 定位页号（重排后页号会变，CFI 不变）。
      final pages = await source.loadChapter(spine);
      if (token != _jumpToken) {
        return false;
      }
      final anchor = ReaderAnchor(cfi: cfi);
      final pageIndex = _locatePage(pages, anchor);
      if (pageIndex != 0) {
        await pager.goTo(spine, pageIndex);
        if (token != _jumpToken) {
          return false;
        }
      }
      if (continuous) {
        final layout = ScrollChapterLayout.fromPages(spine, pages);
        for (final segment in layout.segments) {
          if (segment.pageIndex != pageIndex) continue;
          final offset = _scrollOffsetForAnchor(segment.content, anchor);
          if (offset != null) {
            _scrollSpineIndex = spine;
            _scrollPageIndex = pageIndex;
            _scrollOffset = offset;
          }
          break;
        }
        // 连续滚动可能在跳转早期按旧进度完成一次恢复；目标页和页内偏移
        // 确定后再递增一次，确保视图重新读取最终进度。
        _generation += 1;
      }
      final target = pager.current;
      if (origin?.spineIndex != target?.spineIndex ||
          origin?.pageIndex != target?.pageIndex) {
        _suppressRestoredFinished = false;
      }
      _notify();
      _persist();
      return changed || pageIndex != 0;
    } finally {
      trace?.stop();
      if (token == _jumpToken) {
        _jumpLoadingTitle = null;
        _notify();
      }
    }
  }

  /// 当前章全部分页（跨页复制/标注上下文用，P4-19）。
  ///
  /// 页缓存命中时无额外开销；无当前页时返回空列表。
  Future<List<PageContent>> chapterPages() async {
    final current = page;
    if (current == null) {
      return const <PageContent>[];
    }
    return source.loadChapter(current.spineIndex);
  }

  /// 跳转加载中的目标章名（null = 不在跳转中，P4-12 全屏浮层用）。
  String? get jumpLoadingTitle => _jumpLoadingTitle;

  /// 跳转到指定章节首屏（目录点击用，P4-11/P4-12）。
  ///
  /// token 防竞态（§27.1）：每次跳转递增 token，任务完成时比对，与当前
  /// token 不符直接丢弃结果——连续点多个目录项不会出现「后到的旧结果覆盖
  /// 新位置」。跳转期间 [jumpLoadingTitle] 生效，由阅读页显示全屏浮层。
  Future<bool> jumpToChapter(int spineIndex, {String? title}) async {
    if (_pager == null) {
      return false;
    }
    final token = ++_jumpToken;
    _jumpLoadingTitle = title ?? '第 ${spineIndex + 1} 章';
    _notify();
    final trace = readerTraceEnabled
        ? ReaderTrace.instance.start(
            ReaderTraceName.chapterJump,
            bookId: bookId,
          )
        : null;
    try {
      if (_loading || _contentSizeTask != null) await _waitForReload();
      if (_disposed || token != _jumpToken) return false;
      _generation += 1;
      _clearScrollPosition();
      final pager = _pager!;
      final changed = await pager.goTo(
        spineIndex,
        0,
        emptyDirection: spineIndex < (page?.spineIndex ?? 0) ? -1 : 1,
      );
      if (token != _jumpToken) {
        return false;
      }
      if (changed) {
        _suppressRestoredFinished = false;
        _notify();
        _persist();
      }
      return changed;
    } finally {
      trace?.stop();
      if (token == _jumpToken) {
        _jumpLoadingTitle = null;
        _notify();
      }
    }
  }

  /// 重排完成后再导航，避免复用旧分页或让加载状态失去清理者。
  Future<void> _waitForReload() async {
    Future<void>? task;
    do {
      task = _overridesTask ?? _contentSizeTask ?? _reloadTask;
      if (task == null) return;
      await task;
    } while (!_disposed &&
        task != (_overridesTask ?? _contentSizeTask ?? _reloadTask));
    if (!_disposed) _loading = false;
  }

  /// 当前进度。
  ReaderProgress? get progress {
    final current = _pager?.current;
    if (current == null) {
      return null;
    }
    final lastSpineIndex = _lastReadableSpineIndex;
    final lastChapterPages = lastSpineIndex == null
        ? null
        : _pager?.spinePages[lastSpineIndex]?.length;
    final finished =
        _restoredFinished ||
        (!_suppressRestoredFinished &&
            lastChapterPages != null &&
            lastChapterPages > 0 &&
            current.spineIndex == lastSpineIndex &&
            current.pageIndex >= lastChapterPages - 1);
    return ReaderProgress(
      spineIndex: current.spineIndex,
      pageIndex: current.pageIndex,
      finished: finished,
      cfi: contentRevision == null ? null : currentCfi,
      contentRevision: contentRevision,
      approximate: _restoredApproximate,
      scrollOffset:
          current.spineIndex == _scrollSpineIndex &&
              current.pageIndex == _scrollPageIndex
          ? _scrollOffset
          : null,
    );
  }

  /// 末尾章节可能为空，只有向后导航到书尾时才全部加载。
  int? get _lastReadableSpineIndex {
    final pages = _pager?.spinePages ?? const <int, List<PageContent>>{};
    for (var index = source.chapterCount - 1; index >= 0; index--) {
      final chapter = pages[index];
      if (chapter == null) {
        return null;
      }
      if (chapter.isNotEmpty) {
        return index;
      }
    }
    return null;
  }

  /// 当前虚拟页号。
  int get currentVirtualPage => _pager?.currentVirtualPage ?? 0;

  /// 已映射页数。
  int get mappedPageCount => _pager?.mappedPageCount ?? 0;

  /// 当前章页数（P8-10 页家具；章未加载为 0）。
  int get chapterPageCount {
    final current = page;
    if (current == null) {
      return 0;
    }
    return _pager?.spinePages[current.spineIndex]?.length ?? 0;
  }

  /// 已加载章节的页数，供目标纸面页眉和跨章预热使用。
  int pageCountOf(int spineIndex) =>
      _pager?.spinePages[spineIndex]?.length ?? 0;

  /// 当前页文本（用于测试/无障碍）。
  String get currentText => _textOf(page);

  static String _textOf(PageContent? value) {
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

  void _recordPageTurn(PageContent? origin) {
    _suppressRestoredFinished = false;
    _restoredApproximate = false;
    _pageTurns += 1;
    _charactersRead += _textOf(origin)
        .replaceAll(RegExp(r'\s+'), '')
        .runes
        .length;
  }

  /// 打开并恢复进度。
  Future<void> open({
    ReaderOverrides? overrides,
    double? contentWidth,
    double? contentHeight,
    double contentTopInset = 0,
  }) async {
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
      await _prepareInitialLayout(
        overrides,
        contentWidth,
        contentHeight,
        contentTopInset,
      );
      if (generation != _generation) return;
      final saved = await store.load(bookId);
      if (generation != _generation) return;
      final sameRevision = saved?.contentRevision == contentRevision;
      final legacyProgress = saved?.contentRevision == null;
      final usableCache = sameRevision || legacyProgress;
      _restoredFinished = usableCache && (saved?.finished ?? false);
      _suppressRestoredFinished = saved != null && !saved.finished;
      final pager = VirtualPager(
        spineCount: source.chapterCount,
        loader: source.loadChapter,
      );
      await pager.initialize(
        startSpine: usableCache ? saved?.spineIndex ?? 0 : 0,
        startPage: usableCache ? saved?.pageIndex ?? 0 : 0,
      );
      if (generation != _generation) return;
      _pager = pager;
      _clearScrollPosition();
      final savedCfi = sameRevision ? saved?.cfi : null;
      if (savedCfi != null) {
        await _restoreCfi(
          pager,
          savedCfi,
          generation,
          continuous: saved?.scrollOffset != null,
          preferredPageIndex: sameRevision ? saved?.pageIndex : null,
        );
        if (generation != _generation) return;
      } else if (saved?.scrollOffset != null && usableCache) {
        _scrollSpineIndex = saved!.spineIndex;
        _scrollPageIndex = saved.pageIndex;
        _scrollOffset = saved.scrollOffset;
      }
      _restoredApproximate =
          (saved?.approximate ?? false) || (saved != null && !usableCache);
      _loading = false;
      // 恢复出来的位置不算「变化」，直接记为已持久化值，避免打开就回写。
      _lastPersisted = progress;
      _notify();
    } catch (error) {
      if (generation != _generation) {
        return;
      }
      _error = error;
      _loading = false;
      _notify();
    }
  }

  Future<void> _restoreCfi(
    VirtualPager pager,
    String cfi,
    int generation, {
    bool continuous = false,
    int? preferredPageIndex,
  }) async {
    final parsed = EpubCfi.parse(cfi);
    final spine = parsed == null ? null : spineIndexOfCfi(parsed);
    if (spine == null || spine < 0 || spine >= source.chapterCount) return;
    final pages = await source.loadChapter(spine);
    if (_disposed || generation != _generation) return;
    final anchor = ReaderAnchor(cfi: cfi);
    final index =
        preferredPageIndex != null &&
            preferredPageIndex >= 0 &&
            preferredPageIndex < pages.length &&
            _pageContainsAnchor(pages[preferredPageIndex], anchor)
        ? preferredPageIndex
        : _locatePage(pages, anchor);
    await pager.goTo(spine, index);
    if (_disposed || generation != _generation || !continuous) return;
    final layout = ScrollChapterLayout.fromPages(spine, pages);
    for (final segment in layout.segments) {
      if (segment.pageIndex != index) continue;
      _scrollSpineIndex = spine;
      _scrollPageIndex = index;
      _scrollOffset = _scrollOffsetForAnchor(segment.content, anchor);
      break;
    }
  }

  /// 第一章排版之前应用最终设置与尺寸，避免首屏出现后再立即重排。
  Future<void> _prepareInitialLayout(
    ReaderOverrides? overrides,
    double? width,
    double? height,
    double topInset,
  ) async {
    final src = source;
    if (overrides != null) {
      _overrides = overrides;
      if (src is RestylableChapterSource) await src.applyOverrides(overrides);
    }
    if (width != null && height != null) {
      _contentWidth = width;
      _contentHeight = height;
      _contentTopInset = topInset;
      if (src is ResizableChapterSource) {
        await src.applyContentSize(
          width: width,
          height: height,
          topInset: topInset,
        );
      }
    }
  }

  /// 下一页。
  Future<bool> next() async {
    final pager = _pager;
    if (pager == null) {
      return false;
    }
    final generation = _generation;
    final origin = page;
    final changed = await pager.next();
    if (changed && generation == _generation) {
      _recordPageTurn(origin);
      _notify();
      _persist();
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
    final origin = page;
    final changed = await pager.previous();
    if (changed && generation == _generation) {
      _recordPageTurn(origin);
      _notify();
      _persist();
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
      final cfi = _firstCfi(slice.block);
      if (cfi != null && cfi.isNotEmpty) {
        return ReaderAnchor(cfi: cfi, charOffset: _lineStartOffset(slice));
      }
    }
    for (final slice in page?.slices ?? const <PageBlockSlice>[]) {
      final cfi = _firstCfi(slice.block);
      if (cfi != null && cfi.isNotEmpty) {
        return ReaderAnchor(cfi: cfi, charOffset: _lineStartOffset(slice));
      }
    }
    return const ReaderAnchor();
  }

  static String? _firstCfi(PageBlock block) {
    final table = block.table;
    if (table == null) return block.startCfi;
    for (final cell in table.cells) {
      if (cell.startCfi != null) return cell.startCfi;
    }
    return block.startCfi;
  }

  static int _lineStartOffset(PageBlockSlice slice) {
    final layout = slice.block.layout;
    if (slice.startLine < 0 || slice.startLine >= layout.lines.length) {
      return 0;
    }
    return layout.lines[slice.startLine].start;
  }

  /// 应用阅读器设置：指纹变化时重排章节并按锚点恢复位置（§21、§17.4）。
  ///
  /// 连续滑动期间只保留最新设置；在途旧排版由 generation 丢弃，避免每个
  /// 滑块步进都完整测量一次当前章。
  Future<void> applyOverrides(ReaderOverrides next) {
    if (_disposed) return Future.value();
    final src = source;
    if (src is! RestylableChapterSource) {
      if (next.fingerprint != _overrides.fingerprint) {
        _overrides = next;
        _notify();
      }
      return Future.value();
    }
    final pending = _pendingOverride;
    if ((_overridesTask != null &&
            next.fingerprint == _overrides.fingerprint) ||
        (pending != null &&
            next.fingerprint == pending.overrides.fingerprint)) {
      return _overridesTask ?? Future.value();
    }
    if (_overridesTask == null && next.fingerprint == _overrides.fingerprint) {
      _overrides = next;
      return Future.value();
    }
    _pendingOverride = (overrides: next, generation: ++_generation);
    _pager?.cancelPendingNavigation();
    return _overridesTask ??= _drainOverrides();
  }

  Future<void> _drainOverrides() async {
    try {
      while (!_disposed && _pendingOverride != null) {
        final request = _pendingOverride!;
        _pendingOverride = null;
        final currentPage = _pager?.current?.content;
        final spine = currentPage?.spineIndex ?? 0;
        final anchor = _anchorOf(currentPage);
        _overrides = request.overrides;
        final src = source;
        if (src is! RestylableChapterSource) {
          _notify();
          continue;
        }
        await (_reloadTask = _reloadChapter(
          generation: request.generation,
          spine: spine,
          anchor: anchor,
          prepare: () => src.applyOverrides(request.overrides),
        ));
      }
    } finally {
      _overridesTask = null;
    }
  }

  /// 字体装饰改变度量后重载分页，并按保存的原文 CFI 回位。
  Future<bool> refreshLayout({String? anchorCfi}) async {
    final current = page;
    if (_disposed || current == null) return false;
    final generation = ++_generation;
    final anchor = anchorCfi == null
        ? _anchorOf(current)
        : ReaderAnchor(cfi: anchorCfi);
    await (_reloadTask = _reloadChapter(
      generation: generation,
      spine: current.spineIndex,
      anchor: anchor,
    ));
    return generation == _generation && _error == null;
  }

  /// 应用新的正文区尺寸（旋转/窗口变化，P2-31）。
  ///
  /// 只重排当前章，其他章仍在导航到该章时加载；在途请求合并到最新尺寸。
  /// [preview] 期间固定阅读锚点且不保存临时页码，退出预览时再提交位置。
  Future<void> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
    bool preview = false,
  }) {
    if (_disposed) return Future.value();
    _pendingContentSize = (
      width: width,
      height: height,
      topInset: topInset,
      preview: preview,
    );
    return _contentSizeTask ??= _drainContentSizes();
  }

  Future<void> _drainContentSizes() async {
    try {
      while (!_disposed && _pendingContentSize != null) {
        final next = _pendingContentSize!;
        _pendingContentSize = null;
        try {
          await _applyContentSize(next);
        } catch (error) {
          _error = error;
          _notify();
        }
      }
    } finally {
      _contentSizeTask = null;
    }
  }

  Future<void> _applyContentSize(_ContentSizeRequest next) async {
    final currentPage = _pager?.current?.content;
    if (next.preview && _contentSizePreviewAnchor == null) {
      _contentSizePreviewAnchor = _anchorOf(currentPage);
      _contentSizePreviewProgress = progress;
      _contentSizeBeforePreview = (
        _contentWidth,
        _contentHeight,
        _contentTopInset,
      );
    }
    final anchor = _contentSizePreviewAnchor ?? _anchorOf(currentPage);
    if (_contentWidth == next.width &&
        _contentHeight == next.height &&
        _contentTopInset == next.topInset &&
        _error == null) {
      if (!next.preview) _finishContentSizePreview();
      return;
    }
    final src = source;
    if (src is! ResizableChapterSource) {
      _setContentSize(next);
      if (!next.preview) _finishContentSizePreview();
      return;
    }
    await _resizeCurrentChapter(src, next, anchor);
  }

  Future<void> _resizeCurrentChapter(
    ResizableChapterSource src,
    _ContentSizeRequest next,
    ReaderAnchor anchor,
  ) async {
    final spine = page?.spineIndex ?? 0;
    final generation = ++_generation;
    final changed = await src.applyContentSize(
      width: next.width,
      height: next.height,
      topInset: next.topInset,
    );
    if (generation != _generation) return;
    _setContentSize(next);
    if (changed || _error != null) {
      final original = _contentSizePreviewProgress;
      // 原尺寸直接恢复原页号，避免锚点恰在页边界时退到前一页。
      final restoresOriginalSize =
          (next.width, next.height, next.topInset) == _contentSizeBeforePreview;
      await (_reloadTask = _reloadChapter(
        generation: generation,
        spine: spine,
        anchor: anchor,
        pageIndex: restoresOriginalSize && original?.spineIndex == spine
            ? original?.pageIndex
            : null,
      ));
    }
    if (generation != _generation || _error != null) return;
    if (!next.preview) _finishContentSizePreview();
  }

  void _setContentSize(_ContentSizeRequest next) {
    _contentWidth = next.width;
    _contentHeight = next.height;
    _contentTopInset = next.topInset;
  }

  void _finishContentSizePreview() {
    if (_contentSizePreviewAnchor == null) return;
    _contentSizePreviewAnchor = null;
    _contentSizePreviewProgress = null;
    _contentSizeBeforePreview = null;
    _persist();
  }

  /// 重载当前章节并回到锚点；失败时不丢弃旧页（避免闪空白）。
  Future<void> _reloadChapter({
    required int generation,
    required int spine,
    required ReaderAnchor anchor,
    Future<void> Function()? prepare,
    int? pageIndex,
  }) async {
    _clearScrollPosition();
    _pager?.cancelPendingNavigation();
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
        loader: (index) =>
            index == spine ? Future.value(pages) : source.loadChapter(index),
      );
      await pager.initialize(
        startSpine: spine,
        startPage: pageIndex ?? _locatePage(pages, anchor),
      );
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
        _persist();
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
    final parsedTarget = cfi == null ? null : EpubCfi.parse(cfi);
    if (parsedTarget == null) {
      return pages.first.pageIndex;
    }
    final target = parsedTarget.rangeStart ?? parsedTarget;
    final targetPath = _cfiPath(target);
    for (final page in pages) {
      if (_pageContainsAnchor(page, anchor)) {
        return page.pageIndex;
      }
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
        final comparison = _cfiPath(parsed).compareTo(targetPath);
        if (comparison == 0) {
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

  static bool _pageContainsAnchor(PageContent page, ReaderAnchor anchor) {
    final cfi = anchor.cfi;
    final parsedTarget = cfi == null ? null : EpubCfi.parse(cfi);
    if (parsedTarget == null) return false;
    final target = parsedTarget.rangeStart ?? parsedTarget;
    final targetPath = _cfiPath(target);
    final targetOffset = (target.segments.last.offset ?? 0) + anchor.charOffset;
    for (final slice in page.slices) {
      if (_tableContainsCfi(slice.block, targetPath, targetOffset)) {
        return true;
      }
      final value = slice.block.startCfi;
      final parsed = value == null ? null : EpubCfi.parse(value);
      if (parsed == null || _cfiPath(parsed).compareTo(targetPath) != 0) {
        continue;
      }
      final offset = targetOffset - (parsed.segments.last.offset ?? 0);
      if (_sliceContainsOffset(slice, offset)) {
        return true;
      }
    }
    return false;
  }

  static EpubCfi _cfiPath(EpubCfi cfi) =>
      cfi.withCharOffset(0).copyWithSide(CfiSide.none);

  static bool _tableContainsCfi(PageBlock block, EpubCfi path, int offset) {
    final table = block.table;
    if (table == null) return false;
    for (final cell in table.cells) {
      final parsed = cell.startCfi == null
          ? null
          : EpubCfi.parse(cell.startCfi!);
      if (parsed == null || _cfiPath(parsed).compareTo(path) != 0) continue;
      final local = offset - (parsed.segments.last.offset ?? 0);
      // 单元格是不可分文本载荷，行内盒文字不在 layout.text 中；路径精确
      // 命中后，格内偏移不会改变所在页，不能用空占位串长度拒绝它。
      if (local >= 0) return true;
    }
    return false;
  }

  static bool _sliceContainsOffset(PageBlockSlice slice, int offset) {
    return _lineIndexForOffset(slice, offset) != null;
  }

  static int? _lineIndexForOffset(PageBlockSlice slice, int offset) {
    final layout = slice.block.layout;
    final last = math.min(slice.endLine, layout.lines.length);
    for (var i = slice.startLine; i < last; i++) {
      final line = layout.lines[i];
      if (offset >= line.start &&
          (offset < line.end ||
              line.start == line.end && offset == line.start ||
              offset == layout.text.length && offset == line.end)) {
        return i;
      }
    }
    return null;
  }

  PageHit? _hitAtScrollOffset(PageContent page) {
    final offset = _scrollOffset;
    if (offset == null) {
      return null;
    }
    final top = page.topPadding;
    final bottom = math.max(top, page.topPadding + page.usedHeight - 0.5);
    // 滚动位置会把行首坐标量化到略小于理论值；不加容差时正好落在
    // 上一行的半开区间末尾，书签/标注会锚到上一行。
    final y = (offset + 0.01).clamp(top, bottom).toDouble();
    return page.hitTest(Offset(0, y));
  }

  static PageHit? _firstHit(PageContent page) {
    for (var sliceIndex = 0; sliceIndex < page.slices.length; sliceIndex++) {
      final slice = page.slices[sliceIndex];
      if (slice.overlay || slice.startLine >= slice.endLine) {
        continue;
      }
      final lineIndex = slice.startLine.clamp(
        0,
        slice.block.layout.lines.length - 1,
      );
      if (lineIndex < 0 || lineIndex >= slice.block.layout.lines.length) {
        continue;
      }
      return PageHit(
        sliceIndex: sliceIndex,
        slice: slice,
        lineIndex: lineIndex,
        line: slice.block.layout.lines[lineIndex],
      );
    }
    return null;
  }

  /// 目标行相对连续滚动页切片顶部的偏移；无法精确定位时回退页首。
  static double? _scrollOffsetForAnchor(PageContent page, ReaderAnchor anchor) {
    final cfi = anchor.cfi;
    final parsedTarget = cfi == null ? null : EpubCfi.parse(cfi);
    if (parsedTarget == null) {
      return null;
    }
    final target = parsedTarget.rangeStart ?? parsedTarget;
    final targetPath = _cfiPath(target);
    final targetOffset = (target.segments.last.offset ?? 0) + anchor.charOffset;
    var flowY = page.topPadding;
    for (final slice in page.slices) {
      final sliceTop = slice.overlay ? (slice.absoluteTop ?? flowY) : flowY;
      final baseCfi = slice.block.startCfi;
      final parsedBase = baseCfi == null ? null : EpubCfi.parse(baseCfi);
      if (parsedBase != null &&
          _cfiPath(parsedBase).compareTo(targetPath) == 0) {
        final localOffset =
            targetOffset - (parsedBase.segments.last.offset ?? 0);
        final lineIndex = _lineIndexForOffset(slice, localOffset);
        if (lineIndex != null) {
          var lineY = sliceTop + slice.leadingExtent;
          for (var i = slice.startLine; i < lineIndex; i++) {
            lineY += slice.block.layout.lines[i].height;
          }
          return math.max(0.0, lineY);
        }
      }
      if (!slice.overlay) {
        flowY += slice.height;
      }
    }
    return null;
  }

  /// 调度进度写入（P4-10）：值变化才写，2 秒内的多次翻页合并成一次。
  ///
  /// 首次变化立即落盘（leading），避免「翻一页就退出」的短会话丢进度；
  /// 之后的连续变化走 trailing 合并。
  void _persist() {
    final value = _progressToPersist;
    if (value == null || value == _lastPersisted) {
      return;
    }
    if (_lastPersisted == null) {
      _flushProgress().ignore();
      return;
    }
    _persistTimer?.cancel();
    _persistTimer = Timer(persistInterval, () => _flushProgress().ignore());
  }

  /// 立即落盘（生命周期切后台/退出阅读页/强杀前调用）。
  Future<void> flushProgress() => _flushProgress();

  ReaderProgress? get _progressToPersist =>
      _contentSizePreviewProgress ?? progress;

  Future<void> _flushProgress() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    while (_persistTask != null) {
      try {
        await _persistTask;
      } catch (_) {
        // 上一轮失败仍保留待保存位置，本次落盘继续重试。
      }
    }
    final value = _progressToPersist;
    if (value == null || value == _lastPersisted) {
      return;
    }
    final task = store.save(bookId, value);
    _persistTask = task;
    try {
      await task;
      _lastPersisted = value;
      _persistWrites += 1;
    } finally {
      _persistTask = null;
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
    _pendingContentSize = null;
    _pendingOverride = null;
    _jumpToken += 1;
    _pager?.cancelPendingNavigation();
    // 退出前把最后一次进度写下去（P4-10：不依赖节流定时器）。
    _flushProgress().ignore();
    _persistTimer?.cancel();
    _persistTimer = null;
    _disposed = true;
    super.dispose();
  }
}
