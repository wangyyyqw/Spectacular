import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../annotations/annotation.dart';
import '../annotations/annotation_style_painter.dart';
import 'decoration_geometry.dart';
import 'decoration_style.dart';

/// 装饰盒绘制，调用方传入已扩展内边距的逐行矩形。
abstract final class ReaderDecorationPainter {
  static void paintHighlights(
    Canvas canvas,
    List<ReaderDecorationBox> boxes, {
    required bool foreground,
    bool inkMode = false,
  }) {
    for (final box in boxes) {
      final highlight = box.style.highlight;
      if (highlight == null) continue;
      final line = box.range.line;
      final source = line.slice.block.layout.lines[line.lineIndex];
      final baseline =
          (line.textTop ?? line.rect.top) +
          source.baseline -
          source.top +
          highlight.strokeWidth;
      for (final rect in box.range.rects) {
        paintHighlight(
          canvas,
          rect,
          highlight,
          foreground: foreground,
          inkMode: inkMode,
          vertical: line.isVertical,
          baseline: line.isVertical ? null : baseline,
        );
      }
    }
    if (!foreground && !inkMode) _paintJoinedHighlights(canvas, boxes);
  }

  static void paintHighlight(
    Canvas canvas,
    Rect rect,
    ReaderDecorationHighlight highlight, {
    required bool foreground,
    bool inkMode = false,
    bool vertical = false,
    double? baseline,
  }) {
    final style = inkMode ? highlight.style.inkStyle : highlight.style;
    final background =
        style == ReaderAnnotationStyle.background ||
        style == ReaderAnnotationStyle.halfBackground;
    if (background == foreground || style == ReaderAnnotationStyle.tint) return;
    final opacity = inkMode
        ? 1.0
        : Color(highlight.color).a * highlight.effectiveOpacity;
    AnnotationStylePainter.paint(
      canvas,
      rect,
      color: inkMode ? const Color(0xFF000000) : Color(highlight.color),
      style: style,
      fillAlpha: opacity,
      strokeAlpha: opacity,
      strokeWidth: inkMode ? 2 : highlight.strokeWidth,
      vertical: vertical,
      baseline: baseline,
    );
  }

  static void _paintJoinedHighlights(
    Canvas canvas,
    List<ReaderDecorationBox> boxes,
  ) {
    final previousLines =
        <(ReaderDecorationRange, Object, int), List<ReaderDecorationBox>>{};
    for (final box in boxes) {
      final highlight = box.style.highlight;
      final source = box.highlightSource;
      final line = box.range.line;
      if (highlight == null ||
          source == null ||
          !highlight.joinLines ||
          highlight.style != ReaderAnnotationStyle.background ||
          line.isVertical) {
        continue;
      }
      final previous =
          previousLines[(source, line.slice.block, line.lineIndex - 1)] ??
          const [];
      for (final before in previous) {
        for (final upper in before.range.rects) {
          for (final lower in box.range.rects) {
            paintHighlightGap(canvas, upper, lower, highlight);
          }
        }
      }
      (previousLines[(source, line.slice.block, line.lineIndex)] ??= []).add(
        box,
      );
    }
  }

  static void paintHighlightGap(
    Canvas canvas,
    Rect upper,
    Rect lower,
    ReaderDecorationHighlight highlight,
  ) {
    final gap = Rect.fromLTRB(
      math.max(upper.left, lower.left),
      upper.bottom,
      math.min(upper.right, lower.right),
      lower.top,
    );
    if (gap.isEmpty) return;
    canvas.drawRect(
      gap,
      Paint()
        ..color = Color(highlight.color).withValues(
          alpha: Color(highlight.color).a * highlight.effectiveOpacity,
        ),
    );
  }

  /// 依次绘制底色、圆角裁切图片和四边边框，不覆盖正文文字。
  static void paintBox(
    Canvas canvas,
    Rect rect,
    ReaderDecorationStyle style, {
    ui.Image? image,
    bool inkMode = false,
  }) {
    if (rect.isEmpty) return;
    final radius = math.min(
      style.borderRadius,
      math.min(rect.width, rect.height) / 2,
    );
    final rounded = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(rounded);
    if (inkMode) {
      if (style.backgroundColor != null || style.backgroundImagePath != null) {
        canvas.drawLine(
          Offset(rect.left, rect.bottom - 1),
          Offset(rect.right, rect.bottom - 1),
          Paint()
            ..color = const Color(0xFF000000)
            ..strokeWidth = 2,
        );
      }
    } else {
      final color = style.backgroundColor;
      if (color != null) {
        canvas.drawRRect(
          rounded,
          Paint()
            ..color = Color(color)
                .withValues(alpha: Color(color).a * style.backgroundOpacity),
        );
      }
      if (image != null) {
        paintImage(
          canvas: canvas,
          rect: rect,
          image: image,
          fit: style.backgroundImageFit.fit,
          repeat: style.backgroundImageFit == ReaderDecorationImageFit.tile
              ? ImageRepeat.repeat
              : ImageRepeat.noRepeat,
          opacity: style.backgroundOpacity,
          filterQuality: FilterQuality.low,
        );
      }
    }
    _paintBorders(canvas, rect, radius, style, inkMode);
    canvas.restore();
  }

  static void _paintBorders(
    Canvas canvas,
    Rect rect,
    double radius,
    ReaderDecorationStyle style,
    bool inkMode,
  ) {
    final sides = [
      style.borderTop,
      style.borderRight,
      style.borderBottom,
      style.borderLeft,
    ];
    for (var index = 0; index < sides.length; index++) {
      final side = sides[index];
      if (side.width <= 0) continue;
      canvas.save();
      canvas.clipRect(_sideClip(rect, index, math.max(radius, side.width)));
      _paintOutline(
        canvas,
        rect,
        radius,
        side.width,
        inkMode ? const Color(0xFF000000) : Color(side.color),
        style.borderStyle,
      );
      canvas.restore();
    }
  }

  static Rect _sideClip(Rect rect, int side, double depth) => switch (side) {
    0 => Rect.fromLTRB(rect.left, rect.top, rect.right, rect.top + depth),
    1 => Rect.fromLTRB(rect.right - depth, rect.top, rect.right, rect.bottom),
    2 => Rect.fromLTRB(rect.left, rect.bottom - depth, rect.right, rect.bottom),
    _ => Rect.fromLTRB(rect.left, rect.top, rect.left + depth, rect.bottom),
  };

  static Path _outline(Rect rect, double radius, double inset) =>
      Path()..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(inset),
          Radius.circular(math.max(0, radius - inset)),
        ),
      );

  static void _paintOutline(
    Canvas canvas,
    Rect rect,
    double radius,
    double width,
    Color color,
    ReaderDecorationBorderStyle style,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    if (style == ReaderDecorationBorderStyle.double) {
      paint.strokeWidth = width / 3;
      canvas.drawPath(_outline(rect, radius, width / 6), paint);
      canvas.drawPath(_outline(rect, radius, width * 5 / 6), paint);
      return;
    }
    final path = _outline(rect, radius, width / 2);
    if (style == ReaderDecorationBorderStyle.solid) {
      canvas.drawPath(path, paint);
      return;
    }
    _paintPattern(canvas, path, paint, style);
  }

  static void _paintPattern(
    Canvas canvas,
    Path path,
    Paint paint,
    ReaderDecorationBorderStyle style,
  ) {
    final dotted = style == ReaderDecorationBorderStyle.dotted;
    final dash = math.max(3.0, paint.strokeWidth * 3);
    final gap = math.max(2.0, paint.strokeWidth * 2);
    final step = dotted ? paint.strokeWidth * 2.5 : dash + gap;
    for (final metric in path.computeMetrics()) {
      for (var position = 0.0; position < metric.length; position += step) {
        if (dotted) {
          final tangent = metric.getTangentForOffset(position);
          if (tangent != null) {
            canvas.drawCircle(
              tangent.position,
              paint.strokeWidth / 2,
              Paint()..color = paint.color,
            );
          }
        } else {
          canvas.drawPath(
            metric.extractPath(
              position,
              math.min(position + dash, metric.length),
            ),
            paint,
          );
        }
      }
    }
  }
}
