import 'package:flutter/material.dart';

/// 仅在分页阅读时启用；纵向手势与正文横向翻页参与同一手势竞争。
class BookmarkPullTarget extends StatefulWidget {
  const BookmarkPullTarget({
    super.key,
    required this.child,
    required this.onAdd,
    required this.color,
    required this.background,
    this.topInset = 0,
  });

  final Widget child;
  final VoidCallback? onAdd;
  final Color color;
  final Color background;
  final double topInset;

  @override
  State<BookmarkPullTarget> createState() => _BookmarkPullTargetState();
}

class _BookmarkPullTargetState extends State<BookmarkPullTarget> {
  static const _threshold = 80.0;
  double _distance = 0;

  void _reset() => setState(() => _distance = 0);

  // 手势与提示采用同一声明式树，避免拆散距离状态的生命周期。
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onVerticalDragStart: widget.onAdd == null ? null : (_) => _reset(),
    onVerticalDragUpdate: widget.onAdd == null
        ? null
        : (details) => setState(() {
            _distance = (_distance + details.delta.dy).clamp(0, 160);
          }),
    onVerticalDragEnd: widget.onAdd == null
        ? null
        : (_) {
            final add = _distance >= _threshold;
            _reset();
            if (add) widget.onAdd?.call();
          },
    onVerticalDragCancel: widget.onAdd == null ? null : _reset,
    child: Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (widget.onAdd != null && _distance > 0)
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
                      _distance >= _threshold ? '松手添加书签' : '下拉添加书签',
                      style: TextStyle(color: widget.color),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
