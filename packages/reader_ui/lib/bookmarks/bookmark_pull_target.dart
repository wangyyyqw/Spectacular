import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../icons/app_icon.dart';
import 'bookmark_ribbon.dart';
import 'bookmark_style.dart';

/// 仅在分页阅读时启用；纵向手势与正文横向翻页参与同一手势竞争。
class BookmarkPullTarget extends StatefulWidget {
  const BookmarkPullTarget({
    super.key,
    required this.child,
    required this.onToggle,
    required this.bookmarked,
    required this.color,
    required this.background,
    this.pageAnchor,
    this.ribbon,
    this.topInset = 0,
    this.rightInset = 0,
    this.animateReturn = true,
    this.onPullingChanged,
  });

  final Widget child;
  final VoidCallback? onToggle;
  final bool bookmarked;
  final Color color;
  final Color background;
  final String? pageAnchor;
  final ReaderBookmarkRibbon? ribbon;
  final double topInset;
  final double rightInset;
  final bool animateReturn;
  final ValueChanged<bool>? onPullingChanged;

  @override
  State<BookmarkPullTarget> createState() => _BookmarkPullTargetState();
}

class _BookmarkPullTargetState extends State<BookmarkPullTarget> {
  static const _thresholdDp = 128.0;
  static const _dragInsetPixels = 144.0;
  double _dragOffset = 0;
  bool _dragging = false;
  VoidCallback? _toggle;
  bool _hintReady = false;
  bool _hintBookmarked = false;
  bool _pulling = false;

  void _setPulling(bool value) {
    if (_pulling == value) return;
    _pulling = value;
    widget.onPullingChanged?.call(value);
  }

  @override
  void didUpdateWidget(BookmarkPullTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onToggle == null || widget.pageAnchor != oldWidget.pageAnchor) {
      _clearGesture();
    }
  }

  void _clearGesture() {
    _dragging = false;
    _dragOffset = 0;
    _toggle = null;
  }

  void _reset() => setState(_clearGesture);

  void _begin() => setState(() {
    _dragging = true;
    _dragOffset = 0;
    _toggle = widget.onToggle;
    _hintReady = false;
    _hintBookmarked = widget.bookmarked;
  });

  void _update(double delta) {
    if (!_dragging) return;
    setState(() {
      _dragOffset += delta;
      _hintReady = _pageOffset >= _threshold;
    });
    if (_pageOffset > 0) _setPulling(true);
  }

  void _end() {
    final toggle = _dragging && _pageOffset >= _threshold ? _toggle : null;
    _reset();
    toggle?.call();
  }

  double get _threshold {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return (_thresholdDp * ratio).round() / ratio;
  }

  // 先扣除 144 个物理像素，再用纸面位移判断 128dp 阈值。
  double get _pageOffset =>
      (_dragOffset - _dragInsetPixels / MediaQuery.devicePixelRatioOf(context))
          .clamp(0, double.infinity);

  Widget _buildSurface(double offset, Widget? child) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Color.alphaBlend(
            widget.color.withValues(alpha: 0.06),
            widget.background,
          ),
        ),
        if (offset > 0) _buildHint(offset),
        Transform.translate(
          key: const ValueKey('bookmark-pull-page'),
          offset: Offset(0, offset),
          child: ColoredBox(color: widget.background, child: child),
        ),
        // 归位结束先保留已添加的标记，下一帧与纸面同时交接。
        if (widget.ribbon != null &&
            ((offset > 0 && (_hintBookmarked || _hintReady)) ||
                (_pulling && widget.bookmarked)))
          Positioned(
            top: 0,
            right: widget.ribbon!.style.rightInset + widget.rightInset,
            child: IgnorePointer(
              child: Semantics(
                label: widget.bookmarked ? '当前页已有书签' : '添加书签',
                child: widget.ribbon,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buildHintContent() {
    final ready = _hintReady;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        RotatedBox(
          quarterTurns: ready ? 1 : 3,
          child: AppIcon(AppGlyph.arrowBack, size: 18, color: widget.color),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${ready ? '松手确认' : '下拉'}'
            '${_hintBookmarked ? '移除' : '添加'}${ready ? '' : '书签'}',
            style: TextStyle(color: widget.color, fontSize: 14),
            textAlign: TextAlign.end,
          ),
        ),
        const SizedBox(width: 8),
        AppIcon(
          AppGlyph.bookmark,
          size: 20,
          color: widget.color,
          filled: ready,
        ),
      ],
    );
  }

  Widget _buildHint(double offset) => Positioned(
    top: widget.topInset + (offset - _threshold).clamp(-_threshold, 0),
    left: 16,
    right:
        (widget.ribbon?.style.rightInset ??
            const ReaderBookmarkStyle().rightInset) +
        16 +
        widget.rightInset +
        (widget.ribbon?.style.width ?? 0),
    child: Semantics(
      liveRegion: true,
      child: IgnorePointer(child: _buildHintContent()),
    ),
  );

  GestureRecognizerFactory<_BookmarkVerticalDragRecognizer> _gestureFactory() =>
      GestureRecognizerFactoryWithHandlers<_BookmarkVerticalDragRecognizer>(
        () => _BookmarkVerticalDragRecognizer(debugOwner: this),
        (recognizer) {
          recognizer
            ..onDown = ((_) => _begin())
            ..onStart = ((_) => _update(recognizer.start()))
            ..onUpdate = ((details) => _update(details.delta.dy))
            ..onEnd = ((_) => _end())
            ..onCancel = _reset
            ..onlyAcceptDragOnThreshold = true
            ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
        },
      );

  // 手势目标保持原位，只有页面整体位移，避免拖动坐标随正文变化。
  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      if (widget.onToggle != null)
        _BookmarkVerticalDragRecognizer: _gestureFactory(),
    },
    semantics: _BookmarkDragSemantics(
      widget.onToggle == null
          ? null
          : (details) {
              _begin();
              _update(details.delta.dy);
              _end();
            },
    ),
    child: _buildAnimatedPage(),
  );

  // 已被识别的拖动收到系统取消时仍可能回调结束，先清除距离。
  Widget _buildAnimatedPage() => Listener(
    onPointerCancel: (_) => _reset(),
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: widget.onToggle == null ? 0 : _pageOffset),
      duration:
          _dragging ||
              !widget.animateReturn ||
              MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      onEnd: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _dragOffset == 0) _setPulling(false);
        });
      },
      builder: (context, offset, child) => _buildSurface(offset, child),
      child: RepaintBoundary(child: widget.child),
    ),
  );
}

/// 初次按累计主方向锁定；锁定前的采样只用于识别，不推动纸面。
class _BookmarkVerticalDragRecognizer extends VerticalDragGestureRecognizer {
  _BookmarkVerticalDragRecognizer({super.debugOwner});

  Offset _offset = Offset.zero;
  double _lastDelta = 0;
  bool _started = false;

  double start() {
    _started = true;
    return _lastDelta;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_started && event is PointerMoveEvent) {
      _offset += event.localDelta;
      _lastDelta = event.localDelta.dy;
      if (_offset.dx.abs() > computeHitSlop(event.kind, gestureSettings) &&
          _offset.dx.abs() > _offset.dy.abs()) {
        rejectGesture(event.pointer);
        return;
      }
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      _offset.dy.abs() > _offset.dx.abs() &&
      super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      );

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    _offset = Offset.zero;
    _lastDelta = 0;
    _started = false;
  }
}

/// 自定义识别器沿用原生纵向手势的辅助功能生命周期。
class _BookmarkDragSemantics extends SemanticsGestureDelegate {
  const _BookmarkDragSemantics(this.onUpdate);

  final GestureDragUpdateCallback? onUpdate;

  @override
  void assignSemantics(RenderSemanticsGestureHandler renderObject) {
    renderObject.onVerticalDragUpdate = onUpdate;
  }
}
