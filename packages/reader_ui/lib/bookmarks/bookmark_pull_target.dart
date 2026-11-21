import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// 仅在分页阅读时启用；纵向手势与正文横向翻页参与同一手势竞争。
class BookmarkPullTarget extends StatefulWidget {
  const BookmarkPullTarget({
    super.key,
    required this.child,
    required this.onToggle,
    required this.bookmarked,
    required this.color,
    required this.background,
    this.topInset = 0,
  });

  final Widget child;
  final VoidCallback? onToggle;
  final bool bookmarked;
  final Color color;
  final Color background;
  final double topInset;

  @override
  State<BookmarkPullTarget> createState() => _BookmarkPullTargetState();
}

class _BookmarkPullTargetState extends State<BookmarkPullTarget> {
  static const _threshold = 140.0;
  Offset? _origin;
  double _distance = 0;

  void _reset() => setState(() {
    _origin = null;
    _distance = 0;
  });

  void _update(Offset position) {
    final origin = _origin;
    if (origin == null) return;
    final offset = position - origin;
    // 明显横移或先上滑的手势整次取消，避免翻页和往返拖动误触。
    if (offset.dx.abs() > 48 || offset.dy < -kTouchSlop) {
      _reset();
      return;
    }
    setState(() => _distance = offset.dy.clamp(0, double.infinity));
  }

  // 手势与提示采用同一声明式树，避免拆散距离状态的生命周期。
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onVerticalDragDown: widget.onToggle == null
        ? null
        : (details) {
            _reset();
            _origin = details.localPosition;
          },
    onVerticalDragStart: widget.onToggle == null
        ? null
        : (details) => _update(details.localPosition),
    onVerticalDragUpdate: widget.onToggle == null
        ? null
        : (details) => _update(details.localPosition),
    onVerticalDragEnd: widget.onToggle == null
        ? null
        : (_) {
            final trigger = _distance >= _threshold;
            _reset();
            if (trigger) widget.onToggle?.call();
          },
    onVerticalDragCancel: widget.onToggle == null ? null : _reset,
    // 已被识别的拖动收到系统取消时仍可能回调结束，先清除距离。
    child: Listener(
      onPointerCancel: (_) => _reset(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (widget.onToggle != null && _distance >= 40)
            Positioned(
              top: widget.topInset + 12,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Material(
                    color: widget.background,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        '${_distance >= _threshold ? '松手' : '下拉'}'
                        '${widget.bookmarked ? '移除' : '添加'}书签',
                        style: TextStyle(color: widget.color),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
