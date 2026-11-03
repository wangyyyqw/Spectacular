import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
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
    _dragTicker = vsync.createTicker(_smoothDrag);
    session.addListener(_sessionChanged);
  }

  final ReaderSession session;
  final Future<ui.Image?> Function(PageContent page) acquireImage;
  late final AnimationController _settling;
  late final Ticker _dragTicker;
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
  ui.Offset? _down, _latest, _smoothTarget, _lastProcessed;
  DateTime? _downTime;
  Duration? _lastTick;
  bool _released = false, _complete = true, _dragging = false;
  bool _disposed = false, _committing = false;
  bool? _queued;
  int _token = 0;
  double _startProgress = 0;
  ui.Offset? _startPoint, _endPoint;
  double _releaseVelocity = 0;

  bool get active => phase != PageTurnPhase.idle;

  /// 原始按下位置只记录，不抢占长按、链接或选区手势。
  void pointerDown(ui.Offset position) {
    if (active) return;
    _down = position;
    _downTime = DateTime.now();
  }

  /// 点击、键盘等离散输入最多保留一个后续意图。
  void request(bool next) {
    if (active) {
      _queued = next;
      return;
    }
    _down = ui.Offset(rtl ? 0 : size.width, size.height / 2);
    _downTime = DateTime.now();
    _latest = _down;
    unawaited(_prepare(next, dragging: false));
  }

  void beginDrag(DragStartDetails details) {
    if (active) return;
    _down ??= details.localPosition;
    _downTime ??= DateTime.now();
    _latest = details.localPosition;
    _dragging = true;
  }

  void updateDrag(DragUpdateDetails details) {
    if (!_dragging || phase == PageTurnPhase.settling) return;
    _latest = details.localPosition;
    final dx = _latest!.dx - _down!.dx;
    if (!active && dx.abs() > 1) {
      unawaited(_prepare((dx < 0) != rtl, dragging: true));
    }
    if (phase == PageTurnPhase.dragging) _updateDragFrame();
  }

  void endDrag(DragEndDetails details) {
    if (!_dragging) return;
    _released = true;
    _dragging = false;
    _releaseVelocity = details.primaryVelocity ?? 0;
    _dragTicker.stop();
    if (phase == PageTurnPhase.dragging) _settle(_shouldComplete());
    if (!active) _resetPointer();
  }

  Future<void> _prepare(bool direction, {required bool dragging}) async {
    if (size.isEmpty || _disposed) return;
    final token = ++_token;
    next = direction;
    phase = PageTurnPhase.preparing;
    _released = !dragging;
    progress = 0;
    try {
      final prepared = await session.preparePageTurn(next);
      if (!_valid(token)) return;
      if (prepared == null) {
        cancel();
        return;
      }
      turn = prepared;
      if (mode != PageTurnMode.none) {
        originImage = await acquireImage(prepared.origin);
        if (!_valid(token)) return;
        targetImage = await acquireImage(prepared.target.content);
        if (!_valid(token)) return;
      }
      _initializePoint();
      phase = PageTurnPhase.dragging;
      if (_released) {
        if (dragging && mode == PageTurnMode.simulationBessel) {
          // 准备图片期间手指可能已经松开，此时 _lastProcessed 仍是初始化
          // 后的页缘点。按松手前最后位置重新判定，避免已滑过阈值却回弹。
          _lastProcessed = _processedPoint(_canonical(_latest!));
        }
        _settle(dragging ? _shouldComplete() : true);
      } else {
        _updateDragFrame();
      }
    } catch (_) {
      if (_valid(token)) cancel();
    }
  }

  bool _valid(int token) => !_disposed && token == _token;

  ui.Offset _canonical(ui.Offset position) =>
      ui.Offset(rtl ? size.width - position.dx : position.dx, position.dy);

  void _initializePoint() {
    final down = _canonical(_down!);
    top = next && down.dx >= size.width / 2 && down.dy < size.height / 3;
    horizontal =
        !next ||
        down.dx < size.width / 2 ||
        (down.dy >= size.height / 3 && down.dy <= size.height * 2 / 3);
    point = ui.Offset(
      next ? size.width : 0,
      top ? 1 : (horizontal ? down.dy : size.height - 1),
    );
    _lastProcessed = point;
  }

  void _updateDragFrame() {
    if (mode == PageTurnMode.simulationBessel) {
      final latest = _canonical(_latest!);
      _smoothTarget = ui.Offset(
        latest.dx.clamp(next ? -size.width : 0, size.width),
        horizontal ? point!.dy : latest.dy.clamp(0.1, size.height - 0.1),
      );
      if (!_dragTicker.isActive) {
        _lastTick = null;
        _dragTicker.start();
      }
    } else {
      final sign = (next != rtl) ? -1 : 1;
      progress = ((_latest!.dx - _down!.dx) * sign / size.width).clamp(0, 1);
      notifyListeners();
    }
  }

  /// 按页宽限定每帧移动距离，回拖与纵向移动共用抓取点轨迹。
  void _smoothDrag(Duration elapsed) {
    final oldTick = _lastTick;
    _lastTick = elapsed;
    final dt = oldTick == null
        ? 1 / 60
        : (elapsed - oldTick).inMicroseconds / 1e6;
    final target = _smoothTarget!;
    final current = point!;
    final delta = target - current;
    final distance = delta.distance;
    final step = size.width * 9 * dt.clamp(0, 0.05);
    point = distance <= step ? target : current + delta * (step / distance);
    _updateBesselProgress();
    if (point == target) _dragTicker.stop();
    notifyListeners();
  }

  void _updateBesselProgress() {
    _lastProcessed = _processedPoint(point!);
    progress =
        (next
                ? (size.width - point!.dx) / (2 * size.width)
                : point!.dx / size.width)
            .clamp(0, 1);
  }

  ui.Offset _processedPoint(ui.Offset point) {
    final input = horizontal ? ui.Offset(point.dx, size.height - 0.1) : point;
    final geometry = BesselGeometry.resolve(size, input, top: top);
    return geometry?.a ?? input;
  }

  bool _shouldComplete() {
    if (mode == PageTurnMode.simulationBessel) {
      if (DateTime.now().difference(_downTime!) <
          const Duration(milliseconds: 300)) {
        return true;
      }
      final current = _lastProcessed ?? _canonical(_latest!);
      final delta = current.dx - _canonical(_down!).dx;
      return next ? delta <= -size.width / 4 : delta >= size.width / 4;
    }
    final sign = (next != rtl) ? -1 : 1;
    final p = ((_latest!.dx - _down!.dx) * sign / size.width).clamp(0, 1);
    final velocity = _releaseVelocity * sign / size.width;
    return velocity > -0.8 && (velocity >= 0.8 || p >= 0.35);
  }

  void _settle(bool complete) {
    _dragTicker.stop();
    _complete = complete;
    _startProgress = progress;
    if (mode == PageTurnMode.none ||
        originImage == null ||
        targetImage == null) {
      _finish();
      return;
    }
    phase = PageTurnPhase.settling;
    final bessel = mode == PageTurnMode.simulationBessel;
    if (bessel) _prepareBesselEnd();
    final distance = ((complete ? 1 : 0) - progress).abs();
    _settling.duration = Duration(
      milliseconds: bessel
          ? 300
          : ((complete ? 240 : 180) * distance).round().clamp(
              60,
              complete ? 240 : 180,
            ),
    );
    unawaited(_runSettling(++_token));
  }

  void _prepareBesselEnd() {
    _startPoint = point;
    final y = top
        ? (_complete ? 0.0 : 0.1)
        : horizontal
        ? point!.dy
        : size.height - (_complete ? 0 : 0.1);
    final x = _complete
        ? (next ? -size.width : size.width)
        : next
        ? size.width - 0.1
        : -(point!.dx + size.width / 2);
    _endPoint = ui.Offset(x, !next && _complete ? point!.dy : y);
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
    final t = bessel
        ? _settling.value
        : Curves.easeOutCubic.transform(_settling.value);
    progress = _startProgress + ((_complete ? 1 : 0) - _startProgress) * t;
    if (bessel) point = ui.Offset.lerp(_startPoint, _endPoint, t);
    notifyListeners();
  }

  void _finish() {
    final prepared = turn;
    final queued = _queued;
    _queued = null;
    _committing = true;
    if (_complete && prepared != null) session.commitPageTurn(prepared);
    _committing = false;
    cancel();
    if (queued != null && !_disposed) {
      scheduleMicrotask(() {
        if (!_disposed) request(queued);
      });
    }
  }

  void _sessionChanged() {
    if (_committing || !active) return;
    final prepared = turn;
    if (session.loading ||
        (prepared != null &&
            (prepared.generation != session.generation ||
                !identical(prepared.origin, session.page)))) {
      cancel();
    }
  }

  /// 指针取消、版面失效和外部跳转均保留已提交位置。
  void cancel() {
    _token++;
    _settling.stop(canceled: true);
    _dragTicker.stop();
    phase = PageTurnPhase.idle;
    originImage = targetImage = null;
    turn = null;
    point = null;
    progress = 0;
    _queued = null;
    _resetPointer();
    if (!_disposed) notifyListeners();
  }

  void _resetPointer() {
    _down = _latest = _smoothTarget = _lastProcessed = null;
    _downTime = null;
    _lastTick = null;
    _released = _dragging = false;
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    session.removeListener(_sessionChanged);
    _settling.dispose();
    _dragTicker.dispose();
    super.dispose();
  }
}
