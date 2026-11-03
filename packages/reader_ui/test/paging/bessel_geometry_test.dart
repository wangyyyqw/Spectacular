import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/bessel_geometry.dart';

void expectOffset(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 0.001));
  expect(actual.dy, closeTo(expected.dy, 0.001));
}

Offset transform(Float64List matrix, Offset point) => Offset(
  matrix[0] * point.dx + matrix[4] * point.dy + matrix[12],
  matrix[1] * point.dx + matrix[5] * point.dy + matrix[13],
);

void main() {
  test('690 固定输入恢复 A 到 K 控制点', () {
    final geometry = BesselGeometry.resolve(
      const Size(1000, 1500),
      const Offset(600, 1000),
    );
    expect(geometry, isNotNull);
    final value = geometry!;

    expectOffset(value.a, const Offset(600, 1000));
    expectOffset(value.f, const Offset(1000, 1500));
    expectOffset(value.e, const Offset(487.5, 1500));
    expectOffset(value.h, const Offset(1000, 1090));
    expectOffset(value.c, const Offset(231.25, 1500));
    expectOffset(value.j, const Offset(1000, 885));
    expectOffset(value.b, const Offset(543.75, 1250));
    expectOffset(value.k, const Offset(800, 1045));
    expectOffset(value.d, const Offset(437.5, 1437.5));
    expectOffset(value.i, const Offset(950, 1027.5));
  });

  test('纸背反射固定 E、H，并将抓取点映射到页角', () {
    final geometry = BesselGeometry.resolve(
      const Size(1000, 1500),
      const Offset(600, 1000),
    )!;
    final matrix = geometry.reflection();

    expectOffset(transform(matrix, geometry.e), geometry.e);
    expectOffset(transform(matrix, geometry.h), geometry.h);
    expectOffset(transform(matrix, geometry.a), geometry.f);
  });

  test('退化尺寸与触摸点返回空结果', () {
    expect(BesselGeometry.resolve(Size.zero, Offset.zero), isNull);
    expect(
      BesselGeometry.resolve(
        const Size(1000, 1500),
        const Offset(double.nan, 1),
      ),
      isNull,
    );
  });

  test('折痕越出纸面时上下页角仍与触点重合', () {
    const size = Size(320, 480);
    for (final top in [false, true]) {
      final touch = Offset(280, top ? 170 : 310);
      final geometry = BesselGeometry.resolve(size, touch, top: top)!;

      expectOffset(geometry.a, touch);
      expectOffset(transform(geometry.reflection(), geometry.f), touch);
      expect(geometry.frontPath().getBounds().isFinite, isTrue);
      expect(
        geometry.backPath(geometry.frontPath()).getBounds().isFinite,
        isTrue,
      );
    }
  });

  test('中心起卷沿整条侧边弯曲且抓取点固定在触点', () {
    const size = Size(320, 480);
    for (final y in <double>[192, 240, 288]) {
      final touch = Offset(220, y);
      final geometry = BesselGeometry.resolve(size, touch, horizontal: true)!;
      final front = geometry.frontPath();
      final back = geometry.backPath(front);

      expectOffset(geometry.a, touch);
      expectOffset(geometry.f, Offset(320, y));
      expectOffset(transform(geometry.reflection(), geometry.f), touch);
      expect(front.contains(touch - const Offset(1, 0)), isTrue);
      expect(front.contains(touch + const Offset(1, 0)), isFalse);
      expect(back.contains(touch + const Offset(1, 0)), isTrue);
      expect(back.getBounds().height, size.height);
    }
  });

  test('中心起卷在首尾帧和越界点的路径及反射均有限', () {
    const size = Size(320, 480);
    for (final x in <double>[320, 319.9, 0, -319.9, -320]) {
      final geometry = BesselGeometry.resolve(
        size,
        Offset(x, 240),
        horizontal: true,
      )!;

      expect(geometry.reflection().every((value) => value.isFinite), isTrue);
      expect(geometry.frontPath().getBounds().isFinite, isTrue);
      expect(
        geometry.backPath(geometry.frontPath()).getBounds().isFinite,
        isTrue,
      );
    }
  });
}
