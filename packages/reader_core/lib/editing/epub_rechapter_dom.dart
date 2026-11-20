part of 'package_editor.dart';

class _RechapterBook {
  _RechapterBook(this.revision, this.metadataPath, this.metadata);
  final String revision;
  final String metadataPath;
  final Map<String, dynamic> metadata;
  final List<_RechapterDocument> documents = [];
  final List<_RechapterBlock> blocks = [];
}

class _RechapterDocument {
  _RechapterDocument(this.path, this.document, this.start, this.spineIndex);
  final String path;
  final XmlDocument document;
  final int start;
  final int spineIndex;
  late int end;
  final Map<XmlNode, (int, int)> spans = {};
  XmlElement get body => _rechapterElement(document, 'body');
}

class _RechapterBlock {
  _RechapterBlock(this.text, this.candidate);
  final String text;
  final bool candidate;
}

Future<_RechapterBook> _readRechapterBook(String path) async {
  final session = await EpubEditSession.open(File(path));
  try {
    final editor = PackageEditor(session);
    final item = editor
        ._items(editor._package)
        .where((item) => item.getAttribute('id') == txtMetadataManifestId)
        .firstOrNull;
    if (item == null) throw const EpubEditException('只有 TXT 转入的书籍可以重新分章');
    final metadataPath = editor._itemPath(item);
    final data = jsonDecode(session.readText(metadataPath));
    if (data is! Map<String, dynamic> ||
        data['schema'] != 1 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch('${data['sourceDigest']}')) {
      throw const EpubEditException('TXT 来源信息无效，不能重新分章');
    }
    final book = _RechapterBook(session.baseDigest, metadataPath, data);
    for (final path in session.spinePaths) {
      final doc = _RechapterDocument(
        path,
        XmlDocument.parse(session.readText(path)),
        book.blocks.length,
        book.documents.length,
      );
      for (final node in doc.body.children) {
        _collectRechapterBlock(book, doc, node);
      }
      doc.end = book.blocks.length;
      book.documents.add(doc);
    }
    return book;
  } finally {
    session.close();
  }
}

void _collectRechapterBlock(
  _RechapterBook book,
  _RechapterDocument doc,
  XmlNode node,
) {
  final start = book.blocks.length;
  if (node is XmlElement && _canDescendRechapter(node)) {
    for (final child in node.children) {
      _collectRechapterBlock(book, doc, child);
    }
  } else {
    final text = switch (node) {
      XmlElement() => node.innerText,
      XmlText() => node.value,
      XmlCDATA() => node.value,
      _ => '',
    };
    book.blocks.add(_RechapterBlock(text, _rechapterCandidate(node)));
  }
  doc.spans[node] = (start, book.blocks.length);
}

bool _canDescendRechapter(XmlElement node) =>
    const {'div', 'section', 'article', 'main'}.contains(node.name.local) &&
    node.childElements.any(
      (child) => const {
        'div',
        'section',
        'article',
        'main',
        'p',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
        'table',
        'ul',
        'ol',
        'aside',
        'figure',
        'blockquote',
        'pre',
        'hr',
      }.contains(child.name.local),
    ) &&
    !_rechapterFootnote(node);

bool _rechapterFootnote(XmlElement node) => node.attributes.any(
  (attribute) =>
      const {'type', 'role'}.contains(attribute.name.local) &&
      attribute.value
          .split(RegExp(r'\s+'))
          .any(
            (value) => const {
              'footnote',
              'endnote',
              'rearnote',
              'doc-footnote',
              'doc-endnote',
            }.contains(value),
          ),
);

bool _rechapterCandidate(XmlNode node) {
  if (node is XmlText || node is XmlCDATA) {
    return node.innerText.trim().isNotEmpty;
  }
  if (node is! XmlElement || _rechapterFootnote(node)) return false;
  if (!const {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'div',
    'section',
  }.contains(node.name.local)) {
    return false;
  }
  return !node.descendants.whereType<XmlElement>().any(
    (element) =>
        const {
          'table',
          'ul',
          'ol',
          'aside',
          'img',
          'svg',
          'audio',
          'video',
          'br',
        }.contains(element.name.local) ||
        _rechapterFootnote(element),
  );
}

XmlElement _rechapterElement(XmlNode doc, String name) => doc.descendants
    .whereType<XmlElement>()
    .firstWhere((element) => element.name.local == name);

/// 保留原容器外壳，切点只落在完整节点之前，不拆行内标签。
XmlNode? _sliceRechapterNode(
  _RechapterDocument doc,
  XmlNode node,
  int start,
  int end,
) {
  final span = doc.spans[node]!;
  if (span.$2 <= start || span.$1 >= end) return null;
  if (span.$1 >= start && span.$2 <= end) return node.copy();
  if (node is! XmlElement || !_canDescendRechapter(node)) {
    throw const EpubEditException('切点位于不能拆分的段落、表格或媒体内部');
  }
  final copy = node.copy()..children.clear();
  if (span.$1 < start) {
    copy.attributes.removeWhere((attribute) => attribute.name.local == 'id');
  }
  copy.children.addAll([
    for (final child in node.children)
      ?_sliceRechapterNode(doc, child, start, end),
  ]);
  return copy;
}

class _RechapterPiece {
  _RechapterPiece(this.source, this.root, this.oldCfis);
  final _RechapterDocument source;
  final XmlElement root;
  final List<String> oldCfis;
}

_RechapterPiece _rechapterPiece(_RechapterDocument doc, int start, int end) {
  final body = doc.body.copy()..children.clear();
  if (start > doc.start) {
    body.attributes.removeWhere((attribute) => attribute.name.local == 'id');
  }
  body.children.addAll([
    for (final child in doc.body.children)
      ?_sliceRechapterNode(doc, child, start, end),
  ]);
  final oldCfis = _rechapterCfis(doc.body, doc.spineIndex);
  final elements = doc.body.descendants.whereType<XmlElement>().where((node) {
    var current = node as XmlNode;
    while (!doc.spans.containsKey(current)) {
      current = current.parent!;
    }
    final span = doc.spans[current]!;
    return span.$2 > start && span.$1 < end;
  });
  return _RechapterPiece(doc, body, [
    for (final node in elements) oldCfis[node]!,
  ]);
}

Map<XmlElement, String> _rechapterCfis(XmlElement body, int spine) {
  final result = <XmlElement, String>{};
  void visit(XmlElement node, List<CfiStep> steps) {
    final builder = CfiBuilder().itemRef((spine + 1) * 2).body(4);
    for (final step in steps) {
      builder.step(step.index, assertion: step.assertion);
    }
    result[node] = builder.build().serialize();
    var index = 0;
    for (final child in node.childElements) {
      index += 2;
      final id = child.getAttribute('id');
      visit(child, [
        ...steps,
        CfiStep(index, assertion: id?.isEmpty == true ? null : id),
      ]);
    }
  }

  visit(body, const []);
  return result;
}

String _rechapterContext(_RechapterDocument source) {
  final root = source.document.rootElement.copy();
  final head = _rechapterElement(root, 'head');
  head.children.removeWhere(
    (node) =>
        node is XmlElement && node.name.local == 'title' ||
        node is XmlText && node.value.trim().isEmpty,
  );
  final body = _rechapterElement(root, 'body')..children.clear();
  body.attributes.removeWhere((attribute) => attribute.name.local == 'id');
  _rewriteElementReferences(root, (href) {
    final uri = Uri.tryParse(href);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return href;
    final resolved = resolveEditReference(source.path, href);
    return '${resolved.$1}${resolved.$2}';
  });
  return root.toXmlString();
}

/// 祖先按 ID 参与样式时复制外壳会改变选择器，必须保留原版。
void _checkRechapterContainerStyles(
  _RechapterBook book,
  List<ChapterBoundary> boundaries,
  EpubEditSession session,
) {
  final cuts = boundaries
      .skip(1)
      .map((boundary) => boundary.blockIndex)
      .toSet();
  final oldStarts = book.documents.map((doc) => doc.start).toSet();
  final newStarts = {0, ...cuts};
  final boundariesChanged =
      book.documents.length != boundaries.length ||
      oldStarts.length != newStarts.length ||
      !oldStarts.containsAll(newStarts);
  for (final doc in book.documents) {
    final css = _rechapterCss(doc, session);
    if (boundariesChanged) _checkRechapterPositionStyles(doc, css);
    final structuralIds = [
      ..._elementIds(doc.body),
      ..._elementIds(doc.document.rootElement),
    ];
    if (structuralIds.any((id) => css.contains('#$id'))) {
      throw EpubEditException('正文根元素 ID 参与样式，无法安全重新分章：${doc.path}');
    }
    for (final entry in doc.spans.entries) {
      final node = entry.key;
      if (node is! XmlElement ||
          !_canDescendRechapter(node) ||
          !cuts.any((cut) => cut > entry.value.$1 && cut < entry.value.$2)) {
        continue;
      }
      final ids = _elementIds(node);
      if (ids.any((id) => css.contains('#$id'))) {
        throw EpubEditException('容器 ID 参与样式，无法安全拆分：${doc.path}');
      }
    }
  }
}

void _checkRechapterPositionStyles(_RechapterDocument doc, String css) {
  for (final rule in CssParser.parse(css).rules) {
    if (SelectorParser.parse(rule.selector).selectors
        .any((selector) => selector.usesTreePosition)) {
      throw EpubEditException(
        '保守检查发现依赖节点顺序的 CSS，改变章节边界可能影响样式，请保留原章节边界：'
        '${doc.path}（${rule.selector}）',
      );
    }
    if (_rechapterUsesCounter(rule.declarations)) {
      throw EpubEditException(
        '保守检查发现 CSS 计数器，改变章节边界可能影响编号，请保留原章节边界：${doc.path}',
      );
    }
  }
  for (final node in doc.document.descendants.whereType<XmlElement>()) {
    final inline = node.getAttribute('style');
    if (inline != null &&
        _rechapterUsesCounter(CssParser.parseInlineDeclarations(inline))) {
      throw EpubEditException(
        '保守检查发现行内 CSS 计数器，改变章节边界可能影响编号，请保留原章节边界：${doc.path}',
      );
    }
  }
}

bool _rechapterUsesCounter(Iterable<CssDeclaration> declarations) =>
    declarations.any(
      (declaration) =>
          const {
            'counter-reset',
            'counter-increment',
            'counter-set',
          }.contains(declaration.property.toLowerCase()) ||
          RegExp(
            r'\bcounters?\s*\(',
            caseSensitive: false,
          ).hasMatch(declaration.value),
    );

String _rechapterCss(_RechapterDocument doc, EpubEditSession session) {
  final styles = StringBuffer();
  // 包括被 @import 间接引用的样式，避免仅检查 head 第一层漏过 ID 依赖。
  for (final resource in session.resources.where(
    (resource) =>
        resource.mediaType == 'text/css' || resource.path.endsWith('.css'),
  )) {
    styles.writeln(session.readText(resource.path));
  }
  for (final node in doc.document.descendants.whereType<XmlElement>()) {
    if (node.name.local == 'style') styles.writeln(node.innerText);
    if (node.name.local != 'link' || node.getAttribute('rel') != 'stylesheet') {
      continue;
    }
    final href = node.getAttribute('href');
    if (href == null) continue;
    final target = resolveEditReference(doc.path, href).$1;
    if (session.readBytes(target) != null) {
      styles.writeln(session.readText(target));
    }
  }
  return styles.toString();
}
