import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';

import 'support/css_chapter_book.dart';

/// 多看/掌阅/WebKit 私有属性映射（P9-28）。
///
/// 两层断言：
/// 1. 解析入口把私有属性名改写成标准属性名（[CssParser.parse]）；
/// 2. 改名后的声明真的进了计算样式（章节目录走完整管线）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('解析入口改名', () {
    String propertyOf(String declaration) {
      final sheet = CssParser.parse('p { $declaration }');
      return sheet.rules.single.declarations.single.property;
    }

    String valueOf(String declaration) {
      final sheet = CssParser.parse('p { $declaration }');
      return sheet.rules.single.declarations.single.value;
    }

    const cases = <String, String>{
      // 既定映射（回归）。
      'duokan-text-indent': 'text-indent',
      '-duokan-text-indent': 'text-indent',
      'duokan-paragraph-align': 'text-align',
      'duokan-line-height': 'line-height',
      'duokan-text-fill': 'color',
      'duokan-margin-before': 'margin-top',
      // 着重号族：多看与 -webkit- 旧语法。
      'duokan-text-emphasis': 'text-emphasis',
      'duokan-text-emphasis-style': 'text-emphasis-style',
      'duokan-text-emphasis-color': 'text-emphasis-color',
      'duokan-text-emphasis-position': 'text-emphasis-position',
      '-webkit-text-emphasis': 'text-emphasis',
      '-webkit-text-emphasis-style': 'text-emphasis-style',
      '-webkit-text-emphasis-color': 'text-emphasis-color',
      '-webkit-text-emphasis-position': 'text-emphasis-position',
      '-epub-text-emphasis': 'text-emphasis',
      // 断行严格度。
      'duokan-line-break': 'line-break',
      '-webkit-line-break': 'line-break',
      // 排版方向族：text-orientation 不能并进 writing-mode。
      'duokan-writing-mode': 'writing-mode',
      'duokan-text-orientation': 'text-orientation',
      'epub-text-orientation': 'text-orientation',
      '-webkit-writing-mode': 'writing-mode',
      // 真实书里出现过的其余私有属性。
      '-epub-hyphens': 'hyphens',
      '-webkit-text-combine': 'text-combine-upright',
      // 真实书（7 本语料）里出现过的其余私有属性，逐个保证有映射：
      // duokan-letter-spacing / duokan-block-progression / duokan-text-orientation
      // 等已在上面覆盖，这里补齐语料里剩下的几种写法。
      'duokan-text-shadow': 'text-shadow',
      'duokan-text-decoration': 'text-decoration',
      'duokan-font-weight': 'font-weight',
      'duokan-padding-before': 'padding-top',
      'duokan-padding-after': 'padding-bottom',
      'duokan-page-break-inside': 'page-break-inside',
      'duokan-page-break-before': 'page-break-before',
      'duokan-page-break-after': 'page-break-after',
      // WebKit 逻辑边距：按逻辑属性映射（受 direction/writing-mode 影响），
      // 横排 LTR 下落到 margin-left/right。
      '-webkit-margin-start': 'margin-inline-start',
      '-webkit-margin-end': 'margin-inline-end',
    };

    cases.forEach((private, standard) {
      test('$private → $standard', () {
        expect(propertyOf('$private: 1'), standard);
      });
    });

    test('writing-mode 族的非标准取值被规整', () {
      expect(valueOf('duokan-writing-orientation: vertical'), 'vertical-rl');
      expect(valueOf('duokan-writing-mode: horizontal'), 'horizontal-tb');
      // 多看块级推进方向折成标准竖排取值。
      expect(valueOf('duokan-block-progression: rl'), 'vertical-rl');
      expect(valueOf('duokan-block-progression: lr'), 'vertical-lr');
      expect(valueOf('duokan-block-progression: tb'), 'horizontal-tb');
      expect(valueOf('duokan-writing-mode: vertical-rl'), 'vertical-rl');
    });
  });

  group('章节管线里生效', () {
    Future<Map<String, ComputedStyle>> styles(String body, String css) async {
      final source = await openCssChapter(
        body: body,
        css: css,
        contentWidth: 300,
        contentHeight: 500,
      );
      final pages = await source.loadChapter(0);
      final result = <String, ComputedStyle>{};
      for (final slice in pages.expand((page) => page.slices)) {
        final style = slice.block.style;
        if (style == null) {
          continue;
        }
        result.putIfAbsent(
          slice.block.layout.text.split('\n').first.split(' ').first,
          () => style,
        );
      }
      return result;
    }

    test('着重号族（多看/WebKit）写进计算样式', () async {
      final parsed = await styles(
        '<p class="e">着重:文本</p><p class="w">webkit:文本</p>',
        '.e { duokan-text-emphasis-style: dot; '
            'duokan-text-emphasis-color: #ff0000; '
            'duokan-text-emphasis-position: under; } '
            '.w { -webkit-text-emphasis: filled circle; }',
      );
      final duokan = parsed['着重:文本']!;
      expect(duokan.textEmphasisStyle, CssTextEmphasisStyle.dot);
      expect(duokan.textEmphasisColor, const Color(0xFFFF0000));
      expect(duokan.textEmphasisPosition, CssTextEmphasisPosition.under);
      expect(
        parsed['webkit:文本']!.textEmphasisStyle,
        CssTextEmphasisStyle.circle,
      );
    });

    test('缩进/断行/断词私有属性写进计算样式', () async {
      final parsed = await styles(
        '<p class="c">属性:文本</p>',
        '.c { duokan-text-indent: 2em; duokan-line-break: strict; '
            '-epub-hyphens: auto; }',
      );
      final style = parsed['属性:文本']!;
      expect(style.textIndent, 32);
      expect(style.values['line-break'], 'strict');
      expect(style.values['hyphens'], 'auto');
    });

    test('排版方向族：upright 不覆盖 vertical-rl', () async {
      final parsed = await styles(
        '<p class="v">竖排:文本</p>',
        '.v { duokan-writing-mode: vertical-rl; '
            'duokan-text-orientation: upright; '
            'duokan-writing-orientation: vertical; '
            'duokan-block-progression: rl; }',
      );
      final style = parsed['竖排:文本']!;
      // 真实书（zhushen-yuxi.epub）的声明顺序：text-orientation 与
      // writing-orientation 在 writing-mode 之后，映射错就会把横排打回来。
      expect(style.values['writing-mode'], 'vertical-rl');
      expect(style.values['text-orientation'], 'upright');
    });

    test('WebKit 逻辑边距落到左右外边距', () async {
      final parsed = await styles(
        '<p class="m">边距:文本</p>',
        '.m { -webkit-margin-start: 24px; }',
      );
      expect(parsed['边距:文本']!.margin.left, 24);
    });
  });
}
