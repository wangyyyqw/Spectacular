import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';

class _Element implements SelectorElement {
  _Element(this.tag, this.attributes, [this.childElements = const []]);

  @override
  final String tag;
  @override
  final Map<String, String> attributes;
  @override
  final List<SelectorElement> childElements;
}

List<CascadeRule> _rules(String css) => CascadeRule.fromStylesheet(
  CssParser.parse(css),
  origin: CascadeOrigin.author,
);

void main() {
  test('样式共享只在不依赖兄弟位置时启用，包含否定参数里的结构伪类', () {
    for (final selector in [
      'p:first-child',
      'p:not(:nth-child(2))',
      'p + p',
      'p ~ p',
    ]) {
      expect(
        CascadeRuleSet(_rules('$selector { color: red; }')).usesTreePosition,
        isTrue,
        reason: selector,
      );
    }
    for (final selector in [
      '.book > p',
      'p:not(.note)',
      'p[hidden]',
      ':root',
    ]) {
      expect(
        CascadeRuleSet(_rules('$selector { color: red; }')).usesTreePosition,
        isFalse,
        reason: selector,
      );
    }
  });

  test('无关的结构选择器不阻止普通元素共享，祖先依赖仍保留', () {
    final rules = CascadeRuleSet(
      _rules('''
      dd + dt { margin-top: 8px; }
      p { color: black; }
      section:nth-child(2) .note { color: red; }
    '''),
    );
    expect(rules.candidatesFor(_Element('p', {})).usesTreePosition, isFalse);
    expect(rules.candidatesFor(_Element('dt', {})).usesTreePosition, isTrue);
    expect(
      rules.candidatesFor(_Element('p', {'class': 'note'})).usesTreePosition,
      isTrue,
    );
  });

  test('规则集复制输入，稳定排序，候选集合只读且不重复', () {
    final first = _rules('p, .a, #target { color: red; }').single;
    final last = _rules('.a { color: blue; }').single;
    final input = [first, last];
    final rules = CascadeRuleSet(input);
    input.clear();
    final element = _Element('P', {'id': 'target', 'class': 'b a a'});
    final candidates = rules.candidatesFor(element);
    expect(candidates, [first, last]);
    expect(() => candidates.clear(), throwsUnsupportedError);
    expect(
      identical(
        candidates,
        rules.candidatesFor(_Element('p', {'id': 'target', 'class': 'a b'})),
      ),
      isTrue,
    );
    expect(
      Cascade.compute(
        element: element,
        ancestors: [],
        rules: candidates,
      )['color'],
      'red',
      reason: '逗号组仍取实际命中的最高特异性',
    );
  });

  test('索引不缓存属性、祖先、兄弟、媒体与内联声明的最终匹配结果', () {
    final rules = _rules('''
      * { color: black; --gap: 3px; }
      section > p.a { margin-left: var(--gap); }
      .a[data-hot] { color: red; }
      p + p { padding-left: 7px; }
      p:nth-child(2) { font-size: 23px; }
      .a, #second { color: blue; }
      @media (min-width: 400px) { .a { color: green !important; } }
    ''').reversed.toList();
    final compiled = CascadeRuleSet(rules);
    final first = _Element('p', {'class': 'a'});
    final second = _Element('p', {
      'class': 'a',
      'data-hot': '',
      'id': 'second',
    });
    final parent = _Element('section', {}, [first, second]);
    for (final width in [350.0, 500.0]) {
      for (final element in [first, second]) {
        final common = Cascade.compute(
          element: element,
          ancestors: [parent],
          rules: rules,
          containingWidth: width,
        );
        final indexed = Cascade.compute(
          element: element,
          ancestors: [parent],
          rules: compiled.candidatesFor(element),
          containingWidth: width,
        );
        expect(indexed.values, common.values);
        expect(indexed.customProperties, common.customProperties);
      }
    }
    final warm = compiled.candidatesFor(first);
    first.attributes['data-hot'] = '';
    expect(compiled.candidatesFor(first), same(warm));
    final style = Cascade.compute(
      element: first,
      ancestors: [parent],
      rules: warm,
      inlineDeclarations: CssParser.parseStyleAttribute('color: purple'),
    );
    expect(style['color'], 'purple');
  });

  test('上下文不同但主体相同的元素不会复用最终样式', () {
    final rules = CascadeRuleSet(
      _rules('''
      p { color: black; }
      [data-hot] { color: red; }
      section p { padding-left: 9px; }
    '''),
    );
    final plain = _Element('p', {});
    final hot = _Element('p', {'data-hot': ''});
    expect(rules.candidatesFor(plain), same(rules.candidatesFor(hot)));
    final normal = Cascade.compute(
      element: plain,
      ancestors: [],
      rules: rules.candidatesFor(plain),
    );
    final highlighted = Cascade.compute(
      element: hot,
      ancestors: [
        _Element('section', {}, [hot]),
      ],
      rules: rules.candidatesFor(hot),
    );
    expect(normal['color'], 'black');
    expect(highlighted['color'], 'red');
    expect(normal.padding.left, 0);
    expect(highlighted.padding.left, 9);
  });

  test('大量无关规则不进入候选，未索引的伪类不会遗漏', () {
    final rules = CascadeRuleSet(
      _rules('''
      ${[for (var i = 0; i < 1000; i++) '.unused$i { color: red; }'].join()}
      p { color: blue; }
      :not(.excluded) { padding-left: 5px; }
    '''),
    );
    final element = _Element('p', {});
    final candidates = rules.candidatesFor(element);
    expect(candidates, hasLength(2));
    final style = Cascade.compute(
      element: element,
      ancestors: [],
      rules: candidates,
    );
    expect(style['color'], 'blue');
    expect(style.padding.left, 5);
  });

  test('现代函数伪类参与候选筛选、匹配与特异性层叠', () {
    final rules = CascadeRuleSet(
      _rules('''
      .a { color: blue; }
      :where(#x) { color: green; }
      :is(#x, .missing) { color: red; }
      p:not(.a, .b) { color: purple; }
      div:has(> p) { padding-left: 11px; }
    '''),
    );
    final target = _Element('p', {'id': 'x', 'class': 'a'});
    final other = _Element('p', {'class': 'c'});
    final div = _Element('div', {}, [target]);

    final targetStyle = Cascade.compute(
      element: target,
      ancestors: [div],
      rules: rules.candidatesFor(target),
    );
    expect(targetStyle['color'], 'red', reason: ':is(#x) 的 id 特异性胜出');

    final otherStyle = Cascade.compute(
      element: other,
      ancestors: [],
      rules: rules.candidatesFor(other),
    );
    expect(otherStyle['color'], 'purple', reason: ':not() 列表排除 .a/.b');

    final divStyle = Cascade.compute(
      element: div,
      ancestors: [],
      rules: rules.candidatesFor(div),
    );
    expect(divStyle.padding.left, 11);
  });
}
