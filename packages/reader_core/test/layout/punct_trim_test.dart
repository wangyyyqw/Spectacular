import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/punct_trim.dart';
import 'package:reader_core/layout/text_layout.dart';

/// P7-19：标点挤压——相邻全角标点的前标点加 -0.5em 字距；
/// `text-spacing-trim: trim-adjacent` 启用，默认 normal 与现状一致；
/// 比例字体（advance < 0.9em）逐对跳过。
void main() {
  group('punctCompressionOffsets 纯函数', () {
    const text = '「你好」，他说。';
    test('全角字形：相邻标点对计入（」，）', () {
      final offsets = punctCompressionOffsets(
        text,
        em: 16,
        advanceOf: (char) => 16, // Ahem 全宽。
      );
      // 」（index 3）与 ，（index 4）相邻 → 前标点 」 偏移 3。
      expect(offsets, <int>[3]);
    });

    test('比例字形守卫：advance < 0.9em 跳过该对', () {
      final offsets = punctCompressionOffsets(
        text,
        em: 16,
        advanceOf: (char) => char == '」' ? 8 : 16, // 」为比例字形。
      );
      expect(offsets, isEmpty, reason: '前标点非整格字形时不挤压');
    });

    test('非相邻标点不计入', () {
      final offsets = punctCompressionOffsets(
        '，他说。你好',
        em: 16,
        advanceOf: (char) => 16,
      );
      expect(offsets, isEmpty);
    });
  });

  group('测量集成（TextLayoutEngine）', () {
    final normal = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final trimmed = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'text-spacing-trim': 'trim-adjacent',
    });

    test('挤压后行宽收窄一个半角（0.5em）', () {
      const text = '「你好」，他说。';
      final plain = TextLayoutEngine.layout(
        text: text,
        style: normal,
        maxWidth: 400,
      );
      final compressed = TextLayoutEngine.layout(
        text: text,
        style: trimmed,
        maxWidth: 400,
      );
      expect(plain.lineCount, 1);
      expect(compressed.lineCount, 1);
      expect(
        compressed.lines.single.width,
        closeTo(plain.lines.single.width - 8, 0.01),
        reason: '一对挤压 = -0.5em = -8px',
      );
    });

    test('默认 normal 输出与现状一致', () {
      const text = '「你好」，他说。';
      final plain = TextLayoutEngine.layout(
        text: text,
        style: normal,
        maxWidth: 400,
      );
      expect(plain.lines.single.width, 8 * 16.0);
    });

    test('text-spacing-trim 解析与继承', () {
      expect(trimmed.textSpacingTrim, CssTextSpacingTrim.trimAdjacent);
      expect(normal.textSpacingTrim, CssTextSpacingTrim.normal);
      expect(
        _parse('space-all'),
        CssTextSpacingTrim.normal,
      );
      expect(_parse('trim-start'), CssTextSpacingTrim.normal);
      final child = ComputedStyle(
        const <String, String>{'color': 'red'},
        parent: trimmed,
        explicitProperties: const <String>{'color'},
      );
      expect(child.textSpacingTrim, CssTextSpacingTrim.trimAdjacent);
    });
  });

  group('分页集成', () {
    test('挤压影响分页几何（可用宽内放下更多内容不崩溃）', () {
      final normal = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': 'Ahem',
      });
      final trimmed = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': 'Ahem',
        'text-spacing-trim': 'trim-adjacent',
      });
      const text = '「你好」，「他说」，「她说」，「大家都说」。';
      PageBlock blockOf(ComputedStyle style) {
        final layout = TextLayoutEngine.layout(
          text: text,
          style: style,
          maxWidth: 128,
        );
        return PageBlock.styled(
          layout: layout,
          style: style,
          containingWidth: 128,
        );
      }

      final normalResult = Paginator(
        pageHeight: 200,
      ).measureChapter(blocks: <PageBlock>[blockOf(normal)]);
      final trimmedResult = Paginator(
        pageHeight: 200,
      ).measureChapter(blocks: <PageBlock>[blockOf(trimmed)]);
      expect(normalResult.pages, isNotEmpty);
      expect(trimmedResult.pages, isNotEmpty);
      // 挤压收窄行宽 → 同宽下块高不增（页数不增）。
      expect(
        trimmedResult.pages.length,
        lessThanOrEqualTo(normalResult.pages.length),
      );
    });
  });
}

CssTextSpacingTrim _parse(String value) => ComputedStyle(<String, String>{
  'font-size': '16px',
  'text-spacing-trim': value,
}).textSpacingTrim;
