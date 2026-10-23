import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/parser/document_parser.dart';

const _xhtml = '''
<html><body>
<div id="root" class="main">
  <p id="p1" class="a b">one <span id="sp1" class="x">S</span></p>
  <div id="mid" class="box">
    <p id="p2" class="a">two</p>
    <span id="sp2" class="x">T</span>
  </div>
</div>
</body></html>
''';

void main() {
  final document = DocumentParser.parse(xhtml: _xhtml, spineIndex: 0);
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

  ParsedElement element(String id) => document.elementById(id)!;
  List<ParsedElement> ancestors(String id) => paths[id]!;

  bool match(String selector, String id) {
    final list = SelectorParser.parse(selector);
    expect(list.selectors, isNotEmpty, reason: selector);
    return list.matches(element(id), ancestors(id));
  }

  test('30 条选择器匹配用例', () {
    final cases = <(String, String, bool)>[
      ('p', 'p1', true),
      ('p', 'root', false),
      ('.a', 'p1', true),
      ('.a', 'p2', true),
      ('.a.b', 'p1', true),
      ('.a.b', 'p2', false),
      ('#p1', 'p1', true),
      ('#p1', 'p2', false),
      ('div p', 'p1', true),
      ('div p', 'root', false),
      ('div > p', 'p1', true),
      ('#root > p', 'p2', false),
      ('#root > p', 'p1', true),
      ('div > span', 'sp2', true),
      ('div div > p', 'p2', true),
      ('.box > p', 'p2', true),
      ('.main > .box', 'mid', true),
      ('.main > p', 'mid', false),
      ('p span', 'sp1', true),
      ('p > span.x', 'sp1', true),
      ('.a .x', 'sp1', true),
      ('.a > .x', 'sp1', true),
      ('#root .x', 'sp2', true),
      ('#root > .x', 'sp2', false),
      ('div, span', 'sp2', true),
      ('#p2, #p1', 'p1', true),
      ('p.a.b#p1', 'p1', true),
      ('*', 'p1', true),
      ('*.x', 'sp1', true),
      ('div > p > span', 'sp1', true),
    ];
    for (var i = 0; i < cases.length; i++) {
      final (selector, id, expected) = cases[i];
      expect(
        match(selector, id),
        expected,
        reason: 'case ${i + 1}: $selector -> $id',
      );
    }
    expect(cases, hasLength(30));
  });

  test('逗号分组任一匹配', () {
    final list = SelectorParser.parse('section, #p2');
    expect(list.selectors, hasLength(2));
    expect(list.matches(element('p2'), ancestors('p2')), isTrue);
    expect(list.matches(element('p1'), ancestors('p1')), isFalse);
  });

  test('四元组特异性', () {
    Specificity spec(String selector) =>
        SelectorParser.parse(selector).selectors.single.specificity;
    expect(spec('#p1'), const Specificity(0, 1, 0, 0));
    expect(spec('.a.b'), const Specificity(0, 0, 2, 0));
    expect(spec('div p'), const Specificity(0, 0, 0, 2));
    expect(spec('div.foo > p'), const Specificity(0, 0, 1, 2));
    expect(spec('*'), const Specificity(0, 0, 0, 0));
    expect(spec('p.a.b#id'), const Specificity(0, 1, 2, 1));
    expect(spec('.a.b').compareTo(spec('.a')), greaterThan(0));
    expect(spec('#id').compareTo(spec('.a.b')), greaterThan(0));
    expect(spec('p').compareTo(spec('*')), greaterThan(0));
  });

  test('标签名大小写不敏感', () {
    expect(match('DIV', 'root'), isTrue);
    expect(match('DiV > P', 'p1'), isTrue);
  });

  test('不支持的选择器跳过并记录 warning', () {
    for (final selector in <String>[
      'p[title]',
      'p:first-child',
      'p:hover',
      'div + p',
      'div ~ p',
    ]) {
      final result = SelectorParser.parse(selector);
      expect(result.selectors, isEmpty, reason: selector);
      expect(result.warnings, isNotEmpty, reason: selector);
    }
  });
}
