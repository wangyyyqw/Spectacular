import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';

ComputedStyle _bookStyle() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'serif',
  'color': '#112233',
  'text-align': 'left',
  'text-indent': '2em',
});

void main() {
  group('覆盖层优先级（P2-22）', () {
    test('设置值覆盖书籍声明，未设置项继续继承', () {
      final base = _bookStyle();
      final applied = const ReaderOverrides(
        fontSize: 20,
        lineHeight: 1.8,
        textAlign: CssTextAlign.justify,
        textColor: Color(0xFF445566),
      ).apply(base);

      expect(applied.fontSize, 20);
      expect(applied.lineHeight / applied.fontSize, closeTo(1.8, 0.001));
      expect(applied.textAlign, CssTextAlign.justify);
      expect(applied.color, const Color(0xFF445566));
      // 书籍声明的其它属性保留。
      // text-indent 是继承属性：父级 2em 已算成 32px，覆盖层不重新解算。
      expect(applied.textIndent, closeTo(32, 0.01));
      expect(applied.fontFamilies, base.fontFamilies);
    });

    test('空设置不改变书籍样式', () {
      final base = _bookStyle();
      expect(const ReaderOverrides().apply(base), same(base));
      expect(const ReaderOverrides().isEmpty, isTrue);
    });

    test('页边距写进 padding 声明', () {
      final applied = const ReaderOverrides(
        padding: CssEdges(top: 10, right: 20, bottom: 30, left: 40),
      ).apply(_bookStyle());
      expect(applied.padding.top, 10);
      expect(applied.padding.right, 20);
      expect(applied.padding.bottom, 30);
      expect(applied.padding.left, 40);
    });
  });

  group('CSS 声明与指纹', () {
    test('声明映射', () {
      final values = const ReaderOverrides(
        fontSize: 18,
        lineHeight: 1.6,
        textAlign: CssTextAlign.center,
        padding: CssEdges(top: 1, right: 2, bottom: 3, left: 4),
        textColor: Color(0xFF112233),
        backgroundColor: Color(0xFFFFFFFF),
      ).toCssDeclarations();

      expect(values['font-size'], '18px');
      expect(values['line-height'], '1.6');
      expect(values['text-align'], 'center');
      expect(values['padding-top'], '1px');
      expect(values['padding-left'], '4px');
      expect(values['color'], '#112233');
      expect(values['background-color'], '#ffffff');
    });

    test('指纹只含排版相关字段', () {
      const a = ReaderOverrides(fontSize: 18);
      const b = ReaderOverrides(fontSize: 18, textColor: Color(0xFF000000));
      expect(a.fingerprint, b.fingerprint, reason: '颜色不参与布局指纹');

      const c = ReaderOverrides(fontSize: 19);
      expect(c.fingerprint, isNot(a.fingerprint));
      const d = ReaderOverrides(
        padding: CssEdges(top: 8, right: 8, bottom: 8, left: 8),
      );
      expect(d.fingerprint, isNot(a.fingerprint));
    });
  });
}
