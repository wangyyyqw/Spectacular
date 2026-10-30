import 'package:flutter/material.dart';

import 'tap_zones.dart';

/// 识别出的基础手势。
enum ReaderGesture {
  tapLeft,
  tapCenter,
  tapRight,
  swipeLeft,
  swipeRight,
  swipeUp,
  swipeDown,
  none,
}

/// 翻页意图。
enum PageTurnIntent { previous, next, none }

/// 手势参数（技术方案 §74.7）。
class ReaderGestureConfig {
  /// 创建配置。
  const ReaderGestureConfig({
    this.edgeRatio = 0.3,
    this.clickLeftNextPage = false,
    this.verticalWriting = false,
    this.tapZones,
    this.distanceRatio = 0.3,
    this.speedThreshold = 800,
    this.dragStartTolerance = 8,
  });

  /// 左右区宽度占比。
  final double edgeRatio;

  /// 左区点击改为下一页（左利手）。
  final bool clickLeftNextPage;

  /// 竖排：左右语义反转。
  final bool verticalWriting;

  /// 九宫格配置；为空时沿用旧版三区点击设置。
  final ReaderTapZones? tapZones;

  /// 滑动翻页距离阈值（屏宽占比）。
  final double distanceRatio;

  /// 滑动翻页速度阈值（px/s）。
  final double speedThreshold;

  /// 拖动起点容差。
  final double dragStartTolerance;
}

/// 纯逻辑手势分类器，便于单测。
class ReaderGestureInterpreter {
  /// 创建分类器。
  const ReaderGestureInterpreter(this.config);

  /// 配置。
  final ReaderGestureConfig config;

  /// 点击区域分类。
  ReaderGesture tapAt(Offset position, {required double width}) {
    if (width <= 0) {
      return ReaderGesture.none;
    }
    final ratio = position.dx / width;
    if (ratio < config.edgeRatio) {
      return ReaderGesture.tapLeft;
    }
    if (ratio < 1 - config.edgeRatio) {
      return ReaderGesture.tapCenter;
    }
    return ReaderGesture.tapRight;
  }

  /// 点击所在九宫格。
  ReaderTapZone tapZoneAt(Offset position, {required Size size}) {
    if (size.width <= 0 || size.height <= 0) {
      return ReaderTapZone.center;
    }
    final column = (position.dx / size.width * 3).floor().clamp(0, 2);
    final row = (position.dy / size.height * 3).floor().clamp(0, 2);
    return ReaderTapZone.values[row * 3 + column];
  }

  /// 点击动作；未配置九宫格时把旧版三区设置转换成动作。
  ReaderTapAction tapActionAt(Offset position, {required Size size}) {
    final zones = config.tapZones;
    if (zones != null) {
      return zones.actionAt(tapZoneAt(position, size: size));
    }
    return switch (tapIntent(tapAt(position, width: size.width))) {
      PageTurnIntent.previous => ReaderTapAction.previousPage,
      PageTurnIntent.next => ReaderTapAction.nextPage,
      PageTurnIntent.none => ReaderTapAction.openMenu,
    };
  }

  /// 主方向分类（不考虑阈值）。
  ReaderGesture swipeDirection(double dx, double dy) {
    if (dx == 0 && dy == 0) {
      return ReaderGesture.none;
    }
    if (dx.abs() >= dy.abs()) {
      return dx < 0 ? ReaderGesture.swipeLeft : ReaderGesture.swipeRight;
    }
    return dy < 0 ? ReaderGesture.swipeUp : ReaderGesture.swipeDown;
  }

  /// 是否达到翻页阈值（只对水平滑动生效）。
  bool shouldTurnPage({
    required double dx,
    required double dy,
    required double width,
    double velocityX = 0,
    double velocityY = 0,
  }) {
    if (dx.abs() < dy.abs()) {
      return false;
    }
    if (dx.abs() >= width * config.distanceRatio) {
      return true;
    }
    return velocityX.abs() >= config.speedThreshold;
  }

  /// 点击手势对应的翻页意图。
  PageTurnIntent tapIntent(ReaderGesture gesture) {
    final reverse = config.verticalWriting;
    switch (gesture) {
      case ReaderGesture.tapLeft:
        final next = config.clickLeftNextPage != reverse;
        return next ? PageTurnIntent.next : PageTurnIntent.previous;
      case ReaderGesture.tapRight:
        final next = config.clickLeftNextPage == reverse;
        return next ? PageTurnIntent.next : PageTurnIntent.previous;
      default:
        return PageTurnIntent.none;
    }
  }

  /// 滑动手势对应的翻页意图；竖排反向。
  PageTurnIntent swipeIntent(ReaderGesture gesture) {
    switch (gesture) {
      case ReaderGesture.swipeLeft:
        return config.verticalWriting
            ? PageTurnIntent.previous
            : PageTurnIntent.next;
      case ReaderGesture.swipeRight:
        return config.verticalWriting
            ? PageTurnIntent.next
            : PageTurnIntent.previous;
      default:
        return PageTurnIntent.none;
    }
  }
}

/// 基础阅读视图：左右区域点击与水平滑动翻页。
class ReaderView extends StatefulWidget {
  /// 创建阅读视图。
  const ReaderView({
    super.key,
    this.child,
    this.onPrevious,
    this.onNext,
    this.onToggleToolbar,
    this.onLongPressAt,
    this.onDoubleTapAt,
    this.onTripleTapAt,
    this.onGesture,
    this.pageIndex,
    this.pageCount,
    this.config = const ReaderGestureConfig(),
  });

  /// 阅读内容。
  final Widget? child;

  /// 上一页回调。
  final VoidCallback? onPrevious;

  /// 下一页回调。
  final VoidCallback? onNext;

  /// 中间区域点击：工具栏。
  final VoidCallback? onToggleToolbar;

  /// 长按位置（相对阅读视图左上角，P4-14 命中测试用）。
  final ValueChanged<Offset>? onLongPressAt;

  /// 双击位置（P4-16 选词）；为 null 时不启用双击识别（单击不延迟）。
  final ValueChanged<Offset>? onDoubleTapAt;

  /// 三击位置（P4-16 选句）。
  final ValueChanged<Offset>? onTripleTapAt;

  /// 手势观测回调（测试/埋点）。
  final ValueChanged<ReaderGesture>? onGesture;

  /// 当前页序号；提供 pageCount 时用于边界钳制。
  final int? pageIndex;

  /// 总页数。
  final int? pageCount;

  /// 手势参数。
  final ReaderGestureConfig config;

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  ReaderGestureInterpreter get _interpreter =>
      ReaderGestureInterpreter(widget.config);
  double _dragDx = 0;
  double _dragDy = 0;
  Offset? _lastTapPosition;
  DateTime? _doubleTapTime;

  bool get _atFirst => widget.pageIndex != null && widget.pageIndex! <= 0;

  bool get _atLast =>
      widget.pageIndex != null &&
      widget.pageCount != null &&
      widget.pageIndex! >= widget.pageCount! - 1;

  void _notify(ReaderGesture gesture) {
    if (gesture != ReaderGesture.none) {
      widget.onGesture?.call(gesture);
    }
  }

  void _turn(PageTurnIntent intent) {
    if (intent == PageTurnIntent.next) {
      if (_atLast) {
        return;
      }
      widget.onNext?.call();
    } else if (intent == PageTurnIntent.previous) {
      if (_atFirst) {
        return;
      }
      widget.onPrevious?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            _lastTapPosition = details.localPosition;
          },
          onDoubleTap: widget.onDoubleTapAt == null
              ? null
              : () {
                  _doubleTapTime = DateTime.now();
                  final position = _lastTapPosition;
                  if (position != null) {
                    widget.onDoubleTapAt!(position);
                  }
                },
          onTapUp: (details) {
            // 三击：双击后 350ms 内再落一次 → 选句（P4-16，§63.2）。
            final doubleTap = _doubleTapTime;
            if (widget.onTripleTapAt != null &&
                doubleTap != null &&
                DateTime.now().difference(doubleTap) <
                    const Duration(milliseconds: 350)) {
              _doubleTapTime = null;
              widget.onTripleTapAt!(details.localPosition);
              return;
            }
            final gesture = _interpreter.tapAt(
              details.localPosition,
              width: width,
            );
            _notify(gesture);
            final action = _interpreter.tapActionAt(
              details.localPosition,
              size: Size(width, height),
            );
            switch (action) {
              case ReaderTapAction.previousPage:
                _turn(PageTurnIntent.previous);
              case ReaderTapAction.nextPage:
                _turn(PageTurnIntent.next);
              case ReaderTapAction.openMenu:
              widget.onToggleToolbar?.call();
              case ReaderTapAction.none:
                break;
            }
          },
          onLongPressStart: (details) {
            widget.onLongPressAt?.call(details.localPosition);
          },
          onHorizontalDragStart: (_) {
            _dragDx = 0;
            _dragDy = 0;
          },
          onHorizontalDragUpdate: (details) {
            _dragDx += details.delta.dx;
            _dragDy += details.delta.dy;
          },
          onHorizontalDragEnd: (details) {
            final gesture = _interpreter.swipeDirection(_dragDx, _dragDy);
            _notify(gesture);
            if (_interpreter.shouldTurnPage(
              dx: _dragDx,
              dy: _dragDy,
              width: width,
              velocityX: details.primaryVelocity ?? 0,
            )) {
              _turn(_interpreter.swipeIntent(gesture));
            }
          },
          onVerticalDragEnd: (details) {
            final gesture = _interpreter.swipeDirection(
              0,
              details.primaryVelocity ?? 0,
            );
            _notify(gesture);
          },
          child: widget.child ?? const SizedBox.expand(),
        );
      },
    );
  }
}
