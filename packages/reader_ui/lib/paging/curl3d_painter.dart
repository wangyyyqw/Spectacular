import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'curl3d_geometry.dart';
import 'duokan_curl_shader.dart';

/// 阅读视口持有的绘制资源；着色器首次使用时创建，随视口销毁。
class Curl3dPaintResources {
  ui.FragmentShader? _sheetShader, _shadowShader;
  bool _disposed = false;

  ui.FragmentShader get _sheet {
    assert(!_disposed);
    final program = DuokanCurlShader.program;
    if (program == null) throw StateError('3D 翻页着色器尚未加载');
    return _sheetShader ??= program.fragmentShader();
  }

  ui.FragmentShader get _shadow {
    assert(!_disposed);
    return _shadowShader ??= DuokanCurlShader.shadowProgram!.fragmentShader();
  }

  @visibleForTesting
  ui.FragmentShader? get debugSheetShader => _sheetShader;

  @visibleForTesting
  ui.FragmentShader? get debugShadowShader => _shadowShader;

  /// 快照窗口失效时解除采样器引用，防止远跳后仍占用旧页面纹理。
  void releaseImages() {
    _sheetShader?.dispose();
    _sheetShader = null;
  }

  void dispose() {
    releaseImages();
    _shadowShader?.dispose();
    _disposed = true;
  }
}

/// 按多看的扫描顺序绘制投影、纸面和自阴影，纹理始终使用原纸面坐标。
class Curl3dPainter {
  Curl3dPainter({
    required this.paperColor,
    this.backgroundImage,
    this.resources,
  });

  final Color paperColor;
  final ui.Image? backgroundImage;
  final Curl3dPaintResources? resources;
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
    final resources = this.resources ?? Curl3dPaintResources();
    canvas.save();
    try {
      canvas.clipRect(Offset.zero & size);
      _drawBottom(canvas, bottom, size, resources);
      if (mirror) {
        canvas.translate(size.width, 0);
        canvas.scale(-1, 1);
      }
      _drawShadow(canvas, geometry.dropShadow, size, resources);
      _drawPaper(canvas, paper, geometry, mirror, resources);
      _drawShadow(canvas, geometry.selfShadow, size, resources);
    } finally {
      canvas.restore();
      if (this.resources == null) resources.dispose();
    }
  }

  ui.FragmentShader _shader(
    Size size,
    ui.Image paper,
    bool mirror,
    Curl3dPaintResources resources,
  ) {
    final shader = resources._sheet;
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, paperColor.r);
    shader.setFloat(3, paperColor.g);
    shader.setFloat(4, paperColor.b);
    shader.setFloat(5, paperColor.a);
    shader.setFloat(6, mirror ? 1 : 0);
    shader.setFloat(7, backgroundImage == null ? 0 : 1);
    shader.setFloat(8, paper.width.toDouble());
    shader.setFloat(9, paper.height.toDouble());
    shader.setFloat(10, (backgroundImage ?? paper).width.toDouble());
    shader.setFloat(11, (backgroundImage ?? paper).height.toDouble());
    shader.setImageSampler(0, paper);
    shader.setImageSampler(1, backgroundImage ?? paper);
    return shader;
  }

  void _drawPaper(
    Canvas canvas,
    ui.Image paper,
    Curl3dGeometry geometry,
    bool mirror,
    Curl3dPaintResources resources,
  ) {
    if (!geometry.active) {
      _drawBottom(canvas, paper, geometry.size, resources, mirror: mirror);
      return;
    }
    final shader = _shader(geometry.size, paper, mirror, resources);
    _sheetPaint.shader = shader;
    try {
      for (final strip in geometry.strips) {
        _setProjectionProfile(shader, geometry, strip.profile);
        // 片元按原纸面和截面范围判断覆盖，避免 MSAA 折边混入底页。
        // 只裁掉投影包围盒以外的片元，绘制坐标与公共边插值保持不变。
        canvas.save();
        canvas.clipRect(strip.projectedBounds, doAntiAlias: false);
        canvas.drawRect(Offset.zero & geometry.size, _sheetPaint);
        canvas.restore();
      }
    } finally {
      _sheetPaint.shader = null;
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
    Curl3dPaintResources resources,
  ) {
    if (shadow.length < 3) return;
    const capacity = DuokanCurlShader.shadowTriangleCapacity;
    final shader = resources._shadow;
    _shadowPaint.shader = shader;
    try {
      for (var start = 2; start < shadow.length; start += capacity) {
        // 限制每批的三角形数与覆盖范围，避免移动端每个片元遍历整片阴影。
        // 仍统一用纸面矩形插值坐标，保持 Windows 公共边互补。
        for (var slot = 0; slot < capacity; slot++) {
          final index = start + slot;
          final valid =
              index < shadow.length &&
              _setShadowAlphaPlane(shader, shadow, index - 2, slot * 16);
          shader.setFloat(slot * 16 + 3, valid ? 1 : 0);
          if (valid) _setShadowEdges(shader, shadow, index - 2, slot * 16 + 4);
        }
        canvas.save();
        canvas.clipRect(
          _shadowBounds(
            shadow,
            start - 2,
            math.min(start + capacity, shadow.length),
          ).inflate(1),
          doAntiAlias: false,
        );
        canvas.drawRect(Offset.zero & size, _shadowPaint);
        canvas.restore();
      }
    } finally {
      _shadowPaint.shader = null;
    }
  }

  bool _setShadowAlphaPlane(
    ui.FragmentShader shader,
    List<Curl3dShadowSample> shadow,
    int start,
    int offset,
  ) {
    final a = shadow[start];
    final b = shadow[start + 1].position - a.position;
    final c = shadow[start + 2].position - a.position;
    final area = b.dx * c.dy - b.dy * c.dx;
    if (area.abs() < 1e-8) return false;
    final alphaB = shadow[start + 1].alpha - a.alpha;
    final alphaC = shadow[start + 2].alpha - a.alpha;
    final dx = (alphaB * c.dy - alphaC * b.dy) / area;
    final dy = (b.dx * alphaC - c.dx * alphaB) / area;
    shader.setFloat(offset, dx);
    shader.setFloat(offset + 1, dy);
    shader.setFloat(
      offset + 2,
      a.alpha - dx * a.position.dx - dy * a.position.dy,
    );
    return true;
  }

  void _setShadowEdges(
    ui.FragmentShader shader,
    List<Curl3dShadowSample> shadow,
    int start,
    int offset,
  ) {
    final b = shadow[start + 1].position - shadow[start].position;
    final c = shadow[start + 2].position - shadow[start].position;
    final sign = (b.dx * c.dy - b.dy * c.dx).sign;
    for (var index = 0; index < 3; index++) {
      var a = shadow[start + index].position;
      var b = shadow[start + (index + 1) % 3].position;
      // 公共边统一从下往上、水平时从左往右计算；相邻三角形使用完全
      // 相同的 float 系数，只在片元中反转符号，避免舍入后漏画或叠黑。
      final forward = a.dy > b.dy || (a.dy == b.dy && a.dx < b.dx);
      if (!forward) {
        final swap = a;
        a = b;
        b = swap;
      }
      final delta = b - a;
      final edgeOffset = offset + index * 4;
      shader.setFloat(edgeOffset, -delta.dy);
      shader.setFloat(edgeOffset + 1, delta.dx);
      shader.setFloat(edgeOffset + 2, delta.dy * a.dx - delta.dx * a.dy);
      // 正向包含公共边，反向排除，每个像素只归属于一个三角形。
      shader.setFloat(edgeOffset + 3, forward ? sign : -sign);
    }
  }

  Rect _shadowBounds(List<Curl3dShadowSample> shadow, int start, int end) {
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (var index = start; index < end; index++) {
      final position = shadow[index].position;
      left = math.min(left, position.dx);
      top = math.min(top, position.dy);
      right = math.max(right, position.dx);
      bottom = math.max(bottom, position.dy);
    }
    return Rect.fromLTRB(
      left.floorToDouble(),
      top.floorToDouble(),
      right.ceilToDouble(),
      bottom.ceilToDouble(),
    );
  }

  void _drawBottom(
    Canvas canvas,
    ui.Image image,
    Size size,
    Curl3dPaintResources resources, {
    bool mirror = false,
  }) {
    final shader = _shader(size, image, mirror, resources);
    // 静态底页也来自 RGB565 快照，与卷纸共用相同的编码和采样。
    shader.setFloat(16, 1);
    shader.setFloat(DuokanCurlShader.profileOffset + 3, 1);
    _sheetPaint.shader = shader;
    try {
      canvas.drawRect(Offset.zero & size, _sheetPaint);
    } finally {
      _sheetPaint.shader = null;
    }
  }
}
