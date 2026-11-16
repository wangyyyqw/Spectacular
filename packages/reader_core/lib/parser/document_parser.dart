import 'package:html/dom.dart' as dom;

import '../position/cfi.dart';
import '../src/api/interfaces.dart';
import '../src/api/models.dart';
import 'cfi_children.dart';
import 'cfi_resolver.dart';
import 'xhtml_input.dart';

/// 解析路径选择（P7-11 双路径）。
///
/// 合法 XHTML 使用带源位置的 XML 事件树，CFI 结构与原文一致；失败自动
/// 回退 html5lib 容错解析（[tolerantFallback]），带降级诊断。
enum DocumentParserChoice { strict, tolerantFallback }

/// 解析后的节点基类。
sealed class ParsedNode implements EpubNode {
  /// 创建节点。
  ParsedNode({required this.start, required this.end, required this.cfi});

  /// 源码起始偏移（UTF-16 code unit）。
  final int start;

  /// 源码结束偏移。
  final int end;

  /// 解析期绑定的 base CFI。
  final EpubCfi cfi;
}

/// 解析后的元素节点。
final class ParsedElement extends ParsedNode implements Element {
  /// 创建元素。
  ParsedElement({
    required this.tag,
    required this.attributes,
    required this.children,
    required super.start,
    required super.end,
    required super.cfi,
  });

  /// 标签名（小写）。
  final String tag;

  /// 属性（已解码）。
  final Map<String, String> attributes;

  /// 子节点。
  final List<ParsedNode> children;

  /// id 属性。
  String? get id => attributes['id'];
}

/// 解析后的文本节点。
final class ParsedText extends ParsedNode {
  /// 创建文本节点。
  ParsedText({
    required this.text,
    required super.start,
    required super.end,
    required super.cfi,
  });

  /// 解码后的文本。
  final String text;
}

/// 一章的解析结果，可直接作为 SpineDocument。
class ParsedDocument implements SpineDocument {
  /// 创建文档。
  ParsedDocument({
    required this.spineIndex,
    required this.root,
    required this.source,
    required this.textNodes,
    required this.elementsById,
    required this.parserChoice,
    this.htmlAttributes = const <String, String>{},
    this.parseDiagnostics = const <String>[],
  }) : plainText = textNodes.map((node) => node.text).join();

  @override
  final int spineIndex;

  @override
  final ParsedElement root;

  /// 原始 XHTML，用于失效 CFI 容错。
  final String source;

  /// 根元素属性供视口轴级联使用；不把 html 插入正文树，保持原有 CFI。
  final Map<String, String> htmlAttributes;

  /// 全部文本节点（文档顺序）。
  final List<ParsedText> textNodes;

  /// id → 元素。
  final Map<String, ParsedElement> elementsById;

  /// 解析路径（P7-11）：作为章节缓存键的一部分，回读缓存时据此判断
  /// 旧结果可否复用（两条路径的 DOM 结构可能不同）。
  final DocumentParserChoice parserChoice;

  /// 解析期降级诊断（如严格解析失败的原因摘要）。
  final List<String> parseDiagnostics;

  /// 排版缓存的路径分量：两条路径可区分。
  String get parserCacheKey => switch (parserChoice) {
    DocumentParserChoice.strict => 'strict',
    DocumentParserChoice.tolerantFallback => 'tolerant',
  };

  @override
  final String plainText;

  @override
  int get charCount => plainText.length;

  /// 按 id 取元素。
  ParsedElement? elementById(String id) => elementsById[id];

  /// 按路径精确定位节点；路径不存在或字符槽没有实际文本节点时返回 null。
  ParsedNode? nodeAtCfi(EpubCfi cfi) {
    if (cfi.isRange) {
      return null;
    }
    final itemref = cfi.itemref;
    if (itemref == null || itemref != (spineIndex + 1) * 2) {
      return null;
    }
    ParsedNode current = root;
    for (final step in cfi.steps) {
      if (current is! ParsedElement) {
        return null;
      }
      if (step.index.isEven) {
        final next = _elementAtStep(current, step);
        if (next == null) {
          return null;
        }
        current = next;
      } else {
        for (final text in current.children.whereType<ParsedText>()) {
          if (text.cfi.steps.last.index == step.index) {
            return text;
          }
        }
        return null;
      }
    }
    return current;
  }

  ParsedElement? _elementAtStep(ParsedElement parent, CfiStep step) {
    final elements = parent.children.whereType<ParsedElement>().toList(
      growable: false,
    );
    final index = step.index ~/ 2;
    var next = index >= 1 && index <= elements.length
        ? elements[index - 1]
        : null;
    final assertion = step.assertion;
    if (next == null ||
        (assertion != null && assertion.isNotEmpty && next.id != assertion)) {
      if (assertion != null && assertion.isNotEmpty) {
        next = elementsById[assertion] ?? next;
      }
    }
    return next;
  }

  /// 容错解析失效 CFI。
  CfiResolution resolve(EpubCfi cfi) => CfiResolver.resolve(
    xhtml: source,
    target: cfi,
    expectedSpineIndex: spineIndex,
  );
}

/// 把 XHTML 解析为节点模型，并在解析期绑定 CFI。
abstract final class DocumentParser {
  /// DOM 嵌套深度上限（P7-16；对照 Reeden nestingTooDeep 防线，
  /// 兼顾本解析器 convert 的递归栈深）。超限子树展平为文本。
  static const int maxDomDepth = 500;

  /// 单个属性值长度上限（P7-16；对照 Reeden SVG 单段 65536 字符——
  /// data URI 炸弹经属性进入）。超限截断并记诊断。
  static const int maxAttributeValueLength = 65536;

  /// 解析 XHTML。
  ///
  /// 先用严格 XML 转换（P7-11 双路径）：合法命中 [DocumentParserChoice.strict]；
  /// 失败回退 html5lib 容错解析并记录降级诊断（诊断码
  /// `E_DOCUMENT_TOLERANT_FALLBACK`）。压力防护（P7-16）：嵌套超
  /// [maxDomDepth] 的子树展平为文本（`E_DOM_NESTING_TOO_DEEP`），
  /// 属性值超 [maxAttributeValueLength] 截断（`E_ATTRIBUTE_TRUNCATED`）。
  static ParsedDocument parse({
    required String xhtml,
    required int spineIndex,
  }) {
    var choice = DocumentParserChoice.strict;
    final diagnostics = <String>[];
    late final XhtmlInput input;
    try {
      input = parseStrictXhtmlInput(xhtml);
    } on FormatException catch (error) {
      choice = DocumentParserChoice.tolerantFallback;
      diagnostics.add(
        'E_DOCUMENT_TOLERANT_FALLBACK: 严格 XML 解析失败（${error.message}），'
        '已回退容错解析',
      );
      input = parseTolerantXhtmlInput(xhtml);
    }
    var depthClamped = 0;
    var attributesTruncated = 0;
    final textNodes = <ParsedText>[];
    final elementsById = <String, ParsedElement>{};

    EpubCfi build(List<CfiStep> steps) {
      final builder = CfiBuilder().itemRef((spineIndex + 1) * 2).body(4);
      for (final step in steps) {
        builder.step(step.index, assertion: step.assertion);
      }
      return builder.build();
    }

    final offsetStart = input.startOf;
    final offsetEnd = input.endOf;

    ParsedElement convert(dom.Element element, List<CfiStep> path, int depth) {
      final attributes = <String, String>{
        for (final entry in element.attributes.entries)
          entry.key.toString(): _capAttributeValue(
            entry.value,
            () => attributesTruncated += 1,
          ),
      };
      final node = ParsedElement(
        tag: element.localName ?? '',
        attributes: Map<String, String>.unmodifiable(attributes),
        children: <ParsedNode>[],
        start: offsetStart(element),
        end: offsetEnd(element),
        cfi: build(path),
      );
      final id = attributes['id'];
      if (id != null && id.isNotEmpty) {
        elementsById.putIfAbsent(id, () => node);
      }

      // 嵌套超限：子树不再下钻，文本展平保留可读内容（P7-16）。
      if (depth >= maxDomDepth) {
        depthClamped += 1;
        final flat = element.text;
        if (flat.isNotEmpty) {
          final text = ParsedText(
            text: flat,
            start: offsetStart(element),
            end: offsetEnd(element),
            cfi: build(<CfiStep>[...path, CfiStep(1)]),
          );
          node.children.add(text);
          textNodes.add(text);
        }
        return node;
      }

      for (final child in cfiChildren(
        element.nodes,
        isElement: (node) => node is dom.Element,
        textOf: (node) => node is dom.Text ? node.text : null,
      )) {
        final childElement = child.element;
        if (childElement is dom.Element) {
          final childId = childElement.attributes['id'];
          final step = CfiStep(
            child.index,
            assertion: childId == null || childId.isEmpty ? null : childId,
          );
          node.children.add(
            convert(childElement, <CfiStep>[...path, step], depth + 1),
          );
        } else if (child.text.isNotEmpty) {
          final step = CfiStep(child.index);
          final text = ParsedText(
            text: child.text,
            start: offsetStart(child.characters.first),
            end: offsetEnd(child.characters.last),
            cfi: build(<CfiStep>[...path, step]),
          );
          node.children.add(text);
          textNodes.add(text);
        }
      }
      return node;
    }

    final root = convert(input.body, const <CfiStep>[], 0);
    final htmlAttributes = <String, String>{
      for (final entry in input.htmlAttributes.entries)
        entry.key.toString(): _capAttributeValue(
          entry.value,
          () => attributesTruncated += 1,
        ),
    };
    if (depthClamped > 0) {
      diagnostics.add(
        'E_DOM_NESTING_TOO_DEEP: $depthClamped 处嵌套超过 $maxDomDepth 层，'
        '子树已展平为文本',
      );
    }
    if (attributesTruncated > 0) {
      diagnostics.add(
        'E_ATTRIBUTE_TRUNCATED: $attributesTruncated 处属性值超过'
        ' $maxAttributeValueLength 字符，已截断',
      );
    }
    return ParsedDocument(
      spineIndex: spineIndex,
      root: root,
      source: xhtml,
      htmlAttributes: Map.unmodifiable(htmlAttributes),
      textNodes: List<ParsedText>.unmodifiable(textNodes),
      elementsById: Map<String, ParsedElement>.unmodifiable(elementsById),
      parserChoice: choice,
      parseDiagnostics: List<String>.unmodifiable(diagnostics),
    );
  }

  /// 属性值长度钳制（P7-16）：超限截断并计数（data URI 炸弹防线）。
  static String _capAttributeValue(String value, void Function() onTruncate) {
    if (value.length <= maxAttributeValueLength) {
      return value;
    }
    onTruncate();
    return value.substring(0, maxAttributeValueLength);
  }
}
