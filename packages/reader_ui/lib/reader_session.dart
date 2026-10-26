import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/perf/trace.dart';
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
    this.persistInterval = defaultPersistInterval,
  });

  /// 进度写入节流间隔（P4-10，§76.6）。
  static const Duration defaultPersistInterval = Duration(seconds: 2);

  /// 章节来源。
  final ReaderChapterSource source;

  /// 进度存储。
  final ReaderProgressStore store;

  /// 书籍标识。
  final String bookId;

  /// 进度写入节流间隔：间隔内的连续翻页合并成一次写库。
  final Duration persistInterval;

  VirtualPager? _pager;
  ReaderOverrides _overrides = const ReaderOverrides();
  bool _loading = false;

  /// 异步任务代号：取消或开始新任务后，旧任务不再回写状态（P2-27）。
  int _generation = 0;

  double? _contentWidth;
  double? _contentHeight;

  /// 当前正文区高度（分页依据；测试与诊断用）。
  double? get contentHeight => _contentHeight;
  Object? _error;
  bool _disposed = false;
  Timer? _persistTimer;
  ReaderProgress? _lastPersisted;
  int _persistWrites = 0;
  int _jumpToken = 0;
  String? _jumpLoadingTitle;

  /// 已写库次数（节流验收用：连续翻 100 页应 ≤5 次）。
  int get persistWriteCount => _persistWrites;

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

  /// 目录（源不支持目录时为空）。
  List<TocEntry> get toc {
    final source = this.source;
    return source is TocChapterSource
        ? source.toc
        : const <TocEntry>[];
  }

  /// 当前页首个块的 CFI（书签/标注锚点用；无 CFI 时返回 null）。
  String? get currentCfi => _anchorOf(page).cfi;

  /// 跳到指定 CFI（书签跳转用，P4-13）：解析 spine 后在目标章内定位页。
  ///
  /// 与 [jumpToChapter] 共用 jumpToken 防竞态与跳转浮层。
  Future<bool> jumpToCfi(String cfi, {String? title}) async {
    final pager = _pager;
    if (pager == null) {
      return false;
    }
    final parsed = EpubCfi.parse(cfi);
    final spine = parsed == null ? null : spineIndexOfCfi(parsed);
    if (spine == null || spine >= source.chapterCount) {
      return false;
    }
    final token = ++_jumpToken;
    _generation += 1;
    _jumpLoadingTitle = title ?? '书签位置';
    _notify();
    final trace = readerTraceEnabled
        ? ReaderTrace.instance.start(ReaderTraceName.chapterJump, bookId: bookId)
        : null;
    try {
      final changed = await pager.goTo(spine, 0);
      if (token != _jumpToken) {
        return false;
      }
      // 章节已分页：按 CFI 定位页号（重排后页号会变，CFI 不变）。
      final pages = await source.loadChapter(spine);
      if (token != _jumpToken) {
        return false;
      }
      final pageIndex = _locatePage(pages, ReaderAnchor(cfi: cfi));
      if (pageIndex != 0) {
        await pager.goTo(spine, pageIndex);
        if (token != _jumpToken) {
          return false;
        }
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
    final pager = _pager;
    if (pager == null) {
      return false;
    }
    final token = ++_jumpToken;
    // 跳转优先：让进行中的翻页/重排结果作废，避免旧结果回写。
    _generation += 1;
    _jumpLoadingTitle = title ?? '第 ${spineIndex + 1} 章';
    _notify();
    final trace = readerTraceEnabled
        ? ReaderTrace.instance.start(ReaderTraceName.chapterJump, bookId: bookId)
        : null;
    try {
      final changed = await pager.goTo(spineIndex, 0);
      if (token != _jumpToken) {
        return false;
      }
      if (changed) {
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

  /// 当前章页数（P8-10 页家具；章未加载为 0）。
  int get chapterPageCount {
    final current = page;
    if (current == null) {
      return 0;
    }
    return _pager?.spinePages[current.spineIndex]?.length ?? 0;
  }

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
    final changed = await pager.previous();
    if (changed && generation == _generation) {
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

  /// 调度进度写入（P4-10）：值变化才写，2 秒内的多次翻页合并成一次。
  ///
  /// 首次变化立即落盘（leading），避免「翻一页就退出」的短会话丢进度；
  /// 之后的连续变化走 trailing 合并。
  void _persist() {
    final value = progress;
    if (value == null || value == _lastPersisted) {
      return;
    }
    if (_lastPersisted == null) {
      unawaited(_flushProgress());
      return;
    }
    _persistTimer?.cancel();
    _persistTimer = Timer(persistInterval, () => unawaited(_flushProgress()));
  }

  /// 立即落盘（生命周期切后台/退出阅读页/强杀前调用）。
  Future<void> flushProgress() => _flushProgress();

  Future<void> _flushProgress() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    final value = progress;
    if (value == null || value == _lastPersisted) {
      return;
    }
    _lastPersisted = value;
    _persistWrites += 1;
    await store.save(bookId, value);
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _generation += 1; // 丢弃未完成任务
    // 退出前把最后一次进度写下去（P4-10：不依赖节流定时器）。
    final value = progress;
    if (value != null && value != _lastPersisted) {
      _lastPersisted = value;
      _persistWrites += 1;
      unawaited(store.save(bookId, value));
    }
    _persistTimer?.cancel();
    _persistTimer = null;
    _disposed = true;
    super.dispose();
  }
}
