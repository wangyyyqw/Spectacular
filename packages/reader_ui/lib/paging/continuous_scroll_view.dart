import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/scroll_layout.dart';

import '../reader_session.dart';
import 'page_turn_mode.dart';

/// 连续滚动的纸面构建器。
typedef ScrollPaperBuilder = Widget Function(PageContent page, Size size);

/// 按章懒构建的连续阅读视口。
///
/// 每个列表项是一页经过空白压缩后的切片，项与项首尾相接。分页只用于提供
/// 已测量的块与行，滚动本身不触发正文重排。
class ContinuousScrollView extends StatefulWidget {
  const ContinuousScrollView({
    super.key,
    required this.session,
    required this.paperBuilder,
    required this.padding,
    required this.revision,
    this.onPageVisible,
    this.onTapAtPage,
    this.onUserScroll,
  });

  final ReaderSession session;
  final ScrollPaperBuilder paperBuilder;
  final EdgeInsets padding;
  final Object revision;
  final ValueChanged<PageContent>? onPageVisible;

  final bool Function(PageContent page, Offset localPosition)? onTapAtPage;
  final VoidCallback? onUserScroll;

  @override
  State<ContinuousScrollView> createState() => ContinuousScrollViewState();
}

/// 连续滚动状态；阅读页通过它响应点击区的前后屏移动。
class ContinuousScrollViewState extends State<ContinuousScrollView> {
  final ScrollController _controller = ScrollController();
  final List<ScrollChapterLayout> _chapters = <ScrollChapterLayout>[];
  final List<_ScrollEntry> _entries = <_ScrollEntry>[];
  final Map<(int, int), GlobalKey> _pageKeys = <(int, int), GlobalKey>{};
  Timer? _syncTimer;
  PageContent? _visibleContent;
  double _visiblePageOffset = 0;
  bool _loading = true;
  bool _extendingBefore = false;
  bool _insertingBefore = false;
  bool _extendingAfter = false;
  bool _trimmingWindow = false;
  Future<void>? _extendBeforeTask;
  Future<void>? _extendAfterTask;
  int _loadToken = 0;
  int _restoreToken = 0;
  int? _windowReloadGeneration;
  late int _layoutGeneration;
  late final ReaderViewportSnapshot? Function() _viewportSnapshotProvider =
      _snapshotForSession;
  Object? _error;
  bool _restoring = false;
  bool _programmaticJump = false;
  bool _userDragging = false;
  bool _hasUserScrollSinceRestore = false;
  bool _windowAtBookEnd = false;

  @override
  void initState() {
    super.initState();
    _layoutGeneration = widget.session.generation;
    widget.session.registerViewportSnapshotProvider(_viewportSnapshotProvider);
    _controller.addListener(_handleScroll);
    unawaited(_loadInitialWindow());
  }

  @override
  void didUpdateWidget(ContinuousScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        _layoutGeneration != widget.session.generation) {
      if (oldWidget.session != widget.session) {
        oldWidget.session.unregisterViewportSnapshotProvider(
          _viewportSnapshotProvider,
        );
        widget.session.registerViewportSnapshotProvider(
          _viewportSnapshotProvider,
        );
      }
      _scheduleWindowReload(widget.session.generation);
    }
  }

  void _scheduleWindowReload(int generation) {
    if (_windowReloadGeneration == generation) return;
    _windowReloadGeneration = generation;
    _loadToken += 1;
    _restoreToken += 1;
    _syncTimer?.cancel();
    unawaited(_reloadWindowAfterLayout(generation));
  }

  Future<void> _reloadWindowAfterLayout(int generation) async {
    await widget.session.waitForPendingLayout();
    if (!mounted ||
        generation != _windowReloadGeneration ||
        generation != widget.session.generation) {
      return;
    }
    _windowReloadGeneration = null;
    await _loadInitialWindow();
  }

  Future<void> _loadInitialWindow() async {
    final token = ++_loadToken;
    await widget.session.waitForPendingLayout();
    if (!mounted || token != _loadToken) return;
    final generation = widget.session.generation;
    final progress = widget.session.progress;
    final center = progress?.spineIndex ?? 0;
    final loaded = <ScrollChapterLayout>[];
    var atBookEnd = false;
    try {
      final pivot =
          await _findReadable(center, direction: 1) ??
          await _findReadable(center - 1, direction: -1);
      if (pivot == null) {
        if (!mounted || token != _loadToken) return;
        setState(() {
          _loading = false;
          _error = StateError('全书没有可读章节');
        });
        return;
      }
      loaded.add(pivot);
      atBookEnd = pivot.spineIndex == widget.session.source.chapterCount - 1;
    } on ChapterLoadCancelled {
      return;
    } catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _error = error;
      });
      return;
    }
    if (!mounted ||
        token != _loadToken ||
        generation != widget.session.generation) {
      return;
    }
    loaded.sort((left, right) => left.spineIndex.compareTo(right.spineIndex));
    _syncTimer?.cancel();
    setState(() {
      _layoutGeneration = generation;
      _chapters
        ..clear()
        ..addAll(loaded);
      _error = null;
      _loading = false;
      _visibleContent = null;
      _hasUserScrollSinceRestore = false;
      _windowAtBookEnd = atBookEnd;
      _rebuildEntries();
    });
    await WidgetsBinding.instance.endOfFrame;
    if (_isCurrentWindow(token, generation)) {
      _jumpToReadingPosition(progress);
    }
  }

  bool _isCurrentWindow(int token, int generation) =>
      mounted &&
      token == _loadToken &&
      generation == _layoutGeneration &&
      generation == widget.session.generation;

  /// 读取一段可读章节；缺失章返回空布局，未知异常由调用方按错误处理。
  Future<ScrollChapterLayout?> _findReadable(
    int start, {
    required int direction,
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
  }) async {
    final count = widget.session.source.chapterCount;
    for (var spine = start; spine >= 0 && spine < count; spine += direction) {
      final source = widget.session.source;
      if (source is MissingChapterSource && source.isChapterMissing(spine)) {
        continue;
      }
      final layout = await widget.session.loadScrollChapter(
        spine,
        priority: priority,
      );
      if (!layout.isEmpty) return layout;
    }
    return null;
  }

  void _rebuildEntries() {
    _entries.clear();
    var top = 0.0;
    for (final chapter in _chapters) {
      for (final segment in chapter.segments) {
        _entries.add(_ScrollEntry(chapter, segment, top));
        top += segment.extent;
      }
    }
  }

  double get _contentExtent =>
      _entries.isEmpty ? 0 : _entries.last.top + _entries.last.segment.extent;

  double _chapterTop(int spineIndex) {
    var top = 0.0;
    for (final chapter in _chapters) {
      if (chapter.spineIndex >= spineIndex) break;
      top += chapter.extent;
    }
    return top;
  }

  void _jumpToReadingPosition(ReaderProgress? progress) {
    if (!_controller.hasClients) return;
    final desired = progress?.spineIndex ?? 0;
    final spine =
        _chapters
            .where((item) => item.spineIndex >= desired)
            .firstOrNull
            ?.spineIndex ??
        _chapters.lastOrNull?.spineIndex ??
        0;
    final page = spine == progress?.spineIndex ? progress?.pageIndex ?? 0 : 0;
    final offsetInPage = spine == progress?.spineIndex
        ? progress?.scrollOffset ?? 0
        : 0.0;
    final chapter = _chapters
        .where((item) => item.spineIndex == spine)
        .firstOrNull;
    if (chapter == null) return;
    final pageStart = chapter.offsetOfPage(page);
    final pageExtent = math.max(
      0.0,
      chapter.offsetOfPage(page + 1) - pageStart,
    );
    final pageOffset = offsetInPage.clamp(0.0, pageExtent).toDouble();
    final offset =
        widget.padding.top + _chapterTop(spine) + pageStart + pageOffset;
    _restoring = true;
    final token = ++_restoreToken;
    _jumpProgrammatically(
      offset.clamp(0.0, _controller.position.maxScrollExtent),
    );
    unawaited(_settleAtReadingPosition(progress, token));
  }

  /// 等目标页真正布局后，用它的实际位置校正滚动偏移。
  ///
  /// ListView 对可变高度子项的估算会在前方插入章节后产生误差，预先按
  /// extent 算出的像素偏移因此可能偏几行；这里以渲染盒位置为准。
  Future<void> _settleAtReadingPosition(
    ReaderProgress? progress,
    int token,
  ) async {
    final loadToken = _loadToken;
    final generation = _layoutGeneration;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!_isCurrentWindow(loadToken, generation) ||
            !_controller.hasClients ||
            token != _restoreToken) {
          return;
        }
        final spine =
            progress?.spineIndex ?? _chapters.firstOrNull?.spineIndex ?? 0;
        final page = progress?.pageIndex ?? 0;
        if (!_revealAtPage(spine, page, progress?.scrollOffset ?? 0)) {
          continue;
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!_isCurrentWindow(loadToken, generation) ||
            token != _restoreToken) {
          return;
        }
        _captureVisiblePage(commit: false);
        return;
      }
    } finally {
      if (_isCurrentWindow(loadToken, generation) && token == _restoreToken) {
        // 程序恢复只校正视口，不把“可见页首”反写成用户阅读位置；
        // 书尾因内容不足无法置顶时尤其不能覆盖已保存的精确偏移。
        _captureVisiblePage(commit: false, stage: false);
        _restoring = false;
        unawaited(_extendBefore());
        unawaited(_extendAfter());
        _maybeExtendWindow();
      }
    }
  }

  _ScrollEntry? _entryForPage(int spine, int page) {
    for (final entry in _entries) {
      if (entry.chapter.spineIndex == spine &&
          entry.segment.pageIndex == page) {
        return entry;
      }
    }
    return null;
  }

  RenderBox? _boxOf(_ScrollEntry entry) {
    final key = _pageKeys[(entry.chapter.spineIndex, entry.segment.pageIndex)];
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    return box;
  }

  double? _revealOffset(RenderBox box) {
    try {
      return RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    } catch (_) {
      return null;
    }
  }

  /// 按页号与页内偏移定位；页必须已经构建，否则返回 false 等下一帧。
  bool _revealAtPage(int spine, int page, double pageOffset) {
    if (!_controller.hasClients) {
      return false;
    }
    final entry = _entryForPage(spine, page);
    final box = entry == null ? null : _boxOf(entry);
    if (entry == null || box == null) {
      return false;
    }
    final top = _revealOffset(box);
    if (top == null) {
      return false;
    }
    final target = top + pageOffset.clamp(0.0, entry.segment.extent);
    final corrected = target.clamp(0.0, _controller.position.maxScrollExtent);
    if ((_controller.offset - corrected).abs() <= 0.5) {
      return true;
    }
    _jumpProgrammatically(corrected);
    return true;
  }

  void _jumpProgrammatically(double offset) {
    _programmaticJump = true;
    try {
      _controller.jumpTo(offset);
    } finally {
      _programmaticJump = false;
    }
  }

  void _handleScroll() {
    if (!_controller.hasClients) return;
    _captureVisiblePage();
    if (!_restoring) {
      _maybeExtendWindow();
      _trimWindow();
    }
  }

  void _captureVisiblePage({bool commit = true, bool stage = true}) {
    if (_entries.isEmpty || !_controller.hasClients) return;
    final actual = _entryAtActualOffset();
    final _ScrollEntry page;
    final double pageOffset;
    if (actual != null) {
      page = actual.entry;
      pageOffset = actual.offset;
    } else {
      final relative = (_controller.offset - widget.padding.top).clamp(
        0.0,
        _contentExtent,
      );
      final estimated = _pageAtOffset(relative);
      if (estimated == null) return;
      page = estimated;
      pageOffset = (relative - estimated.top)
          .clamp(0.0, estimated.segment.extent)
          .toDouble();
    }
    final content = page.segment.content;
    _visiblePageOffset = pageOffset;
    if (!identical(content, _visibleContent)) {
      _visibleContent = content;
      widget.onPageVisible?.call(content);
    }
    if (_restoring || _programmaticJump) {
      _syncTimer?.cancel();
      return;
    }
    final generation = _layoutGeneration;
    if (widget.session.loading || generation != widget.session.generation) {
      _syncTimer?.cancel();
      return;
    }
    if (stage && _hasUserScrollSinceRestore) {
      widget.session.stageViewportSnapshot(
        ReaderViewportSnapshot(
          spineIndex: page.chapter.spineIndex,
          pageIndex: page.segment.pageIndex,
          scrollOffset: pageOffset,
          generation: generation,
          cfi: widget.session.cfiAtPageOffset(content, pageOffset),
        ),
      );
    }
    if (!commit || !_hasUserScrollSinceRestore) {
      _syncTimer?.cancel();
      return;
    }
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted ||
          generation != _layoutGeneration ||
          !identical(content, _visibleContent)) {
        return;
      }
      unawaited(
        widget.session.commitScrollPosition(
          page.chapter.spineIndex,
          page.segment.pageIndex,
          pageOffset,
          cfi: widget.session.cfiAtPageOffset(content, pageOffset),
          generation: generation,
        ),
      );
    });
  }

  ReaderViewportSnapshot? _snapshotForSession() {
    if (!mounted ||
        _entries.isEmpty ||
        !_controller.hasClients ||
        _restoring ||
        widget.session.loading ||
        _layoutGeneration != widget.session.generation) {
      return null;
    }
    if (!_hasUserScrollSinceRestore) return null;
    _captureVisiblePage(commit: false, stage: false);
    final content = _visibleContent;
    if (content == null) return null;
    return ReaderViewportSnapshot(
      spineIndex: content.spineIndex,
      pageIndex: content.pageIndex,
      scrollOffset: _visiblePageOffset,
      generation: _layoutGeneration,
      cfi: widget.session.cfiAtPageOffset(content, _visiblePageOffset),
    );
  }

  /// 同步暂存当前可见位置；退出/切模式时无需等待 120ms 合并窗口。
  void captureLatestPosition() {
    if (!mounted || !_controller.hasClients || !_hasUserScrollSinceRestore) {
      return;
    }
    _syncTimer?.cancel();
    _captureVisiblePage(commit: false);
  }

  /// 在切后台前立即提交当前可见页，避免连续滚动的防抖窗口丢失位置。
  Future<void> flushVisiblePosition() async {
    if (!_controller.hasClients || !_hasUserScrollSinceRestore) return;
    _syncTimer?.cancel();
    _captureVisiblePage(commit: false, stage: false);
    final page = _visibleContent;
    if (page == null) return;
    await widget.session.commitScrollPosition(
      page.spineIndex,
      page.pageIndex,
      _visiblePageOffset,
      cfi: widget.session.cfiAtPageOffset(page, _visiblePageOffset),
      generation: _layoutGeneration,
    );
  }

  /// 用已构建页的实际顶部位置反推当前可见页与页内偏移。
  ///
  /// ListView 只对已构建子项有精确几何；用估算的 `entry.top` 记录页内
  /// 偏移，会在前方插入章节或跳转后被放大成整页误差。
  ({_ScrollEntry entry, double offset})? _entryAtActualOffset() {
    final top = _controller.offset;
    for (final entry in _entries) {
      final box = _boxOf(entry);
      if (box == null) continue;
      final reveal = _revealOffset(box);
      if (reveal == null) continue;
      final extent = entry.segment.extent;
      if (top >= reveal - 0.5 && top < reveal + extent - 0.5) {
        return (
          entry: entry,
          offset: (top - reveal).clamp(0.0, extent).toDouble(),
        );
      }
    }
    return null;
  }

  _ScrollEntry? _pageAtOffset(double offset) {
    var low = 0;
    var high = _entries.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final entry = _entries[middle];
      if (offset < entry.top) {
        high = middle - 1;
      } else if (offset >= entry.top + entry.segment.extent) {
        low = middle + 1;
      } else {
        return entry;
      }
    }
    return _entries.isEmpty
        ? null
        : _entries[low.clamp(0, _entries.length - 1)];
  }

  void _maybeExtendWindow() {
    if (_restoring || !_controller.hasClients || _chapters.isEmpty) return;
    final height = _controller.position.viewportDimension;
    if (_controller.offset - widget.padding.top < height * 0.25) {
      unawaited(_extendBefore());
    }
    final remaining = _controller.position.maxScrollExtent - _controller.offset;
    if (remaining < height * 0.5) {
      unawaited(_extendAfter());
    }
  }

  /// 只保留视口前后预加载区覆盖的章节各再扩一章，避免长时间连续阅读后
  /// 布局和页面键持续增长。
  ///
  /// 保留范围必须覆盖前后预加载触发区：否则刚补进来的邻章会在同一帧被裁掉，
  /// 视口停在旧的内容末尾，翻页看起来毫无反应。
  void _trimWindow() {
    if (_restoring ||
        _trimmingWindow ||
        _extendingBefore ||
        _extendingAfter ||
        !_controller.hasClients ||
        _chapters.isEmpty) {
      return;
    }
    final height = _controller.position.viewportDimension;
    final first = _chapterAtOffset(_controller.offset - height * 0.25);
    final last = _chapterAtOffset(_controller.offset + height * 1.5);
    if (first == null || last == null) return;
    final firstIndex = _chapters.indexWhere(
      (chapter) => chapter.spineIndex == first,
    );
    final lastIndex = _chapters.indexWhere(
      (chapter) => chapter.spineIndex == last,
    );
    if (firstIndex < 0 || lastIndex < 0) return;
    final from = math.max(0, firstIndex - 1);
    final to = math.min(_chapters.length, lastIndex + 2);
    if (from == 0 && to == _chapters.length) return;
    unawaited(_replaceChapterWindow(_chapters.sublist(from, to)));
  }

  /// 内容坐标处的章节序号；越界按内容范围钳制到首尾章。
  int? _chapterAtOffset(double offset) {
    if (_entries.isEmpty) return null;
    final relative = (offset - widget.padding.top).clamp(0.0, _contentExtent);
    return _pageAtOffset(relative)?.chapter.spineIndex;
  }

  Future<void> _replaceChapterWindow(List<ScrollChapterLayout> retained) async {
    if (_trimmingWindow || retained.isEmpty) return;
    _trimmingWindow = true;
    final token = _loadToken;
    final generation = _layoutGeneration;
    _captureVisiblePage(commit: false);
    final visibleContent = _visibleContent;
    final visibleOffset = _visiblePageOffset;
    final retainedSpines = <int>{
      for (final chapter in retained) chapter.spineIndex,
    };
    setState(() {
      if (retained.last.spineIndex != _chapters.last.spineIndex) {
        _windowAtBookEnd = false;
      }
      _chapters
        ..clear()
        ..addAll(retained);
      _pageKeys.removeWhere((key, _) => !retainedSpines.contains(key.$1));
      _rebuildEntries();
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        token != _loadToken ||
        generation != _layoutGeneration ||
        !_controller.hasClients) {
      _trimmingWindow = false;
      return;
    }
    if (visibleContent != null) {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (_revealAtPage(
          visibleContent.spineIndex,
          visibleContent.pageIndex,
          visibleOffset,
        )) {
          break;
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || token != _loadToken) {
          _trimmingWindow = false;
          return;
        }
      }
    }
    _trimmingWindow = false;
    _captureVisiblePage(commit: false, stage: false);
  }

  /// 向前补一章；并发调用共享同一次加载，便于翻页等待结果。
  Future<void> _extendBefore() {
    final running = _extendBeforeTask;
    if (running != null) return running;
    final token = _loadToken;
    final generation = _layoutGeneration;
    final task = _loadExtendBefore();
    return _extendBeforeTask = task
        .onError<ChapterLoadCancelled>((_, _) {})
        .whenComplete(() {
          final inserted = _insertingBefore;
          _extendBeforeTask = null;
          _extendingBefore = false;
          _insertingBefore = false;
          if (inserted && _isCurrentWindow(token, generation)) {
            _maybeExtendWindow();
          }
        });
  }

  Future<void> _loadExtendBefore() async {
    if (_chapters.isEmpty) return;
    final token = _loadToken;
    final generation = _layoutGeneration;
    _extendingBefore = true;
    final layout = await _findReadable(
      _chapters.first.spineIndex - 1,
      direction: -1,
      priority: ChapterLayoutPriority.prefetch,
    );
    if (!_isCurrentWindow(token, generation) || layout == null) return;
    _insertingBefore = true;
    _captureVisiblePage(commit: false, stage: false);
    final visibleContent = _visibleContent;
    final visibleOffset = _visiblePageOffset;
    final oldOffset = _controller.hasClients ? _controller.offset : 0.0;
    setState(() {
      _chapters.insert(0, layout);
      _rebuildEntries();
    });
    await WidgetsBinding.instance.endOfFrame;
    if (_isCurrentWindow(token, generation) && _controller.hasClients) {
      var restored = false;
      if (visibleContent != null) {
        restored = _revealAtPage(
          visibleContent.spineIndex,
          visibleContent.pageIndex,
          visibleOffset,
        );
      }
      for (var attempt = 0; attempt < 2 && !restored; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!_isCurrentWindow(token, generation) || !_controller.hasClients) {
          break;
        }
        if (visibleContent != null) {
          restored = _revealAtPage(
            visibleContent.spineIndex,
            visibleContent.pageIndex,
            visibleOffset,
          );
        }
      }
      if (restored) {
        await WidgetsBinding.instance.endOfFrame;
        if (_isCurrentWindow(token, generation) && _controller.hasClients) {
          _captureVisiblePage(commit: false, stage: false);
        }
      } else {
        if (!_isCurrentWindow(token, generation)) return;
        final fallback = (oldOffset + layout.extent).clamp(
          0.0,
          _controller.position.maxScrollExtent,
        );
        _jumpProgrammatically(fallback);
        await WidgetsBinding.instance.endOfFrame;
        for (
          var attempt = 0;
          attempt < 2 && !restored && visibleContent != null;
          attempt++
        ) {
          if (!_isCurrentWindow(token, generation) || !_controller.hasClients) {
            break;
          }
          restored = _revealAtPage(
            visibleContent.spineIndex,
            visibleContent.pageIndex,
            visibleOffset,
          );
          if (!restored) {
            await WidgetsBinding.instance.endOfFrame;
          }
        }
        if (restored) {
          await WidgetsBinding.instance.endOfFrame;
        }
        if (_isCurrentWindow(token, generation) && _controller.hasClients) {
          _captureVisiblePage(commit: false, stage: false);
        }
      }
    }
  }

  /// 向后补一章；并发调用共享同一次加载，便于翻页等待结果。
  Future<void> _extendAfter() {
    final running = _extendAfterTask;
    if (running != null) return running;
    final task = _loadExtendAfter();
    return _extendAfterTask = task
        .onError<ChapterLoadCancelled>((_, _) {})
        .whenComplete(() {
          _extendAfterTask = null;
          _extendingAfter = false;
        });
  }

  Future<void> _loadExtendAfter() async {
    if (_chapters.isEmpty) return;
    final token = _loadToken;
    final generation = _layoutGeneration;
    _extendingAfter = true;
    final layout = await _findReadable(
      _chapters.last.spineIndex + 1,
      direction: 1,
      priority: ChapterLayoutPriority.prefetch,
    );
    if (!_isCurrentWindow(token, generation)) return;
    if (layout == null) {
      if (!_windowAtBookEnd) setState(() => _windowAtBookEnd = true);
      return;
    }
    setState(() {
      _windowAtBookEnd = false;
      _chapters.add(layout);
      _rebuildEntries();
    });
    _extendingAfter = false;
    await WidgetsBinding.instance.endOfFrame;
    if (_isCurrentWindow(token, generation)) {
      _trimWindow();
    }
  }

  /// 翻一屏前保证目标方向有足够余量：窗口到边时先等邻章加载完成，
  /// 否则滚动会被旧的最大范围钳制，点击看起来毫无反应。
  Future<void> _ensureTurnRoom(bool next) async {
    for (
      var attempt = 0;
      attempt < widget.session.source.chapterCount;
      attempt++
    ) {
      if (!mounted || !_controller.hasClients || _chapters.isEmpty) return;
      final height = _controller.position.viewportDimension;
      final room = next
          ? _controller.position.maxScrollExtent - _controller.offset
          : _controller.offset;
      if (room >= height * 0.88) return;
      if (next) {
        final before = _chapters.last.spineIndex;
        await _extendAfter();
        if (_chapters.isEmpty || _chapters.last.spineIndex <= before) return;
      } else {
        final before = _chapters.first.spineIndex;
        await _extendBefore();
        if (_chapters.isEmpty || _chapters.first.spineIndex >= before) return;
      }
    }
  }

  /// 点击区按当前可视高度移动一屏。
  Future<void> scrollPage(bool next) async {
    if (!_controller.hasClients) return;
    _hasUserScrollSinceRestore = true;
    await _ensureTurnRoom(next);
    if (!mounted || !_controller.hasClients) return;
    final height = _controller.position.viewportDimension;
    final target = (_controller.offset + (next ? height : -height) * 0.88)
        .clamp(0.0, _controller.position.maxScrollExtent);
    await _controller.animateTo(
      target,
      duration: pageTurnAnimationDuration,
      curve: Curves.easeOutCubic,
    );
    _captureVisiblePage();
  }

  /// 把视口点击坐标映射到可见页切片，再交给正文处理。
  bool handleTapAt(Offset position) {
    final hit = pageAt(position, includeMargins: true);
    if (hit == null) {
      return false;
    }
    return widget.onTapAtPage?.call(hit.page, hit.localPosition) ?? false;
  }

  /// 把阅读视口坐标映射到所在页切片及其页内坐标。
  ({PageContent page, Offset localPosition, double pageTop})? pageAt(
    Offset position, {
    bool includeMargins = false,
  }) {
    if (!_controller.hasClients || _entries.isEmpty) {
      return null;
    }
    final size = context.size;
    if (size == null ||
        position.dx < 0 ||
        position.dx > size.width ||
        (!includeMargins &&
            (position.dx < widget.padding.left ||
                position.dx > size.width - widget.padding.right))) {
      return null;
    }
    final relative = _controller.offset + position.dy - widget.padding.top;
    if (relative < 0) {
      return null;
    }
    final page = _pageAtOffset(relative);
    if (page == null) {
      return null;
    }
    return (
      page: page.segment.content,
      localPosition: Offset(
        position.dx - widget.padding.left,
        relative - page.top,
      ),
      pageTop: widget.padding.top + page.top - _controller.offset,
    );
  }

  /// 页切片当前在视口中的顶部坐标；页不在已加载切片中时返回 null。
  double? pageTopOnScreen(PageContent page) {
    if (!_controller.hasClients) {
      return null;
    }
    for (final entry in _entries) {
      if (identical(entry.segment.content, page)) {
        return widget.padding.top + entry.top - _controller.offset;
      }
    }
    return null;
  }

  /// 当前保留的章节序号；测试用于确认连续滚动窗口不会无界增长。
  @visibleForTesting
  List<int> get debugLoadedSpineIndices => <int>[
    for (final chapter in _chapters) chapter.spineIndex,
  ];

  /// 当前页面键数量；测试用于确认离窗页面的 key 已释放。
  @visibleForTesting
  int get debugPageKeyCount => _pageKeys.length;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey<String>('continuous-scroll-loading'),
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Text(
          '连续滚动加载失败：$error',
          key: const ValueKey<String>('continuous-scroll-error'),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - widget.padding.horizontal).clamp(
          1.0,
          double.infinity,
        );
        // 书尾预留一屏滚动空间，使末页任意页内偏移都能恢复到视口顶部。
        // 留白只参与滚动物理，不进入页切片、字符权重或阅读进度。
        final scrollPadding = widget.padding.copyWith(
          bottom: _windowAtBookEnd
              ? math.max(widget.padding.bottom, constraints.maxHeight)
              : widget.padding.bottom,
        );
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final canNavigate =
                !_programmaticJump &&
                !_trimmingWindow &&
                !_insertingBefore &&
                _layoutGeneration == widget.session.generation &&
                !widget.session.loading;
            // 尺寸重排可能触发系统弹道校正，仅像素变化不足以证明用户导航。
            // 拖动有 dragDetails；外部 jumpTo 在 idle 活动中发出开始通知；
            // 鼠标/无障碍则通过 UserScrollNotification 报告阅读方向。
            final explicitStart =
                notification is ScrollStartNotification &&
                (notification.dragDetails != null ||
                    !_controller.position.isScrollingNotifier.value);
            final userDirection =
                notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle;
            if (canNavigate && (explicitStart || userDirection)) {
              if (_restoring) {
                _restoreToken += 1;
                _restoring = false;
              }
              _userDragging = true;
              _hasUserScrollSinceRestore = true;
              widget.onUserScroll?.call();
              _captureVisiblePage();
            }
            if (notification is ScrollEndNotification) {
              // 程序恢复/窗口前插产生的滚动结束不是用户阅读导航，不能把
              // 书尾被 maxScrollExtent 钳制后的可见页反写为保存位置。
              if (_userDragging) {
                _userDragging = false;
                _captureVisiblePage();
              }
            }
            return false;
          },
          child: ListView.builder(
            key: const ValueKey<String>('continuous-scroll'),
            controller: _controller,
            padding: scrollPadding,
            itemCount: _entries.length,
            itemBuilder: (context, index) {
              final entry = _entries[index];
              final pageKey = _pageKeys.putIfAbsent((
                entry.chapter.spineIndex,
                entry.segment.pageIndex,
              ), () => GlobalKey());
              return SizedBox(
                key: pageKey,
                height: entry.segment.extent,
                child: RepaintBoundary(
                  child: widget.paperBuilder(
                    entry.segment.content,
                    Size(width, entry.segment.extent),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    if (mounted && _controller.hasClients && _entries.isNotEmpty) {
      _syncTimer?.cancel();
      _captureVisiblePage(commit: false);
    }
    widget.session.unregisterViewportSnapshotProvider(
      _viewportSnapshotProvider,
    );
    _loadToken++;
    _syncTimer?.cancel();
    _controller
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }
}

class _ScrollEntry {
  const _ScrollEntry(this.chapter, this.segment, this.top);

  final ScrollChapterLayout chapter;
  final ScrollPageSegment segment;
  final double top;
}
