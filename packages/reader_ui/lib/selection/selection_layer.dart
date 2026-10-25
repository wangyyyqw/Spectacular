import 'package:flutter/material.dart';
import 'package:reader_core/layout/paginator.dart';

import 'selection.dart';

/// 选区层（P4-15）：逐行高亮 + 起止手柄拖拽。
///
/// 只有手柄热区接收手势，其余区域穿透给下层阅读视图（不挡翻页）。
class SelectionLayer extends StatelessWidget {
  /// 创建选区层。
  const SelectionLayer({
    super.key,
    required this.page,
    required this.selection,
    required this.onChanged,
    this.color = const Color(0x4D5B8DEF),
    this.handleColor = const Color(0xFF5B8DEF),
  });

  /// 当前页。
  final PageContent page;

  /// 当前选区。
  final ReaderSelection selection;

  /// 选区变化回调（拖拽手柄）。
  final ValueChanged<ReaderSelection> onChanged;

  /// 高亮颜色。
  final Color color;

  /// 手柄颜色。
  final Color handleColor;

  @override
  Widget build(BuildContext context) {
    final geometry = SelectionOps.geometryOf(page, selection);
    final hotSize =
        SelectionOps.handleDot + SelectionOps.handleTouchPadding * 2;
    return Stack(
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _SelectionPainter(
              geometry: geometry,
              color: color,
              handleColor: handleColor,
            ),
          ),
        ),
        _handle(
          context,
          key: const ValueKey<String>('selection-handle-start'),
          center: geometry.startHandle,
          hotSize: hotSize,
          onDrag: (local) => _drag(selection, start: true, local: local),
        ),
        _handle(
          context,
          key: const ValueKey<String>('selection-handle-end'),
          center: geometry.endHandle,
          hotSize: hotSize,
          onDrag: (local) => _drag(selection, start: false, local: local),
        ),
      ],
    );
  }

  Widget _handle(
    BuildContext context, {
    required Key key,
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
          onDrag(local);
        },
        child: Center(
          child: Container(
            width: SelectionOps.handleDot,
            height: SelectionOps.handleDot,
            decoration: BoxDecoration(
              color: handleColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  void _drag(ReaderSelection current, {required bool start, required Offset local}) {
    // 拖拽是字符级（§63.2），命中已钳制在页内，不会越页。
    final hit = SelectionOps.charAt(page, local);
    final next = start
        ? ReaderSelection.normalized(hit, current.end)
        : ReaderSelection.normalized(current.start, hit);
    if (next.start != current.start || next.end != current.end) {
      onChanged(next);
    }
  }
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter({
    required this.geometry,
    required this.color,
    required this.handleColor,
  });

  final SelectionGeometry geometry;
  final Color color;
  final Color handleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    for (final rect in geometry.lineRects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        fill,
      );
    }
    final dot = Paint()..color = handleColor;
    for (final center in [geometry.startHandle, geometry.endHandle]) {
      canvas.drawCircle(center, SelectionOps.handleDot / 2, dot);
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.color != color ||
      oldDelegate.handleColor != handleColor;
}
