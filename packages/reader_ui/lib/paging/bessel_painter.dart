import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'bessel_geometry.dart';

/// 690 §3～5、700 §2 的页面合成；只消费准备好的位图。
class BesselPainter {
  BesselPainter({required this.paperColor})
    : _cornerBackPaint = Paint()..color = paperColor,
      _edgeBackPaint = Paint()..color = paperColor.withAlpha(145);

  final Color paperColor;
  final Paint _cornerBackPaint;
  final Paint _edgeBackPaint;
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
    // 正反面共用折痕边缘，先铺整页底图，避免抗锯齿缝隙透出底页。
    // 不能铺固定纸色，否则深色图片页会在折痕处露出亮色尖角。
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.union, front, back));
    _drawImage(canvas, paper, geometry.size, rtl);
    canvas.restore();
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

  double _shadowOpacity(BesselGeometry g) => g.horizontal
      ? 1
      : ((g.a.dx + g.size.width) / g.size.width).clamp(0.0, 1.0);

  void _bottomShadow(Canvas canvas, BesselGeometry g) {
    if (g.horizontal) {
      _edgeBottomShadow(canvas, g);
      return;
    }
    final width = (g.a - g.f).distance / 4;
    final length = _length(g);
    // DI 是可见折痕；投影覆盖曲面边缘，并在折痕外侧衰减。
    _shadow(
      canvas,
      Rect.fromLTRB(-width, -length, width / 2, length),
      g.d,
      _foldAngle(g),
      _gradient(g, 0, 0.42),
    );
  }

  void _frontShadows(Canvas canvas, BesselGeometry g, Path front) {
    if (g.horizontal) {
      _edgeContactShadow(canvas, g);
      return;
    }
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
      _gradient(g, g.top ? 0.1 : 0, g.top ? 0 : 0.1),
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
      _gradient(g, g.top ? 0.1 : 0, g.top ? 0 : 0.1, vertical: true),
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
    if (g.horizontal) {
      _edgeBack(canvas, g, back, image, rtl);
      return;
    }
    canvas.save();
    canvas.clipPath(back);
    // 角部纸背是不透光纸张，不能透出镜像正文或目标页。
    canvas.drawRect(Offset.zero & g.size, _cornerBackPaint);
    final width = (g.a - g.f).distance / 8;
    final length = _length(g);
    // 曲面宽度对应贝塞尔中点到 CJ 的距离，纸背在折痕处最暗。
    _shadow(
      canvas,
      Rect.fromLTRB(0, -length, width, length),
      g.d,
      _foldAngle(g),
      _gradient(g, 0.18, 0),
    );
    canvas.restore();
  }

  void _edgeBottomShadow(Canvas canvas, BesselGeometry geometry) {
    final width = geometry.d.dx - geometry.e.dx;
    _shadow(
      canvas,
      Rect.fromLTWH(0, 0, width, geometry.size.height),
      geometry.d,
      0,
      const LinearGradient(
        colors: [Color(0x45000000), Color(0x1A000000), Color(0x00000000)],
        stops: [0, 0.3, 1],
      ),
    );
  }

  void _edgeContactShadow(Canvas canvas, BesselGeometry geometry) {
    final width = math.min(3.0, (geometry.d.dx - geometry.a.dx) / 12);
    _shadow(
      canvas,
      Rect.fromLTRB(-width, 0, 0, geometry.size.height),
      Offset(geometry.a.dx, 0),
      0,
      _gradient(geometry, 0, 0.09),
    );
  }

  void _edgeBack(
    Canvas canvas,
    BesselGeometry geometry,
    Path back,
    ui.Image image,
    bool rtl,
  ) {
    final mesh = _edgeMesh(geometry, image, rtl);
    final shader = ui.ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      Float64List(16)
        ..[0] = 1
        ..[5] = 1
        ..[10] = 1
        ..[15] = 1,
      filterQuality: FilterQuality.low,
    );
    canvas.save();
    canvas.clipPath(back);
    canvas.drawVertices(mesh, BlendMode.src, Paint()..shader = shader);
    _edgeBackShading(canvas, back);
    canvas.restore();
    shader.dispose();
    mesh.dispose();
  }

  void _edgeBackShading(Canvas canvas, Path back) {
    canvas.drawPath(back, _edgeBackPaint);
    canvas.drawPath(
      back,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x00000000),
            Color(0x00000000),
            Color(0x12000000),
            Color(0x45000000),
          ],
          stops: [0, 0.5, 0.78, 1],
        ).createShader(back.getBounds()),
    );
  }

  ui.Vertices _edgeMesh(BesselGeometry geometry, ui.Image image, bool rtl) {
    const segments = 32;
    final positions = <Offset>[];
    final texture = <Offset>[];
    final radius = geometry.d.dx - geometry.e.dx;
    for (var index = -1; index <= segments; index++) {
      final angle = math.pi * (1 - index / (2 * segments));
      final screenX = index < 0
          ? geometry.a.dx
          : geometry.e.dx + radius * math.sin(angle);
      final source = index < 0
          ? geometry.size.width
          : geometry.e.dx + radius * angle;
      final sourceX =
          (rtl ? geometry.size.width - source : source) *
          image.width /
          geometry.size.width;
      positions
        ..add(Offset(screenX, 0))
        ..add(Offset(screenX, geometry.size.height));
      texture
        ..add(Offset(sourceX, 0))
        ..add(Offset(sourceX, image.height.toDouble()));
    }
    return ui.Vertices(
      ui.VertexMode.triangleStrip,
      positions,
      textureCoordinates: texture,
    );
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
    BesselGeometry g,
    double startAlpha,
    double endAlpha, {
    bool vertical = false,
  }) {
    final opacity = _shadowOpacity(g);
    return LinearGradient(
      begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
      end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
      colors: [
        Color.from(alpha: startAlpha * opacity, red: 0, green: 0, blue: 0),
        Color.from(alpha: endAlpha * opacity, red: 0, green: 0, blue: 0),
      ],
    );
  }
}
