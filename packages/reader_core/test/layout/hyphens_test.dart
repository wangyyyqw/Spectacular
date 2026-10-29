import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/text_layout.dart';

/// `hyphens` 断词（CSS hyphens）：软连字符 U+00AD 与自动音节断行。
///
/// Ahem 每字 1em：16px 字号下每字 16 宽。
ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('planSoftBreaks: hyphens:auto 按英文词表插断点并标记连字符', () {
    final plan = TextLayoutEngine.planSoftBreaks(
      text: 'hyphenation',
      hyphens: CssHyphens.auto,
      overflowWrap: CssOverflowWrap.normal,
      wordBreak: CssWordBreak.normal,
      contentWidth: 50,
      style: _style(const {}),
      hyphenAdvance: 8,
    );
    expect(plan.changed, isTrue, reason: '插入了断点');
    expect(plan.text.length, greaterThan(11));
    expect(plan.hyphenPoints, isNotEmpty);
    // 断点后的下标映射回原文：映射单调不减且落在原文范围内。
    for (var i = 1; i < plan.offsets.length; i++) {
      expect(plan.offsets[i], greaterThanOrEqualTo(plan.offsets[i - 1]));
      expect(plan.offsets[i], lessThanOrEqualTo(11));
    }
    expect(plan.originalOffset(plan.offsets.length - 1), 11);
  });

  test('planSoftBreaks: hyphens:none 不产生任何断点', () {
    final plan = TextLayoutEngine.planSoftBreaks(
      text: 'abacada extraordinarily',
      hyphens: CssHyphens.none,
      overflowWrap: CssOverflowWrap.normal,
      wordBreak: CssWordBreak.normal,
      contentWidth: 50,
      style: _style(const {}),
    );
    expect(plan.changed, isFalse);
    expect(plan.text, 'abacada extraordinarily');
    expect(plan.hyphenPoints, isEmpty);
  });

  test('hyphens:manual 认软连字符 U+00AD，断在该处且行尾带连字符', () {
    const text = 'ab\u00ADcdefgh';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(const {'hyphens': 'manual'}),
      maxWidth: 40,
    );
    expect(layout.lineCount, greaterThan(1));
    final first = layout.lines.first;
    expect(first.hyphenated, isTrue, reason: '软连字符处断开');
    expect(first.hyphenWidth, greaterThan(0));
    // 行区间仍是原文坐标：断点处的软连字符可能落在行内（零宽不可见）。
    expect(
      layout.text.substring(first.start, first.end).replaceAll('\u00AD', ''),
      'ab',
    );
  });

  test('hyphens:none 不认软连字符（不产生行尾连字符标记）', () {
    const text = 'ab\u00ADcdefgh';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(const {'hyphens': 'none'}),
      maxWidth: 40,
    );
    expect(layout.lines.any((line) => line.hyphenated), isFalse);
  });

  test('hyphens:auto 让超宽长词断在词内（连字符宽计入行宽）', () {
    const text = 'extraordinary extra';
    final auto = TextLayoutEngine.layout(
      text: text,
      style: _style(const {'hyphens': 'auto'}),
      maxWidth: 40,
    );
    final hyphenated = auto.lines.where((line) => line.hyphenated).toList();
    expect(hyphenated, isNotEmpty);
    for (final line in hyphenated) {
      expect(line.hyphenWidth, greaterThan(0));
      expect(line.width, greaterThan(0));
    }
  });

  test('overflow-wrap:break-word 只给放不下的长词插断点', () {
    final breakWord = TextLayoutEngine.planSoftBreaks(
      text: 'short ABCDEFGHIJKLMNOP',
      hyphens: CssHyphens.none,
      overflowWrap: CssOverflowWrap.breakWord,
      wordBreak: CssWordBreak.normal,
      contentWidth: 40,
      style: _style(const {}),
    );
    expect(breakWord.changed, isTrue, reason: '长词放不下 → 插断点');
    expect(breakWord.hyphenPoints, isEmpty, reason: '不画连字符');

    final fits = TextLayoutEngine.planSoftBreaks(
      text: 'ab cd',
      hyphens: CssHyphens.none,
      overflowWrap: CssOverflowWrap.breakWord,
      wordBreak: CssWordBreak.normal,
      contentWidth: 40,
      style: _style(const {}),
    );
    expect(fits.changed, isFalse, reason: '词都放得下 → 不插断点');
  });
}
