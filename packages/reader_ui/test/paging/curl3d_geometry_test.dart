import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/curl3d_geometry.dart';

const _size = Size(400, 600);

// 数值来自多看 7.44.21 CurlMesh 的 Java 执行结果；仅按 DEX 修正 JADX 的
// 排序循环、求交循环和扫描分母，再把 GL 坐标及归一化 UV 换算成页面像素。
const _nativeCenter20 = {
  0: [0.0, 600.0, 0.0, 600.0, 0.0, 0.0, 0.0, 1.0],
  9: [368.348541, 600.0, 367.008972, 600.0, 8.035083, 0.475947, 0.0, 0.879474],
  17: [400.0, 0.0, 390.302155, 0.0, 29.024744, 0.825345, 0.0, 0.564629],
};
const _nativeUpper = {
  0: [0.0, 600.0, 0.0, 600.0, 0.0, 0.0, 0.0, 1.0],
  20: [
    237.996170,
    0.0,
    227.682556,
    12.376343,
    39.886971,
    0.586264,
    -0.703517,
    0.401695,
  ],
  39: [
    400.0,
    0.0,
    301.939697,
    117.672363,
    127.306587,
    0.265989,
    -0.319186,
    -0.909599,
  ],
};
const _nativeLower = {
  0: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
  20: [
    400.0,
    464.996796,
    389.686401,
    452.620483,
    39.886971,
    0.586264,
    0.703517,
    0.401695,
  ],
  39: [
    400.0,
    600.0,
    301.939697,
    482.327637,
    127.306595,
    0.265989,
    0.319186,
    -0.909599,
  ],
};

Curl3dGeometry _geometry({
  Offset grab = const Offset(400, 300),
  Offset touch = const Offset(280, 300),
}) => Curl3dGeometry(size: _size, grab: grab, touch: touch);

void _expectOffset(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 0.001));
  expect(actual.dy, closeTo(expected.dy, 0.001));
}

void _expectSample(Curl3dSample sample, List<double> expected) {
  final actual = [
    sample.source.dx,
    sample.source.dy,
    sample.point.position.dx,
    sample.point.position.dy,
    sample.point.z,
    sample.point.normalXY.dx,
    sample.point.normalXY.dy,
    sample.point.normalZ,
  ];
  for (var index = 0; index < actual.length; index++) {
    expect(
      actual[index],
      closeTo(expected[index], index < 5 ? 0.001 : 0.000001),
    );
  }
}

void _expectShadow(Curl3dShadowSample sample, List<double> expected) {
  _expectOffset(sample.position, Offset(expected[0], expected[1]));
  expect(sample.alpha, closeTo(expected[2], 0.000001));
}

double _sourceArea(List<Curl3dSample> strip) {
  var area = 0.0;
  for (var index = 2; index < strip.length; index++) {
    final a = strip[index - 2].source;
    final b = strip[index - 1].source - a;
    final c = strip[index].source - a;
    area += (b.dx * c.dy - b.dy * c.dx).abs() / 2;
  }
  return area;
}

void _expectFiniteGeometry(Curl3dGeometry geometry) {
  expect(geometry.radius, inInclusiveRange(0, _size.width / 6));
  expect(geometry.mesh.length, inInclusiveRange(4, 46));
  expect(_sourceArea(geometry.mesh), closeTo(240000, 0.001));
  for (final sample in geometry.mesh) {
    expect(sample.source.dx, inInclusiveRange(-0.001, 400.001));
    expect(sample.source.dy, inInclusiveRange(-0.001, 600.001));
    expect(sample.point.position.isFinite && sample.point.z.isFinite, isTrue);
    final normal = sample.point.normalXY;
    final z = sample.point.normalZ;
    expect(
      normal.dx * normal.dx + normal.dy * normal.dy + z * z,
      closeTo(1, 1e-8),
    );
  }
  expect(
    geometry.dropShadow.length + geometry.selfShadow.length,
    lessThanOrEqualTo(88),
  );
  for (final strip in [geometry.dropShadow, geometry.selfShadow]) {
    expect(strip.length.isEven, isTrue);
    for (final sample in strip) {
      expect(sample.position.isFinite, isTrue);
      expect(sample.alpha, inInclusiveRange(0, 0.5));
    }
  }
}

void _testFixedRadius() {
  test('中心拖动保持页面宽度六分之一的原生半径', () {
    for (final x in [380.0, 280.0, 160.0]) {
      final geometry = _geometry(touch: Offset(x, 300));
      expect(geometry.active, isTrue);
      expect(geometry.radius, closeTo(66.666667, 0.000001));
      _expectOffset(geometry.u, const Offset(-1, 0));
      _expectOffset(geometry.e, const Offset(0, 1));
    }
  });
}

void _testInitialCurl() {
  test('四百像素页面初拖二十像素符合原生折痕与页角数值', () {
    final geometry = _geometry(touch: const Offset(380, 300));
    _expectOffset(geometry.creaseCenter, const Offset(335.279144, 300));
    final corner = geometry.pointAt(const Offset(400, 300));
    _expectOffset(corner.position, const Offset(390.302155, 300));
    expect(corner.z, closeTo(29.024744, 0.001));
    expect(corner.normalZ, closeTo(0.564629, 0.000001));
    // 原生起卷让页角沿圆柱渐入，初期页角并不精确落到手指上。
    expect(corner.position.dx, greaterThan(geometry.touch.dx + 10));
    _expectOffset(
      geometry.pointAt(const Offset(100, 120)).position,
      const Offset(100, 120),
    );
  });
}

void _testFlatPage() {
  test('零拖动和右缘以外保持四顶点平面', () {
    for (final touch in [const Offset(400, 300), const Offset(420, 300)]) {
      final geometry = _geometry(touch: touch);
      expect(geometry.active, isFalse);
      expect(geometry.mesh.length, 4);
      expect(geometry.dropShadow, isEmpty);
      expect(geometry.selfShadow, isEmpty);
      for (final sample in geometry.mesh) {
        expect(sample.point.position, sample.source);
        expect(sample.point.z, 0);
        expect(sample.point.normalZ, 1);
      }
    }
  });
}

void _testNativeScan() {
  test('水平起卷按原生连续扫描顺序保留固定像素纹理坐标', () {
    final geometry = _geometry(touch: const Offset(380, 300));
    expect(geometry.mesh.length, 18);
    for (final entry in _nativeCenter20.entries) {
      _expectSample(geometry.mesh[entry.key], entry.value);
    }
    expect(geometry.dropShadow.length, 26);
    expect(geometry.selfShadow, isEmpty);
  });
}

void _testCornerScan() {
  test('上下角插点及法线符合原生网格', () {
    final cases = [
      (
        _geometry(grab: const Offset(400, 0), touch: const Offset(300, 120)),
        _nativeUpper,
      ),
      (
        _geometry(grab: const Offset(400, 600), touch: const Offset(300, 480)),
        _nativeLower,
      ),
    ];
    for (final (geometry, expected) in cases) {
      expect(geometry.mesh.length, 40);
      for (final entry in expected.entries) {
        _expectSample(geometry.mesh[entry.key], entry.value);
      }
    }
  });
}

void _testPageEdgeConstraint() {
  test('触点越过上下边缘时采用原生页边方向约束', () {
    final upper = _geometry(
      grab: const Offset(400, 0),
      touch: const Offset(380, -40),
    );
    final lower = _geometry(
      grab: const Offset(400, 600),
      touch: const Offset(380, 640),
    );
    _expectOffset(upper.creaseCenter, const Offset(356.718536, -86.562927));
    _expectOffset(lower.creaseCenter, const Offset(356.718536, 686.562866));
    _expectOffset(upper.u, const Offset(-0.887372, -0.461053));
    _expectOffset(lower.u, const Offset(-0.887372, 0.461053));
    _expectOffset(
      upper.pointAt(const Offset(400, 600)).position,
      const Offset(-44.092987, 369.261902),
    );
    _expectOffset(
      lower.pointAt(const Offset(400, 0)).position,
      const Offset(-44.092960, 230.738068),
    );
  });
}

void _testLeftEdgeShrink() {
  test('左侧越界才收缩半径并可退化为完整纸背', () {
    final shrink = _geometry(touch: const Offset(-280, 300));
    expect(shrink.radius, closeTo(36.773714, 0.001));
    _expectOffset(shrink.creaseCenter, const Offset(0, 300));
    _expectOffset(
      shrink.pointAt(const Offset(400, 300)).position,
      const Offset(-284.471985, 300),
    );
    final flatBack = _geometry(touch: const Offset(-400, 300));
    expect(flatBack.active, isTrue);
    expect(flatBack.radius, 0);
    _expectOffset(
      flatBack.pointAt(const Offset(400, 600)).position,
      const Offset(-400, 600),
    );
    expect(flatBack.pointAt(const Offset(400, 600)).normalZ, -1);
    expect(flatBack.dropShadow, isEmpty);
    expect(flatBack.selfShadow, isEmpty);
  });
}

void _testBackwardAnchor() {
  test('后退把虚拟左页起手点投影到可见右缘', () {
    final geometry = _geometry(
      grab: const Offset(-400, 300),
      touch: const Offset(40, 360),
    );
    _expectOffset(geometry.creaseCenter, const Offset(116.240509, 370.396423));
    _expectOffset(geometry.u, const Offset(-0.990830, -0.135113));
    _expectOffset(
      geometry.pointAt(const Offset(400, 600)).position,
      const Offset(-11.115719, 543.938599),
    );
    expect(geometry.radius, closeTo(66.666667, 0.000001));
    final initial = _geometry(
      grab: const Offset(-400, 300),
      touch: const Offset(-400, 300),
    );
    expect(initial.radius, 0);
    _expectOffset(
      initial.pointAt(const Offset(400, 300)).position,
      const Offset(-400, 300),
    );
  });
}

void _testNativeShadows() {
  test('两类阴影沿原生轮廓排序并包含最终半影与透明度', () {
    final geometry = _geometry();
    expect(geometry.mesh.length, 36);
    expect(geometry.dropShadow.length, 36);
    expect(geometry.selfShadow.length, 26);
    _expectShadow(geometry.dropShadow[0], [252.439880, 600.0, 0.250138]);
    _expectShadow(geometry.dropShadow[18], [307.905884, 0.0, 0.495167]);
    _expectShadow(geometry.dropShadow[35], [253.694031, 0.0, 0.0]);
    _expectShadow(geometry.selfShadow[0], [307.905884, 600.0, 0.152900]);
    _expectShadow(geometry.selfShadow[13], [265.927307, 0.0, 0.0]);
    _expectShadow(geometry.selfShadow[25], [307.390381, 0.0, 0.0]);
    final lower = _geometry(
      grab: const Offset(400, 600),
      touch: const Offset(300, 480),
    );
    _expectShadow(lower.dropShadow.first, [134.651947, 599.961487, 0.250138]);
    _expectShadow(lower.selfShadow.last, [371.634796, 474.005249, 0.0]);
  });
}

void _testFiniteTopology() {
  test('中心角部反向与半径退化仍完整覆盖页面且拓扑有限', () {
    for (final (grab, touch) in [
      (const Offset(400, 300), const Offset(400, 300)),
      (const Offset(400, 300), const Offset(380, 300)),
      (const Offset(400, 300), const Offset(160, 300)),
      (const Offset(400, 0), const Offset(300, 120)),
      (const Offset(400, 600), const Offset(300, 480)),
      (const Offset(400, 0), const Offset(380, -40)),
      (const Offset(400, 600), const Offset(380, 640)),
      (const Offset(400, 300), const Offset(-280, 300)),
      (const Offset(400, 300), const Offset(-400, 300)),
      (const Offset(-400, 300), const Offset(40, 360)),
      (const Offset(-400, 300), const Offset(-400, 300)),
    ]) {
      _expectFiniteGeometry(_geometry(grab: grab, touch: touch));
    }
  });
}

List<double> _projectedSample(
  Curl3dGeometry geometry,
  Curl3dStrip strip,
  Offset position,
) {
  final profile = strip.profile;
  final x =
      (position.dx - geometry.creaseCenter.dx) * geometry.u.dx +
      (position.dy - geometry.creaseCenter.dy) * geometry.u.dy;
  var end = profile.indexWhere((stop) => stop.x >= x);
  if (end < 0) end = profile.length - 1;
  if (end == 0) end = 1;
  final a = profile[end - 1];
  final b = profile[end];
  final t = ((x - a.x) / (b.x - a.x)).clamp(0.0, 1.0);
  final sourceX = a.sourceX + (b.sourceX - a.sourceX) * t;
  final source = position + geometry.u * (sourceX - x);
  final normalSin = a.normalSin + (b.normalSin - a.normalSin) * t;
  return [
    source.dx,
    source.dy,
    geometry.u.dx * normalSin,
    geometry.u.dy * normalSin,
    a.normalZ + (b.normalZ - a.normalZ) * t,
  ];
}

double _projectedArea(List<Curl3dSample> triangle) {
  final a = triangle[0].point.position;
  final b = triangle[1].point.position - a;
  final c = triangle[2].point.position - a;
  return (b.dx * c.dy - b.dy * c.dx).abs();
}

void _testProjectionProfile() {
  test('屏幕片元反查保留原 strip 的全部非退化三角形、UV 与完整法线', () {
    for (final (grab, touch) in [
      (const Offset(400, 300), const Offset(380, 300)),
      (const Offset(400, 300), const Offset(347, 300)),
      (const Offset(400, 300), const Offset(350, 300)),
      (const Offset(400, 300), const Offset(200, 300)),
      (const Offset(400, 300), const Offset(160, 300)),
      (const Offset(400, 0), const Offset(300, 120)),
      (const Offset(400, 600), const Offset(300, 480)),
      (const Offset(400, 0), const Offset(200, 12)),
      (const Offset(400, 600), const Offset(200, 588)),
      (const Offset(400, 0), const Offset(380, -40)),
      (const Offset(400, 300), const Offset(-280, 300)),
      (const Offset(400, 300), const Offset(-400, 300)),
      (const Offset(-400, 600), const Offset(100, 480)),
    ]) {
      _expectStripCoverage(_geometry(grab: grab, touch: touch));
    }
  });
}

void _expectStripCoverage(Curl3dGeometry geometry) {
  expect(geometry.strips.length, lessThanOrEqualTo(2));
  final mesh = geometry.mesh;
  final represented = <int>{};
  for (final strip in geometry.strips) {
    expect(strip.profile.length, lessThanOrEqualTo(24));
    final start = mesh.indexOf(strip.mesh.first);
    for (var index = 2; index < strip.mesh.length; index++) {
      final triangle = strip.mesh.sublist(index - 2, index + 1);
      if (_projectedArea(triangle) < 1e-7) continue;
      represented.add(start + index);
      _expectProjection(geometry, strip, triangle);
    }
  }
  expect(represented, {
    for (var index = 2; index < mesh.length; index++)
      if (_projectedArea(mesh.sublist(index - 2, index + 1)) >= 1e-7) index,
  }, reason: '姿态 ${geometry.touch} 只允许拆开投影退化的桥，不能删可见三角形');
}

void _expectProjection(
  Curl3dGeometry geometry,
  Curl3dStrip strip,
  List<Curl3dSample> triangle,
) {
  const weights = [0.2, 0.3, 0.5];
  var position = Offset.zero;
  final expected = List<double>.filled(5, 0);
  for (var index = 0; index < 3; index++) {
    final sample = triangle[index];
    position += sample.point.position * weights[index];
    final values = [
      sample.source.dx,
      sample.source.dy,
      sample.point.normalXY.dx,
      sample.point.normalXY.dy,
      sample.point.normalZ,
    ];
    for (var channel = 0; channel < values.length; channel++) {
      expected[channel] += values[channel] * weights[index];
    }
  }
  final actual = _projectedSample(geometry, strip, position);
  for (var channel = 0; channel < expected.length; channel++) {
    expect(
      actual[channel],
      closeTo(expected[channel], 1e-7),
      reason: '姿态 ${geometry.touch}、片元 $position、分量 $channel',
    );
  }
}

void main() {
  _testProjectionProfile();
  _testFixedRadius();
  _testInitialCurl();
  _testFlatPage();
  _testNativeScan();
  _testCornerScan();
  _testPageEdgeConstraint();
  _testLeftEdgeShrink();
  _testBackwardAnchor();
  _testNativeShadows();
  _testFiniteTopology();
}
