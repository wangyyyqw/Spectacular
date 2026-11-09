import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/curl3d_geometry.dart';

const _size = Size(400, 600);

Curl3dGeometry _geometry({
  Offset grab = const Offset(400, 600),
  Offset touch = const Offset(300, 480),
  Offset slide = Offset.zero,
}) => Curl3dGeometry(size: _size, grab: grab, touch: touch, slide: slide);

bool _inside(Offset point) =>
    point.dx >= -0.01 &&
    point.dy >= -0.01 &&
    point.dx <= _size.width + 0.01 &&
    point.dy <= _size.height + 0.01;

void main() {
  test('页角正好落在触点上', () {
    for (final touch in <Offset>[
      const Offset(300, 480),
      const Offset(240, 360),
      const Offset(80, 120),
    ]) {
      final geometry = _geometry(touch: touch);
      final corner = geometry.pointAt(geometry.grab);
      expect(
        (corner.position - geometry.touch).distance,
        lessThan(0.01),
        reason: '触点 $touch',
      );
    }
  });

  test('没有拖动时整页保持原样', () {
    final geometry = _geometry(touch: const Offset(400, 600));
    expect(geometry.hasFold, isFalse);
    expect(geometry.active, isFalse);
    for (final point in <Offset>[
      Offset.zero,
      const Offset(200, 300),
      const Offset(400, 600),
    ]) {
      final projected = geometry.pointAt(point).position;
      expect((projected - point).distance, lessThan(0.001));
    }
  });

  test('折痕以内的纸面保持平面，内容不压缩', () {
    final geometry = _geometry();
    for (final source in <Offset>[
      const Offset(20, 40),
      const Offset(180, 300),
      const Offset(360, 200),
    ]) {
      expect(geometry.depthOf(source), lessThan(0));
      final projected = geometry.pointAt(source);
      expect((projected.position - source).distance, lessThan(0.001));
      expect(projected.normalZ, 1);
    }
  });

  test('折角只切开页角，拖动位移全部转化为折角', () {
    final near = _geometry(touch: const Offset(380, 560));
    final far = _geometry(touch: const Offset(240, 360));
    // 折痕随触点移动，折痕之外的另一侧保持不动。
    expect(
      near.creaseCenter.dx,
      greaterThan(far.creaseCenter.dx),
      reason: '触点越靠左，折痕越靠左',
    );
    for (final geometry in <Curl3dGeometry>[near, far]) {
      final corner = geometry.pointAt(const Offset(0, 0)).position;
      expect((corner - const Offset(0, 0)).distance, lessThan(0.001));
    }
  });

  test('折痕垂直于页角与触点的连线', () {
    final geometry = _geometry(touch: const Offset(300, 480));
    final axis = geometry.grab - geometry.touch;
    expect(geometry.u.dx, closeTo(axis.dx / axis.distance, 0.0001));
    expect(geometry.u.dy, closeTo(axis.dy / axis.distance, 0.0001));
    expect(geometry.e.dx * geometry.u.dx + geometry.e.dy * geometry.u.dy, 0);
  });

  test('圆柱与平铺纸面在弧长处连续', () {
    final geometry = _geometry();
    final before = geometry.pointAt(
      geometry.at(geometry.rollLength - 0.01, 10),
    );
    final after = geometry.pointAt(geometry.at(geometry.rollLength + 0.01, 10));
    expect((after.position - before.position).distance, lessThan(0.2));
    expect(after.normalZ, -1);
  });

  test('纸背在屏幕上的宽度不超过弧长，说明纸面被折叠而非拉伸', () {
    final geometry = _geometry(touch: const Offset(240, 360));
    final tip = geometry.pointAt(geometry.grab).position;
    final axis = (tip - geometry.creaseCenter).distance;
    expect(axis, lessThan(geometry.flapDepth));
  });

  test('三个网格都只铺在纸面之内，不产生越界三角形', () {
    for (final touch in <Offset>[
      const Offset(390, 570),
      const Offset(300, 480),
      const Offset(40, 60),
    ]) {
      final geometry = _geometry(touch: touch);
      for (final grid in <Curl3dGrid>[
        geometry.frontGrid(),
        geometry.flapFrontGrid(),
        geometry.flapBackGrid(),
      ]) {
        expect(grid.width, greaterThan(1), reason: '触点 $touch');
        expect(grid.samples.length % grid.width, 0);
        expect(grid.height, greaterThan(1));
        for (final sample in grid.samples) {
          expect(_inside(sample.source), isTrue, reason: '触点 $touch');
        }
      }
    }
  });

  test('正面网格在折痕以内，纸背网格在折痕之外', () {
    final geometry = _geometry();
    for (final sample in geometry.frontGrid().samples) {
      expect(geometry.depthOf(sample.source), lessThan(0.01));
    }
    for (final sample in geometry.flapFrontGrid().samples) {
      expect(geometry.depthOf(sample.source), greaterThan(-0.01));
    }
    for (final sample in geometry.flapBackGrid().samples) {
      expect(geometry.depthOf(sample.source), greaterThan(-0.01));
    }
  });

  test('纸背网格覆盖整个折角，边界贴着纸边', () {
    final geometry = _geometry();
    final back = geometry.flapBackGrid();
    final depths = <double>[];
    for (var row = 0; row < back.height; row++) {
      final samples = back.samples.sublist(
        row * back.width,
        row * back.width + back.width,
      );
      depths.add(geometry.depthOf(samples.last.source));
    }
    expect(
      depths.reduce((a, b) => a > b ? a : b),
      closeTo(geometry.flapDepth, 0.5),
      reason: '折角尖端应被网格覆盖到',
    );
  });

  test('收尾位移整体平移纸张', () {
    final still = _geometry();
    final shifted = _geometry(slide: const Offset(-120, 0));
    final a = still.pointAt(const Offset(100, 100)).position;
    final b = shifted.pointAt(const Offset(100, 100)).position;
    expect((b - a - const Offset(-120, 0)).distance, lessThan(0.001));
  });

  test('纸背轮廓落在页面之内', () {
    for (final touch in <Offset>[
      const Offset(390, 570),
      const Offset(300, 480),
      const Offset(160, 260),
    ]) {
      final geometry = _geometry(touch: touch);
      final outline = geometry.flapOutline();
      expect(outline.length, greaterThan(3));
      // 卷边会略微鼓出页面边界，允许一个圆柱半径的余量。
      final margin = geometry.radius + 0.5;
      for (final point in outline) {
        expect(point.dx.isFinite && point.dy.isFinite, isTrue);
        expect(
          point.dx >= -margin &&
              point.dy >= -margin &&
              point.dx <= _size.width + margin &&
              point.dy <= _size.height + margin,
          isTrue,
          reason: '触点 $touch 轮廓越界 $point',
        );
      }
    }
  });
}
