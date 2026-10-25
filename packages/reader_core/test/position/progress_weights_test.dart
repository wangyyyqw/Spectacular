import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/locator.dart';

void main() {
  group('进度权重表（§76.1/§76.2）', () {
    test('章前累计与百分比：中间位置稳定', () {
      final weights = ProgressWeights.fromCharCounts(<int>[100, 200, 300]);
      expect(weights.total, 600);
      expect(weights.charStarts, <int>[0, 100, 300]);
      expect(weights.percentOf(0, charOffsetInChapter: 0), 0);
      expect(weights.percentOf(1, charOffsetInChapter: 100), closeTo(200 / 600, 1e-9));
      expect(weights.percentOf(2, charOffsetInChapter: 300), 1);
      expect(weights.percentInt(1, charOffsetInChapter: 100), 33);
      expect(weights.percentOf10000(1, charOffsetInChapter: 100), 3333);
    });

    test('同一位置重复计算完全一致（稳定性）', () {
      final weights = ProgressWeights.fromCharCounts(<int>[10, 20, 30, 40]);
      final first = weights.percentOf(2, charOffsetInChapter: 15);
      for (var i = 0; i < 20; i++) {
        expect(weights.percentOf(2, charOffsetInChapter: 15), first);
      }
    });

    test('封面页与 linear=no 章排除后不影响分母', () {
      // 0: 封面（无文本），1-2: 正文，3: linear=no。
      final weights = ProgressWeights.fromCharCounts(
        <int>[0, 100, 100, 50],
        excluded: <int>{3},
      );
      expect(weights.total, 200, reason: '被排除章不计入分母');
      expect(weights.percentOf(1), 0, reason: '封面不计入，正文首章即 0%');
      expect(weights.percentOf(2, charOffsetInChapter: 100), 1);
      expect(weights.includes(3), isFalse);
      expect(weights.percentOf(3), 1, reason: '被排除章按章首位置计');
    });

    test('不同封面大小不影响进度（封面无字符）', () {
      final smallCover = ProgressWeights.fromCharCounts(<int>[0, 500]);
      final bigCover = ProgressWeights.fromCharCounts(<int>[0, 500]);
      expect(
        bigCover.percentOf(1, charOffsetInChapter: 250),
        smallCover.percentOf(1, charOffsetInChapter: 250),
      );
    });

    test('越界与负值钳制在 0～1', () {
      final weights = ProgressWeights.fromCharCounts(<int>[100, 100]);
      expect(weights.percentOf(1, charOffsetInChapter: 9999), 1);
      expect(weights.percentOf(1, charOffsetInChapter: -5), 0.5);
      expect(weights.percentOf(99), 1);
      expect(weights.percentOf(-1), 0);
    });

    test('无字符统计时按章等权估算并标记 estimated', () {
      final weights = ProgressWeights.fromCharCounts(<int>[0, 0, 0, 0]);
      expect(weights.estimated, isTrue);
      expect(weights.total, 4);
      expect(weights.percentInt(2), 50);
      expect(weights.totalCharacters, 4);
    });
  });
}
