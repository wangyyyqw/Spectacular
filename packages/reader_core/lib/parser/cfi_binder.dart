import 'package:xml/xml.dart';

import '../position/cfi.dart';
import 'cfi_children.dart';

/// 绑定到 CFI 的逻辑字符块。
class BoundTextNode {
  /// 创建文本节点。
  const BoundTextNode({
    required this.text,
    required this.baseCfi,
    required this.elementSteps,
    required this.textStep,
    this.elementId,
  });

  /// 同一元素间普通文本与 CDATA 合并后的内容。
  final String text;

  /// 不含字符偏移的 base CFI。
  final EpubCfi baseCfi;

  /// 从 body 到所在元素的步进。
  final List<CfiStep> elementSteps;

  /// 文本节点步进（奇数）。
  final CfiStep textStep;

  /// 所在元素的 id，可为空。
  final String? elementId;
}

/// 一章的 CFI 绑定结果。
class BoundDocument {
  /// 创建绑定结果。
  const BoundDocument({
    required this.spineIndex,
    required this.textNodes,
    required this.elementCfi,
    this.warnings = const <String>[],
  });

  /// spine 序号。
  final int spineIndex;

  /// 全部文本节点。
  final List<BoundTextNode> textNodes;

  /// 元素 id → CFI。
  final Map<String, EpubCfi> elementCfi;

  /// 解析警告。
  final List<String> warnings;

  /// 按 id 取元素 CFI。
  EpubCfi? cfiForId(String id) => elementCfi[id];

  /// 按字符偏移细化文本节点 CFI；越界或负数返回 null。
  EpubCfi? refine(BoundTextNode node, int offset) {
    if (offset < 0 || offset > node.text.length) {
      return null;
    }
    return node.baseCfi.withCharOffset(offset);
  }
}

/// 解析 XHTML 时为每个非空逻辑字符块构造 base CFI。
abstract final class CfiBinder {
  /// 绑定一章；XHTML 解析失败时返回空节点并记录 warning。
  static BoundDocument bind({required String xhtml, required int spineIndex}) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(
        _stripBom(xhtml),
        entityMapping: cfiEntityMapping,
      );
    } on FormatException catch (error) {
      return BoundDocument(
        spineIndex: spineIndex,
        textNodes: const <BoundTextNode>[],
        elementCfi: const <String, EpubCfi>{},
        warnings: <String>['XHTML 解析失败：${error.message}'],
      );
    }

    XmlElement? body;
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'body') {
        body = element;
        break;
      }
    }
    if (body == null) {
      return BoundDocument(
        spineIndex: spineIndex,
        textNodes: const <BoundTextNode>[],
        elementCfi: const <String, EpubCfi>{},
        warnings: <String>['XHTML 缺少 body'],
      );
    }

    final textNodes = <BoundTextNode>[];
    final elementCfi = <String, EpubCfi>{};

    EpubCfi build(List<CfiStep> steps) {
      final builder = CfiBuilder().itemRef((spineIndex + 1) * 2).body(4);
      for (final step in steps) {
        builder.step(step.index, assertion: step.assertion);
      }
      return builder.build();
    }

    void visit(XmlElement parent, List<CfiStep> path) {
      for (final child in xmlCfiChildren(parent)) {
        final node = child.element;
        if (node is XmlElement) {
          final id = node.getAttribute('id')?.trim();
          final step = CfiStep(
            child.index,
            assertion: id == null || id.isEmpty ? null : id,
          );
          final nextPath = <CfiStep>[...path, step];
          final cfi = build(nextPath);
          if (id != null && id.isNotEmpty) {
            elementCfi.putIfAbsent(id, () => cfi);
          }
          visit(node, nextPath);
        } else if (child.text.isNotEmpty) {
          final textStep = CfiStep(child.index);
          textNodes.add(
            BoundTextNode(
              text: child.text,
              baseCfi: build(<CfiStep>[...path, textStep]),
              elementSteps: List<CfiStep>.unmodifiable(path),
              textStep: textStep,
              elementId: path.isEmpty ? null : path.last.assertion,
            ),
          );
        }
      }
    }

    final bodyCfi = build(const <CfiStep>[]);
    final bodyId = body.getAttribute('id')?.trim();
    if (bodyId != null && bodyId.isNotEmpty) {
      elementCfi[bodyId] = bodyCfi;
    }
    visit(body, const <CfiStep>[]);

    return BoundDocument(
      spineIndex: spineIndex,
      textNodes: List<BoundTextNode>.unmodifiable(textNodes),
      elementCfi: Map<String, EpubCfi>.unmodifiable(elementCfi),
    );
  }

  static String _stripBom(String text) =>
      text.startsWith('\uFEFF') ? text.substring(1) : text;
}
