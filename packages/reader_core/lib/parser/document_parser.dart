import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;

import '../position/cfi.dart';
import '../src/api/interfaces.dart';
import '../src/api/models.dart';
import 'cfi_resolver.dart';

/// 解析路径选择（P7-11 双路径）。
///
/// 严格 XML 解析作为**校验闸门**：合法 XHTML 命中 [strict]（命名空间
/// 与 `epub:type` 语义可用）；失败自动回退 html5lib 容错解析
/// （[tolerantFallback]），带降级诊断。转换层始终走 html5lib——它提供
/// sourceSpan 源偏移，是 CFI 绑定与失效容错的坐标基础；`package:xml`
/// 不带偏移，直接转换会破坏 CFI（对照 Reeden 双路径动机，500 号 §1）。
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
    this.parseDiagnostics = const <String>[],
  }) : plainText = textNodes.map((node) => node.text).join();

  @override
  final int spineIndex;

  @override
  final ParsedElement root;

  /// 原始 XHTML，用于失效 CFI 容错。
  final String source;

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

  /// 按路径精确定位节点；路径不存在返回 null。
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
        final elements = current.children.whereType<ParsedElement>().toList(
          growable: false,
        );
        final index = step.index ~/ 2;
        ParsedElement? next;
        if (index >= 1 && index <= elements.length) {
          next = elements[index - 1];
        }
        final assertion = step.assertion;
        if (next == null ||
            (assertion != null &&
                assertion.isNotEmpty &&
                next.id != assertion)) {
          if (assertion != null && assertion.isNotEmpty) {
            final byId = elementsById[assertion];
            if (byId != null) {
              next = byId;
            }
          }
        }
        if (next == null) {
          return null;
        }
        current = next;
      } else {
        final texts = current.children.whereType<ParsedText>().toList(
          growable: false,
        );
        final index = (step.index + 1) ~/ 2;
        if (index < 1 || index > texts.length) {
          return null;
        }
        return texts[index - 1];
      }
    }
    return current;
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
  /// 解析 XHTML。
  ///
  /// 先用严格 XML 校验（P7-11 双路径）：合法命中 [DocumentParserChoice.strict]；
  /// 失败回退 html5lib 容错解析并记录降级诊断（诊断码
  /// `E_DOCUMENT_TOLERANT_FALLBACK`）。
  static ParsedDocument parse({
    required String xhtml,
    required int spineIndex,
  }) {
    var choice = DocumentParserChoice.strict;
    final diagnostics = <String>[];
    try {
      xml.XmlDocument.parse(xhtml);
    } on xml.XmlException catch (error) {
      choice = DocumentParserChoice.tolerantFallback;
      diagnostics.add(
        'E_DOCUMENT_TOLERANT_FALLBACK: 严格 XML 解析失败（${error.message}），'
        '已回退容错解析',
      );
    }
    final document = html_parser.parse(xhtml, generateSpans: true);
    final body = document.body;
    if (body == null) {
      throw const FormatException('XHTML 缺少 body');
    }
    final textNodes = <ParsedText>[];
    final elementsById = <String, ParsedElement>{};

    EpubCfi build(List<CfiStep> steps) {
      final builder = CfiBuilder().itemRef((spineIndex + 1) * 2).body(4);
      for (final step in steps) {
        builder.step(step.index, assertion: step.assertion);
      }
      return builder.build();
    }

    int offsetStart(dom.Node node) => node.sourceSpan?.start.offset ?? 0;
    int offsetEnd(dom.Node node) =>
        node.sourceSpan?.end.offset ?? offsetStart(node);

    ParsedElement convert(dom.Element element, List<CfiStep> path) {
      final attributes = <String, String>{
        for (final entry in element.attributes.entries)
          entry.key.toString(): entry.value,
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

      var elementIndex = 0;
      var textIndex = 0;
      for (final child in element.nodes) {
        if (child is dom.Element) {
          elementIndex += 1;
          final childId = child.attributes['id'];
          final step = CfiStep(
            elementIndex * 2,
            assertion: childId == null || childId.isEmpty ? null : childId,
          );
          node.children.add(convert(child, <CfiStep>[...path, step]));
        } else if (child is dom.Text) {
          textIndex += 1;
          final step = CfiStep(textIndex * 2 - 1);
          final text = ParsedText(
            text: child.text,
            start: offsetStart(child),
            end: offsetEnd(child),
            cfi: build(<CfiStep>[...path, step]),
          );
          node.children.add(text);
          textNodes.add(text);
        }
      }
      return node;
    }

    final root = convert(body, const <CfiStep>[]);
    return ParsedDocument(
      spineIndex: spineIndex,
      root: root,
      source: xhtml,
      textNodes: List<ParsedText>.unmodifiable(textNodes),
      elementsById: Map<String, ParsedElement>.unmodifiable(elementsById),
      parserChoice: choice,
      parseDiagnostics: List<String>.unmodifiable(diagnostics),
    );
  }
}
