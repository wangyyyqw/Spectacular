import 'package:flutter/material.dart';
import 'package:reader_core/layout/paginator.dart';

import 'selection.dart';

/// 选区层（P4-15）：逐行高亮 + 起止手柄拖拽。
///
/// 只有手柄热区接收手势，其余区域穿透给下层阅读视图（不挡翻页）。
class SelectionLayer extends StatefulWidget {
  /// 创建选区层。
  const SelectionLayer({
    super.key,
    required this.page,
    required this.pageIndex,
    required this.selection,
    required this.onChanged,
    this.onEdgeDrag,
    this.contentPadding = EdgeInsets.zero,
    this.inkMode = false,
    this.color = const Color(0x4D5B8DEF),
    this.handleColor = const Color(0xFF5B8DEF),
  });

  /// 当前页。
  final PageContent page;

  /// 当前页序号（跨页选区按页拆分，§63.5）。
  final int pageIndex;

  /// 当前选区。
  final ReaderSelection selection;

  /// 选区变化回调；跨页时保留另一端的命中点和页码，单页仍回传局部选区。
  final ValueChanged<ReaderSelection> onChanged;

  /// 拖到页边超时触发翻页（§63.5：延时 300ms 避免误触）。
  final ValueChanged<bool>? onEdgeDrag;

  /// 正文相对整页的内缩；绘制与拖拽共用，页边热区仍按整页判定。
  final EdgeInsets contentPadding;

  /// 墨水屏模式：选区改用黑色描边，手柄改为纯黑。
  final bool inkMode;

  /// 边缘热区高度（逻辑像素）：拖进底部/顶部这段区域即触发翻页。
  static const double edgeHotZone = 48;

  /// 高亮颜色。
  final Color color;

  /// 手柄颜色。
  final Color handleColor;

  /// 墨水屏选区与手柄统一使用纯黑。
  static const Color inkColor = Color(0xFF000000);

  /// 按显示模式解析选区/手柄颜色。
  static Color resolveColor({required bool inkMode, required Color color}) =>
      inkMode ? inkColor : color;

  @override
  State<SelectionLayer> createState() => _SelectionLayerState();
}

class _SelectionLayerState extends State<SelectionLayer>
    with SingleTickerProviderStateMixin {
  static const Duration _entranceDuration = Duration(milliseconds: 180);

  late final AnimationController _entranceController;
  late final Animation<double> _entrance;
  late final Animation<double> _handleScale;
  // 跨页手势归一化后端点可能交换，继续移动时仍保留原来的固定端点。
  final _dragOrigins = <bool, ReaderSelection>{};

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: _entranceDuration,
    )..forward();
    _entrance = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _handleScale = Tween<double>(begin: 0.72, end: 1).animate(_entrance);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _entranceController.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant SelectionLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _entranceController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final geometry =
        SelectionOps.geometryForPage(
          widget.page,
          widget.pageIndex,
          widget.selection,
        ) ??
        SelectionOps.geometryOf(widget.page, widget.selection);
    final origin = Offset(
      widget.contentPadding.left,
      widget.contentPadding.top,
    );
    final hotSize =
        SelectionOps.handleDot + SelectionOps.handleTouchPadding * 2;
    return FadeTransition(
      key: const ValueKey<String>('selection-entrance'),
      opacity: _entrance,
      child: Stack(
        children: [
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _SelectionPainter(
                geometry: geometry,
                origin: origin,
                color: widget.color,
                inkMode: widget.inkMode,
              ),
            ),
          ),
          _handle(
            context,
            key: const ValueKey<String>('selection-handle-start'),
            scaleKey: const ValueKey<String>('selection-handle-start-scale'),
            center: geometry.startHandle + origin,
            hotSize: hotSize,
            start: true,
          ),
          _handle(
            context,
            key: const ValueKey<String>('selection-handle-end'),
            scaleKey: const ValueKey<String>('selection-handle-end-scale'),
            center: geometry.endHandle + origin,
            hotSize: hotSize,
            start: false,
          ),
        ],
      ),
    );
  }

  Widget _handle(
    BuildContext context, {
    required Key key,
    required Key scaleKey,
    required Offset center,
    required double hotSize,
    required bool start,
  }) {
    return Positioned(
      left: center.dx - hotSize / 2,
      top: center.dy - hotSize / 2,
      width: hotSize,
      height: hotSize,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          if (widget.selection.isMultiPage) {
            _dragOrigins[start] = widget.selection;
          } else {
            _dragOrigins.remove(start);
          }
        },
        onPanEnd: (_) => _dragOrigins.remove(start),
        onPanCancel: () => _dragOrigins.remove(start),
        onPanUpdate: (details) {
          final box = context.findRenderObject();
          if (box is! RenderBox) {
            return;
          }
          final local = box.globalToLocal(details.globalPosition);
          final onEdge = widget.onEdgeDrag;
          if (onEdge != null) {
            final height = box.size.height;
            if (local.dy > height - SelectionLayer.edgeHotZone) {
              onEdge(true);
              return;
            }
            if (local.dy < SelectionLayer.edgeHotZone) {
              onEdge(false);
              return;
            }
          }
          _drag(
            widget.selection,
            start: start,
            local:
                local -
                Offset(widget.contentPadding.left, widget.contentPadding.top),
          );
        },
        child: ScaleTransition(
          key: scaleKey,
          scale: _handleScale,
          child: Center(
            child: Container(
              width: SelectionOps.handleDot,
              height: SelectionOps.handleDot,
              decoration: BoxDecoration(
                color: SelectionLayer.resolveColor(
                  inkMode: widget.inkMode,
                  color: widget.handleColor,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _drag(
    ReaderSelection current, {
    required bool start,
    required Offset local,
  }) {
    final next = _selectionAfterDrag(current, start: start, local: local);
    if (next.start != current.start ||
        next.end != current.end ||
        next.startPageIndex != current.startPageIndex ||
        next.endPageIndex != current.endPageIndex) {
      widget.onChanged(next);
    }
  }

  ReaderSelection _selectionAfterDrag(
    ReaderSelection current, {
    required bool start,
    required Offset local,
  }) {
    // 拖拽是字符级（§63.2），命中已钳制在页内；跨页由边缘翻页扩展。
    final hit = SelectionOps.charAt(widget.page, local);
    final origin = _dragOrigins[start] ?? current;
    if (origin.isMultiPage) {
      return ReaderSelection.spanning(
        start: start ? hit : origin.start,
        startPageIndex: start ? widget.pageIndex : origin.startPageIndex,
        end: start ? origin.end : hit,
        endPageIndex: start ? origin.endPageIndex : widget.pageIndex,
      );
    }
    final localSelection =
        SelectionOps.localSelectionOf(widget.page, widget.pageIndex, current) ??
        current;
    return start
        ? ReaderSelection.normalized(
            hit,
            localSelection.end,
            pageIndex: widget.pageIndex,
          )
        : ReaderSelection.normalized(
            localSelection.start,
            hit,
            pageIndex: widget.pageIndex,
          );
  }
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter({
    required this.geometry,
    required this.origin,
    required this.color,
    required this.inkMode,
  });

  final SelectionGeometry geometry;
  final Offset origin;
  final Color color;
  final bool inkMode;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    final paint = Paint()
      ..color = SelectionLayer.resolveColor(inkMode: inkMode, color: color);
    if (inkMode) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
    }
    for (final rect in geometry.lineRects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.origin != origin ||
      oldDelegate.color != color ||
      oldDelegate.inkMode != inkMode;
}
