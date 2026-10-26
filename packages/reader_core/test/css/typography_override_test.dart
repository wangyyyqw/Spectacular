import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';

/// P9-01 回归：阅读器排版覆盖只能改字号/行高/对齐。
///
/// 重建 ComputedStyle 会把非继承属性（背景色/背景图/边框/内外边距）归零，
/// 书籍的卡片、面板与外框会整块消失。
void main() {
  ComputedStyle panel() => ComputedStyle(const <String, String>{
    'font-size': '15px',
    'line-height': '1.5',
    'color': '#cbd5e1',
    'background-color': 'rgba(13, 19, 31, 0.8)',
    'background-image': 'url("OEBPS/Images/panel.png")',
    'background-size': 'cover',
    'background-repeat': 'no-repeat',
    'border-left': '3px solid #e2b867',
    'border-top': '1px solid #283652',
    'padding': '10px 14px',
    'margin': '10px auto',
  });

  test('applyTypography 保留背景/边框/内外边距', () {
    const overrides = ReaderOverrides(fontSize: 17, lineHeight: 1.6);
    final base = panel();
    final after = overrides.applyTypography(base);

    expect(after.backgroundColor.a, closeTo(0.8, 0.001));
    expect(after.backgroundImage, 'OEBPS/Images/panel.png');
    expect(after.backgroundSize.mode, CssBackgroundSizeMode.cover);
    expect(after.backgroundRepeat, CssBackgroundRepeat.noRepeat);
    expect(after.borders.left.width, 3);
    expect(after.borders.top.width, 1);
    expect(after.padding.left, 14);
    expect(after.padding.top, 10);
    expect(after.margin.top, 10);

    expect(after.fontSize, 17);
    expect(after.lineHeight, closeTo(17 * 1.6, 0.001));
  });

  test('applyTypography 同时覆盖对齐且不动颜色', () {
    const overrides = ReaderOverrides(
      fontSize: 20,
      lineHeight: 2.0,
      textAlign: CssTextAlign.center,
    );
    final after = overrides.applyTypography(panel());
    expect(after.textAlign, CssTextAlign.center);
    expect(after.fontSize, 20);
    expect(after.lineHeight, closeTo(40, 0.001));
    expect(after.color, const Color(0xFFCBD5E1));
  });

  test('无设置时原样返回', () {
    final base = panel();
    expect(const ReaderOverrides().applyTypography(base), same(base));
  });
}
