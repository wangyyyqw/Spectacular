import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../icons/app_icon.dart';
import 'bookmark_ribbon.dart';
import 'bookmark_style.dart';

/// 仅在分页阅读时启用；纵向手势与正文横向翻页参与同一手势竞争。
class BookmarkPullTarget extends StatefulWidget {
  const BookmarkPullTarget({
    super.key,
    required this.child,
    required this.onToggle,
    required this.bookmarked,
    required this.color,
    required this.background,
    this.ribbon,
    this.topInset = 0,
    this.rightInset = 0,
    this.animateReturn = true,
    this.onPullingChanged,
  });

  final Widget child;
  final VoidCallback? onToggle;
  final bool bookmarked;
  final Color color;
  final Color background;
  final ReaderBookmarkRibbon? ribbon;
  final double topInset;
  final double rightInset;
  final bool animateReturn;
  final ValueChanged<bool>? onPullingChanged;

  @override
  State<BookmarkPullTarget> createState() => _BookmarkPullTargetState();
}

class _BookmarkPullTargetState extends State<BookmarkPullTarget> {
  static const _threshold = 140.0;
  Offset? _origin;
  double _distance = 0;
  bool _hintReady = false;
  bool _hintBookmarked = false;
  bool _pulling = false;

  void _setPulling(bool value) {
    if (_pulling == value) return;
    _pulling = value;
    widget.onPullingChanged?.call(value);
  }

  @override
  void didUpdateWidget(BookmarkPullTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onToggle == null) {
      _origin = null;
      _distance = 0;
    }
  }

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
    setState(() {
      _distance = offset.dy.clamp(0, double.infinity);
      _hintReady = _distance >= _threshold;
    });
    if (_distance > 0) _setPulling(true);
  }

  double get _pageOffset =>
      (_distance <= _threshold
              ? _distance
              : _threshold + (_distance - _threshold) * 0.35)
          .clamp(0, 240);

  Widget _buildSurface(double offset, Widget? child) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Color.alphaBlend(
            widget.color.withValues(alpha: 0.06),
            widget.background,
          ),
        ),
        if (offset > 0) _buildHint(),
        Transform.translate(
          key: const ValueKey('bookmark-pull-page'),
          offset: Offset(0, offset),
          child: ColoredBox(color: widget.background, child: child),
        ),
        // 归位结束先保留已添加的标记，下一帧与纸面同时交接。
        if (widget.ribbon != null &&
            (offset > 0 || (_pulling && widget.bookmarked)))
          Positioned(
            top: 0,
            right: widget.ribbon!.style.rightInset + widget.rightInset,
            child: IgnorePointer(
              child: Semantics(
                label: widget.bookmarked ? '当前页已有书签' : '添加书签',
                child: widget.ribbon,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buildHint() {
    final ready = _hintReady;
    return Positioned(
      top: widget.topInset + 28,
      left: 16,
      right:
          (widget.ribbon?.style.rightInset ??
              const ReaderBookmarkStyle().rightInset) +
          16 +
          widget.rightInset +
          (widget.ribbon?.style.width ?? 0),
      child: IgnorePointer(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            RotatedBox(
              quarterTurns: ready ? 1 : 3,
              child: AppIcon(AppGlyph.arrowBack, size: 18, color: widget.color),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${ready ? '松手确认' : '下拉'}'
                '${_hintBookmarked ? '移除' : '添加'}${ready ? '' : '书签'}',
                style: TextStyle(color: widget.color, fontSize: 14),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 手势目标保持原位，只有页面整体位移，避免拖动坐标随正文变化。
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onVerticalDragDown: widget.onToggle == null
        ? null
        : (details) {
            _reset();
            _origin = details.localPosition;
            _hintReady = false;
            _hintBookmarked = widget.bookmarked;
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
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: widget.onToggle == null ? 0 : _pageOffset),
        duration:
            _origin != null ||
                !widget.animateReturn ||
                MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        onEnd: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _distance == 0) _setPulling(false);
          });
        },
        builder: (context, offset, child) => _buildSurface(offset, child),
        child: RepaintBoundary(child: widget.child),
      ),
    ),
  );
}
