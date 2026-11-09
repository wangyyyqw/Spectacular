import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'curl3d_geometry.dart';
import 'duokan_curl_shader.dart';

/// 按多看的扫描顺序绘制投影、纸面和自阴影，纹理始终使用原纸面坐标。
class Curl3dPainter {
  Curl3dPainter({required this.paperColor, this.backgroundImage});

  final Color paperColor;
  final ui.Image? backgroundImage;
  final Paint _sheetPaint = Paint()..filterQuality = FilterQuality.none;
  final Paint _shadowPaint = Paint()..color = const Color(0xFFFFFFFF);

  void paint(
    Canvas canvas,
    ui.Image paper,
    ui.Image bottom, {
    required Curl3dGeometry geometry,
    required bool mirror,
  }) {
    final size = geometry.size;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _drawBottom(canvas, bottom, size);
    if (mirror) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    _drawShadow(canvas, geometry.dropShadow, geometry.size, paper);
    _drawPaper(canvas, paper, geometry, mirror);
    _drawShadow(canvas, geometry.selfShadow, geometry.size, paper);
    canvas.restore();
  }

  ui.FragmentShader _shader(Size size, ui.Image paper, bool mirror) {
    final program = DuokanCurlShader.program;
    if (program == null) throw StateError('3D 翻页着色器尚未加载');
    final shader = program.fragmentShader();
    final values = [
      size.width,
      size.height,
      paperColor.r,
      paperColor.g,
      paperColor.b,
      paperColor.a,
      mirror ? 1.0 : 0.0,
      backgroundImage == null ? 0.0 : 1.0,
      paper.width.toDouble(),
      paper.height.toDouble(),
      (backgroundImage ?? paper).width.toDouble(),
      (backgroundImage ?? paper).height.toDouble(),
    ];
    for (var index = 0; index < values.length; index++) {
      shader.setFloat(index, values[index]);
    }
    shader.setImageSampler(0, paper);
    shader.setImageSampler(1, backgroundImage ?? paper);
    return shader;
  }

  void _drawPaper(
    Canvas canvas,
    ui.Image paper,
    Curl3dGeometry geometry,
    bool mirror,
  ) {
    if (!geometry.active) {
      _drawBottom(canvas, paper, geometry.size, mirror: mirror);
      return;
    }
    final shader = _shader(geometry.size, paper, mirror);
    _sheetPaint.shader = shader;
    try {
      for (final strip in geometry.strips) {
        _setProjectionProfile(shader, geometry, strip.profile);
        // 片元按原纸面和截面范围判断覆盖，避免 MSAA 折边混入底页。
        canvas.drawRect(Offset.zero & geometry.size, _sheetPaint);
      }
    } finally {
      _sheetPaint.shader = null;
      shader.dispose();
    }
  }

  void _setProjectionProfile(
    ui.FragmentShader shader,
    Curl3dGeometry geometry,
    List<Curl3dProjectionStop> profile,
  ) {
    assert(profile.length <= DuokanCurlShader.profileCapacity);
    shader.setFloat(12, geometry.creaseCenter.dx);
    shader.setFloat(13, geometry.creaseCenter.dy);
    shader.setFloat(14, geometry.u.dx);
    shader.setFloat(15, geometry.u.dy);
    shader.setFloat(16, profile.length.toDouble());
    for (var index = 0; index < DuokanCurlShader.profileCapacity; index++) {
      final stop = index < profile.length ? profile[index] : profile.last;
      final offset = DuokanCurlShader.profileOffset + index * 4;
      shader.setFloat(offset, stop.x);
      shader.setFloat(offset + 1, stop.sourceX);
      shader.setFloat(offset + 2, stop.normalSin);
      shader.setFloat(offset + 3, stop.normalZ);
    }
  }

  void _drawShadow(
    Canvas canvas,
    List<Curl3dShadowSample> shadow,
    Size size,
    ui.Image paper,
  ) {
    if (shadow.length < 3) return;
    final shader = _shader(size, paper, false)..setFloat(16, -1);
    _shadowPaint.shader = shader;
    try {
      for (var index = 2; index < shadow.length; index++) {
        final triangle = shadow.sublist(index - 2, index + 1);
        final plane = _shadowAlphaPlane(triangle);
        if (plane == null) continue;
        for (var component = 0; component < plane.length; component++) {
          shader.setFloat(
            DuokanCurlShader.shadowPlaneOffset + component,
            plane[component],
          );
        }
        _setShadowEdges(shader, triangle);
        canvas.drawRect(_shadowBounds(triangle), _shadowPaint);
      }
    } finally {
      _shadowPaint.shader = null;
      shader.dispose();
    }
  }

  List<double>? _shadowAlphaPlane(List<Curl3dShadowSample> triangle) {
    final a = triangle[0];
    final b = triangle[1].position - a.position;
    final c = triangle[2].position - a.position;
    final area = b.dx * c.dy - b.dy * c.dx;
    if (area.abs() < 1e-8) return null;
    final alphaB = triangle[1].alpha - a.alpha;
    final alphaC = triangle[2].alpha - a.alpha;
    final dx = (alphaB * c.dy - alphaC * b.dy) / area;
    final dy = (b.dx * alphaC - c.dx * alphaB) / area;
    return [dx, dy, a.alpha - dx * a.position.dx - dy * a.position.dy];
  }

  void _setShadowEdges(
    ui.FragmentShader shader,
    List<Curl3dShadowSample> triangle,
  ) {
    final b = triangle[1].position - triangle[0].position;
    final c = triangle[2].position - triangle[0].position;
    final sign = (b.dx * c.dy - b.dy * c.dx).sign;
    for (var index = 0; index < 3; index++) {
      final a = triangle[index].position;
      final delta = (triangle[(index + 1) % 3].position - a) * sign;
      final values = [
        -delta.dy,
        delta.dx,
        delta.dy * a.dx - delta.dx * a.dy,
        // 半开公共边，每个像素只归属于一个三角形。
        delta.dy < 0 || (delta.dy == 0 && delta.dx > 0) ? 0.0 : 1.0,
      ];
      for (var component = 0; component < values.length; component++) {
        shader.setFloat(
          DuokanCurlShader.shadowEdgesOffset + index * 4 + component,
          values[component],
        );
      }
    }
  }

  Rect _shadowBounds(List<Curl3dShadowSample> triangle) {
    final xs = triangle.map((sample) => sample.position.dx);
    final ys = triangle.map((sample) => sample.position.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min).floorToDouble(),
      ys.reduce(math.min).floorToDouble(),
      xs.reduce(math.max).ceilToDouble(),
      ys.reduce(math.max).ceilToDouble(),
    );
  }

  void _drawBottom(
    Canvas canvas,
    ui.Image image,
    Size size, {
    bool mirror = false,
  }) {
    final shader = _shader(size, image, mirror);
    // 静态底页也来自 RGB565 快照，与卷纸共用相同的编码和采样。
    shader.setFloat(16, 1);
    shader.setFloat(DuokanCurlShader.profileOffset + 3, 1);
    _sheetPaint.shader = shader;
    try {
      canvas.drawRect(Offset.zero & size, _sheetPaint);
    } finally {
      _sheetPaint.shader = null;
      shader.dispose();
    }
  }
}
