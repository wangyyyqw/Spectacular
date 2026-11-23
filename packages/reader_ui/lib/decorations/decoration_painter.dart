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
    final joined = <ReaderDecorationBox>[];
    for (final box in ReaderDecorationGeometry.highlightBoxesFor(boxes)) {
      final highlight = box.style.highlight!;
      if (!foreground &&
          !inkMode &&
          highlight.style == ReaderAnnotationStyle.background &&
          highlight.joinLines &&
          box.highlightSource != null &&
          !box.range.line.isVertical) {
        joined.add(box);
        continue;
      }
      _paintHighlightBox(canvas, box, foreground, inkMode);
    }
    if (joined.isNotEmpty) _paintJoinedHighlights(canvas, joined);
  }

  static void _paintHighlightBox(
    Canvas canvas,
    ReaderDecorationBox box,
    bool foreground,
    bool inkMode,
  ) {
    final highlight = box.style.highlight!;
    final line = box.range.line;
    final source = line.slice.block.layout.lines[line.lineIndex];
    final baseline =
        (line.textTop ?? line.rect.top) +
        source.baseline -
        source.top +
        (inkMode ? 2 : highlight.strokeWidth);
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
    if (background) {
      paintHighlightBackground(
        canvas,
        [
          [rect],
        ],
        highlight,
        vertical: vertical,
      );
      return;
    }
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
    final groups =
        <(ReaderDecorationRange, Object), List<ReaderDecorationBox>>{};
    for (final box in boxes) {
      (groups[(box.highlightSource!, box.range.line.slice.block)] ??= []).add(
        box,
      );
    }
    for (final group in groups.values) {
      final lines = <List<Rect>>[];
      int? previousIndex;
      for (final box in group) {
        final index = box.range.line.lineIndex;
        if (index == previousIndex) {
          lines.last.addAll(box.range.rects);
        } else {
          if (previousIndex != null && index != previousIndex + 1) {
            lines.add(const []);
          }
          lines.add(box.range.rects);
        }
        previousIndex = index;
      }
      paintHighlightBackground(canvas, lines, group.first.style.highlight!);
    }
  }

  static void paintHighlightBackground(
    Canvas canvas,
    List<List<Rect>> lines,
    ReaderDecorationHighlight highlight, {
    bool vertical = false,
  }) {
    final path = Path();
    List<Rect> previous = const [];
    for (final rects in lines) {
      for (final rect in rects) {
        final fill = highlight.style == ReaderAnnotationStyle.halfBackground
            ? vertical
                  ? Rect.fromLTRB(
                      rect.left,
                      rect.top,
                      rect.center.dx,
                      rect.bottom,
                    )
                  : Rect.fromLTRB(
                      rect.left,
                      rect.center.dy,
                      rect.right,
                      rect.bottom,
                    )
            : rect;
        final radius = math.min(
          highlight.borderRadius,
          math.min(fill.width, fill.height) / 2,
        );
        path.addRRect(RRect.fromRectAndRadius(fill, Radius.circular(radius)));
        if (highlight.style == ReaderAnnotationStyle.background &&
            highlight.joinLines &&
            !vertical) {
          for (final upper in previous) {
            _addHighlightGap(path, upper, rect, radius);
          }
        }
      }
      previous = rects;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Color(highlight.color).withValues(
          alpha: Color(highlight.color).a * highlight.effectiveOpacity,
        ),
    );
  }

  static void _addHighlightGap(
    Path path,
    Rect upper,
    Rect lower,
    double radius,
  ) {
    final gap = Rect.fromLTRB(
      math.max(upper.left, lower.left),
      upper.bottom - math.min(radius, upper.height / 2),
      math.min(upper.right, lower.right),
      lower.top + radius,
    );
    if (gap.isEmpty) return;
    path.addRect(gap);
  }

  /// 依次绘制底色、圆角裁切图片和四边边框，不覆盖正文文字。
  static void paintBox(
    Canvas canvas,
    Rect rect,
    ReaderDecorationStyle style, {
    ui.Image? image,
    ReaderDecorationNineSlice? imageNineSlice,
    Rect? imageAnchor,
    Rect? clipRect,
    bool vertical = false,
    bool inkMode = false,
  }) {
    if (rect.isEmpty) return;
    final radius = math.min(
      style.borderRadius,
      math.min(rect.width, rect.height) / 2,
    );
    final rounded = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final nineSlice =
        style.backgroundImageFit == ReaderDecorationImageFit.nineSlice
        ? style.backgroundImageNineSlice ??
              imageNineSlice ??
              const ReaderDecorationNineSlice()
        : null;
    canvas.save();
    if (clipRect != null) canvas.clipRect(clipRect);
    if (nineSlice == null || inkMode) canvas.clipRRect(rounded);
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
        if (nineSlice == null) {
          canvas.save();
          final fitted = applyBoxFit(
            style.backgroundImageFit.fit,
            Size(image.width.toDouble(), image.height.toDouble()),
            rect.size,
          );
          final imageRect =
              style.backgroundImageFit == ReaderDecorationImageFit.contain
              ? Alignment.center.inscribe(fitted.destination, rect)
              : rect;
          _clipImageCorners(canvas, imageRect, style.borderRadius);
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
          canvas.restore();
        } else {
          canvas.save();
          final anchor = imageAnchor ?? rect;
          final target = vertical
              ? Rect.fromLTWH(0, 0, anchor.height, anchor.width)
              : anchor;
          if (vertical) {
            canvas.translate(anchor.right, anchor.top);
            canvas.rotate(math.pi / 2);
          }
          _paintNineSlice(
            canvas,
            image,
            target,
            nineSlice,
            style.backgroundOpacity,
            style.borderRadius,
          );
          canvas.restore();
        }
      }
    }
    _paintBorders(canvas, rect, radius, style, inkMode);
    canvas.restore();
  }

  static void _paintNineSlice(
    Canvas canvas,
    ui.Image image,
    Rect text,
    ReaderDecorationNineSlice nineSlice,
    double opacity,
    double borderRadius,
  ) {
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final factor = nineSlice.scaleFor(text, size);
    final destination = nineSlice.imageRectFor(text, size);
    canvas.save();
    // 点九图含文字区以外的素材边角，圆角应裁切完整图案而非文字区。
    _clipImageCorners(canvas, destination, borderRadius);
    canvas.translate(destination.left, destination.top);
    canvas.scale(factor);
    canvas.drawImageNine(
      image,
      nineSlice.centerFor(size),
      Rect.fromLTWH(
        0,
        0,
        destination.width / factor,
        destination.height / factor,
      ),
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: opacity)
        ..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  static void _clipImageCorners(Canvas canvas, Rect rect, double radius) {
    if (radius <= 0) return;
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular(
          math.min(radius, math.min(rect.width, rect.height) / 2),
        ),
      ),
    );
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
