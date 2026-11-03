import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'bessel_geometry.dart';
import 'bessel_painter.dart';
import 'page_turn_controller.dart';
import 'page_turn_mode.dart';

/// 每帧只绘制缓存位图和变换，正文不会重新布局。
class PageTurnPainter extends CustomPainter {
  PageTurnPainter(this.controller, {required this.paperColor})
    : super(repaint: controller);

  final PageTurnController controller;
  final Color paperColor;
  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = controller.originImage;
    final target = controller.targetImage;
    if (!controller.active || origin == null || target == null) return;
    final p = controller.progress;
    if (p <= 0 || p >= 1) {
      _image(canvas, p >= 1 ? target : origin, size);
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (controller.mode == PageTurnMode.simulationBessel) {
      _bessel(canvas, size, origin, target);
    } else if (controller.mode == PageTurnMode.slideHorizontal) {
      final sign = (controller.next != controller.rtl) ? -1 : 1;
      _translated(canvas, origin, size, sign * p * size.width);
      _translated(canvas, target, size, sign * (p - 1) * size.width);
    } else {
      _cover(canvas, size, origin, target);
    }
    canvas.restore();
  }

  void _bessel(Canvas canvas, Size size, ui.Image origin, ui.Image target) {
    final point = controller.point;
    if (point == null) return;
    final touch = controller.horizontal
        ? Offset(point.dx, size.height - 0.1)
        : point;
    final geometry = BesselGeometry.resolve(size, touch, top: controller.top);
    if (geometry == null) {
      _cover(canvas, size, origin, target);
      return;
    }
    try {
      BesselPainter(paperColor: paperColor).paint(
        canvas,
        geometry,
        controller.next ? target : origin,
        controller.next ? origin : target,
        rtl: controller.rtl,
      );
    } on StateError {
      _cover(canvas, size, origin, target);
    }
  }

  void _cover(Canvas canvas, Size size, ui.Image origin, ui.Image target) {
    final p = controller.progress;
    final exposure = controller.next ? p : 1 - p;
    final bottom = controller.next ? target : origin;
    if (controller.mode == PageTurnMode.coverStack) {
      canvas.save();
      final scale = 0.97 + exposure * 0.03;
      canvas.translate(
        size.width * (1 - scale) / 2,
        size.height * (1 - scale) / 2,
      );
      canvas.scale(scale);
      _image(canvas, bottom, size);
      canvas.restore();
    } else {
      _image(canvas, bottom, size);
    }
    final dx = -(controller.next ? p : 1 - p) * size.width;
    final physicalDx = controller.rtl ? -dx : dx;
    _translated(canvas, controller.next ? origin : target, size, physicalDx);
    _edgeShadow(canvas, size, physicalDx);
  }

  void _edgeShadow(Canvas canvas, Size size, double dx) {
    final edge = controller.rtl ? dx : dx + size.width;
    final rect = Rect.fromLTWH(
      controller.rtl ? edge - 24 : edge,
      0,
      24,
      size.height,
    );
    final gradient = LinearGradient(
      begin: controller.rtl ? Alignment.centerRight : Alignment.centerLeft,
      end: controller.rtl ? Alignment.centerLeft : Alignment.centerRight,
      colors: const [Color(0x30000000), Color(0x00000000)],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  void _translated(Canvas canvas, ui.Image image, Size size, double dx) {
    canvas.save();
    canvas.translate(dx, 0);
    _image(canvas, image, size);
    canvas.restore();
  }

  void _image(Canvas canvas, ui.Image image, Size size) => canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Offset.zero & size,
    _imagePaint,
  );

  @override
  bool shouldRepaint(PageTurnPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.paperColor != paperColor;
}
