import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

TextLayoutResult _layout(String text, ComputedStyle style) =>
    TextLayoutEngine.layout(text: text, style: style, maxWidth: 600);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('letter-spacing 宽度增量与设定值一致', () {
    final plain = _layout('abc', _style(const {}));
    final spaced = _layout('abc', _style(const {'letter-spacing': '8px'}));
    // Flutter 在每个字符后加字距（含末字符），3 字符 → 3 × 8。
    expect(spaced.width - plain.width, closeTo(24, 0.01));
  });

  test('word-spacing 宽度增量等于空格数的倍数', () {
    final plain = _layout('a b c', _style(const {}));
    final spaced = _layout('a b c', _style(const {'word-spacing': '10px'}));
    expect(spaced.width - plain.width, closeTo(20, 0.01), reason: '两个空格 × 10');
  });

  test('text-transform 变换测量文本', () {
    expect(
      _layout('AbC', _style(const {'text-transform': 'uppercase'})).text,
      'ABC',
    );
    expect(
      _layout('AbC', _style(const {'text-transform': 'lowercase'})).text,
      'abc',
    );
    expect(
      _layout('ab cd', _style(const {'text-transform': 'capitalize'})).text,
      'Ab Cd',
    );
    expect(_style(const {}).textTransform, CssTextTransform.none);
  });

  test('vertical-align 基线偏移：按父字号 1/3、1/5（Chrome 口径）', () {
    // 根样式 parentFontSize = rootFontSize = 16：super = -(16/3+1) = -6.33，
    // sub = 16/5+1 = 4.2（对齐 Chromium 的字体 ascent/3、ascent/5）。
    expect(
      _style(const {'vertical-align': 'super'}).verticalAlignShift,
      closeTo(-(16 / 3 + 1), 0.01),
    );
    expect(
      _style(const {'vertical-align': 'sub'}).verticalAlignShift,
      closeTo(16 / 5 + 1, 0.01),
    );
    expect(_style(const {'vertical-align': 'baseline'}).verticalAlignShift, 0);
    expect(_style(const {'vertical-align': 'middle'}).verticalAlignShift, 0);
  });

  test('word-spacing 与 text-transform 继承，vertical-align 不继承', () {
    final parent = _style(const {
      'word-spacing': '5px',
      'text-transform': 'uppercase',
      'vertical-align': 'super',
    });
    final child = ComputedStyle(
      const {'color': '#FF0000'},
      parent: parent,
      explicitProperties: const {'color'},
      containingWidth: 0,
    );
    expect(child.wordSpacing, 5);
    expect(child.textTransform, CssTextTransform.uppercase);
    expect(child.verticalAlign, CssVerticalAlign.baseline);
  });
}
