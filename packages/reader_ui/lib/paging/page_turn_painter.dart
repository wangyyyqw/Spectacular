import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'bessel_painter.dart';
import 'continuation_geometry.dart';
import 'continuation_painter.dart';
import 'curl3d_painter.dart';
import 'page_turn_controller.dart';
import 'page_turn_mode.dart';

/// 每帧只绘制缓存位图和变换，正文不会重新布局。
class PageTurnPainter extends CustomPainter {
  PageTurnPainter(
    this.controller, {
    required this.paperColor,
    this.backgroundImage,
    this.pageInsets = EdgeInsets.zero,
    this.curl3dResources,
  }) : _besselPainter = BesselPainter(paperColor: paperColor),
       super(repaint: controller);

  final PageTurnController controller;
  final Color paperColor;
  final ui.Image? backgroundImage;
  final EdgeInsets pageInsets;
  final Curl3dPaintResources? curl3dResources;
  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;
  final BesselPainter _besselPainter;
  late final _curl3dPainter = Curl3dPainter(
    paperColor: paperColor,
    backgroundImage: backgroundImage,
    resources: curl3dResources,
  );
  final _continuationPainter = ContinuationPainter();
  Object? _continuationPages;
  ContinuationPageGeometry? _originContinuation;
  ContinuationPageGeometry? _targetContinuation;

  /// 堆叠覆盖中下一页只跟随当前页移动的一小段，形成搓纸视差。
  static const _coverStackShift = 0.08;
  static const _coverStackMask = Color(0xFF808080);
  static const _coverStackMaskAlpha = 0.22;
  final Paint _coverStackMaskPaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final origin = controller.originImage;
    // 目标未就绪时轻抬原页，不能因跨章加载阻断手势反馈。
    final target = controller.targetImage ?? origin;
    if (!controller.active || origin == null || target == null) return;
    if (controller.mode == PageTurnMode.continuation) {
      _continuation(canvas, size, origin, target);
      return;
    }
    _paintTurn(canvas, size, origin, target);
  }

  void _continuation(
    Canvas canvas,
    Size size,
    ui.Image origin,
    ui.Image target,
  ) {
    final sheet = Offset.zero & size;
    canvas.save();
    canvas.clipRect(sheet);
    canvas.drawRect(sheet, Paint()..color = paperColor);
    if (backgroundImage case final background?) {
      _image(canvas, background, size);
    }
    final progress = controller.progress;
    // 冷目标就绪前保持原正文，不能把原文再当成下一页接入。
    if (progress <= 0 ||
        controller.targetImage == null ||
        controller.targetOpacity <= 0) {
      _image(canvas, origin, size);
      canvas.restore();
      return;
    }
    if (progress >= 1) {
      _targetImage(canvas, size, origin, target);
      canvas.restore();
      return;
    }
    final originPage = controller.session.page;
    final targetPage = controller.turn?.target.content;
    final key = (originPage, targetPage, size, pageInsets);
    if (_continuationPages != key) {
      _continuationPages = key;
      _originContinuation = ContinuationPageGeometry.resolve(
        originPage,
        size,
        pageInsets: pageInsets,
      );
      _targetContinuation = ContinuationPageGeometry.resolve(
        targetPage,
        size,
        pageInsets: pageInsets,
      );
    }
    _continuationPainter.paint(
      canvas,
      size,
      origin: origin,
      target: target,
      originGeometry: _originContinuation!,
      targetGeometry: _targetContinuation!,
      progress: progress,
      direction: controller.next != controller.rtl ? 1 : -1,
    );
    canvas.restore();
  }

  void _paintTurn(Canvas canvas, Size size, ui.Image origin, ui.Image target) {
    final p = controller.progress;
    final curl3d = controller.mode == PageTurnMode.simulation3d;
    // 3D 的可见程度由折角几何决定，不看进度。
    if (!curl3d && (p <= 0 || p >= 1)) {
      if (p >= 1) {
        _targetImage(canvas, size, origin, target);
      } else {
        _image(canvas, origin, size);
      }
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (controller.mode == PageTurnMode.simulationBessel) {
      _bessel(canvas, size, origin, target);
    } else if (curl3d) {
      _curl3d(canvas, size, origin, target);
    } else if (controller.mode == PageTurnMode.slideHorizontal) {
      final sign = (controller.next != controller.rtl) ? -1 : 1;
      _translated(canvas, origin, size, sign * p * size.width);
      _targetImage(
        canvas,
        size,
        origin,
        target,
        dx: sign * (p - 1) * size.width,
      );
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
      _besselPainter.bottomOpacity = controller.targetOpacity;
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

  void _curl3d(Canvas canvas, Size size, ui.Image origin, ui.Image target) {
    final geometry = controller.curl3dGeometry;
    if (geometry == null) {
      _image(canvas, origin, size);
      return;
    }
    // 前后翻页都卷走当前页，按物理起卷侧镜像几何，底页为目标页。
    _curl3dPainter.paint(
      canvas,
      origin,
      target,
      geometry: geometry,
      mirror: !controller.fromRight,
      bottomOpacity: controller.targetOpacity,
    );
  }

  void _besselFallback(
    Canvas canvas,
    Size size,
    ui.Image origin,
    ui.Image target,
  ) {
    _targetImage(canvas, size, origin, target);
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
      _targetImage(canvas, size, origin, target);
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
    if (controller.next) {
      _targetImage(canvas, size, origin, target);
    } else {
      _image(canvas, origin, size);
    }
    final dx = -(controller.next ? p : 1 - p) * size.width;
    final physicalDx = controller.rtl ? -dx : dx;
    if (controller.next) {
      _translated(canvas, origin, size, physicalDx);
    } else {
      _targetImage(canvas, size, origin, target, dx: physicalDx);
    }
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

  void _targetImage(
    Canvas canvas,
    Size size,
    ui.Image origin,
    ui.Image target, {
    double dx = 0,
  }) {
    canvas.save();
    canvas.translate(dx, 0);
    final opacity = controller.targetOpacity;
    if (opacity < 1) _image(canvas, origin, size);
    if (opacity > 0) {
      _imagePaint.color = Color.fromRGBO(255, 255, 255, opacity);
      _image(canvas, target, size);
      _imagePaint.color = const Color(0xFFFFFFFF);
    }
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
      oldDelegate.paperColor != paperColor ||
      oldDelegate.backgroundImage != backgroundImage ||
      oldDelegate.pageInsets != pageInsets ||
      oldDelegate.curl3dResources != curl3dResources;
}
