import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'bessel_painter.dart';
import 'page_turn_controller.dart';
import 'page_turn_mode.dart';

/// 每帧只绘制缓存位图和变换，正文不会重新布局。
class PageTurnPainter extends CustomPainter {
  PageTurnPainter(this.controller, {required this.paperColor})
    : _besselPainter = BesselPainter(paperColor: paperColor),
      super(repaint: controller);

  final PageTurnController controller;
  final Color paperColor;
  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;
  final BesselPainter _besselPainter;

  /// 堆叠覆盖中下一页只跟随当前页移动的一小段，形成搓纸视差。
  static const _coverStackShift = 0.08;
  static const _coverStackMask = Color(0xFF808080);
  static const _coverStackMaskAlpha = 0.22;
  final Paint _coverStackMaskPaint = Paint();

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
    final geometry = controller.besselGeometry;
    if (geometry == null) {
      _besselFallback(canvas, size, origin, target);
      return;
    }
    final saveCount = canvas.getSaveCount();
    try {
      _besselPainter.paint(
        canvas,
        geometry,
        target,
        origin,
        rtl: !controller.fromRight,
      );
    } on StateError {
      canvas.restoreToCount(saveCount);
      _besselFallback(canvas, size, origin, target);
    }
  }

  void _besselFallback(
    Canvas canvas,
    Size size,
    ui.Image origin,
    ui.Image target,
  ) {
    _image(canvas, target, size);
    final dx =
        (controller.fromRight ? -1 : 1) * controller.progress * size.width;
    _translated(canvas, origin, size, dx);
    _edgeShadow(canvas, size, dx, fromRight: controller.fromRight);
  }

  void _cover(Canvas canvas, Size size, ui.Image origin, ui.Image target) {
    final p = controller.progress;
    if (controller.mode == PageTurnMode.coverStack) {
      final exit =
          (controller.next ? -1.0 : 1.0) * (controller.rtl ? -1.0 : 1.0);
      final originDx = exit * p * size.width;
      final targetDx = -exit * _coverStackShift * (1 - p) * size.width;
      canvas.save();
      canvas.translate(targetDx, 0);
      _image(canvas, target, size);
      _coverStackMaskPaint.color = _coverStackMask.withValues(
        alpha: _coverStackMaskAlpha * (1 - p),
      );
      canvas.drawRect(Offset.zero & size, _coverStackMaskPaint);
      canvas.restore();
      _translated(canvas, origin, size, originDx);
      _edgeShadow(
        canvas,
        size,
        originDx,
        fromRight: controller.next != controller.rtl,
      );
      return;
    }
    final bottom = controller.next ? target : origin;
    _image(canvas, bottom, size);
    final dx = -(controller.next ? p : 1 - p) * size.width;
    final physicalDx = controller.rtl ? -dx : dx;
    _translated(canvas, controller.next ? origin : target, size, physicalDx);
    _edgeShadow(canvas, size, physicalDx, fromRight: !controller.rtl);
  }

  void _edgeShadow(
    Canvas canvas,
    Size size,
    double dx, {
    required bool fromRight,
  }) {
    final edge = fromRight ? dx + size.width : dx;
    final rect = Rect.fromLTWH(
      fromRight ? edge : edge - 24,
      0,
      24,
      size.height,
    );
    final gradient = LinearGradient(
      begin: fromRight ? Alignment.centerLeft : Alignment.centerRight,
      end: fromRight ? Alignment.centerRight : Alignment.centerLeft,
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
