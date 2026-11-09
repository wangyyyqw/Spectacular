import 'dart:math' as math;
import 'dart:ui';

/// 3D 仿真翻页的几何：固定页面 UV，只变形顶点。
///
/// 折痕是被掀起的一角 [grab] 与当前触点 [touch] 连线的中垂线附近，
/// 因此拖动时页角始终跟着手指走，折痕只会切开纸张的一角，不会横贯整页。
/// 折痕到页角之间的纸会在半径 [radius] 的半圆柱上卷起，绕过圆柱后平铺到
/// 正面，形成纸背；纸面长度守恒，图案不会被拉伸。
class Curl3dGeometry {
  Curl3dGeometry({
    required this.size,
    required this.grab,
    required this.touch,
    this.slide = Offset.zero,
  }) {
    final delta = grab - touch;
    final distance = delta.distance;
    hasFold = distance > 0.75;
    u = distance < 1e-6 ? const Offset(1, 0) : delta / distance;
    e = Offset(-u.dy, u.dx);
    radius = math.max(0.5, math.min(size.shortestSide * 0.08, distance * 0.26));
    rollLength = math.pi * radius;
    // 折痕向纸背方向内移，让页角正好落在触点上：
    // 弧长 = 折痕到触点的距离 + 半圆柱弧长。
    final inset = math.max(0.0, (distance - rollLength) / 2);
    creaseCenter = touch + u * inset;
    flapDepth = distance - inset;
    flapPolygon = _clipPage(keepPositive: true);
    flatPolygon = _clipPage(keepPositive: false);
  }

  final Size size;

  /// 被手指按住的页角，规范坐标；不会随后续拖动改变。
  final Offset grab;

  /// 当前触点，规范坐标；拖动时等价于“抓取点 + 位移”。
  final Offset touch;

  /// 收尾时整页滑出画面的位移。
  final Offset slide;

  /// 折痕法线，由折痕指向被掀起的页角一侧。
  late final Offset u;

  /// 折痕方向。
  late final Offset e;

  /// 折痕中点。
  late final Offset creaseCenter;

  /// 折痕到页角的纸面长度。
  late final double flapDepth;

  /// 折痕处的圆柱半径。
  late final double radius;

  /// 半圆柱的弧长。
  late final double rollLength;

  /// 是否已经能看见折角。
  late final bool hasFold;

  /// 页面被折痕切开后的可翻起部分（`depth >= 0`）。
  late final List<Offset> flapPolygon;

  /// 页面留在原处的部分（`depth <= 0`）。
  late final List<Offset> flatPolygon;

  bool get active => hasFold && flapDepth > 0.5 && flapPolygon.length >= 3;

  /// 页面坐标到折痕的有符号距离；正数在页角一侧。
  double depthOf(Offset source) {
    final delta = source - creaseCenter;
    return delta.dx * u.dx + delta.dy * u.dy;
  }

  /// 页面坐标沿折痕方向的坐标。
  double alongOf(Offset source) {
    final delta = source - creaseCenter;
    return delta.dx * e.dx + delta.dy * e.dy;
  }

  /// 页面坐标 [source] 的投影位置、深度与法线 z。
  Curl3dPoint pointAt(Offset source) {
    final delta = source - creaseCenter;
    final d = delta.dx * u.dx + delta.dy * u.dy;
    final t = delta.dx * e.dx + delta.dy * e.dy;
    if (d <= 0) {
      return Curl3dPoint(creaseCenter + u * d + e * t + slide, 0, 1);
    }
    if (d <= rollLength) {
      final angle = d / radius;
      return Curl3dPoint(
        creaseCenter + u * (radius * math.sin(angle)) + e * t + slide,
        radius * (1 - math.cos(angle)),
        math.cos(angle),
      );
    }
    // 绕过圆柱后纸面平铺在正面，长度按弧长守恒。
    final distance = d - rollLength;
    return Curl3dPoint(
      creaseCenter - u * distance + e * t + slide,
      2 * radius,
      -1,
    );
  }

  /// 折痕坐标 d 对应的页面坐标。
  Offset at(double d, double t) => creaseCenter + u * d + e * t;

  /// 未卷曲的正面：折痕以内的纸面，保持平面，不做任何压缩。
  Curl3dGrid frontGrid() => _gridOf(flatPolygon, 16, 8, _identityBand);

  /// 圆柱上仍朝向正面的窄条，保留一点卷边上的图案。
  Curl3dGrid flapFrontGrid() => _gridOf(flapPolygon, 12, 5, _rollFrontBand);

  /// 纸背：圆柱后半段与平铺段，长度按弧长守恒。
  Curl3dGrid flapBackGrid() => _gridOf(flapPolygon, 18, 12, _backBand);

  /// 纸背在屏幕上的轮廓，供投影阴影使用。
  List<Offset> flapOutline() {
    if (flapPolygon.length < 3) return const [];
    final outline = <Offset>[];
    const steps = 6;
    for (var index = 0; index < flapPolygon.length; index++) {
      final a = flapPolygon[index];
      final b = flapPolygon[(index + 1) % flapPolygon.length];
      for (var step = 0; step <= steps; step++) {
        outline.add(pointAt(Offset.lerp(a, b, step / steps)!).position);
      }
    }
    return outline;
  }

  /// 用折痕把页面矩形切成两半，网格只铺在真实的纸面上。
  List<Offset> _clipPage({required bool keepPositive}) {
    final corners = <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    final result = <Offset>[];
    for (var index = 0; index < corners.length; index++) {
      final a = corners[index];
      final b = corners[(index + 1) % corners.length];
      final da = depthOf(a);
      final db = depthOf(b);
      final insideA = keepPositive ? da >= 0 : da <= 0;
      final insideB = keepPositive ? db >= 0 : db <= 0;
      if (insideA) result.add(a);
      if (insideA != insideB) {
        result.add(Offset.lerp(a, b, da / (da - db))!);
      }
    }
    return result;
  }

  /// 行位置：均匀铺满，再加上多边形顶点，保证折角尖与纸边贴合。
  List<double> _rowsFor(List<Offset> polygon, int divisions) {
    if (polygon.isEmpty) return const [];
    final values = <double>[for (final point in polygon) alongOf(point)];
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    for (var index = 1; index < divisions; index++) {
      values.add(low + (high - low) * index / divisions);
    }
    values.sort();
    final result = <double>[];
    for (final value in values) {
      if (result.isEmpty || value - result.last > 0.01) result.add(value);
    }
    return result;
  }

  /// 一行纸面在折痕方向的区间。
  (double, double)? _depthRange(List<Offset> polygon, double t) {
    var from = double.infinity;
    var to = -double.infinity;
    for (var index = 0; index < polygon.length; index++) {
      final a = polygon[index];
      final b = polygon[(index + 1) % polygon.length];
      final ta = alongOf(a);
      final tb = alongOf(b);
      if ((t - ta) * (t - tb) > 0) continue;
      final span = tb - ta;
      final ratio = span.abs() < 1e-9 ? 0.0 : (t - ta) / span;
      final d = depthOf(a) + (depthOf(b) - depthOf(a)) * ratio;
      from = math.min(from, d);
      to = math.max(to, d);
    }
    return from > to ? null : (from, to);
  }

  Curl3dGrid _gridOf(
    List<Offset> polygon,
    int divisions,
    int columns,
    List<double> Function(double from, double to, int columns) band,
  ) {
    final rows = _rowsFor(polygon, divisions);
    final rowList = <List<Offset>>[];
    for (final t in rows) {
      final range = _depthRange(polygon, t);
      if (range == null) continue;
      final values = band(range.$1, range.$2, columns);
      rowList.add([for (final d in values) at(d, t)]);
    }
    return _grid(rowList);
  }

  List<double> _identityBand(double from, double to, int columns) =>
      _even(from, to, columns);

  List<double> _rollFrontBand(double from, double to, int columns) {
    final start = math.max(0.0, from);
    return _even(start, math.max(start, math.min(rollLength / 2, to)), columns);
  }

  /// 前半段在圆柱上，后半段平铺；两段都夹在真实纸面区间内。
  List<double> _backBand(double from, double to, int columns) {
    final start = math.max(from, math.min(rollLength / 2, to));
    final end = math.max(start, to);
    final half = columns ~/ 2;
    final values = <double>[start];
    final rollEnd = math.min(rollLength, end);
    _append(values, start, rollEnd, columns - half);
    _append(values, math.max(rollLength, start).clamp(start, end), end, half);
    return values;
  }

  List<double> _even(double from, double to, int count) {
    if (to <= from) return List<double>.filled(count + 1, from);
    return <double>[
      for (var index = 0; index <= count; index++)
        from + (to - from) * index / count,
    ];
  }

  void _append(List<double> values, double from, double to, int count) {
    if (to <= from) {
      for (var index = 0; index < count; index++) {
        values.add(from);
      }
      return;
    }
    for (var index = 1; index <= count; index++) {
      values.add(from + (to - from) * index / count);
    }
  }

  Curl3dGrid _grid(List<List<Offset>> rowList) {
    if (rowList.isEmpty) return const Curl3dGrid(0, []);
    final samples = <Curl3dSample>[];
    for (final row in rowList) {
      for (final source in row) {
        samples.add(Curl3dSample(source, pointAt(source)));
      }
    }
    return Curl3dGrid(rowList.first.length, samples);
  }
}

/// 一个顶点的投影结果；z 只用于明暗，不参与投影。
class Curl3dPoint {
  const Curl3dPoint(this.position, this.z, this.normalZ);

  final Offset position;
  final double z;
  final double normalZ;
}

/// 页面坐标与投影结果成对保存，纹理坐标只由页面坐标决定。
class Curl3dSample {
  const Curl3dSample(this.source, this.point);

  final Offset source;
  final Curl3dPoint point;
}

/// 行主序的顶点网格。
class Curl3dGrid {
  const Curl3dGrid(this.width, this.samples);

  final int width;
  final List<Curl3dSample> samples;

  int get height => width == 0 ? 0 : samples.length ~/ width;
}
