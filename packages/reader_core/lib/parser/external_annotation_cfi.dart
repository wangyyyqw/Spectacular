import 'package:xml/xml.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;

import '../position/cfi.dart';
import 'cfi_children.dart';

/// 阅微使用原 DOM 子节点序号，并在文本节点之后附加字符端点。
/// 转换依赖对应章节原文；调用方仍须核验选区引用。
class ExternalAnnotationCfi {
  ExternalAnnotationCfi(
    String xhtml, {
    this.isInline,
    this.hasInlineDecoration,
  }) {
    try {
      final document = XmlDocument.parse(
        xhtml,
        entityMapping: cfiEntityMapping,
      );
      _body = document.descendants.whereType<XmlElement>().firstWhere(
        (element) => element.name.local == 'body',
      );
    } on FormatException {
      final body = html_parser.parse(xhtml).body;
      if (body == null) throw const FormatException('XHTML 缺少 body');
      _body = _xmlNode(body) as XmlElement;
    }
  }

  static XmlNode _xmlNode(html.Node node) => switch (node) {
    html.Element() => XmlElement(XmlName.parts(node.localName!), [
      for (final entry in node.attributes.entries)
        XmlAttribute(XmlName.parts('${entry.key}'), entry.value),
    ], node.nodes.map(_xmlNode)),
    html.Text() => XmlText(node.data),
    html.Comment() => XmlComment(node.data ?? ''),
    _ => XmlText(''),
  };

  late final XmlElement _body;
  final bool Function(String cfi)? isInline;
  final bool Function(String cfi)? hasInlineDecoration;

  String? toLocal(String value) => _convert(value, incoming: true);

  /// 原端点所在的 DOM 容器，供引用核验限定搜索范围。
  String? localScope(String value) =>
      _convert(value, incoming: true, scope: true);

  String? toExternal(String value) => _convert(value, incoming: false);

  String? _convert(String value, {required bool incoming, bool scope = false}) {
    final candidates = epubCfiCandidates(value);
    if (candidates.isEmpty) return null;
    final point = EpubCfi.parse(candidates.first);
    if (point == null || point.isRange || point.segments.length != 2) {
      return null;
    }
    final segment = point.segments.last;
    final steps = segment.steps;
    if (steps.length < 2 || steps.first.index != 4 || segment.offset == null) {
      return null;
    }
    XmlElement parent = _body;
    final output = <CfiStep>[const CfiStep(4)];
    final path = steps.skip(1).toList();
    if (incoming) {
      if (path.length < 2 || path.last.index != 1) return null;
      path.removeLast();
    }
    for (var i = 0; i < path.length; i++) {
      final step = path[i];
      final children = xmlCfiChildren(parent).toList();
      XmlNode? node;
      CfiChild<XmlNode>? slot;
      if (incoming) {
        final index = step.index - 1;
        if (index < 0 || index >= parent.children.length) return null;
        node = parent.children[index];
        for (final child in children) {
          if (identical(child.element, node) ||
              child.characters.contains(node)) {
            slot = child;
            break;
          }
        }
      } else {
        for (final child in children) {
          if (child.index == step.index) {
            slot = child;
            break;
          }
        }
        node = slot?.element;
        if (node == null && slot != null && slot.characters.length == 1) {
          node = slot.characters.single;
        }
      }
      if (node == null || slot == null) return null;
      if (node is XmlElement) {
        output.add(
          incoming
              ? CfiStep(slot.index, assertion: node.getAttribute('id'))
              : CfiStep(parent.children.indexOf(node) + 1),
        );
        if (i == path.length - 1) {
          return scope
              ? EpubCfi([point.segments.first, CfiSegment(output)]).serialize()
              : null;
        }
        parent = node;
        continue;
      }
      if (i != path.length - 1 || node is! XmlText) return null;
      final raw = node.value;
      // 阅微 fe7 去掉文本节点两端空格和换行，再计算字符偏移。
      final leading =
          raw.length - raw.replaceFirst(RegExp(r'^[ \n]+'), '').length;
      final trimmed = raw.replaceAll(RegExp(r'^[ \n]+|[ \n]+$'), '');
      if (scope) {
        return EpubCfi([
          point.segments.first,
          CfiSegment([...output, CfiStep(slot.index)]),
        ]).serialize();
      }
      var offset = segment.offset!;
      if (incoming) {
        if (offset < 0 || offset > trimmed.length) return null;
        offset += leading;
        for (final previous in slot.characters) {
          if (identical(previous, node)) break;
          offset += previous.value?.length ?? 0;
        }
        output.add(CfiStep(slot.index));
      } else {
        offset -= leading;
        if (offset < 0 || offset > trimmed.length) return null;
        final grouped = _inlineEndpoint(
          point.segments.first,
          parent,
          node,
          offset,
        );
        if (grouped != null) return grouped;
        output.add(CfiStep(parent.children.indexOf(node) + 1));
        output.add(const CfiStep(1));
      }
      final converted = EpubCfi([
        point.segments.first,
        CfiSegment(output, offset: offset, side: segment.side),
      ]).serialize();
      return incoming ? converted : converted.replaceFirst('!', '');
    }
    return null;
  }

  String _elementCfi(CfiSegment package, XmlElement element) {
    final path = <CfiStep>[];
    XmlElement? current = element;
    while (current != null && !identical(current, _body)) {
      final parent = current.parentElement;
      if (parent == null) break;
      final slot = xmlCfiChildren(parent)
          .firstWhere((child) => identical(child.element, current));
      path.insert(
        0,
        CfiStep(slot.index, assertion: current.getAttribute('id')),
      );
      current = parent;
    }
    return EpubCfi([
      package,
      CfiSegment([const CfiStep(4), ...path]),
    ]).serialize();
  }

  String? _inlineEndpoint(
    CfiSegment package,
    XmlElement parent,
    XmlText target,
    int offset,
  ) {
    final inline = isInline;
    if (inline == null || !inline(_elementCfi(package, parent))) return null;
    var block = parent;
    while (inline(_elementCfi(package, block))) {
      final ancestor = block.parentElement;
      if (ancestor == null) return null;
      block = ancestor;
    }
    final group = block.children.firstWhere(
      (node) =>
          node is XmlElement ||
          (node is XmlText && node.value.trim().isNotEmpty),
    );
    var displayOffset = 0;
    int? targetOffset;
    void visit(XmlNode node) {
      if (targetOffset != null) return;
      if (node is XmlText) {
        if (identical(node, target)) {
          targetOffset = displayOffset + offset;
        } else {
          displayOffset += node.value
              .replaceAll(RegExp(r'^[ \n]+|[ \n]+$'), '')
              .length;
        }
      } else if (node is XmlElement) {
        final key = _elementCfi(package, node);
        if (!inline(key)) return;
        final decoration = hasInlineDecoration?.call(key) ?? false;
        if (decoration) displayOffset++;
        for (final child in node.children) {
          visit(child);
        }
        if (decoration) displayOffset++;
      }
    }

    for (final child in block.children) {
      visit(child);
    }
    if (targetOffset == null) return null;
    final path = <CfiStep>[];
    XmlNode? current = group;
    while (current != null && !identical(current, _body)) {
      final ancestor = current.parentElement;
      if (ancestor == null) return null;
      path.insert(0, CfiStep(ancestor.children.indexOf(current) + 1));
      current = ancestor;
    }
    return EpubCfi([
      package,
      CfiSegment([
        const CfiStep(4),
        ...path,
        const CfiStep(1),
      ], offset: targetOffset),
    ]).serialize().replaceFirst('!', '');
  }
}
