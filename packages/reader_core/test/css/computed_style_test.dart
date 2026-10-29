import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/parser/document_parser.dart';

const _xhtml = '''
<html><body><div id="parent"><p id="p">text</p></div></body></html>
''';

void main() {
  final document = DocumentParser.parse(xhtml: _xhtml, spineIndex: 0);
  final viewOwner = <ParsedNode, ParsedElementView>{};
  final rootView = ParsedElementView.wrap(document.root, viewOwner);
  SelectorElement el(String id) => viewOwner[document.elementById(id)]!;

  final paths = <String, List<SelectorElement>>{};
  void walk(SelectorElement element, List<SelectorElement> path) {
    final id = element.attributes['id'];
    if (id != null) {
      paths[id] = List<SelectorElement>.unmodifiable(path);
    }
    for (final child in element.childElements) {
      walk(child, <SelectorElement>[...path, element]);
    }
  }

  walk(rootView, const <SelectorElement>[]);

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
    // 未声明行高 = CSS `normal`：因子为 null（TextStyle(height: null) 交给
    // 字体度量，Chrome 同字体约 1.41–1.44em）；像素值只是几何兜底近似。
    expect(initial.lineHeightFactor, isNull);
    expect(initial.unitlessLineHeightFactor, isNull);
    expect(initial.lineHeight, closeTo(16 * 1.437, 0.001));
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
    // 未声明 → CSS normal：因子为 null，像素值只是 1.437 的兜底近似。
    expect(base.lineHeightFactor, isNull);
    expect(base.lineHeight, closeTo(20 * 1.437, 0.001));
  });

  test('未声明行高 = CSS normal：显式 normal/继承/阅读器覆盖三条路径', () {
    // 1) 显式 `line-height: normal` 与未声明等价（因子仍为 null）。
    final explicitNormal = style(
      'p',
      'p { font-size: 20px; line-height: normal; }',
    );
    expect(explicitNormal.lineHeightFactor, isNull);
    expect(explicitNormal.lineHeight, closeTo(20 * 1.437, 0.001));

    // 2) 继承：父级 normal 时子级继续 normal（不继承近似的像素值）；
    //    父级无单位因子按子字号重算；父级 px 按绝对值继承。
    final normalParent = style('parent', 'div { font-size: 20px; }');
    final normalChild = style(
      'p',
      'p { font-size: 10px; }',
      parent: normalParent,
    );
    expect(normalChild.lineHeightFactor, isNull, reason: 'normal 逐级保持');
    expect(normalChild.lineHeight, closeTo(10 * 1.437, 0.001));

    final unitlessParent = style(
      'parent',
      'div { font-size: 20px; line-height: 1.8; }',
    );
    expect(unitlessParent.lineHeightFactor, 1.8);
    final unitlessChild = style(
      'p',
      'p { font-size: 10px; }',
      parent: unitlessParent,
    );
    expect(unitlessChild.lineHeightFactor, closeTo(1.8, 0.001));
    expect(unitlessChild.lineHeight, closeTo(18, 0.001));
    expect(unitlessChild.unitlessLineHeightFactor, closeTo(1.8, 0.001));

    final pxParent = style(
      'parent',
      'div { font-size: 20px; line-height: 30px; }',
    );
    final pxChild = style('p', 'p { font-size: 10px; }', parent: pxParent);
    expect(pxChild.lineHeight, 30, reason: 'px 行高按绝对值继承');
    expect(pxChild.lineHeightFactor, closeTo(3, 0.001), reason: '30/10');

    // 3) 阅读器覆盖仍是显式的（ReaderOverrides 走 withTypography）。
    final navigated = style(
      'p',
      'p { font-size: 20px; }',
    ).withTypography(lineHeightFactor: 1.5);
    expect(navigated.lineHeightFactor, 1.5, reason: '阅读器覆盖不能被 normal 吞掉');
    expect(navigated.lineHeight, 30);
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

  test('font-weight 相对关键字 bolder/lighter（CSS Fonts 4 映射表）', () {
    // bolder：100–300→400、400–500→700、600–900→900；
    // lighter：100–500→100、600–700→400、800–900→700。
    const bolder = <int, int>{
      100: 400,
      200: 400,
      300: 400,
      400: 700,
      500: 700,
      600: 900,
      700: 900,
      800: 900,
      900: 900,
    };
    const lighter = <int, int>{
      100: 100,
      200: 100,
      300: 100,
      400: 100,
      500: 100,
      600: 400,
      700: 400,
      800: 700,
      900: 700,
    };
    for (final entry in bolder.entries) {
      final parent = style('parent', 'div { font-weight: ${entry.key}; }');
      expect(
        style('p', 'p { font-weight: bolder; }', parent: parent).fontWeight,
        entry.value,
        reason: 'bolder(${entry.key})',
      );
    }
    for (final entry in lighter.entries) {
      final parent = style('parent', 'div { font-weight: ${entry.key}; }');
      expect(
        style('p', 'p { font-weight: lighter; }', parent: parent).fontWeight,
        entry.value,
        reason: 'lighter(${entry.key})',
      );
    }
    // 无父级（根元素）按初始值 400：bolder → 700、lighter → 100。
    expect(style('p', 'p { font-weight: bolder; }').fontWeight, 700);
    expect(style('p', 'p { font-weight: lighter; }').fontWeight, 100);
    // `font` 简写里的相对字重同样按父级解算。
    final parent = style('parent', 'div { font-weight: 300; }');
    expect(
      style('p', 'p { font: bolder 16px serif; }', parent: parent).fontWeight,
      400,
    );
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

    final elliptical = style('p', 'p { border-radius: 30px / 10px; }');
    expect(elliptical.borders.topLeftRadius, 30);
    expect(elliptical.borders.topLeftRadiusY, 10);
    expect(elliptical.borders.bottomRightRadius, 30);
    expect(elliptical.borders.bottomRightRadiusY, 10);

    final corner = style(
      'p',
      'p { border-top-left-radius: 20px 8px; '
          'border-bottom-right-radius: 10%; }',
    );
    expect(corner.borders.topLeftRadius, 20);
    expect(corner.borders.topLeftRadiusY, 8);
    expect(corner.borders.bottomRightRadiusPercent, closeTo(0.1, 0.0001));
    expect(corner.borders.bottomRightRadiusPercentY, closeTo(0.1, 0.0001));

    final ellipticalPercent = style(
      'p',
      'p { border-radius: 20% 10% / 5% 15%; }',
    );
    expect(
      ellipticalPercent.borders.topLeftRadiusPercent,
      closeTo(0.2, 0.0001),
    );
    expect(
      ellipticalPercent.borders.topLeftRadiusPercentY,
      closeTo(0.05, 0.0001),
    );
    expect(
      ellipticalPercent.borders.topRightRadiusPercent,
      closeTo(0.1, 0.0001),
    );
    expect(
      ellipticalPercent.borders.topRightRadiusPercentY,
      closeTo(0.15, 0.0001),
    );

    final plain = style('p', 'p { color: red; }');
    expect(plain.borders.hasBorder, isFalse);
    expect(plain.backgroundColor.a, 0);
    expect(plain.backgroundImage, isNull);
  });

  test('border-style：3D 线型保留原值，none/hidden 宽度归零', () {
    // 四种立体线型与 solid 同宽同色，只有明暗差异；此前降级成 solid，
    // 现在保留原值由绘制层画两半明暗（CSS Backgrounds §4.4）。
    for (final entry in const <String, CssBorderStyle>{
      'groove': CssBorderStyle.groove,
      'ridge': CssBorderStyle.ridge,
      'inset': CssBorderStyle.inset,
      'outset': CssBorderStyle.outset,
    }.entries) {
      final parsed = style('p', 'p { border: 4px ${entry.key} #F00; }');
      expect(parsed.borders.top.style, entry.value, reason: entry.key);
      expect(parsed.borders.top.width, 4, reason: entry.key);
      expect(parsed.borders.isUniform, isTrue, reason: entry.key);
    }
    final hidden = style('p', 'p { border: 4px hidden #F00; }');
    expect(hidden.borders.top.style, CssBorderStyle.none);
    expect(hidden.borders.top.width, 0, reason: 'hidden 计算宽度 0');
    expect(hidden.borders.hasBorder, isFalse);
    final none = style('p', 'p { border-width: 5px; border-style: none; }');
    expect(none.borders.top.width, 0, reason: 'none 计算宽度 0');
    // 只写线型不写宽度仍是 medium 3px。
    final medium = style('p', 'p { border-style: solid; }');
    expect(medium.borders.top.width, 3);
  });

  test('outline 简写与长属性独立于盒模型', () {
    final parsed = style(
      'p',
      'p { color: #00FF00; outline: 4px dashed #FF0000; '
          'outline-width: 6px; outline-offset: -2px; }',
    );
    expect(parsed.outline.width, 6);
    expect(parsed.outline.style, CssBorderStyle.dashed);
    expect(parsed.outline.color, const Color(0xFFFF0000));
    expect(parsed.outline.offset, -2);
    expect(parsed.margin.top, 0, reason: 'outline 不占布局空间');

    final current = style('p', 'p { color: #00FF00; outline: 2px solid; }');
    expect(current.outline.style, CssBorderStyle.solid);
    expect(current.outline.color, const Color(0xFF00FF00));

    final reset = style(
      'p',
      'p { outline-width: 9px; outline-style: dashed; '
          'outline: 1px solid #0000FF; }',
    );
    expect(reset.outline.width, 1, reason: '后置简写重置遗漏的长属性');
    expect(reset.outline.style, CssBorderStyle.solid);
    expect(reset.outline.color, const Color(0xFF0000FF));
  });

  test('box-shadow 保留 blur/spread/inset', () {
    final shadow = style(
      'p',
      'p { box-shadow: 2px 3px 4px 5px #112233 inset; }',
    ).boxShadow;
    expect(shadow, isNotNull);
    expect(shadow!.offsetX, 2);
    expect(shadow.offsetY, 3);
    expect(shadow.blur, 4);
    expect(shadow.spread, 5);
    expect(shadow.inset, isTrue);
    expect(shadow.color, const Color(0xFF112233));

    // 未写 blur/spread 时默认 0，旧字段语义不变。
    final basic = style('p', 'p { box-shadow: 1px 2px #000; }').boxShadow!;
    expect(basic.blur, 0);
    expect(basic.spread, 0);
    expect(basic.inset, isFalse);
    // 单值 + 颜色 + 无偏移的形态按 rgba 内部逗号不切分。
    final rgba = style(
      'p',
      'p { box-shadow: 0 1px 2px rgba(0, 0, 0, 0.5), 3px 3px red; }',
    ).boxShadow!;
    expect(rgba.offsetY, 1);
    expect(rgba.blur, 2);
    expect(rgba.color.a, closeTo(0.5, 0.01));
    expect(style('p', 'p { box-shadow: none; }').boxShadow, isNull);
  });

  test('text-shadow 的 blur 字段（W5 核对）', () {
    // 绘制层需要 blur：三个长度按 offset-x / offset-y / blur 顺序解析。
    final shadow = style(
      'p',
      'p { text-shadow: 1px 2px 3px #ff0000; }',
    ).textShadow;
    expect(shadow, hasLength(1));
    expect(shadow.single.offsetX, 1);
    expect(shadow.single.offsetY, 2);
    expect(shadow.single.blur, 3);
    expect(shadow.single.color, const Color(0xFFFF0000));
    // 只写两个长度时 blur 默认 0；多阴影各自保留 blur。
    final noBlur = style('p', 'p { text-shadow: 1px 1px #000; }').textShadow;
    expect(noBlur.single.blur, 0);
    final multi = style(
      'p',
      'p { text-shadow: 1px 1px 2px #000, 0 0 4px #fff; }',
    ).textShadow;
    expect(multi, hasLength(2));
    expect(multi.first.blur, 2);
    expect(multi.last.blur, 4);
    expect(multi.last.offsetX, 0);
  });

  test('渐变结构：linear（角度/方向 + 色标）', () {
    final deg = style(
      'p',
      'p { background-image: linear-gradient(45deg, #f00 0%, #00f 100%); }',
    );
    expect(deg.backgroundImage, isNull, reason: '渐变不是 url');
    final linear = deg.backgroundGradient;
    expect(linear, isA<CssLinearGradient>());
    final byDeg = linear! as CssLinearGradient;
    expect(byDeg.angle, 45);
    expect(byDeg.stops, hasLength(2));
    expect(byDeg.stops.first.color, const Color(0xFFFF0000));
    expect(byDeg.stops.first.position, 0);
    expect(byDeg.stops.last.color, const Color(0xFF0000FF));
    expect(byDeg.stops.last.position, 1);

    // 方向关键字与角度单位换算；rgba 内的逗号不切分色标。
    final corner =
        style(
              'p',
              'p { background-image: '
                  'linear-gradient(to right top, #f00, rgba(0, 255, 0, 0.5) 40%, #00f); }',
            ).backgroundGradient!
            as CssLinearGradient;
    expect(corner.angle, 45);
    expect(corner.stops, hasLength(3));
    expect(corner.stops[1].color.a, closeTo(0.5, 0.01));
    expect(corner.stops[1].position, closeTo(0.4, 0.001));

    expect(
      (style(
                'p',
                'p { background-image: linear-gradient(to bottom, #000, #fff); }',
              ).backgroundGradient!
              as CssLinearGradient)
          .angle,
      180,
    );
    expect(
      (style(
                'p',
                'p { background-image: linear-gradient(0.25turn, #000, #fff); }',
              ).backgroundGradient!
              as CssLinearGradient)
          .angle,
      90,
    );
    // 未声明方向按规范默认 180（向下）。
    expect(
      (style(
                'p',
                'p { background-image: linear-gradient(#000, #fff); }',
              ).backgroundGradient!
              as CssLinearGradient)
          .angle,
      180,
    );
    expect(
      style('p', 'p { background-image: none; }').backgroundGradient,
      isNull,
    );
  });

  test('多背景层按声明顺序保留，并循环分配尺寸/平铺/位置', () {
    final layered = style(
      'p',
      'p { background-image: '
          'linear-gradient(#f00, #f00), linear-gradient(#00f, #00f); '
          'background-size: 50% 100%, 25% 50%; '
          'background-repeat: no-repeat, repeat; '
          'background-position: left top; }',
    );
    final layers = layered.backgroundLayers;
    expect(layers, hasLength(2));
    expect(
      (layers[0].gradient! as CssLinearGradient).stops.first.color,
      const Color(0xFFFF0000),
    );
    expect(layers[0].repeat, CssBackgroundRepeat.noRepeat);
    expect(layers[0].size.width!.value, 50);
    expect(layers[0].position.x.value, 0);
    expect(layers[0].position.y.value, 0);
    expect(
      (layers[1].gradient! as CssLinearGradient).stops.first.color,
      const Color(0xFF0000FF),
    );
    expect(layers[1].repeat, CssBackgroundRepeat.repeat);
    expect(layers[1].size.width!.value, 25);
    expect(layers[1].position.x.value, 0, reason: '单个位置值循环到所有层');
    expect(layers[1].position.y.value, 0);
  });

  test('渐变结构：radial（shape/position + 色标）', () {
    final at =
        style(
              'p',
              'p { background-image: '
                  'radial-gradient(circle at 30% 70%, #f00, #00f 60%); }',
            ).backgroundGradient!
            as CssRadialGradient;
    expect(at.shape, CssRadialShape.circle);
    expect(at.centerX.value, 30);
    expect(at.centerX.isPercent, isTrue);
    expect(at.centerY.value, 70);
    expect(at.stops, hasLength(2));
    expect(at.stops.last.position, closeTo(0.6, 0.001));

    final plain =
        style(
              'p',
              'p { background-image: radial-gradient(#f00, #00f); }',
            ).backgroundGradient!
            as CssRadialGradient;
    expect(plain.shape, CssRadialShape.ellipse, reason: '默认 ellipse');
    expect(plain.centerX.value, 50);
    expect(plain.centerY.value, 50);
    // 单值位置（top）只移动纵轴。
    final top =
        style(
              'p',
              'p { background-image: radial-gradient(at top, #f00, #00f); }',
            ).backgroundGradient!
            as CssRadialGradient;
    expect(top.centerY.value, 0);
    expect(top.centerX.value, 50);
  });

  test('repeating 渐变标记与像素色标换算（W5）', () {
    final repeating =
        style(
              'p',
              'p { background-image: '
                  'repeating-linear-gradient(45deg, #f00 0px, #00f 10px); }',
            ).backgroundGradient!
            as CssLinearGradient;
    expect(repeating.repeating, isTrue);
    expect(repeating.angle, 45);
    // 像素位置保留在 positionPx，绘制层按渐变线长度换算成比例。
    expect(repeating.stops.first.position, isNull);
    expect(repeating.stops.first.positionPx, 0);
    expect(repeating.stops.last.positionPx, 10);
    expect(repeating.stops.last.fractionOf(100), closeTo(0.1, 0.001));
    expect(repeating.stops.last.fractionOf(0), isNull, reason: 'extent 未知');

    // 百分比色标：fractionOf 直接用比例，与 extent 无关。
    final percent =
        style(
              'p',
              'p { background-image: '
                  'repeating-radial-gradient(circle, #f00 0%, #00f 25%); }',
            ).backgroundGradient!
            as CssRadialGradient;
    expect(percent.repeating, isTrue);
    expect(percent.shape, CssRadialShape.circle);
    expect(percent.stops.last.fractionOf(999), closeTo(0.25, 0.001));

    // 非 repeating 形态标记为 false（不回归）。
    final plain = style(
      'p',
      'p { background-image: linear-gradient(#f00, #00f); }',
    ).backgroundGradient!;
    expect(plain.repeating, isFalse);
  });

  test('渐变区间色标：<color> <start> <end> 展开成两个同色 stop（W7）', () {
    // 26-background-gradient 的 .rep 写法：像素区间 → 4 个 stop。
    final stripes =
        style(
              'p',
              'p { background-image: repeating-linear-gradient('
                  '90deg, #000 0 4px, #fff 4px 8px); }',
            ).backgroundGradient!
            as CssLinearGradient;
    expect(stripes.repeating, isTrue);
    expect(stripes.angle, 90);
    expect(stripes.stops, hasLength(4));
    expect(
      [for (final stop in stripes.stops) stop.positionPx],
      isNot(contains(isNull)),
      reason: '四个 stop 都带像素位置',
    );
    expect(
      [for (final stop in stripes.stops) stop.positionPx!.round()],
      <int>[0, 4, 4, 8],
    );
    expect(
      [for (final stop in stripes.stops) stop.color.toARGB32()],
      <int>[0xFF000000, 0xFF000000, 0xFFFFFFFF, 0xFFFFFFFF],
      reason: '同色成对',
    );

    // 百分比区间（.stripe 写法）→ 4 个 stop；首段写的是无单位 `0`，按长度
    // 保留为 positionPx=0，换算后与 0% 等价（fractionOf 统一口径）。
    final hardStops = style(
      'p',
      'p { background-image: linear-gradient('
          '90deg, #ff0000 0 50%, #0000ff 50% 100%); }',
    ).backgroundGradient!;
    expect(hardStops.stops, hasLength(4));
    expect(
      [for (final stop in hardStops.stops) stop.fractionOf(100)],
      <double>[0, 0.5, 0.5, 1],
    );

    // 第二个位置小于第一个：按 CSS 语义钳到第一个（区间宽度为 0）。
    final clamped = style(
      'p',
      'p { background-image: linear-gradient(#fff 8px 4px, #000 20px); }',
    ).backgroundGradient!;
    expect(clamped.stops, hasLength(3));
    expect(clamped.stops[0].positionPx, 8);
    expect(clamped.stops[1].positionPx, 8);
    expect(clamped.stops[2].positionPx, 20);
  });

  test('filter 解析：有序滤镜列表与各函数参数（W5）', () {
    // 单个 blur：长度按 px 解算。
    final blur = style('p', 'p { filter: blur(2px); }').filters;
    expect(blur, hasLength(1));
    expect(blur.single.kind, CssFilterKind.blur);
    expect(blur.single.amount, 2);

    // 百分比归一：grayscale(100%) → 1；倍率函数按百分比换算。
    final gray = style('p', 'p { filter: grayscale(100%); }').filters;
    expect(gray.single.kind, CssFilterKind.grayscale);
    expect(gray.single.amount, 1);
    final sepia = style('p', 'p { filter: sepia(0.6); }').filters;
    expect(sepia.single.amount, closeTo(0.6, 0.001));
    final brightness = style('p', 'p { filter: brightness(150%); }').filters;
    expect(brightness.single.kind, CssFilterKind.brightness);
    expect(brightness.single.amount, closeTo(1.5, 0.001));
    final opacityFn = style('p', 'p { filter: opacity(0.4); }').filters;
    expect(opacityFn.single.kind, CssFilterKind.opacity);
    expect(opacityFn.single.amount, closeTo(0.4, 0.001));
    final hue = style('p', 'p { filter: hue-rotate(0.25turn); }').filters;
    expect(hue.single.kind, CssFilterKind.hueRotate);
    expect(hue.single.amount, closeTo(90, 0.001));

    // 多滤镜保持声明顺序。
    final multi = style(
      'p',
      'p { filter: blur(1px) grayscale(50%) brightness(0.8); }',
    ).filters;
    expect(multi.map((filter) => filter.kind).toList(), <CssFilterKind>[
      CssFilterKind.blur,
      CssFilterKind.grayscale,
      CssFilterKind.brightness,
    ]);
    expect(multi[1].amount, closeTo(0.5, 0.001));
    expect(multi[2].amount, closeTo(0.8, 0.001));

    // drop-shadow：偏移/模糊/颜色，颜色函数内部逗号不切分。
    final dropShadow = style(
      'p',
      'p { filter: drop-shadow(2px 3px 4px rgba(0, 0, 0, 0.5)); }',
    ).filters.single;
    expect(dropShadow.kind, CssFilterKind.dropShadow);
    expect(dropShadow.shadow!.offsetX, 2);
    expect(dropShadow.shadow!.offsetY, 3);
    expect(dropShadow.shadow!.blur, 4);
    expect(dropShadow.shadow!.color.a, closeTo(0.5, 0.01));

    // 无参函数取规范默认 1；none → 空列表；不继承；-webkit-filter 兜底。
    expect(style('p', 'p { filter: brightness(); }').filters.single.amount, 1);
    expect(style('p', 'p { filter: none; }').filters, isEmpty);
    final parent = style('parent', 'div { filter: blur(2px); }');
    expect(
      style('p', 'p { color: red; }', parent: parent).filters,
      isEmpty,
      reason: 'filter 不继承',
    );
    final webkit = style('p', 'p { -webkit-filter: blur(3px); }').filters;
    expect(webkit.single.kind, CssFilterKind.blur);
    expect(webkit.single.amount, 3);
    // 厂商前缀与标准名共用级联槽位：同特异性按声明顺序取胜。
    expect(
      style(
        'p',
        'p { -webkit-filter: blur(1px); filter: blur(2px); }',
      ).filters.single.amount,
      2,
    );
    expect(
      style(
        'p',
        'p { filter: blur(2px); -webkit-filter: blur(1px); }',
      ).filters.single.amount,
      1,
    );
  });

  test('effectiveOpacity 沿父链累计（W5）', () {
    expect(ComputedStyle(const <String, String>{}).effectiveOpacity, 1);
    final parent = style('parent', 'div { opacity: 0.5; }');
    expect(parent.opacity, 0.5);
    expect(parent.effectiveOpacity, closeTo(0.5, 0.001));
    final child = style('p', 'p { opacity: 0.4; }', parent: parent);
    expect(child.opacity, closeTo(0.4, 0.001), reason: 'opacity 本身不继承');
    expect(
      child.effectiveOpacity,
      closeTo(0.2, 0.001),
      reason: '0.5 × 0.4，与浏览器合成一致',
    );
    // 子元素未声明 opacity 时，累计值仍带父级。
    final inherited = style('p', 'p { color: red; }', parent: parent);
    expect(inherited.opacity, 1);
    expect(inherited.effectiveOpacity, closeTo(0.5, 0.001));
    // withTypography 只改排版，不改合成值。
    expect(
      child.withTypography(fontSize: 20).effectiveOpacity,
      closeTo(0.2, 0.001),
    );
  });

  test('transform：有序列表 + 百分比标记（W11）', () {
    // translate：px 与百分比都保留；百分比不提前换算成 px。
    final translate = style(
      'p',
      'p { transform: translate(20px, 10%); }',
    ).transforms;
    expect(translate, hasLength(1));
    expect(translate.single.kind, CssTransformKind.translate);
    expect(translate.single.x!.value, 20);
    expect(translate.single.x!.isPercent, isFalse);
    expect(translate.single.y!.value, 10);
    expect(translate.single.y!.isPercent, isTrue);
    expect(translate.single.y!.resolve(200), closeTo(20, 0.001));

    // 组合顺序保留；translateX 的 y 补 0，scaleX 的 sy 补 1。
    final combo = style(
      'p',
      'p { transform: translateX(-10px) scaleX(1.2); }',
    ).transforms;
    expect(combo, hasLength(2));
    expect(combo[0].kind, CssTransformKind.translate);
    expect(combo[0].x!.value, -10);
    expect(combo[0].y!.value, 0);
    expect(combo[1].kind, CssTransformKind.scale);
    expect(combo[1].sx, closeTo(1.2, 0.001));
    expect(combo[1].sy, 1);

    // scale(0.8) 的 sy 为 null（同 sx）；百分比按倍数归一。
    final scale = style('p', 'p { transform: scale(0.8); }').transforms.single;
    expect(scale.sy, isNull);
    final scalePercent = style(
      'p',
      'p { transform: scale(150%, 50%); }',
    ).transforms.single;
    expect(scalePercent.sx, closeTo(1.5, 0.001));
    expect(scalePercent.sy, closeTo(0.5, 0.001));

    // 角度：deg / turn 都折算成度。
    expect(
      style('p', 'p { transform: rotate(15deg); }').transforms.single.angleDeg,
      15,
    );
    expect(
      style(
        'p',
        'p { transform: rotate(0.5turn); }',
      ).transforms.single.angleDeg,
      closeTo(180, 0.001),
    );

    // matrix 六个分量；skew 两轴角度。
    final matrix = style(
      'p',
      'p { transform: matrix(1, 0.2, 0.3, 1, 10, 20); }',
    ).transforms.single;
    expect(matrix.kind, CssTransformKind.matrix);
    expect(matrix.values, <double>[1, 0.2, 0.3, 1, 10, 20]);
    final skew = style(
      'p',
      'p { transform: skew(10deg, 5deg); }',
    ).transforms.single;
    expect(skew.kind, CssTransformKind.skew);
    expect(skew.axDeg, 10);
    expect(skew.ayDeg, 5);

    // none / 未声明 → 空；未支持函数跳过（不报错）。
    expect(style('p', 'p { transform: none; }').transforms, isEmpty);
    expect(style('p', 'p { color: red; }').transforms, isEmpty);
    final unsupported = style(
      'p',
      'p { transform: translate3d(1px, 2px, 3px) rotate(30deg); }',
    ).transforms;
    expect(unsupported, hasLength(1), reason: '未支持的 translate3d 被跳过');
    expect(unsupported.single.kind, CssTransformKind.rotate);
    // 前缀名与标准名同槽级联，不能固定让标准名获胜。
    expect(
      style(
        'p',
        'p { -webkit-transform: translateX(1px); '
            'transform: translateX(2px); }',
      ).transforms.single.x!.value,
      2,
    );
    expect(
      style(
        'p',
        'p { transform: translateX(2px); '
            '-webkit-transform: translateX(1px); }',
      ).transforms.single.x!.value,
      1,
    );
    expect(
      style(
        'p',
        'p { -webkit-transform-origin: 20px 30%; }',
      ).transformOriginX.value,
      20,
    );
  });

  test('transform-origin：默认 50%/50%，关键词与长度（W11）', () {
    final initial = style('p', 'p { color: red; }');
    expect(initial.transformOriginX.value, 50);
    expect(initial.transformOriginX.isPercent, isTrue);
    expect(initial.transformOriginY.value, 50);
    expect(initial.transformOriginY.isPercent, isTrue);

    final leftTop = style('p', 'p { transform-origin: left top; }');
    expect(leftTop.transformOriginX.value, 0);
    expect(leftTop.transformOriginY.value, 0);
    expect(leftTop.transformOriginX.isPercent, isTrue);

    final mixed = style('p', 'p { transform-origin: 20px 30%; }');
    expect(mixed.transformOriginX.value, 20);
    expect(mixed.transformOriginX.isPercent, isFalse);
    expect(mixed.transformOriginY.value, 30);
    expect(mixed.transformOriginY.isPercent, isTrue);

    // 单值 top 只改纵轴，横轴取 center。
    final top = style('p', 'p { transform-origin: top; }');
    expect(top.transformOriginX.value, 50);
    expect(top.transformOriginY.value, 0);
  });

  test('writing-mode / text-orientation / direction 解析与继承（W11）', () {
    final defaults = style('p', 'p { color: red; }');
    expect(defaults.writingMode, CssWritingMode.horizontalTb);
    expect(defaults.textOrientation, CssTextOrientation.mixed);
    expect(defaults.direction, CssDirection.ltr);

    expect(
      style('p', 'p { writing-mode: vertical-rl; }').writingMode,
      CssWritingMode.verticalRl,
    );
    expect(
      style('p', 'p { writing-mode: vertical-lr; }').writingMode,
      CssWritingMode.verticalLr,
    );
    // CSS2 旧值。
    expect(
      style('p', 'p { writing-mode: tb-rl; }').writingMode,
      CssWritingMode.verticalRl,
    );
    // 多看私有属性经别名表落到 writing-mode。
    expect(
      style('p', 'p { -duokan-writing-mode: vertical-rl; }').writingMode,
      CssWritingMode.verticalRl,
    );

    expect(
      style('p', 'p { text-orientation: upright; }').textOrientation,
      CssTextOrientation.upright,
    );
    expect(
      style('p', 'p { text-orientation: sideways-right; }').textOrientation,
      CssTextOrientation.sideways,
    );
    expect(style('p', 'p { direction: rtl; }').direction, CssDirection.rtl);

    // 三者都继承。
    final parent = style(
      'parent',
      'div { writing-mode: vertical-rl; text-orientation: upright; '
          'direction: rtl; }',
    );
    final child = style('p', 'p { color: red; }', parent: parent);
    expect(child.writingMode, CssWritingMode.verticalRl);
    expect(child.textOrientation, CssTextOrientation.upright);
    expect(child.direction, CssDirection.rtl);
    // 子级显式声明覆盖继承值。
    final override = style(
      'p',
      'p { writing-mode: horizontal-tb; direction: ltr; }',
      parent: parent,
    );
    expect(override.writingMode, CssWritingMode.horizontalTb);
    expect(override.direction, CssDirection.ltr);
  });

  test('overflow：枚举解析且不继承（W11）', () {
    expect(style('p', 'p { color: red; }').overflow, CssOverflow.visible);
    expect(style('p', 'p { overflow: hidden; }').overflow, CssOverflow.hidden);
    expect(style('p', 'p { overflow: clip; }').overflow, CssOverflow.clip);
    expect(style('p', 'p { overflow: scroll; }').overflow, CssOverflow.scroll);
    expect(style('p', 'p { overflow: auto; }').overflow, CssOverflow.auto);
    // 两轴写法只取首值；overflow-x 兜底。
    expect(
      style('p', 'p { overflow: hidden auto; }').overflow,
      CssOverflow.hidden,
    );
    expect(
      style('p', 'p { overflow-x: scroll; }').overflow,
      CssOverflow.scroll,
    );
    expect(
      style('p', 'p { overflow-y: hidden; }').overflow,
      CssOverflow.hidden,
    );
    expect(
      style('p', 'p { overflow-x: visible; overflow-y: clip; }').overflow,
      CssOverflow.clip,
    );
    expect(
      style('p', 'p { overflow-x: hidden; overflow-y: visible; }').overflow,
      CssOverflow.hidden,
    );
    // 不继承：父级 hidden，子级仍 visible。
    final parent = style('parent', 'div { overflow: hidden; }');
    expect(parent.overflow, CssOverflow.hidden);
    expect(
      style('p', 'p { color: red; }', parent: parent).overflow,
      CssOverflow.visible,
    );
  });

  test('columns：count/width/gap/rule 与 columns 简写（W11）', () {
    final count = style('p', 'p { columns: 2; }');
    expect(count.columnCount, 2);
    expect(count.columnWidth, isNull);

    final shorthand = style('p', 'p { columns: 3 60px; }');
    expect(shorthand.columnCount, 3);
    expect(shorthand.columnWidth!.value, 60);

    final widthOnly = style('p', 'p { columns: 200px; }');
    expect(widthOnly.columnCount, isNull);
    expect(widthOnly.columnWidth!.value, 200);

    final auto = style('p', 'p { columns: auto; }');
    expect(auto.columnCount, isNull);
    expect(auto.columnWidth, isNull);

    // 长属性：count 为整数、width 支持 em、gap 支持 normal/长度。
    final longhands = style(
      'p',
      'p { column-count: 4; column-width: 10em; column-gap: 16px; }',
    );
    expect(longhands.columnCount, 4);
    expect(longhands.columnWidth!.value, 160);
    expect(longhands.columnGap, 16);
    expect(style('p', 'p { column-gap: normal; }').columnGap, isNull);

    // 简写与长属性同时出现：长属性优先（简写只兜底）。
    final precedence = style('p', 'p { column-count: 5; columns: 2 100px; }');
    expect(precedence.columnCount, 5);
    expect(precedence.columnWidth!.value, 100);

    // column-rule 复用 CssBorderSide：`1px solid #999`。
    final rule = style('p', 'p { column-rule: 1px solid #999; }').columnRule!;
    expect(rule.width, 1);
    expect(rule.style, CssBorderStyle.solid);
    expect(rule.color, const Color(0xFF999999));
    expect(style('p', 'p { color: red; }').columnRule, isNull);

    // 不继承。
    final parent = style('parent', 'div { column-count: 3; }');
    expect(style('p', 'p { color: red; }', parent: parent).columnCount, isNull);
  });

  test('position: absolute 的解算规则（W18 定位）', () {
    final staticBox = style('p', 'p { top: 10px; left: 20px; }');
    expect(staticBox.isOutOfFlow, isFalse);
    expect(
      staticBox.resolveAbsoluteBox(containingWidth: 300, containingHeight: 400),
      isNull,
      reason: '非 absolute/fixed 不参与解算',
    );

    // 基本偏移 + 声明尺寸。
    final basic = style(
      'p',
      'p { position: absolute; top: 10px; left: 20px; '
          'width: 120px; height: 30px; }',
    );
    expect(basic.isOutOfFlow, isTrue);
    final box = basic.resolveAbsoluteBox(
      containingWidth: 350,
      containingHeight: 500,
    )!;
    expect(box.left, 20);
    expect(box.top, 10);
    expect(box.width, 120);
    expect(box.height, 30);
    // 尺寸已知时另一侧偏移由容器推出。
    expect(box.right, 350 - 20 - 120);
    expect(box.bottom, 500 - 10 - 30);

    // 百分比按包含块尺寸解算。
    final percent = style(
      'p',
      'p { position: absolute; left: 10%; top: 25%; }',
    ).resolveAbsoluteBox(containingWidth: 200, containingHeight: 400)!;
    expect(percent.left, 20);
    expect(percent.top, 100);
    expect(
      percent.width,
      isNull,
      reason: 'width: auto 且只有 left → 需要 shrink-to-fit',
    );

    // right + bottom（贴右下），宽高由声明给出 → left/top 反推。
    final bottomRight = style(
      'p',
      'p { position: absolute; right: 8px; bottom: 12px; '
          'width: 52px; height: 30px; }',
    ).resolveAbsoluteBox(containingWidth: 350, containingHeight: 480)!;
    expect(bottomRight.right, 8);
    expect(bottomRight.bottom, 12);
    expect(bottomRight.left, 350 - 8 - 52);
    expect(bottomRight.top, 480 - 12 - 30);

    // 53-display-position 的 .abs2：right/bottom + width，height auto。
    final autoHeight = style(
      'p',
      'p { position: absolute; right: 12px; bottom: 16px; width: 80px; }',
    ).resolveAbsoluteBox(containingWidth: 350, containingHeight: 800)!;
    expect(autoHeight.left, 350 - 12 - 80, reason: '贴右 → left 反推为 258');
    expect(autoHeight.width, 80);
    expect(autoHeight.bottom, 16);
    expect(
      autoHeight.top,
      isNull,
      reason: 'height: auto → 上边由内容高度 + bottom 决定',
    );

    // 两侧偏移都给、尺寸 auto → 尺寸由偏移推出（拉伸）。
    final stretch = style(
      'p',
      'p { position: absolute; left: 0; right: 0; top: 0; bottom: 0; }',
    ).resolveAbsoluteBox(containingWidth: 350, containingHeight: 500)!;
    expect(stretch.width, 350);
    expect(stretch.height, 500);

    // 外边距/边框/内边距要从拉伸尺寸里扣掉。
    final edged = style(
      'p',
      'p { position: absolute; left: 10px; right: 10px; top: 0; bottom: 0; '
          'margin: 4px 6px; padding: 2px 3px; border: 1px solid #000; }',
    ).resolveAbsoluteBox(containingWidth: 350, containingHeight: 500)!;
    // 水平边总 = margin 12 + padding 6 + border 2 = 20
    expect(edged.width, 350 - 10 - 10 - 20);
    // 垂直边总 = margin 8 + padding 4 + border 2 = 14
    expect(edged.height, 500 - 0 - 0 - 14);

    // border-box 的声明尺寸已经包含 padding/border，反推位置时只再扣 margin。
    final borderBoxEdged = style(
      'p',
      'p { position: absolute; box-sizing: border-box; right: 20px; '
          'bottom: 28px; width: 112px; height: 54px; '
          'margin: 4px 6px; padding: 5px; border: 3px solid #000; }',
    ).resolveAbsoluteBox(containingWidth: 350, containingHeight: 800)!;
    expect(borderBoxEdged.width, 112);
    expect(borderBoxEdged.height, 54);
    expect(borderBoxEdged.left, 350 - 20 - 112 - 12);
    expect(borderBoxEdged.top, 800 - 28 - 54 - 8);

    // min/max 约束参与。
    final clamped = style(
      'p',
      'p { position: absolute; left: 0; width: 900px; max-width: 200px; }',
    ).resolveAbsoluteBox(containingWidth: 350, containingHeight: 500)!;
    expect(clamped.width, 200);

    // fixed 也是脱离正常流（包含块=页面，由调用方传页面尺寸）。
    final fixed = style(
      'p',
      'p { position: fixed; left: 5px; top: 6px; width: 10px; height: 11px; }',
    );
    expect(fixed.isOutOfFlow, isTrue);
    final fixedBox = fixed.resolveAbsoluteBox(
      containingWidth: 350,
      containingHeight: 500,
    )!;
    expect(fixedBox.left, 5);
    expect(fixedBox.top, 6);
  });

  test('column-rule 线型（double/dotted/dashed/groove）不吞 columns（W18）', () {
    // 63-columns-rule 的 `.plain`：column-count 与 column-rule 必须各自生效。
    final doubled = style(
      'p',
      'p { column-count: 2; column-rule: 3px double #333; }',
    );
    expect(doubled.columnCount, 2, reason: '列数不能被 column-rule 影响');
    expect(doubled.columnRule, isNotNull);
    expect(doubled.columnRule!.style, CssBorderStyle.double);
    expect(doubled.columnRule!.width, 3);
    expect(doubled.columnRule!.color, const Color(0xFF333333));

    // `columns` 简写与 column-rule 并存（简写不能被误吞）。
    final shorthand = style(
      'p',
      'p { columns: 2; column-rule: 3px double #333; }',
    );
    expect(shorthand.columnCount, 2);
    expect(shorthand.columnRule!.style, CssBorderStyle.double);

    // 各线型原样保留（含 3D 线型）；未知线型（wavy）当无效声明，列数照常。
    for (final (keyword, expected) in <(String, CssBorderStyle)>[
      ('dotted', CssBorderStyle.dotted),
      ('dashed', CssBorderStyle.dashed),
      ('double', CssBorderStyle.double),
      ('groove', CssBorderStyle.groove),
      ('ridge', CssBorderStyle.ridge),
      ('inset', CssBorderStyle.inset),
      ('outset', CssBorderStyle.outset),
    ]) {
      final rule = style(
        'p',
        'p { column-count: 2; column-rule: 2px $keyword #123456; }',
      );
      expect(rule.columnCount, 2, reason: keyword);
      expect(rule.columnRule!.style, expected, reason: keyword);
      expect(rule.columnRule!.width, 2, reason: keyword);
      expect(rule.columnRule!.color, const Color(0xFF123456), reason: keyword);
    }
    final invalid = style(
      'p',
      'p { column-count: 2; column-rule: 3px wavy #333; }',
    );
    expect(invalid.columnCount, 2, reason: '未知线型只让 rule 失效');
    expect(invalid.columnRule?.style, CssBorderStyle.none);

    // none：宽度归零（与 border 语义一致）。
    final none = style(
      'p',
      'p { column-count: 2; column-rule: 3px none #333; }',
    );
    expect(none.columnCount, 2);
    expect(none.columnRule!.width, 0);
    expect(none.columnRule!.style, CssBorderStyle.none);
  });

  test('hyphens / word-break / overflow-wrap 解析与继承（W11）', () {
    final defaults = style('p', 'p { color: red; }');
    expect(defaults.hyphens, CssHyphens.manual);
    expect(defaults.wordBreak, CssWordBreak.normal);
    expect(defaults.overflowWrap, CssOverflowWrap.normal);

    expect(style('p', 'p { hyphens: auto; }').hyphens, CssHyphens.auto);
    expect(style('p', 'p { hyphens: none; }').hyphens, CssHyphens.none);
    // 私有/旧前缀经别名表落到 hyphens。
    expect(style('p', 'p { -epub-hyphens: auto; }').hyphens, CssHyphens.auto);
    expect(style('p', 'p { -webkit-hyphens: auto; }').hyphens, CssHyphens.auto);

    expect(
      style('p', 'p { word-break: break-all; }').wordBreak,
      CssWordBreak.breakAll,
    );
    expect(
      style('p', 'p { word-break: keep-all; }').wordBreak,
      CssWordBreak.keepAll,
    );

    expect(
      style('p', 'p { overflow-wrap: break-word; }').overflowWrap,
      CssOverflowWrap.breakWord,
    );
    expect(
      style('p', 'p { overflow-wrap: anywhere; }').overflowWrap,
      CssOverflowWrap.anywhere,
    );
    // 旧名 word-wrap 兜底（别名表未登记该旧名）。
    expect(
      style('p', 'p { word-wrap: break-word; }').overflowWrap,
      CssOverflowWrap.breakWord,
    );

    // 三者都继承。
    final parent = style(
      'parent',
      'div { hyphens: auto; word-break: break-all; '
          'overflow-wrap: anywhere; }',
    );
    final child = style('p', 'p { color: red; }', parent: parent);
    expect(child.hyphens, CssHyphens.auto);
    expect(child.wordBreak, CssWordBreak.breakAll);
    expect(child.overflowWrap, CssOverflowWrap.anywhere);
  });

  test('font 简写重置子属性（line-height/font-variant/stretch/adjust）（W18）', () {
    // 父级/同元素其它规则给出的子属性会被 font 简写重置为初始值。
    final parent = style(
      'parent',
      'div { line-height: 2; font-weight: 700; font-style: italic; '
          'font-variant: small-caps; font-stretch: condensed; '
          'font-size-adjust: 0.5; }',
    );
    final reset = style('p', 'p { font: 16px serif; }', parent: parent);
    expect(reset.fontSize, 16);
    expect(reset.lineHeightFactor, isNull, reason: 'line-height 重置为 normal');
    expect(reset.fontWeight, 400, reason: 'font-weight 重置为 normal');
    expect(reset.italic, isFalse, reason: 'font-style 重置为 normal');
    expect(reset.fontVariantCaps, CssFontVariantCaps.normal);
    expect(reset.fontStretch, 100, reason: 'font-stretch 重置为 normal');
    expect(reset.fontSizeAdjust, isNull, reason: 'font-size-adjust 重置为 none');
    expect(reset.fontFamilies, contains('serif'));

    // 简写里写出的子属性照常生效。
    final full = style(
      'p',
      'p { font: italic small-caps bold condensed 16px/1.5 serif; }',
    );
    expect(full.italic, isTrue);
    expect(full.fontVariantCaps, CssFontVariantCaps.smallCaps);
    expect(full.fontWeight, 700);
    expect(full.fontStretch, 75);
    expect(full.lineHeight, closeTo(24, 0.001));
    expect(full.fontSize, 16);

    // 缺字体族 → 整条声明无效（不重置、不生效）。
    final invalid = style('p', 'p { font: bold 16px; }', parent: parent);
    expect(invalid.fontSize, 16, reason: '继承父级字号，说明声明被忽略');
    expect(invalid.fontWeight, 700, reason: '父级字重保留，说明未重置');
    expect(invalid.lineHeightFactor, 2);
  });

  test('font-stretch / font-size-adjust 字段与继承（W18）', () {
    final defaults = style('p', 'p { color: red; }');
    expect(defaults.fontStretch, 100);
    expect(defaults.fontSizeAdjust, isNull);

    expect(style('p', 'p { font-stretch: condensed; }').fontStretch, 75);
    expect(style('p', 'p { font-stretch: semi-expanded; }').fontStretch, 112.5);
    expect(style('p', 'p { font-stretch: ultra-expanded; }').fontStretch, 200);
    expect(style('p', 'p { font-stretch: 87.5%; }').fontStretch, 87.5);
    expect(style('p', 'p { font-stretch: 120%; }').fontStretch, 120);
    // 非法值回退继承/初始。
    expect(style('p', 'p { font-stretch: 10%; }').fontStretch, 100);

    expect(style('p', 'p { font-size-adjust: 0.5; }').fontSizeAdjust, 0.5);
    // none 显式重置（不继承父级）。
    final parent = style(
      'parent',
      'div { font-size-adjust: 0.5; font-stretch: expanded; }',
    );
    expect(
      style('p', 'p { color: red; }', parent: parent).fontSizeAdjust,
      0.5,
      reason: '继承',
    );
    expect(
      style(
        'p',
        'p { font-size-adjust: none; }',
        parent: parent,
      ).fontSizeAdjust,
      isNull,
      reason: 'none 覆盖继承值',
    );
    expect(
      style('p', 'p { color: red; }', parent: parent).fontStretch,
      125,
      reason: 'font-stretch 继承',
    );
  });

  test('font 简写：系统字体关键字（W18）', () {
    for (final keyword in const <String>[
      'caption',
      'icon',
      'menu',
      'message-box',
      'small-caption',
      'status-bar',
    ]) {
      final system = style('p', 'p { font: $keyword; }');
      expect(system.fontSize, 16, reason: keyword);
      expect(system.fontFamilies.first.toLowerCase(), 'arial', reason: keyword);
      expect(system.fontWeight, 400, reason: keyword);
      expect(system.italic, isFalse, reason: keyword);
      expect(system.lineHeightFactor, isNull, reason: keyword);
      expect(system.fontStretch, 100, reason: keyword);
    }
    // -webkit- 前缀同样识别。
    expect(style('p', 'p { font: -webkit-caption; }').fontSize, 16);
  });

  test('font-variant：small-caps 族与 font 简写 token（W18）', () {
    final defaults = style('p', 'p { color: red; }');
    expect(defaults.fontVariantCaps, CssFontVariantCaps.normal);

    expect(
      style('p', 'p { font-variant: small-caps; }').fontVariantCaps,
      CssFontVariantCaps.smallCaps,
    );
    expect(
      style('p', 'p { font-variant-caps: all-small-caps; }').fontVariantCaps,
      CssFontVariantCaps.allSmallCaps,
    );
    expect(
      style(
        'p',
        'p { font-variant: petite-caps oldstyle-nums; }',
      ).fontVariantCaps,
      CssFontVariantCaps.petiteCaps,
      reason: '多 token 简写里取 caps 关键字，数值变体忽略',
    );
    expect(
      style('p', 'p { font-variant-caps: unicase; }').fontVariantCaps,
      CssFontVariantCaps.unicase,
    );
    // 长属性优先于简写。
    expect(
      style(
        'p',
        'p { font-variant: small-caps; font-variant-caps: titling-caps; }',
      ).fontVariantCaps,
      CssFontVariantCaps.titlingCaps,
    );
    // `font` 简写里的 small-caps token。
    final shorthand = style('p', 'p { font: small-caps 12px/2 serif; }');
    expect(shorthand.fontVariantCaps, CssFontVariantCaps.smallCaps);
    expect(shorthand.fontSize, 12);
    expect(shorthand.lineHeight, 24);

    // 继承。
    final parent = style('parent', 'div { font-variant: small-caps; }');
    expect(
      style('p', 'p { color: red; }', parent: parent).fontVariantCaps,
      CssFontVariantCaps.smallCaps,
    );
  });

  test('逻辑属性：inline/block 按 writing-mode + direction 落物理（W18）', () {
    // horizontal-tb + ltr：inline-start = left，block-start = top。
    final ltr = style(
      'p',
      'p { margin-inline-start: 10px; margin-inline-end: 2px; '
          'margin-block-start: 4px; margin-block-end: 6px; }',
    );
    expect(ltr.margin.left, 10);
    expect(ltr.margin.right, 2);
    expect(ltr.margin.top, 4);
    expect(ltr.margin.bottom, 6);

    // padding 同理。
    final padding = style(
      'p',
      'p { padding-inline-start: 7px; padding-inline-end: 3px; }',
    );
    expect(padding.padding.left, 7);
    expect(padding.padding.right, 3);
    expect(padding.padding.top, 0);

    // border-inline-* 映射到 border-left/right 简写与长属性。
    final border = style(
      'p',
      'p { border-inline-start: 2px solid #ff0000; '
          'border-inline-end-color: #00ff00; }',
    );
    expect(border.borders.left.width, 2);
    expect(border.borders.left.style, CssBorderStyle.solid);
    expect(border.borders.left.color, const Color(0xFFFF0000));
    expect(border.borders.right.color, const Color(0xFF00FF00));

    // direction: rtl 时 inline-start = right。
    final rtl = style('p', 'p { direction: rtl; margin-inline-start: 9px; }');
    expect(rtl.margin.right, 9);
    expect(rtl.margin.left, 0);

    // vertical-rl：行内轴竖直（inline-start = top），块级轴从右往左。
    final vertical = style(
      'p',
      'p { writing-mode: vertical-rl; margin-inline-start: 11px; '
          'margin-block-start: 13px; }',
    );
    expect(vertical.margin.top, 11);
    expect(vertical.margin.right, 13);
    expect(vertical.margin.left, 0);

    // vertical-lr：块级推进从左往右。
    final verticalLr = style(
      'p',
      'p { writing-mode: vertical-lr; margin-block-start: 5px; }',
    );
    expect(verticalLr.margin.left, 5);

    // 竖排 + rtl：行内方向自下而上 → inline-start = bottom。
    final verticalRtl = style(
      'p',
      'p { writing-mode: vertical-rl; direction: rtl; '
          'margin-inline-start: 3px; }',
    );
    expect(verticalRtl.margin.bottom, 3);

    // 同一条规则内物理与逻辑并存：后声明者胜（与浏览器一致，逻辑属性
    // 在级联期映射成同一物理属性参与竞争）。
    final both = style(
      'p',
      'p { margin-left: 1px; margin-inline-start: 20px; }',
    );
    expect(both.margin.left, 20);
    final reverse = style(
      'p',
      'p { margin-inline-start: 20px; margin-left: 1px; }',
    );
    expect(reverse.margin.left, 1);

    // inset-inline-start 落到 left（left 字段是 CssLength）。
    final inset = style('p', 'p { inset-inline-start: 8px; }');
    expect(inset.left!.value, 8);
  });

  test('逻辑属性在级联期映射：简写与逻辑属性按优先级竞争（W18 修复）', () {
    // `p{margin:8px 0}` 展开出 margin-left:0；`#p{margin-inline-start:24px}`
    // 优先级更高 → 必须赢（此前物理优先的近似会被展开出的 0 顶掉）。
    final higher = style(
      'p',
      'p { margin: 8px 0; } #p { margin-inline-start: 24px; }',
    );
    expect(higher.margin.top, 8);
    expect(higher.margin.left, 24);
    expect(higher.margin.right, 0);

    // 反过来：简写优先级更高（#p 的简写 vs p 的逻辑属性）→ 简写值胜。
    final lower = style(
      'p',
      'p { margin-inline-start: 24px; } #p { margin: 8px 0; }',
    );
    expect(lower.margin.left, 0, reason: '高优先级的简写展开覆盖逻辑属性');
    expect(lower.margin.top, 8);

    // rtl 由祖先继承：inline-start 落到右侧。
    final rtlParent = style('parent', 'div { direction: rtl; }');
    final rtlChild = style(
      'p',
      'p { padding-inline-start: 12px; border-inline-start: 3px solid #123456; }',
      parent: rtlParent,
    );
    expect(rtlChild.padding.right, 12);
    expect(rtlChild.padding.left, 0);
    expect(rtlChild.borders.right.width, 3);
    expect(rtlChild.borders.right.color, const Color(0xFF123456));
    expect(rtlChild.borders.left.width, 0);

    // 竖排：-webkit-margin-start 走逻辑映射（inline-start = top）。
    final vertical = style(
      'p',
      'p { writing-mode: vertical-rl; -webkit-margin-start: 7px; }',
    );
    expect(vertical.margin.top, 7);
    expect(vertical.margin.left, 0);
    // rtl 下 -webkit-padding-start → 右。
    final rtl = style('p', 'p { direction: rtl; -webkit-padding-start: 5px; }');
    expect(rtl.padding.right, 5);
  });

  test('direction: rtl 参与对齐映射与行内 baseDirection（W18）', () {
    final ltr = style('p', 'p { text-align: start; }');
    expect(ltr.isRtl, isFalse);
    expect(ltr.resolvedTextAlign, CssTextAlign.left);
    expect(
      style('p', 'p { text-align: end; }').resolvedTextAlign,
      CssTextAlign.right,
    );

    final rtl = style('p', 'p { direction: rtl; text-align: start; }');
    expect(rtl.isRtl, isTrue);
    expect(rtl.resolvedTextAlign, CssTextAlign.right);
    expect(
      style('p', 'p { direction: rtl; text-align: end; }').resolvedTextAlign,
      CssTextAlign.left,
    );
    // left/right/center/justify 不受 direction 影响。
    expect(
      style('p', 'p { direction: rtl; text-align: left; }').resolvedTextAlign,
      CssTextAlign.left,
    );
    expect(
      style(
        'p',
        'p { direction: rtl; text-align: justify; }',
      ).resolvedTextAlign,
      CssTextAlign.justify,
    );
    // 默认 start（未声明）在 rtl 下也应右对齐。
    expect(
      style('p', 'p { direction: rtl; }').resolvedTextAlign,
      CssTextAlign.right,
    );
  });

  test('quotes：引号对结构 / none / auto 与继承（W18）', () {
    // 初始值 auto。
    expect(style('p', 'p { color: red; }').quotes, isA<CssQuotesAuto>());

    final pairs = style('p', 'p { quotes: "«" "»" "‹" "›"; }').quotes;
    expect(pairs, isA<CssQuotesPairs>());
    final list = (pairs as CssQuotesPairs).pairs;
    expect(list, hasLength(2));
    expect(list.first.open, '«');
    expect(list.first.close, '»');
    expect(list.last.open, '‹');
    expect(list.last.close, '›');

    // 单引号包裹同样识别；转义引号解包。
    final single =
        style('p', "p { quotes: '“' '”' '\\201c' 'x'; }").quotes
            as CssQuotesPairs;
    expect(single.pairs.first.open, '“');
    expect(single.pairs.first.close, '”');
    expect(single.pairs.last.open, '“', reason: '\\201c 解成 “');

    expect(style('p', 'p { quotes: none; }').quotes, isA<CssQuotesNone>());
    expect(style('p', 'p { quotes: auto; }').quotes, isA<CssQuotesAuto>());

    // 奇数个字符串 = 声明无效 → 回退父级/初始值。
    expect(
      style('p', 'p { quotes: "«" "»" "‹"; }').quotes,
      isA<CssQuotesAuto>(),
    );

    // 继承。
    final parent = style('parent', 'div { quotes: "「" "」"; }');
    final inherited = style('p', 'p { color: red; }', parent: parent).quotes;
    expect(inherited, isA<CssQuotesPairs>());
    expect((inherited as CssQuotesPairs).pairs.single.open, '「');
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

  test('负 padding 使整条声明无效', () {
    final negative = style('p', 'p { padding: -4px 8px; }');
    expect(negative.padding.top, 0);
    expect(negative.padding.right, 0);
    expect(negative.padding.bottom, 0);
    expect(negative.padding.left, 0);

    final longhand = style('p', 'p { padding-top: 4px; padding-top: -1em; }');
    expect(longhand.padding.top, 4);
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

  test('contentBoxWidth：border-box 的 width 要扣 padding/border', () {
    // 对照用例 09 `.bb`：350 版心宽下 border-box 200px 含 10px padding、
    // 3px 边框 → 内容宽 200-20-6=174（浏览器行宽 166.2/171.7，均 ≤174）。
    final borderBox = style(
      'p',
      'p { box-sizing: border-box; width: 200px; padding: 10px; '
          'border: 3px solid #cc3366; }',
    );
    expect(borderBox.contentBoxWidth(350), 174);

    // 同一声明在 content-box 下内容宽就是 200。
    final contentBox = style(
      'p',
      'p { box-sizing: content-box; width: 200px; padding: 10px; '
          'border: 3px solid #cc3366; }',
    );
    expect(contentBox.contentBoxWidth(350), 200);

    // 对照用例 09 `.box`：未声明 width，版心 350 扣 margin 40 +
    // padding 32 + border 4 = 274（浏览器行宽 233.8/270.9）。
    final auto = style(
      'p',
      'p { margin: 10px 20px; padding: 8px 16px; '
          'border: 2px solid #3366cc; }',
    );
    expect(auto.contentBoxWidth(350), 274);

    // 百分比 width 按传入的包含块宽解算；min/max 钳制且 min 优先。
    final percent = style('p', 'p { width: 50%; padding: 5px; }');
    expect(percent.contentBoxWidth(300), 150);
    final clamped = style(
      'p',
      'p { width: 100px; min-width: 180px; max-width: 120px; }',
    );
    expect(clamped.contentBoxWidth(350), 180, reason: 'min 优先于 max');
    // 可用宽不足时钳到 0，不返回负数。
    expect(auto.contentBoxWidth(10), 0);

    // 与 layout 层 BoxModel 保持同一口径（防止两处实现分叉）。
    for (final candidate in <ComputedStyle>[borderBox, contentBox, auto]) {
      expect(
        candidate.contentBoxWidth(350),
        BoxModel.fromStyle(
          candidate,
          containingWidth: 350,
        ).resolveContentWidth(350),
      );
    }
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
    // 根元素：父级字号取 rootFontSize 16；Chrome 公式 -（父字号/3 + 1）。
    expect(parsed.verticalAlignShift, closeTo(-(16 / 3 + 1), 0.001));

    final em = style(
      'p',
      'p { word-spacing: 0.5em; text-transform: capitalize; '
          'vertical-align: sub; }',
    );
    expect(em.wordSpacing, 8);
    expect(em.textTransform, CssTextTransform.capitalize);
    expect(em.verticalAlignShift, closeTo(16 / 5 + 1, 0.001));

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

  test('vertical-align: super/sub 按父级字号偏移（Chrome 实测口径）', () {
    // Chrome（headless 155）实测：父字号 17px 时 super=-6.66、sub=+4.39，
    // 且与子元素自身字号无关（0.7em/2em 子字号偏移不变）；父字号 8–100px
    // 线性拟合为 super=-(父字号/3+1)、sub=父字号/5+1。
    final parent = style('parent', 'div { font-size: 17px; }');
    final sup = style(
      'p',
      'p { vertical-align: super; font-size: 0.7em; }',
      parent: parent,
    );
    expect(sup.fontSize, closeTo(11.9, 0.001));
    expect(sup.verticalAlignShift, closeTo(-6.66, 0.01));

    final sub = style(
      'p',
      'p { vertical-align: sub; font-size: 2em; }',
      parent: parent,
    );
    expect(sub.fontSize, 34);
    // 17/5+1 = 4.4；Chrome 内部按 1/64 像素取整后报 4.39，差值在取整精度内。
    expect(sub.verticalAlignShift, closeTo(4.4, 0.02), reason: '子字号不参与');

    // middle/top/bottom 不产生基线偏移（保持不变，行排版层按行盒处理）。
    for (final value in const <String>['middle', 'top', 'bottom']) {
      final other = style('p', 'p { vertical-align: $value; }', parent: parent);
      expect(other.verticalAlignShift, 0, reason: value);
    }
  });

  test('text-spacing-trim 默认与 Chrome normal 一致（相邻全角标点折叠）', () {
    // Chrome 的 text-spacing-trim 初始值是 normal，且会折叠相邻全角标点
    // （对照用例 01：「：、」实测各 8.5px，space-all 下各 17px），所以引擎
    // 未声明时必须默认开启挤压，否则同一行宽下比浏览器宽出半个标点。
    expect(
      ComputedStyle(const <String, String>{}).textSpacingTrim,
      CssTextSpacingTrim.trimAdjacent,
    );
    expect(
      style('p', 'p { text-spacing-trim: normal; }').textSpacingTrim,
      CssTextSpacingTrim.trimAdjacent,
    );
    expect(
      style('p', 'p { text-spacing-trim: space-all; }').textSpacingTrim,
      CssTextSpacingTrim.normal,
      reason: 'space-all = 全部保持全角 = 不挤压',
    );
    expect(
      style('p', 'p { text-spacing-trim: trim-start; }').textSpacingTrim,
      CssTextSpacingTrim.trimAdjacent,
      reason: '行首半角未实现，按 normal 的相邻折叠近似',
    );

    final spaced = style('parent', 'div { text-spacing-trim: space-all; }');
    final inherited = style('p', 'p { color: red; }', parent: spaced);
    expect(inherited.textSpacingTrim, CssTextSpacingTrim.normal, reason: '继承');
  });

  test('text-transform 的 full-width / small-caps 与 Chrome 一致回退 none', () {
    // Chrome 149/155 实测：CSS.supports('text-transform','full-width') 与
    // ('…','small-caps') 均为 false，计算值 none（对照用例 08 两侧行宽一致）。
    // 引擎同样只认 none/uppercase/lowercase/capitalize，未知值回退 none。
    expect(
      style('p', 'p { text-transform: full-width; }').textTransform,
      CssTextTransform.none,
    );
    expect(
      style('p', 'p { text-transform: small-caps; }').textTransform,
      CssTextTransform.none,
    );
  });

  test('vertical-align: <length> / <percentage>（W2）', () {
    final px = style('p', 'p { vertical-align: 10px; }');
    expect(
      px.verticalAlign,
      CssVerticalAlign.baseline,
      reason: '枚举仍是 baseline',
    );
    expect(px.verticalAlignLength, 10);
    expect(px.verticalAlignShift, -10, reason: 'CSS 正值向上，位移取负');

    final em = style('p', 'p { font-size: 20px; vertical-align: -0.5em; }');
    expect(em.verticalAlignLength, -10);
    expect(em.verticalAlignShift, 10);

    // 百分比按本元素行高：Chrome 实测 17px/1.6 → 行高 27.2，10% = 2.72px。
    final percent = style(
      'p',
      'p { font-size: 17px; line-height: 1.6; vertical-align: 10%; }',
    );
    expect(percent.lineHeight, closeTo(27.2, 0.01));
    expect(percent.verticalAlignLength, closeTo(2.72, 0.01));
    expect(percent.verticalAlignShift, closeTo(-2.72, 0.01));

    // 关键字不进长度分支，super/sub 仍走父字号公式。
    final middle = style('p', 'p { vertical-align: middle; }');
    expect(middle.verticalAlignLength, isNull);
    expect(middle.verticalAlignShift, 0);
    final sup = style('p', 'p { vertical-align: super; }');
    expect(sup.verticalAlignLength, isNull);
    expect(sup.verticalAlignShift, closeTo(-(16 / 3 + 1), 0.001));
  });

  test('list-style-position 解析、简写展开且继承（W2）', () {
    expect(
      ComputedStyle(const <String, String>{}).listStylePosition,
      CssListStylePosition.outside,
      reason: '初始 outside',
    );
    expect(
      style('p', 'p { list-style-position: inside; }').listStylePosition,
      CssListStylePosition.inside,
    );
    // 简写在层叠层展开：`list-style: square inside` 两个长属性都要生效。
    final shorthand = style('p', 'p { list-style: square inside; }');
    expect(shorthand.listStyleType, CssListStyleType.square);
    expect(shorthand.listStylePosition, CssListStylePosition.inside);
    expect(
      style('p', 'p { list-style: none outside; }').listStylePosition,
      CssListStylePosition.outside,
    );

    final parent = style('parent', 'div { list-style-position: inside; }');
    final child = style('p', 'p { color: red; }', parent: parent);
    expect(
      child.listStylePosition,
      CssListStylePosition.inside,
      reason: 'list-style-position 按 CSS 继承父值',
    );
    // 未知值回退 outside。
    expect(
      style('p', 'p { list-style-position: bogus; }').listStylePosition,
      CssListStylePosition.outside,
    );
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
    final combined = style(
      'p',
      'p { text-decoration: underline line-through overline; }',
    );
    expect(
      combined.textDecoration,
      CssTextDecoration.underlineLineThroughOverline,
    );
    expect(combined.textDecoration.hasUnderline, isTrue);
    expect(combined.textDecoration.hasLineThrough, isTrue);
    expect(combined.textDecoration.hasOverline, isTrue);
    final none = style('p', 'p { text-decoration: none; }');
    expect(none.textDecoration, CssTextDecoration.none);

    final filled = style('p', 'p { text-emphasis: filled; }');
    expect(filled.textEmphasisStyle, CssTextEmphasisStyle.dot);
    final open = style('p', 'p { text-emphasis-style: open; }');
    expect(open.textEmphasisStyle, CssTextEmphasisStyle.openDot);
    final circle = style('p', 'p { text-emphasis-style: open circle; }');
    expect(circle.textEmphasisStyle, CssTextEmphasisStyle.openCircle);
    final sesame = style('p', 'p { text-emphasis-style: filled sesame; }');
    expect(sesame.textEmphasisStyle, CssTextEmphasisStyle.sesame);

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

  test('ruby-align 仅接受规范值，默认 space-around，非法值继承', () {
    expect(
      ComputedStyle(const <String, String>{}).rubyAlign,
      CssRubyAlign.spaceAround,
    );
    expect(
      style('p', 'p { ruby-align: start; }').rubyAlign,
      CssRubyAlign.start,
    );
    expect(
      style('p', 'p { ruby-align: space-between; }').rubyAlign,
      CssRubyAlign.spaceBetween,
    );

    final parent = style('parent', 'div { ruby-align: center; }');
    expect(
      style('p', 'p { ruby-align: end; }', parent: parent).rubyAlign,
      CssRubyAlign.center,
      reason: 'end 不是 CSS Ruby 1 的合法 ruby-align 值',
    );
  });
}
