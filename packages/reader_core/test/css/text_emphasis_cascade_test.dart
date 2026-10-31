import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/parser/document_parser.dart';

ComputedStyle _style(String css, {ComputedStyle? parent, String inline = ''}) {
  final document = DocumentParser.parse(
    xhtml: '<html><body><p id="p" class="mark">中文</p></body></html>',
    spineIndex: 0,
  );
  final owners = <ParsedNode, ParsedElementView>{};
  ParsedElementView.wrap(document.root, owners);
  return Cascade.compute(
    element: owners[document.elementById('p')]!,
    ancestors: const <SelectorElement>[],
    rules: CascadeRule.fromStylesheet(
      CssParser.parse(css),
      origin: CascadeOrigin.author,
    ),
    inlineDeclarations: inline.isEmpty
        ? const <CssDeclaration>[]
        : CssParser.parse('p {$inline}').rules.single.declarations,
    parent: parent,
  );
}

void main() {
  test('简写解析颜色、顺序及缺省长属性，直接构造也可用', () {
    for (final raw in ['open circle #cc0000', '#cc0000 circle open']) {
      final style = _style('p { text-emphasis: $raw; }');
      expect(style.textEmphasisStyle, CssTextEmphasisStyle.openCircle);
      expect(style.textEmphasisColor, const Color(0xFFCC0000));
    }
    final rgb = _style('p { text-emphasis: rgb(0, 102, 204) sesame; }');
    expect(rgb.textEmphasisStyle, CssTextEmphasisStyle.sesame);
    expect(rgb.textEmphasisColor, const Color(0xFF0066CC));
    final colorOnly = _style('p { text-emphasis: blue; }');
    expect(colorOnly.textEmphasisStyle, CssTextEmphasisStyle.none);
    expect(colorOnly.textEmphasisColor, const Color(0xFF0000FF));
    final direct = ComputedStyle({'text-emphasis': 'dot red'});
    expect(direct.textEmphasisStyle, CssTextEmphasisStyle.dot);
    expect(direct.textEmphasisColor, const Color(0xFFFF0000));
  });

  test('只写填充时横排用圆、竖排用芝麻，继承已计算的形状', () {
    for (final fill in ['filled', 'open']) {
      final horizontal = _style('p { text-emphasis: $fill; }');
      expect(
        horizontal.textEmphasisStyle,
        fill == 'open'
            ? CssTextEmphasisStyle.openCircle
            : CssTextEmphasisStyle.circle,
      );
      final vertical = _style(
        'p { writing-mode: vertical-rl; text-emphasis-style: $fill; }',
      );
      expect(
        vertical.textEmphasisStyle,
        fill == 'open'
            ? CssTextEmphasisStyle.openSesame
            : CssTextEmphasisStyle.sesame,
      );
      final child = _style(
        'p { writing-mode: horizontal-tb; }',
        parent: vertical,
      );
      expect(child.textEmphasisStyle, vertical.textEmphasisStyle);
      final sideways = _style(
        'p { writing-mode: vertical-lr; text-orientation: sideways; '
        'text-emphasis: $fill; }',
      );
      expect(sideways.textEmphasisStyle, horizontal.textEmphasisStyle);
    }
  });

  test('简写与长属性按声明顺序竞争', () {
    final cases = <(String, CssTextEmphasisStyle, Color?)>[
      (
        'text-emphasis-color: red; text-emphasis: circle;',
        CssTextEmphasisStyle.circle,
        null,
      ),
      (
        'text-emphasis: circle; text-emphasis-color: red;',
        CssTextEmphasisStyle.circle,
        const Color(0xFFFF0000),
      ),
      (
        'text-emphasis-style: sesame; text-emphasis: blue;',
        CssTextEmphasisStyle.none,
        const Color(0xFF0000FF),
      ),
      (
        'text-emphasis: blue; text-emphasis-style: sesame;',
        CssTextEmphasisStyle.sesame,
        const Color(0xFF0000FF),
      ),
    ];
    for (final (css, shape, color) in cases) {
      final style = _style('p {$css}');
      expect(style.textEmphasisStyle, shape, reason: css);
      expect(style.textEmphasisColor, color, reason: css);
    }
  });

  test('简写与长属性按特异性、重要性和内联竞争', () {
    final importantColor = _style(
      'p { text-emphasis-color: red !important; text-emphasis: dot blue; }',
    );
    expect(importantColor.textEmphasisStyle, CssTextEmphasisStyle.dot);
    expect(importantColor.textEmphasisColor, const Color(0xFFFF0000));
    final importantShorthand = _style(
      'p { text-emphasis: dot blue !important; text-emphasis-style: sesame; }',
    );
    expect(importantShorthand.textEmphasisStyle, CssTextEmphasisStyle.dot);
    expect(importantShorthand.textEmphasisColor, const Color(0xFF0000FF));
    final specific = _style(
      '.mark { text-emphasis: circle blue; } p { text-emphasis-color: red; }',
    );
    expect(specific.textEmphasisColor, const Color(0xFF0000FF));
    final inline = _style(
      'p { text-emphasis-style: sesame; text-emphasis-color: red; }',
      inline: 'text-emphasis: open;',
    );
    expect(inline.textEmphasisStyle, CssTextEmphasisStyle.openCircle);
    expect(inline.textEmphasisColor, isNull);
  });

  test('简写重置缺项但不重置位置，支持继承、初始值和 unset', () {
    final parent = _style(
      'p { text-emphasis: open sesame blue; text-emphasis-position: under; }',
    );
    for (final keyword in ['inherit', 'unset']) {
      final child = _style('p { text-emphasis: $keyword; }', parent: parent);
      expect(child.textEmphasisStyle, parent.textEmphasisStyle);
      expect(child.textEmphasisColor, parent.textEmphasisColor);
      expect(child.textEmphasisPosition, parent.textEmphasisPosition);
    }
    for (final raw in ['none', 'initial']) {
      final child = _style('p { text-emphasis: $raw; }', parent: parent);
      expect(child.textEmphasisStyle, CssTextEmphasisStyle.none);
      expect(child.textEmphasisColor, isNull);
      expect(child.textEmphasisPosition, CssTextEmphasisPosition.under);
    }
    final styleOnly = _style('p { text-emphasis: circle; }', parent: parent);
    expect(styleOnly.textEmphasisColor, isNull);
    final root = _style('p { text-emphasis: inherit; }');
    expect(root.textEmphasisStyle, CssTextEmphasisStyle.none);
    expect(root.textEmphasisColor, isNull);
  });

  test('长属性显式继承可覆盖先前简写，不再回读简写', () {
    final parent = _style('p { text-emphasis: sesame blue; }');
    final child = _style(
      'p { text-emphasis: circle red; text-emphasis-style: inherit; '
      'text-emphasis-color: inherit; }',
      parent: parent,
    );
    expect(child.textEmphasisStyle, CssTextEmphasisStyle.sesame);
    expect(child.textEmphasisColor, const Color(0xFF0000FF));
  });

  test('currentcolor 继承后跟随子元素正文色，具体颜色保持继承', () {
    for (final raw in ['circle', 'circle currentcolor']) {
      final parent = _style('p { color: red; text-emphasis: $raw; }');
      final child = _style('p { color: green; }', parent: parent);
      expect(child.textEmphasisColor ?? child.color, const Color(0xFF008000));
    }
    final parent = _style('p { text-emphasis: circle blue; }');
    final inherited = _style('p { color: green; }', parent: parent);
    expect(inherited.textEmphasisColor, const Color(0xFF0000FF));
    final reset = _style(
      'p { color: green; text-emphasis-color: currentcolor; }',
      parent: parent,
    );
    expect(reset.textEmphasisColor ?? reset.color, const Color(0xFF008000));
    final grandchild = _style('p { color: red; }', parent: reset);
    expect(
      grandchild.textEmphasisColor ?? grandchild.color,
      const Color(0xFFFF0000),
    );
  });

  test('无效简写整条忽略，无效长属性保留较早的合法声明', () {
    for (final raw in [
      'none circle',
      'filled open',
      'circle sesame',
      'dot dot',
      'circle red blue',
      'circle bogus',
      'none open',
    ]) {
      final style = _style(
        'p { text-emphasis: sesame blue; text-emphasis: $raw; }',
      );
      expect(style.textEmphasisStyle, CssTextEmphasisStyle.sesame, reason: raw);
      expect(style.textEmphasisColor, const Color(0xFF0000FF), reason: raw);
    }
    final longhand = _style(
      'p { text-emphasis-style: circle; text-emphasis-style: open filled; }',
    );
    expect(longhand.textEmphasisStyle, CssTextEmphasisStyle.circle);
  });
}
