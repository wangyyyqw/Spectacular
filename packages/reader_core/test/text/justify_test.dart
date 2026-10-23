import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/text/justify.dart';
import 'package:reader_core/text/script.dart';

void main() {
  group('CJK 判定', () {
    test('ASCII 不算 CJK', () {
      expect(containsCjk('abc123'), isFalse);
      expect(isCjkCodePoint(0x41), isFalse);
      expect(isCjkCodePoint(0x20), isFalse);
    });

    test('汉字、假名、谚文、全角标点算 CJK', () {
      for (final rune in ['中', 'あ', 'ア', '한', '，', '。', '、']) {
        expect(containsCjk(rune), isTrue, reason: rune);
      }
    });

    test('扩展区汉字算 CJK', () {
      expect(containsCjk('𠀀'), isTrue, reason: '扩展 B');
      expect(containsCjk('㐀'), isTrue, reason: '扩展 A');
    });
  });

  group('可拉伸间隙', () {
    test('纯中文 20 字得到 19 个间隙', () {
      const text = '一二三四五六七八九十一二三四五六七八九十';
      expect(text.runes.length, 20);
      expect(justifyGapOffsets(text), hasLength(19));
    });

    test('中英混排跳过拉丁词内部间隙', () {
      // 中(0)文(1)a(2)b(3)c(4)测(5)试(6)
      expect(justifyGapOffsets('中文abc测试'), <int>[0, 1, 4, 5]);
    });

    test('末字之后没有间隙', () {
      expect(justifyGapOffsets('中文'), <int>[0]);
      expect(justifyGapOffsets('中'), isEmpty);
      expect(justifyGapOffsets(''), isEmpty);
    });

    test('含换行的间隙跳过', () {
      expect(justifyGapOffsets('中文\n对齐'), <int>[0, 3]);
    });

    test('西文行只拉伸词间空格', () {
      expect(justifyGapOffsets('ab cd ef'), <int>[2, 5]);
      expect(justifyGapOffsets('abcdef'), isEmpty);
      expect(justifyGapOffsets('ab\ncd'), isEmpty);
    });

    test('单字符行无间隙', () {
      expect(justifyGapOffsets('a'), isEmpty);
    });
  });
}
