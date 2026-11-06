import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_core/layout/paginator.dart';

import 'annotation.dart';
import 'annotation_style_painter.dart';
import 'decorations.dart';
import 'mark_settings.dart';
import 'thought_marker.dart';

/// 阅读标记与页边想法层，选区始终位于此层之上。
class AnnotationLayer extends StatelessWidget {
  /// 创建标注层。
  const AnnotationLayer({
    super.key,
    required this.page,
    required this.annotations,
    this.inkMode = false,
    this.settings = const ReaderMarkSettings(),
    this.backgroundsBehindText = false,
  });

  /// 当前页及已核验的标注。
  final PageContent page;
  final List<ReaderAnnotation> annotations;

  /// 墨水屏保留线型，背景与染色降级为黑色实线。
  final bool inkMode;

  /// 全局线宽与连块设置。
  final ReaderMarkSettings settings;

  /// 阅读页已在文字前绘制底色时，此层只绘制线条与图标。
  final bool backgroundsBehindText;

  /// 墨水屏图标统一为黑色。
  static Color markerColor({required bool inkMode, required Color color}) =>
      inkMode ? const Color(0xFF000000) : color;

  @override
  Widget build(BuildContext context) => annotations.isEmpty
      ? const SizedBox.shrink()
      : IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _AnnotationPainter(
              page: page,
              annotations: annotations,
              inkMode: inkMode,
              settings: settings,
              backgroundsBehindText: backgroundsBehindText,
            ),
          ),
        );
}

/// 共用阅读标记绘制器，正文前绘底色，正文后绘线条与想法。
abstract final class ReaderAnnotationPainting {
  /// 在作者块背景与手工装饰之后、正文之前绘制阅读底色。
  static void paintBackgrounds(
    Canvas canvas,
    PageContent page,
    List<ReaderAnnotation> annotations,
    ReaderMarkSettings settings, {
    PageBlockSlice? slice,
  }) {
    final lines = AnnotationDecorations.linesFor(page, annotations);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (slice != null && !identical(line.line.slice, slice)) continue;
      final style = line.annotation.style;
      if (style != ReaderAnnotationStyle.background &&
          style != ReaderAnnotationStyle.halfBackground) {
        continue;
      }
      _paintLine(canvas, line, settings: settings, inkMode: false);
      if (settings.joinBackgroundLines &&
          style == ReaderAnnotationStyle.background &&
          index > 0) {
        _paintGap(canvas, lines[index - 1], line);
      }
    }
  }

  static void _paintGap(
    Canvas canvas,
    AnnotationLine before,
    AnnotationLine after,
  ) {
    if (before.annotation.id != after.annotation.id ||
        !identical(before.line.slice.block, after.line.slice.block) ||
        before.line.lineIndex + 1 != after.line.lineIndex ||
        before.line.isVertical) {
      return;
    }
    final upper = AnnotationDecorations.rectsFor(before);
    final lower = AnnotationDecorations.rectsFor(after);
    if (upper.isEmpty || lower.isEmpty) return;
    final left = math.max(upper.last.left, lower.first.left);
    final right = math.min(upper.last.right, lower.first.right);
    if (right <= left || lower.first.top <= upper.last.bottom) return;
    canvas.drawRect(
      Rect.fromLTRB(left, upper.last.bottom, right, lower.first.top),
      Paint()
        ..color = Color(after.annotation.color ?? defaultHighlightColor)
            .withValues(alpha: after.annotation.effectiveOpacity),
    );
  }

  static void _paintLine(
    Canvas canvas,
    AnnotationLine line, {
    required ReaderMarkSettings settings,
    required bool inkMode,
  }) {
    final annotation = line.annotation;
    final width = inkMode ? 2.0 : settings.strokeWidth;
    final source = line.line.slice.block.layout.lines[line.line.lineIndex];
    final baseline =
        (line.line.textTop ?? line.line.rect.top) +
        source.baseline -
        source.top +
        width;
    final opacity = inkMode ? 1.0 : annotation.effectiveOpacity;
    for (final rect in AnnotationDecorations.rectsFor(line)) {
      AnnotationStylePainter.paint(
        canvas,
        rect,
        color: inkMode
            ? Colors.black
            : Color(annotation.color ?? defaultHighlightColor),
        style: inkMode ? annotation.style.inkStyle : annotation.style,
        fillAlpha: opacity,
        strokeAlpha: opacity,
        strokeWidth: width,
        baseline: line.line.isVertical ? null : baseline,
        vertical: line.line.isVertical,
      );
    }
  }
}

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter({
    required this.page,
    required this.annotations,
    required this.inkMode,
    required this.settings,
    required this.backgroundsBehindText,
  });

  final PageContent page;
  final List<ReaderAnnotation> annotations;
  final bool inkMode;
  final ReaderMarkSettings settings;
  final bool backgroundsBehindText;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = AnnotationDecorations.linesFor(page, annotations);
    if (!inkMode && !backgroundsBehindText) {
      ReaderAnnotationPainting.paintBackgrounds(
        canvas,
        page,
        annotations,
        settings,
      );
    }
    for (final line in lines) {
      if (!inkMode &&
          (line.annotation.style == ReaderAnnotationStyle.background ||
              line.annotation.style == ReaderAnnotationStyle.halfBackground)) {
        continue;
      }
      ReaderAnnotationPainting._paintLine(
        canvas,
        line,
        settings: settings,
        inkMode: inkMode,
      );
    }
    for (final marker in ThoughtMarkerGeometry.markersFor(
      page,
      lines,
      contentWidth: size.width,
    )) {
      ThoughtMarkerGeometry.paint(
        canvas,
        marker,
        inkMode
            ? Colors.black
            : Color(marker.annotation.color ?? defaultHighlightColor),
      );
    }
  }

  @override
  bool shouldRepaint(_AnnotationPainter oldDelegate) =>
      oldDelegate.page != page ||
      oldDelegate.annotations != annotations ||
      oldDelegate.inkMode != inkMode ||
      oldDelegate.settings != settings ||
      oldDelegate.backgroundsBehindText != backgroundsBehindText;
}
