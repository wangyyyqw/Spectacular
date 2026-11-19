import 'dart:typed_data';

import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as ast;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'edit_text_encoding.dart';
import 'editable_document.dart';

typedef _Reference = ({String path, String fragment});

/// 只阻止本次新增的断链；原书既有断链保留为告警，不借编辑自动修书。
class EditReferenceValidator {
  EditReferenceValidator(
    this.readBefore,
    this.readAfter,
    this.availablePaths,
    this.originalPaths,
  );
  final Uint8List? Function(String) readBefore;
  final Uint8List? Function(String) readAfter;
  final Set<String> availablePaths;
  final Set<String> originalPaths;
  final _targetIds = <String, Set<String>>{};
  final _originalTargetIds = <String, Set<String>>{};

  List<String> validate(Iterable<String> changedPaths) {
    final warnings = <String>[];
    final affectedTargets = originalPaths.difference(availablePaths);
    final changed = changedPaths.toSet();
    for (final path in changed) {
      if (!_referenceDocument(path)) continue;
      final after = readAfter(path);
      if (after == null) continue;
      final previous = _originalReferences(path, collectIds: true);
      final current = _references(path, _decode(after), idsByPath: _targetIds);
      _checkLinks(path, current, previous, warnings);
      final ids = _targetIds[path];
      if (ids != null &&
          !ids.containsAll(_originalTargetIds[path] ?? const {})) {
        affectedTargets.add(path);
      }
    }
    if (affectedTargets.isNotEmpty) {
      for (final path in availablePaths) {
        if (changed.contains(path) || !_referenceDocument(path)) continue;
        final unchanged = _originalReferences(path);
        final incoming = unchanged.where(
          (ref) => affectedTargets.contains(ref.path),
        );
        _checkLinks(path, incoming, unchanged, warnings);
      }
    }
    return warnings;
  }

  void _checkLinks(
    String path,
    Iterable<_Reference> links,
    Set<_Reference> previous,
    List<String> warnings,
  ) {
    for (final ref in links) {
      final failure = _failure(ref);
      if (failure == null) continue;
      if (previous.contains(ref) && _failure(ref, original: true) != null) {
        warnings.add('保留原有引用问题：$path → $failure');
      } else {
        throw EpubEditException('新增引用无效：$path → $failure');
      }
    }
  }

  Set<_Reference> _originalReferences(String path, {bool collectIds = false}) {
    try {
      final bytes = readBefore(path);
      if (bytes == null) return {};
      return _references(
        path,
        _decode(bytes),
        idsByPath: collectIds ? _originalTargetIds : null,
      );
    } catch (_) {
      // 旧源码无法可靠解析时，不把未知引用当作已确认的历史问题。
      return {};
    }
  }

  String? _failure(_Reference ref, {bool original = false}) {
    final paths = original ? originalPaths : availablePaths;
    final read = original ? readBefore : readAfter;
    final cache = original ? _originalTargetIds : _targetIds;
    final label =
        '${ref.path}${ref.fragment.isEmpty ? '' : '#${ref.fragment}'}';
    if (!paths.contains(ref.path)) return '$label（资源不存在）';
    if (ref.fragment.isEmpty || !_xmlDocument(ref.path)) return null;
    try {
      final ids = cache.putIfAbsent(ref.path, () {
        final bytes = read(ref.path);
        if (bytes == null) return {};
        return _documentIds(XmlDocument.parse(_decode(bytes)));
      });
      return ids.contains(ref.fragment) ? null : '$label（片段不存在）';
    } catch (_) {
      return '$label（目标 XML 无法验证）';
    }
  }
}

bool _xmlDocument(String path) => const {
  '.xhtml',
  '.html',
  '.htm',
  '.xml',
  '.opf',
  '.ncx',
  '.svg',
}.contains(p.posix.extension(path).toLowerCase());

bool _referenceDocument(String path) =>
    _xmlDocument(path) || p.posix.extension(path).toLowerCase() == '.css';

String _decode(Uint8List bytes) => EditTextEncoding.detect(bytes).decode(bytes);

Set<String> _documentIds(XmlDocument document) => {
  for (final node in document.descendants.whereType<XmlElement>())
    for (final attribute in node.attributes)
      if (attribute.name.qualified == 'id' ||
          attribute.name.qualified == 'xml:id')
        attribute.value,
};

Set<_Reference> _references(
  String path,
  String source, {
  Map<String, Set<String>>? idsByPath,
}) {
  final base = Uri(path: path);
  if (p.posix.extension(path).toLowerCase() == '.css') {
    return _cssReferences(source, base);
  }
  final document = XmlDocument.parse(source);
  if (idsByPath != null) idsByPath[path] = _documentIds(document);
  final htmlBase = document.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'base')
      .firstOrNull
      ?.getAttribute('href');
  final documentBase = htmlBase == null ? base : base.resolve(htmlBase);
  return {
    for (final element in document.descendants.whereType<XmlElement>())
      ..._elementReferences(element, documentBase),
  };
}

Set<_Reference> _elementReferences(XmlElement element, Uri documentBase) {
  var base = documentBase;
  for (final node in [
    ...element.ancestors.whereType<XmlElement>().toList().reversed,
    element,
  ]) {
    final xmlBase = node.getAttribute('xml:base');
    if (xmlBase != null) base = base.resolve(xmlBase);
  }
  final references = <_Reference>{};
  for (final attribute in element.attributes) {
    if (const {
      'href',
      'src',
      'poster',
      'data',
      'URI',
    }.contains(attribute.name.local)) {
      if (element.name.local == 'base') continue;
      final ref = _resolve(base, attribute.value);
      if (ref != null) references.add(ref);
    } else if (attribute.name.local == 'style') {
      references.addAll(_cssReferences('x{${attribute.value}}', base));
    }
  }
  if (element.name.local == 'style') {
    references.addAll(_cssReferences(element.innerText, base));
  }
  return references;
}

_Reference? _resolve(Uri base, String href) {
  if (href.trim().isEmpty) return null;
  final uri = base.resolve(href.trim());
  if (uri.hasScheme || uri.hasAuthority) return null;
  return (
    path: p.posix.normalize(Uri.decodeComponent(uri.path)),
    fragment: Uri.decodeComponent(uri.fragment),
  );
}

Set<_Reference> _cssReferences(String source, Uri base) {
  final visitor = _CssReferences(base);
  css.parse(source).visit(visitor);
  return visitor.references;
}

class _CssReferences extends ast.Visitor {
  _CssReferences(this.base);
  final Uri base;
  final references = <_Reference>{};

  void _add(String value) {
    final ref = _resolve(base, value);
    if (ref != null) references.add(ref);
  }

  @override
  void visitUriTerm(ast.UriTerm node) => _add(node.text);

  @override
  void visitImportDirective(ast.ImportDirective node) => _add(node.import);
}
