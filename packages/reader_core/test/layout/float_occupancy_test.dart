import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/float_occupancy.dart';

void main() {
  group('FloatOccupancy 占用模型（P3-12）', () {
    test('单浮左：区间内左占 100，浮动结束后恢复全宽', () {
      final occupancy = FloatOccupancy()
        ..insert(
          BoxOccupied(
            rect: const Rect.fromLTWH(0, 0, 100, 50),
            baseline: 0,
            side: FloatSide.left,
          ),
        );
      expect(occupancy.occupiedLeftAt(0, 20), 100);
      expect(occupancy.occupiedRightAt(0, 20, 300), 0);
      expect(occupancy.contentWidthAt(0, 20, 300), 200);
      expect(occupancy.contentWidthAt(50, 70, 300), 300,
          reason: '浮动底部之下不受约束（贴边不相交）');
      expect(occupancy.clearanceBelow(20, FloatSide.left), 30);
    });

    test('单浮右：区间内右占 80', () {
      final occupancy = FloatOccupancy()
        ..insert(
          BoxOccupied(
            rect: const Rect.fromLTWH(220, 0, 80, 60),
            baseline: 0,
            side: FloatSide.right,
          ),
        );
      expect(occupancy.occupiedRightAt(0, 30, 300), 80);
      expect(occupancy.occupiedLeftAt(0, 30), 0);
      expect(occupancy.contentWidthAt(0, 30, 300), 220);
      expect(occupancy.clearanceBelow(60, FloatSide.right), 0);
    });

    test('双浮动重叠：左右约束叠加', () {
      final occupancy = FloatOccupancy()
        ..insert(
          BoxOccupied(
            rect: const Rect.fromLTWH(0, 0, 100, 80),
            baseline: 0,
            side: FloatSide.left,
          ),
        )
        ..insert(
          BoxOccupied(
            rect: const Rect.fromLTWH(220, 20, 80, 40),
            baseline: 1,
            side: FloatSide.right,
          ),
        );
      // 重叠区（20..60）：左 100 + 右 80。
      expect(occupancy.contentWidthAt(20, 40, 300), 120);
      // 只剩左浮动区（60..80）。
      expect(occupancy.contentWidthAt(60, 80, 300), 200);
      // 双双结束后。
      expect(occupancy.contentWidthAt(80, 100, 300), 300);
    });

    test('同 y 多个左浮动取最大右边缘（CSS 语义）', () {
      final occupancy = FloatOccupancy()
        ..insert(
          BoxOccupied(
            rect: const Rect.fromLTWH(0, 0, 60, 40),
            baseline: 0,
            side: FloatSide.left,
          ),
        )
        ..insert(
          BoxOccupied(
            rect: const Rect.fromLTWH(60, 0, 60, 40),
            baseline: 0,
            side: FloatSide.left,
          ),
        );
      expect(occupancy.occupiedLeftAt(0, 40), 120);
    });

    test('take 分页切分：跨页浮动裁剪续用，本页用尽的消耗', () {
      final occupancy = FloatOccupancy()
        ..insert(
          BoxOccupied(
            rect: const Rect.fromLTWH(0, 10, 100, 60),
            baseline: 0,
            side: FloatSide.left,
          ),
        )
        ..insert(
          BoxOccupied(
            rect: const Rect.fromLTWH(0, 0, 50, 30),
            baseline: 0,
            side: FloatSide.right,
          ),
        );
      final (:next, :consumed) = occupancy.take(40);
      // 左浮（10..70）跨页：剩余高 20，x/宽度不变，y 归零。
      expect(next.items, hasLength(1));
      expect(next.items.single.rect, const Rect.fromLTWH(0, 0, 100, 20));
      expect(next.items.single.side, FloatSide.left);
      // 右浮（0..30）已用尽。
      expect(consumed, hasLength(1));
      expect(consumed.single.side, FloatSide.right);
      expect(next.contentWidthAt(0, 20, 300), 200);
    });

    test('removeIntersecting 与 clear', () {
      final occupancy = FloatOccupancy()
        ..insert(
          BoxOccupied(
            rect: const Rect.fromLTWH(0, 0, 100, 50),
            baseline: 0,
            side: FloatSide.left,
          ),
        )
        ..insert(
          BoxOccupied(
            rect: const Rect.fromLTWH(200, 100, 80, 50),
            baseline: 1,
            side: FloatSide.right,
          ),
        );
      occupancy.removeIntersecting(const Rect.fromLTWH(0, 0, 50, 20));
      expect(occupancy.items, hasLength(1));
      expect(occupancy.items.single.side, FloatSide.right);
      occupancy.clear();
      expect(occupancy.isEmpty, isTrue);
    });
  });
}
