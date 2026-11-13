part of 'image_preview_page.dart';

/// 视口固定，图片分页在其内部移动，横滑中加入第二指仍能接管缩放。
class _ImagePreviewViewport extends StatefulWidget {
  const _ImagePreviewViewport({
    required this.child,
    required this.index,
    required this.canZoom,
    required this.animate,
    this.pager,
  });

  final Widget child;
  final int index;
  final bool canZoom;
  final bool animate;
  final PageController? pager;

  @override
  State<_ImagePreviewViewport> createState() => _ImagePreviewViewportState();
}

class _ImagePreviewViewportState extends State<_ImagePreviewViewport>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final _zoom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  )..addListener(_animateZoom);
  Matrix4Tween? _zoomTween;
  Drag? _drag;
  var _distance = Offset.zero;
  var _canSwipe = false;
  var _pointers = 0;
  var _multitouch = false;
  Offset? _doubleTapPosition;

  bool get _zoomed => _transform.value.getMaxScaleOnAxis() > 1.001;
  bool get _animate =>
      widget.animate && !MediaQuery.disableAnimationsOf(context);

  @override
  void didUpdateWidget(_ImagePreviewViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    _zoom.stop();
    _transform.value = Matrix4.identity();
    _canSwipe = false;
  }

  @override
  void dispose() {
    _drag?.cancel();
    _zoom.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom([Offset? position]) {
    if (!widget.canZoom) return;
    _cancelSwipe();
    final center = position ?? context.size!.center(Offset.zero);
    final target = _zoomed
        ? Matrix4.identity()
        : (Matrix4.diagonal3Values(3, 3, 1)
            ..setTranslationRaw(-center.dx * 2, -center.dy * 2, 0));
    _zoom.stop();
    if (!_animate) {
      _transform.value = target;
      return;
    }
    _zoomTween = Matrix4Tween(begin: _transform.value.clone(), end: target);
    _zoom.forward(from: 0);
  }

  void _animateZoom() {
    _transform.value = _zoomTween!.transform(
      Curves.easeOutCubic.transform(_zoom.value),
    );
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !widget.canZoom) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    _toggleZoom();
    return KeyEventResult.handled;
  }

  void _startSwipe(int pointers) {
    _zoom.stop();
    if (pointers > 1 || _multitouch) {
      _cancelSwipe();
      return;
    }
    _distance = Offset.zero;
    _canSwipe = widget.pager?.hasClients == true && !_zoomed;
  }

  void _updateInteraction(ScaleUpdateDetails details) {
    if (details.pointerCount > 1 || _zoomed || details.scale != 1) {
      _cancelSwipe();
      return;
    }
    if (!_canSwipe) return;
    _distance += details.focalPointDelta;
    if (_drag == null &&
        _distance.distance > kTouchSlop &&
        _distance.dy.abs() > _distance.dx.abs()) {
      _canSwipe = false;
      return;
    }
    if (!_animate || (_distance.dx.abs() < kTouchSlop && _drag == null)) return;
    final delta = _drag == null ? _distance.dx : details.focalPointDelta.dx;
    _drag ??= widget.pager!.position.drag(
      DragStartDetails(globalPosition: details.focalPoint),
      () => _drag = null,
    );
    _drag!.update(
      DragUpdateDetails(
        globalPosition: details.focalPoint,
        delta: Offset(delta, 0),
        primaryDelta: delta,
      ),
    );
  }

  void _endSwipe(Velocity velocity) {
    final drag = _drag;
    _drag = null;
    if (drag != null) {
      _canSwipe = false;
      final speed = velocity.pixelsPerSecond.dx;
      drag.end(
        DragEndDetails(
          velocity: Velocity(pixelsPerSecond: Offset(speed, 0)),
          primaryVelocity: speed,
        ),
      );
      return;
    }
    final horizontal = _distance.dx.abs();
    if (!_canSwipe || horizontal <= _distance.dy.abs()) return;
    _canSwipe = false;
    final speed = velocity.pixelsPerSecond.dx;
    if (horizontal < context.size!.width / 3 && speed.abs() < 500) return;
    final direction = speed.abs() >= 500 ? speed : _distance.dx;
    final pager = widget.pager!;
    final next = widget.index + (direction < 0 ? 1 : -1);
    final last =
        (pager.position.maxScrollExtent / pager.position.viewportDimension)
            .round();
    pager.jumpToPage(next.clamp(0, last));
  }

  void _cancelSwipe() {
    _canSwipe = false;
    final drag = _drag;
    _drag = null;
    if (drag == null) return;
    drag.cancel();
    widget.pager?.jumpToPage(widget.index);
  }

  void _pointerDown(PointerDownEvent event) {
    _pointers++;
    if (_pointers < 2) return;
    _multitouch = true;
    _cancelSwipe();
  }

  void _pointerUp(PointerEvent event) {
    _pointers = (_pointers - 1).clamp(0, _pointers);
    if (_pointers == 0) _multitouch = false;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _key,
    child: Listener(
      onPointerDown: _pointerDown,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      child: GestureDetector(
        onDoubleTapDown: widget.canZoom
            ? (details) => _doubleTapPosition = details.localPosition
            : null,
        onDoubleTap: widget.canZoom
            ? () => _toggleZoom(_doubleTapPosition)
            : null,
        child: _viewer(),
      ),
    ),
  );

  Widget _viewer() => Semantics(
    image: widget.canZoom,
    label: widget.canZoom ? '图片' : null,
    hint: widget.canZoom ? '双击放大，再次双击还原' : null,
    onTap: widget.canZoom ? _toggleZoom : null,
    child: InteractiveViewer(
      key: const ValueKey<String>('preview-viewer'),
      transformationController: _transform,
      scaleEnabled: widget.canZoom,
      panEnabled: widget.canZoom,
      maxScale: 8,
      onInteractionStart: (details) => _startSwipe(details.pointerCount),
      onInteractionUpdate: _updateInteraction,
      onInteractionEnd: (details) => _endSwipe(details.velocity),
      child: widget.child,
    ),
  );
}
