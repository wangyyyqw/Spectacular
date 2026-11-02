import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'annotation.dart';

/// 标注样式的统一绘制入口。
abstract final class AnnotationStylePainter {
  /// 按样式绘制底色或下划线。
  static void paint(
    Canvas canvas,
    Rect rect, {
    required Color color,
    required ReaderAnnotationStyle style,
    double fillAlpha = 0.32,
    double strokeAlpha = 0.9,
    double strokeWidth = 1.8,
  }) {
    if (rect.isEmpty) {
      return;
    }
    if (style == ReaderAnnotationStyle.background) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = color.withValues(alpha: fillAlpha),
      );
      return;
    }
    final paint = Paint()
      ..color = color.withValues(alpha: strokeAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final baseline = rect.bottom - strokeWidth / 2;
    switch (style) {
      case ReaderAnnotationStyle.background:
        return;
      case ReaderAnnotationStyle.underline:
        canvas.drawLine(
          Offset(rect.left, baseline),
          Offset(rect.right, baseline),
          paint,
        );
      case ReaderAnnotationStyle.wavyUnderline:
        canvas.drawPath(_wavyPath(rect, baseline, strokeWidth), paint);
      case ReaderAnnotationStyle.dashedUnderline:
        canvas.drawPath(_dashedPath(rect, baseline), paint);
    }
  }

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
