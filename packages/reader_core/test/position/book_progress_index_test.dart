import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/book_progress_index.dart';

void main() {
  test('按未压缩字节和章内原文比例计算，结果不依赖页面或字号', () {
    final index = BookProgressIndex.fromUncompressedSizes([100, 300, 600]);
    expect(index.totalWeight, 1000);
    expect(index.chapterStarts, [0, 100, 400]);
    expect(index.estimated, isFalse);
    expect(index.percentOf(1, 0.5), 0.25);
    for (var repeat = 0; repeat < 10; repeat++) {
      expect(index.percentOf(1, 0.5), 0.25);
    }
  });

  test('排除目录、非正文和缺章后，首尾正文覆盖 0～100%', () {
    final index = BookProgressIndex.fromUncompressedSizes(
      [5000, 100, 5000, 300, null],
      excluded: {0, 2, 4},
    );
    expect(index.estimated, isFalse, reason: '已排除章的未知大小不触发等权');
    expect(index.chapterWeights, [0, 100, 0, 300, 0]);
    expect(index.totalWeight, 400);
    expect(index.percentOf(1, 0), 0);
    expect(index.percentOf(2, 0.8), 0.25);
    expect(index.percentOf(3, 1), 1);
    expect(index.includes(4), isFalse);
    expect(index.locate(0)!.spineIndex, 1);
    expect(index.locate(1)!.spineIndex, 3);
  });

  test('可读章元数据缺失或非法时，全书统一按可读章等权', () {
    for (final missing in <int?>[null, -1]) {
      final index = BookProgressIndex.fromUncompressedSizes(
        [5000, missing, 200, 800],
        excluded: {0},
      );
      expect(index.estimated, isTrue);
      expect(index.chapterWeights, [0, 1, 1, 1]);
      expect(index.totalWeight, 3);
      expect(index.percentOf(2, 0.5), 0.5);
    }
  });

  test('已知空条目不占字节权重，纯图片章节仍按文件大小计入', () {
    final index = BookProgressIndex.fromUncompressedSizes([0, 200, 800]);
    expect(index.includes(0), isFalse);
    expect(index.includes(1), isTrue);
    expect(index.estimated, isFalse);
    expect(index.locate(0)!.spineIndex, 1);
    expect(index.percentOf(2, 0.5), 0.6);
  });

  test('全部大小为零时按可读章节等权，空书和全部排除安全返回', () {
    final zero = BookProgressIndex.fromUncompressedSizes(
      [0, 0, 0],
      excluded: {1},
    );
    expect(zero.chapterWeights, [1, 0, 1]);
    expect(zero.estimated, isTrue);
    for (final index in [
      BookProgressIndex.fromUncompressedSizes([]),
      BookProgressIndex.fromUncompressedSizes([100, 200], excluded: {0, 1}),
    ]) {
      expect(index.totalWeight, 0);
      expect(index.percentOf(0, 0.5), 0);
      expect(index.locate(0.5), isNull);
    }
  });

  test('精确内部章边界选择下一章，100% 保留末章尾部', () {
    final index = BookProgressIndex.fromUncompressedSizes(
      [100, 999, 300],
      excluded: {1},
    );
    final boundary = index.locate(0.25)!;
    expect(boundary.spineIndex, 2);
    expect(boundary.chapterRatio, 0);
    final end = index.locate(1)!;
    expect(end.spineIndex, 2);
    expect(end.chapterRatio, 1);
  });

  test('非有限输入和越界输入不会产生非法百分比', () {
    final index = BookProgressIndex.fromUncompressedSizes([100, 100]);
    expect(index.percentOf(-1, 1), 0);
    expect(index.percentOf(99, 0), 1);
    expect(index.percentOf(1, -5), 0.5);
    expect(index.percentOf(1, double.nan), 0.5);
    expect(index.percentOf(1, double.infinity), 1);
    expect(index.locate(double.nan)!.chapterRatio, 0);
    expect(index.locate(double.negativeInfinity)!.spineIndex, 0);
    expect(index.locate(double.infinity)!.chapterRatio, 1);
  });

  test('输入与公开权重不可被调用方修改', () {
    final sizes = <int?>[100, 300];
    final excluded = <int>{};
    final index = BookProgressIndex.fromUncompressedSizes(
      sizes,
      excluded: excluded,
    );
    sizes[0] = 10000;
    excluded.add(0);
    expect(index.percentOf(1, 0), 0.25);
    expect(() => index.chapterWeights[0] = 10000, throwsUnsupportedError);
    expect(() => index.chapterStarts[0] = 10000, throwsUnsupportedError);
    expect(() => index.excluded.add(0), throwsUnsupportedError);
  });

  test('千章元数据的随机比例往返保持同一结果', () {
    final random = Random(7);
    final index = BookProgressIndex.fromUncompressedSizes(
      [for (var spine = 0; spine < 1000; spine++) random.nextInt(50000) + 1],
      excluded: {for (var spine = 0; spine < 1000; spine += 11) spine},
    );
    for (var sample = 0; sample < 1000; sample++) {
      final percent = random.nextDouble();
      final point = index.locate(percent)!;
      expect(index.includes(point.spineIndex), isTrue);
      expect(
        index.percentOf(point.spineIndex, point.chapterRatio),
        closeTo(percent, 1e-12),
      );
    }
  });
}
