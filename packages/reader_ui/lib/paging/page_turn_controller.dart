import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:reader_core/layout/paginator.dart';

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
  }) {
    _settling = AnimationController(vsync: vsync)..addListener(_animateFrame);
    _catchUp = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 100),
    )..addListener(_catchUpFrame);
    session.addListener(_sessionChanged);
  }

  final ReaderSession session;
  final Future<ui.Image?> Function(PageContent page) acquireImage;
  late final AnimationController _settling;
  late final AnimationController _catchUp;
  bool _preparationVisible = false;
  double _catchUpProgress = 0;
  ui.Offset? _catchUpPoint;

  /// 冷目标露底渐入；3D 保持原有绘制行为。
  double get targetOpacity => mode == PageTurnMode.simulation3d
      ? 1
      : (_catchUp.isAnimating ? _catchUp.value : 1);
  PageTurnPhase phase = PageTurnPhase.idle;
  PageTurnMode mode = PageTurnMode.cover;
  ui.Size size = ui.Size.zero;
  bool rtl = false;
  bool next = true;
  bool top = false;
  bool horizontal = true;
  double progress = 0;
  ui.Offset? point;

  /// 3D 仿真被按住的页角，规范坐标；轻点翻页时取页角或侧边。
  ui.Offset? grab;

  /// 3D 仿真收尾时整页滑出画面的水平位移。
  double slide = 0;
  ui.Image? originImage, targetImage;
  PreparedPageTurn? turn;
  ui.Offset? _down, _latest;
  ui.Offset? _pointerDown;
  _PendingDrag? _pendingDrag;
  _DragMotion? _dragMotion;
  bool _released = false, _complete = true, _dragging = false;
  bool _disposed = false, _committing = false;
  final List<bool> _queued = <bool>[];
  int _token = 0;
  double _startProgress = 0;
  ui.Offset? _startPoint, _endPoint;
  double _releaseVelocity = 0;
  int? _generation;
  PageContent? _origin;

  bool get active => phase != PageTurnPhase.idle;

  /// 活动纸的物理起卷侧；前后翻页的轴互为镜像。
  bool get fromRight => next != rtl;

  /// 3D 仿真的折角几何：折痕是抓取页角与当前触点的中垂线。
  Curl3dGeometry? get curl3dGeometry {
    final anchor = grab;
    final current = point;
    if (anchor == null || current == null) return null;
    return Curl3dGeometry(
      size: size,
      grab: anchor,
      touch: current,
      slide: ui.Offset(slide, 0),
    );
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
    _pointerDown = position;
  }

  /// 点击、键盘等离散输入按先后顺序排队，动画结束后逐页执行。
  void request(bool next) {
    if (active) {
      _queued.add(next);
      return;
    }
    _down = ui.Offset(next != rtl ? size.width : 0, size.height / 2);
    _latest = _down;
    unawaited(_prepare(next, dragging: false));
  }

  void beginDrag(DragStartDetails details) {
    final down = _pointerDown ?? details.localPosition;
    _pointerDown = null;
    if (active) {
      // 下一次滑动单独记录，不能覆盖仍在准备或收尾的翻页触点。
      _pendingDrag = _PendingDrag(
        down,
        details.localPosition,
        session.generation,
      );
      return;
    }
    _down = down;
    _latest = details.localPosition;
    _dragMotion = _DragMotion(down.dx)..update(details.localPosition.dx);
    _dragging = true;
  }

  void updateDrag(DragUpdateDetails details) {
    final pending = _pendingDrag;
    if (pending != null) {
      pending.latest = details.localPosition;
      pending.motion.update(details.localPosition.dx);
      return;
    }
    if (!_dragging || phase == PageTurnPhase.settling) return;
    _latest = details.localPosition;
    final motion = _dragMotion!..update(_latest!.dx);
    final initialSign = motion.initialSign;
    if (!active && initialSign != null) {
      unawaited(_prepare((initialSign < 0) != rtl, dragging: true));
    }
    if (phase == PageTurnPhase.dragging ||
        (phase == PageTurnPhase.preparing && originImage != null)) {
      _updateDragFrame();
    }
  }

  void endDrag(DragEndDetails details) {
    final pending = _pendingDrag;
    if (pending != null) {
      _pendingDrag = null;
      final dx = pending.latest.dx - pending.down.dx;
      final initialSign = pending.motion.initialSign;
      if (initialSign == null) return;
      final direction = (initialSign < 0) != rtl;
      if (pending.generation == session.generation &&
          _acceptSwipe(
            dx,
            details.primaryVelocity ?? 0,
            direction,
            pending.motion.lastSign,
          )) {
        request(direction);
      }
      return;
    }
    if (!_dragging) return;
    _released = true;
    _dragging = false;
    _releaseVelocity = details.primaryVelocity ?? 0;
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

  /// 仅取消真实拖动；轻点也会触发拖动手势取消，不能影响点击翻页队列。
  void cancelDrag() {
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
    final token = ++_token;
    next = direction;
    _generation = session.generation;
    _origin = session.page;
    phase = PageTurnPhase.preparing;
    _released = !dragging;
    progress = 0;
    slide = 0;
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
    try {
      if (!await _prepareOrigin(token, dragging)) return;
      final prepared = await session.preparePageTurn(next);
      if (!_valid(token)) return;
      if (prepared == null) {
        cancel();
        return;
      }
      turn = prepared;
      if (mode != PageTurnMode.none) {
        final target = await acquireImage(prepared.target.content);
        if (!_valid(token)) return;
        if (target == null) return cancel();
        targetImage = target;
      }
      phase = PageTurnPhase.dragging;
      // 已松手时从等待期间实际显示的位置接续，不能跳到过期触点再收尾。
      if (_preparationVisible &&
          mode != PageTurnMode.simulation3d &&
          mode != PageTurnMode.none) {
        _startCatchUp();
      } else if (dragging && !_released) {
        _updateDragFrame();
      }
      notifyListeners();
      if (_released) {
        _settle(dragging ? _shouldComplete() : true);
      }
    } catch (_) {
      if (_valid(token)) cancel();
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
    if (dragging) _updateDragFrame();
    return true;
  }

  bool _valid(int token) => !_disposed && token == _token;

  ui.Offset _canonical(ui.Offset position) => ui.Offset(
    fromRight ? position.dx : size.width - position.dx,
    position.dy,
  );

  void _initializePoint() {
    final down = _canonical(_down!);
    top = down.dy < size.height / 2;
    // 起手所在的中心二十分之一从侧边卷起；手势内固定类型，跨区不跳变。
    horizontal = (down.dy - size.height / 2).abs() <= size.height / 40;
    final edge = ui.Offset(size.width, down.dy.clamp(0.1, size.height - 0.1));
    grab = horizontal ? edge : ui.Offset(size.width, top ? 0.0 : size.height);
    // 3D 从页角起卷，抓取点与触点重合时折角为零；其余模式从侧边起手。
    point = mode == PageTurnMode.simulation3d ? grab : edge;
  }

  void _updateDragFrame() {
    if (_catchUp.isAnimating) {
      _catchUpFrame();
      return;
    }
    _resolveDragFrame();
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

  void _resolveDragFrame() {
    if (mode == PageTurnMode.simulationBessel) {
      final latest = _canonical(_latest!);
      point = ui.Offset(
        latest.dx.clamp(-size.width, size.width),
        latest.dy.clamp(0.1, size.height - 0.1),
      );
      progress = ((size.width - point!.dx) / (2 * size.width)).clamp(0, 1);
    } else if (mode == PageTurnMode.simulation3d) {
      // 页角随手指平移，折痕始终是页角与触点的中垂线。
      final delta = _canonical(_latest!) - _canonical(_down!);
      final anchor = grab;
      point = anchor == null
          ? null
          : ui.Offset(
              (anchor.dx + delta.dx).clamp(-size.width, size.width),
              (anchor.dy + delta.dy).clamp(0.0, size.height),
            );
      final travel = point == null ? 0.0 : (point! - anchor!).distance;
      progress = (travel / (size.width * 0.9)).clamp(0.0, 0.999);
    } else {
      final sign = (next != rtl) ? -1 : 1;
      progress = ((_latest!.dx - _down!.dx) * sign / size.width).clamp(0, 1);
    }
    // 冷目标未就绪时只轻抬原页，保留可见反馈和后续完整的翻页行程。
    if (phase == PageTurnPhase.preparing && progress > 0.08) {
      progress = 0.08;
      if (mode == PageTurnMode.simulationBessel) {
        point = ui.Offset(size.width * 0.84, point!.dy);
      }
    }
  }

  void _startCatchUp() {
    _catchUpProgress = progress;
    _catchUpPoint = point;
    _catchUp.forward(from: 0);
  }

  void _catchUpFrame() {
    if (phase == PageTurnPhase.dragging && !_released) {
      _resolveDragFrame();
      final t = Curves.easeOutCubic.transform(_catchUp.value);
      progress = _catchUpProgress + (progress - _catchUpProgress) * t;
      if (mode == PageTurnMode.simulationBessel) {
        point = ui.Offset.lerp(_catchUpPoint, point, t);
      }
    }
    if (!_disposed) notifyListeners();
  }

  bool _shouldComplete() => _acceptSwipe(
    _latest!.dx - _down!.dx,
    _releaseVelocity,
    next,
    _dragMotion?.lastSign,
  );

  /// 仿真翻页以松手方向为主；低速时使用有效末段方向，避免慢回拖误提交。
  bool _acceptSwipe(
    double dx,
    double releaseVelocity,
    bool direction,
    double? lastSign,
  ) {
    final sign = (direction != rtl) ? -1 : 1;
    final p = (dx * sign / size.width).clamp(0, 1);
    final velocity = releaseVelocity * sign / size.width;
    if (mode != PageTurnMode.simulationBessel &&
        mode != PageTurnMode.simulation3d) {
      return velocity > -0.8 && (velocity >= 0.8 || p >= 0.35);
    }
    if (velocity <= -_reverseVelocity) return false;
    if (velocity >= _directionVelocity) return true;
    if (lastSign != null && lastSign * sign < 0) return false;
    return p >= _distanceGuard;
  }

  /// 松手方向阈值，按页宽/秒计；大于该值即视为朝翻页方向轻扫。
  static const double _directionVelocity = 0.05;

  /// 反向阈值，略大于 0，滤掉指针抖动。
  static const double _reverseVelocity = 0.05;

  /// 无速度时仍需拖过的最小页宽比例，防止轻点或抖动误翻。
  static const double _distanceGuard = 0.08;

  void _settle(bool complete) {
    _complete = complete;
    _startProgress = progress;
    if (mode == PageTurnMode.none) {
      _finish();
      return;
    }
    phase = PageTurnPhase.settling;
    final pointBased =
        mode == PageTurnMode.simulationBessel ||
        mode == PageTurnMode.simulation3d;
    if (pointBased) _preparePointEnd();
    _settling.duration = pageTurnAnimationDuration;
    unawaited(_runSettling(++_token));
  }

  void _preparePointEnd() {
    _startPoint = point;
    if (mode == PageTurnMode.simulation3d) {
      // 完成时折角继续展开并整页滑出；取消时退回抓取页角。
      _endPoint = _complete
          ? ui.Offset(-size.width * 0.6, point?.dy ?? size.height / 2)
          : grab;
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

  Future<void> _runSettling(int token) async {
    try {
      await _settling.forward(from: 0).orCancel;
      if (_valid(token)) _finish();
    } on TickerCanceled {
      // 取消、重排或退出后旧收尾不能提交。
    }
  }

  void _animateFrame() {
    final bessel = mode == PageTurnMode.simulationBessel;
    final curl3d = mode == PageTurnMode.simulation3d;
    final t = Curves.easeOutCubic.transform(_settling.value);
    progress = _startProgress + ((_complete ? 1 : 0) - _startProgress) * t;
    if (bessel || curl3d) point = ui.Offset.lerp(_startPoint, _endPoint, t);
    if (curl3d) slide = _complete ? -size.width * t : 0;
    notifyListeners();
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
    _settling.stop(canceled: true);
    _catchUp.stop(canceled: true);
    phase = PageTurnPhase.idle;
    originImage = targetImage = null;
    turn = null;
    _generation = null;
    _origin = null;
    point = null;
    progress = 0;
    slide = 0;
    _resetPointer();
    if (!_disposed) notifyListeners();
  }

  void _resetPointer() {
    _down = _latest = null;
    grab = null;
    _dragMotion = null;
    _released = _dragging = false;
    _releaseVelocity = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    session.removeListener(_sessionChanged);
    _settling.dispose();
    _catchUp.dispose();
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

  void update(double x) {
    if (initialSign == null && (x - down).abs() > 1) {
      initialSign = (x - down).sign;
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
