import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;

/// 页面随水平手势平移，松手后补完切换或回到原位。
class HorizontalPageSwitcher<T> extends StatefulWidget {
  const HorizontalPageSwitcher({
    super.key,
    this.gestureKey,
    required this.items,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.builder,
  });

  final Key? gestureKey;
  final List<T> items;
  final T value;
  final bool enabled;
  final ValueChanged<T> onChanged;
  final Widget Function(T value) builder;

  @override
  State<HorizontalPageSwitcher<T>> createState() =>
      _HorizontalPageSwitcherState<T>();
}

class _HorizontalPageSwitcherState<T> extends State<HorizontalPageSwitcher<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late T _displayValue;
  final _offset = ValueNotifier<double>(0);
  double _from = 0;
  double _to = 0;
  double _distance = 0;
  double _width = 1;
  int _direction = 0;
  int? _targetIndex;

  @override
  void initState() {
    super.initState();
    _displayValue = widget.value;
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          final t = Curves.easeOutCubic.transform(_controller.value);
          _offset.value = _from + (_to - _from) * t;
        });
  }

  @override
  void didUpdateWidget(HorizontalPageSwitcher<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled ||
        !listEquals(oldWidget.items, widget.items) ||
        !widget.items.contains(_displayValue)) {
      _controller.stop();
      _displayValue = widget.value;
      _offset.value = 0;
      _direction = 0;
      _targetIndex = null;
    } else if (oldWidget.value != widget.value &&
        _displayValue != widget.value) {
      _controller.stop();
      final previous = widget.items.indexOf(_displayValue);
      final next = widget.items.indexOf(widget.value);
      _direction = (next - previous).sign;
      _offset.value = 0;
      _settle(true, targetIndex: next);
    }
  }

  int get _neighborIndex => widget.items.indexOf(_displayValue) + _direction;

  void _dragUpdate(DragUpdateDetails details) {
    if (_controller.isAnimating) return;
    _distance += details.primaryDelta ?? 0;
    final direction = _distance < 0 ? 1 : -1;
    final next = widget.items.indexOf(_displayValue) + direction;
    final nextDirection = next >= 0 && next < widget.items.length
        ? direction
        : 0;
    if (_direction != nextDirection) {
      setState(() => _direction = nextDirection);
    }
    _offset.value = _direction == 0 ? 0 : (_distance / _width).clamp(-1.0, 1.0);
  }

  void _dragEnd(DragEndDetails details) {
    if (_controller.isAnimating) return;
    final velocity = details.primaryVelocity ?? 0;
    final commit =
        _direction != 0 &&
        (_distance.abs() >= 48 ||
            (_distance.abs() >= 20 && velocity.abs() >= 400));
    _settle(commit);
  }

  Future<void> _settle(bool commit, {int? targetIndex}) async {
    _targetIndex = targetIndex;
    final target = commit
        ? widget.items[targetIndex ?? _neighborIndex]
        : _displayValue;
    _from = _offset.value;
    _to = commit ? -_direction.toDouble() : 0;
    if (!MediaQuery.disableAnimationsOf(context) && _from != _to) {
      try {
        await _controller.forward(from: 0).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _displayValue = target;
      _offset.value = 0;
      _direction = 0;
    });
    if (commit && widget.value != target) widget.onChanged(target);
  }

  @override
  void dispose() {
    _controller.dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _width = constraints.maxWidth;
      Widget page(T value, double offset, {required bool active}) =>
          AnimatedBuilder(
            key: ValueKey(('horizontal-page', value)),
            animation: _offset,
            builder: (_, child) => FractionalTranslation(
              translation: Offset(_offset.value + offset, 0),
              child: child,
            ),
            // 手势和补间只改变平移，页面内容复用本次构建结果。
            child: ExcludeFocus(
              excluding: !active,
              child: ExcludeSemantics(
                excluding: !active,
                child: IgnorePointer(
                  ignoring: !active,
                  child: HeroMode(
                    enabled: active,
                    child: RepaintBoundary(child: widget.builder(value)),
                  ),
                ),
              ),
            ),
          );
      return GestureDetector(
        key: widget.gestureKey,
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: widget.enabled
            ? (_) {
                if (!_controller.isAnimating) {
                  _distance = 0;
                  _targetIndex = null;
                }
              }
            : null,
        onHorizontalDragUpdate: widget.enabled ? _dragUpdate : null,
        onHorizontalDragEnd: widget.enabled ? _dragEnd : null,
        onHorizontalDragCancel: widget.enabled
            ? () {
                if (!_controller.isAnimating) _settle(false);
              }
            : null,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              page(_displayValue, 0, active: _direction == 0),
              if (_direction != 0)
                page(
                  widget.items[_targetIndex ?? _neighborIndex],
                  _direction.toDouble(),
                  active: false,
                ),
            ],
          ),
        ),
      );
    },
  );
}
