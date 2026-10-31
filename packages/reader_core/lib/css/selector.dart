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

/// `:has()` 的一项相对选择器；[combinator] 为参数开头的组合符。
class RelativeSelector {
  /// 创建相对选择器。
  const RelativeSelector(this.combinator, this.selector);

  /// 相对组合符；缺省为后代（`:has(p)`）。
  final SelectorCombinator combinator;

  /// 组合符之后的选择器。
  final ComplexSelector selector;
}

/// 结构伪类与否定选择器；An+B 和否定参数只编译一次。
class PseudoTest {
  /// 创建测试；[negation] 复用解析器已编译的否定参数。
  PseudoTest(
    this.name,
    this.argument, {
    this.negation,
    this.selectors = const <ComplexSelector>[],
    this.relatives = const <RelativeSelector>[],
    this.specificity = const Specificity(0, 0, 0, 0),
  });

  final String name;
  final String? argument;

  /// 否定参数的编译结果；省略时兼容从 [argument] 延迟解析。
  final ComplexSelector? negation;

  /// 列表参数（`:is()` / `:where()` / `:not()` / `:nth-child(... of S)`）。
  final List<ComplexSelector> selectors;

  /// `:has()` 的相对选择器参数。
  final List<RelativeSelector> relatives;

  /// 函数伪类自身贡献的特异性（`:where()` 为零）。
  final Specificity specificity;

  static const _nthNames = {
    'nth-child',
    'nth-last-child',
    'nth-of-type',
    'nth-last-of-type',
  };
  static const _positionNames = {
    ..._nthNames,
    'first-child',
    'last-child',
    'only-child',
    'first-of-type',
    'last-of-type',
    'only-of-type',
  };
  late final _nth = _parseNth(argument ?? '');
  late final _negation =
      negation ??
      (argument == null
          ? null
          : SelectorParser.parse(argument!).selectors.singleOrNull);

  /// 是否需要元素的兄弟位置，而非仅依赖标签、属性和祖先链。
  bool get usesTreePosition =>
      _positionNames.contains(name) ||
      name == 'has' ||
      selectors.any((selector) => selector.usesTreePosition) ||
      (name == 'not' && (_negation?.usesTreePosition ?? false));

  bool matches(SelectorElement element, List<SelectorElement> ancestors) {
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
      case 'not':
        if (selectors.isNotEmpty) {
          return !selectors.any(
            (selector) => selector.matches(element, ancestors),
          );
        }
        return _negation != null && !_negation.matches(element, ancestors);
      case 'is':
      case 'where':
        return selectors.any(
          (selector) => selector.matches(element, ancestors),
        );
      case 'has':
        return _matchesHas(element, ancestors);
      default:
        return _positionNames.contains(name) &&
            _matchesPosition(element, ancestors);
    }
  }

  bool _matchesHas(SelectorElement element, List<SelectorElement> ancestors) {
    for (final relative in relatives) {
      if (_matchesRelative(relative, element, ancestors)) {
        return true;
      }
    }
    return false;
  }

  bool _matchesRelative(
    RelativeSelector relative,
    SelectorElement anchor,
    List<SelectorElement> ancestors,
  ) {
    final selector = relative.selector;
    bool matchesFirst(SelectorElement candidate, List<SelectorElement> path) {
      return selector.parts.first.matches(candidate, path) &&
          _matchesRelativeTail(selector, 0, candidate, path);
    }

    switch (relative.combinator) {
      case SelectorCombinator.child:
        final path = <SelectorElement>[...ancestors, anchor];
        for (final child in anchor.childElements) {
          if (matchesFirst(child, path)) {
            return true;
          }
        }
      case SelectorCombinator.adjacentSibling:
        final siblings = ancestors.isEmpty
            ? const <SelectorElement>[]
            : ancestors.last.childElements;
        final index = siblings.indexWhere(
          (sibling) => identical(sibling, anchor),
        );
        if (index >= 0 && index + 1 < siblings.length) {
          return matchesFirst(siblings[index + 1], ancestors);
        }
      case SelectorCombinator.generalSibling:
        final siblings = ancestors.isEmpty
            ? const <SelectorElement>[]
            : ancestors.last.childElements;
        final index = siblings.indexWhere(
          (sibling) => identical(sibling, anchor),
        );
        if (index >= 0) {
          for (var i = index + 1; i < siblings.length; i++) {
            if (matchesFirst(siblings[i], ancestors)) {
              return true;
            }
          }
        }
      case SelectorCombinator.descendant:
        bool visit(SelectorElement node, List<SelectorElement> nodePath) {
          for (final child in node.childElements) {
            final childPath = <SelectorElement>[...nodePath, node];
            if (matchesFirst(child, childPath) || visit(child, childPath)) {
              return true;
            }
          }
          return false;
        }

        return visit(anchor, ancestors);
    }
    return false;
  }

  static bool _matchesRelativeTail(
    ComplexSelector selector,
    int index,
    SelectorElement candidate,
    List<SelectorElement> path,
  ) {
    if (index >= selector.parts.length - 1) {
      return true;
    }

    bool matchesNext(SelectorElement next, List<SelectorElement> nextPath) {
      return selector.parts[index + 1].matches(next, nextPath) &&
          _matchesRelativeTail(selector, index + 1, next, nextPath);
    }

    final combinator = selector.combinators[index];
    if (combinator == SelectorCombinator.child) {
      final nextPath = <SelectorElement>[...path, candidate];
      for (final child in candidate.childElements) {
        if (matchesNext(child, nextPath)) {
          return true;
        }
      }
      return false;
    }
    if (combinator == SelectorCombinator.adjacentSibling ||
        combinator == SelectorCombinator.generalSibling) {
      if (path.isEmpty) {
        return false;
      }
      final siblings = path.last.childElements;
      final at = siblings.indexWhere(
        (sibling) => identical(sibling, candidate),
      );
      if (at < 0 || at + 1 >= siblings.length) {
        return false;
      }
      if (combinator == SelectorCombinator.adjacentSibling) {
        return matchesNext(siblings[at + 1], path);
      }
      for (var i = at + 1; i < siblings.length; i++) {
        if (matchesNext(siblings[i], path)) {
          return true;
        }
      }
      return false;
    }

    bool visit(SelectorElement node, List<SelectorElement> nodePath) {
      for (final child in node.childElements) {
        final childPath = <SelectorElement>[...nodePath, node];
        if (matchesNext(child, childPath) || visit(child, childPath)) {
          return true;
        }
      }
      return false;
    }

    return visit(candidate, path);
  }

  bool _matchesPosition(
    SelectorElement element,
    List<SelectorElement> ancestors,
  ) {
    final ofType = name.endsWith('of-type');
    var siblings = ancestors.isEmpty ? [element] : ancestors.last.childElements;
    if (selectors.isNotEmpty) {
      siblings = <SelectorElement>[
        for (final sibling in siblings)
          if (selectors.any((selector) => selector.matches(sibling, ancestors)))
            sibling,
      ];
    }
    final tag = element.tag.toLowerCase();
    var index = 0, count = 0;
    for (final sibling in siblings) {
      if (ofType && sibling.tag.toLowerCase() != tag) continue;
      count++;
      if (identical(sibling, element)) index = count;
    }
    if (index == 0) return false;
    if (name.startsWith('only-')) return count == 1;
    final fromEnd = name.startsWith('last-') || name.startsWith('nth-last-');
    final position = fromEnd ? count - index + 1 : index;
    if (name.startsWith('first-') || name.startsWith('last-')) {
      return position == 1;
    }
    final pattern = _nth;
    if (pattern == null) return false;
    final (step, offset) = pattern;
    if (step == 0) return position == offset;
    final delta = position - offset;
    return delta % step == 0 && delta ~/ step >= 0;
  }

  /// An+B 的 n 必须为非负整数；负步进如 -n+2 只选择前两个元素。
  static (int, int)? _parseNth(String raw) {
    final arg = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (arg == 'odd') return (2, 1);
    if (arg == 'even') return (2, 0);
    final number = int.tryParse(arg);
    if (number != null) return (0, number);
    final match = RegExp(r'^([+-]?\d*)n([+-]\d+)?$').firstMatch(arg);
    if (match == null) return null;
    final coefficient = match.group(1)!;
    final step = coefficient.isEmpty || coefficient == '+'
        ? 1
        : coefficient == '-'
        ? -1
        : int.tryParse(coefficient);
    final offset = match.group(2) == null ? 0 : int.tryParse(match.group(2)!);
    return step == null || offset == null ? null : (step, offset);
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

  /// 结构伪类和兄弟组合器禁止同形元素共享最终样式。
  bool get usesTreePosition =>
      combinators.any(
        (combinator) =>
            combinator == SelectorCombinator.adjacentSibling ||
            combinator == SelectorCombinator.generalSibling,
      ) ||
      parts.any(
        (part) => part.pseudos.any((pseudo) => pseudo.usesTreePosition),
      );

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
      if (!parts[index].matches(candidate, path)) {
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
    final extracted = _extractFunctionalPseudos(text);
    warnings.addAll(extracted.warnings);
    if (extracted.invalid) {
      return SelectorList(
        selectors: const <ComplexSelector>[],
        warnings: List<String>.unmodifiable(warnings),
      );
    }
    final errors = <csslib.Message>[];
    final SelectorGroup? group;
    try {
      group = csslib.parseSelectorGroup(extracted.text, errors: errors);
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
      final parsed = _parseComplex(selector, warnings, extracted.tests);
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

  /// 提取 csslib 无法完整解析的函数伪类，替换成可解析的占位符。
  static _ExtractedPseudos _extractFunctionalPseudos(String text) {
    final tests = <String, PseudoTest>{};
    final warnings = <String>[];
    final output = StringBuffer();
    var invalid = false;
    var index = 0;
    String? quote;

    while (index < text.length) {
      final char = text[index];
      if (quote != null) {
        output.write(char);
        if (char == r'\' && index + 1 < text.length) {
          output.write(text[index + 1]);
          index += 2;
          continue;
        }
        if (char == quote) {
          quote = null;
        }
        index += 1;
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        output.write(char);
        index += 1;
        continue;
      }
      if (char == ':' &&
          (index == 0 || text[index - 1] != ':') &&
          (index == 0 || text[index - 1] != r'\')) {
        var end = index + 1;
        while (end < text.length && _isSelectorNameChar(text[end])) {
          end += 1;
        }
        if (end > index + 1 && end < text.length && text[end] == '(') {
          final name = text.substring(index + 1, end).toLowerCase();
          final argument = _functionArgument(text, end);
          if (argument != null && _shouldCompileFunction(name, argument.text)) {
            final compiled = _compileFunctionalPseudo(
              name,
              argument.text,
              warnings,
            );
            if (compiled == null) {
              invalid = true;
            } else {
              final placeholder = 'rp${tests.length}';
              tests[placeholder] = compiled;
              output.write(':$placeholder');
            }
            index = argument.end + 1;
            continue;
          }
        }
      }
      output.write(char);
      index += 1;
    }

    return _ExtractedPseudos(
      text: output.toString(),
      tests: tests,
      warnings: warnings,
      invalid: invalid,
    );
  }

  static bool _isSelectorNameChar(String char) {
    final unit = char.codeUnitAt(0);
    return (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A) ||
        char == '-' ||
        char == '_';
  }

  /// 读取函数参数并返回右括号位置；括号、方括号与引号内的分隔符不计数。
  static _FunctionArgument? _functionArgument(String text, int open) {
    var depth = 0;
    var brackets = 0;
    String? quote;
    for (var i = open; i < text.length; i++) {
      final char = text[i];
      if (quote != null) {
        if (char == r'\' && i + 1 < text.length) {
          i += 1;
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '[') {
        brackets += 1;
        continue;
      }
      if (char == ']') {
        if (brackets > 0) brackets -= 1;
        continue;
      }
      if (brackets > 0) {
        continue;
      }
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        depth -= 1;
        if (depth == 0) {
          return _FunctionArgument(text.substring(open + 1, i), i);
        }
      }
    }
    return null;
  }

  static bool _shouldCompileFunction(String name, String argument) {
    if (name == 'is' || name == 'where' || name == 'not' || name == 'has') {
      return true;
    }
    if (name == 'nth-child' || name == 'nth-last-child') {
      return _splitNthOf(argument)?.$2 != null;
    }
    return false;
  }

  static PseudoTest? _compileFunctionalPseudo(
    String name,
    String argument,
    List<String> warnings,
  ) {
    switch (name) {
      case 'is':
      case 'where':
      case 'not':
        final selectors = _parseSelectorList(argument, ':$name()', warnings);
        if (selectors == null) return null;
        final specificity = name == 'where'
            ? const Specificity(0, 0, 0, 0)
            : _maxSpecificity(selectors);
        return PseudoTest(
          name,
          argument,
          selectors: selectors,
          specificity: specificity,
        );
      case 'has':
        final relatives = _parseRelativeSelectors(argument, warnings);
        if (relatives == null) return null;
        return PseudoTest(
          'has',
          argument,
          relatives: relatives,
          specificity: _maxSpecificity(
            relatives.map((relative) => relative.selector),
          ),
        );
      case 'nth-child':
      case 'nth-last-child':
        final split = _splitNthOf(argument);
        final pattern = split?.$1;
        final ofSelector = split?.$2;
        if (pattern == null ||
            ofSelector == null ||
            ofSelector.isEmpty ||
            PseudoTest._parseNth(pattern) == null) {
          warnings.add('无效的结构伪类参数：$argument');
          return null;
        }
        final selectors = _parseSelectorList(
          ofSelector,
          ':$name(... of S)',
          warnings,
        );
        if (selectors == null) return null;
        final inner = _maxSpecificity(selectors);
        return PseudoTest(
          name,
          pattern,
          selectors: selectors,
          specificity: Specificity(
            0,
            inner.id,
            1 + inner.classCount,
            inner.type,
          ),
        );
      default:
        return null;
    }
  }

  static List<ComplexSelector>? _parseSelectorList(
    String text,
    String context,
    List<String> warnings,
  ) {
    final parsed = SelectorParser.parse(text);
    if (parsed.selectors.isEmpty || parsed.warnings.isNotEmpty) {
      warnings.add('$context 参数无效：$text');
      warnings.addAll(parsed.warnings);
      return null;
    }
    return parsed.selectors;
  }

  static List<RelativeSelector>? _parseRelativeSelectors(
    String text,
    List<String> warnings,
  ) {
    final parts = _splitTopLevel(text, ',');
    if (parts == null) {
      warnings.add(':has() 参数括号不匹配');
      return null;
    }
    final relatives = <RelativeSelector>[];
    for (final raw in parts) {
      var part = raw.trim();
      if (part.isEmpty) {
        warnings.add(':has() 含空参数');
        return null;
      }
      var combinator = SelectorCombinator.descendant;
      if (part.startsWith('>')) {
        combinator = SelectorCombinator.child;
        part = part.substring(1).trim();
      } else if (part.startsWith('+')) {
        combinator = SelectorCombinator.adjacentSibling;
        part = part.substring(1).trim();
      } else if (part.startsWith('~')) {
        combinator = SelectorCombinator.generalSibling;
        part = part.substring(1).trim();
      }
      if (part.isEmpty) {
        warnings.add(':has() 组合符后缺少选择器');
        return null;
      }
      final selectors = _parseSelectorList(part, ':has()', warnings);
      if (selectors == null || selectors.length != 1) {
        warnings.add(':has() 只接受单个复合选择器：$raw');
        return null;
      }
      relatives.add(RelativeSelector(combinator, selectors.single));
    }
    return relatives.isEmpty ? null : relatives;
  }

  /// 拆分顶层逗号；括号、方括号和引号内的逗号保留。
  static List<String>? _splitTopLevel(String text, String delimiter) {
    final parts = <String>[];
    var start = 0;
    var depth = 0;
    var brackets = 0;
    String? quote;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quote != null) {
        if (char == r'\' && i + 1 < text.length) {
          i += 1;
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '[') {
        brackets += 1;
        continue;
      }
      if (char == ']') {
        if (brackets > 0) brackets -= 1;
        continue;
      }
      if (brackets > 0) continue;
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        depth -= 1;
        if (depth < 0) return null;
      } else if (char == delimiter && depth == 0) {
        parts.add(text.substring(start, i));
        start = i + 1;
      }
    }
    if (quote != null || depth != 0 || brackets != 0) return null;
    parts.add(text.substring(start));
    return parts;
  }

  /// 拆分 `An+B of S` 的顶层 `of`；不含 `of` 时返回 `(pattern, null)`。
  static (String, String?)? _splitNthOf(String text) {
    var depth = 0;
    var brackets = 0;
    String? quote;
    for (var i = 0; i + 1 < text.length; i++) {
      final char = text[i];
      if (quote != null) {
        if (char == r'\' && i + 1 < text.length) {
          i += 1;
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '[') {
        brackets += 1;
        continue;
      }
      if (char == ']') {
        if (brackets > 0) brackets -= 1;
        continue;
      }
      if (brackets > 0) continue;
      if (char == '(') {
        depth += 1;
        continue;
      }
      if (char == ')') {
        depth -= 1;
        continue;
      }
      if (depth != 0) continue;
      if (text.substring(i, i + 2).toLowerCase() != 'of') continue;
      final before = i == 0 || _isWhitespace(text[i - 1]);
      final after = i + 2 >= text.length || _isWhitespace(text[i + 2]);
      if (!before || !after) continue;
      return (text.substring(0, i).trim(), text.substring(i + 2).trim());
    }
    return (text.trim(), null);
  }

  static bool _isWhitespace(String char) =>
      char == ' ' || char == '\n' || char == '\r' || char == '\t';

  static Specificity _maxSpecificity(Iterable<ComplexSelector> selectors) {
    var max = const Specificity(0, 0, 0, 0);
    for (final selector in selectors) {
      if (selector.specificity.compareTo(max) > 0) {
        max = selector.specificity;
      }
    }
    return max;
  }

  static ComplexSelector? _parseComplex(
    Selector selector,
    List<String> warnings,
    Map<String, PseudoTest> functions,
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
        if (arg == null) {
          warnings.add('否定选择器缺少参数');
          return null;
        }
        final inner = _parseComplex(
          Selector([SimpleSelectorSequence(arg, arg.span)], arg.span),
          warnings,
          functions,
        );
        if (inner == null) return null;
        pseudoTests[slot].add(
          PseudoTest('not', arg.span?.text, negation: inner),
        );
        id += inner.specificity.id;
        classes += inner.specificity.classCount;
        types += inner.specificity.type;
      } else if (simple is PseudoClassFunctionSelector) {
        final name = simple.name.toLowerCase();
        if (!PseudoTest._nthNames.contains(name)) {
          warnings.add('暂不支持函数伪类 :$name');
          return null;
        }
        // csslib 的函数 span 仅到左括号，参数属于独立 expression 节点。
        final pseudo = PseudoTest(name, simple.argument.span?.text);
        if (pseudo._nth == null) {
          warnings.add('无效的结构伪类参数：${simple.argument.span?.text}');
          return null;
        }
        pseudoTests[slot].add(pseudo);
        classes += 1;
      } else if (simple is PseudoClassSelector) {
        final name = simple.name.toLowerCase();
        final functional = functions[name];
        if (functional != null) {
          pseudoTests[slot].add(functional);
          id += functional.specificity.id;
          classes += functional.specificity.classCount;
          types += functional.specificity.type;
          continue;
        }
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
}

class _FunctionArgument {
  const _FunctionArgument(this.text, this.end);

  final String text;
  final int end;
}

class _ExtractedPseudos {
  const _ExtractedPseudos({
    required this.text,
    required this.tests,
    required this.warnings,
    required this.invalid,
  });

  final String text;
  final Map<String, PseudoTest> tests;
  final List<String> warnings;
  final bool invalid;
}
