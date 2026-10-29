import 'package:csslib/parser.dart' as csslib;
import 'package:csslib/visitor.dart';

import '../parser/document_parser.dart';

/// 选择器匹配元素视图（P8-01）：tag + 属性 + 元素子树；由调用方适配
///（原始解析树 / flat 管线聚合树 / 行内标记链均可实现）。
abstract class SelectorElement {
  /// 标签名。
  String get tag;

  /// 元素属性（id/class/style/src…）。
  Map<String, String> get attributes;

  /// 元素子（结构伪类与兄弟组合器用；同一树内视图须稳定相等）。
  List<SelectorElement> get childElements;
}

/// [ParsedElement] 树的匹配视图：按树缓存包装，保证 identical 稳定。
class ParsedElementView implements SelectorElement {
  ParsedElementView._(this._node, this._children);

  /// 包装一棵树（同一 [owner] 缓存内复用视图实例）。
  static ParsedElementView wrap(
    ParsedElement node,
    Map<ParsedNode, ParsedElementView> owner,
  ) {
    final cached = owner[node];
    if (cached != null) {
      return cached;
    }
    final children = <ParsedElementView>[
      for (final child in node.children)
        if (child is ParsedElement) wrap(child, owner),
    ];
    final view = ParsedElementView._(
      node,
      List<SelectorElement>.unmodifiable(children),
    );
    owner[node] = view;
    return view;
  }

  final ParsedElement _node;

  final List<SelectorElement> _children;

  @override
  late final String tag = _node.tag;

  @override
  late final Map<String, String> attributes = _node.attributes;

  @override
  List<SelectorElement> get childElements => _children;
}

/// 组合符。
enum SelectorCombinator {
  descendant,
  child,

  /// 相邻兄弟（A + B）。
  adjacentSibling,

  /// 通用兄弟（A ~ B）。
  generalSibling,
}

/// 四元组特异性：inline / id / class / type。
class Specificity implements Comparable<Specificity> {
  /// 创建特异性。
  const Specificity(this.inline, this.id, this.classCount, this.type);

  /// style 属性数量（选择器本身为 0）。
  final int inline;

  /// id 数量。
  final int id;

  /// class/属性/伪类数量。
  final int classCount;

  /// 标签/伪元素数量。
  final int type;

  @override
  int compareTo(Specificity other) {
    final inlineDiff = inline.compareTo(other.inline);
    if (inlineDiff != 0) {
      return inlineDiff;
    }
    final idDiff = id.compareTo(other.id);
    if (idDiff != 0) {
      return idDiff;
    }
    final classDiff = classCount.compareTo(other.classCount);
    if (classDiff != 0) {
      return classDiff;
    }
    return type.compareTo(other.type);
  }

  @override
  bool operator ==(Object other) =>
      other is Specificity &&
      other.inline == inline &&
      other.id == id &&
      other.classCount == classCount &&
      other.type == type;

  @override
  int get hashCode => Object.hash(inline, id, classCount, type);

  @override
  String toString() => '($inline,$id,$classCount,$type)';
}

/// 复合选择器的一部分（同一元素上的 tag/#id/.class/[attr]/:pseudo 组合）。
class SelectorPart {
  /// 创建部分。
  SelectorPart({this.tag, this.id, Set<String>? classes})
    : classes = classes ?? <String>{},
      attributeTests = const <AttributeTest>[],
      pseudos = const <PseudoTest>[];

  /// 属性选择器（[a] / [a=v] / [a~=v]…）。
  SelectorPart.withAttributes({
    this.tag,
    this.id,
    Set<String>? classes,
    List<AttributeTest>? attributeTests,
    List<PseudoTest>? pseudos,
  }) : classes = classes ?? <String>{},
       attributeTests = attributeTests ?? const <AttributeTest>[],
       pseudos = pseudos ?? const <PseudoTest>[];

  /// 标签名；null 表示 `*`。
  final String? tag;

  /// id。
  final String? id;

  /// class 集合。
  final Set<String> classes;

  /// 属性选择器测试。
  final List<AttributeTest> attributeTests;

  /// 伪类测试（结构伪类 + :not；交互态在解析期归入永不匹配）。
  final List<PseudoTest> pseudos;

  /// 是否匹配（P8-01：含属性与伪类；位置上下文取 [context]）。
  bool matches(SelectorElement element, [List<SelectorElement>? ancestors]) {
    final expectedTag = tag;
    if (expectedTag != null &&
        element.tag.toLowerCase() != expectedTag.toLowerCase()) {
      return false;
    }
    if (id != null && element.attributes['id'] != id) {
      return false;
    }
    if (classes.isNotEmpty) {
      final actual = (element.attributes['class'] ?? '')
          .split(RegExp(r'\s+'))
          .where((value) => value.isNotEmpty)
          .toSet();
      if (!classes.every(actual.contains)) {
        return false;
      }
    }
    for (final test in attributeTests) {
      if (!test.matches(element)) {
        return false;
      }
    }
    for (final pseudo in pseudos) {
      if (!pseudo.matches(element, ancestors ?? const <SelectorElement>[])) {
        return false;
      }
    }
    return true;
  }
}

/// 属性选择器测试（P8-01）：存在 / = / ~= / |= / ^= / $= / *=。
class AttributeTest {
  /// 创建测试。
  const AttributeTest(this.name, this.operator, this.value);

  /// 属性名（小写）。
  final String name;

  /// 操作符（'' 存在 / '=','~=','|=','^=','$=','*='）。
  final String operator;

  /// 比较值（存在测试为空串）。
  final String value;

  bool matches(SelectorElement element) {
    final actual = element.attributes[name];
    if (actual == null) {
      return false;
    }
    switch (operator) {
      case '':
        return true;
      case '=':
        return actual == value;
      case '~=':
        return actual.split(RegExp(r'\s+')).contains(value);
      case '|=':
        return actual == value || actual.startsWith('$value-');
      case '^=':
        return value.isNotEmpty && actual.startsWith(value);
      case r'$=':
        return value.isNotEmpty && actual.endsWith(value);
      case '*=':
        return value.isNotEmpty && actual.contains(value);
      default:
        return false;
    }
  }
}

/// 结构伪类测试（P8-01）：:first-child/:last-child/:nth-child(An+B)/
/// :first-of-type/:not(compound)/:root；交互态（:hover 等）不匹配。
class PseudoTest {
  /// 创建测试：[name] 小写；[argument] 为 nth 参数或 :not 内复合。
  const PseudoTest(this.name, this.argument);

  final String name;
  final String? argument;

  bool matches(
    SelectorElement element,
    List<SelectorElement> ancestors,
  ) {
    switch (name) {
      case 'hover':
      case 'visited':
      case 'active':
      case 'focus':
      case 'target':
        return false;
      case 'link':
        return const {'a', 'area'}.contains(element.tag.toLowerCase()) &&
            element.attributes.containsKey('href');
      case 'root':
        return ancestors.isEmpty;
      case 'first-child':
        return _siblingIndex(element, ancestors) == 0;
      case 'first-of-type':
        final siblings = _parentChildren(ancestors);
        if (siblings == null) return ancestors.isEmpty;
        for (final sibling in siblings) {
          if (sibling.tag.toLowerCase() == element.tag.toLowerCase()) {
            return identical(sibling, element);
          }
        }
        return false;
      case 'last-child':
        final index = _siblingIndex(element, ancestors);
        if (index < 0) {
          return false;
        }
        final siblings = _parentChildren(ancestors);
        return siblings != null && index == siblings.length - 1;
      case 'nth-child':
        final index = _siblingIndex(element, ancestors);
        if (index < 0 || argument == null) {
          return false;
        }
        return _nthMatches(argument!, index + 1);
      case 'not':
        if (argument == null) {
          return true;
        }
        final inner = SelectorParser.parseCompound(argument!);
        return inner == null || !inner.matches(element, ancestors);
      default:
        return false;
    }
  }

  static List<SelectorElement>? _parentChildren(List<SelectorElement> ancestors) =>
      ancestors.isEmpty ? null : ancestors.last.childElements;

  static int _siblingIndex(
    SelectorElement element,
    List<SelectorElement> ancestors,
  ) {
    final siblings = _parentChildren(ancestors);
    if (siblings == null) {
      return -1;
    }
    for (var i = 0; i < siblings.length; i++) {
      if (identical(siblings[i], element)) {
        return i;
      }
    }
    return -1;
  }

  /// An+B 求值（odd/even/整数/步进）。
  static bool _nthMatches(String raw, int index) {
    final arg = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    int? step, offset;
    if (arg == 'odd') {
      step = 2;
      offset = 1;
    } else if (arg == 'even') {
      step = 2;
      offset = 0;
    } else if (arg.contains('n')) {
      final m = RegExp(r'^([+-]?\d*)n([+-]\d+)?$').firstMatch(arg);
      if (m == null) {
        return false;
      }
      final stepRaw = m.group(1);
      step = stepRaw == null || stepRaw.isEmpty || stepRaw == '+'
          ? 1
          : stepRaw == '-'
          ? -1
          : int.tryParse(stepRaw);
      offset = m.group(2) == null ? 0 : int.tryParse(m.group(2)!);
    } else {
      step = 0;
      offset = int.tryParse(arg);
    }
    if (step == null || offset == null) {
      return false;
    }
    if (step == 0) {
      return index == offset;
    }
    final delta = index - offset;
    return delta % step == 0 && delta ~/ step >= 0;
  }
}

/// 一个复杂选择器（可含后代/子代组合）。
class ComplexSelector {
  /// 创建选择器。
  ComplexSelector({
    required this.parts,
    required this.combinators,
    required this.specificity,
    required this.text,
  });

  /// 从左到右的复合片段。
  final List<SelectorPart> parts;

  /// 相邻片段之间的组合符，长度 = parts.length - 1。
  final List<SelectorCombinator> combinators;

  /// 特异性。
  final Specificity specificity;

  /// 原始文本。
  final String text;

  /// 匹配元素；[ancestors] 从根到父节点（P8-01：兄弟组合器沿父的
  /// 元素子回溯）。
  bool matches(SelectorElement element, List<SelectorElement> ancestors) {
    bool matchPart(
      int index,
      SelectorElement candidate,
      List<SelectorElement> path,
    ) {
      if (index < 0) {
        return true;
      }
      if (!parts[index].matches(candidate, [
        ...path,
      ])) {
        return false;
      }
      if (index == 0) {
        return true;
      }
      final combinator = combinators[index - 1];
      if (combinator == SelectorCombinator.child) {
        if (path.isEmpty) {
          return false;
        }
        return matchPart(
          index - 1,
          path.last,
          path.sublist(0, path.length - 1),
        );
      }
      if (combinator == SelectorCombinator.adjacentSibling ||
          combinator == SelectorCombinator.generalSibling) {
        // 兄弟池：candidate 的父（path.last）元素子中位于 candidate
        // 之前的部分（由近及远）。
        if (path.isEmpty) {
          return false;
        }
        final siblings = path.last.childElements;
        var at = -1;
        for (var i = 0; i < siblings.length; i++) {
          if (identical(siblings[i], candidate)) {
            at = i;
            break;
          }
        }
        if (at <= 0) {
          return false;
        }
        if (combinator == SelectorCombinator.adjacentSibling) {
          return matchPart(index - 1, siblings[at - 1], path);
        }
        for (var i = at - 1; i >= 0; i--) {
          if (matchPart(index - 1, siblings[i], path)) {
            return true;
          }
        }
        return false;
      }
      for (var i = path.length - 1; i >= 0; i--) {
        if (matchPart(index - 1, path[i], path.sublist(0, i))) {
          return true;
        }
      }
      return false;
    }

    return matchPart(parts.length - 1, element, ancestors);
  }

  @override
  String toString() => text;
}

/// 选择器组（逗号分组）。
class SelectorList {
  /// 创建选择器组。
  const SelectorList({required this.selectors, required this.warnings});

  /// 可匹配的选择器。
  final List<ComplexSelector> selectors;

  /// 不支持选择器时的告警。
  final List<String> warnings;

  /// 任一选择器匹配。
  bool matches(SelectorElement element, List<SelectorElement> ancestors) =>
      selectors.any((selector) => selector.matches(element, ancestors));
}

/// 选择器解析器。
abstract final class SelectorParser {
  /// 解析选择器组；不支持的选择器跳过并记录 warning。
  static SelectorList parse(String text) {
    final warnings = <String>[];
    final errors = <csslib.Message>[];
    final SelectorGroup? group;
    try {
      group = csslib.parseSelectorGroup(text, errors: errors);
    } catch (error) {
      return SelectorList(
        selectors: const <ComplexSelector>[],
        warnings: <String>['选择器解析异常：$error'],
      );
    }
    if (group == null) {
      return SelectorList(
        selectors: const <ComplexSelector>[],
        warnings: <String>[
          ...errors.map((message) => message.describe),
          '选择器解析失败：$text',
        ],
      );
    }

    final result = <ComplexSelector>[];
    for (final selector in group.selectors) {
      final parsed = _parseComplex(selector, warnings);
      if (parsed != null) {
        result.add(parsed);
      }
    }
    return SelectorList(
      selectors: List<ComplexSelector>.unmodifiable(result),
      warnings: List<String>.unmodifiable(<String>[
        ...errors.map((message) => message.describe),
        ...warnings,
      ]),
    );
  }

  static ComplexSelector? _parseComplex(
    Selector selector,
    List<String> warnings,
  ) {
    final parts = <SelectorPart>[];
    final combinators = <SelectorCombinator>[];
    var id = 0, classes = 0, types = 0;
    var tag = <String?>[null];
    var idValue = <String?>[null];
    var classesValue = <Set<String>>[<String>{}];
    var attrTests = <List<AttributeTest>>[<AttributeTest>[]];
    var pseudoTests = <List<PseudoTest>>[<PseudoTest>[]];
    var slot = 0;
    void pushSlot() {
      tag.add(null);
      idValue.add(null);
      classesValue.add(<String>{});
      attrTests.add(<AttributeTest>[]);
      pseudoTests.add(<PseudoTest>[]);
      slot = tag.length - 1;
    }

    parts.add(SelectorPart());
    for (final sequence in selector.simpleSelectorSequences) {
      if (!sequence.isCombinatorNone) {
        SelectorCombinator? combinator;
        if (sequence.isCombinatorGreater) {
          combinator = SelectorCombinator.child;
        } else if (sequence.isCombinatorDescendant) {
          combinator = SelectorCombinator.descendant;
        } else if (sequence.isCombinatorPlus) {
          combinator = SelectorCombinator.adjacentSibling;
        } else if (sequence.isCombinatorTilde) {
          combinator = SelectorCombinator.generalSibling;
        }
        if (combinator == null) {
          warnings.add('暂不支持选择器组合符：${selector.span?.text ?? ''}');
          return null;
        }
        combinators.add(combinator);
        pushSlot();
      }
      final simple = sequence.simpleSelector;
      if (simple is ElementSelector) {
        if (!simple.isWildcard) {
          tag[slot] = simple.name;
          types += 1;
        }
      } else if (simple is ClassSelector) {
        classesValue[slot].add(simple.name);
        classes += 1;
      } else if (simple is IdSelector) {
        idValue[slot] = simple.name;
        id += 1;
      } else if (simple is AttributeSelector) {
        final name = simple.name.toLowerCase();
        final String op = simple.matchOperator() ?? '';
        final String value = simple.value == null
            ? ''
            : simple.value.toString();
        attrTests[slot].add(AttributeTest(name, op, value));
        classes += 1;
      } else if (simple is NegationSelector) {
        final arg = simple.negationArg;
        if (arg is ElementSelector ||
            arg is ClassSelector ||
            arg is IdSelector) {
          var text = '';
          if (arg is ElementSelector) {
            text = arg.name;
          } else if (arg is ClassSelector) {
            text = '.${arg.name}';
          } else if (arg is IdSelector) {
            text = '#${arg.name}';
          }
          pseudoTests[slot].add(PseudoTest('not', text));
          classes += 1;
        } else {
          warnings.add('暂不支持 :not 参数：${selector.span?.text ?? ''}');
          return null;
        }
      } else if (simple is PseudoClassFunctionSelector) {
        final name = simple.name.toLowerCase();
        if (name == 'nth-child') {
          // csslib 的函数 span 仅到左括号，参数属于独立 expression 节点。
          pseudoTests[slot].add(
            PseudoTest(name, simple.argument.span?.text),
          );
          classes += 1;
        } else if (name == 'not') {
          final inner = simple.selector;
          if (inner.simpleSelectorSequences.length == 1) {
            final only = inner.simpleSelectorSequences.single.simpleSelector;
            var text = '';
            if (only is ElementSelector) {
              text = only.name;
            } else if (only is ClassSelector) {
              text = '.${only.name}';
            } else if (only is IdSelector) {
              text = '#${only.name}';
            }
            if (text.isNotEmpty) {
              pseudoTests[slot].add(PseudoTest('not', text));
              classes += 1;
              continue;
            }
          }
          warnings.add('暂不支持 :not 参数：${selector.span?.text ?? ''}');
          return null;
        } else {
          warnings.add('暂不支持函数伪类 :$name');
          return null;
        }
      } else if (simple is PseudoClassSelector) {
        final name = simple.name.toLowerCase();
        pseudoTests[slot].add(PseudoTest(name, null));
        classes += 1;
      } else {
        warnings.add('暂不支持选择器：${selector.span?.text ?? ''}');
        return null;
      }
    }

    final built = <SelectorPart>[
      for (var i = 0; i < tag.length; i++)
        SelectorPart.withAttributes(
          tag: tag[i],
          id: idValue[i],
          classes: classesValue[i],
          attributeTests: attrTests[i],
          pseudos: pseudoTests[i],
        ),
    ];
    if (combinators.length != built.length - 1) {
      warnings.add('选择器结构不完整：${selector.span?.text ?? ''}');
      return null;
    }
    return ComplexSelector(
      parts: List<SelectorPart>.unmodifiable(built),
      combinators: List<SelectorCombinator>.unmodifiable(combinators),
      specificity: Specificity(0, id, classes, types),
      text: selector.span?.text ?? ''.trim(),
    );
  }

  /// 解析单个复合片段（:not 参数等内部使用）。
  static SelectorPart? parseCompound(String text) {
    final list = parse(text);
    if (list.selectors.length != 1 ||
        list.selectors.single.parts.length != 1) {
      return null;
    }
    return list.selectors.single.parts.single;
  }
}
