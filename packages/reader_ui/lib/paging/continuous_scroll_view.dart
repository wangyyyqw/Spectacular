import 'dart:async';

import 'package:flutter/material.dart';
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
  });

  final ReaderSession session;
  final ScrollPaperBuilder paperBuilder;
  final EdgeInsets padding;
  final Object revision;
  final ValueChanged<PageContent>? onPageVisible;

  @override
  State<ContinuousScrollView> createState() => ContinuousScrollViewState();
}

/// 连续滚动状态；阅读页通过它响应点击区的前后屏移动。
class ContinuousScrollViewState extends State<ContinuousScrollView> {
  final ScrollController _controller = ScrollController();
  final List<ScrollChapterLayout> _chapters = <ScrollChapterLayout>[];
  final List<_ScrollEntry> _entries = <_ScrollEntry>[];
  Timer? _syncTimer;
  PageContent? _visibleContent;
  bool _loading = true;
  bool _extendingBefore = false;
  bool _extendingAfter = false;
  int _loadToken = 0;
  late int _layoutGeneration = widget.session.generation;
  Object? _error;

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
    final offset =
        widget.padding.top + _chapterTop(spine) + chapter.offsetOfPage(page);
    _controller.jumpTo(offset.clamp(0.0, _controller.position.maxScrollExtent));
    _captureVisiblePage();
  }

  void _handleScroll() {
    if (!_controller.hasClients) return;
    _captureVisiblePage();
    _maybeExtendWindow();
  }

  void _captureVisiblePage() {
    if (_entries.isEmpty || !_controller.hasClients) return;
    final relative = (_controller.offset - widget.padding.top).clamp(
      0.0,
      _contentExtent,
    );
    final page = _pageAtOffset(relative);
    if (page == null) return;
    final content = page.segment.content;
    if (identical(content, _visibleContent)) return;
    _visibleContent = content;
    widget.onPageVisible?.call(content);
    _syncTimer?.cancel();
    final generation = _layoutGeneration;
    _syncTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted ||
          generation != _layoutGeneration ||
          !identical(content, _visibleContent)) {
        return;
      }
      unawaited(
        widget.session.commitScrollPage(
          page.chapter.spineIndex,
          page.segment.pageIndex,
        ),
      );
    });
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
    if (!_controller.hasClients || _chapters.isEmpty) return;
    final height = _controller.position.viewportDimension;
    if (_controller.offset < height) {
      unawaited(_extendBefore());
    }
    if (_controller.offset > _controller.position.maxScrollExtent - height) {
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
    final oldOffset = _controller.hasClients ? _controller.offset : 0.0;
    setState(() {
      _chapters.insert(0, layout);
      _rebuildEntries();
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && _controller.hasClients) {
      _controller.jumpTo(
        (oldOffset + layout.extent).clamp(
          0.0,
          _controller.position.maxScrollExtent,
        ),
      );
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
            findChildIndexCallback: (key) {
              final value = key;
              if (value is! ValueKey<(int, int)>) return null;
              for (var index = 0; index < _entries.length; index++) {
                final entry = _entries[index];
                if (entry.chapter.spineIndex == value.value.$1 &&
                    entry.segment.pageIndex == value.value.$2) {
                  return index;
                }
              }
              return null;
            },
            itemBuilder: (context, index) {
              final entry = _entries[index];
              return SizedBox(
                key: ValueKey<(int, int)>((
                  entry.chapter.spineIndex,
                  entry.segment.pageIndex,
                )),
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
