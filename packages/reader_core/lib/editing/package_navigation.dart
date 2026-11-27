part of 'package_editor.dart';

class EditTocEntry {
  const EditTocEntry(this.label, this.path, {this.fragment, this.depth = 0});
  final String label;
  final String path;
  final String? fragment;
  final int depth;
}

extension PackageNavigationCommands on PackageEditor {
  List<EditTocEntry> get toc {
    final doc = _package;
    final nav = _items(doc)
        .where(
          (e) => (e.getAttribute('properties') ?? '')
              .split(RegExp(r'\s+'))
              .contains('nav'),
        )
        .firstOrNull;
    final ncx = _items(doc)
        .where(
          (e) => e.getAttribute('media-type') == 'application/x-dtbncx+xml',
        )
        .firstOrNull;
    final item = nav ?? ncx;
    if (item == null) return [];
    final path = _itemPath(item);
    final tree = XmlDocument.parse(session.readText(path));
    final root = nav == null
        ? _section(tree, 'navMap')
        : tree.descendants.whereType<XmlElement>().firstWhere(
            (e) =>
                e.name.local == 'nav' &&
                e.attributes.any(
                  (a) =>
                      a.name.local == 'type' &&
                      a.value.split(' ').contains('toc'),
                ),
          );
    final result = <EditTocEntry>[];
    _readToc(root, path, nav != null, 0, result);
    return result;
  }

  void setToc(List<EditTocEntry> entries) {
    _checkToc(entries);
    final doc = _package;
    final texts = _tocDocuments(doc, entries);
    session.transaction('修改目录', (tx) {
      for (final entry in texts.entries) {
        tx.writeText(entry.key, entry.value);
      }
      tx.writeText(opfPath, doc.toXmlString());
    });
  }

  void generateToc() {
    final entries = <EditTocEntry>[];
    final changed = <String, String>{};
    for (final chapter in chapters) {
      final doc = XmlDocument.parse(session.readText(chapter.path));
      final ids = doc.descendants
          .whereType<XmlElement>()
          .expand(_elementIds)
          .toSet();
      var sequence = 1;
      for (final heading in doc.descendants.whereType<XmlElement>().where(
        (e) => RegExp(r'^h[1-6]$').hasMatch(e.name.local),
      )) {
        var id = _elementIds(heading).firstOrNull;
        if (id == null || id.isEmpty) {
          while (ids.contains('heading-$sequence')) {
            sequence++;
          }
          id = 'heading-$sequence';
          ids.add(id);
          heading.setAttribute('id', id);
        }
        entries.add(
          EditTocEntry(heading.innerText.trim(), chapter.path, fragment: id),
        );
      }
      changed[chapter.path] = doc.toXmlString();
    }
    if (entries.isEmpty) throw StateError('正文没有标题，请手动编辑目录');
    final doc = _package;
    changed.addAll(_tocDocuments(doc, entries));
    session.transaction('从标题生成目录', (tx) {
      for (final entry in changed.entries) {
        tx.writeText(entry.key, entry.value);
      }
      tx.writeText(opfPath, doc.toXmlString());
    });
  }

  void _checkToc(List<EditTocEntry> entries) {
    var previous = -1;
    for (final entry in entries) {
      if (entry.depth < 0 || entry.depth > previous + 1) {
        throw ArgumentError('目录层级不能跳级');
      }
      if (entry.label.trim().isEmpty ||
          !session.resources.any((r) => r.path == entry.path)) {
        throw ArgumentError('目录标题或目标无效');
      }
      if (entry.fragment case final fragment? when fragment.isNotEmpty) {
        final doc = XmlDocument.parse(session.readText(entry.path));
        if (!doc.descendants.whereType<XmlElement>().any(
          (e) => _elementIds(e).contains(fragment),
        )) {
          throw ArgumentError('目录目标 ID 不存在：$fragment');
        }
      }
      previous = entry.depth;
    }
  }

  Map<String, String> _tocDocuments(
    XmlDocument doc,
    List<EditTocEntry> entries,
  ) {
    final result = <String, String>{};
    final nav = _items(doc)
        .where(
          (e) => (e.getAttribute('properties') ?? '')
              .split(RegExp(r'\s+'))
              .contains('nav'),
        )
        .firstOrNull;
    final ncx = _items(doc)
        .where(
          (e) => e.getAttribute('media-type') == 'application/x-dtbncx+xml',
        )
        .firstOrNull;
    if (nav != null) result[_itemPath(nav)] = _navText(_itemPath(nav), entries);
    if (ncx != null) result[_itemPath(ncx)] = _ncxText(_itemPath(ncx), entries);
    if (nav == null && ncx == null) {
      final epub3 = (doc.rootElement.getAttribute('version') ?? '').startsWith(
        '3',
      );
      var path = p.posix.join(
        p.posix.dirname(opfPath),
        epub3 ? 'edit-nav.xhtml' : 'edit-toc.ncx',
      );
      var suffix = 1;
      while (session.resources.any((r) => r.path == path)) {
        path = p.posix.join(
          p.posix.dirname(opfPath),
          'edit-nav-${suffix++}.${epub3 ? 'xhtml' : 'ncx'}',
        );
      }
      final id = _addManifest(
        doc,
        path,
        epub3 ? 'application/xhtml+xml' : 'application/x-dtbncx+xml',
      );
      final item = _items(doc).firstWhere((e) => e.getAttribute('id') == id);
      if (epub3) {
        item.setAttribute('properties', 'nav');
      } else {
        _section(doc, 'spine').setAttribute('toc', id);
      }
      result[path] = epub3 ? _navText(path, entries) : _ncxText(path, entries);
    }
    return result;
  }

  String _navText(String path, List<EditTocEntry> entries) {
    final existing = session.resources.any((r) => r.path == path);
    final doc = XmlDocument.parse(
      existing
          ? session.readText(path)
          : '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
                '<head><title>目录</title></head><body><nav epub:type="toc"><h1>目录</h1></nav></body></html>',
    );
    final nav = doc.descendants.whereType<XmlElement>().firstWhere(
      (e) =>
          e.name.local == 'nav' &&
          e.attributes.any(
            (a) => a.name.local == 'type' && a.value.split(' ').contains('toc'),
          ),
    );
    nav.children.removeWhere((e) => e is XmlElement && e.name.local == 'ol');
    final root = _elementLike(nav, 'ol');
    final lists = <XmlElement>[root];
    for (final entry in entries) {
      while (lists.length > entry.depth + 1) {
        lists.removeLast();
      }
      if (lists.length <= entry.depth) {
        final list = _elementLike(nav, 'ol');
        lists.last.childElements.last.children.add(list);
        lists.add(list);
      }
      lists.last.children.add(
        _elementLike(nav, 'li', [], [
          _elementLike(
            nav,
            'a',
            [
              XmlAttribute(
                XmlName.parts('href'),
                relativeEditReference(
                  path,
                  entry.path,
                  _fragment(entry.fragment),
                ),
              ),
            ],
            [XmlText(entry.label)],
          ),
        ]),
      );
    }
    nav.children.add(root);
    return doc.toXmlString();
  }

  String _ncxText(String path, List<EditTocEntry> entries) {
    final existing = session.resources.any((r) => r.path == path);
    final doc = XmlDocument.parse(
      existing
          ? session.readText(path)
          : '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
                '<head/><docTitle><text/></docTitle><navMap/></ncx>',
    );
    final root = _section(doc, 'navMap');
    root.children.clear();
    final parents = <XmlElement>[root];
    var count = 0;
    for (final entry in entries) {
      while (parents.length > entry.depth + 1) {
        parents.removeLast();
      }
      if (parents.length <= entry.depth) {
        parents.add(parents.last.childElements.last);
      }
      final point = _elementLike(
        root,
        'navPoint',
        [
          XmlAttribute(XmlName.parts('id'), 'edit-toc-${++count}'),
          XmlAttribute(XmlName.parts('playOrder'), '$count'),
        ],
        [
          _elementLike(root, 'navLabel', [], [
            _elementLike(root, 'text', [], [XmlText(entry.label)]),
          ]),
          _elementLike(root, 'content', [
            XmlAttribute(
              XmlName.parts('src'),
              relativeEditReference(
                path,
                entry.path,
                _fragment(entry.fragment),
              ),
            ),
          ]),
        ],
      );
      parents.last.children.add(point);
    }
    return doc.toXmlString();
  }

  /// 分章点必须处于 body 的完整子节点之间，不能截断行内结构。
  void splitChapter(String path, int sourceOffset, String newPath) {
    _requireNewPath(newPath);
    final split = _splitSource(path, sourceOffset);
    final rebased = _rewriteDocument(path, split.after, (href) {
      final uri = Uri.tryParse(href);
      if (uri == null || uri.hasScheme || uri.hasAuthority) return href;
      final (target, suffix) = resolveEditReference(path, href);
      return relativeEditReference(newPath, target, suffix);
    });
    final doc = _package;
    _insertSplitChapter(doc, path, newPath);
    session.transaction('拆分章节', (tx) {
      tx.writeText(path, split.before);
      tx.writeText(newPath, rebased);
      tx.writeText(opfPath, doc.toXmlString());
      _moveFragmentReferences(tx, path, newPath, split.movedIds, {
        ...session.resources.where(_textResource).map((r) => r.path),
        newPath,
      });
    });
  }

  ({String before, String after, Set<String> movedIds}) _splitSource(
    String path,
    int sourceOffset,
  ) {
    final source = session.readText(path);
    final indexed = EditableDocument.parse(source, path: path);
    final body = indexed.elements.firstWhere((e) => e.tag == 'body');
    if (sourceOffset <= body.openEnd ||
        sourceOffset >= body.closeStart ||
        body.children.any(
          (e) => sourceOffset > e.start && sourceOffset < e.end,
        )) {
      throw ArgumentError('请把光标放在完整段落之间');
    }
    final before = source.replaceRange(sourceOffset, body.closeStart, '');
    final after = source.replaceRange(body.openEnd, sourceOffset, '');
    XmlDocument.parse(before);
    final movedIds = _section(
      XmlDocument.parse(after),
      'body',
    ).descendants.whereType<XmlElement>().expand(_elementIds).toSet();
    return (before: before, after: after, movedIds: movedIds);
  }

  void _insertSplitChapter(XmlDocument doc, String path, String newPath) {
    final id = _addManifest(doc, newPath, 'application/xhtml+xml');
    final currentId = _items(doc)
        .firstWhere((e) => _itemPath(e) == path)
        .getAttribute('id');
    final spine = _section(doc, 'spine');
    final index = spine.children.indexWhere(
      (e) => e is XmlElement && e.getAttribute('idref') == currentId,
    );
    if (index < 0) throw ArgumentError('只能拆分阅读顺序中的章节');
    spine.children.insert(
      index + 1,
      _elementLike(spine, 'itemref', [
        XmlAttribute(XmlName.parts('idref'), id),
      ]),
    );
  }

  void mergeChapters(String firstPath, String secondPath) {
    final ordered = chapters.map((e) => e.path).toList();
    if (!ordered.contains(firstPath) ||
        ordered.indexOf(secondPath) != ordered.indexOf(firstPath) + 1) {
      throw ArgumentError('只能合并相邻章节');
    }
    final secondId = _items(_package)
        .firstWhere((item) => _itemPath(item) == secondPath)
        .getAttribute('id')!;
    final first = _mergedDocument(firstPath, secondPath);
    final references = _rewrittenResources({secondPath: firstPath})
      ..remove(secondPath);
    final doc = XmlDocument.parse(
      references.remove(opfPath) ?? session.readText(opfPath),
    );
    final item = _items(doc)
        .firstWhere((item) => item.getAttribute('id') == secondId);
    _assertNoItemReferences(doc, item);
    _removeManifestAndSpine(doc, secondId);
    session.transaction('合并章节', (tx) {
      for (final entry in references.entries) {
        tx.writeText(entry.key, entry.value);
      }
      tx.writeText(firstPath, first.toXmlString());
      tx.writeText(opfPath, doc.toXmlString());
      tx.remove(secondPath);
    });
  }

  XmlDocument _mergedDocument(String firstPath, String secondPath) {
    final first = _rebaseMergedDocument(firstPath, firstPath, secondPath);
    final second = _rebaseMergedDocument(secondPath, firstPath, secondPath);
    final ids = first.descendants
        .whereType<XmlElement>()
        .expand(_elementIds)
        .toSet();
    if (second.descendants.whereType<XmlElement>().any(
      (e) => _elementIds(e).any(ids.contains),
    )) {
      throw StateError('章节存在重复 ID，请先重命名后再合并');
    }
    _section(first, 'body').children.add(
      _copyWithNamespaces(_section(second, 'body'), localName: 'div'),
    );
    _section(first, 'head').children.addAll(
      _section(second, 'head').childElements
          .where((e) => e.name.local == 'link' || e.name.local == 'style')
          .map(_copyWithNamespaces),
    );
    return first;
  }

  XmlDocument _rebaseMergedDocument(
    String path,
    String firstPath,
    String secondPath,
  ) => XmlDocument.parse(
    _rewriteDocument(path, session.readText(path), (href) {
      final uri = Uri.tryParse(href);
      if (uri == null || uri.hasScheme || uri.hasAuthority) return href;
      final (target, suffix) = resolveEditReference(path, href);
      if (path == firstPath && target != secondPath) return href;
      return relativeEditReference(
        firstPath,
        target == secondPath ? firstPath : target,
        suffix,
      );
    }),
  );

  void _moveFragmentReferences(
    EpubEditTransaction tx,
    String oldPath,
    String newPath,
    Set<String> ids,
    Set<String> paths,
  ) {
    for (final path in paths) {
      final source = tx.readText(path);
      final next = _rewriteDocument(path, source, (href) {
        final uri = Uri.tryParse(href);
        if (uri == null ||
            uri.hasScheme ||
            uri.hasAuthority ||
            !ids.contains(Uri.decodeComponent(uri.fragment))) {
          return href;
        }
        final (target, suffix) = resolveEditReference(path, href);
        return target == oldPath
            ? relativeEditReference(path, newPath, suffix)
            : href;
      });
      if (next != source) tx.writeText(path, next);
    }
  }
}

String _fragment(String? value) =>
    value == null || value.isEmpty ? '' : '#${Uri.encodeComponent(value)}';

void _readToc(
  XmlElement root,
  String path,
  bool nav,
  int depth,
  List<EditTocEntry> result,
) {
  for (final child in root.childElements) {
    if (child.name.local == (nav ? 'a' : 'navPoint')) {
      final href = nav
          ? child.getAttribute('href')
          : child.childElements
                .where((e) => e.name.local == 'content')
                .firstOrNull
                ?.getAttribute('src');
      if (href != null) {
        final uri = Uri.parse(href);
        result.add(
          EditTocEntry(
            nav
                ? child.innerText
                : child.childElements
                      .firstWhere((e) => e.name.local == 'navLabel')
                      .innerText,
            resolveEditReference(path, href).$1,
            fragment: uri.hasFragment
                ? Uri.decodeComponent(uri.fragment)
                : null,
            depth: depth,
          ),
        );
      }
    }
    final deeper = nav
        ? child.name.local == 'ol' && root.name.local == 'li'
        : child.name.local == 'navPoint';
    _readToc(child, path, nav, depth + (deeper ? 1 : 0), result);
  }
}
