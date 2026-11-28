import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_title_focus.dart';

// 120×160 正式拼图的可见多边形，已转到各封面自己的局部坐标。
// 固定几何夹具避免测试再次实现生产代码的分区和尺寸推导。
const _regions = <int, ({Size size, List<List<Offset>> paths})>{
  2: (
    size: Size(148.706538, 198.275384),
    paths: [
      [
        Offset(-47.517619, -98.804358),
        Offset(47.517619, -32.259969),
        Offset(-44.254611, 98.804358),
        Offset(-47.517619, 96.519576),
      ],
      [
        Offset(44.254611, -98.804358),
        Offset(47.517619, -96.519576),
        Offset(47.517619, 98.804358),
        Offset(-47.517619, 32.259969),
      ],
    ],
  ),
  3: (
    size: Size(115.698771, 154.265028),
    paths: [
      [
        Offset(-43.959619, 56.824645),
        Offset(-43.959619, -56.824645),
        Offset(43.959619, 4.737068),
        Offset(7.487504, 56.824645),
      ],
      [
        Offset(-47.522914, 60.458375),
        Offset(37.143906, -60.458375),
        Offset(47.522914, -53.190915),
        Offset(47.522914, 60.458375),
      ],
      [
        Offset(-39.488375, 69.693770),
        Offset(-39.488375, -76.799180),
        Offset(39.488375, -21.499065),
        Offset(-29.340798, 76.799180),
      ],
    ],
  ),
  4: (
    size: Size(95.535238, 127.380317),
    paths: [
      [
        Offset(-47.517619, 42.520184),
        Offset(-47.517619, -42.520184),
        Offset(47.517619, 24.024206),
        Offset(34.566596, 42.520184),
      ],
      [
        Offset(-34.566596, -42.520184),
        Offset(47.517619, -42.520184),
        Offset(47.517619, 42.520184),
        Offset(-47.517619, -24.024206),
      ],
      [
        Offset(-41.042107, 56.284175),
        Offset(37.779100, -56.284175),
        Offset(41.042107, -53.999392),
        Offset(41.042107, 56.284175),
      ],
      [
        Offset(-41.042107, -56.284175),
        Offset(41.042107, -56.284175),
        Offset(-37.779100, 56.284175),
        Offset(-41.042107, 53.999392),
      ],
    ],
  ),
};

double _visibleFraction(
  Path region,
  CoverTitleFocus focus,
  ({Size imageSize, Offset translation}) placement,
) {
  final size = placement.imageSize;
  final title = Rect.fromLTRB(
    (focus.titleBounds.left - .5) * size.width,
    (focus.titleBounds.top - .5) * size.height,
    (focus.titleBounds.right - .5) * size.width,
    (focus.titleBounds.bottom - .5) * size.height,
  ).shift(placement.translation);
  var visible = 0;
  // 交付断言用更密的独立采样，避免只重述生产8×8评分。
  for (var row = 0; row < 80; row++) {
    for (var column = 0; column < 80; column++) {
      if (region.contains(
        Offset(
          title.left + (column + .5) * title.width / 80,
          title.top + (row + .5) * title.height / 80,
        ),
      )) {
        visible++;
      }
    }
  }
  return visible / 6400;
}

void main() {
  for (final count in [2, 3, 4]) {
    test('$count 本旋转拼图保持原图比例，极端书名位置均不露底', () {
      final fixture = _regions[count]!;
      for (final (index, points) in fixture.paths.indexed) {
        final local = Path()..addPolygon(points, true);
        final rotation = (count == 3 && index == 2 ? 55 : -35) * math.pi / 180;
        const center = Offset(83, 119);
        final transform = Matrix4.translationValues(center.dx, center.dy, 0)
          ..rotateZ(rotation);
        final clip = local.transform(transform.storage);
        for (final image in const [
          Size(750, 1000),
          Size(300, 1800),
          Size(1600, 400),
        ]) {
          for (final title in const [
            Rect.fromLTRB(.15, .05, .85, .15),
            Rect.fromLTRB(.05, .2, .15, .8),
            Rect.fromLTRB(.15, .85, .85, .95),
          ]) {
            final placement = coverTitleFocusPlacement(
              focus: CoverTitleFocus(imageSize: image, titleBounds: title),
              coverSize: fixture.size,
              clipPath: clip,
              regionCenter: center,
              rotation: rotation,
            );
            expect(
              placement.imageSize.aspectRatio,
              closeTo(image.aspectRatio, 1e-8),
            );
            final fittedWidth = math.max(
              fixture.size.width,
              fixture.size.height * image.aspectRatio,
            );
            expect(
              placement.imageSize.width,
              inInclusiveRange(fittedWidth, fittedWidth * 1.35 + .001),
            );
            final imageBounds = Rect.fromCenter(
              center: placement.translation,
              width: placement.imageSize.width,
              height: placement.imageSize.height,
            );
            for (final point in points) {
              expect(
                imageBounds.inflate(.001).contains(point),
                isTrue,
                reason: '$count 本第 $index 张，$image，$title，顶点 $point 不得露底',
              );
            }
          }
        }
      }
    });
  }

  test('超长图顶部和宽图侧边书名从中心裁切之外进入两本拼图', () {
    final fixture = _regions[2]!;
    final region = Path()..addPolygon(fixture.paths.first, true);
    for (final example in const [
      (
        image: Size(500, 1000),
        title: Rect.fromLTRB(.15, .05, .85, .15),
        minimum: .35,
      ),
      (
        image: Size(1000, 500),
        title: Rect.fromLTRB(.05, .2, .15, .8),
        minimum: .85,
      ),
    ]) {
      final focus = CoverTitleFocus(
        imageSize: example.image,
        titleBounds: example.title,
      );
      final placement = coverTitleFocusPlacement(
        focus: focus,
        coverSize: fixture.size,
        clipPath: region,
        regionCenter: Offset.zero,
        rotation: 0,
      );
      expect(
        _visibleFraction(region, focus, placement),
        greaterThan(example.minimum),
      );
    }
  });

  test('四本同宽高比顶部书名适度放大，已经可见的底部书名保留原大小', () {
    final fixture = _regions[4]!;
    final region = Path()..addPolygon(fixture.paths.first, true);
    for (final bottom in [false, true]) {
      final focus = CoverTitleFocus(
        imageSize: const Size(750, 1000),
        titleBounds: bottom
            ? const Rect.fromLTRB(.15, .85, .85, .95)
            : const Rect.fromLTRB(.15, .05, .85, .15),
      );
      final placement = coverTitleFocusPlacement(
        focus: focus,
        coverSize: fixture.size,
        clipPath: region,
        regionCenter: Offset.zero,
        rotation: 0,
      );
      expect(
        _visibleFraction(region, focus, placement),
        greaterThan(bottom ? .95 : .23),
      );
      expect(
        placement.imageSize.width,
        bottom
            ? closeTo(fixture.size.width, .001)
            : greaterThan(fixture.size.width),
      );
    }
  });

  test('书名已在中心可见时不放大或无故移动', () {
    final clip = Path()..addRect(const Rect.fromLTRB(-30, -50, 30, 50));
    final placement = coverTitleFocusPlacement(
      focus: const CoverTitleFocus(
        imageSize: Size(100, 140),
        titleBounds: Rect.fromLTRB(.4, .4, .6, .6),
      ),
      coverSize: const Size(100, 140),
      clipPath: clip,
      regionCenter: Offset.zero,
      rotation: 0,
    );
    expect(placement.imageSize, const Size(100, 140));
    expect(placement.translation, Offset.zero);
  });
}
