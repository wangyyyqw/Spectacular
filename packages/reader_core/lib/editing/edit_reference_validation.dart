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
    for (final path in changedPaths) {
      final after = readAfter(path);
      if (after == null || !_referenceDocument(path)) continue;
      final previous = _originalReferences(path);
      for (final ref in _references(path, _decode(after))) {
        final failure = _failure(ref);
        if (failure == null) continue;
        if (previous.contains(ref) && _failure(ref, original: true) != null) {
          warnings.add('保留原有引用问题：$path → $failure');
        } else {
          throw EpubEditException('新增引用无效：$path → $failure');
        }
      }
    }
    return warnings;
  }

  Set<_Reference> _originalReferences(String path) {
    final bytes = readBefore(path);
    if (bytes == null) return {};
    try {
      return _references(path, _decode(bytes));
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
        final document = XmlDocument.parse(_decode(bytes));
        return {
          for (final node in document.descendants.whereType<XmlElement>())
            for (final attribute in node.attributes)
              if (attribute.name.qualified == 'id' ||
                  attribute.name.qualified == 'xml:id')
                attribute.value,
        };
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

Set<_Reference> _references(String path, String source) {
  final base = Uri(path: path);
  if (p.posix.extension(path).toLowerCase() == '.css') {
    return _cssReferences(source, base);
  }
  final document = XmlDocument.parse(source);
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
