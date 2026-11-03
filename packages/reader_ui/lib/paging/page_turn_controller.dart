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
  bool _released = false, _complete = true, _dragging = false;
  bool _disposed = false, _committing = false;
  bool? _queued;
  int _token = 0;
  double _startProgress = 0;
  ui.Offset? _startPoint, _endPoint;
  double _releaseVelocity = 0;

  bool get active => phase != PageTurnPhase.idle;

  /// 当前抓取点对应的卷曲几何；直接跟手，不再压到页缘。
  BesselGeometry? get besselGeometry {
    final current = point;
    return current == null
        ? null
        : BesselGeometry.resolve(
            size,
            next ? current : ui.Offset(size.width - current.dx, current.dy),
            top: top,
            horizontal: horizontal,
          );
  }

  /// 原始按下位置只记录，不抢占长按、链接或选区手势。
  void pointerDown(ui.Offset position) {
    if (active) return;
    _down = position;
  }

  /// 点击、键盘等离散输入最多保留一个后续意图。
  void request(bool next) {
    if (active) {
      _queued = next;
      return;
    }
    _down = ui.Offset(next != rtl ? size.width : 0, size.height / 2);
    _latest = _down;
    unawaited(_prepare(next, dragging: false));
  }

  void beginDrag(DragStartDetails details) {
    if (active) return;
    _down ??= details.localPosition;
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
      if (dragging) _updateDragFrame();
      if (_released) {
        _settle(dragging ? _shouldComplete() : true);
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
    top = down.dy < size.height / 2;
    // 起手所在的中心五分之一从侧边卷起；手势内固定类型，跨区不跳变。
    horizontal = (down.dy - size.height / 2).abs() <= size.height / 10;
    point = ui.Offset(
      next ? size.width : 0,
      down.dy.clamp(0.1, size.height - 0.1),
    );
  }

  void _updateDragFrame() {
    if (mode == PageTurnMode.simulationBessel) {
      final latest = _canonical(_latest!);
      point = ui.Offset(
        latest.dx.clamp(
          next ? -size.width : 0,
          next ? size.width : size.width * 2,
        ),
        latest.dy.clamp(0.1, size.height - 0.1),
      );
      progress =
          ((next ? size.width - point!.dx : point!.dx) / (2 * size.width))
              .clamp(0, 1);
    } else {
      final sign = (next != rtl) ? -1 : 1;
      progress = ((_latest!.dx - _down!.dx) * sign / size.width).clamp(0, 1);
    }
    notifyListeners();
  }

  bool _shouldComplete() {
    final sign = (next != rtl) ? -1 : 1;
    final p = ((_latest!.dx - _down!.dx) * sign / size.width).clamp(0, 1);
    final velocity = _releaseVelocity * sign / size.width;
    final threshold = mode == PageTurnMode.simulationBessel ? 0.25 : 0.35;
    return velocity > -0.8 && (velocity >= 0.8 || p >= threshold);
  }

  void _settle(bool complete) {
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
    final y = horizontal
        ? point!.dy
        : top
        ? 0.1
        : size.height - 0.1;
    final x = _complete
        ? (next ? -size.width : size.width * 2)
        : (next ? size.width - 0.1 : 0.1);
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
