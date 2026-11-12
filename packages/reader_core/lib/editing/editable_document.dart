import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xml/xml_events.dart';

/// 精确源码定位失败时拒绝写入，不使用阅读器的容错位置。
class EpubEditException implements Exception {
  const EpubEditException(this.message);
  final String message;
  @override
  String toString() => message;
}

String editDigest(String source) =>
    sha256.convert(utf8.encode(source)).toString();

String escapeXmlText(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String escapeXmlAttribute(String text) =>
    escapeXmlText(text).replaceAll('"', '&quot;');

/// XML 事件提供原始 UTF-16 区间；不经过容错 HTML 树或重新序列化。
class EditableDocument {
  EditableDocument._(this.source, this.path, this.revision, this.sourceDigest);

  factory EditableDocument.parse(
    String source, {
    String path = '',
    int revision = 0,
  }) {
    final result = EditableDocument._(
      source,
      path,
      revision,
      editDigest(source),
    );
    final stack = <EditableElementRef>[];
    try {
      for (final event in parseEvents(
        source,
        validateNesting: true,
        validateNamespace: true,
        validateDocument: true,
        withLocation: true,
      )) {
        result._accept(event, stack);
      }
    } catch (error) {
      throw EpubEditException('文档不是可精确编辑的 XML：$error');
    }
    if (stack.isNotEmpty || result._elements.isEmpty) {
      throw const EpubEditException('XML 元素未闭合');
    }
    return result;
  }

  final String source;
  final String path;
  final int revision;
  final String sourceDigest;
  final _elements = <EditableElementRef>[];
  List<EditableElementRef> get elements => List.unmodifiable(_elements);

  void _accept(XmlEvent event, List<EditableElementRef> stack) {
    if (event is XmlStartElementEvent) {
      final node = EditableElementRef._(this, event, stack.lastOrNull);
      node.parent?._children.add(node);
      _elements.add(node);
      if (event.isSelfClosing) {
        node._close(event.stop!, event.stop!);
      } else {
        stack.add(node);
      }
    } else if (event is XmlEndElementEvent) {
      stack.removeLast()._close(event.start!, event.stop!);
    }
  }

  EditableElementRef? elementAtOffset(int offset) => _elements
      .where((node) => node.start <= offset && offset < node.end)
      .lastOrNull;
}

/// 只读编辑目标，绑定路径和原文摘要；任何写入前必须重新核对摘要。
class EditableElementRef {
  EditableElementRef._(this.document, XmlStartElementEvent event, this.parent)
    : qualifiedName = event.name,
      attributes = Map.unmodifiable({
        for (final attribute in event.attributes)
          attribute.name: attribute.value,
      }),
      start = event.start!,
      openEnd = event.stop!,
      selfClosing = event.isSelfClosing;

  final EditableDocument document;
  final String qualifiedName;
  final Map<String, String> attributes;
  final EditableElementRef? parent;
  final int start;
  final int openEnd;
  final bool selfClosing;
  late final int closeStart;
  late final int end;
  final _children = <EditableElementRef>[];

  void _close(int close, int stop) {
    closeStart = close;
    end = stop;
  }

  String get path => document.path;
  int get revision => document.revision;
  String get sourceDigest => document.sourceDigest;
  String get tag => qualifiedName.split(':').last;
  int get sourceStart => start;
  int get sourceEnd => end;
  Set<String> get classes => (attributes['class'] ?? '')
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty)
      .toSet();
  List<EditableElementRef> get children => List.unmodifiable(_children);
  List<EditableElementRef> get ancestors => [
    if (parent case final owner?) ...owner.ancestors,
    ?parent,
  ];
  String get outerXml => document.source.substring(start, end);
  String get innerXml =>
      selfClosing ? '' : document.source.substring(openEnd, closeStart);
  String get text => [
    for (final event in parseEvents(innerXml, validateNesting: true))
      if (event is XmlTextEvent)
        event.value
      else if (event is XmlCDATAEvent)
        event.value,
  ].join();

  /// 返回整份新源码；仅替换目标属性，不重排其他属性与引号。
  String replaceAttribute(String name, String? value) {
    if (!RegExp(r'^[A-Za-z_:][A-Za-z0-9_.:-]*$').hasMatch(name)) {
      throw const EpubEditException('属性名无效');
    }
    final opening = document.source.substring(start, openEnd);
    final pattern = RegExp(
      r'''\s+([^\s=<>/]+)\s*=\s*(["'])(.*?)\2''',
      dotAll: true,
    );
    final match = pattern
        .allMatches(opening)
        .where((item) => item.group(1) == name)
        .firstOrNull;
    final replacement = value == null
        ? ''
        : ' $name="${escapeXmlAttribute(value)}"';
    final insertion = opening.lastIndexOf(selfClosing ? '/>' : '>');
    final next = match == null
        ? opening.replaceRange(insertion, insertion, replacement)
        : opening.replaceRange(match.start, match.end, replacement);
    return document.source.replaceRange(start, openEnd, next);
  }

  String replaceInner(String html) {
    if (!selfClosing) {
      return document.source.replaceRange(openEnd, closeStart, html);
    }
    final opening = document.source
        .substring(start, openEnd)
        .replaceFirst(RegExp(r'/\s*>$'), '>');
    return document.source.replaceRange(
      start,
      end,
      '$opening$html</$qualifiedName>',
    );
  }
}
