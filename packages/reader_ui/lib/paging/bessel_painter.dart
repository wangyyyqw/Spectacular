import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'bessel_geometry.dart';

/// 690 §3～5、700 §2 的页面合成；只消费准备好的位图。
class BesselPainter {
  BesselPainter({required this.paperColor})
    : _backPaperPaint = Paint()..color = paperColor,
      _backContentPaint = Paint()
        ..filterQuality = FilterQuality.low
        ..colorFilter = ColorFilter.matrix(_fadeMatrix(paperColor)),
      _mottlePaint = Paint()
        ..filterQuality = FilterQuality.low
        ..colorFilter = ColorFilter.mode(paperColor, BlendMode.modulate);

  final Color paperColor;
  final Paint _backPaperPaint;
  final Paint _backContentPaint;
  final Paint _mottlePaint;
  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;
  static ui.Image? _paperNoiseCache;
  static ui.ImageShader? _paperNoiseShaderCache;

  /// 纸背油墨只保留约四成反差，再向纸色靠拢，形成浅淡的透印效果。
  static const double _backInkFade = 0.44;

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
    // 先在纸背铺一层不透明纸色，网格抗锯齿缝隙也不会透出底页。
    canvas.drawRect(Offset.zero & g.size, _backPaperPaint);
    _cornerBackContent(canvas, g, back, image, rtl);
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
    _drawBackContent(canvas, mesh.content, mesh.mottle, image);
    _edgeBackShading(canvas, back);
    canvas.restore();
    mesh.content.dispose();
    mesh.mottle.dispose();
  }

  void _edgeBackShading(Canvas canvas, Path back) {
    // 只叠加黑色折痕阴影，不能再用半透明纸色覆盖镜像内容。
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

  void _cornerBackContent(
    Canvas canvas,
    BesselGeometry geometry,
    Path back,
    ui.Image image,
    bool rtl,
  ) {
    final bounds = back.getBounds().intersect(Offset.zero & geometry.size);
    if (bounds.isEmpty) return;
    final mesh = _cornerMesh(geometry, image, bounds, rtl);
    _drawBackContent(canvas, mesh.content, mesh.mottle, image);
    mesh.content.dispose();
    mesh.mottle.dispose();
  }

  /// 纸背内容先淡化，再叠加随网格一起形变的纸纤维斑驳。
  void _drawBackContent(
    Canvas canvas,
    ui.Vertices content,
    ui.Vertices mottle,
    ui.Image image,
  ) {
    final shader = _imageShader(image);
    _backContentPaint.shader = shader;
    canvas.drawVertices(content, BlendMode.srcOver, _backContentPaint);
    _backContentPaint.shader = null;
    shader.dispose();
    _mottlePaint.shader = _paperNoiseShader();
    canvas.drawVertices(mottle, BlendMode.srcOver, _mottlePaint);
    _mottlePaint.shader = null;
  }

  /// 只压缩油墨颜色反差，alpha 保持为 1，纸背本身始终不透明。
  static List<double> _fadeMatrix(Color paper) {
    const fade = _backInkFade;
    final red = paper.r * 255;
    final green = paper.g * 255;
    final blue = paper.b * 255;
    return <double>[
      fade,
      0,
      0,
      0,
      (1 - fade) * red,
      0,
      fade,
      0,
      0,
      (1 - fade) * green,
      0,
      0,
      fade,
      0,
      (1 - fade) * blue,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  ui.ImageShader _paperNoiseShader() {
    final cached = _paperNoiseShaderCache;
    if (cached != null) return cached;
    final matrix = Float64List(16)
      ..[0] = 1 / 3
      ..[5] = 1 / 3
      ..[10] = 1
      ..[15] = 1;
    return _paperNoiseShaderCache = ui.ImageShader(
      _paperNoise(),
      TileMode.mirror,
      TileMode.mirror,
      matrix,
      filterQuality: FilterQuality.low,
    );
  }

  static ui.Image _paperNoise() {
    final cached = _paperNoiseCache;
    if (cached != null) return cached;
    const size = 256;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final random = math.Random(0x5EED);
    for (var index = 0; index < 52; index++) {
      final center = Offset(
        random.nextDouble() * size,
        random.nextDouble() * size,
      );
      final radius = 16 + random.nextDouble() * 58;
      final color = index.isEven
          ? Color.fromRGBO(255, 255, 255, 0.12)
          : Color.fromRGBO(96, 96, 96, 0.055);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(center, radius, [
            color,
            color.withValues(alpha: 0),
          ]),
      );
    }
    for (var index = 0; index < 640; index++) {
      final point = Offset(
        random.nextDouble() * size,
        random.nextDouble() * size,
      );
      final color = index.isEven
          ? Color.fromRGBO(255, 255, 255, 0.02 + random.nextDouble() * 0.04)
          : Color.fromRGBO(96, 96, 96, 0.02 + random.nextDouble() * 0.045);
      if (index % 7 == 0) {
        final angle = random.nextDouble() * math.pi * 2;
        final length = 2 + random.nextDouble() * 7;
        final end = point + Offset(math.cos(angle), math.sin(angle)) * length;
        canvas.drawLine(
          point,
          end,
          Paint()
            ..color = color
            ..strokeWidth = 0.7,
        );
      } else {
        canvas.drawCircle(
          point,
          0.4 + random.nextDouble() * 1.2,
          Paint()..color = color,
        );
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
    picture.dispose();
    return _paperNoiseCache = image;
  }

  /// 角部纸背显示镜像页面，并沿折痕法线做非线性压缩模拟纸张弯曲。
  ({ui.Vertices content, ui.Vertices mottle}) _cornerMesh(
    BesselGeometry geometry,
    ui.Image image,
    Rect bounds,
    bool rtl,
  ) {
    const segments = 16;
    final axis = geometry.a - geometry.f;
    final length = axis.distance;
    final normal = length < 1e-6 ? const Offset(1, 0) : axis / length;
    final middle = (geometry.a + geometry.f) / 2;
    final reach = (geometry.a - middle).distance;
    final positions = <Offset>[];
    final texture = <Offset>[];
    final mottleTexture = <Offset>[];
    for (var row = 0; row <= segments; row++) {
      final y = bounds.top + bounds.height * row / segments;
      for (var column = 0; column <= segments; column++) {
        final point = Offset(bounds.left + bounds.width * column / segments, y);
        final delta = point - middle;
        final distance = delta.dx * normal.dx + delta.dy * normal.dy;
        var source = point - normal * (2 * distance);
        if (distance > 0 && reach > 0) {
          final t = (distance / reach).clamp(0.0, 1.0);
          // 折痕处压缩最强，纸角处回到镜像原位，避免采样越出页面。
          source -= normal * (reach * math.pow(t, 0.7) - distance).toDouble();
        }
        positions.add(point);
        mottleTexture.add(
          Offset(_foldedMottleX(point.dx, geometry.size.width), point.dy),
        );
        texture.add(
          Offset(
            (rtl ? geometry.size.width - source.dx : source.dx) *
                image.width /
                geometry.size.width,
            source.dy * image.height / geometry.size.height,
          ),
        );
      }
    }
    final indices = <int>[];
    for (var row = 0; row < segments; row++) {
      for (var column = 0; column < segments; column++) {
        final index = row * (segments + 1) + column;
        indices.addAll(<int>[
          index,
          index + 1,
          index + segments + 1,
          index + 1,
          index + segments + 2,
          index + segments + 1,
        ]);
      }
    }
    return (
      content: ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        textureCoordinates: texture,
        indices: indices,
      ),
      // 纹理按页面中线折叠，左右翻页和正反页渲染时斑驳保持严格镜像。
      mottle: ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        textureCoordinates: mottleTexture,
        indices: indices,
      ),
    );
  }

  ui.ImageShader _imageShader(ui.Image image) => ui.ImageShader(
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

  ({ui.Vertices content, ui.Vertices mottle}) _edgeMesh(
    BesselGeometry geometry,
    ui.Image image,
    bool rtl,
  ) {
    const segments = 32;
    final positions = <Offset>[];
    final texture = <Offset>[];
    final mottleTexture = <Offset>[];
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
      final mottleX = _foldedMottleX(screenX, geometry.size.width);
      mottleTexture
        ..add(Offset(mottleX, 0))
        ..add(Offset(mottleX, geometry.size.height));
      texture
        ..add(Offset(sourceX, 0))
        ..add(Offset(sourceX, image.height.toDouble()));
    }
    return (
      content: ui.Vertices(
        ui.VertexMode.triangleStrip,
        positions,
        textureCoordinates: texture,
      ),
      mottle: ui.Vertices(
        ui.VertexMode.triangleStrip,
        positions,
        textureCoordinates: mottleTexture,
      ),
    );
  }

  static double _foldedMottleX(double x, double width) {
    final clamped = x.clamp(0.0, width);
    return math.min(clamped, width - clamped);
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
