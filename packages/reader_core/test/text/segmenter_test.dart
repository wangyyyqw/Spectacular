import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/text/segmenter.dart';

void main() {
  group('取词（§40.2）', () {
    test('CJK 连续段是一个词', () {
      const text = '他在诡异世界开了家餐厅。';
      final range = TextSegmenter.wordRangeAt(text, 3); // 「世」
      expect(text.substring(range.start, range.end), '他在诡异世界开了家餐厅');
    });

    test('拉丁字母数字连续段是一个词', () {
      const text = '用 epub3 格式打包';
      final range = TextSegmenter.wordRangeAt(text, 6); // 「u」
      expect(text.substring(range.start, range.end), 'epub3');
    });

    test('标点与空白单独成词', () {
      const text = '好。';
      final range = TextSegmenter.wordRangeAt(text, 1);
      expect(text.substring(range.start, range.end), '。');
    });

    test('偏移等于长度时取最后一个字符的词', () {
      const text = 'abc';
      final range = TextSegmenter.wordRangeAt(text, 3);
      expect(text.substring(range.start, range.end), 'abc');
    });

    test('空文本返回空区间', () {
      expect(TextSegmenter.wordRangeAt('', 0).isEmpty, isTrue);
    });
  });

  group('切句（§40.2）', () {
    test('按句末标点切句，后引号归前一句', () {
      const text = '他说：“你来了。”我回答：“是的。”';
      final first = TextSegmenter.sentenceRangeAt(text, 2);
      expect(text.substring(first.start, first.end), '他说：“你来了。”');
      final second = TextSegmenter.sentenceRangeAt(text, 12);
      expect(text.substring(second.start, second.end), '我回答：“是的。”');
    });

    test('感叹号与问号也是句界', () {
      const text = '真的吗？太好了！走吧';
      final a = TextSegmenter.sentenceRangeAt(text, 0);
      expect(text.substring(a.start, a.end), '真的吗？');
      final b = TextSegmenter.sentenceRangeAt(text, 4);
      expect(text.substring(b.start, b.end), '太好了！');
      final c = TextSegmenter.sentenceRangeAt(text, 8);
      expect(text.substring(c.start, c.end), '走吧');
    });

    test('换行也是句界', () {
      const text = '第一行\n第二行';
      final a = TextSegmenter.sentenceRangeAt(text, 1);
      expect(text.substring(a.start, a.end), '第一行');
      final b = TextSegmenter.sentenceRangeAt(text, 5);
      expect(text.substring(b.start, b.end), '第二行');
    });

    test('省略号连写按一个句末处理（§40.2 把 … 列为句末标点）', () {
      const text = '他想了很久……然后走了。';
      final first = TextSegmenter.sentenceRangeAt(text, 2);
      expect(text.substring(first.start, first.end), '他想了很久……');
      final second = TextSegmenter.sentenceRangeAt(text, text.length - 2);
      expect(text.substring(second.start, second.end), '然后走了。');
    });

    test('无句末标点时整行为一句', () {
      const text = '没有标点的一行字';
      final range = TextSegmenter.sentenceRangeAt(text, 3);
      expect(text.substring(range.start, range.end), text);
    });
  });
}
