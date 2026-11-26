import 'package:xml/xml_events.dart';

import '../epub/footnote.dart';
import 'editable_document.dart';
import 'epub_edit_session.dart';
import 'package_editor.dart';

/// 已有注释保留作者 HTML、容器属性和返回正文的链接。
class EpubEditableNote {
  const EpubEditableNote({required this.definition, this.reference});

  final EditableElementRef definition;
  final EditableElementRef? reference;
  String get bodyHtml => definition.innerXml;
  String get label => reference?.text ?? '';
}

/// 只有文字边界允许插入链接；标签、实体和 CDATA 内部回退到元素末尾。
class EpubNoteInsertion {
  const EpubNoteInsertion(this.element, this.offset, this.atCursor);

  final EditableElementRef element;
  final int offset;
  final bool atCursor;
}

/// 在原 XHTML 上局部写入标准脚注，不转换书籍的其他注释格式。
class EpubNoteEditor {
  const EpubNoteEditor(this.session);

  final EpubEditSession session;
  static const _namespaces =
      'xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops"';

  EpubEditableNote? read(EditableElementRef target) {
    session.checkElement(target);
    final chain = [target, ...target.ancestors.reversed];
    final definition = chain.where(_isDefinition).firstOrNull;
    if (definition != null) {
      return EpubEditableNote(
        definition: definition,
        reference: _referenceFor(definition),
      );
    }
    final reference = chain.where((element) => element.tag == 'a').firstOrNull;
    if (reference == null || _isBacklink(reference)) return null;
    final linked = _linkedElement(reference);
    if (linked != null && _isDefinition(linked)) {
      return EpubEditableNote(definition: linked, reference: reference);
    }
    if (_hasType(reference, 'noteref') || _hasRole(reference, 'doc-noteref')) {
      throw const EpubEditException('未找到此标记对应的标准脚注，请先检查链接目标');
    }
    return null;
  }

  EpubNoteInsertion insertion(EditableElementRef target, {int? sourceOffset}) {
    session.checkElement(target);
    if (target.tag != 'body' &&
        !target.ancestors.any((element) => element.tag == 'body')) {
      throw const EpubEditException('请在正文元素中添加注释');
    }
    final anchor = [
      target,
      ...target.ancestors.reversed,
    ].where((element) => element.tag == 'a').firstOrNull;
    if (anchor != null) return EpubNoteInsertion(anchor, anchor.end, false);
    if (sourceOffset != null) {
      final container = _textContainer(target, sourceOffset);
      if (container != null) {
        return EpubNoteInsertion(container, sourceOffset, true);
      }
    }
    return EpubNoteInsertion(
      target,
      target.selfClosing ? target.end : target.closeStart,
      false,
    );
  }

  void create(
    EditableElementRef target, {
    required String label,
    required String text,
    int? sourceOffset,
  }) {
    if (label.trim().isEmpty || text.trim().isEmpty) {
      throw const EpubEditException('请填写注释标记和注释内容');
    }
    if (read(target) != null) {
      throw const EpubEditException('此处已有注释，请编辑现有注释');
    }
    final point = insertion(target, sourceOffset: sourceOffset);
    final body = target.document.elements.firstWhere(
      (node) => node.tag == 'body',
    );
    final (noteId, referenceId) = _ids(target.document);
    final reference =
        '<a $_namespaces epub:type="noteref" role="doc-noteref" '
        'id="$referenceId" href="#$noteId">${escapeXmlText(label.trim())}</a>';
    final content = escapeXmlText(text.trim()).replaceAll('\n', '<br/>');
    final definition =
        '\n<aside $_namespaces epub:type="footnote" '
        'role="doc-footnote" id="$noteId"><p>$content</p>'
        '<a epub:type="backlink" role="doc-backlink" '
        'href="#$referenceId">返回正文</a></aside>\n';
    final source = body.selfClosing
        ? body.replaceInner('<p>$reference</p>$definition')
        : _insert(target.document.source, point, body, reference, definition);
    session.transaction('添加脚注', (tx) => tx.writeText(target.path, source));
  }

  void update(EpubEditableNote note, {required String bodyHtml}) {
    session.checkElement(note.definition);
    if (note.reference case final reference?) session.checkElement(reference);
    if (bodyHtml.trim().isEmpty) {
      throw const EpubEditException('注释内容不能为空');
    }
    final source = note.definition.replaceInner(bodyHtml);
    final document = EditableDocument.parse(source, path: note.definition.path);
    final updated = document.elementAtOffset(note.definition.start)!;
    final previousLinks = _backlinks(note.definition);
    final nextLinks = _backlinks(updated);
    if (previousLinks.length != nextLinks.length ||
        previousLinks.any((link) => !nextLinks.remove(link))) {
      throw const EpubEditException('请保留原有返回正文的链接及其属性');
    }
    session.transaction(
      '修改脚注',
      (tx) => tx.writeText(note.definition.path, source),
    );
  }

  EditableElementRef? _linkedElement(EditableElementRef reference) {
    final href = reference.attributes['href'] ?? '';
    final uri = Uri.tryParse(href);
    if (uri == null || uri.hasScheme || uri.hasAuthority || !uri.hasFragment) {
      return null;
    }
    final (path, _) = resolveEditReference(reference.path, href);
    if (session.readBytes(path) == null) return null;
    return session
        .editableDocument(path)
        .elements
        .where((node) => node.attributes['id'] == uri.fragment)
        .firstOrNull;
  }

  EditableElementRef? _referenceFor(EditableElementRef definition) {
    for (final child in definition.document.elements) {
      if (child.start > definition.start &&
          child.end <= definition.end &&
          _isBacklink(child)) {
        final target = _linkedElement(child);
        if (target?.tag == 'a') return target;
      }
    }
    return definition.document.elements.where((node) {
      if (node.tag != 'a' || _isBacklink(node)) return false;
      final href = node.attributes['href'] ?? '';
      final uri = Uri.tryParse(href);
      if (uri == null || uri.hasScheme || !uri.hasFragment) return false;
      final (path, _) = resolveEditReference(node.path, href);
      return path == definition.path &&
          uri.fragment == definition.attributes['id'];
    }).firstOrNull;
  }

  static bool _isDefinition(EditableElementRef node) =>
      const [
        'footnote',
        'endnote',
        'rearnote',
      ].any((type) => _hasType(node, type)) ||
      const ['doc-footnote', 'doc-endnote'].any((role) => _hasRole(node, role));

  static bool _hasType(EditableElementRef node, String value) =>
      (node.attributes['epub:type'] ?? '')
          .split(RegExp(r'\s+'))
          .contains(value);

  static bool _hasRole(EditableElementRef node, String value) =>
      (node.attributes['role'] ?? '').split(RegExp(r'\s+')).contains(value);

  static bool _isBacklink(EditableElementRef node) =>
      FootnoteParser.isBacklink(node.tag, node.attributes);

  static List<String> _backlinks(EditableElementRef node) => [
    for (final child in node.document.elements)
      if (child.start > node.start &&
          child.end <= node.end &&
          _isBacklink(child))
        child.outerXml,
  ];

  static (String, String) _ids(EditableDocument document) {
    final ids = {
      for (final node in document.elements) ...[
        node.attributes['id'],
        node.attributes['xml:id'],
      ],
    };
    var index = 1;
    while (ids.contains('note-$index') || ids.contains('noteref-$index')) {
      index++;
    }
    return ('note-$index', 'noteref-$index');
  }

  static EditableElementRef? _textContainer(
    EditableElementRef target,
    int offset,
  ) {
    if (offset < target.openEnd || offset > target.closeStart) return null;
    final source = target.document.source;
    if (offset < source.length && _lowSurrogate(source.codeUnitAt(offset))) {
      return null;
    }
    for (final event in parseEvents(source, withLocation: true)) {
      if (event is! XmlTextEvent ||
          offset < event.start! ||
          offset > event.stop!) {
        continue;
      }
      final text = source.substring(event.start!, event.stop!);
      final relative = offset - event.start!;
      if (RegExp(r'&[^;]+;')
          .allMatches(text)
          .any((entity) => entity.start < relative && relative < entity.end)) {
        return null;
      }
      final parent = target.document.elementAtOffset(event.start!);
      if (parent != null &&
          ![parent, ...parent.ancestors].any((element) => element.tag == 'a')) {
        return parent;
      }
      return null;
    }
    return null;
  }

  static bool _lowSurrogate(int code) => code >= 0xdc00 && code <= 0xdfff;

  static String _insert(
    String source,
    EpubNoteInsertion point,
    EditableElementRef body,
    String reference,
    String definition,
  ) {
    final marker = point.element.tag == 'body'
        ? '<p>$reference</p>'
        : reference;
    return source
        .replaceRange(body.closeStart, body.closeStart, definition)
        .replaceRange(point.offset, point.offset, marker);
  }
}
