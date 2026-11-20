part of 'package_editor.dart';

typedef _RechapterPrepared = ({
  Map<String, Uint8List?>? writes,
  List<String> errors,
  Map<String, String> elementCfiMap,
});

class _RechapterOutput {
  _RechapterOutput(this.path, this.boundary, this.pieces);
  final String path;
  final ChapterBoundary boundary;
  final List<_RechapterPiece> pieces;
}

Future<_RechapterPrepared> _prepareRechapter(
  String source,
  _RechapterBook book,
  ChapterDetectionResult detection,
  ChapterDetectionOptions options,
) async {
  final session = await EpubEditSession.open(File(source));
  try {
    if (session.baseDigest != book.revision) {
      throw const EpubEditException('书籍版本已变化，请重新预览章节');
    }
    _checkRechapterStructure(book, session);
    _checkRechapterContainerStyles(book, detection.boundaries, session);
    final outputs = _rechapterOutputs(book, detection, session);
    final targets = _rechapterTargets(outputs);
    final writes = _rechapterWrites(book, outputs, targets, session, options);
    final elementCfiMap = _rechapterElementMap(outputs, writes);
    _applyRechapterWrites(session, writes);
    final editor = PackageEditor(session);
    editor.setToc(_rechapterToc(outputs));
    session.validate();
    return (
      writes: session.resourceOverrides,
      errors: const <String>[],
      elementCfiMap: elementCfiMap,
    );
  } on Exception catch (error) {
    return (
      writes: null,
      errors: ['无法安全重新分章：$error'],
      elementCfiMap: const <String, String>{},
    );
  } finally {
    session.close();
  }
}

Map<String, String> _rechapterElementMap(
  List<_RechapterOutput> outputs,
  Map<String, Uint8List?> writes,
) {
  final result = <String, String>{};
  final ambiguous = <String>{};
  for (var i = 0; i < outputs.length; i++) {
    final output = outputs[i];
    final doc = XmlDocument.parse(utf8.decode(writes[output.path]!));
    final body = _rechapterElement(doc, 'body');
    final next = _rechapterCfis(body, i);
    final cfiList = body.descendants
        .whereType<XmlElement>()
        .map((node) => next[node]!)
        .toList();
    var offset = 0;
    for (var part = 0; part < output.pieces.length; part++) {
      final piece = output.pieces[part];
      if (part > 0) offset += _elementIds(piece.root).length;
      for (final old in piece.oldCfis) {
        final current = cfiList[offset++];
        final previous = result[old];
        if (previous != null && previous != current) ambiguous.add(old);
        result[old] = current;
      }
    }
    if (offset != cfiList.length) throw const EpubEditException('节点迁移映射不完整');
  }
  result.removeWhere((key, _) => ambiguous.contains(key));
  return result;
}

void _checkRechapterStructure(_RechapterBook book, EpubEditSession session) {
  final editor = PackageEditor(session);
  final package = editor._package;
  final refs = editor._section(package, 'spine').childElements;
  if (refs.any(
    (ref) => ref.attributes.any(
      (attribute) =>
          attribute.name.local != 'idref' &&
          !(attribute.name.local == 'linear' && attribute.value == 'yes'),
    ),
  )) {
    throw const EpubEditException('阅读顺序含专用属性，不能安全重新分章');
  }
  final paths = book.documents.map((doc) => doc.path).toSet();
  for (final item
      in editor
          ._items(package)
          .where((item) => paths.contains(editor._itemPath(item)))) {
    if (item.attributes.any(
      (attribute) =>
          !const {'id', 'href', 'media-type'}.contains(attribute.name.local),
    )) {
      throw const EpubEditException('正文章节含专用清单属性，不能安全重新分章');
    }
  }
  if (book.documents.any(
    (doc) => doc.document.descendants.whereType<XmlElement>().any(
      (node) => const {'script', 'base'}.contains(node.name.local),
    ),
  )) {
    throw const EpubEditException('章节含脚本或专用基址，不能安全重新分章');
  }
}

List<_RechapterOutput> _rechapterOutputs(
  _RechapterBook book,
  ChapterDetectionResult detection,
  EpubEditSession session,
) {
  final outputs = <_RechapterOutput>[];
  final paths = session.resources.map((resource) => resource.path).toSet();
  for (var i = 0; i < detection.boundaries.length; i++) {
    final boundary = detection.boundaries[i];
    final start = i == 0 ? 0 : boundary.blockIndex;
    final end = i + 1 < detection.boundaries.length
        ? detection.boundaries[i + 1].blockIndex
        : book.blocks.length;
    final sources = book.documents.where(
      (doc) => doc.end > start && doc.start < end,
    );
    final pieces = [
      for (final doc in sources) _rechapterPiece(doc, start, end),
    ];
    if (pieces.isEmpty) throw const EpubEditException('章节没有可保留的正文节点');
    if (pieces.map((piece) => _rechapterContext(piece.source)).toSet().length >
        1) {
      throw EpubEditException('“${boundary.title}”跨越样式不同的章节，请保留原章节边界');
    }
    var path = p.posix.join(
      p.posix.dirname(session.opfPath),
      'Text/rechapter-${book.revision.substring(0, 12)}-${i + 1}.xhtml',
    );
    while (paths.contains(path)) {
      path = '${p.posix.withoutExtension(path)}-new.xhtml';
    }
    paths.add(path);
    outputs.add(_RechapterOutput(path, boundary, pieces));
  }
  return outputs;
}

typedef _RechapterTarget = ({String path, String fragment});

Map<(String, String), _RechapterTarget> _rechapterTargets(
  List<_RechapterOutput> outputs,
) {
  final result = <(String, String), _RechapterTarget>{};
  for (final output in outputs) {
    final ids = <String>{};
    for (final piece in output.pieces) {
      final old = piece.source.path;
      result.putIfAbsent((old, ''), () => (path: output.path, fragment: ''));
      for (final node in [
        piece.root,
        ...piece.root.descendants.whereType<XmlElement>(),
      ]) {
        for (final id in _elementIds(node)) {
          if (!ids.add(id)) throw EpubEditException('合并章节存在重复 ID：$id');
          result.putIfAbsent((
            old,
            id,
          ), () => (path: output.path, fragment: id));
        }
      }
      for (final id in _elementIds(piece.source.document.rootElement)) {
        result.putIfAbsent((old, id), () => (path: output.path, fragment: id));
      }
    }
  }
  return result;
}

Map<String, Uint8List?> _rechapterWrites(
  _RechapterBook book,
  List<_RechapterOutput> outputs,
  Map<(String, String), _RechapterTarget> targets,
  EpubEditSession session,
  ChapterDetectionOptions options,
) {
  final oldPaths = book.documents.map((doc) => doc.path).toSet();
  final writes = <String, Uint8List?>{for (final path in oldPaths) path: null};
  for (final output in outputs) {
    writes[output.path] = utf8.encode(_rechapterDocument(output, targets));
  }
  for (final resource in session.resources.where(_textResource)) {
    if (oldPaths.contains(resource.path) || resource.path == session.opfPath) {
      continue;
    }
    final original = session.readText(resource.path);
    final next = _rewriteDocument(
      resource.path,
      original,
      (href) =>
          _rechapterReference(resource.path, resource.path, href, targets),
    );
    if (original != next) writes[resource.path] = utf8.encode(next);
  }
  final package = _rechapterPackage(session, outputs, oldPaths, targets);
  writes[session.opfPath] = utf8.encode(package);
  writes[book.metadataPath] = utf8.encode(
    jsonEncode({...book.metadata, 'options': options.toJson()}),
  );
  return writes;
}

String _rechapterDocument(
  _RechapterOutput output,
  Map<(String, String), _RechapterTarget> targets,
) {
  final source = output.pieces.first.source;
  final document = source.document.copy();
  final body = _rechapterElement(document, 'body')..children.clear();
  body.attributes.clear();
  body.attributes.addAll(
    output.pieces.first.root.attributes.map((e) => e.copy()),
  );
  _rechapterElement(document, 'title').innerText = output.boundary.title;
  _rewriteElementReferences(
    document.rootElement,
    (href) => _rechapterReference(source.path, output.path, href, targets),
  );
  for (final piece in output.pieces) {
    final root = piece.root.copy();
    _rewriteElementReferences(
      root,
      (href) =>
          _rechapterReference(piece.source.path, output.path, href, targets),
    );
    if (!identical(piece, output.pieces.first)) {
      for (final id in _elementIds(root)) {
        body.children.add(
          _elementLike(body, 'span', [XmlAttribute(XmlName.parts('id'), id)]),
        );
      }
    }
    body.children.addAll(root.children.map((node) => node.copy()));
  }
  return document.toXmlString();
}

String _rechapterReference(
  String oldSource,
  String newSource,
  String href,
  Map<(String, String), _RechapterTarget> targets,
) {
  final uri = Uri.tryParse(href);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      href.startsWith('//')) {
    return href;
  }
  final (path, suffix) = resolveEditReference(oldSource, href);
  final target = targets[(path, Uri.decodeComponent(uri.fragment))];
  if (target == null) return relativeEditReference(newSource, path, suffix);
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return relativeEditReference(
    newSource,
    target.path,
    '$query${_fragment(target.fragment)}',
  );
}

String _rechapterPackage(
  EpubEditSession session,
  List<_RechapterOutput> outputs,
  Set<String> oldPaths,
  Map<(String, String), _RechapterTarget> targets,
) {
  final editor = PackageEditor(session);
  final package = editor._package;
  final manifest = editor._section(package, 'manifest');
  final removed = editor
      ._items(package)
      .where((item) => oldPaths.contains(editor._itemPath(item)))
      .toList();
  for (final item in removed) {
    editor._assertNoItemReferences(package, item);
  }
  final ids = removed.map((item) => item.getAttribute('id')).toSet();
  manifest.children.removeWhere(
    (node) => node is XmlElement && ids.contains(node.getAttribute('id')),
  );
  final spine = editor._section(package, 'spine')..children.clear();
  for (final output in outputs) {
    final id = editor._addManifest(
      package,
      output.path,
      'application/xhtml+xml',
    );
    spine.children.add(
      _elementLike(spine, 'itemref', [
        XmlAttribute(XmlName.parts('idref'), id),
      ]),
    );
  }
  _rewriteElementReferences(
    package.rootElement,
    (href) =>
        _rechapterReference(session.opfPath, session.opfPath, href, targets),
  );
  return package.toXmlString();
}

List<EditTocEntry> _rechapterToc(List<_RechapterOutput> outputs) {
  var insideVolume = false;
  return [
    for (final output in outputs)
      (() {
        if (output.boundary.isVolume) insideVolume = true;
        return EditTocEntry(
          output.boundary.title,
          output.path,
          depth: insideVolume && !output.boundary.isVolume ? 1 : 0,
        );
      })(),
  ];
}
