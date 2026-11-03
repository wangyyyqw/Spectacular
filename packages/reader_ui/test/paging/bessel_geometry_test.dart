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

  test('角部过度纵向拖动被限制在书脊边界，水平位置仍跟手', () {
    const size = Size(320, 480);
    for (final top in [false, true]) {
      final touch = Offset(280, top ? 170 : 310);
      final geometry = BesselGeometry.resolve(size, touch, top: top)!;

      expect(geometry.a.dx, touch.dx);
      expect(geometry.c.dx, closeTo(0, 0.001));
      expect((geometry.a.dy - geometry.f.dy).abs(), lessThan(170));
      expectOffset(transform(geometry.reflection(), geometry.f), geometry.a);
      expect(geometry.frontPath().getBounds().isFinite, isTrue);
      expect(
        geometry.backPath(geometry.frontPath()).getBounds().isFinite,
        isTrue,
      );
    }
  });

  test('高屏大幅斜拖不会把纸角拉到对侧半屏或将折痕拉过书脊', () {
    const size = Size(320, 700);
    for (final top in [false, true]) {
      final geometry = BesselGeometry.resolve(
        size,
        Offset(90, top ? 500 : 200),
        top: top,
      )!;

      expect(geometry.a.dx, 90);
      expect(geometry.c.dx, greaterThanOrEqualTo(-0.001));
      expect((geometry.a.dy - geometry.f.dy).abs(), lessThan(size.width));
      expect(top ? geometry.a.dy < 350 : geometry.a.dy > 350, isTrue);
    }
  });

  test('上下角连续越界拖动的折痕和纸背反射均有效', () {
    const size = Size(320, 700);
    for (final top in [false, true]) {
      for (var touchX = 320.0; touchX >= -320; touchX -= 4) {
        final geometry = BesselGeometry.resolve(
          size,
          Offset(touchX, top ? 650 : 50),
          top: top,
        )!;

        expect(geometry.a.dx, closeTo(touchX, 0.1001));
        expect(geometry.c.dx, greaterThanOrEqualTo(-160.001));
        expect(geometry.e.dx, greaterThanOrEqualTo(-0.001));
        expect(
          geometry.c.dx,
          greaterThanOrEqualTo(geometry.a.dx.clamp(-320, 0) / 2 - 0.001),
        );
        expect(geometry.reflection().every((value) => value.isFinite), isTrue);
        expectOffset(transform(geometry.reflection(), geometry.f), geometry.a);
        expect(geometry.frontPath().getBounds().isFinite, isTrue);
        expect(
          geometry.backPath(geometry.frontPath()).getBounds().isFinite,
          isTrue,
        );
      }
    }
  });

  test('越界限制在合法触点和边界之间连续，上下角互为镜像', () {
    const size = Size(320, 480);
    BesselGeometry? previous;
    for (var distance = 1.0; distance <= 479; distance += 0.5) {
      final bottom = BesselGeometry.resolve(
        size,
        Offset(220, size.height - distance),
      )!;
      final top = BesselGeometry.resolve(
        size,
        Offset(220, distance),
        top: true,
      )!;

      expectOffset(top.a, Offset(bottom.a.dx, size.height - bottom.a.dy));
      expect(top.c.dx, closeTo(bottom.c.dx, 0.001));
      if (previous != null) {
        expect((bottom.a - previous.a).distance, lessThanOrEqualTo(0.5001));
      }
      previous = bottom;
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

  test('中心起卷的纸边和折痕贯穿全高且宽度不随纵向触点变化', () {
    const size = Size(320, 480);
    for (final touchX in <double>[300, 220, 80, 0, -160, -300]) {
      Rect? previousBounds;
      for (final touchY in <double>[192, 240, 288]) {
        final geometry = BesselGeometry.resolve(
          size,
          Offset(touchX, touchY),
          horizontal: true,
        )!;
        final front = geometry.frontPath();
        final back = geometry.backPath(front);
        final bounds = back.getBounds();
        expect(bounds.left, touchX);
        expect(bounds.top, 0);
        expect(bounds.bottom, size.height);
        expect(bounds.right, lessThan(geometry.c.dx));
        if (previousBounds != null) expect(bounds, previousBounds);
        previousBounds = bounds;
        for (final sampleY in <double>[1, 120, 240, 360, 479]) {
          expect(front.contains(Offset(touchX + 1, sampleY)), isFalse);
          expect(back.contains(Offset(touchX + 0.5, sampleY)), isTrue);
          expect(back.contains(Offset(bounds.right - 0.5, sampleY)), isTrue);
          expect(back.contains(Offset(bounds.right + 0.5, sampleY)), isFalse);
        }
      }
    }
  });
}
