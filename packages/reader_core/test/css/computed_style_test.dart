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
}
