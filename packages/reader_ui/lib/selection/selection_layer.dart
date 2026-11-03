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
    this.color = const Color(0x4D5B8DEF),
    this.handleColor = const Color(0xFF5B8DEF),
  });

  /// 当前页。
  final PageContent page;

  /// 当前页序号（跨页选区按页拆分，§63.5）。
  final int pageIndex;

  /// 当前选区。
  final ReaderSelection selection;

  /// 选区变化回调（拖拽手柄，参数是该页的局部选区）。
  final ValueChanged<ReaderSelection> onChanged;

  /// 拖到页边超时触发翻页（§63.5：延时 300ms 避免误触）。
  final ValueChanged<bool>? onEdgeDrag;

  /// 正文相对整页的内缩；绘制与拖拽共用，页边热区仍按整页判定。
  final EdgeInsets contentPadding;

  /// 边缘热区高度（逻辑像素）：拖进底部/顶部这段区域即触发翻页。
  static const double edgeHotZone = 48;

  /// 高亮颜色。
  final Color color;

  /// 手柄颜色。
  final Color handleColor;

  @override
  State<SelectionLayer> createState() => _SelectionLayerState();
}

class _SelectionLayerState extends State<SelectionLayer>
    with SingleTickerProviderStateMixin {
  static const Duration _entranceDuration = Duration(milliseconds: 180);

  late final AnimationController _entranceController;
  late final Animation<double> _entrance;
  late final Animation<double> _handleScale;

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
              ),
            ),
          ),
          _handle(
            context,
            key: const ValueKey<String>('selection-handle-start'),
            scaleKey: const ValueKey<String>('selection-handle-start-scale'),
            center: geometry.startHandle + origin,
            hotSize: hotSize,
            onDrag: (local) =>
                _drag(widget.selection, start: true, local: local),
          ),
          _handle(
            context,
            key: const ValueKey<String>('selection-handle-end'),
            scaleKey: const ValueKey<String>('selection-handle-end-scale'),
            center: geometry.endHandle + origin,
            hotSize: hotSize,
            onDrag: (local) =>
                _drag(widget.selection, start: false, local: local),
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
    required ValueChanged<Offset> onDrag,
  }) {
    return Positioned(
      left: center.dx - hotSize / 2,
      top: center.dy - hotSize / 2,
      width: hotSize,
      height: hotSize,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
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
          onDrag(
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
                color: widget.handleColor,
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
    // 拖拽是字符级（§63.2），命中已钳制在页内；跨页由边缘翻页扩展。
    final localSelection =
        SelectionOps.localSelectionOf(widget.page, widget.pageIndex, current) ??
        current;
    final hit = SelectionOps.charAt(widget.page, local);
    final next = start
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
    if (next.start != current.start || next.end != current.end) {
      widget.onChanged(next);
    }
  }
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter({
    required this.geometry,
    required this.origin,
    required this.color,
  });

  final SelectionGeometry geometry;
  final Offset origin;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    final fill = Paint()..color = color;
    for (final rect in geometry.lineRects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        fill,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.origin != origin ||
      oldDelegate.color != color;
}
