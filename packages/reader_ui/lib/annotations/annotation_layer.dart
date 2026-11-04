import 'package:flutter/material.dart';
import 'package:reader_core/layout/paginator.dart';

import '../selection/selection.dart';
import 'annotation.dart';
import 'annotation_style_painter.dart';
import 'decorations.dart';

/// 标注装饰层（P4-18）：高亮样式 + 笔记标记。
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

  /// 笔记标记颜色：墨水屏统一为黑色，普通模式沿用传入颜色。
  static Color markerColor({required bool inkMode, required Color color}) =>
      inkMode ? const Color(0xFF000000) : color;

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
      // 墨水屏默认底色样式降级为黑色下划线，其他线型保留形状。
      final style =
          inkMode && line.annotation.style == ReaderAnnotationStyle.background
          ? ReaderAnnotationStyle.underline
          : line.annotation.style;
      final color = inkMode
          ? const Color(0xFF000000)
          : Color(line.annotation.color ?? defaultHighlightColor);
      for (final rect in rects) {
        AnnotationStylePainter.paint(
          canvas,
          rect,
          color: color,
          style: style,
          fillAlpha: highlightAlpha,
          strokeAlpha: inkMode ? 1 : 0.9,
          strokeWidth: inkMode ? 2 : 1.8,
        );
      }
      if (line.annotation.type == ReaderAnnotationType.note &&
          rects.isNotEmpty) {
        noteMarks.add(
          Offset(
            rects.last.right + AnnotationDecorations.noteMarkerOffset,
            rects.last.center.dy,
          ),
        );
      }
    }
    // 笔记标记：行尾右侧的小圆点（P4-18）。
    final marker = Paint()
      ..color = AnnotationLayer.markerColor(
        inkMode: inkMode,
        color: noteMarkerColor,
      );
    for (final center in noteMarks) {
      canvas.drawCircle(center, AnnotationDecorations.noteMarkerRadius, marker);
    }
  }

  @override
  bool shouldRepaint(_AnnotationPainter oldDelegate) =>
      oldDelegate.inkMode != inkMode ||
      !_sameLines(oldDelegate.lines, lines) ||
      oldDelegate.page.spineIndex != page.spineIndex ||
      oldDelegate.page.pageIndex != page.pageIndex ||
      oldDelegate.highlightAlpha != highlightAlpha ||
      oldDelegate.noteMarkerColor != noteMarkerColor;

  bool _sameLines(List<AnnotationLine> left, List<AnnotationLine> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      final a = left[index];
      final b = right[index];
      if (!identical(a.line, b.line) ||
          a.startOffset != b.startOffset ||
          a.endOffset != b.endOffset ||
          a.annotation.id != b.annotation.id ||
          a.annotation.type != b.annotation.type ||
          a.annotation.color != b.annotation.color ||
          a.annotation.style != b.annotation.style) {
        return false;
      }
    }
    return true;
  }
}
