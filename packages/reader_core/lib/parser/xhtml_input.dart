import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml_events.dart' as xml;

import 'cfi_children.dart';
import 'html5_input.dart';

/// 待转换的正文树与原始 UTF-16 源范围，两条解析路径共用后续防护与转换。
class XhtmlInput {
  const XhtmlInput({
    required this.body,
    required this.htmlAttributes,
    required this.startOf,
    required this.endOf,
  });

  final dom.Element body;
  final Map<Object, String> htmlAttributes;
  final int Function(dom.Node) startOf;
  final int Function(dom.Node) endOf;
}

/// 严格 XHTML 按原 XML 结构转换，不插入 HTML5 的隐式元素。
XhtmlInput parseStrictXhtmlInput(String source) {
  final builder = _XmlInputBuilder();
  for (final event in xml.parseEvents(
    source,
    entityMapping: cfiEntityMapping,
    validateDocument: true,
    validateNesting: true,
    withNamespace: true,
    withLocation: true,
  )) {
    builder.add(event);
  }
  return builder.build();
}

/// 容错路径仍使用现有 HTML5 预处理和源范围映射。
XhtmlInput parseTolerantXhtmlInput(String source) {
  final prepared = prepareHtml5InputWithOffsets(source);
  final document = html_parser.parse(prepared.xhtml, generateSpans: true);
  final body = document.body;
  if (body == null) throw const FormatException('XHTML 缺少 body');
  int startOf(dom.Node node) =>
      prepared.originalOffset(node.sourceSpan?.start.offset ?? 0);
  return XhtmlInput(
    body: body,
    htmlAttributes: document.documentElement!.attributes,
    startOf: startOf,
    endOf: (node) =>
        prepared.originalOffset(node.sourceSpan?.end.offset ?? startOf(node)),
  );
}

class _XmlInputBuilder {
  final _parents = <dom.Element>[];
  final _ranges = Map<dom.Node, (int, int)>.identity();
  dom.Element? _html;
  dom.Element? _body;

  void add(xml.XmlEvent event) {
    final start = event.start ?? 0;
    final end = event.stop ?? start;
    switch (event) {
      case xml.XmlStartElementEvent():
        final name = event.name.split(':').last.toLowerCase();
        final element = dom.Element.tag(name);
        for (final attribute in event.attributes) {
          element.attributes[attribute.name] = attribute.value;
        }
        if (_parents.isNotEmpty) _parents.last.nodes.add(element);
        _ranges[element] = (start, end);
        if (name == 'html') _html ??= element;
        if (name == 'body') _body ??= element;
        if (!event.isSelfClosing) _parents.add(element);
      case xml.XmlEndElementEvent():
        _parents.removeLast();
      case xml.XmlTextEvent():
        _addText(event.value, start, end);
      case xml.XmlCDATAEvent():
        // 字符源范围沿用正文位置，不含 CDATA 的包围标记。
        _addText(event.value, start + 9, end - 3);
      default:
        // 注释与处理指令不创建字符节点，也不占 CFI 位置。
        break;
    }
  }

  void _addText(String value, int start, int end) {
    if (_parents.isEmpty || value.isEmpty) return;
    final text = dom.Text(value);
    _parents.last.nodes.add(text);
    _ranges[text] = (start, end);
  }

  XhtmlInput build() {
    final body = _body;
    if (body == null) throw const FormatException('XHTML 缺少 body');
    return XhtmlInput(
      body: body,
      htmlAttributes: _html?.attributes ?? const {},
      startOf: (node) => _ranges[node]?.$1 ?? 0,
      endOf: (node) => _ranges[node]?.$2 ?? 0,
    );
  }
}
