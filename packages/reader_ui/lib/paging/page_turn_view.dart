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
    this.preload = true,
    this.rtl = false,
  });

  final ReaderSession session;
  final PageTurnMode mode;
  final Object revision;
  final ReaderPaperBuilder paperBuilder;
  final Color paperColor;
  final ReaderPageImagesPreparer? preparePageImages;
  final bool rtl;

  /// 重排编辑期间暂停后台准备，避免预览尚未稳定时抢跑邻章。
  final bool preload;

  @override
  State<PageTurnView> createState() => PageTurnViewState();
}

/// 阅读页通过此视口转发手势，绘制帧由独立控制器驱动。
class PageTurnViewState extends State<PageTurnView>
    with TickerProviderStateMixin {
  late final PageTurnController controller = PageTurnController(
    session: widget.session,
    vsync: this,
    acquireImage: _acquireTurnImage,
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
  PageContent? _staticPage;
  ui.Image? _staticImage;
  bool _staticPaperReady = false;
  int _staticToken = 0;
  final _window = <int, PageContent>{};
  final _captures = <PageContent, _WindowCapture>{};
  final _pendingCaptures = <_WindowCapture>[];
  bool _capturingWindow = false;
  PageContent? _windowPage;

  bool get _usesWindow =>
      widget.mode != PageTurnMode.simulation3d &&
      widget.mode != PageTurnMode.scroll;

  Set<PageContent> get _windowPages => _window.values.toSet();

  int get snapshotBytes => _cache.bytes;
  int get snapshotCount => _cache.length;

  /// 该页由完整快照承接，补图后的静态重绘交给本视口统一恢复。
  bool isPresentingSnapshot(PageContent page) => identical(_staticPage, page);

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
    if (oldWidget.preload != widget.preload) {
      _lastWarm = null;
      if (!widget.preload && !controller.active) _cancelPendingCaptures();
    }
  }

  void _invalidate() {
    _revisionDirty = false;
    if (controller.active) controller.cancel();
    _captureToken++;
    _capturePage = null;
    _lastWarm = null;
    _window.clear();
    _windowPage = null;
    _captures.clear();
    _cache.clear();
    _clearStaticImage();
  }

  void _controllerChanged() {
    if (!mounted) return;
    final show = controller.active && controller.originImage != null;
    _cache.protected = {
      if (_usesWindow && _windowPage != null) _windowPage!,
      if (widget.session.page != null) widget.session.page!,
      if (controller.turn != null) controller.turn!.target.content,
    };
    if (_usesWindow) {
      _syncWindow();
      _cache.retainPages(_windowPages);
    }
    final target = controller.turn?.target.content;
    if (show &&
        controller.targetImage != null &&
        !identical(target, _staticPage)) {
      _clearStaticImage();
      _staticPage = target;
      _staticImage = controller.targetImage!.clone();
    }
    if (show != _showAnimation) {
      setState(() => _showAnimation = show);
      if (!show) unawaited(_restoreStaticPaper());
    }
    if (!controller.active) {
      if (_revisionDirty) {
        _invalidate();
        return;
      }
      if (_pageDirty) _cancelPendingCaptures();
      if (_usesWindow) unawaited(_drainWindowCaptures());
      _scheduleWarm();
    }
  }

  void _clearStaticImage() {
    _staticToken++;
    _staticImage?.dispose();
    _staticImage = null;
    _staticPage = null;
    _staticPaperReady = false;
  }

  /// 快照先接住落页，原图在动画之外补齐后再恢复静态纸面。
  Future<void> _restoreStaticPaper() async {
    final page = widget.session.page;
    if (!identical(page, _staticPage)) {
      _clearStaticImage();
      final image = page == null ? null : _cache.get(page);
      if (image == null) return;
      _staticPage = page;
      _staticImage = image.clone();
    }
    if (page == null) return;
    final token = _staticToken;
    try {
      await widget.preparePageImages?.call(page);
    } catch (_) {
      // 宿主解码失败时恢复既有缺图占位，不能留下永久覆盖的快照。
    }
    if (!mounted || token != _staticToken) return;
    setState(() => _staticPaperReady = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && token == _staticToken) setState(_clearStaticImage);
  }

  /// 切后台时释放翻页位图；恢复后按当前页重新预热。
  void releaseCachedBitmaps() {
    _warmSuspended = true;
    controller.cancel();
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
    if (_usesWindow) {
      _pageDirty = false;
      _syncWindow();
      return;
    }
    _pageDirty = false;
    _captureToken++;
    _captureQueue = Future<void>.value();
    _capturePage = null;
    _lastWarm = null;
  }

  Future<ui.Image?> _enqueueCapture(PageContent page) {
    final token = _captureToken;
    final result = _captureQueue.then((_) => _capture(page, token));
    _captureQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<ui.Image?> _acquireTurnImage(PageContent page) {
    if (_usesWindow) return _enqueueWindowCapture(page, urgent: true);
    // 3D 仿真保留原有捕获策略。
    _cancelPendingCaptures();
    return _enqueueCapture(page);
  }

  void _syncWindow() {
    final page = widget.session.page;
    if (page == null || identical(page, _windowPage)) return;
    final offset = _window.entries
        .where((entry) => identical(entry.value, page))
        .map((entry) => entry.key)
        .firstOrNull;
    final retained = <int, PageContent>{};
    if (offset != null) {
      for (final entry in _window.entries) {
        final distance = entry.key - offset;
        if (distance.abs() <= 2) retained[distance] = entry.value;
      }
    }
    _window
      ..clear()
      ..addAll(retained)
      ..[0] = page;
    _windowPage = page;
    _lastWarm = null;
    _cache.retainPages(_windowPages);
  }

  bool _retainCapture(PageContent page) =>
      _windowPages.contains(page) ||
      identical(page, widget.session.page) ||
      (controller.active &&
          (identical(page, _windowPage) ||
              identical(page, controller.turn?.target.content)));

  Future<ui.Image?> _enqueueWindowCapture(
    PageContent page, {
    bool urgent = false,
  }) {
    final cached = _cache.get(page);
    if (cached != null) return Future.value(cached);
    var capture = _captures[page];
    if (capture != null && capture.token == _captureToken) {
      if (urgent) capture.urgent = true;
      if (urgent && _pendingCaptures.remove(capture)) {
        _pendingCaptures.insert(0, capture);
        unawaited(_drainWindowCaptures());
      }
      return capture.result.future;
    }
    capture = _WindowCapture(page, _captureToken)..urgent = urgent;
    _captures[page] = capture;
    unawaited(_prepareWindowCapture(capture));
    return capture.result.future;
  }

  Future<void> _prepareWindowCapture(_WindowCapture capture) async {
    try {
      await widget.preparePageImages?.call(capture.page);
      if (capture.urgent) {
        _pendingCaptures.insert(0, capture);
      } else {
        _pendingCaptures.add(capture);
      }
      unawaited(_drainWindowCaptures());
    } catch (error, stack) {
      capture.result.completeError(error, stack);
      if (identical(_captures[capture.page], capture)) {
        _captures.remove(capture.page);
      }
    }
  }

  Future<void> _drainWindowCaptures() async {
    if (_capturingWindow) return;
    _capturingWindow = true;
    try {
      while (_pendingCaptures.isNotEmpty) {
        final index = controller.active
            ? _pendingCaptures.indexWhere((capture) => capture.urgent)
            : 0;
        if (index < 0) break;
        final capture = _pendingCaptures.removeAt(index);
        try {
          final image = await _capture(
            capture.page,
            capture.token,
            imagesPrepared: true,
          );
          capture.result.complete(image);
        } catch (error, stack) {
          capture.result.completeError(error, stack);
        } finally {
          if (identical(_captures[capture.page], capture)) {
            _captures.remove(capture.page);
          }
        }
      }
    } finally {
      _capturingWindow = false;
    }
  }

  Future<ui.Image?> _capture(
    PageContent page,
    int token, {
    bool imagesPrepared = false,
  }) async {
    bool valid() =>
        mounted &&
        token == _captureToken &&
        (!_usesWindow || _retainCapture(page));
    if (!valid()) return null;
    // 完整快照可直接翻动；静态纸面所需原图在落页时独立恢复。
    final cached = _cache.get(page);
    if (cached != null) return cached;
    final prepare = widget.preparePageImages;
    if (prepare != null && !imagesPrepared) {
      await prepare(page);
      if (!valid()) return null;
    }
    return _capturePaper(page, valid);
  }

  bool _usesCurrentBoundary(PageContent page) =>
      identical(page, widget.session.page) && (!_usesWindow || !_showAnimation);

  Future<ui.Image?> _capturePaper(
    PageContent page,
    bool Function() valid,
  ) async {
    var current = _usesCurrentBoundary(page);
    if (!current) setState(() => _capturePage = page);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!valid()) return null;
        if (current && !_usesCurrentBoundary(page)) {
          // 导航或动画可能在等待帧时替换当前边界，改用该页自己的捕获纸面。
          current = false;
          setState(() => _capturePage = page);
          continue;
        }
        final key = current ? _currentBoundary : _captureBoundary;
        final boundary = key.currentContext?.findRenderObject();
        if (boundary is RenderRepaintBoundary && !boundary.debugNeedsPaint) {
          final image = boundary.toImageSync(pixelRatio: _ratio);
          _cache.put(page, image);
          return image;
        }
      }
      return null;
    } finally {
      if (mounted && identical(_capturePage, page)) {
        setState(() => _capturePage = null);
      }
    }
  }

  void _scheduleWarm() {
    if (_warmSuspended ||
        !widget.preload ||
        !mounted ||
        (!_usesWindow && controller.active)) {
      return;
    }
    if (_usesWindow) _syncWindow();
    final page = widget.session.page;
    final key = (page, widget.revision, _size, _ratio);
    if (page == null || _size.isEmpty || key == _lastWarm) return;
    _lastWarm = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (_usesWindow || !controller.active)) {
        unawaited(_warm(page));
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _warm(PageContent page) async {
    final token = _captureToken;
    final animate = widget.mode != PageTurnMode.none;
    if (!_canWarm(page, token)) return;
    if (animate) {
      await (_usesWindow ? _enqueueWindowCapture(page) : _enqueueCapture(page));
    }
    // 先两侧近邻，再准备第二页；同距离优先最近翻页方向，避免远页抢跑。
    for (var distance = 1; distance <= 2; distance++) {
      for (final next in [controller.next, !controller.next]) {
        if (!_canWarm(page, token)) return;
        final offset = next ? distance : -distance;
        final candidate = _usesWindow && _window.containsKey(offset)
            ? _window[offset]
            : await _prepareWarmPage(next, distance, page, token);
        if (!_canWarm(page, token)) return;
        if (candidate != null) {
          if (_usesWindow) _window[offset] = candidate;
          if (animate) {
            await (_usesWindow
                ? _enqueueWindowCapture(candidate)
                : _enqueueCapture(candidate));
          }
        }
      }
    }
    // 窗口外邻章只在空闲时预取，不能抢占活动翻页。
    for (final next in [controller.next, !controller.next]) {
      if (!_canWarm(page, token)) return;
      if (_usesWindow && controller.active) {
        _lastWarm = null;
        return;
      }
      try {
        await widget.session.prefetchTurnChapter(
          next,
          shouldContinue: () {
            if (_usesWindow && controller.active) {
              _lastWarm = null;
              return false;
            }
            return _canWarm(page, token);
          },
        );
      } catch (_) {
        // 预取错误不影响当前正文，实际翻页时允许重新加载。
      }
    }
  }

  bool _canWarm(PageContent page, int token) =>
      mounted &&
      !_warmSuspended &&
      widget.preload &&
      token == _captureToken &&
      (_usesWindow || !controller.active) &&
      identical(page, widget.session.page);

  Future<PageContent?> _prepareWarmPage(
    bool next,
    int distance,
    PageContent page,
    int token,
  ) async {
    try {
      return (await widget.session.preparePageTurn(
        next,
        prefetch: true,
        distance: distance,
        shouldContinue: () => _canWarm(page, token),
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
      // 位图宽高按像素取整；预算覆盖当前页与前后各两页共五个快照。
      final cacheRatio =
          math.sqrt(
            _cache.maxBytes /
                (size.width * size.height * 4 * _cache.maxEntries),
          ) *
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
        if (!_showAnimation && !identical(page, _staticPage)) {
          _clearStaticImage();
        }
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
          Offstage(
            offstage:
                _showAnimation ||
                (identical(_staticPage, page) && !_staticPaperReady),
            child: RepaintBoundary(
              key: _currentBoundary,
              child: widget.paperBuilder(page, size),
            ),
          ),
          if (!_showAnimation && identical(_staticPage, page))
            Positioned.fill(
              child: IgnorePointer(
                child: RawImage(
                  key: const ValueKey('page-turn-static-snapshot'),
                  image: _staticImage,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.low,
                ),
              ),
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
    _clearStaticImage();
    super.dispose();
  }
}

class _WindowCapture {
  _WindowCapture(this.page, this.token);

  final PageContent page;
  final int token;
  bool urgent = false;
  final result = Completer<ui.Image?>();
}
