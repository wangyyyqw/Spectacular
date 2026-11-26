import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 抽屉保持最终视口尺寸，只把已露出的范围交给懒加载列表。
class ReaderPanelReveal extends InheritedWidget {
  const ReaderPanelReveal({
    super.key,
    required this.animation,
    required this.extent,
    required super.child,
  });

  final Animation<double> animation;
  final double extent;

  @override
  bool updateShouldNotify(ReaderPanelReveal oldWidget) =>
      animation != oldWidget.animation || extent != oldWidget.extent;
}

/// 入场按可见范围创建列表项，退场复用完整内容，不改变滚动视口或位置。
class ReaderPanelSliver extends StatelessWidget {
  const ReaderPanelSliver({super.key, required this.sliver});

  final Widget sliver;

  @override
  Widget build(BuildContext context) {
    final reveal = context
        .dependOnInheritedWidgetOfExactType<ReaderPanelReveal>();
    return reveal == null
        ? sliver
        : _RevealSliver(reveal: reveal, child: sliver);
  }
}

class _RevealSliver extends SingleChildRenderObjectWidget {
  const _RevealSliver({required this.reveal, required super.child});

  final ReaderPanelReveal reveal;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRevealSliver(reveal.animation, reveal.extent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRevealSliver renderObject,
  ) => renderObject.update(reveal.animation, reveal.extent);
}

class _RenderRevealSliver extends RenderProxySliver {
  _RenderRevealSliver(this._animation, this._extent);

  Animation<double> _animation;
  double _extent;
  double _paintExtent = double.infinity;

  void update(Animation<double> animation, double extent) {
    if (_animation != animation) {
      if (attached) _animation.removeListener(_tick);
      _animation = animation;
      if (attached) _animation.addListener(_tick);
    }
    _extent = extent;
    _tick();
  }

  void _tick() {
    // 中途关闭只收起已经创建的部分，不为即将移除的屏外条目补做布局。
    if (_animation.status == AnimationStatus.reverse ||
        _animation.status == AnimationStatus.dismissed) {
      return;
    }
    // 提前准备一行触控区域，避免新条目恰好到裁剪边缘才创建。
    final extent =
        _animation.status == AnimationStatus.forward && _animation.value < 1
        ? _extent * _animation.value + 48
        : double.infinity;
    if (_paintExtent == extent) return;
    _paintExtent = extent;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(_tick);
    _tick();
  }

  @override
  void detach() {
    _animation.removeListener(_tick);
    super.detach();
  }

  @override
  void performLayout() {
    // 发生主动滚动时立即交回常规列表布局，保留拖动和无障碍滚动行为。
    final extent = constraints.scrollOffset > 0
        ? double.infinity
        : _paintExtent;
    child!.layout(
      constraints.copyWith(
        remainingPaintExtent: math.min(
          constraints.remainingPaintExtent,
          extent,
        ),
        remainingCacheExtent: math.min(
          constraints.remainingCacheExtent,
          extent,
        ),
      ),
      parentUsesSize: true,
    );
    geometry = child!.geometry;
  }
}
