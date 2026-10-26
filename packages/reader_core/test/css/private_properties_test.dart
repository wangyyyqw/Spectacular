import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/css/ua_stylesheet.dart';

/// P9-13：多看/掌阅私有属性在解析入口改名后，走标准属性链路生效。
void main() {
  ComputedStyle compute(String declarations) {
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
    );
  }

  test('多看缩进/对齐/断行私有属性', () {
    expect(compute('-duokan-text-indent: 2em').textIndent, 32);
    expect(compute('duokan-text-indent: 1em').textIndent, 16);
    expect(
      compute('duokan-paragraph-align: center').textAlign,
      CssTextAlign.center,
    );
    expect(compute('duokan-break-inside: avoid').breakInsideAvoid, isTrue);
  });

  test('多看段前后距与方向族映射', () {
    final margins = compute('duokan-margin-before: 12px; duokan-margin-after: 6px');
    expect(margins.margin.top, 12);
    expect(margins.margin.bottom, 6);
    expect(compute('duokan-padding-before: 3px').padding.top, 3);
  });

  test('多看 bleed 出血方向解析', () {
    final bleed = compute('duokan-bleed: left right');
    expect(bleed.bleed.left, isTrue);
    expect(bleed.bleed.right, isTrue);
    expect(bleed.bleed.top, isFalse);
    expect(compute('duokan-bleed: auto').bleed.any, isFalse);
    // 多看常把方向连写（真实书 `lefttopright`）。
    final joined = compute('duokan-bleed: lefttopright');
    expect(joined.bleed.left, isTrue);
    expect(joined.bleed.top, isTrue);
    expect(joined.bleed.right, isTrue);
    expect(joined.bleed.bottom, isFalse);
    final all = compute('-duokan-bleed: all');
    expect(all.bleed.any, isTrue);
    expect(all.bleed.bottom, isTrue);
  });

  test('多看渐变文字取首色当纯色', () {
    expect(
      compute('-duokan-text-fill: linear-gradient(#ffd700, #b0904d)').color,
      const Color(0xFFFFD700),
    );
    expect(compute('duokan-text-color: #cbd5e1').color, const Color(0xFFCBD5E1));
  });

  test('vertical-align 私有值 duokan-middle-line', () {
    expect(
      compute('vertical-align: duokan-middle-line').verticalAlign,
      CssVerticalAlign.middle,
    );
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
