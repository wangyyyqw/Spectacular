import 'package:flutter/material.dart';

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
    this.safeEdge = 24,
    this.clickLeftNextPage = false,
    this.verticalWriting = false,
    this.distanceRatio = 0.3,
    this.speedThreshold = 800,
    this.dragStartTolerance = 8,
  });

  /// 左右区宽度占比。
  final double edgeRatio;

  /// 系统边缘安全边（逻辑像素）。
  final double safeEdge;

  /// 左区点击改为下一页（左利手）。
  final bool clickLeftNextPage;

  /// 竖排：左右语义反转。
  final bool verticalWriting;

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
    if (position.dx < config.safeEdge ||
        position.dx > width - config.safeEdge) {
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
  late final ReaderGestureInterpreter _interpreter = ReaderGestureInterpreter(
    widget.config,
  );
  double _dragDx = 0;
  double _dragDy = 0;

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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final gesture = _interpreter.tapAt(
              details.localPosition,
              width: width,
            );
            _notify(gesture);
            if (gesture == ReaderGesture.tapCenter) {
              widget.onToggleToolbar?.call();
            } else {
              _turn(_interpreter.tapIntent(gesture));
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
