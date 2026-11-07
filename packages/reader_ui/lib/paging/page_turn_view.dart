import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:reader_core/layout/paginator.dart';

import '../reader_session.dart';
import 'page_snapshot_cache.dart';
import 'page_turn_controller.dart';
import 'page_turn_mode.dart';
import 'page_turn_painter.dart';

/// 静态纸面和目标纸面共用同一个构建器，保证快照与排版一致。
typedef ReaderPaperBuilder = Widget Function(PageContent page, Size size);

/// 生成纸面快照前解码该页图片，避免翻页完成后才补图。
typedef ReaderPageImagesPreparer = Future<void> Function(PageContent page);

class PageTurnView extends StatefulWidget {
  const PageTurnView({
    super.key,
    required this.session,
    required this.mode,
    required this.revision,
    required this.paperBuilder,
    required this.paperColor,
    this.preparePageImages,
    this.rtl = false,
  });

  final ReaderSession session;
  final PageTurnMode mode;
  final Object revision;
  final ReaderPaperBuilder paperBuilder;
  final Color paperColor;
  final ReaderPageImagesPreparer? preparePageImages;
  final bool rtl;

  @override
  State<PageTurnView> createState() => PageTurnViewState();
}

/// 阅读页通过此视口转发手势，绘制帧由独立控制器驱动。
class PageTurnViewState extends State<PageTurnView>
    with TickerProviderStateMixin {
  late final PageTurnController controller = PageTurnController(
    session: widget.session,
    vsync: this,
    acquireImage: _enqueueCapture,
  )..addListener(_controllerChanged);
  final _currentBoundary = GlobalKey();
  final _captureBoundary = GlobalKey();
  final _cache = PageSnapshotCache();
  Future<void> _captureQueue = Future.value();
  PageContent? _capturePage;
  Size _size = Size.zero;
  double _ratio = 1;
  int _captureToken = 0;
  Object? _lastWarm;
  bool _showAnimation = false;
  bool _revisionDirty = false;
  bool _pageDirty = false;
  bool _warmSuspended = false;
  PageContent? _renderedPage;

  int get snapshotBytes => _cache.bytes;
  int get snapshotCount => _cache.length;

  @override
  void didUpdateWidget(PageTurnView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.mode != widget.mode ||
        oldWidget.rtl != widget.rtl) {
      if (controller.active) {
        _revisionDirty = true;
      } else {
        _invalidate();
      }
    }
  }

  void _invalidate() {
    _revisionDirty = false;
    controller.cancel();
    _captureToken++;
    _capturePage = null;
    _lastWarm = null;
    _cache.clear();
  }

  void _controllerChanged() {
    if (!mounted) return;
    final show =
        controller.active &&
        controller.originImage != null &&
        controller.targetImage != null;
    _cache.protected = {
      if (widget.session.page != null) widget.session.page!,
      if (controller.turn != null) controller.turn!.target.content,
    };
    if (show != _showAnimation) setState(() => _showAnimation = show);
    if (!controller.active) {
      if (_revisionDirty) {
        _invalidate();
        return;
      }
      if (_pageDirty) _cancelPendingCaptures();
      _scheduleWarm();
    }
  }

  /// 切后台时释放翻页位图；恢复后按当前页重新预热。
  void releaseCachedBitmaps() {
    _warmSuspended = true;
    _invalidate();
    _captureQueue = Future<void>.value();
  }

  /// 回到前台后重新允许预热当前页与相邻页。
  void resumeWarmup() {
    if (!_warmSuspended) return;
    _warmSuspended = false;
    _lastWarm = null;
    _scheduleWarm();
  }

  /// 页面提交后丢弃仅供旧页使用的排队截图，避免快速翻页时任务累积。
  void _cancelPendingCaptures() {
    _pageDirty = false;
    _captureToken++;
    _captureQueue = Future<void>.value();
    _capturePage = null;
    _lastWarm = null;
  }

  Future<ui.Image?> _enqueueCapture(PageContent page) {
    final cached = _cache.get(page);
    if (cached != null) return Future.value(cached);
    final result = _captureQueue.then((_) => _capture(page));
    _captureQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<ui.Image?> _capture(PageContent page) async {
    final cached = _cache.get(page);
    if (cached != null || !mounted) return cached;
    final token = _captureToken;
    final prepare = widget.preparePageImages;
    if (prepare != null) {
      await prepare(page);
      if (!mounted || token != _captureToken) return null;
    }
    final current = identical(page, widget.session.page);
    if (!current) setState(() => _capturePage = page);
    ui.Image? image;
    for (var attempt = 0; attempt < 2; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || token != _captureToken) return null;
      final key = current ? _currentBoundary : _captureBoundary;
      final boundary = key.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary && !boundary.debugNeedsPaint) {
        image = boundary.toImageSync(pixelRatio: _ratio);
        _cache.put(page, image);
        break;
      }
    }
    if (mounted && _capturePage != null) setState(() => _capturePage = null);
    return image;
  }

  void _scheduleWarm() {
    if (_warmSuspended ||
        !mounted ||
        controller.active ||
        widget.mode == PageTurnMode.none) {
      return;
    }
    final page = widget.session.page;
    final key = (page, widget.revision, _size, _ratio);
    if (page == null || _size.isEmpty || key == _lastWarm) return;
    _lastWarm = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !controller.active) unawaited(_warm(page));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _warm(PageContent page) async {
    final candidates = <PageContent>{page, ...widget.session.adjacentPages};
    for (final candidate in candidates) {
      if (!mounted ||
          controller.active ||
          !identical(page, widget.session.page)) {
        return;
      }
      await _enqueueCapture(candidate);
    }
    // 先准备用户最常继续的前进方向，再补后退方向；两侧同时排版会在
    // 跨章时争用主 isolate，让下一手势反而更慢。
    final prepared = <PageContent>[
      ?await _prepareWarmPage(true),
      ?await _prepareWarmPage(false),
    ];
    for (final candidate in prepared) {
      if (!mounted ||
          controller.active ||
          !identical(page, widget.session.page)) {
        return;
      }
      await _enqueueCapture(candidate);
    }
  }

  Future<PageContent?> _prepareWarmPage(bool next) async {
    try {
      return (await widget.session.preparePageTurn(
        next,
        prefetch: true,
      ))?.target.content;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final deviceRatio = MediaQuery.devicePixelRatioOf(context);
      // 位图宽高按像素取整，预留 2% 余量才能同时保留当前、前、后三页。
      final cacheRatio =
          math.sqrt(_cache.maxBytes / (size.width * size.height * 4 * 3)) *
          0.98;
      final ratio = math.min(deviceRatio, cacheRatio);
      if (_size != size || _ratio != ratio) {
        _invalidate();
        _size = size;
        _ratio = ratio;
      }
      controller.size = size;
      controller.rtl = widget.rtl;
      controller.mode = widget.mode;
      final page = widget.session.page!;
      if (!identical(page, _renderedPage)) {
        _renderedPage = page;
        _pageDirty = true;
        if (!controller.active) _cancelPendingCaptures();
      }
      _scheduleWarm();
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_capturePage != null)
            ExcludeSemantics(
              child: IgnorePointer(
                child: RepaintBoundary(
                  key: _captureBoundary,
                  child: widget.paperBuilder(_capturePage!, size),
                ),
              ),
            ),
          RepaintBoundary(
            key: _currentBoundary,
            child: widget.paperBuilder(page, size),
          ),
          if (_showAnimation)
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('page-turn-animation'),
                  painter: PageTurnPainter(
                    controller,
                    paperColor: widget.paperColor,
                  ),
                ),
              ),
            ),
          // 隐在纸面下的纹理采样由同一帧预热；不会触发额外正文测量。
        ],
      );
    },
  );

  @override
  void dispose() {
    _captureToken++;
    controller.removeListener(_controllerChanged);
    controller.dispose();
    _cache.clear();
    super.dispose();
  }
}
