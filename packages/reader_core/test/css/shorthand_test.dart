import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';

/// P9 回归：`font` 简写展开与 -webkit- 对齐值。
void main() {
  ComputedStyle style(Map<String, String> declarations) =>
      ComputedStyle(declarations);

  test('font 简写展开字号/行高/字重/斜体/字族', () {
    final parsed = style(const <String, String>{
      'font': 'italic bold 20px/2 "宋体", serif',
    });
    expect(parsed.fontSize, 20);
    expect(parsed.lineHeightFactor, 2);
    expect(parsed.lineHeight, 40);
    expect(parsed.fontWeight, 700);
    expect(parsed.italic, isTrue);
    expect(parsed.fontFamily, '宋体');
    expect(parsed.fontFamilyFallback, contains('serif'));
  });

  test('font 简写不覆盖已声明的长属性', () {
    final parsed = style(const <String, String>{
      'font': 'bold 20px serif',
      'font-size': '14px',
    });
    expect(parsed.fontSize, 14);
    expect(parsed.fontWeight, 700);
  });

  test('font 简写支持无行高的百分比字号与系统关键字丢弃', () {
    final parsed = style(const <String, String>{'font': '120% serif'});
    expect(parsed.fontSize, greaterThan(0));
    final keyword = style(const <String, String>{'font': 'caption'});
    expect(keyword.fontSize, 16, reason: '系统关键字不支持时保持初始值');
  });

  test('-webkit-center 等对齐值映射', () {
    expect(
      style(const <String, String>{'text-align': '-webkit-center'}).textAlign,
      CssTextAlign.center,
    );
    expect(
      style(const <String, String>{'text-align': '-webkit-right'}).textAlign,
      CssTextAlign.right,
    );
  });
}
