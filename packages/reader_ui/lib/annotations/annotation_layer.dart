import 'package:flutter/material.dart';
import 'package:reader_core/layout/paginator.dart';

import '../selection/selection.dart';
import 'annotation.dart';
import 'decorations.dart';

/// 标注装饰层（P4-18）：高亮底色 + 笔记标记。
///
/// 绘制在正文之上、选区层之下：高亮按半透明底色叠加（§64.3 允许装饰层独立
/// 绘制），重叠标注按创建时间顺序绘制，后来的覆盖先前的。
class AnnotationLayer extends StatelessWidget {
  /// 创建标注层。
  const AnnotationLayer({
    super.key,
    required this.page,
    required this.annotations,
    this.highlightAlpha = 0.32,
    this.noteMarkerColor = const Color(0xFFFFC107),
    this.inkMode = false,
  });

  /// 当前页。
  final PageContent page;

  /// 全书标注（内部按当前页过滤）。
  final List<ReaderAnnotation> annotations;

  /// 高亮底色透明度。
  final double highlightAlpha;

  /// 笔记标记颜色。
  final Color noteMarkerColor;

  /// 墨水屏模式（P4-23，§42.2）：高亮改为下划线，不画半透明色块。
  final bool inkMode;

  @override
  Widget build(BuildContext context) {
    if (annotations.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _AnnotationPainter(
          page: page,
          lines: AnnotationDecorations.linesFor(page, annotations),
          highlightAlpha: highlightAlpha,
          noteMarkerColor: noteMarkerColor,
          inkMode: inkMode,
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter({
    required this.page,
    required this.lines,
    required this.highlightAlpha,
    required this.noteMarkerColor,
    required this.inkMode,
  });

  final PageContent page;
  final List<AnnotationLine> lines;
  final double highlightAlpha;
  final Color noteMarkerColor;
  final bool inkMode;

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty) {
      return;
    }
    // 按创建时间顺序绘制（linesFor 已排序）：后创建的覆盖先创建的。
    final noteMarks = <Offset>{};
    for (final line in lines) {
      final rects = SelectionOps.lineRectsFor(
        line.line,
        line.startOffset,
        line.endOffset,
      );
      if (inkMode) {
        // 墨水屏只认黑白两级：高亮用 2px 黑色下划线（§42.2）。
        final underline = Paint()
          ..color = const Color(0xFF000000)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        for (final rect in rects) {
          final y = rect.bottom - 1;
          canvas.drawLine(
            Offset(rect.left, y),
            Offset(rect.right, y),
            underline,
          );
        }
      } else {
        final color = Color(line.annotation.color ?? 0xFFFFEB3B)
            .withValues(alpha: highlightAlpha);
        final paint = Paint()..color = color;
        for (final rect in rects) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(2)),
            paint,
          );
        }
      }
      if (line.annotation.type == ReaderAnnotationType.note && rects.isNotEmpty) {
        noteMarks.add(Offset(rects.last.right + 4, rects.last.center.dy));
      }
    }
    // 笔记标记：行尾右侧的小圆点（P4-18）。
    final marker = Paint()..color = noteMarkerColor;
    for (final center in noteMarks) {
      canvas.drawCircle(center, 3, marker);
    }
  }

  @override
  bool shouldRepaint(_AnnotationPainter oldDelegate) =>
      oldDelegate.inkMode != inkMode ||
      oldDelegate.lines.length != lines.length ||
      oldDelegate.page.spineIndex != page.spineIndex ||
      oldDelegate.page.pageIndex != page.pageIndex ||
      oldDelegate.highlightAlpha != highlightAlpha ||
      oldDelegate.noteMarkerColor != noteMarkerColor;
}
