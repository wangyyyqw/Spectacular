import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/parser/document_parser.dart';

const _xhtml = '''
<html><body><div id="parent"><p id="p">text</p></div></body></html>
''';

void main() {
  final document = DocumentParser.parse(xhtml: _xhtml, spineIndex: 0);
  ParsedElement el(String id) => document.elementById(id)!;

  final paths = <String, List<ParsedElement>>{};
  void walk(ParsedElement element, List<ParsedElement> path) {
    final id = element.id;
    if (id != null) {
      paths[id] = List<ParsedElement>.unmodifiable(path);
    }
    for (final child in element.children.whereType<ParsedElement>()) {
      walk(child, <ParsedElement>[...path, element]);
    }
  }

  walk(document.root, const <ParsedElement>[]);

  ComputedStyle style(
    String id,
    String css, {
    ComputedStyle? parent,
    double rootFontSize = 16,
    double containingWidth = 0,
  }) {
    final sheet = CssParser.parse(css);
    return Cascade.compute(
      element: el(id),
      ancestors: paths[id]!,
      rules: [
        for (var i = 0; i < sheet.rules.length; i++)
          CascadeRule(
            rule: sheet.rules[i],
            origin: CascadeOrigin.author,
            order: i,
          ),
      ],
      parent: parent,
      rootFontSize: rootFontSize,
      containingWidth: containingWidth,
    );
  }

  test('初始值表', () {
    final initial = ComputedStyle(const <String, String>{});
    expect(initial.fontSize, 16);
    expect(initial.lineHeight, 24);
    expect(initial.lineHeightFactor, 1.5);
    expect(initial.color, const Color(0xFF000000));
    expect(initial.fontWeight, 400);
    expect(initial.italic, isFalse);
    expect(initial.textAlign, CssTextAlign.start);
    expect(initial.textIndent, 0);
    expect(initial.letterSpacing, 0);
    expect(initial.margin.top, 0);
    expect(initial.margin.left, 0);
  });

  test('font-size 的 px/em/%/pt/rem 换算', () {
    final parent = style('parent', 'div { font-size: 20px; }');
    expect(parent.fontSize, 20);
    expect(style('p', 'p { font-size: 2em; }', parent: parent).fontSize, 40);
    expect(style('p', 'p { font-size: 150%; }', parent: parent).fontSize, 30);
    expect(style('p', 'p { font-size: 12pt; }', parent: parent).fontSize, 16);
    expect(style('p', 'p { font-size: 24px; }', parent: parent).fontSize, 24);
    expect(style('p', 'p { font-size: 2rem; }', parent: parent).fontSize, 32);
  });

  test('line-height 倍数/百分比/长度换算', () {
    final base = style('p', 'p { font-size: 20px; }');
    expect(
      style('p', 'p { font-size: 20px; line-height: 1.5; }').lineHeight,
      30,
    );
    expect(
      style('p', 'p { font-size: 20px; line-height: 150%; }').lineHeight,
      30,
    );
    expect(
      style('p', 'p { font-size: 20px; line-height: 2em; }').lineHeight,
      40,
    );
    expect(
      style('p', 'p { font-size: 20px; line-height: 30px; }').lineHeight,
      30,
    );
    expect(base.lineHeightFactor, 1.5);
  });

  test('margin 四值/百分比/pt/覆盖', () {
    final result = style(
      'p',
      'p { font-size: 20px; margin: 1em 10% 2pt auto; }',
      containingWidth: 300,
    );
    expect(result.margin.top, 20);
    expect(result.margin.right, 30);
    expect(result.margin.bottom, closeTo(2.6667, 0.001));
    expect(result.margin.left, 0);

    final overridden = style(
      'p',
      'p { font-size: 20px; margin: 1px; margin-left: 2em; }',
    );
    expect(overridden.margin.top, 1);
    expect(overridden.margin.left, 40);
  });

  test('text-indent 与负 letter-spacing 解析/继承', () {
    final parent = style(
      'parent',
      'div { font-size: 20px; text-indent: 2em; letter-spacing: -1px; }',
    );
    expect(parent.textIndent, 40);
    expect(parent.letterSpacing, -1);
    final child = style('p', 'p {}', parent: parent);
    expect(child.textIndent, 40);
    expect(child.letterSpacing, -1);
    final percent = style(
      'p',
      'p { font-size: 16px; text-indent: 10%; }',
      containingWidth: 320,
    );
    expect(percent.textIndent, 32);
  });

  test('颜色解析与继承', () {
    expect(style('p', 'p { color: #aabbcc; }').color, const Color(0xFFAABBCC));
    expect(style('p', 'p { color: #abc; }').color, const Color(0xFFAABBCC));
    expect(
      style('p', 'p { color: rgb(1, 2, 3); }').color,
      const Color(0xFF010203),
    );
    expect(style('p', 'p { color: red; }').color, const Color(0xFFFF0000));
    final parent = style('parent', 'div { color: #123456; }');
    expect(
      style('p', 'p { color: inherit; }', parent: parent).color,
      const Color(0xFF123456),
    );
  });

  test('字重/斜体/字体族/text-align', () {
    final style1 = style(
      'p',
      'p { font-weight: bold; font-style: italic; font-family: "Book", serif; text-align: justify; }',
    );
    expect(style1.fontWeight, 700);
    expect(style1.italic, isTrue);
    expect(style1.fontFamily, 'Book');
    expect(style1.textAlign, CssTextAlign.justify);
    expect(style('p', 'p { font-weight: 600; }').fontWeight, 600);
    expect(style('p', 'p { font-weight: normal; }').fontWeight, 400);
  });

  test('未设置字段继承父值或取初始值', () {
    final parent = style(
      'parent',
      'div { font-size: 20px; line-height: 30px; color: #112233; '
          'font-weight: bold; font-style: italic; font-family: Serif; '
          'text-align: center; }',
    );
    final child = style('p', 'p { color: #445566; }', parent: parent);
    expect(child.fontSize, 20);
    expect(child.lineHeight, 30);
    expect(child.fontWeight, 700);
    expect(child.italic, isTrue);
    expect(child.fontFamily, 'Serif');
    expect(child.textAlign, CssTextAlign.center);
    expect(child.color, const Color(0xFF445566));
    expect(child.margin.top, 0);
  });

  test('position/float/display 解析且不继承', () {
    final parsed = style(
      'p',
      'p { position: absolute; float: left; display: table; }',
    );
    expect(parsed.position, CssPosition.absolute);
    expect(parsed.cssFloat, CssFloat.left);
    expect(parsed.display, CssDisplay.table);

    final parent = style(
      'parent',
      'div { display: inline; position: fixed; float: right; }',
    );
    final child = style('p', 'p { color: red; }', parent: parent);
    expect(child.position, CssPosition.static, reason: 'position 不继承');
    expect(child.cssFloat, CssFloat.none, reason: 'float 不继承');
    expect(child.display, CssDisplay.block, reason: 'display 不继承');
  });

  test('font-family 列表、fallback 链与继承', () {
    final parsed = style('p', 'p { font-family: "Book Serif", Ahem, serif; }');
    expect(parsed.fontFamilies, <String>['Book Serif', 'Ahem', 'serif']);
    expect(parsed.fontFamily, 'Book Serif');
    expect(parsed.fontFamilyFallback, <String>['Ahem', 'serif']);

    final parent = style('parent', 'div { font-family: A, B; }');
    final child = style('p', 'p { color: red; }', parent: parent);
    expect(child.fontFamilies, <String>['A', 'B'], reason: 'font-family 继承');

    final quoted = style('p', "p { font-family: 'A, B', C; }");
    expect(quoted.fontFamilies, <String>['A, B', 'C'], reason: '引号内逗号不切分');

    final none = style('p', 'p { color: red; }');
    expect(none.fontFamilies, isEmpty);
    expect(none.fontFamily, isNull);
    expect(none.fontFamilyFallback, isEmpty);
  });

  test('背景与边框属性解析', () {
    final parsed = style(
      'p',
      'p { background-color: #112233; background-image: url("bg.png"); '
          'border: 2px solid #FF0000; border-radius: 8px; }',
    );
    expect(parsed.backgroundColor, const Color(0xFF112233));
    expect(parsed.backgroundImage, 'bg.png');
    expect(parsed.borders.top.width, 2);
    expect(parsed.borders.top.style, CssBorderStyle.solid);
    expect(parsed.borders.top.color, const Color(0xFFFF0000));
    expect(parsed.borders.isUniform, isTrue);
    expect(parsed.borders.topLeftRadius, 8);
    expect(parsed.borders.bottomRightRadius, 8);

    final four = style(
      'p',
      'p { border-width: 1px 2px; border-style: dashed solid; '
          'border-top-color: #00FF00; }',
    );
    expect(four.borders.top.width, 1);
    expect(four.borders.right.width, 2);
    expect(four.borders.bottom.width, 1);
    expect(four.borders.left.width, 2);
    expect(four.borders.top.style, CssBorderStyle.dashed);
    expect(four.borders.right.style, CssBorderStyle.solid);
    expect(four.borders.top.color, const Color(0xFF00FF00));
    expect(four.borders.isUniform, isFalse);

    final radii = style('p', 'p { border-radius: 4px 0 8px; }');
    expect(radii.borders.topLeftRadius, 4);
    expect(radii.borders.topRightRadius, 0);
    expect(radii.borders.bottomRightRadius, 8);
    expect(radii.borders.bottomLeftRadius, 0);

    final plain = style('p', 'p { color: red; }');
    expect(plain.borders.hasBorder, isFalse);
    expect(plain.backgroundColor.a, 0);
    expect(plain.backgroundImage, isNull);
  });

  test('width/height 的 px、em、百分比与 auto', () {
    final px = style('p', 'p { width: 120px; height: 2em; }');
    expect(px.width?.value, 120);
    expect(px.width?.isPercent, isFalse);
    expect(px.width?.isAuto, isFalse);
    expect(px.width?.resolve(300), 120);
    expect(px.height?.value, 32, reason: 'em 按元素自身字号换算');

    final percent = style('p', 'p { width: 50%; height: 25%; }');
    expect(percent.width?.isPercent, isTrue);
    expect(percent.width?.value, 50);
    expect(percent.width?.resolve(400), 200);
    expect(percent.height?.isPercent, isTrue);
    expect(percent.height?.value, 25, reason: '百分比不解算成像素');

    final auto = style('p', 'p { width: auto; }');
    expect(auto.width?.isAuto, isTrue);
    expect(auto.width?.resolve(300), isNull);
    expect(auto.height, isNull, reason: '未声明 height 为 null');
  });

  test('min/max 尺寸与 max-* 的 none', () {
    final parsed = style(
      'p',
      'p { min-width: 10px; max-width: 80%; min-height: 1em; '
          'max-height: none; }',
    );
    expect(parsed.minWidth?.value, 10);
    expect(parsed.maxWidth?.isPercent, isTrue);
    expect(parsed.maxWidth?.value, 80);
    expect(parsed.maxWidth?.resolve(500), 400);
    expect(parsed.minHeight?.value, 16);
    expect(parsed.maxHeight, isNull, reason: 'max-height: none 视为未设上限');

    final plain = style('p', 'p { color: red; }');
    expect(plain.width, isNull);
    expect(plain.minWidth, isNull);
    expect(plain.maxWidth, isNull);
  });

  test('padding 简写 1–4 值展开', () {
    final one = style('p', 'p { padding: 5px; }');
    expect(one.padding.top, 5);
    expect(one.padding.right, 5);
    expect(one.padding.bottom, 5);
    expect(one.padding.left, 5);

    final two = style('p', 'p { padding: 1px 2px; }');
    expect(two.padding.top, 1);
    expect(two.padding.right, 2);
    expect(two.padding.bottom, 1);
    expect(two.padding.left, 2);

    final three = style('p', 'p { padding: 1px 2px 3px; }');
    expect(three.padding.top, 1);
    expect(three.padding.right, 2);
    expect(three.padding.bottom, 3);
    expect(three.padding.left, 2);

    final four = style('p', 'p { padding: 1px 2px 3px 4px; }');
    expect(four.padding.top, 1);
    expect(four.padding.right, 2);
    expect(four.padding.bottom, 3);
    expect(four.padding.left, 4);
  });

  test('padding 长写覆盖简写', () {
    final overridden = style(
      'p',
      'p { padding: 5px; padding-left: 2em; padding-bottom: 0; }',
    );
    expect(overridden.padding.top, 5);
    expect(overridden.padding.right, 5);
    expect(overridden.padding.bottom, 0);
    expect(overridden.padding.left, 32);
  });

  test('负 padding 钳 0', () {
    final negative = style('p', 'p { padding: -4px 8px; }');
    expect(negative.padding.top, 0);
    expect(negative.padding.right, 8);
    expect(negative.padding.bottom, 0);
    expect(negative.padding.left, 8);

    final longhand = style('p', 'p { padding-top: -1em; }');
    expect(longhand.padding.top, 0);
  });

  test('百分比 padding 按 containingWidth 解算', () {
    final percent = style('p', 'p { padding: 10% 5%; }', containingWidth: 200);
    expect(percent.padding.top, 20);
    expect(percent.padding.right, 10);
    expect(percent.padding.bottom, 20);
    expect(percent.padding.left, 10);

    final longhand = style('p', 'p { padding-top: 25%; }', containingWidth: 80);
    expect(longhand.padding.top, 20);
  });

  test('box-sizing 解析与回退', () {
    expect(
      style('p', 'p { box-sizing: border-box; }').boxSizing,
      CssBoxSizing.borderBox,
    );
    expect(
      style('p', 'p { box-sizing: content-box; }').boxSizing,
      CssBoxSizing.contentBox,
    );
    expect(
      style('p', 'p { box-sizing: padding-box; }').boxSizing,
      CssBoxSizing.contentBox,
      reason: '其余值回退 contentBox',
    );
  });

  test('尺寸/内边距/box-sizing 默认值且不继承', () {
    final initial = ComputedStyle(const <String, String>{});
    expect(initial.width, isNull);
    expect(initial.height, isNull);
    expect(initial.minWidth, isNull);
    expect(initial.maxWidth, isNull);
    expect(initial.minHeight, isNull);
    expect(initial.maxHeight, isNull);
    expect(initial.padding.top, 0);
    expect(initial.padding.right, 0);
    expect(initial.padding.bottom, 0);
    expect(initial.padding.left, 0);
    expect(initial.boxSizing, CssBoxSizing.contentBox);

    final parent = style(
      'parent',
      'div { width: 100px; padding: 10px; box-sizing: border-box; }',
    );
    final child = style('p', 'p { color: red; }', parent: parent);
    expect(child.width, isNull, reason: 'width 不继承');
    expect(child.padding.top, 0, reason: 'padding 不继承');
    expect(child.boxSizing, CssBoxSizing.contentBox, reason: 'box-sizing 不继承');
  });

  test('visibility 与 white-space 解析且继承', () {
    final parsed = style(
      'p',
      'p { visibility: hidden; white-space: pre-wrap; }',
    );
    expect(parsed.visibility, CssVisibility.hidden);
    expect(parsed.whiteSpace, CssWhiteSpace.preWrap);

    final parent = style(
      'parent',
      'div { visibility: collapse; white-space: nowrap; }',
    );
    final child = style('p', 'p { color: red; }', parent: parent);
    expect(child.visibility, CssVisibility.collapse, reason: 'visibility 继承');
    expect(child.whiteSpace, CssWhiteSpace.nowrap, reason: 'white-space 继承');

    final fallback = style('p', 'p { visibility: bogus; white-space: bogus; }');
    expect(fallback.visibility, CssVisibility.visible);
    expect(fallback.whiteSpace, CssWhiteSpace.normal);
  });

  test('word-spacing / text-transform / vertical-align 解析与继承', () {
    final parsed = style(
      'p',
      'p { word-spacing: 8px; text-transform: uppercase; '
          'vertical-align: super; }',
    );
    expect(parsed.wordSpacing, 8);
    expect(parsed.textTransform, CssTextTransform.uppercase);
    expect(parsed.verticalAlign, CssVerticalAlign.superscript);
    expect(parsed.verticalAlignShift, closeTo(-6.4, 0.01));

    final em = style(
      'p',
      'p { word-spacing: 0.5em; text-transform: capitalize; '
          'vertical-align: sub; }',
    );
    expect(em.wordSpacing, 8);
    expect(em.textTransform, CssTextTransform.capitalize);
    expect(em.verticalAlignShift, closeTo(2.4, 0.01));

    final parent = style(
      'parent',
      'div { word-spacing: 4px; text-transform: lowercase; '
          'vertical-align: super; }',
    );
    final child = style('p', 'p { color: red; }', parent: parent);
    expect(child.wordSpacing, 4, reason: 'word-spacing 继承');
    expect(child.textTransform, CssTextTransform.lowercase);
    expect(child.verticalAlign, CssVerticalAlign.baseline, reason: '不继承');

    final plain = style('p', 'p { color: red; }');
    expect(plain.wordSpacing, 0);
    expect(plain.textTransform, CssTextTransform.none);
    expect(plain.verticalAlign, CssVerticalAlign.baseline);
  });

  test('text-decoration / text-emphasis / 分页属性解析', () {
    final deco = style(
      'p',
      'p { text-decoration: underline; text-emphasis: dot; '
          'text-emphasis-position: under; text-emphasis-color: #FF0000; }',
    );
    expect(deco.textDecoration, CssTextDecoration.underline);
    expect(deco.textEmphasisStyle, CssTextEmphasisStyle.dot);
    expect(deco.textEmphasisPosition, CssTextEmphasisPosition.under);
    expect(deco.textEmphasisColor, const Color(0xFFFF0000));

    final through = style('p', 'p { text-decoration: line-through; }');
    expect(through.textDecoration, CssTextDecoration.lineThrough);
    final overline = style('p', 'p { text-decoration: overline; }');
    expect(overline.textDecoration, CssTextDecoration.overline);
    final none = style('p', 'p { text-decoration: none; }');
    expect(none.textDecoration, CssTextDecoration.none);

    final filled = style('p', 'p { text-emphasis: filled; }');
    expect(filled.textEmphasisStyle, CssTextEmphasisStyle.filled);
    final open = style('p', 'p { text-emphasis-style: open; }');
    expect(open.textEmphasisStyle, CssTextEmphasisStyle.open);

    final breaks = style(
      'p',
      'p { page-break-before: always; break-after: page; '
          'page-break-inside: avoid; }',
    );
    expect(breaks.pageBreakBefore, isTrue);
    expect(breaks.pageBreakAfter, isTrue);
    expect(breaks.breakInsideAvoid, isTrue);
    final auto = style('p', 'p { page-break-before: auto; }');
    expect(auto.pageBreakBefore, isFalse);

    // text-emphasis 继承，text-decoration 不继承。
    final parent = style(
      'parent',
      'div { text-decoration: underline; text-emphasis: dot; '
          'text-emphasis-position: under; }',
    );
    final child = style('p', 'p { color: #00FF00; }', parent: parent);
    expect(child.textDecoration, CssTextDecoration.none, reason: '不继承');
    expect(child.textEmphasisStyle, CssTextEmphasisStyle.dot);
    expect(child.textEmphasisPosition, CssTextEmphasisPosition.under);
  });

  test('P0 收口属性：text-shadow / 背景子属性 / 定位 / clear / 表格边框', () {
    final parsed = style(
      'p',
      'p { text-shadow: 2px 3px 4px #FF0000; background-repeat: no-repeat; '
          'background-size: cover; background-position: center; '
          'background-origin: content-box; clear: both; '
          'border-collapse: collapse; border-spacing: 6px 4px; '
          'top: 10px; left: 20%; }',
    );
    expect(parsed.textShadow, hasLength(1));
    expect(parsed.textShadow.single.offsetX, 2);
    expect(parsed.textShadow.single.offsetY, 3);
    expect(parsed.textShadow.single.blur, 4);
    expect(parsed.textShadow.single.color, const Color(0xFFFF0000));
    expect(parsed.backgroundRepeat, CssBackgroundRepeat.noRepeat);
    expect(parsed.backgroundSize.mode, CssBackgroundSizeMode.cover);
    expect(parsed.backgroundPosition.x.value, 50);
    expect(parsed.backgroundOrigin, CssBackgroundOrigin.contentBox);
    expect(parsed.clear, CssClear.both);
    expect(parsed.borderCollapse, CssBorderCollapse.collapse);
    expect(parsed.borderSpacing.left, 6);
    expect(parsed.borderSpacing.top, 4);
    expect(parsed.top?.value, 10);
    expect(parsed.left?.isPercent, isTrue);
    expect(parsed.left?.value, 20);

    final defaults = style('p', 'p { color: red; }');
    expect(defaults.textShadow, isEmpty);
    expect(defaults.backgroundRepeat, CssBackgroundRepeat.repeat);
    expect(defaults.backgroundSize.mode, CssBackgroundSizeMode.auto);
    expect(defaults.backgroundPosition.x.value, 0);
    expect(defaults.backgroundOrigin, CssBackgroundOrigin.paddingBox);
    expect(defaults.clear, CssClear.none);
    expect(defaults.borderCollapse, CssBorderCollapse.separate);
    expect(defaults.borderSpacing.left, 0);
    expect(defaults.top, isNull);

    final parent = style('parent', 'div { text-shadow: 1px 1px 0 #000000; }');
    final child = style('p', 'p { color: red; }', parent: parent);
    expect(child.textShadow, hasLength(1), reason: 'text-shadow 继承');
  });
}
