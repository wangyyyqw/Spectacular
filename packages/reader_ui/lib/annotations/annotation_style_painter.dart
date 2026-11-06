import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'annotation.dart';

/// 标注样式的统一绘制入口。
abstract final class AnnotationStylePainter {
  /// 按样式绘制阅读标记；文字染色由正文绘制管线处理。
  static void paint(
    Canvas canvas,
    Rect rect, {
    required Color color,
    required ReaderAnnotationStyle style,
    double fillAlpha = 0.32,
    double strokeAlpha = 0.9,
    double strokeWidth = 1.8,
    double? baseline,
    bool vertical = false,
  }) {
    if (rect.isEmpty || style == ReaderAnnotationStyle.tint) return;
    if (vertical) {
      canvas.save();
      canvas.translate(rect.right, rect.top);
      canvas.rotate(math.pi / 2);
      paint(
        canvas,
        Rect.fromLTWH(0, 0, rect.height, rect.width),
        color: color,
        style: style,
        fillAlpha: fillAlpha,
        strokeAlpha: strokeAlpha,
        strokeWidth: strokeWidth,
      );
      canvas.restore();
      return;
    }
    if (style == ReaderAnnotationStyle.background ||
        style == ReaderAnnotationStyle.halfBackground) {
      final fill = style == ReaderAnnotationStyle.halfBackground
          ? Rect.fromLTRB(rect.left, rect.center.dy, rect.right, rect.bottom)
          : rect;
      canvas.drawRect(
        fill,
        Paint()..color = color.withValues(alpha: fillAlpha),
      );
      return;
    }
    _paintLines(
      canvas,
      rect,
      color: color,
      style: style,
      opacity: strokeAlpha,
      strokeWidth: strokeWidth,
      baseline: baseline,
    );
  }

  static void _paintLines(
    Canvas canvas,
    Rect rect, {
    required Color color,
    required ReaderAnnotationStyle style,
    required double opacity,
    required double strokeWidth,
    double? baseline,
  }) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final lineY = baseline ?? rect.bottom - strokeWidth / 2;
    switch (style) {
      case ReaderAnnotationStyle.background:
      case ReaderAnnotationStyle.halfBackground:
      case ReaderAnnotationStyle.tint:
        return;
      case ReaderAnnotationStyle.underline:
        _line(canvas, rect, lineY, paint);
      case ReaderAnnotationStyle.wavyUnderline:
        canvas.drawPath(_wavyPath(rect, lineY, strokeWidth), paint);
      case ReaderAnnotationStyle.dashedUnderline:
        canvas.drawPath(_dashedPath(rect, lineY), paint);
      case ReaderAnnotationStyle.doubleUnderline:
        final gap = math.max(2.0, strokeWidth * 1.6);
        _line(canvas, rect, lineY - gap, paint);
        _line(canvas, rect, lineY, paint);
      case ReaderAnnotationStyle.dottedUnderline:
        for (
          var position = rect.left;
          position <= rect.right;
          position += strokeWidth * 2.5
        ) {
          canvas.drawCircle(
            Offset(position, lineY),
            strokeWidth / 2,
            Paint()..color = paint.color,
          );
        }
      case ReaderAnnotationStyle.lineThrough:
        _line(canvas, rect, rect.center.dy, paint);
    }
  }

  static void _line(Canvas canvas, Rect rect, double height, Paint paint) =>
      canvas.drawLine(
        Offset(rect.left, height),
        Offset(rect.right, height),
        paint,
      );

  static Path _wavyPath(Rect rect, double baseline, double strokeWidth) {
    final amplitude = math.max(1.1, strokeWidth * 0.65);
    const wavelength = 6.0;
    final path = Path();
    for (var x = rect.left; x <= rect.right; x += 1) {
      final y =
          baseline +
          math.sin((x - rect.left) / wavelength * math.pi * 2) * amplitude;
      if (x == rect.left) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  static Path _dashedPath(Rect rect, double baseline) {
    const dash = 5.0;
    const gap = 3.0;
    final path = Path();
    for (var x = rect.left; x < rect.right; x += dash + gap) {
      path.moveTo(x, baseline);
      path.lineTo(math.min(x + dash, rect.right), baseline);
    }
    return path;
  }
}
