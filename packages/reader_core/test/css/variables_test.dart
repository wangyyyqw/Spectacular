import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/css/ua_stylesheet.dart';

/// P9-14/P9-15：自定义属性（var）与 calc() 表达式。
void main() {
  ComputedStyle compute(
    String declarations, {
    ComputedStyle? parent,
    double containingWidth = 300,
  }) {
    final rules = <CascadeRule>[
      ...uaRules(),
      ...CascadeRule.fromStylesheet(
        CssParser.parse('p { $declarations }'),
        origin: CascadeOrigin.author,
        startOrder: 1000,
      ),
    ];
    return Cascade.compute(
      element: const _Element('p', <String, String>{}),
      ancestors: const <SelectorElement>[],
      rules: rules,
      parent: parent,
      containingWidth: containingWidth,
    );
  }

  ComputedStyle parentWith(Map<String, String> variables) => ComputedStyle(
    Map<String, String>.unmodifiable(variables),
    customProperties: variables,
    parent: null,
  );

  test('var() 取父级自定义属性', () {
    final parent = parentWith(const <String, String>{'--main': '#ff0000'});
    expect(compute('color: var(--main)', parent: parent).color,
        const Color(0xFFFF0000));
    expect(compute('font-size: var(--missing)', parent: parent).fontSize, 16);
  });

  test('var() 回退值与嵌套引用', () {
    final parent = parentWith(const <String, String>{
      '--accent': '#00ff00',
      '--alias': 'var(--accent)',
    });
    expect(
      compute('color: var(--missing, var(--alias))', parent: parent).color,
      const Color(0xFF00FF00),
    );
  });

  test('var() 循环引用不挂死且有回退', () {
    final parent = parentWith(const <String, String>{
      '--a': 'var(--b)',
      '--b': 'var(--a)',
    });
    expect(
      compute('color: var(--a, #0000ff)', parent: parent).color,
      const Color(0xFF0000FF),
    );
  });

  test('calc() 数值运算与百分比', () {
    expect(
      compute('width: calc(100% - 20px)').width!.value,
      closeTo(280, 0.01),
    );
    expect(
      compute('padding-left: calc(1em + 4px)').padding.left,
      closeTo(20, 0.01),
    );
    expect(
      compute('letter-spacing: calc(0.5px * 2)').letterSpacing,
      closeTo(1, 0.01),
    );
    expect(
      compute('text-indent: calc((100% - 40px) / 2)').textIndent,
      closeTo(130, 0.01),
    );
  });

  test('calc() 非法表达式回退默认值', () {
    expect(compute('width: calc(100% - )').width, isNull);
    expect(compute('width: calc(10px / 0)').width, isNull);
  });
}

class _Element implements SelectorElement {
  const _Element(this.tag, this.attributes);

  @override
  final String tag;

  @override
  final Map<String, String> attributes;

  @override
  List<SelectorElement> get childElements => const <SelectorElement>[];
}
