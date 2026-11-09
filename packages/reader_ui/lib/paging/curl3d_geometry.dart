import 'dart:math' as math;
import 'dart:ui';

/// 多看圆柱卷页的正交投影，页面坐标始终作为固定纹理坐标。
///
/// 输入采用从左到右、y 向下的页面坐标。前进从右缘起手，后退从左侧
/// 虚拟页的 -width 起手；镜像及实际翻页方向由调用方处理。
class Curl3dGeometry {
  Curl3dGeometry({
    required this.size,
    required this.grab,
    required this.touch,
  }) {
    final state = _curlState();
    radius = state.radius;
    creaseCenter = state.center;
    active = state.active;
    // 保留原生 acos 旋转，水平拖动时的边界角点也按原扫描顺序插入。
    final angle = math.acos(state.direction.dx.clamp(-1.0, 1.0));
    final rotation = state.direction.dy < 0 ? -angle : angle;
    u = active ? Offset(math.cos(rotation), math.sin(rotation)) : Offset.zero;
    e = Offset(u.dy, -u.dx);
  }

  static const _curlSplits = 20;

  final Size size;

  /// 固定起手点：前进 x 为 width，后退 x 为 -width。
  final Offset grab;

  /// 当前实际指针位置，允许越过页面边界。
  final Offset touch;

  /// 沿当前指针减去有效起手点的卷曲方向，已包含页边约束。
  late final Offset u;

  /// 折痕方向，保留原生 GL 网格的扫描上下顺序。
  late final Offset e;

  late final Offset creaseCenter;
  late final double radius;
  late final bool active;

  /// 原生连续三角形带；source 是原页面的像素纹理坐标。
  late final List<Curl3dSample> mesh = List.unmodifiable(_buildMesh());

  /// 在投影最远处拆开原 strip，直接在屏幕片元内反查纸面坐标及法线。
  late final List<Curl3dStrip> strips = _buildStrips();

  /// 半影位移已合并，alpha 已包含原片元着色器的 0.5 系数。
  late final List<Curl3dShadowSample> dropShadow = List.unmodifiable(
    _buildShadow(self: false),
  );

  late final List<Curl3dShadowSample> selfShadow = List.unmodifiable(
    _buildShadow(self: true),
  );

  /// 任意页面坐标的投影位置、高度与完整单位法线。
  Curl3dPoint pointAt(Offset source) {
    if (!active) return _flatPoint(source);
    final vertex = _localVertex(source);
    final band = vertex.x >= 0
        ? _CurlBand.flat
        : radius == 0 || vertex.x <= -math.pi * radius
        ? _CurlBand.back
        : _CurlBand.cylinder;
    return _project(vertex, band);
  }

  _CurlState _curlState() {
    final maximum = size.width / 6;
    final direction = touch - _effectiveAnchor();
    final distance = direction.distance;
    final arc = math.pi * maximum;
    final shift = distance >= arc
        ? -(distance - arc) / 2
        : math.sqrt(arc * distance) - distance;
    var center = touch + direction * (distance == 0 ? 0 : shift / distance);
    var currentRadius = maximum;
    if (center.dx >= size.width || distance == 0) {
      return _CurlState(maximum, center, Offset.zero, false);
    }
    if (center.dx < 0) {
      currentRadius = math.max(maximum + center.dx * 1.05 * 2 / math.pi, 0.0);
      center = Offset(0, center.dy);
    }
    final constrained = _constrainDirection(center, direction);
    final length = constrained.distance;
    return _CurlState(
      currentRadius,
      center,
      length == 0 ? Offset.zero : constrained / length,
      length != 0,
    );
  }

  Offset _effectiveAnchor() {
    if (grab.dx >= 0) return grab;
    final span = touch.dx - grab.dx;
    final y = span == 0
        ? grab.dy
        : touch.dy + (size.width - touch.dx) * (touch.dy - grab.dy) / span;
    return Offset(size.width, y);
  }

  Offset _constrainDirection(Offset center, Offset direction) {
    if (direction.dy == 0) return direction;
    final hitY = center.dy + center.dx * direction.dx / direction.dy;
    if (direction.dy > 0 && hitY > 0) {
      return Offset(-center.dy, center.dx);
    }
    if (direction.dy < 0 && hitY < size.height) {
      return Offset(center.dy - size.height, -center.dx);
    }
    return direction;
  }

  Curl3dPoint _flatPoint(Offset source) =>
      Curl3dPoint(source, 0, Offset.zero, 1);

  _CurlVertex _localVertex(Offset source) {
    final delta = source - creaseCenter;
    return _CurlVertex(
      source,
      delta.dx * u.dx + delta.dy * u.dy,
      delta.dx * e.dx + delta.dy * e.dy,
    );
  }

  Curl3dPoint _project(_CurlVertex vertex, _CurlBand band) {
    if (band == _CurlBand.flat) return _flatPoint(vertex.source);
    if (band == _CurlBand.back) {
      return Curl3dPoint(
        creaseCenter - u * (vertex.x + math.pi * radius) + e * vertex.y,
        2 * radius,
        Offset.zero,
        -1,
      );
    }
    final angle = vertex.x / radius;
    final sine = math.sin(angle);
    final cosine = math.cos(angle);
    return Curl3dPoint(
      creaseCenter + u * (radius * sine) + e * vertex.y,
      radius * (1 - cosine),
      u * sine,
      cosine,
    );
  }

  List<Offset> _pageCorners() => [
    Offset.zero,
    Offset(0, size.height),
    Offset(size.width, 0),
    Offset(size.width, size.height),
  ];

  List<_CurlVertex> _rotatedCorners() {
    final vertices = _pageCorners().map(_localVertex).toList();
    vertices.sort((a, b) {
      final order = b.x.compareTo(a.x);
      return order == 0 ? b.y.compareTo(a.y) : order;
    });
    return vertices;
  }

  List<(int, int)> _rectangleEdges(List<_CurlVertex> vertices) {
    final edges = [(0, 1), (0, 2), (1, 3), (2, 3)];
    final first = Offset(vertices[0].x, vertices[0].y);
    final third = Offset(vertices[2].x, vertices[2].y);
    final fourth = Offset(vertices[3].x, vertices[3].y);
    if ((first - third).distance > (first - fourth).distance) {
      edges[1] = (0, 3);
      edges[2] = (1, 2);
    }
    return edges;
  }

  List<_CurlVertex> _intersections(
    List<_CurlVertex> vertices,
    List<(int, int)> edges,
    double scan,
  ) {
    final result = <_CurlVertex>[];
    for (final edge in edges) {
      final a = vertices[edge.$1];
      final b = vertices[edge.$2];
      if (a.x <= scan || b.x >= scan) continue;
      final ratio = (scan - b.x) / (a.x - b.x);
      result.add(
        _CurlVertex(
          b.source + (a.source - b.source) * ratio,
          scan,
          b.y + (a.y - b.y) * ratio,
        ),
      );
    }
    return result;
  }

  void _appendCorner(
    List<_CurlVertex> output,
    _CurlVertex corner,
    List<_CurlVertex> intersections,
  ) {
    if (intersections.length > 1) return;
    if (intersections.isNotEmpty && intersections.first.y > corner.y) {
      output.addAll(intersections);
      output.add(corner);
    } else {
      output.add(corner);
      output.addAll(intersections);
    }
  }

  List<_CurlVertex> _scanBand(
    List<_CurlVertex> vertices,
    List<(int, int)> edges,
    double scan,
    double previous,
  ) {
    final output = <_CurlVertex>[];
    for (final corner in vertices) {
      if (corner.x < scan || corner.x > previous) continue;
      _appendCorner(output, corner, _intersections(vertices, edges, corner.x));
    }
    final intersections = _intersections(vertices, edges, scan);
    if (intersections.length == 2) {
      if (intersections[0].y < intersections[1].y) {
        output.addAll(intersections.reversed);
      } else {
        output.addAll(intersections);
      }
    }
    return output;
  }

  List<Curl3dSample> _flatMesh() => [
    for (final source in _pageCorners())
      Curl3dSample(source, _flatPoint(source)),
  ];

  List<Curl3dSample> _buildMesh() {
    if (!active) return _flatMesh();
    final vertices = _rotatedCorners();
    final edges = _rectangleEdges(vertices);
    final scans = [
      0.0,
      for (var i = 1; i < _curlSplits; i++)
        -math.pi * radius * i / (_curlSplits - 1),
      vertices.last.x - 1,
    ];
    final samples = <Curl3dSample>[];
    var previous = vertices.first.x + 1;
    for (var index = 0; index < scans.length; index++) {
      final band = index == 0
          ? _CurlBand.flat
          : index == scans.length - 1 || radius == 0
          ? _CurlBand.back
          : _CurlBand.cylinder;
      for (final vertex in _scanBand(vertices, edges, scans[index], previous)) {
        samples.add(Curl3dSample(vertex.source, _project(vertex, band)));
      }
      previous = scans[index];
    }
    return samples;
  }

  List<Curl3dStrip> _buildStrips() {
    if (!active) return const [];
    final columns = <int>[0];
    for (var index = 1; index < mesh.length; index++) {
      if ((_localX(mesh[index].source) - _localX(mesh[index - 1].source))
                  .abs() >
              1e-7 ||
          // 半径归零时同位置可由正面切换到纸背，仍须保留法线跳变。
          (mesh[index].point.normalZ - mesh[index - 1].point.normalZ).abs() >
              1e-7) {
        columns.add(index);
      }
    }
    final positions = [
      for (final index in columns) _localX(mesh[index].point.position),
    ];
    final minimum = positions.reduce(math.min);
    final first = positions.indexWhere((x) => (x - minimum).abs() < 1e-7);
    final last = positions.lastIndexWhere((x) => (x - minimum).abs() < 1e-7);
    final frontEnd = first + 1 < columns.length
        ? columns[first + 1]
        : mesh.length;
    return List.unmodifiable([
      for (final branch in [
        mesh.sublist(0, frontEnd),
        mesh.sublist(columns[last]),
      ])
        ?_strip(branch),
    ]);
  }

  Curl3dStrip? _strip(List<Curl3dSample> branch) {
    if (branch.length < 3) return null;
    final profile = _projectionProfile(branch);
    return profile.length < 2
        ? null
        : Curl3dStrip(List.unmodifiable(branch), profile);
  }

  double _localX(Offset position) =>
      (position.dx - creaseCenter.dx) * u.dx +
      (position.dy - creaseCenter.dy) * u.dy;

  List<Curl3dProjectionStop> _projectionProfile(List<Curl3dSample> branch) {
    final stops = [
      for (final sample in branch)
        Curl3dProjectionStop(
          _localX(sample.point.position),
          _localX(sample.source),
          sample.point.normalXY.dx * u.dx + sample.point.normalXY.dy * u.dy,
          sample.point.normalZ,
        ),
    ]..sort((a, b) => a.x.compareTo(b.x));
    final profile = <Curl3dProjectionStop>[];
    for (final stop in stops) {
      if (profile.isEmpty || (stop.x - profile.last.x).abs() > 1e-7) {
        profile.add(stop);
      }
    }
    return List.unmodifiable(profile);
  }

  List<Curl3dShadowSample> _buildShadow({required bool self}) {
    if (!active || radius == 0) return const [];
    final edges = <(Curl3dShadowSample, Curl3dShadowSample)>[];
    for (final sample in mesh) {
      final pair = _shadowPair(sample.point, self: self);
      if (pair != null) edges.insert((edges.length + 1) ~/ 2, pair);
    }
    return [
      for (final edge in edges) ...[edge.$1, edge.$2],
    ];
  }

  (Curl3dShadowSample, Curl3dShadowSample)? _shadowPair(
    Curl3dPoint point, {
    required bool self,
  }) {
    if (self ? point.z <= radius : point.z <= 0 || point.z > radius) {
      return null;
    }
    final t = self ? (point.z - radius) / radius : point.z / radius;
    final smooth = t * t * (3 - 2 * t);
    final offset = self
        ? u * (smooth * radius * 0.4)
        : -u * (math.sqrt(smooth) * radius * 0.8);
    final alpha = self
        ? (0.3 + smooth * 0.3) * 0.5
        : (0.5 + smooth * 0.5) * 0.5;
    return (
      Curl3dShadowSample(point.position, alpha),
      Curl3dShadowSample(point.position + offset, 0),
    );
  }
}

/// 保留原覆盖顺序的一段单调投影，最多前后两段。
class Curl3dStrip {
  const Curl3dStrip(this.mesh, this.profile);

  final List<Curl3dSample> mesh;
  final List<Curl3dProjectionStop> profile;
}

/// 投影局部 x 对应的纸面 x 和完整法线，法线的 xy 分量沿卷曲方向。
class Curl3dProjectionStop {
  const Curl3dProjectionStop(
    this.x,
    this.sourceX,
    this.normalSin,
    this.normalZ,
  );

  final double x;
  final double sourceX;
  final double normalSin;
  final double normalZ;
}

/// 一个顶点的正交投影；z 用于法线着色和两类阴影。
class Curl3dPoint {
  const Curl3dPoint(this.position, this.z, this.normalXY, this.normalZ);

  final Offset position;
  final double z;
  final Offset normalXY;
  final double normalZ;
}

/// 原页面像素 UV 与变形后的顶点成对保存。
class Curl3dSample {
  const Curl3dSample(this.source, this.point);

  final Offset source;
  final Curl3dPoint point;
}

/// 阴影三角形带的屏幕位置和最终透明度。
class Curl3dShadowSample {
  const Curl3dShadowSample(this.position, this.alpha);

  final Offset position;
  final double alpha;
}

enum _CurlBand { flat, cylinder, back }

class _CurlState {
  const _CurlState(this.radius, this.center, this.direction, this.active);

  final double radius;
  final Offset center;
  final Offset direction;
  final bool active;
}

class _CurlVertex {
  const _CurlVertex(this.source, this.x, this.y);

  final Offset source;
  final double x;
  final double y;
}
