import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/theme/reader_theme.dart';

void main() {
  test('五套主题齐全且正文对比度 ≥4.5:1', () {
    expect(ReaderTheme.themes, hasLength(5));
    expect(
      ReaderTheme.themes.map((theme) => theme.id),
      containsAll(<String>['white', 'sepia', 'gray', 'dark', 'black']),
    );
    for (final theme in ReaderTheme.themes) {
      expect(
        theme.luminance,
        greaterThanOrEqualTo(4.5),
        reason: '${theme.name} 主题对比度 ${theme.luminance}',
      );
      expect(theme.background, isNot(theme.text));
    }
  });

  test('主题转成覆盖：正文色与背景色成对', () {
    final overrides = ReaderTheme.dark.toOverrides();
    expect(overrides.textColor, ReaderTheme.dark.text);
    expect(overrides.backgroundColor, ReaderTheme.dark.background);
    expect(overrides.fontSize, isNull, reason: '主题不改变排版');
  });

  test('byId 未知 id 回退白色', () {
    expect(ReaderTheme.byId('sepia'), same(ReaderTheme.sepia));
    expect(ReaderTheme.byId('unknown'), same(ReaderTheme.white));
  });

  test('切换主题不改变布局指纹（无需重新分页）', () {
    final before = ReaderTheme.white.toOverrides();
    final after = ReaderTheme.black.toOverrides();
    expect(after.fingerprint, before.fingerprint);
  });

  test('亮度计算符合 WCAG 阈值样例', () {
    // 白/黑对比度 = 21:1。
    const white = ReaderTheme(
      id: 'w',
      name: 'w',
      background: Color(0xFFFFFFFF),
      text: Color(0xFF000000),
    );
    expect(white.luminance, closeTo(21, 0.01));
  });
}
