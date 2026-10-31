import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/parser/document_parser.dart';

const _xhtml = '''
<html><body>
<div id="root" class="main">
  <p id="p1" class="a b">one <span id="sp1" class="x deep">S</span></p>
  <div id="mid" class="box">
    <p id="p2" class="a">two</p>
    <span id="sp2" class="x">T <em class="deep">D</em></span>
  </div>
</div>
</body></html>
''';

class _MutableElement implements SelectorElement {
  @override
  String get tag => 'p';

  @override
  final attributes = <String, String>{};

  @override
  List<SelectorElement> get childElements => const [];
}

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

  SelectorElement element(String id) => viewOwner[document.elementById(id)]!;
  List<SelectorElement> ancestors(String id) => paths[id]!;

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

  test('class 重复匹配覆盖空白、大小写与可变属性', () {
    final view = _MutableElement();
    final part = SelectorPart(classes: {'a', 'b'});
    for (final value in ['a b', '  a\tb\n a\r\f', 'b a']) {
      view.attributes['class'] = value;
      expect(part.matches(view), isTrue);
      expect(part.matches(view), isTrue);
    }
    for (final value in ['a', 'a B', 'ab', '']) {
      view.attributes['class'] = value;
      expect(part.matches(view), isFalse);
    }
    view.attributes['class'] = 'a b';
    expect(part.matches(view), isTrue, reason: '属性改变后不能复用元素旧匹配结果');
  });

  test('class 缓存淘汰与超长属性不改变匹配结果', () {
    final view = _MutableElement();
    for (var i = 0; i < 260; i++) {
      view.attributes['class'] = 'common c$i';
      expect(SelectorPart(classes: {'common', 'c$i'}).matches(view), isTrue);
      expect(SelectorPart(classes: {'c${i + 1}'}).matches(view), isFalse);
    }
    view.attributes['class'] = 'common c0';
    expect(SelectorPart(classes: {'common', 'c0'}).matches(view), isTrue);
    view.attributes['class'] = '${'long ' * 300}target';
    expect(SelectorPart(classes: {'long', 'target'}).matches(view), isTrue);
  });

  test('P8-01 升级后支持的选择器（属性/伪类/兄弟）', () {
    for (final selector in <String>[
      'p[title]',
      'p:first-child',
      'div + p',
      'div ~ p',
    ]) {
      final result = SelectorParser.parse(selector);
      expect(result.selectors, isNotEmpty, reason: selector);
    }
    // 交互态伪类解析成功但永不匹配。
    expect(match('p:hover', 'p1'), isFalse);
  });

  test('仍不支持的选择器跳过并记录 warning', () {
    for (final selector in <String>[
      'p::before',
      'p:lang(en)',
      'p:is()',
      'p:has(> )',
    ]) {
      final result = SelectorParser.parse(selector);
      expect(result.selectors, isEmpty, reason: selector);
      expect(result.warnings, isNotEmpty, reason: selector);
    }
  });

  test(':is() / :where() 列表匹配与特异性', () {
    expect(match(':is(p, span)', 'p1'), isTrue);
    expect(match(':is(p, span)', 'sp1'), isTrue);
    expect(match(':is(p, span)', 'mid'), isFalse);
    expect(match(':is(.box > p)', 'p2'), isTrue);
    expect(match(':where(#p1, .box)', 'mid'), isTrue);
    expect(match(':where(#p1, .box)', 'p2'), isFalse);

    Specificity spec(String selector) =>
        SelectorParser.parse(selector).selectors.single.specificity;
    expect(spec('p:is(.a, #p1)'), const Specificity(0, 1, 0, 1));
    expect(spec('p:where(#p1, .a)'), const Specificity(0, 0, 0, 1));
  });

  test(':not() 列表参数匹配与最高特异性', () {
    expect(match('span:not(.a, #sp2)', 'sp1'), isTrue);
    expect(match('span:not(.a, #sp2)', 'sp2'), isFalse);
    expect(match('div:not(.a, #root)', 'mid'), isTrue);
    expect(match('div:not(.a, #root)', 'root'), isFalse);
    final specificity = SelectorParser.parse('p:not(.a, #p1)')
        .selectors
        .single
        .specificity;
    expect(specificity, const Specificity(0, 1, 0, 1));
  });

  test(':has() 后代、子代与兄弟相对选择器', () {
    expect(match('div:has(> p)', 'root'), isTrue);
    expect(match('div:has(> p)', 'mid'), isTrue);
    expect(match('p:has(> p)', 'p1'), isFalse);
    expect(match('div:has(.x)', 'root'), isTrue);
    expect(match('div:has(.x)', 'mid'), isTrue);
    expect(match('div:has(> p + span)', 'mid'), isTrue);
    expect(match('div:has(> p + span)', 'root'), isFalse);
    expect(match('p:has(+ span)', 'p2'), isTrue);
    expect(match('p:has(+ span)', 'p1'), isFalse);
    expect(match('p:has(~ span)', 'p2'), isTrue);
    expect(match('p:has(~ span)', 'p1'), isFalse);
    expect(match('div:has(.a, #sp2)', 'mid'), isTrue);
    expect(match('div:has(> p .deep)', 'root'), isTrue);
    expect(match('div:has(> p .deep)', 'mid'), isFalse);
    expect(match('p:has(+ span .deep)', 'p2'), isTrue);
  });

  test('nth-child(An+B of S) 只在过滤后的兄弟中计数', () {
    expect(match('*:nth-child(1 of .a)', 'p1'), isTrue);
    expect(match('*:nth-child(2 of .a)', 'p1'), isFalse);
    expect(match('*:nth-child(1 of .x)', 'sp2'), isTrue);
    expect(match('*:nth-child(2 of .x)', 'sp2'), isFalse);
    expect(match('*:nth-child(2n of .a)', 'p1'), isFalse);
    expect(match('*:nth-last-child(1 of .a)', 'p1'), isTrue);
    final specificity = SelectorParser.parse('li:nth-child(2n of .x)')
        .selectors
        .single
        .specificity;
    expect(specificity, const Specificity(0, 0, 2, 1));
  });

  test('函数伪类的结构依赖参与样式共享判定', () {
    bool treePosition(String selector) =>
        SelectorParser.parse(selector).selectors.single.usesTreePosition;
    expect(treePosition('div:has(p)'), isTrue);
    expect(treePosition('p:is(:first-child, .a)'), isTrue);
    expect(treePosition('p:not(:last-child)'), isTrue);
    expect(treePosition('p:is(.a, .b)'), isFalse);
  });

  test('P8-01 兄弟组合器匹配语义', () {
    // mid 内：p2 之后相邻 span sp2。
    expect(match('p + span', 'sp2'), isTrue);
    expect(match('p ~ span', 'sp2'), isTrue);
    // root 内：p1 是首子，无前兄弟。
    expect(match('span + p', 'p1'), isFalse);
  });

  test('P8-01 属性选择器匹配', () {
    expect(match('p[title]', 'p1'), isFalse, reason: 'p1 无 title 属性');
    expect(match('div[class~=box]', 'mid'), isTrue);
    expect(match('div[class="main"]', 'root'), isTrue);
  });

  test('nth-child 准确提取参数并按元素兄弟计数', () {
    expect(match('div:nth-child(even)', 'mid'), isTrue);
    expect(match('p:nth-child(odd)', 'p1'), isTrue);
    expect(match('span:nth-child(2n + 2)', 'sp2'), isTrue);
    expect(match('span:nth-child(2n + 1)', 'sp2'), isFalse);
  });

  test('first-of-type 忽略前方不同标签的兄弟', () {
    expect(match('div:first-of-type', 'mid'), isTrue);
    expect(match('div:first-child', 'mid'), isFalse);
    expect(match('span:first-of-type', 'sp2'), isTrue);
  });

  test('倒序、同类型与唯一子元素的结构伪类', () {
    final cases = <(String, String, bool)>[
      ('p:nth-of-type(1)', 'p2', true),
      ('span:nth-of-type(2)', 'sp2', false),
      ('span:nth-last-child(1)', 'sp2', true),
      ('p:nth-last-child(2)', 'p2', true),
      ('p:nth-last-child(-n+2)', 'p2', true),
      ('span:nth-last-of-type(odd)', 'sp2', true),
      ('span:nth-last-of-type(even)', 'sp2', false),
      ('div:last-of-type', 'mid', true),
      ('p:last-child', 'p2', false),
      ('span:only-child', 'sp1', true),
      ('p:only-child', 'p2', false),
      ('p:only-of-type', 'p2', true),
      ('p:nth-child(0)', 'p1', false),
      ('p:nth-child(-1)', 'p1', false),
    ];
    for (final (selector, id, expected) in cases) {
      expect(match(selector, id), expected, reason: '$selector -> $id');
    }
    for (final selector in ['*:first-child', '*:last-child', '*:only-child']) {
      expect(SelectorParser.parse(selector).matches(rootView, []), isTrue);
    }
  });

  test('否定参数预编译，支持属性与结构伪类，并保留参数特异性', () {
    expect(match('p:not([title])', 'p1'), isTrue);
    expect(match('p:not([class~=a])', 'p1'), isFalse);
    expect(match('p:not(:first-child)', 'p1'), isFalse);
    expect(match('span:not(:first-child)', 'sp2'), isTrue);
    expect(match('p:not(*)', 'p1'), isFalse);
    Specificity spec(String text) =>
        SelectorParser.parse(text).selectors.single.specificity;
    expect(spec('p:not(#excluded)'), const Specificity(0, 1, 0, 1));
    expect(spec('p:not(span)'), const Specificity(0, 0, 0, 2));
    expect(spec('p:not(.excluded)'), const Specificity(0, 0, 1, 1));
    expect(spec('p:not([hidden])'), const Specificity(0, 0, 1, 1));
    expect(spec('p:not(*)'), const Specificity(0, 0, 0, 1));
  });

  test('link 匹配带 href 的静态链接而不依赖交互状态', () {
    final parsed = DocumentParser.parse(
      xhtml:
          '<html><body><a id="link" href="#next">链接</a>'
          '<a id="anchor">锚点</a></body></html>',
      spineIndex: 0,
    );
    final owner = <ParsedNode, ParsedElementView>{};
    ParsedElementView.wrap(parsed.root, owner);
    final selector = SelectorParser.parse('a:link');
    expect(selector.matches(owner[parsed.elementById('link')]!, []), isTrue);
    expect(selector.matches(owner[parsed.elementById('anchor')]!, []), isFalse);
  });
}
