import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'bessel_geometry.dart';

/// 690 §3～5、700 §2 的页面合成；只消费准备好的位图。
class BesselPainter {
  BesselPainter({required this.paperColor});

  final Color paperColor;
  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;

  void paint(
    Canvas canvas,
    BesselGeometry geometry,
    ui.Image bottom,
    ui.Image paper, {
    required bool rtl,
  }) {
    canvas.save();
    canvas.clipRect(Offset.zero & geometry.size);
    // RTL 先镜像规范几何；页图再用同一镜像抵消，避免文字反向。
    if (rtl) {
      canvas.translate(geometry.size.width, 0);
      canvas.scale(-1, 1);
    }
    _drawImage(canvas, bottom, geometry.size, rtl);
    final front = geometry.frontPath();
    final back = geometry.backPath(front);
    _bottomShadow(canvas, geometry);
    // 正反面共用折痕边缘，先铺整页纸底，避免抗锯齿缝隙透出底页。
    canvas.drawPath(
      Path.combine(PathOperation.union, front, back),
      Paint()..color = paperColor,
    );
    canvas.save();
    canvas.clipPath(front);
    _drawImage(canvas, paper, geometry.size, rtl);
    canvas.restore();
    _frontShadows(canvas, geometry, front);
    _back(canvas, geometry, back, paper, rtl);
    canvas.restore();
  }

  void _drawImage(Canvas canvas, ui.Image image, Size size, bool mirrored) {
    canvas.save();
    if (mirrored) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      _imagePaint,
    );
    canvas.restore();
  }

  double _length(BesselGeometry g) => g.size.longestSide == 0
      ? 0
      : math.sqrt(g.size.width * g.size.width + g.size.height * g.size.height);

  double _foldAngle(BesselGeometry g) =>
      math.atan2(g.a.dy - g.f.dy, g.a.dx - g.f.dx);

  void _bottomShadow(Canvas canvas, BesselGeometry g) {
    final width = (g.a - g.f).distance / 4;
    final length = _length(g);
    // DI 是可见折痕；投影覆盖曲面边缘，并在折痕外侧衰减。
    _shadow(
      canvas,
      Rect.fromLTRB(-width, -length, width / 2, length),
      g.d,
      _foldAngle(g),
      _gradient(0, 0.42),
    );
  }

  void _frontShadows(Canvas canvas, BesselGeometry g, Path front) {
    if (g.horizontal) return;
    final p = g.shadowPoint;
    final eClip = Path.combine(
      PathOperation.intersect,
      BesselGeometry.polygon([p, g.a, g.e, g.c]),
      front,
    );
    final length = _length(g);
    canvas.save();
    canvas.clipPath(eClip);
    _shadow(
      canvas,
      g.top
          ? Rect.fromLTRB(0, -length, 5, 0)
          : Rect.fromLTRB(-5, -length, 1, 0),
      g.e,
      math.atan2(g.a.dx - g.e.dx, g.e.dy - g.a.dy),
      _gradient(g.top ? 0.1 : 0, g.top ? 0 : 0.1),
    );
    canvas.restore();
    _frontHShadow(canvas, g, front);
  }

  void _frontHShadow(Canvas canvas, BesselGeometry g, Path front) {
    final hClip = Path.combine(
      PathOperation.intersect,
      BesselGeometry.polygon([g.shadowPoint, g.a, g.h, g.j]),
      front,
    );
    final length = _length(g);
    final adjustedY = g.h.dy < 0 ? g.h.dy - g.size.height : g.h.dy;
    final r = math.sqrt(g.h.dx * g.h.dx + adjustedY * adjustedY);
    final left = r > length ? -5 - r : -length;
    final right = r > length ? length - r : 0.0;
    canvas.save();
    canvas.clipPath(hClip);
    _shadow(
      canvas,
      g.top
          ? Rect.fromLTRB(left, 0, right, 5)
          : Rect.fromLTRB(left, -5, right, 1),
      g.h,
      math.atan2(g.h.dy - g.a.dy, g.h.dx - g.a.dx),
      _gradient(g.top ? 0.1 : 0, g.top ? 0 : 0.1, vertical: true),
    );
    canvas.restore();
  }

  void _back(
    Canvas canvas,
    BesselGeometry g,
    Path back,
    ui.Image image,
    bool rtl,
  ) {
    if (back.getBounds().isEmpty) return;
    canvas.save();
    canvas.clipPath(back);
    canvas.save();
    canvas.transform(g.reflection());
    _drawImage(canvas, image, g.size, rtl);
    canvas.restore();
    canvas.drawRect(
      Offset.zero & g.size,
      Paint()..color = paperColor.withAlpha(128),
    );
    final width = (g.a - g.f).distance / 8;
    final length = _length(g);
    // 曲面宽度对应贝塞尔中点到 CJ 的距离，纸背在折痕处最暗。
    _shadow(
      canvas,
      Rect.fromLTRB(0, -length, width, length),
      g.d,
      _foldAngle(g),
      _gradient(0.18, 0),
    );
    canvas.restore();
  }

  void _shadow(
    Canvas canvas,
    Rect rect,
    Offset origin,
    double angle,
    Gradient gradient,
  ) {
    if (rect.isEmpty || !angle.isFinite) return;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(angle);
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
    canvas.restore();
  }

  LinearGradient _gradient(
    double startAlpha,
    double endAlpha, {
    bool vertical = false,
  }) => LinearGradient(
    begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
    end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
    colors: [
      Color.from(alpha: startAlpha, red: 0, green: 0, blue: 0),
      Color.from(alpha: endAlpha, red: 0, green: 0, blue: 0),
    ],
  );
}
