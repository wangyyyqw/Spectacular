import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/scroll_layout.dart';

import '../reader_session.dart';

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
  });

  final ReaderSession session;
  final ScrollPaperBuilder paperBuilder;
  final EdgeInsets padding;
  final Object revision;
  final ValueChanged<PageContent>? onPageVisible;
  final bool Function(PageContent page, Offset localPosition)? onTapAtPage;

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
  bool _extendingAfter = false;
  int _loadToken = 0;
  int _restoreToken = 0;
  late int _layoutGeneration = widget.session.generation;
  Object? _error;
  bool _restoring = false;
  bool _programmaticJump = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleScroll);
    unawaited(_loadInitialWindow());
  }

  @override
  void didUpdateWidget(ContinuousScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        _layoutGeneration != widget.session.generation) {
      _layoutGeneration = widget.session.generation;
      unawaited(_loadInitialWindow());
    }
  }

  Future<void> _loadInitialWindow() async {
    final token = ++_loadToken;
    final progress = widget.session.progress;
    final center = progress?.spineIndex ?? 0;
    final indices = <int>{
      if (center > 0) center - 1,
      center,
      if (center + 1 < widget.session.source.chapterCount) center + 1,
    }.toList()..sort();
    final layouts = await Future.wait([
      for (final spine in indices) _loadChapter(spine),
    ]);
    if (!mounted || token != _loadToken) return;
    final loaded = layouts.nonNulls.toList();
    final current = loaded.where((layout) => layout.spineIndex == center);
    if (current.isEmpty) {
      setState(() {
        _loading = false;
        _error = StateError('当前章加载失败');
      });
      return;
    }
    _syncTimer?.cancel();
    setState(() {
      _chapters
        ..clear()
        ..addAll(loaded);
      _error = null;
      _loading = false;
      _visibleContent = null;
      _rebuildEntries();
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && token == _loadToken) {
      _jumpToReadingPosition(progress);
    }
  }

  Future<ScrollChapterLayout?> _loadChapter(int spine) async {
    try {
      return await widget.session.loadScrollChapter(spine);
    } catch (_) {
      return null;
    }
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
    final spine =
        progress?.spineIndex ?? _chapters.firstOrNull?.spineIndex ?? 0;
    final page = progress?.pageIndex ?? 0;
    final chapter = _chapters
        .where((item) => item.spineIndex == spine)
        .firstOrNull;
    if (chapter == null) return;
    final pageStart = chapter.offsetOfPage(page);
    final pageExtent = math.max(
      0.0,
      chapter.offsetOfPage(page + 1) - pageStart,
    );
    final pageOffset = (progress?.scrollOffset ?? 0)
        .clamp(0.0, pageExtent)
        .toDouble();
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
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_controller.hasClients || token != _restoreToken) {
          return;
        }
        final spine =
            progress?.spineIndex ?? _chapters.firstOrNull?.spineIndex ?? 0;
        final page = progress?.pageIndex ?? 0;
        if (!_revealAtPage(spine, page, progress?.scrollOffset ?? 0)) {
          continue;
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || token != _restoreToken) return;
        _captureVisiblePage(commit: false);
        return;
      }
    } finally {
      if (mounted && token == _restoreToken) {
        _restoring = false;
        _captureVisiblePage();
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
    }
  }

  void _captureVisiblePage({bool commit = true}) {
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
    if (!commit || _restoring || _programmaticJump) {
      _syncTimer?.cancel();
      return;
    }
    _syncTimer?.cancel();
    final generation = _layoutGeneration;
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
        ),
      );
    });
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
    final remaining =
        _controller.position.maxScrollExtent - _controller.offset;
    if (remaining < height * 0.5) {
      unawaited(_extendAfter());
    }
  }

  Future<void> _extendBefore() async {
    if (_extendingBefore || _chapters.isEmpty) return;
    final target = _chapters.first.spineIndex - 1;
    if (target < 0) return;
    final token = _loadToken;
    _extendingBefore = true;
    final layout = await _loadChapter(target);
    if (!mounted || token != _loadToken || layout == null) {
      _extendingBefore = false;
      return;
    }
    _captureVisiblePage(commit: false);
    final visibleContent = _visibleContent;
    final visibleOffset = _visiblePageOffset;
    final oldOffset = _controller.hasClients ? _controller.offset : 0.0;
    setState(() {
      _chapters.insert(0, layout);
      _rebuildEntries();
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && _controller.hasClients) {
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
        if (!mounted || !_controller.hasClients) break;
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
        if (mounted && _controller.hasClients) {
          _captureVisiblePage();
        }
      } else {
        final fallback = (oldOffset + layout.extent).clamp(
          0.0,
          _controller.position.maxScrollExtent,
        );
        _jumpProgrammatically(fallback);
        await WidgetsBinding.instance.endOfFrame;
        for (var attempt = 0;
            attempt < 2 && !restored && visibleContent != null;
            attempt++) {
          if (!mounted ||
              !_controller.hasClients ||
              token != _loadToken) {
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
        if (mounted && _controller.hasClients) {
          _captureVisiblePage();
        }
      }
    }
    _extendingBefore = false;
  }

  Future<void> _extendAfter() async {
    if (_extendingAfter || _chapters.isEmpty) return;
    final target = _chapters.last.spineIndex + 1;
    if (target >= widget.session.source.chapterCount) return;
    final token = _loadToken;
    _extendingAfter = true;
    final layout = await _loadChapter(target);
    if (!mounted || token != _loadToken || layout == null) {
      _extendingAfter = false;
      return;
    }
    setState(() {
      _chapters.add(layout);
      _rebuildEntries();
    });
    _extendingAfter = false;
  }

  /// 点击区按当前可视高度移动一屏。
  Future<void> scrollPage(bool next) async {
    if (!_controller.hasClients) return;
    final height = _controller.position.viewportDimension;
    final target = (_controller.offset + (next ? height : -height) * 0.88)
        .clamp(0.0, _controller.position.maxScrollExtent);
    await _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    _captureVisiblePage();
  }

  /// 把视口点击坐标映射到可见页切片，再交给正文处理。
  bool handleTapAt(Offset position) {
    final hit = pageAt(position);
    if (hit == null) {
      return false;
    }
    return widget.onTapAtPage?.call(hit.page, hit.localPosition) ?? false;
  }

  /// 把阅读视口坐标映射到所在页切片及其页内坐标。
  ({PageContent page, Offset localPosition})? pageAt(Offset position) {
    if (!_controller.hasClients || _entries.isEmpty) {
      return null;
    }
    final size = context.size;
    if (size == null ||
        position.dx < widget.padding.left ||
        position.dx > size.width - widget.padding.right) {
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
    );
  }

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
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification) {
              _captureVisiblePage();
            }
            return false;
          },
          child: ListView.builder(
            key: const ValueKey<String>('continuous-scroll'),
            controller: _controller,
            padding: widget.padding,
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
