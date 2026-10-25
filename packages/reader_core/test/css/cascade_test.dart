import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/parser/document_parser.dart';

const _xhtml = '''
<html><body>
<div id="parent" class="book">
  <p id="p" class="note">Hello <span id="child" class="em">x</span></p>
</div>
</body></html>
''';

void main() {
  final document = DocumentParser.parse(xhtml: _xhtml, spineIndex: 0);
  final viewOwner = <ParsedNode, ParsedElementView>{};
  final rootView = ParsedElementView.wrap(document.root, viewOwner);
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

  ParsedElementView el(String id) =>
      viewOwner[document.elementById(id)]!;
  List<SelectorElement> anc(String id) => paths[id]!;

  CascadeRule rule(
    String css, {
    CascadeOrigin origin = CascadeOrigin.author,
    int order = 0,
  }) {
    final sheet = CssParser.parse(css);
    return CascadeRule(rule: sheet.rules.single, origin: origin, order: order);
  }

  ComputedStyle compute({
    String id = 'p',
    List<CascadeRule> rules = const <CascadeRule>[],
    List<CssDeclaration> inline = const <CssDeclaration>[],
    ComputedStyle? parent,
  }) => Cascade.compute(
    element: el(id),
    ancestors: anc(id),
    rules: rules,
    inlineDeclarations: inline,
    parent: parent,
  );

  test('20 组 UA/作者/内联层叠用例', () {
    // 1 UA 正常 < 作者正常
    expect(
      compute(
        rules: [
          rule(
            'p { color: black; }',
            origin: CascadeOrigin.userAgent,
            order: 0,
          ),
          rule('p { color: blue; }', order: 1),
        ],
      )['color'],
      'blue',
    );
    // 2 同来源同特异性，后声明胜
    expect(
      compute(
        rules: [
          rule('p { color: red; }', order: 1),
          rule('p { color: blue; }', order: 2),
        ],
      )['color'],
      'blue',
    );
    // 3 class 特异性高于标签
    expect(
      compute(
        rules: [
          rule('p { color: red; }', order: 1),
          rule('.note { color: green; }', order: 2),
        ],
      )['color'],
      'green',
    );
    // 4 id 高于 class
    expect(
      compute(
        rules: [
          rule('.note { color: green; }', order: 1),
          rule('#p { color: orange; }', order: 2),
        ],
      )['color'],
      'orange',
    );
    // 5 作者 !important 高于高特异性普通声明
    expect(
      compute(
        rules: [
          rule('.note { color: green !important; }', order: 1),
          rule('#p { color: orange; }', order: 2),
        ],
      )['color'],
      'green',
    );
    // 6 内联正常高于作者正常
    expect(
      compute(
        rules: [rule('#p { color: orange; }', order: 1)],
        inline: CssParser.parseStyleAttribute('color: red'),
      )['color'],
      'red',
    );
    // 7 方案 §7.2：内联正常高于作者 !important
    expect(
      compute(
        rules: [rule('p { color: green !important; }', order: 1)],
        inline: CssParser.parseStyleAttribute('color: red'),
      )['color'],
      'red',
    );
    // 8 内联 !important 最高
    expect(
      compute(
        rules: [rule('p { color: green !important; }', order: 1)],
        inline: CssParser.parseStyleAttribute('color: red !important'),
      )['color'],
      'red',
    );
    // 9 div p 低于 .note
    expect(
      compute(
        rules: [
          rule('div p { color: red; }', order: 1),
          rule('.note { color: green; }', order: 2),
        ],
      )['color'],
      'green',
    );
    // 10 同特异性同重要性，后规则胜
    expect(
      compute(
        rules: [
          rule('.note { color: red; }', order: 1),
          rule('.note { color: blue; }', order: 2),
        ],
      )['color'],
      'blue',
    );
    // 11 继承 color
    final parentColor = compute(
      id: 'parent',
      rules: [rule('div { color: red; }')],
    );
    expect(compute(id: 'p', parent: parentColor)['color'], 'red');
    // 12 继承 font-family
    final parentFont = compute(
      id: 'parent',
      rules: [rule('div { font-family: serif; }')],
    );
    expect(compute(id: 'p', parent: parentFont)['font-family'], 'serif');
    // 13 继承 list-style-type
    final parentList = compute(
      id: 'parent',
      rules: [rule('div { list-style-type: square; }')],
    );
    expect(compute(id: 'p', parent: parentList)['list-style-type'], 'square');
    // 14 非继承 margin 不传递
    final parentMargin = compute(
      id: 'parent',
      rules: [rule('div { margin: 1em; }')],
    );
    expect(compute(id: 'p', parent: parentMargin)['margin'], isNull);
    // 15 子元素显式声明覆盖继承
    expect(
      compute(
        id: 'p',
        rules: [rule('p { color: blue; }')],
        parent: parentColor,
      )['color'],
      'blue',
    );
    // 16 inherit 关键字取父值
    expect(
      compute(
        id: 'p',
        rules: [rule('p { color: inherit; }')],
        parent: parentColor,
      )['color'],
      'red',
    );
    // 17 内联字号
    expect(
      compute(
        inline: CssParser.parseStyleAttribute('font-size: 20px'),
      )['font-size'],
      '20px',
    );
    // 18 同规则内后声明胜
    expect(
      compute(rules: [rule('p { color: red; color: blue; }')])['color'],
      'blue',
    );
    // 19 同为 !important，后规则胜
    expect(
      compute(
        rules: [
          rule('p { color: green !important; }', order: 1),
          rule('p { color: blue !important; }', order: 2),
        ],
      )['color'],
      'blue',
    );
    // 20 来源优先于特异性：作者低特异性胜 UA 高特异性
    expect(
      compute(
        rules: [
          rule('#p { color: black; }', origin: CascadeOrigin.userAgent),
          rule('p { color: blue; }', order: 1),
        ],
      )['color'],
      'blue',
    );
  });

  test('继承字段清单与显式文字色标记', () {
    expect(Cascade.inheritedProperties, hasLength(18));
    final parent = compute(
      id: 'parent',
      rules: [rule('div { color: red; font-size: 18px; }')],
    );
    expect(parent.hasExplicitTextColor, isTrue);
    final inherited = compute(id: 'p', parent: parent);
    expect(inherited['font-size'], '18px');
    expect(inherited.hasExplicitTextColor, isFalse);
  });
}
