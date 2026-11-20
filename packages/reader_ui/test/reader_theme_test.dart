import 'dart:ui' show Brightness, Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/theme/reader_theme.dart';

void main() {
  test('保留原有主题，合并相近色后共十二套且正文对比度 ≥4.5:1', () {
    expect(ReaderTheme.themes, hasLength(12));
    expect(
      ReaderTheme.themes.map((theme) => theme.id),
      containsAll(<String>['white', 'sepia', 'pink', 'green', 'black']),
    );
    for (final theme in ReaderTheme.themes) {
      expect(
        theme.luminance,
        greaterThanOrEqualTo(4.5),
        reason: '${theme.name} 主题对比度 ${theme.luminance}',
      );
      expect(theme.background, isNot(theme.text));
      final secondary = ReaderTheme(
        id: 'secondary',
        name: '页眉页脚',
        background: theme.background,
        text: Color.alphaBlend(theme.sub, theme.background),
      );
      expect(
        secondary.luminance,
        greaterThanOrEqualTo(4.5),
        reason: '${theme.name} 页眉页脚对比度',
      );
    }
  });

  test('补充配色来自参考主题，重复及相近色复用原主题', () {
    const backgrounds = <String, int>{
      'white': 0xFFFFFFFF,
      'sepia': 0xFFFDF2E3,
      'pink': 0xFFFCE8EA,
      'green': 0xFFDCEBE1,
      'paper': 0xFFFFFBEB,
      'bamboo': 0xFFF2F7EE,
      'kraft': 0xFFFDF2E3,
      'mist': 0xFFF4F6F8,
      'warm': 0xFF17140F,
      'black': 0xFF000000,
      'inkblue': 0xFF10151F,
      'moss': 0xFF10170F,
      'plum': 0xFF17111A,
    };
    for (final entry in backgrounds.entries) {
      expect(ReaderTheme.byId(entry.key).background, Color(entry.value));
    }
    expect(ReaderTheme.byId('kraft'), same(ReaderTheme.sepia));
    expect(ReaderTheme.byId('gray'), same(ReaderTheme.white));
    expect(ReaderTheme.byId('dark'), same(ReaderTheme.black));
    expect(
      ReaderTheme.themes.map((theme) => theme.background).toSet(),
      hasLength(12),
    );
  });

  test('日夜分组互不重叠，同模式保留配色，跨模式回退对应默认色', () {
    expect(ReaderTheme.dayThemes, hasLength(7));
    expect(ReaderTheme.nightThemes, hasLength(5));
    for (final brightness in Brightness.values) {
      for (final theme in ReaderTheme.themesFor(brightness)) {
        expect(theme.isDark, brightness == Brightness.dark);
        expect(theme.resolveForBrightness(brightness), same(theme));
        expect(theme.resolveForBrightness(null), same(theme));
      }
    }
    expect(
      ReaderTheme.moss.resolveForBrightness(Brightness.light),
      same(ReaderTheme.white),
    );
    expect(
      ReaderTheme.paper.resolveForBrightness(Brightness.dark),
      same(ReaderTheme.black),
    );
  });

  test('主题转成覆盖：正文色与背景色成对', () {
    final overrides = ReaderTheme.black.toOverrides();
    expect(overrides.textColor, ReaderTheme.black.text);
    expect(overrides.backgroundColor, ReaderTheme.black.background);
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
