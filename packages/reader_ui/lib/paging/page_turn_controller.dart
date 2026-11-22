import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';

import '../reader_session.dart';
import 'bessel_geometry.dart';
import 'curl3d_geometry.dart';
import 'page_turn_mode.dart';

/// 翻页阶段；只有收尾成功才提交阅读位置。
enum PageTurnPhase { idle, preparing, dragging, settling }

/// 动画只改变帧参数，不触发正文 build、分页或截图。
class PageTurnController extends ChangeNotifier {
  PageTurnController({
    required this.session,
    required TickerProvider vsync,
    required this.acquireImage,
    this.onBookEnd,
    this.onError,
  }) {
    _settling = AnimationController(vsync: vsync)..addListener(_animateFrame);
    _targetFade = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 100),
    )..addListener(_targetFadeFrame);
    _positionCatchUp = vsync.createTicker(_catchUpPositionFrame);
    session.addListener(_sessionChanged);
  }

  final ReaderSession session;
  final Future<ui.Image?> Function(PageContent page) acquireImage;
  final VoidCallback? onBookEnd;

  /// 当前翻页准备失败时通知宿主；取消和过期任务不触发。
  final void Function(Object error)? onError;
  late final AnimationController _settling;
  late final AnimationController _targetFade;
  late final Ticker _positionCatchUp;
  Duration _catchUpElapsed = Duration.zero;
  bool _preparationVisible = false;
  bool _lifting = false, _rejected3dDrag = false;
  bool _starting3dAnimation = false;
  Timer? _tapRelease;
  Curl3dGeometry? _lastCurlGeometry;

  static const _catchUpFrameLimit = Duration(milliseconds: 16);
  static const _catchUpResponse = Duration(milliseconds: 50);
  static const _catchUpTravel = Duration(milliseconds: 320);
  static const _dragCatchUpResponse = Duration(milliseconds: 32);
  static const _dragCatchUpTravel = Duration(milliseconds: 160);

  /// 冷目标露底渐入，独立于折角位置的追赶。
  double get targetOpacity => _targetFade.isAnimating ? _targetFade.value : 1;
  PageTurnPhase phase = PageTurnPhase.idle;
  PageTurnMode mode = PageTurnMode.cover;
  ui.Size size = ui.Size.zero;
  bool rtl = false;
  bool next = true;
  bool top = false;
  bool horizontal = true;
  double progress = 0;
  ui.Offset? point;

  /// 3D 仿真抓取点；前后翻页均使用当前页的右缘规范坐标。
  ui.Offset? grab;
  ui.Image? originImage, targetImage;
  PreparedPageTurn? turn;
  ui.Offset? _down, _latest;
  ui.Offset? _pointerDown;
  _PendingDrag? _pendingDrag;
  _DragMotion? _dragMotion;
  bool _released = false, _complete = true, _dragging = false;
  bool _dragAtBookEnd = false;
  bool _disposed = false, _committing = false;
  final List<bool> _queued = <bool>[];
  int _token = 0;
  double _startProgress = 0;
  ui.Offset? _startPoint, _endPoint;
  double _releaseVelocity = 0;
  Curve _settlingCurve = Curves.easeOutCubic;
  int? _generation;
  PageContent? _origin;

  bool get active => phase != PageTurnPhase.idle;

  /// 活动纸的物理起卷侧；前后翻页的轴互为镜像。
  bool get fromRight => next != rtl;

  /// 3D 单页几何使用固定抓取点与实际显示触点。
  Curl3dGeometry? get curl3dGeometry {
    final anchor = grab;
    final current = point;
    if (anchor == null || current == null) return null;
    final geometry = Curl3dGeometry(size: size, grab: anchor, touch: current);
    if (geometry.active) _lastCurlGeometry = geometry;
    // 原生越过右缘时保留最后网格；尚未起卷的新轮仍使用平面初态。
    return geometry.active ? geometry : _lastCurlGeometry ?? geometry;
  }

  /// 前后翻页共用右侧规范坐标，绘制时按起卷侧镜像。
  BesselGeometry? get besselGeometry {
    final current = point;
    return current == null
        ? null
        : BesselGeometry.resolve(
            size,
            current,
            top: top,
            horizontal: horizontal,
          );
  }

  /// 原始按下位置只记录，不抢占长按、链接或选区手势。
  void pointerDown(ui.Offset position) {
    if (active && mode.is3d) return;
    _pointerDown = position;
  }

  /// 3D 活动期间拒绝新输入；其余模式的离散输入依次排队。
  void request(bool next) {
    if (active) {
      if (!mode.is3d) _queued.add(next);
      return;
    }
    if (mode.is3d) {
      _down = ui.Offset(
        next != rtl ? 0 : size.width,
        _pointerDown?.dy ?? size.height / 2,
      );
      _pointerDown = null;
    } else {
      _down = ui.Offset(next != rtl ? size.width : 0, size.height / 2);
    }
    _latest = _down;
    unawaited(_prepare(next, dragging: false));
  }

  void beginDrag(DragStartDetails details) {
    final down = mode.is3d
        ? details.localPosition
        : _pointerDown ?? details.localPosition;
    _pointerDown = null;
    if (active) {
      if (mode.is3d) {
        _rejected3dDrag = true;
        return;
      }
      // 下一次滑动单独记录，不能覆盖仍在准备或收尾的翻页触点。
      _pendingDrag = _PendingDrag(
        down,
        details.localPosition,
        session.generation,
      );
      return;
    }
    _rejected3dDrag = false;
    _down = down;
    _latest = details.localPosition;
    _dragMotion = _DragMotion(down.dx)..update(details.localPosition.dx);
    _dragging = true;
  }

  void updateDrag(DragUpdateDetails details) {
    if (_rejected3dDrag) return;
    final pending = _pendingDrag;
    if (pending != null) {
      pending.latest = details.localPosition;
      pending.motion.update(details.localPosition.dx);
      return;
    }
    if (!_dragging || phase == PageTurnPhase.settling) return;
    final inputDelta = details.localPosition - _latest!;
    _latest = details.localPosition;
    final motion = _dragMotion!..update(_latest!.dx);
    final initialSign = motion.initialSign;
    if (!active && initialSign != null) {
      unawaited(_prepare((initialSign < 0) != rtl, dragging: true));
    }
    if (phase == PageTurnPhase.dragging ||
        (phase == PageTurnPhase.preparing && originImage != null)) {
      _updateDragFrame(inputDelta: inputDelta);
    }
  }

  void endDrag(DragEndDetails details) {
    if (_rejected3dDrag) {
      _rejected3dDrag = false;
      return;
    }
    final pending = _pendingDrag;
    if (pending != null) {
      _endPendingDrag(pending, details.primaryVelocity ?? 0);
      return;
    }
    if (!_dragging) return;
    _positionCatchUp.stop();
    if (mode.is3d) _stopLifting();
    _released = true;
    _dragging = false;
    _releaseVelocity = details.primaryVelocity ?? 0;
    if (_dragAtBookEnd) {
      _finishBoundary(_shouldComplete());
      return;
    }
    if (phase == PageTurnPhase.dragging) _settle(_shouldComplete());
    if (phase == PageTurnPhase.preparing && !_shouldComplete()) {
      if (originImage == null || mode == PageTurnMode.none) {
        cancel();
      } else {
        _settle(false);
      }
    }
    if (!active) _resetPointer();
  }

  void _endPendingDrag(_PendingDrag pending, double velocity) {
    _pendingDrag = null;
    final initialSign = pending.motion.initialSign;
    if (initialSign == null) return;
    final direction = (initialSign < 0) != rtl;
    if (pending.generation == session.generation &&
        _acceptSwipe(
          pending.latest.dx - pending.down.dx,
          velocity,
          direction,
          pending.motion.lastSign,
        )) {
      request(direction);
    }
  }

  /// 仅取消真实拖动；轻点也会触发拖动手势取消，不能影响点击翻页队列。
  void cancelDrag() {
    if (_rejected3dDrag) {
      _rejected3dDrag = false;
      return;
    }
    if (_pendingDrag != null) {
      _pendingDrag = null;
      _pointerDown = null;
      return;
    }
    if (!_dragging) return;
    cancel();
  }

  Future<void> _prepare(bool direction, {required bool dragging}) async {
    if (size.isEmpty || _disposed || session.page == null) return;
    final token = _beginPreparation(direction, dragging);
    if (_handleBookEnd(direction, dragging)) return;
    try {
      // 原页与目标资源同时准备；视口只将实际截图串行，避免解码相互阻塞。
      final ready = await Future.wait([
        _prepareOrigin(token, dragging),
        _prepareDestination(token, direction, dragging),
      ], eagerError: true);
      if (!_valid(token) || ready.any((value) => !value)) return;
      _activatePreparedTurn(dragging);
    } catch (error) {
      if (!_valid(token)) return;
      cancel();
      if (error is! ChapterLoadCancelled) onError?.call(error);
    }
  }

  Future<bool> _prepareDestination(
    int token,
    bool direction,
    bool dragging,
  ) async {
    final prepared = await session.preparePageTurn(direction);
    if (!_valid(token)) {
      if (prepared != null) session.releasePageTurn(prepared);
      return false;
    }
    if (prepared == null) {
      if (!_handleBookEnd(direction, dragging)) cancel();
      return false;
    }
    turn = prepared;
    return _prepareTarget(token, prepared);
  }

  bool _handleBookEnd(bool direction, bool dragging) {
    if (!direction || onBookEnd == null || !session.atBookEnd) return false;
    if (dragging && _dragging) {
      _dragAtBookEnd = true;
    } else {
      _finishBoundary(!dragging || _shouldComplete());
    }
    return true;
  }

  void _finishBoundary(bool complete) {
    cancel();
    if (complete) onBookEnd?.call();
  }

  int _beginPreparation(bool direction, bool dragging) {
    final token = ++_token;
    next = direction;
    _generation = session.generation;
    _origin = session.page;
    phase = PageTurnPhase.preparing;
    _released = !dragging && !mode.is3d;
    progress = 0;
    _preparationVisible = false;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_valid(token) &&
          phase == PageTurnPhase.preparing &&
          originImage != null) {
        _preparationVisible = true;
      }
    });
    _initializePoint();
    notifyListeners();
    return token;
  }

  Future<bool> _prepareTarget(int token, PreparedPageTurn prepared) async {
    if (mode == PageTurnMode.none) return true;
    final target = await acquireImage(prepared.target.content);
    if (!_valid(token)) return false;
    if (target == null) {
      cancel();
      return false;
    }
    targetImage = target;
    return true;
  }

  void _activatePreparedTurn(bool dragging) {
    phase = PageTurnPhase.dragging;
    // 已松手时从等待期间实际显示的位置接续；3D 只渐入底页，不插值折角。
    if (_preparationVisible && mode != PageTurnMode.none) {
      _startCatchUp();
    } else if (dragging && !_released) {
      _updateDragFrame();
    }
    notifyListeners();
    if (_released) {
      _settle(dragging ? _shouldComplete() : true);
    }
  }

  Future<bool> _prepareOrigin(int token, bool dragging) async {
    if (mode == PageTurnMode.none) return true;
    final origin = await acquireImage(_origin!);
    if (!_valid(token)) return false;
    if (origin == null) {
      cancel();
      return false;
    }
    originImage = origin;
    if (mode.is3d) {
      if (!_released) _startLifting(token);
      if (!dragging) _scheduleTapRelease(token);
    } else if (dragging) {
      _updateDragFrame();
    }
    return true;
  }

  void _startLifting(int token) {
    _lifting = true;
    _startPoint = grab;
    _endPoint = _curlPointer();
    _settling.duration = _curlDuration(_startPoint!, _endPoint!, lifting: true);
    unawaited(_runLifting(token));
  }

  Future<void> _runLifting(int token) async {
    try {
      await _startCurlAnimation().orCancel;
      if (!_valid(token) || !_lifting) return;
      _lifting = false;
      if (!_released) _updateDragFrame();
    } on TickerCanceled {
      // 松手从已显示的位置接续，旧起手动画不能再回写触点。
    }
  }

  void _stopLifting() {
    if (!_lifting) return;
    _settling.stop(canceled: true);
    _lifting = false;
  }

  void _scheduleTapRelease(int token) {
    if (!_valid(token)) return;
    _tapRelease = Timer(Duration(milliseconds: next ? 50 : 75), () {
      if (!_valid(token)) return;
      _tapRelease = null;
      _stopLifting();
      _released = true;
      if (phase == PageTurnPhase.dragging) _settle(true);
    });
  }

  bool _valid(int token) => !_disposed && token == _token;

  ui.Offset _canonical(ui.Offset position) {
    return ui.Offset(
      fromRight ? position.dx : size.width - position.dx,
      position.dy,
    );
  }

  void _initializePoint() {
    final down = _canonical(_down!);
    if (mode.is3d) {
      _initializeCurlPoint(down);
      return;
    }
    top = down.dy < size.height / 2;
    // 起手所在的中心二十分之一从侧边卷起；手势内固定类型，跨区不跳变。
    horizontal = (down.dy - size.height / 2).abs() <= size.height / 40;
    final edge = ui.Offset(size.width, down.dy.clamp(0.1, size.height - 0.1));
    grab = horizontal ? edge : ui.Offset(size.width, top ? 0.0 : size.height);
    point = edge;
  }

  void _initializeCurlPoint(ui.Offset down) {
    top = down.dy < size.height / 2;
    // 仅中央 5% 从整条侧边起卷，其余抓上/下页角；整次手势固定起卷方式。
    horizontal = (down.dy - size.height / 2).abs() <= size.height / 40;
    final y = horizontal ? size.height / 2 : (top ? 0.0 : size.height);
    grab = ui.Offset(size.width, y);
    point = grab;
  }

  ui.Offset _curlPointer() {
    final pointer = _canonical(_latest!);
    return horizontal ? ui.Offset(pointer.dx, size.height / 2) : pointer;
  }

  double _curlProgress() {
    final distance = size.width - point!.dx;
    final value = (distance / (2 * size.width)).clamp(0.0, 1.0);
    return phase == PageTurnPhase.preparing ? value.clamp(0.0, 0.08) : value;
  }

  void _updateDragFrame({ui.Offset inputDelta = ui.Offset.zero}) {
    if (mode.is3d && (_lifting || _released)) return;
    if (_positionCatchUp.isActive) {
      if (mode.is3d || inputDelta == ui.Offset.zero) {
        return;
      }
      // 补偿只由 ticker 推进，新手势位移仍立即叠加到当前显示位置。
      _followCatchUpInput(inputDelta);
    } else {
      _resolveDragFrame();
    }
    if (phase == PageTurnPhase.preparing && !_preparationVisible) {
      final token = _token;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_valid(token) && phase == PageTurnPhase.preparing) {
          _preparationVisible = true;
        }
      });
    }
    notifyListeners();
  }

  void _followCatchUpInput(ui.Offset delta) {
    if (mode == PageTurnMode.simulationBessel) {
      final moved =
          point! + ui.Offset(fromRight ? delta.dx : -delta.dx, delta.dy);
      point = ui.Offset(
        moved.dx.clamp(-size.width, size.width),
        moved.dy.clamp(0.1, size.height - 0.1),
      );
      progress = ((size.width - point!.dx) / (2 * size.width)).clamp(0, 1);
    } else {
      final sign = next != rtl ? -1 : 1;
      progress = (progress + delta.dx * sign / size.width).clamp(0, 1);
    }
  }

  void _resolveDragFrame() {
    if (mode == PageTurnMode.simulationBessel) {
      final latest = _canonical(_latest!);
      point = ui.Offset(
        latest.dx.clamp(-size.width, size.width),
        latest.dy.clamp(0.1, size.height - 0.1),
      );
      progress = ((size.width - point!.dx) / (2 * size.width)).clamp(0, 1);
    } else if (mode.is3d) {
      point = _curlPointer();
      progress = _curlProgress();
    } else {
      final sign = (next != rtl) ? -1 : 1;
      progress = ((_latest!.dx - _down!.dx) * sign / size.width).clamp(0, 1);
    }
    // 冷目标等待时限制进度元数据；贝塞尔同时限制折角位置。
    if (phase == PageTurnPhase.preparing && progress > 0.08) {
      progress = 0.08;
      if (mode == PageTurnMode.simulationBessel) {
        point = ui.Offset(size.width * 0.84, point!.dy);
      }
    }
  }

  void _startCatchUp() {
    if (!mode.is3d && !_released) {
      _startPositionCatchUp();
    }
    // 接续的正文保持原始不透明度，冷页就绪后只追赶同一个逐行时钟。
    if (mode != PageTurnMode.continuation) _targetFade.forward(from: 0);
    if (mode.is3d && !_released) _updateDragFrame();
  }

  void _targetFadeFrame() {
    if (!_disposed) notifyListeners();
  }

  void _startPositionCatchUp() {
    _catchUpElapsed = Duration.zero;
    _positionCatchUp.start();
  }

  /// 丢帧只延长补偿；3D 每帧最多推进页宽的 5%，其余模式最多 10%。
  void _catchUpPositionFrame(Duration elapsed) {
    final delta = elapsed - _catchUpElapsed;
    _catchUpElapsed = elapsed;
    final waiting3d = mode.is3d && phase == PageTurnPhase.preparing;
    if ((!waiting3d && phase != PageTurnPhase.dragging) ||
        _released ||
        _disposed) {
      _positionCatchUp.stop();
      return;
    }
    final micros = math.min(
      delta.inMicroseconds,
      _catchUpFrameLimit.inMicroseconds,
    );
    if (micros <= 0) return;
    _advanceCatchUpPosition(micros);
    notifyListeners();
  }

  void _advanceCatchUpPosition(int frameMicros) {
    final previousPoint = point;
    final previousProgress = progress;
    _resolveDragFrame();
    final pointBased = mode == PageTurnMode.simulationBessel || mode.is3d;
    final distance = pointBased
        ? (point! - previousPoint!).distance
        : (progress - previousProgress).abs() * size.width;
    if (distance <= 0.5) {
      _positionCatchUp.stop();
      return;
    }
    final curl = mode.is3d;
    final response = curl ? _catchUpResponse : _dragCatchUpResponse;
    final travel = curl ? _catchUpTravel : _dragCatchUpTravel;
    // 接近触点时减速；非 3D 加快冷页面补偿，不延迟新的手势输入。
    final t = math.min(
      frameMicros / response.inMicroseconds,
      size.width * frameMicros / (travel.inMicroseconds * distance),
    );
    progress = previousProgress + (progress - previousProgress) * t;
    if (pointBased) point = ui.Offset.lerp(previousPoint, point, t);
    if (mode.is3d) progress = _curlProgress();
  }

  bool _shouldComplete() {
    var dx = _latest!.dx - _down!.dx;
    if (mode.is3d && dx == 0) {
      // 普通移动相互抵消时，多看回退到起手累计位移。
      dx = _dragMotion?.initialDelta ?? 0;
    }
    return _acceptSwipe(dx, _releaseVelocity, next, _dragMotion?.lastSign);
  }

  /// 3D 使用累计位移与快扫方向，其余模式保留既有松手规则。
  bool _acceptSwipe(
    double dx,
    double releaseVelocity,
    bool direction,
    double? lastSign,
  ) {
    if (mode.is3d) {
      return _acceptCurlSwipe(dx, releaseVelocity, direction);
    }
    final sign = (direction != rtl) ? -1 : 1;
    final p = (dx * sign / size.width).clamp(0, 1);
    final velocity = releaseVelocity * sign / size.width;
    if (mode != PageTurnMode.simulationBessel) {
      return velocity > -0.8 && (velocity >= 0.8 || p >= 0.35);
    }
    if (velocity <= -_reverseVelocity) return false;
    if (velocity >= _directionVelocity) return true;
    if (lastSign != null && lastSign * sign < 0) return false;
    return p >= _distanceGuard;
  }

  bool _acceptCurlSwipe(double dx, double velocity, bool direction) {
    final sign = direction != rtl ? -1 : 1;
    // 多看快扫阈值为 20 dp/s，普通松手位移严格超过 10 dp。
    if (velocity.abs() >= 20) return velocity * sign > 0;
    return dx * sign > 10;
  }

  /// 松手方向阈值，按页宽/秒计；大于该值即视为朝翻页方向轻扫。
  static const double _directionVelocity = 0.05;

  /// 反向阈值，略大于 0，滤掉指针抖动。
  static const double _reverseVelocity = 0.05;

  /// 无速度时仍需拖过的最小页宽比例，防止轻点或抖动误翻。
  static const double _distanceGuard = 0.08;

  void _settle(bool complete) {
    _positionCatchUp.stop();
    _stopLifting();
    _complete = complete;
    _startProgress = progress;
    if (mode == PageTurnMode.none) {
      _finish();
      return;
    }
    phase = PageTurnPhase.settling;
    final pointBased = mode == PageTurnMode.simulationBessel || mode.is3d;
    if (pointBased) _preparePointEnd();
    _settling.duration = mode.is3d
        ? _curlDuration(_startPoint!, _endPoint!, lifting: false)
        : _dragSettlingDuration();
    unawaited(_runSettling(++_token));
  }

  Duration _dragSettlingDuration() {
    final bessel = mode == PageTurnMode.simulationBessel;
    final pixels = bessel
        ? (_endPoint!.dx - _startPoint!.dx).abs()
        : ((_complete ? 1 : 0) - _startProgress).abs() * size.width;
    final remaining = (pixels / (size.width * (bessel ? 2 : 1))).clamp(
      0.0,
      1.0,
    );
    final continuation = mode == PageTurnMode.continuation;
    final maximum =
        (continuation
                ? continuationPageTurnDuration
                : pageTurnAnimationDuration)
            .inMilliseconds;
    var milliseconds = continuation
        ? maximum * remaining
        : 120 + (maximum - 120) * remaining;
    final sign = (next != rtl ? -1 : 1) * (_complete ? 1 : -1);
    final velocity = _releaseVelocity * sign;
    if (velocity > 0) {
      milliseconds = math.min(milliseconds, pixels * 1000 / velocity);
    }
    final duration = Duration(
      milliseconds: milliseconds.round().clamp(120, maximum),
    );
    // 快甩从松手速度接续并减速到零；静止松手与点击沿用既有缓出曲线。
    final slope = pixels > 0
        ? (velocity * duration.inMicroseconds / 1000000 / pixels).clamp(
            0.0,
            3.0,
          )
        : 0.0;
    // 接续的各行自身已经缓入缓出，整体时钟保持线性，松手不会重播逐行入场。
    _settlingCurve = continuation
        ? Curves.linear
        : velocity > 0
        ? Cubic(1 / 3, slope / 3, 2 / 3, 1)
        : Curves.easeOutCubic;
    return duration;
  }

  void _preparePointEnd() {
    _startPoint = point;
    if (mode.is3d) {
      _endPoint = _complete ? ui.Offset(-grab!.dx, grab!.dy) : grab;
      return;
    }
    final y = horizontal
        ? point!.dy
        : top
        ? 0.1
        : size.height - 0.1;
    final x = _complete ? -size.width : size.width - 0.1;
    _endPoint = ui.Offset(x, y);
  }

  Duration _curlDuration(
    ui.Offset from,
    ui.Offset to, {
    required bool lifting,
  }) {
    final milliseconds = (300 * (from.dx - to.dx).abs() / size.height).round();
    return Duration(
      milliseconds: lifting
          ? milliseconds.clamp(0, 100)
          : milliseconds < 150
          ? 150
          : milliseconds,
    );
  }

  Future<void> _runSettling(int token) async {
    try {
      final animation = mode.is3d
          ? _startCurlAnimation()
          : _settling.forward(from: 0);
      await animation.orCancel;
      if (_valid(token)) _finish();
    } on TickerCanceled {
      // 取消、重排或退出后旧收尾不能提交。
    }
  }

  TickerFuture _startCurlAnimation() {
    // forward 的归零通知会先于 ticker 启动，延后通知才能同步取消。
    _starting3dAnimation = true;
    final animation = _settling.forward(from: 0);
    _starting3dAnimation = false;
    _animateCurlFrame();
    return animation;
  }

  void _animateFrame() {
    if (_starting3dAnimation) return;
    if (mode.is3d) {
      _animateCurlFrame();
      return;
    }
    final bessel = mode == PageTurnMode.simulationBessel;
    final t = _settlingCurve.transform(_settling.value);
    progress = _startProgress + ((_complete ? 1 : 0) - _startProgress) * t;
    if (bessel) point = ui.Offset.lerp(_startPoint, _endPoint, t);
    notifyListeners();
  }

  void _animateCurlFrame() {
    final value = _settling.value;
    final t = value * value * (3 - 2 * value);
    point = ui.Offset.lerp(_startPoint, _endPoint, t);
    if (value == 1) {
      _settling.stop(canceled: false);
      if (_lifting) {
        _finishLifting();
      }
    }
    progress = _curlProgress();
    notifyListeners();
  }

  void _finishLifting() {
    _lifting = false;
    if (_released) return;
    final target = _curlPointer();
    final limit =
        size.width *
        _catchUpFrameLimit.inMicroseconds /
        _catchUpTravel.inMicroseconds;
    if ((target - point!).distance <= limit) {
      point = target;
    } else {
      // 起卷期间积累的大幅移动继续逐帧追赶，不能在动画末帧重设触点。
      _startPositionCatchUp();
    }
  }

  void _finish() {
    final prepared = turn;
    final queued = List<bool>.of(_queued);
    _queued.clear();
    _committing = true;
    if (_complete && prepared != null) session.commitPageTurn(prepared);
    _committing = false;
    // 正常收尾只释放当前翻页，保留已开始但尚未松手的下一次滑动。
    _resetTurn();
    if (queued.isNotEmpty && !_disposed) {
      _queued.addAll(queued.skip(1));
      scheduleMicrotask(() {
        if (!_disposed) request(queued.first);
      });
    } else {
      _resumePendingDrag();
    }
  }

  void _resumePendingDrag() {
    final pending = _pendingDrag;
    _pendingDrag = null;
    if (pending == null || pending.generation != session.generation) return;
    _down = pending.down;
    _latest = pending.latest;
    _dragMotion = pending.motion;
    _dragging = true;
    final initialSign = pending.motion.initialSign;
    if (initialSign != null) {
      unawaited(_prepare((initialSign < 0) != rtl, dragging: true));
    }
  }

  void _sessionChanged() {
    if (_committing || !active) return;
    final prepared = turn;
    if (session.loading ||
        _generation != session.generation ||
        !identical(_origin, session.page) ||
        (prepared != null &&
            (prepared.generation != session.generation ||
                !identical(prepared.origin, session.page)))) {
      cancel();
    }
  }

  /// 指针取消、版面失效和外部跳转均保留已提交位置。
  void cancel() {
    _queued.clear();
    _pendingDrag = null;
    _pointerDown = null;
    _resetTurn();
  }

  void _resetTurn() {
    _token++;
    _dragAtBookEnd = false;
    _tapRelease?.cancel();
    _tapRelease = null;
    _lifting = false;
    _lastCurlGeometry = null;
    _settling.stop(canceled: true);
    _targetFade.stop(canceled: true);
    _positionCatchUp.stop();
    phase = PageTurnPhase.idle;
    originImage = targetImage = null;
    final prepared = turn;
    if (prepared != null) session.releasePageTurn(prepared);
    turn = null;
    _generation = null;
    _origin = null;
    point = null;
    progress = 0;
    _resetPointer();
    if (!_disposed) notifyListeners();
  }

  void _resetPointer() {
    _down = _latest = null;
    grab = null;
    _dragMotion = null;
    _released = _dragging = false;
    _rejected3dDrag = false;
    _releaseVelocity = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    session.removeListener(_sessionChanged);
    _settling.dispose();
    _targetFade.dispose();
    _positionCatchUp.dispose();
    super.dispose();
  }
}

class _PendingDrag {
  _PendingDrag(this.down, this.latest, this.generation)
    : motion = (_DragMotion(down.dx)..update(latest.dx));

  final ui.Offset down;
  ui.Offset latest;
  final int generation;
  final _DragMotion motion;
}

class _DragMotion {
  _DragMotion(this.down) : _anchor = down;

  final double down;
  double _anchor;
  double? initialSign, lastSign;
  double initialDelta = 0;

  void update(double x) {
    if (initialSign == null && (x - down).abs() > 1) {
      initialDelta = x - down;
      initialSign = initialDelta.sign;
    }
    // 从最近极值累计反向位移，过滤一像素内的抖动，同时保留慢拖方向。
    final delta = x - _anchor;
    if (lastSign == null) {
      if (delta.abs() <= 1) return;
      lastSign = delta.sign;
      _anchor = x;
    } else if (delta * lastSign! > 0) {
      _anchor = x;
    } else if (delta.abs() > 1) {
      lastSign = delta.sign;
      _anchor = x;
    }
  }
}
