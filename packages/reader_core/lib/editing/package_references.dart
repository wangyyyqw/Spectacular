part of 'package_editor.dart';

/// 解析本地引用，保留查询与片段；网络地址不参与包内重命名。
(String, String) resolveEditReference(String source, String href) {
  final uri = Uri.parse(href);
  if (uri.hasScheme || uri.hasAuthority || href.startsWith('//')) {
    return (href, '');
  }
  final path = uri.path.isEmpty
      ? source
      : p.posix.normalize(
          p.posix.join(p.posix.dirname(source), Uri.decodeComponent(uri.path)),
        );
  return (
    path,
    '${uri.hasQuery ? '?${uri.query}' : ''}'
        '${uri.hasFragment ? '#${uri.fragment}' : ''}',
  );
}

String relativeEditReference(
  String source,
  String target, [
  String suffix = '',
]) {
  final relative = p.posix.relative(target, from: p.posix.dirname(source));
  return '${relative.split('/').map(Uri.encodeComponent).join('/')}$suffix';
}

extension PackageReferenceCommands on PackageEditor {
  void _assertNoItemReferences(XmlDocument doc, XmlElement item) {
    final id = item.getAttribute('id')!;
    for (final element in doc.descendants.whereType<XmlElement>()) {
      if (identical(element, item)) continue;
      if (element.name.local == 'meta' &&
          element.getAttribute('name') == 'cover' &&
          element.getAttribute('content') == id) {
        throw StateError('资源仍用作封面，请先设置其他封面');
      }
      for (final name in [
        'fallback',
        'fallback-style',
        'media-overlay',
        'toc',
      ]) {
        if (element.getAttribute(name) == id) {
          throw StateError('资源仍被 $name 引用，请先调整包结构');
        }
      }
      final refines = Uri.tryParse(element.getAttribute('refines') ?? '');
      if (refines != null &&
          refines.path.isEmpty &&
          Uri.decodeComponent(refines.fragment) == id) {
        throw StateError('资源仍有元数据细化引用，请先调整包结构');
      }
    }
  }

  void _assertNoPackagePathReferences(
    XmlDocument doc,
    XmlElement item,
    String path,
  ) {
    for (final element in doc.descendants.whereType<XmlElement>()) {
      if (identical(element, item)) continue;
      for (final attribute in element.attributes) {
        if ({'href', 'src', 'poster', 'data'}.contains(attribute.name.local) &&
            resolveEditReference(opfPath, attribute.value).$1 == path) {
          throw StateError('资源仍被包内 ${element.name.local} 引用');
        }
      }
    }
  }

  void _removeManifestAndSpine(XmlDocument doc, String id) {
    _section(doc, 'manifest').children.removeWhere(
      (node) => node is XmlElement && node.getAttribute('id') == id,
    );
    _section(doc, 'spine').children.removeWhere(
      (node) => node is XmlElement && node.getAttribute('idref') == id,
    );
  }

  List<String> referencesTo(String path) {
    final result = <String>[];
    for (final resource in session.resources.where(_textResource)) {
      var found = false;
      _rewriteDocument(resource.path, session.readText(resource.path), (href) {
        if (resolveEditReference(resource.path, href).$1 == path) found = true;
        return href;
      });
      if (found) result.add(resource.path);
    }
    return result;
  }

  Map<String, String> _rewrittenResources(Map<String, String> moves) {
    final result = <String, String>{};
    for (final resource in session.resources.where(_textResource)) {
      final text = session.readText(resource.path);
      final movedSource = moves[resource.path] ?? resource.path;
      final next = _rewriteDocument(resource.path, text, (href) {
        final uri = Uri.tryParse(href);
        if (uri == null || uri.hasScheme || uri.hasAuthority) return href;
        final (target, suffix) = resolveEditReference(resource.path, href);
        if (!moves.containsKey(target) && movedSource == resource.path) {
          return href;
        }
        return relativeEditReference(
          movedSource,
          moves[target] ?? target,
          suffix,
        );
      });
      if (next != text) result[resource.path] = next;
    }
    return result;
  }
}

bool _textResource(EpubEditResource resource) =>
    resource.mediaType == 'text/css' ||
    resource.mediaType.contains('xml') ||
    resource.path.endsWith('.opf') ||
    resource.path.endsWith('.ncx');

String _rewriteDocument(
  String path,
  String text,
  String Function(String) rewrite,
) {
  if (path.toLowerCase().endsWith('.css')) return _rewriteCss(text, rewrite);
  final document = XmlDocument.parse(text);
  final changed = _rewriteElementReferences(document.rootElement, rewrite);
  return changed ? document.toXmlString() : text;
}

bool _rewriteElementReferences(
  XmlElement root,
  String Function(String) rewrite,
) {
  var changed = false;
  for (final element in [root, ...root.descendants.whereType<XmlElement>()]) {
    for (final attribute in element.attributes) {
      final before = attribute.value;
      final after = switch (attribute.name.local) {
        'href' || 'src' || 'poster' || 'data' || 'URI' => rewrite(before),
        'style' => _rewriteCss(before, rewrite),
        'srcset' => _rewriteSrcset(before, rewrite),
        _ => before,
      };
      if (before != after) {
        attribute.value = after;
        changed = true;
      }
    }
    if (element.name.local == 'style') {
      final next = _rewriteCss(element.innerText, rewrite);
      if (next != element.innerText) {
        element.children.replaceRange(0, element.children.length, [
          XmlText(next),
        ]);
        changed = true;
      }
    }
  }
  return changed;
}

String _rewriteSrcset(String value, String Function(String) rewrite) {
  // data URI 内含逗号，不能按候选分隔符改写。
  if (value.contains('data:')) return value;
  return value
      .split(',')
      .map((candidate) {
        final match = RegExp(r'^(\s*)(\S+)(.*)$').firstMatch(candidate);
        return match == null
            ? candidate
            : '${match[1]}${rewrite(match[2]!)}${match[3]}';
      })
      .join(',');
}

final _cssReference = RegExp(
  r'''/\*[\s\S]*?\*/|url\(\s*(?:"([^"]*)"|'([^']*)'|([^\s)]*))\s*\)|@import\s+(?:"([^"]*)"|'([^']*)')''',
  caseSensitive: false,
);

String _rewriteCss(String text, String Function(String) rewrite) =>
    text.replaceAllMapped(_cssReference, (match) {
      if (match[0]!.startsWith('/*')) return match[0]!;
      for (var group = 1; group <= 5; group++) {
        final value = match[group];
        if (value == null) continue;
        final updated = rewrite(value);
        if (updated == value) return match[0]!;
        final offset = match[0]!.indexOf(
          value,
          match[0]!.startsWith('@') ? 7 : 4,
        );
        return match[0]!.replaceRange(offset, offset + value.length, updated);
      }
      return match[0]!;
    });
