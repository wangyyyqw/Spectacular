import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'epub_edit_session.dart';
import 'editable_document.dart';
import 'epub_writer.dart';
import '../css/parser.dart';
import '../css/selector.dart';
import '../txt.dart';
import '../position/cfi.dart';

part 'package_references.dart';
part 'package_navigation.dart';
part 'package_search.dart';
part 'epub_rechapter.dart';
part 'epub_rechapter_dom.dart';
part 'epub_rechapter_package.dart';

/// 工作副本中的章节；路径始终相对 EPUB 根目录。
class EditChapter {
  const EditChapter(this.id, this.path, this.title);
  final String id;
  final String path;
  final String title;
}

/// EPUB 包结构命令与源码编辑共用同一个事务历史。
class PackageEditor {
  PackageEditor(this.session);
  final EpubEditSession session;

  String get opfPath => session.opfPath;
  XmlDocument get _package => XmlDocument.parse(session.readText(opfPath));
  XmlElement _section(XmlDocument doc, String name) =>
      doc.descendants.whereType<XmlElement>().firstWhere(
        (e) => e.name.local == name,
        orElse: () => throw FormatException('EPUB 缺少 $name'),
      );
  Iterable<XmlElement> _items(XmlDocument doc) => _section(
    doc,
    'manifest',
  ).childElements.where((e) => e.name.local == 'item');
  String _itemPath(XmlElement item) =>
      resolveEditReference(opfPath, item.getAttribute('href')!).$1;

  Map<String, String> get metadata {
    final result = <String, String>{};
    for (final node in _section(_package, 'metadata').childElements) {
      if (_metadataFields.contains(node.name.local)) {
        result.putIfAbsent(node.name.local, () => node.innerText);
      }
    }
    return result;
  }

  void setMetadata(Map<String, String> values) {
    final doc = _package;
    final metadata = _section(doc, 'metadata');
    for (final entry in values.entries) {
      if (!_metadataFields.contains(entry.key)) {
        throw ArgumentError('不支持修改元数据：${entry.key}');
      }
      final node = metadata.childElements
          .where((e) => e.name.local == entry.key)
          .firstOrNull;
      if (node != null) {
        node.children.replaceRange(0, node.children.length, [
          XmlText(entry.value),
        ]);
      } else {
        metadata.children.add(
          XmlElement(
            XmlName.parts(entry.key, prefix: 'dc'),
            [
              XmlAttribute(
                XmlName.parts('dc', prefix: 'xmlns'),
                'http://purl.org/dc/elements/1.1/',
              ),
            ],
            [XmlText(entry.value)],
          ),
        );
      }
    }
    _writePackage('修改书籍信息', doc);
  }

  /// 完整替换作者或标签；空列表清空该字段，其他元数据保持原样。
  void setMetadataValues(String field, List<String> values) {
    if (field != 'creator' && field != 'subject') {
      throw ArgumentError('不支持修改多值元数据：$field');
    }
    const namespace = 'http://purl.org/dc/elements/1.1/';
    final doc = _package;
    final metadata = _section(doc, 'metadata');
    final removed = metadata.childElements
        .where(
          (node) =>
              node.name.local == field &&
              (node.namespaceUri == namespace ||
                  node.namespaceUri == null ||
                  node.namespaceUri!.isEmpty),
        )
        .toList();
    _removeMetadataElements(metadata, removed);
    metadata.children.addAll([
      for (final value in values)
        XmlElement(
          XmlName.parts(field, prefix: 'dc'),
          [XmlAttribute(XmlName.parts('dc', prefix: 'xmlns'), namespace)],
          [XmlText(value)],
        ),
    ]);
    _writePackage('修改书籍信息', doc);
  }

  void _removeMetadataElements(XmlElement metadata, List<XmlElement> removed) {
    final ids = removed.expand(_elementIds).toSet();
    var changed = true;
    while (changed) {
      changed = false;
      for (final node in metadata.childElements) {
        if (removed.contains(node)) continue;
        final refines = Uri.tryParse(
          node.getAttribute('refines')?.trim() ?? '',
        );
        if (refines == null ||
            refines.hasScheme ||
            refines.hasAuthority ||
            refines.hasQuery ||
            refines.path.isNotEmpty ||
            !ids.contains(Uri.decodeComponent(refines.fragment))) {
          continue;
        }
        removed.add(node);
        ids.addAll(_elementIds(node));
        changed = true;
      }
    }
    metadata.children.removeWhere(removed.contains);
  }

  List<EditChapter> get chapters {
    final doc = _package;
    final items = {
      for (final item in _items(doc)) item.getAttribute('id'): item,
    };
    return [
      for (final ref in _section(doc, 'spine').childElements)
        if (items[ref.getAttribute('idref')] case final item?)
          EditChapter(
            item.getAttribute('id')!,
            _itemPath(item),
            p.posix.basename(_itemPath(item)),
          ),
    ];
  }

  void reorderChapters(List<String> paths) {
    final original = chapters.map((e) => e.path).toList();
    if (paths.length != original.length ||
        paths.toSet().length != paths.length ||
        !paths.toSet().containsAll(original)) {
      throw ArgumentError('章节排序必须包含全部章节且不能重复');
    }
    final doc = _package;
    final spine = _section(doc, 'spine');
    final refs = {
      for (final e in spine.childElements) e.getAttribute('idref'): e.copy(),
    };
    final ids = {
      for (final e in _items(doc)) _itemPath(e): e.getAttribute('id'),
    };
    spine.children.replaceRange(
      0,
      spine.children.length,
      paths.map((path) => refs[ids[path]]!),
    );
    _writePackage('调整章节顺序', doc);
  }

  void addResource(String path, Uint8List bytes, String mediaType) {
    _requireNewPath(path);
    final doc = _package;
    _addManifest(doc, path, mediaType);
    session.transaction('添加资源', (tx) {
      tx.writeBytes(path, bytes);
      tx.writeText(opfPath, doc.toXmlString());
    });
  }

  void addXhtml(
    String path,
    String title, {
    int? index,
    bool blank = false,
    String? stylesFrom,
  }) {
    _requireNewPath(path);
    final doc = _package;
    final id = _addManifest(doc, path, 'application/xhtml+xml');
    final spine = _section(doc, 'spine');
    final references = spine.childElements
        .where((element) => element.name.local == 'itemref')
        .toList();
    if (index != null && (index < 0 || index > references.length)) {
      throw RangeError.range(index, 0, references.length, 'index');
    }
    final position = index == null || index == references.length
        ? spine.children.length
        : spine.children.indexOf(references[index]);
    spine.children.insert(
      position,
      _elementLike(spine, 'itemref', [
        XmlAttribute(XmlName.parts('idref'), id),
      ]),
    );
    final body = _newXhtml(path, title, blank, stylesFrom);
    session.transaction('新增章节', (tx) {
      tx.writeText(path, body.toXmlString());
      tx.writeText(opfPath, doc.toXmlString());
    });
  }

  XmlDocument _newXhtml(
    String path,
    String title,
    bool blank,
    String? stylesFrom,
  ) {
    final document = XmlDocument.parse(
      blank
          ? '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<html xmlns="http://www.w3.org/1999/xhtml">\n'
                '  <head>\n    <title/>\n  </head>\n'
                '  <body>\n    \n  </body>\n</html>\n'
          : '<html xmlns="http://www.w3.org/1999/xhtml"><head><title/></head>'
                '<body><h1/></body></html>',
    );
    _section(document, 'title').children.add(
      XmlText(
        blank && title.trim().isEmpty
            ? p.posix.basenameWithoutExtension(path)
            : title,
      ),
    );
    if (!blank) _section(document, 'h1').children.add(XmlText(title));
    if (stylesFrom != null) {
      _inheritXhtmlStyles(_section(document, 'head'), path, stylesFrom);
    }
    return document;
  }

  void _inheritXhtmlStyles(XmlElement head, String path, String stylesFrom) {
    final original = XmlDocument.parse(session.readText(stylesFrom));
    for (final node in _section(original, 'head').childElements) {
      final isStyle = node.name.local == 'style';
      final isLink =
          node.name.local == 'link' &&
          (node.getAttribute('rel') ?? '')
              .toLowerCase()
              .split(RegExp(r'\s+'))
              .contains('stylesheet');
      if (!isStyle && !isLink) continue;
      final copy = _copyWithNamespaces(node);
      _rewriteElementReferences(copy, (href) {
        final uri = Uri.parse(href);
        if (uri.hasScheme || uri.hasAuthority) return href;
        final (target, suffix) = resolveEditReference(stylesFrom, href);
        return relativeEditReference(path, target, suffix);
      });
      head.children.addAll([XmlText('\n    '), copy]);
    }
  }

  void renameResource(String oldPath, String newPath) {
    _requireNewPath(newPath);
    if (oldPath == opfPath || oldPath.startsWith('META-INF/')) {
      throw StateError('包控制文件不能重命名');
    }
    final contents = _rewrittenResources(oldPath, newPath);
    final bytes = session.readBytes(oldPath);
    if (bytes == null) throw StateError('资源不存在：$oldPath');
    session.transaction('重命名资源并更新引用', (tx) {
      tx.writeBytes(newPath, bytes);
      for (final entry in contents.entries) {
        tx.writeText(entry.key == oldPath ? newPath : entry.key, entry.value);
      }
      tx.remove(oldPath);
    });
  }

  void removeResource(String path) {
    if (path == opfPath || path.startsWith('META-INF/')) {
      throw StateError('包控制文件不能删除');
    }
    final refs = referencesTo(path)
        .where((e) => e != opfPath && e != path)
        .toList();
    if (refs.isNotEmpty) throw StateError('仍被以下文件引用：${refs.join('、')}');
    final doc = _package;
    final item = _items(doc).where((e) => _itemPath(e) == path).firstOrNull;
    if (item == null) throw StateError('资源不在清单中');
    final id = item.getAttribute('id')!;
    final spine = _section(doc, 'spine');
    final reading = spine.childElements
        .where((e) => e.name.local == 'itemref')
        .toList();
    if (reading.length == 1 && reading.first.getAttribute('idref') == id) {
      throw StateError('不能删除最后一个正文文档');
    }
    _assertNoItemReferences(doc, item);
    _assertNoPackagePathReferences(doc, item, path);
    _removeManifestAndSpine(doc, id);
    session.transaction('删除资源', (tx) {
      tx.remove(path);
      tx.writeText(opfPath, doc.toXmlString());
    });
  }

  void setCover(String path) {
    final doc = _package;
    final item = _items(doc).firstWhere((e) => _itemPath(e) == path);
    if (!(item.getAttribute('media-type') ?? '').startsWith('image/')) {
      throw ArgumentError('封面必须是图片资源');
    }
    final isEpub3 = (doc.rootElement.getAttribute('version') ?? '').startsWith(
      '3',
    );
    for (final resource in _items(doc)) {
      final properties = (resource.getAttribute('properties') ?? '')
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty && e != 'cover-image')
          .toList();
      if (identical(resource, item) && isEpub3) properties.add('cover-image');
      resource.setAttribute(
        'properties',
        properties.isEmpty ? null : properties.join(' '),
      );
    }
    final metadata = _section(doc, 'metadata');
    metadata.children.removeWhere(
      (e) =>
          e is XmlElement &&
          e.name.local == 'meta' &&
          e.getAttribute('name')?.trim().toLowerCase() == 'cover',
    );
    metadata.children.add(
      _elementLike(metadata, 'meta', [
        XmlAttribute(XmlName.parts('name'), 'cover'),
        XmlAttribute(XmlName.parts('content'), item.getAttribute('id')!),
      ]),
    );
    _writePackage('设置封面', doc);
  }

  void _writePackage(String label, XmlDocument doc) => session.transaction(
    label,
    (tx) => tx.writeText(opfPath, doc.toXmlString()),
  );

  void _requireNewPath(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        p.posix.normalize(path) != path ||
        path.startsWith('../') ||
        path.contains('#') ||
        path.contains('?')) {
      throw ArgumentError('请输入 EPUB 内的规范相对路径');
    }
    if (session.resources.any((e) => e.path == path)) {
      throw StateError('资源已存在：$path');
    }
  }

  String _addManifest(XmlDocument doc, String path, String mediaType) {
    final ids = _items(doc).map((e) => e.getAttribute('id')).toSet();
    var index = 1;
    while (ids.contains('edit-$index')) {
      index++;
    }
    final id = 'edit-$index';
    final manifest = _section(doc, 'manifest');
    manifest.children.add(
      _elementLike(manifest, 'item', [
        XmlAttribute(XmlName.parts('id'), id),
        XmlAttribute(
          XmlName.parts('href'),
          relativeEditReference(opfPath, path),
        ),
        XmlAttribute(XmlName.parts('media-type'), mediaType),
      ]),
    );
    return id;
  }
}

/// 新元素沿用插入位置的命名空间前缀，不假定 EPUB 使用默认命名空间。
XmlElement _elementLike(
  XmlElement context,
  String name, [
  Iterable<XmlAttribute> attributes = const [],
  Iterable<XmlNode> children = const [],
]) => XmlElement(
  XmlName.parts(name, prefix: context.name.prefix),
  attributes,
  children,
);

Iterable<String> _elementIds(XmlElement node) => node.attributes
    .where(
      (attribute) =>
          attribute.name.qualified == 'id' ||
          attribute.name.qualified == 'xml:id',
    )
    .map((attribute) => attribute.value)
    .where((id) => id.isNotEmpty);

/// 跨文档移动时在副本根补齐原位置有效的声明，保留后代与属性的命名空间。
XmlElement _copyWithNamespaces(XmlElement source, {String? localName}) {
  final copy = XmlElement(
    XmlName.parts(localName ?? source.name.local, prefix: source.name.prefix),
    source.attributes.map((attribute) => attribute.copy()),
    source.children.map((child) => child.copy()),
  );
  final bindings = <String, XmlAttribute>{};
  for (final element in [
    ...source.ancestors.whereType<XmlElement>().toList().reversed,
    source,
  ]) {
    for (final attribute in element.attributes) {
      if (attribute.name.qualified == 'xmlns' ||
          attribute.name.prefix == 'xmlns') {
        bindings[attribute.name.qualified] = attribute;
      }
    }
  }
  for (final binding in bindings.entries) {
    if (!copy.attributes.any(
      (attribute) => attribute.name.qualified == binding.key,
    )) {
      copy.attributes.add(binding.value.copy());
    }
  }
  return copy;
}

const _metadataFields = {
  'title',
  'creator',
  'language',
  'description',
  'publisher',
  'subject',
  'date',
  'rights',
};
