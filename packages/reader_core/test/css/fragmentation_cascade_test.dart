import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/css/ua_stylesheet.dart';
import 'package:reader_core/parser/document_parser.dart';

ComputedStyle _compute(
  String declarations, {
  ComputedStyle? parent,
  List<CascadeRule> rules = const [],
}) {
  final document = DocumentParser.parse(
    xhtml: '<html><body><h1 id="title">正文</h1></body></html>',
    spineIndex: 0,
  );
  return Cascade.compute(
    element: ParsedElementView.wrap(document.elementById('title')!, {}),
    ancestors: const <SelectorElement>[],
    rules: rules,
    inlineDeclarations: CssParser.parseInlineDeclarations(declarations),
    parent: parent,
  );
}

List<CascadeRule> _rules(String css, CascadeOrigin origin, int order) =>
    CascadeRule.fromStylesheet(
      CssParser.parse(css),
      origin: origin,
      startOrder: order,
    );

void main() {
  for (final edge in ['before', 'after', 'inside']) {
    test('新旧 $edge 断页声明按同槽声明顺序竞争', () {
      final oldLast = _compute('break-$edge: avoid; page-break-$edge: auto;');
      final newLast = _compute('page-break-$edge: avoid; break-$edge: auto;');
      for (final style in [oldLast, newLast]) {
        expect(style.values['break-$edge'], 'auto');
        expect(style.values.containsKey('page-break-$edge'), isFalse);
        expect(style.breakInsideAvoid, isFalse);
        expect(style.breakAfterAvoid, isFalse);
      }
    });
  }

  test('always 归一为 page，作者可覆盖 UA 标题避页底', () {
    final page = _compute('page-break-before: always;');
    expect(page.values['break-before'], 'page');
    expect(page.pageBreakBefore, isTrue);
    final heading = _compute('break-after: auto;', rules: uaRules());
    expect(heading.breakAfterAvoid, isFalse);
    expect(heading.values['break-after'], 'auto');
  });

  test('别名保留来源、重要性和特异性，不能固定新名优先', () {
    final important = _compute(
      'break-before: auto;',
      rules: [
        ..._rules(
          'h1{page-break-before: always !important;}',
          CascadeOrigin.author,
          0,
        ),
      ],
    );
    expect(important.pageBreakBefore, isTrue);
    final specificity = _compute(
      '',
      rules: [
        ..._rules(
          '#title{page-break-before: always;}',
          CascadeOrigin.author,
          0,
        ),
        ..._rules('h1{break-before: auto;}', CascadeOrigin.author, 1),
      ],
    );
    expect(specificity.pageBreakBefore, isTrue);
    final author = _compute(
      '',
      rules: [
        ..._rules(
          'h1{page-break-before: always;}',
          CascadeOrigin.userAgent,
          100,
        ),
        ..._rules('h1{break-before: auto;}', CascadeOrigin.author, 0),
      ],
    );
    expect(author.pageBreakBefore, isFalse);
  });

  test('inherit 读取规范父值，initial 与 unset 回到非继承初始值', () {
    final parent = _compute('page-break-before: always; break-after: avoid;');
    final inherited = _compute(
      'break-before: inherit; page-break-after: inherit;',
      parent: parent,
    );
    expect(inherited.pageBreakBefore, isTrue);
    expect(inherited.breakAfterAvoid, isTrue);
    for (final keyword in ['initial', 'unset']) {
      final reset = _compute(
        'break-before: $keyword; page-break-after: $keyword;',
        parent: parent,
      );
      expect(reset.pageBreakBefore, isFalse);
      expect(reset.breakAfterAvoid, isFalse);
      expect(reset.values['break-before'], 'auto');
    }
    expect(_compute('', parent: parent).pageBreakBefore, isFalse);
  });

  test('变量替换后参与别名竞争，无效变量赢家按 unset 回退', () {
    final resolved = _compute(
      '--where: always; break-before: auto; page-break-before: var(--where);',
    );
    expect(resolved.pageBreakBefore, isTrue);
    final invalid = _compute(
      'page-break-before: always; break-before: var(--missing);',
    );
    expect(invalid.pageBreakBefore, isFalse);
    expect(invalid.values['break-before'], 'auto');
  });

  test('无效旧名取值不覆盖已有新名，inside 不接受强制分页值', () {
    final style = _compute(
      'break-before: page; page-break-before: nonsense; '
      'break-inside: avoid; page-break-inside: always;',
    );
    expect(style.pageBreakBefore, isTrue);
    expect(style.breakInsideAvoid, isTrue);
  });

  test('直接构造样式也归一别名、显式属性和多级继承', () {
    final style = ComputedStyle(
      const {'break-before': 'auto', 'page-break-before': 'always'},
      explicitProperties: {'break-before', 'page-break-before'},
    );
    expect(style.pageBreakBefore, isTrue);
    expect(style.explicitProperties, {'break-before'});
    expect(style.values['break-before'], 'page');
    final child = ComputedStyle(const {
      'page-break-before': 'inherit',
    }, parent: style);
    final grandchild = ComputedStyle(const {
      'break-before': 'inherit',
    }, parent: child);
    expect(grandchild.pageBreakBefore, isTrue);
    expect(grandchild.computedValue('page-break-before'), 'page');
  });

  test('avoid-page 与 avoid 共用分页语义，孤行寡行声明始终忽略', () {
    final style = _compute(
      '--lines: 99; orphans: var(--lines) !important; widows: 9 !important; '
      'break-inside: avoid-page; break-after: avoid-page;',
    );
    expect(style.breakInsideAvoid, isTrue);
    expect(style.breakAfterAvoid, isTrue);
    expect(style.values.containsKey('orphans'), isFalse);
    expect(style.values.containsKey('widows'), isFalse);
    final direct = ComputedStyle(const {'orphans': '10', 'widows': '20'});
    expect(direct.values, isEmpty);
    expect(Cascade.inheritedProperties.contains('orphans'), isFalse);
    expect(Cascade.inheritedProperties.contains('widows'), isFalse);
  });
}
