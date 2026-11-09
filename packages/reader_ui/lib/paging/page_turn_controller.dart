import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:reader_core/layout/paginator.dart';

import '../reader_session.dart';
import 'bessel_geometry.dart';
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
    session.addListener(_sessionChanged);
  }

  final ReaderSession session;
  final Future<ui.Image?> Function(PageContent page) acquireImage;
  late final AnimationController _settling;
  PageTurnPhase phase = PageTurnPhase.idle;
  PageTurnMode mode = PageTurnMode.cover;
  ui.Size size = ui.Size.zero;
  bool rtl = false;
  bool next = true;
  bool top = false;
  bool horizontal = true;
  double progress = 0;
  ui.Offset? point;
  ui.Image? originImage, targetImage;
  PreparedPageTurn? turn;
  ui.Offset? _down, _latest;
  ui.Offset? _pointerDown;
  _PendingDrag? _pendingDrag;
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
    _dragging = true;
  }

  void updateDrag(DragUpdateDetails details) {
    final pending = _pendingDrag;
    if (pending != null) {
      pending.latest = details.localPosition;
      return;
    }
    if (!_dragging || phase == PageTurnPhase.settling) return;
    _latest = details.localPosition;
    final dx = _latest!.dx - _down!.dx;
    if (!active && dx.abs() > 1) {
      unawaited(_prepare((dx < 0) != rtl, dragging: true));
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
      final direction = (dx < 0) != rtl;
      if (pending.generation == session.generation &&
          _acceptSwipe(dx, details.primaryVelocity ?? 0, direction)) {
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
      if (dragging && !_released) _updateDragFrame();
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
    point = ui.Offset(size.width, down.dy.clamp(0.1, size.height - 0.1));
  }

  void _updateDragFrame() {
    if (mode == PageTurnMode.simulationBessel) {
      final latest = _canonical(_latest!);
      point = ui.Offset(
        latest.dx.clamp(-size.width, size.width),
        latest.dy.clamp(0.1, size.height - 0.1),
      );
      progress = ((size.width - point!.dx) / (2 * size.width)).clamp(0, 1);
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
    notifyListeners();
  }

  bool _shouldComplete() =>
      _acceptSwipe(_latest!.dx - _down!.dx, _releaseVelocity, next);

  bool _acceptSwipe(double dx, double releaseVelocity, bool direction) {
    final sign = (direction != rtl) ? -1 : 1;
    final p = (dx * sign / size.width).clamp(0, 1);
    final velocity = releaseVelocity * sign / size.width;
    final threshold = mode == PageTurnMode.simulationBessel ? 0.25 : 0.35;
    return velocity > -0.8 && (velocity >= 0.8 || p >= threshold);
  }

  void _settle(bool complete) {
    _complete = complete;
    _startProgress = progress;
    if (mode == PageTurnMode.none) {
      _finish();
      return;
    }
    phase = PageTurnPhase.settling;
    final bessel = mode == PageTurnMode.simulationBessel;
    if (bessel) _prepareBesselEnd();
    _settling.duration = pageTurnAnimationDuration;
    unawaited(_runSettling(++_token));
  }

  void _prepareBesselEnd() {
    _startPoint = point;
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
    final t = Curves.easeOutCubic.transform(_settling.value);
    progress = _startProgress + ((_complete ? 1 : 0) - _startProgress) * t;
    if (bessel) point = ui.Offset.lerp(_startPoint, _endPoint, t);
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
    _dragging = true;
    final dx = pending.latest.dx - pending.down.dx;
    if (dx.abs() > 1) unawaited(_prepare((dx < 0) != rtl, dragging: true));
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
    phase = PageTurnPhase.idle;
    originImage = targetImage = null;
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
    _released = _dragging = false;
    _releaseVelocity = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    session.removeListener(_sessionChanged);
    _settling.dispose();
    super.dispose();
  }
}

class _PendingDrag {
  _PendingDrag(this.down, this.latest, this.generation);

  final ui.Offset down;
  ui.Offset latest;
  final int generation;
}
