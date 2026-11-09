import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'bessel_geometry.dart';

/// 690 §3～5、700 §2 的页面合成；只消费准备好的位图。
class BesselPainter {
  BesselPainter({required this.paperColor})
    : _backPaperPaint = Paint()..color = paperColor,
      _backFadePaint = Paint()
        ..color = paperColor.withValues(alpha: 1 - _backInkContrast);

  final Color paperColor;
  final Paint _backPaperPaint;
  final Paint _backContentPaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _backFadePaint;
  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _shadowPaint = Paint();
  final Paint _edgeBackPaint = Paint();
  final Float64List _identityShaderMatrix = Float64List(16)
    ..[0] = 1
    ..[5] = 1
    ..[10] = 1
    ..[15] = 1;
  static const int _edgeSegments = 32;
  final Float32List _edgePositions = Float32List((_edgeSegments + 2) * 4);
  final Float32List _edgeTextureCoordinates = Float32List(
    (_edgeSegments + 2) * 4,
  );

  /// 纸背只保留少量透印反差，纸色覆盖独立于位图/网格的绘制路径。
  static const double _backInkContrast = 0.22;

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
    // 先在纸背铺一层不透明纸色，网格抗锯齿缝隙也不会透出底页。
    canvas.drawRect(Offset.zero & g.size, _backPaperPaint);
    _cornerBackContent(canvas, g, image, rtl);
    canvas.drawPath(back, _backFadePaint);
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
    canvas.save();
    canvas.clipPath(back);
    canvas.drawRect(Offset.zero & geometry.size, _backPaperPaint);
    _drawBackContent(canvas, mesh, image);
    canvas.drawPath(back, _backFadePaint);
    _edgeBackShading(canvas, back);
    canvas.restore();
    mesh.dispose();
  }

  void _edgeBackShading(Canvas canvas, Path back) {
    _edgeBackPaint.shader = const LinearGradient(
      colors: [
        Color(0x00000000),
        Color(0x00000000),
        Color(0x12000000),
        Color(0x45000000),
      ],
      stops: [0, 0.5, 0.78, 1],
    ).createShader(back.getBounds());
    // 透印淡化后再叠加折痕阴影，保留纸张弯曲的明暗层次。
    canvas.drawPath(back, _edgeBackPaint);
    _edgeBackPaint.shader = null;
  }

  void _cornerBackContent(
    Canvas canvas,
    BesselGeometry geometry,
    ui.Image image,
    bool rtl,
  ) {
    // 等比例反射保留文字尺寸，避免曲面采样在纸角附近放大字形。
    canvas.save();
    canvas.transform(geometry.reflection());
    _drawImage(canvas, image, geometry.size, rtl);
    canvas.restore();
  }

  /// 网格先绘制原始不透明内容，再统一覆盖纸色淡化。
  void _drawBackContent(Canvas canvas, ui.Vertices mesh, ui.Image image) {
    final shader = _imageShader(image);
    _backContentPaint.shader = shader;
    canvas.drawVertices(mesh, BlendMode.src, _backContentPaint);
    _backContentPaint.shader = null;
    shader.dispose();
  }

  ui.ImageShader _imageShader(ui.Image image) => ui.ImageShader(
    image,
    TileMode.clamp,
    TileMode.clamp,
    _identityShaderMatrix,
    filterQuality: FilterQuality.low,
  );

  ui.Vertices _edgeMesh(BesselGeometry geometry, ui.Image image, bool rtl) {
    final radius = geometry.d.dx - geometry.e.dx;
    var cursor = 0;
    for (var index = -1; index <= _edgeSegments; index++) {
      final angle = math.pi * (1 - index / (2 * _edgeSegments));
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
      _edgePositions[cursor] = screenX;
      _edgePositions[cursor + 1] = 0;
      _edgePositions[cursor + 2] = screenX;
      _edgePositions[cursor + 3] = geometry.size.height;
      _edgeTextureCoordinates[cursor] = sourceX;
      _edgeTextureCoordinates[cursor + 1] = 0;
      _edgeTextureCoordinates[cursor + 2] = sourceX;
      _edgeTextureCoordinates[cursor + 3] = image.height.toDouble();
      cursor += 4;
    }
    return ui.Vertices.raw(
      ui.VertexMode.triangleStrip,
      _edgePositions,
      textureCoordinates: _edgeTextureCoordinates,
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
    _shadowPaint.shader = gradient.createShader(rect);
    canvas.drawRect(rect, _shadowPaint);
    _shadowPaint.shader = null;
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
