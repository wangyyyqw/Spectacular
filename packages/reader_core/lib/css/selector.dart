import 'package:csslib/parser.dart' as csslib;
import 'package:csslib/visitor.dart';

import '../parser/document_parser.dart';

/// 组合符。
enum SelectorCombinator { descendant, child }

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

/// 复合选择器的一部分（同一元素上的 tag/#id/.class 组合）。
class SelectorPart {
  /// 创建部分。
  SelectorPart({this.tag, this.id, Set<String>? classes})
    : classes = classes ?? <String>{};

  /// 标签名；null 表示 `*`。
  final String? tag;

  /// id。
  final String? id;

  /// class 集合。
  final Set<String> classes;

  /// 是否匹配。
  bool matches(ParsedElement element) {
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
    return true;
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

  /// 匹配元素；[ancestors] 从根到父节点。
  bool matches(ParsedElement element, List<ParsedElement> ancestors) {
    bool matchPart(
      int index,
      ParsedElement candidate,
      List<ParsedElement> path,
    ) {
      if (index < 0) {
        return true;
      }
      if (!parts[index].matches(candidate)) {
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
  bool matches(ParsedElement element, List<ParsedElement> ancestors) =>
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
    var id = 0;
    var classes = 0;
    var types = 0;
    var current = SelectorPart();
    parts.add(current);

    for (final sequence in selector.simpleSelectorSequences) {
      if (!sequence.isCombinatorNone) {
        if (sequence.isCombinatorGreater) {
          combinators.add(SelectorCombinator.child);
        } else if (sequence.isCombinatorDescendant) {
          combinators.add(SelectorCombinator.descendant);
        } else {
          warnings.add('暂不支持选择器组合符：${selector.span?.text ?? ''}');
          return null;
        }
        current = SelectorPart();
        parts.add(current);
      }
      final simple = sequence.simpleSelector;
      if (simple is ElementSelector) {
        if (simple.isWildcard) {
          // 通配符不计特异性。
        } else {
          current = SelectorPart(
            tag: simple.name,
            id: current.id,
            classes: current.classes,
          );
          parts[parts.length - 1] = current;
          types += 1;
        }
      } else if (simple is ClassSelector) {
        current.classes.add(simple.name);
        classes += 1;
      } else if (simple is IdSelector) {
        // 同一个复合片段内 id 只保留最后一个，但特异性按出现次数计。
        final replacement = SelectorPart(
          tag: current.tag,
          id: simple.name,
          classes: current.classes,
        );
        parts[parts.length - 1] = replacement;
        current = replacement;
        id += 1;
      } else {
        warnings.add('暂不支持选择器：${selector.span?.text ?? ''}');
        return null;
      }
    }

    if (combinators.length != parts.length - 1) {
      warnings.add('选择器结构不完整：${selector.span?.text ?? ''}');
      return null;
    }
    return ComplexSelector(
      parts: List<SelectorPart>.unmodifiable(parts),
      combinators: List<SelectorCombinator>.unmodifiable(combinators),
      specificity: Specificity(0, id, classes, types),
      text: selector.span?.text ?? ''.trim(),
    );
  }
}
