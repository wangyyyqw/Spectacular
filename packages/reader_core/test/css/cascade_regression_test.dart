import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';

void main() {
  test('显式 inherit/unset 继承相对属性的计算值', () {
    final parent = _compute(
      'font-size:150%; line-height:150%; font-weight:bolder; '
      'letter-spacing:0.5em; word-spacing:1em;',
    );
    for (final keyword in ['inherit', 'unset']) {
      final child = _compute(
        'font-size:$keyword; line-height:$keyword; font-weight:$keyword; '
        'letter-spacing:$keyword; word-spacing:$keyword;',
        parent: parent,
      );
      expect(child.fontSize, 24);
      expect(child.lineHeight, 36);
      expect(child.fontWeight, 700);
      expect(child.letterSpacing, 12);
      expect(child.wordSpacing, 24);
    }
  });

  test('继承绝对行高与无单位行高保留各自语义', () {
    final fixed = _compute('font-size:20px; line-height:150%');
    final ratio = _compute('font-size:20px; line-height:1.5');
    expect(
      _compute('font-size:10px;line-height:inherit', parent: fixed).lineHeight,
      30,
    );
    expect(
      _compute('font-size:10px;line-height:inherit', parent: ratio).lineHeight,
      15,
    );
  });

  test('initial 重置继承属性，unset 重置非继承属性', () {
    final parent = _compute(
      'color:red; font-size:24px; line-height:2; '
      'word-spacing:8px; visibility:hidden; direction:rtl;',
    );
    final child = _compute(
      'color:initial; font-size:initial; line-height:initial; '
      'word-spacing:initial; visibility:initial; direction:initial; '
      'margin:12px; margin:unset;',
      parent: parent,
    );
    expect(child.color, const Color(0xff000000));
    expect(child.fontSize, 16);
    expect(child.lineHeightFactor, isNull);
    expect(child.wordSpacing, 0);
    expect(child.visibility, CssVisibility.visible);
    expect(child.direction, CssDirection.ltr);
    expect(child.margin.top, 0);
  });

  test('显式继承非继承盒边属性不重复计算 em', () {
    final parent = _compute(
      'font-size:20px; margin:2em; padding:1em; '
      'border:0.5em solid rgba(255, 0, 0, 0.5)',
    );
    final child = _compute(
      'font-size:10px; margin:inherit; padding:inherit; '
      'border:inherit',
      parent: parent,
    );
    expect(child.margin.left, 40);
    expect(child.padding.left, 20);
    expect(child.borders.top.width, 10);
    expect(child.borders.top.color.a, closeTo(0.5, 0.01));
  });

  test('普通无效声明不能覆盖此前有效声明', () {
    final style = _compute(
      'font-size:20px;font-size:nonsense; '
      'color:red;color:invalid; padding:4px; padding:-1px 8px; '
      'border:2px solid red;border:garbage;',
    );
    expect(style.fontSize, 20);
    expect(style.color, const Color(0xffff0000));
    expect(style.padding.right, 4);
    expect(style.borders.top.width, 2);
  });

  test('没有任何自定义属性时仍使用 var 回退', () {
    expect(
      _compute('color:var(--missing, red)').color,
      const Color(0xffff0000),
    );
  });

  test('自定义属性区分大小写并保持父级已求值的别名', () {
    final parent = _compute('--Ink:red; --ink:blue; --alias:var(--Ink);');
    final child = _compute(
      '--Ink:green; color:var(--alias); '
      'background-color:var(--ink)',
      parent: parent,
    );
    expect(child.color, const Color(0xffff0000));
    expect(child.backgroundColor, const Color(0xff0000ff));
  });

  test('变量替换后再展开多值简写并保留长属性顺序', () {
    final style = _compute(
      '--space:1px 2px; --edge:3px solid blue; '
      'margin-left:9px; margin:var(--space); margin-bottom:4px; '
      'border-top-width:8px;border:var(--edge);',
    );
    expect(style.margin.top, 1);
    expect(style.margin.right, 2);
    expect(style.margin.bottom, 4);
    expect(style.margin.left, 2);
    expect(style.borders.top.width, 3);
  });

  test('变量替换后无效时按 unset 处理，不复活旧声明', () {
    final style = _compute(
      '--bad:nonsense; font-size:20px; '
      'font-size:var(--bad); padding:8px; padding:var(--missing)',
    );
    expect(style.fontSize, 16);
    expect(style.padding.left, 0);
  });

  test('inset 简写按 1~4 值展开并与长属性按顺序竞争', () {
    final one = _compute('inset:10px');
    expect(one.top!.value, 10);
    expect(one.right!.value, 10);
    expect(one.bottom!.value, 10);
    expect(one.left!.value, 10);

    final two = _compute('inset:1px 2px');
    expect(two.top!.value, 1);
    expect(two.right!.value, 2);
    expect(two.bottom!.value, 1);
    expect(two.left!.value, 2);

    final three = _compute('inset:1px 2px 3px');
    expect(three.top!.value, 1);
    expect(three.right!.value, 2);
    expect(three.bottom!.value, 3);
    expect(three.left!.value, 2);

    final four = _compute('inset:1px 2px 3px 4px');
    expect(four.top!.value, 1);
    expect(four.right!.value, 2);
    expect(four.bottom!.value, 3);
    expect(four.left!.value, 4);

    expect(_compute('left:9px; inset:4px').left!.value, 4);
    expect(_compute('inset:4px; left:9px').left!.value, 9);
    expect(
      _compute('left:9px!important; inset:4px').left!.value,
      9,
      reason: 'important 长属性不能被普通简写覆盖',
    );
  });

  test('inset 简写拒绝无效值且变量替换后重新展开', () {
    final style = _compute(
      'inset:7px; inset:nonsense; --edge:1px 2px 3px 4px; inset:var(--edge)',
    );
    expect(style.top!.value, 1);
    expect(style.right!.value, 2);
    expect(style.bottom!.value, 3);
    expect(style.left!.value, 4);

    final invalid = _compute('inset:7px; inset:1px nonsense');
    expect(invalid.top!.value, 7);
    expect(invalid.right!.value, 7);
  });

  test('边框简写与长属性按声明顺序和 important 竞争', () {
    expect(
      _compute('border-top-width:9px;border:1px solid red').borders.top.width,
      1,
    );
    expect(
      _compute('border:1px solid red;border-top-width:9px').borders.top.width,
      9,
    );
    expect(
      _compute('border-top-width:9px!important;border:1px solid red')
          .borders
          .top
          .width,
      9,
    );
    expect(
      _compute('border-top-width:9px;border:1px solid red!important')
          .borders
          .top
          .width,
      1,
    );
  });

  test('零宽边框与缺省 medium 边框能够区分', () {
    expect(_compute('border:0 solid red').borders.top.width, 0);
    expect(_compute('border:solid red').borders.top.width, 3);
    expect(_compute('border:thin solid red').borders.top.width, 1);
    expect(
      _compute('border:2px solid red; border-top-width:0').borders.top.width,
      0,
    );
  });

  test('命名颜色不会使合法边框声明被过滤', () {
    final style = _compute(
      'border:1px solid black; border-left:2px solid gold',
    );
    expect(style.borders.left.width, 2);
    expect(style.borders.left.color, const Color(0xffffd700));
  });

  test('媒体查询关键词不区分大小写', () {
    expect(
      Cascade.mediaMatches('ONLY SCREEN AND (MIN-WIDTH: 300PX)', 350),
      isTrue,
    );
    expect(Cascade.mediaMatches('NOT PRINT', 350), isTrue);
  });

  test('全局关键词不区分大小写', () {
    final parent = _compute('font-size:150%; color:red;');
    final child = _compute('font-size:INHERIT; color:INITIAL;', parent: parent);
    expect(child.fontSize, 24);
    expect(child.color, const Color(0xff000000));
  });
}

ComputedStyle _compute(String declarations, {ComputedStyle? parent}) =>
    Cascade.compute(
      element: const _Element(),
      ancestors: const [],
      rules: CascadeRule.fromStylesheet(
        CssParser.parse('p { $declarations }'),
        origin: CascadeOrigin.author,
      ),
      parent: parent,
      containingWidth: 350,
    );

class _Element implements SelectorElement {
  const _Element();

  @override
  String get tag => 'p';

  @override
  Map<String, String> get attributes => const {};

  @override
  List<SelectorElement> get childElements => const [];
}
