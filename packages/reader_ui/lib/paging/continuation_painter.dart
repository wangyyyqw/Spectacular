import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'continuation_geometry.dart';

/// 接续只移动缓存正文的完整条带，纸底与边角信息由宿主固定绘制。
class ContinuationPainter {
  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;

  void paint(
    Canvas canvas,
    Size size, {
    required ui.Image origin,
    required ui.Image target,
    required ContinuationPageGeometry originGeometry,
    required ContinuationPageGeometry targetGeometry,
    required double progress,
    required double direction,
  }) {
    for (final part in originGeometry.parts) {
      final t = originGeometry.progressFor(
        part,
        progress,
        outgoing: true,
        direction: direction,
      );
      _part(canvas, size, origin, part.clip, -direction * t * size.width);
    }
    for (final part in targetGeometry.parts) {
      final t = targetGeometry.progressFor(
        part,
        progress,
        outgoing: false,
        direction: direction,
      );
      _part(canvas, size, target, part.clip, direction * (1 - t) * size.width);
    }
  }

  void _part(Canvas canvas, Size size, ui.Image image, Rect clip, double dx) {
    canvas.save();
    canvas.translate(dx, 0);
    canvas.clipRect(clip, doAntiAlias: false);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      _imagePaint,
    );
    canvas.restore();
  }
}
