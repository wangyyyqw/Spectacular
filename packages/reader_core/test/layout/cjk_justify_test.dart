import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/cjk_justify.dart';
import 'package:reader_core/text/script.dart';

void main() {
  group('CJK 判定口径（P2-19 修正 isCjk 范围）', () {
    test('ASCII 与半角标点不算 CJK', () {
      expect(containsCjk('abc123'), isFalse);
      expect(containsCjk('a.b,c!'), isFalse);
      expect(isCjkCodePoint(0x41), isFalse);
      expect(isCjkCodePoint(0x2E), isFalse);
    });

    test('汉字、假名、谚文、全角标点算 CJK', () {
      for (final rune in ['中', 'あ', 'ア', '한', '，', '。', '、', '　']) {
        expect(containsCjk(rune), isTrue, reason: rune);
      }
    });

    test('扩展区汉字算 CJK', () {
      expect(containsCjk('𠀀'), isTrue);
      expect(containsCjk('㐀'), isTrue);
    });
  });

  group('可分配 gap（§8.4）', () {
    test('纯中文 20 字 → 19 个 gap', () {
      const text = '一二三四五六七八九十一二三四五六七八九十';
      expect(text.runes.length, 20);
      final gaps = cjkJustifyGapOffsets(text);
      expect(gaps, hasLength(19));
      expect(gaps, List<int>.generate(18, (i) => i) + [18]);
    });

    test('中英混排按规则扣除拉丁词内部间隙', () {
      // 16 字：中文 + English（7 字母）+ 混排测试继续排
      const text = '中文English混排测试继续排';
      expect(text.runes.length, 16);
      final gaps = cjkJustifyGapOffsets(text);
      expect(gaps, <int>[0, 1, 8, 9, 10, 11, 12, 13, 14]);
      expect(gaps, hasLength(9));
    });

    test('标点边界：CJK 标点与其相邻字符可拉伸', () {
      // 中(0)文(1)，(2)测(3)试(4)。(5)
      expect(cjkJustifyGapOffsets('中文，测试。'), <int>[0, 1, 2, 3, 4]);
      // 全角引号不在 CJK 区块，但仍非拉丁字母，边界可拉伸
      expect(cjkJustifyGapOffsets('“中文”'), <int>[0, 1, 2]);
    });

    test('末字之后没有 gap', () {
      expect(cjkJustifyGapOffsets('中文'), <int>[0]);
      expect(cjkJustifyGapOffsets('中'), isEmpty);
      expect(cjkJustifyGapOffsets(''), isEmpty);
    });

    test('含换行的间隙跳过', () {
      expect(cjkJustifyGapOffsets('中文\n对齐'), <int>[0, 3]);
    });

    test('代理对按代码单元计偏移', () {
      // 中(0) 𠀀(1..2) 文(3)：gap 偏移取「左侧字符起始代码单元」
      expect(cjkJustifyGapOffsets('中𠀀文'), <int>[0, 1]);
    });

    test('CJK 与拉丁/数字相邻可拉伸，拉丁内部不拉伸', () {
      expect(cjkJustifyGapOffsets('中文abc测试'), <int>[0, 1, 4, 5]);
      expect(cjkJustifyGapOffsets('中a'), <int>[0]);
      expect(cjkJustifyGapOffsets('a中'), <int>[0]);
      expect(cjkJustifyGapOffsets('12中'), <int>[1]);
      expect(cjkJustifyGapOffsets('中1'), <int>[0]);
    });

    test('西文行只拉伸词间空格', () {
      expect(cjkJustifyGapOffsets('ab cd ef'), <int>[2, 5]);
      expect(cjkJustifyGapOffsets('abcdef'), isEmpty);
      expect(cjkJustifyGapOffsets('ab\ncd'), isEmpty);
      expect(cjkJustifyGapOffsets('a.b,c'), isEmpty);
    });

    test('单字符行无 gap', () {
      expect(cjkJustifyGapOffsets('a'), isEmpty);
      expect(cjkJustifyGapOffsets('中'), isEmpty);
    });
  });

  group('justify 行判定（与布局接线）', () {
    test('拉丁词内部不加字距：英文单词行无 gap', () {
      expect(cjkJustifyGapOffsets('English'), isEmpty);
      expect(cjkJustifyGapOffsets('English words'), <int>[7]);
    });

    test('混排行 gap 数等于可拉伸位置数', () {
      const text = '第一章ChapterOne导读';
      final gaps = cjkJustifyGapOffsets(text);
      expect(gaps, isNotEmpty);
      // 每个 gap 都落在非拉丁-拉丁相邻处
      for (final offset in gaps) {
        expect(offset + 1 < text.length, isTrue);
        final left = text.codeUnitAt(offset);
        final right = text.codeUnitAt(offset + 1);
        expect(left == 0x0A || right == 0x0A, isFalse);
        expect(
          isJustifyWordCodePoint(left) && isJustifyWordCodePoint(right),
          isFalse,
          reason: '拉丁词内部的间隙不应出现',
        );
      }
    });
  });
}
