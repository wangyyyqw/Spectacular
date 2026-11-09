import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'curl3d_geometry.dart';

/// 3D 仿真翻页绘制：正面贴页面快照，纸背铺纸色，折痕处保留卷曲明暗。
///
/// 所有顶点共享固定的页面 UV；每帧只重新计算投影位置与明暗，
/// 因此拖动过程中图案不会在纸面上滑动。
class Curl3dPainter {
  Curl3dPainter({required this.paperColor});

  final Color paperColor;
  final Paint _frontPaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _backPaint = Paint();
  final Paint _shadowPaint = Paint();
  final Paint _edgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  final Paint _creasePaint = Paint();
  final Float64List _identity = Float64List(16)
    ..[0] = 1
    ..[5] = 1
    ..[10] = 1
    ..[15] = 1;

  void paint(
    Canvas canvas,
    Size size,
    ui.Image origin,
    ui.Image target, {
    required Curl3dGeometry geometry,
    required bool mirror,
  }) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (mirror) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    _drawImage(canvas, target, size, mirror);

    final radius = math.max(1.0, geometry.radius);
    _drawTextured(canvas, geometry.frontGrid(), origin, size, mirror, (sample) {
      final depth = -geometry.depthOf(sample.source);
      final t = (depth / (radius * 1.8)).clamp(0.0, 1.0);
      return 0.87 + 0.13 * (1 - (1 - t) * (1 - t));
    });
    _creaseShadow(canvas, geometry);
    _flapShadow(canvas, geometry);
    _drawTextured(
      canvas,
      geometry.flapFrontGrid(),
      origin,
      size,
      mirror,
      // 折痕处正对光线最亮，到卷顶转暗，与纸背的亮度接上。
      (sample) => 0.70 + 0.30 * sample.point.normalZ.clamp(0.0, 1.0),
    );
    _drawBack(canvas, geometry, geometry.flapBackGrid());
    _flapEdge(canvas, geometry);
    canvas.restore();
  }

  void _drawTextured(
    Canvas canvas,
    Curl3dGrid grid,
    ui.Image image,
    Size size,
    bool mirror,
    double Function(Curl3dSample sample) shade,
  ) {
    if (grid.width < 2 || grid.height < 2) return;
    final count = grid.samples.length;
    final positions = Float32List(count * 2);
    final texCoords = Float32List(count * 2);
    final colors = Int32List(count);
    var cursor = 0;
    for (var index = 0; index < count; index++) {
      final sample = grid.samples[index];
      final position = sample.point.position;
      positions[cursor] = position.dx;
      positions[cursor + 1] = position.dy;
      texCoords[cursor] = _textureX(
        sample.source.dx / size.width * image.width,
        image.width,
        mirror,
      );
      texCoords[cursor + 1] = _clampTexture(
        sample.source.dy / size.height * image.height,
        image.height,
      );
      colors[index] = _gray(shade(sample).clamp(0.0, 1.0));
      cursor += 2;
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texCoords,
      colors: colors,
      indices: _indices(grid.height, grid.width),
    );
    final shader = ui.ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      _identity,
      filterQuality: FilterQuality.low,
    );
    _frontPaint
      ..shader = shader
      ..color = const Color(0xFFFFFFFF);
    canvas.drawVertices(vertices, BlendMode.modulate, _frontPaint);
    _frontPaint.shader = null;
    shader.dispose();
  }

  void _drawBack(Canvas canvas, Curl3dGeometry geometry, Curl3dGrid grid) {
    if (grid.width < 2 || grid.height < 2) return;
    final count = grid.samples.length;
    final positions = Float32List(count * 2);
    final colors = Int32List(count);
    final depth = math.max(1.0, geometry.flapDepth);
    var cursor = 0;
    for (var index = 0; index < count; index++) {
      final sample = grid.samples[index];
      final position = sample.point.position;
      positions[cursor] = position.dx;
      positions[cursor + 1] = position.dy;
      // 纸背没有图案：圆柱段按法线做明暗，平铺段向纸角方向逐渐变亮。
      final ratio = (geometry.depthOf(sample.source) / depth).clamp(0.0, 1.0);
      final rollRatio = (geometry.rollLength / depth).clamp(0.0, 1.0);
      final flat = rollRatio >= 1
          ? 0.0
          : ((ratio - rollRatio) / (1 - rollRatio)).clamp(0.0, 1.0);
      final shade =
          0.70 - 0.16 * sample.point.normalZ.clamp(-1.0, 0.0) + 0.06 * flat;
      colors[index] = Color.from(
        alpha: 1,
        red: paperColor.r * shade,
        green: paperColor.g * shade,
        blue: paperColor.b * shade,
      ).toARGB32();
      cursor += 2;
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
      indices: _indices(grid.height, grid.width),
    );
    _backPaint.color = const Color(0xFFFFFFFF);
    canvas.drawVertices(vertices, BlendMode.modulate, _backPaint);
  }

  /// 折痕在正面留下的接触阴影，沿折痕方向铺开。
  void _creaseShadow(Canvas canvas, Curl3dGeometry geometry) {
    final center = geometry.creaseCenter + geometry.slide;
    final span = geometry.size.longestSide * 2;
    final width = geometry.radius * 2.2;
    final a = center - geometry.e * span - geometry.u * width;
    final b = center + geometry.e * span + geometry.u * width;
    final rect = Rect.fromPoints(a, b);
    // 折痕处最深，向两侧对称衰减；不能只朝正面衰减，否则纸背一侧会被整片压暗。
    _creasePaint.shader = ui.Gradient.linear(
      center - geometry.u * width,
      center + geometry.u * width,
      const [Color(0x00000000), Color(0x2E000000), Color(0x00000000)],
      const [0, 0.5, 1],
    );
    canvas.drawRect(rect, _creasePaint);
    _creasePaint.shader = null;
  }

  /// 翻起的纸背投在底页上的柔和阴影；向纸角方向偏移，光晕落在下一页上。
  void _flapShadow(Canvas canvas, Curl3dGeometry geometry) {
    final outline = geometry.flapOutline();
    if (outline.length < 3) return;
    final path = Path()..addPolygon(outline, true);
    _shadowPaint
      ..color = const Color(0x4D000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(
      path.shift(geometry.u * 12 + const Offset(0, 4)),
      _shadowPaint,
    );
    _shadowPaint.maskFilter = null;
  }

  /// 纸张厚度：沿纸背轮廓压一道细边，让折起的纸与下一页分出层次。
  void _flapEdge(Canvas canvas, Curl3dGeometry geometry) {
    final outline = geometry.flapOutline();
    if (outline.length < 3) return;
    _edgePaint
      ..color = const Color(0x33000000)
      ..strokeWidth = 1.4;
    canvas.drawPath(Path()..addPolygon(outline, true), _edgePaint);
  }

  Uint16List _indices(int rowCount, int columnCount) {
    final result = Uint16List((rowCount - 1) * (columnCount - 1) * 6);
    var cursor = 0;
    for (var row = 0; row < rowCount - 1; row++) {
      for (var column = 0; column < columnCount - 1; column++) {
        final topLeft = row * columnCount + column;
        final topRight = topLeft + 1;
        final bottomLeft = topLeft + columnCount;
        final bottomRight = bottomLeft + 1;
        result[cursor++] = topLeft;
        result[cursor++] = topRight;
        result[cursor++] = bottomLeft;
        result[cursor++] = topRight;
        result[cursor++] = bottomRight;
        result[cursor++] = bottomLeft;
      }
    }
    return result;
  }

  int _gray(double value) =>
      Color.from(alpha: 1, red: value, green: value, blue: value).toARGB32();

  double _textureX(double value, int width, bool mirror) {
    final clamped = _clampTexture(value, width);
    return mirror ? width - clamped : clamped;
  }

  double _clampTexture(double value, int extent) {
    final inset = math.min(1.5, extent / 2);
    return value.clamp(inset, extent - inset);
  }

  void _drawImage(Canvas canvas, ui.Image image, Size size, bool mirror) {
    canvas.save();
    if (mirror) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }
}
