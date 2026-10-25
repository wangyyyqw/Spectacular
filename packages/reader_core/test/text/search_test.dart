import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/text/search.dart';

void main() {
  group('2-gram 切分（§66.2）', () {
    test('中文逐字两两切，offset 对应原文位置', () {
      final grams = SearchTokenizer.gramsOf('你好世界');
      expect(grams.map((g) => g.gram), <String>['你好', '好世', '世界']);
      expect(grams.map((g) => g.offset), <int>[0, 1, 2]);
    });

    test('单个中文不产生 gram', () {
      expect(SearchTokenizer.gramsOf('你'), isEmpty);
    });

    test('英文按词切，词内两两切，不跨词', () {
      final grams = SearchTokenizer.gramsOf('hello world');
      expect(
        grams.map((g) => g.gram),
        <String>['he', 'el', 'll', 'lo', 'wo', 'or', 'rl', 'ld'],
      );
      expect(grams[4].offset, 6, reason: 'world 从偏移 6 开始');
    });

    test('数字整串作为一个 gram', () {
      final grams = SearchTokenizer.gramsOf('第2026章');
      expect(grams.map((g) => g.gram), <String>['2026'], reason: '单字不产生 gram');
      expect(grams.single.offset, 1);
    });

    test('标点与空白是分隔符，不产生 gram', () {
      final grams = SearchTokenizer.gramsOf('你好，世界。');
      expect(grams.map((g) => g.gram), <String>['你好', '世界']);
    });

    test('中英混排：各自切分，边界不跨类', () {
      final grams = SearchTokenizer.gramsOf('中文abc');
      expect(grams.map((g) => g.gram), <String>['中文', 'ab', 'bc']);
    });

    test('查询词去重（同 gram 只查一次）', () {
      expect(
        SearchTokenizer.queryGrams('哈哈'),
        <String>['哈哈'],
        reason: '同一 gram 只保留一次',
      );
      expect(SearchTokenizer.queryGrams('世界'), <String>['世界']);
    });

    test('空文本无 gram', () {
      expect(SearchTokenizer.gramsOf(''), isEmpty);
      expect(SearchTokenizer.queryGrams(''), isEmpty);
    });
  });
}
