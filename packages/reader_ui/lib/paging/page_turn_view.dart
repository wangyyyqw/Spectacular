import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:reader_core/layout/paginator.dart';

import '../reader_session.dart';
import 'chapter_preload_controller.dart';
import 'duokan_curl_shader.dart';
import 'page_snapshot_cache.dart';
import 'page_turn_controller.dart';
import 'page_turn_mode.dart';
import 'page_turn_painter.dart';

/// 静态纸面和目标纸面共用同一个构建器，保证快照与排版一致。
typedef ReaderPaperBuilder = Widget Function(PageContent page, Size size);

/// 生成纸面快照前解码该页图片，避免翻页完成后才补图。
typedef ReaderPageImagesPreparer = Future<void> Function(PageContent page);

/// 不含正文的阅读主题纸底，与完整纸面使用同一套背景绘制。
typedef ReaderPaperBackgroundPainter = void Function(Canvas canvas, Size size);

class PageTurnView extends StatefulWidget {
  const PageTurnView({
    super.key,
    required this.session,
    required this.mode,
    required this.revision,
    required this.paperBuilder,
    required this.paperColor,
    this.preparePageImages,
    this.paintBackground,
    this.preload = true,
    this.rtl = false,
  });

  final ReaderSession session;
  final PageTurnMode mode;
  final Object revision;
  final ReaderPaperBuilder paperBuilder;
  final Color paperColor;
  final ReaderPageImagesPreparer? preparePageImages;
  final ReaderPaperBackgroundPainter? paintBackground;
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
  bool _pageCountsDirty = false;
  late int _pageCountRevision = widget.session.pageCountRevision;
  bool _pageDirty = false;
  bool _warmSuspended = false;
  PageContent? _renderedPage;
  PageContent? _staticPage;
  ui.Image? _staticImage;
  ui.Image? _backgroundImage;
  bool _staticPaperReady = false;
  int _staticToken = 0;
  final _window = <int, PageContent>{};
  final _snapshotPageCounts = <PageContent, int>{};
  final _captures = <PageContent, _WindowCapture>{};
  final _imagePreparations = <PageContent, Future<void>>{};
  final _pendingCaptures = <_WindowCapture>[];
  bool _capturingWindow = false;
  PageContent? _windowPage;
  Timer? _warmTimer;
  int _warmToken = 0;
  bool _warmingAllowed = false;
  bool _turnActive = false;
  late final _chapterPreload = ChapterPreloadController(
    widget.session,
    onFirstPage: () {
      if (!mounted) return;
      _lastWarm = null;
      _scheduleWarm();
    },
  );

  static const _warmDelay = Duration(milliseconds: 100);
  static const _busyRetryDelay = Duration(milliseconds: 50);

  bool get _usesWindow => widget.mode != PageTurnMode.scroll;

  Set<PageContent> get _windowPages => _window.values.toSet();

  int get snapshotBytes =>
      _cache.bytes +
      (_backgroundImage == null
          ? 0
          : _backgroundImage!.width * _backgroundImage!.height * 4);
  int get snapshotCount => _cache.length + (_backgroundImage == null ? 0 : 1);

  /// 该页由完整快照承接，补图后的静态重绘交给本视口统一恢复。
  bool isPresentingSnapshot(PageContent page) => identical(_staticPage, page);

  @override
  void didUpdateWidget(PageTurnView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final countsChanged =
        _pageCountRevision != widget.session.pageCountRevision;
    _pageCountRevision = widget.session.pageCountRevision;
    if (oldWidget.revision != widget.revision ||
        oldWidget.mode != widget.mode ||
        oldWidget.rtl != widget.rtl) {
      if (controller.active) {
        _revisionDirty = true;
      } else {
        _invalidate(retainStaticImage: true);
      }
    } else if (countsChanged) {
      if (controller.active) {
        _pageCountsDirty = true;
      } else {
        _refreshPageCounts();
      }
    }
    if (oldWidget.preload != widget.preload) {
      _pauseWarmup();
      if (!widget.preload) widget.session.cancelTurnPrefetch();
    }
  }

  void _invalidate({bool retainStaticImage = false}) {
    _revisionDirty = false;
    _pageCountsDirty = false;
    if (controller.active) controller.cancel();
    _captureToken++;
    _pauseWarmup();
    _capturePage = null;
    _lastWarm = null;
    _window.clear();
    _windowPage = null;
    _captures.clear();
    _imagePreparations.clear();
    _cache.clear();
    _snapshotPageCounts.clear();
    _clearBackgroundImage();
    if (retainStaticImage &&
        _staticImage != null &&
        identical(_staticPage, widget.session.page)) {
      // 绘制版本失效不撤下落页快照；新版原图和静态纸面就绪后再交接。
      _staticToken++;
      _staticPaperReady = false;
      unawaited(_restoreStaticPaper());
    } else {
      _clearStaticImage();
    }
  }

  void _refreshPageCounts() {
    _pageCountsDirty = false;
    bool stale(PageContent page) =>
        _snapshotPageCounts[page] !=
        widget.session.pageCountOf(page.spineIndex);
    final restore = _staticPage != null && stale(_staticPage!);
    _captureToken++;
    _pauseWarmup();
    _capturePage = null;
    _captures.clear();
    _cache.removeWhere(stale);
    _snapshotPageCounts.removeWhere((page, _) => stale(page));
    // 只重绘页码变化的纸面，保留邻页窗口、图片准备和正在补全的章节作业。
    if (restore) {
      _staticToken++;
      _staticPaperReady = false;
      unawaited(_restoreStaticPaper());
    }
  }

  void _clearBackgroundImage() {
    _backgroundImage?.dispose();
    _backgroundImage = null;
    _cache.reservedBytes = 0;
  }

  void _controllerChanged() {
    if (!mounted) return;
    if (controller.active != _turnActive) {
      _turnActive = controller.active;
      _pauseWarmup();
      if (!_turnActive) {
        for (final capture in _captures.values) {
          capture.urgent = false;
        }
      }
    }
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
        _invalidate(retainStaticImage: true);
        return;
      }
      if (_pageCountsDirty) _refreshPageCounts();
      if (_pageDirty) _cancelPendingCaptures();
    }
    _scheduleWarm();
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
    final generation = widget.session.generation;
    final result = _captureQueue.then(
      (_) => _capture(
        page,
        token,
        shouldCapture: () => generation == widget.session.generation,
      ),
    );
    _captureQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<ui.Image?> _acquireTurnImage(PageContent page) async {
    final token = _captureToken;
    final generation = widget.session.generation;
    if (_usesWindow && identical(page, controller.turn?.target.content)) {
      // 冷目标也属于这次窗口，提交后可平移并保留刚读过的原页。
      _window[controller.next ? 1 : -1] = page;
    }
    if (widget.mode == PageTurnMode.simulation3d) {
      await _prepareCurlBackground();
      if (!mounted ||
          token != _captureToken ||
          generation != widget.session.generation) {
        return null;
      }
    }
    if (_usesWindow) return _enqueueWindowCapture(page, urgent: true);
    return _enqueueCapture(page);
  }

  Future<void> _prepareCurlBackground() async {
    final token = _captureToken;
    final generation = widget.session.generation;
    await DuokanCurlShader.load();
    if (!mounted ||
        token != _captureToken ||
        generation != widget.session.generation ||
        _backgroundImage != null) {
      return;
    }
    final paint = widget.paintBackground;
    if (paint == null || _size.isEmpty) return;
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder)..scale(_ratio), _size);
    final picture = recorder.endRecording();
    try {
      _backgroundImage = picture.toImageSync(
        (_size.width * _ratio).ceil(),
        (_size.height * _ratio).ceil(),
      );
      _cache.reservedBytes =
          _backgroundImage!.width * _backgroundImage!.height * 4;
    } finally {
      picture.dispose();
    }
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
    _pauseWarmup();
    _cache.retainPages(_windowPages);
    _snapshotPageCounts.removeWhere((page, _) => !_retainCapture(page));
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
    final generation = widget.session.generation;
    if (capture != null &&
        capture.token == _captureToken &&
        capture.generation == generation) {
      if (urgent) capture.urgent = true;
      if (urgent && _pendingCaptures.remove(capture)) {
        _pendingCaptures.insert(0, capture);
        unawaited(_drainWindowCaptures());
      }
      return capture.result.future;
    }
    capture = _WindowCapture(page, _captureToken, generation)..urgent = urgent;
    _captures[page] = capture;
    unawaited(_prepareWindowCapture(capture));
    return capture.result.future;
  }

  Future<void> _prepareWindowCapture(_WindowCapture capture) async {
    try {
      await _prepareImages(capture.page);
      if (!mounted ||
          capture.token != _captureToken ||
          capture.generation != widget.session.generation) {
        capture.result.complete(null);
        if (identical(_captures[capture.page], capture)) {
          _captures.remove(capture.page);
        }
        return;
      }
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

  Future<void> _prepareImages(PageContent page) {
    final existing = _imagePreparations[page];
    if (existing != null) return existing;
    late final Future<void> pending;
    pending = Future<void>.sync(() => widget.preparePageImages?.call(page))
        .whenComplete(() {
          if (identical(_imagePreparations[page], pending)) {
            _imagePreparations.remove(page);
          }
        });
    _imagePreparations[page] = pending;
    return pending;
  }

  Future<void> _drainWindowCaptures() async {
    if (_capturingWindow) return;
    _capturingWindow = true;
    try {
      while (_pendingCaptures.isNotEmpty) {
        final index = controller.active || !_warmingAllowed
            ? _pendingCaptures.indexWhere((capture) => capture.urgent)
            : 0;
        if (index < 0) break;
        final capture = _pendingCaptures.removeAt(index);
        try {
          final image = await _capture(
            capture.page,
            capture.token,
            imagesPrepared: true,
            shouldCapture: () =>
                capture.generation == widget.session.generation &&
                (capture.urgent ||
                    (_warmingAllowed &&
                        !controller.active &&
                        !widget.session.loading &&
                        widget.session.jumpLoadingTitle == null)),
          );
          capture.result.complete(image);
        } catch (error, stack) {
          capture.result.completeError(error, stack);
        } finally {
          if (identical(_captures[capture.page], capture)) {
            _captures.remove(capture.page);
          }
        }
        // 每张后台快照之间让出一帧，输入与前台请求可先处理。
        if (!capture.urgent) await WidgetsBinding.instance.endOfFrame;
      }
    } finally {
      _capturingWindow = false;
    }
  }

  Future<ui.Image?> _capture(
    PageContent page,
    int token, {
    bool imagesPrepared = false,
    bool Function()? shouldCapture,
  }) async {
    bool valid() =>
        mounted &&
        token == _captureToken &&
        (shouldCapture?.call() ?? true) &&
        (!_usesWindow || _retainCapture(page));
    if (!valid()) return null;
    // 完整快照可直接翻动；静态纸面所需原图在落页时独立恢复。
    final cached = _cache.get(page);
    if (cached != null) return cached;
    if (!imagesPrepared) {
      await _prepareImages(page);
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
    final pageCount = widget.session.pageCountOf(page.spineIndex);
    var current = _usesCurrentBoundary(page);
    if (!current) setState(() => _capturePage = page);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        // 活动翻页继续取得纸面，页码版本差异留到落页后局部刷新。
        if (!valid() ||
            (!controller.active &&
                pageCount != widget.session.pageCountOf(page.spineIndex))) {
          return null;
        }
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
          _snapshotPageCounts[page] = pageCount;
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
    _chapterPreload.update(
      paused: _warmSuspended || !widget.preload || controller.active,
    );
    if (_warmSuspended || !widget.preload || !mounted) {
      return;
    }
    if (widget.session.loading || widget.session.jumpLoadingTitle != null) {
      _pauseWarmup();
      return;
    }
    if (_usesWindow) _syncWindow();
    final page = widget.session.page;
    final generation = widget.session.generation;
    final key = (
      page,
      widget.revision,
      _size,
      _ratio,
      generation,
      widget.session.availablePagesRevision,
    );
    if (page == null || _size.isEmpty || key == _lastWarm) return;
    _lastWarm = key;
    _warmTimer?.cancel();
    _startWarmTimer(page, _warmToken, generation, _warmDelay);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _warmTimer != null) {
        WidgetsBinding.instance.scheduleFrame();
      }
    });
  }

  void _pauseWarmup() {
    _chapterPreload.update(
      paused: _warmSuspended || !widget.preload || controller.active,
    );
    _warmToken++;
    _warmTimer?.cancel();
    _warmTimer = null;
    _warmingAllowed = false;
    _lastWarm = null;
  }

  void _startWarmTimer(
    PageContent page,
    int token,
    int generation,
    Duration delay,
  ) {
    _warmTimer = Timer(delay, () {
      _warmTimer = null;
      if (!mounted ||
          token != _warmToken ||
          generation != widget.session.generation ||
          _warmSuspended ||
          !widget.preload ||
          widget.session.loading ||
          widget.session.jumpLoadingTitle != null ||
          !identical(page, widget.session.page)) {
        return;
      }
      if (controller.active) {
        _startWarmTimer(page, token, generation, _busyRetryDelay);
        return;
      }
      _warmingAllowed = true;
      if (_usesWindow) unawaited(_drainWindowCaptures());
      unawaited(
        _warm(page, token, generation).catchError((Object _) {
          // 预热失败由实际翻页重新请求，不向阅读界面抛出后台异常。
        }),
      );
    });
  }

  Future<void> _warm(PageContent page, int token, int generation) async {
    final animate = widget.mode != PageTurnMode.none;
    if (!_canWarm(page, token, generation)) return;
    if (widget.mode == PageTurnMode.simulation3d) {
      await _prepareCurlBackground();
      if (!_canWarm(page, token, generation)) return;
    }
    final current = animate
        ? (_usesWindow ? _enqueueWindowCapture(page) : _enqueueCapture(page))
        : Future<ui.Image?>.value();
    if (_chapterPreload.firstPage case final first?) {
      unawaited(_warmChapterResources(first, page, token, generation, current));
    }
    await current;
    // 先两侧近邻，再准备第二页；同距离优先最近翻页方向，避免远页抢跑。
    for (var distance = 1; distance <= 2; distance++) {
      for (final next in [controller.next, !controller.next]) {
        if (!_canWarm(page, token, generation)) return;
        final offset = next ? distance : -distance;
        final candidate = _usesWindow && _window.containsKey(offset)
            ? _window[offset]
            : await _prepareWarmPage(next, distance, page, token, generation);
        if (!_canWarm(page, token, generation)) return;
        if (candidate != null) {
          if (_usesWindow) _window[offset] = candidate;
          if (animate) {
            if (_cache.get(candidate) != null) continue;
            await (_usesWindow
                ? _enqueueWindowCapture(candidate)
                : _enqueueCapture(candidate));
          }
        }
      }
    }
  }

  Future<void> _warmChapterResources(
    PageContent first,
    PageContent page,
    int token,
    int generation,
    Future<ui.Image?> current,
  ) async {
    try {
      if (_canWarm(page, token, generation)) {
        // 内容排版可先行，首页原图等当前纸面完成后再让出一帧启动。
        await current;
        await WidgetsBinding.instance.endOfFrame;
        if (!_canWarm(page, token, generation)) return;
        // 窗口外仅预解码首页，进入近邻窗口后再生成位图，保持既有内存预算。
        if (!_windowPages.contains(first) &&
            !widget.session.adjacentPages.contains(first)) {
          await _prepareImages(first);
        }
      }
    } catch (_) {
      // 预取失败不影响当前正文，实际翻页可重新请求。
    }
  }

  bool _canWarm(PageContent page, int token, int generation) =>
      mounted &&
      !_warmSuspended &&
      widget.preload &&
      token == _warmToken &&
      generation == widget.session.generation &&
      !widget.session.loading &&
      widget.session.jumpLoadingTitle == null &&
      _warmingAllowed &&
      !controller.active &&
      identical(page, widget.session.page);

  Future<PageContent?> _prepareWarmPage(
    bool next,
    int distance,
    PageContent page,
    int token,
    int generation,
  ) async {
    try {
      return (await widget.session.preparePageTurn(
        next,
        prefetch: true,
        distance: distance,
        shouldContinue: () => _canWarm(page, token, generation),
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
      // 纹理纸底占用同一预算，六张容量覆盖五张页面与一张纸底。
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
                    backgroundImage: _backgroundImage,
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
    _warmTimer?.cancel();
    _chapterPreload.dispose();
    widget.session.cancelTurnPrefetch();
    controller.removeListener(_controllerChanged);
    controller.dispose();
    widget.session.setBackgroundLayoutPaused(false);
    _cache.clear();
    _clearBackgroundImage();
    _clearStaticImage();
    super.dispose();
  }
}

class _WindowCapture {
  _WindowCapture(this.page, this.token, this.generation);

  final PageContent page;
  final int token;
  final int generation;
  bool urgent = false;
  final result = Completer<ui.Image?>();
}
