import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../css/parser.dart';
import 'editable_document.dart';
import 'edit_text_encoding.dart';

String validateEditContainer(Uint8List bytes) {
  final container = XmlDocument.parse(
    EditTextEncoding.detect(bytes).decode(bytes),
  );
  final rootfile = container.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'rootfile')
      .firstOrNull;
  final path = rootfile?.getAttribute('full-path')?.trim() ?? '';
  if (container.rootElement.name.local != 'container' || path.isEmpty) {
    throw const EpubEditException('container.xml 必须声明有效的 OPF 路径');
  }
  return path;
}

/// 只检查本次触及的源码，未知资源保持原字节；未支持的 CSS 属性不改写。
void validateEditResource(String path, Uint8List bytes) {
  final extension = p.posix.extension(path).toLowerCase();
  final xml = const {'.xhtml', '.html', '.htm', '.xml', '.opf', '.ncx', '.svg'};
  if (!xml.contains(extension) && extension != '.css') return;
  final encoding = EditTextEncoding.detect(bytes);
  final text = encoding.decode(bytes);
  if (extension == '.css') {
    final errors = CssParser.parse(text).warnings.where(
      (message) =>
          RegExp(r'^\d+:\d+:').hasMatch(message) ||
          message.startsWith('CSS 解析异常'),
    );
    if (errors.isNotEmpty) throw EpubEditException('CSS 语法错误：${errors.first}');
    return;
  }
  encoding.validateDeclaration(text);
  final document = EditableDocument.parse(text, path: path);
  final ids = <String>{};
  for (final element in document.elements) {
    final id = element.attributes['id'] ?? element.attributes['xml:id'];
    if (id != null && !ids.add(id)) throw EpubEditException('文档存在重复 ID：$id');
  }
  if (const {'.xhtml', '.html', '.htm'}.contains(extension) &&
      (document.elements.first.tag != 'html' ||
          !document.elements.any((e) => e.tag == 'body'))) {
    throw const EpubEditException('XHTML 必须保留 html 和 body 元素');
  }
}

/// 阅读解析器可跳过坏 idref；保存时拒绝新引入的问题，保留原有告警。
List<String> validateEditPackage(
  String source,
  String opfPath, {
  String? original,
}) {
  final package = _packageElement(XmlDocument.parse(source).rootElement);
  final manifest = _packageSection(package, 'manifest');
  final spine = _packageSection(package, 'spine');
  final before = _originalPackage(original);
  final warnings = <String>[];
  final items = _validateManifest(manifest, before, warnings);
  final previousRefs = _invalidOriginalRefs(before);
  final refs = spine.childElements.where((e) => e.name.local == 'itemref');
  if (refs.isEmpty) throw const EpubEditException('书籍不能没有正文章节');
  for (final ref in refs) {
    final id = ref.getAttribute('idref');
    if (items.contains(id)) continue;
    final message = 'spine 引用了不存在的清单 ID：$id';
    if (!previousRefs.contains(id)) throw EpubEditException(message);
    warnings.add('保留原有包问题：$opfPath → $message');
  }
  return warnings;
}

XmlElement _packageElement(XmlElement root) {
  if (root.name.local == 'package') return root;
  if (root.name.local == 'html') {
    final bodies = root.childElements
        .where((element) => element.name.local == 'body')
        .toList();
    final packages = root.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'package')
        .toList();
    final bodyPackages = bodies.length != 1
        ? const <XmlElement>[]
        : bodies.single.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'package')
              .toList();
    if (bodies.length == 1 &&
        packages.length == 1 &&
        bodyPackages.length == 1) {
      return bodyPackages.single;
    }
  }
  throw const EpubEditException(
    'OPF 根元素必须是 package，或是仅包含一个 body/package 的 html 包装',
  );
}

Set<String?> _invalidOriginalRefs(XmlElement? package) {
  if (package == null) return {};
  final nodes = package.descendants.whereType<XmlElement>();
  final ids = {
    for (final node in nodes)
      if (node.name.local == 'item') node.getAttribute('id'),
  };
  return {
    for (final node in nodes)
      if (node.name.local == 'itemref' &&
          !ids.contains(node.getAttribute('idref')))
        node.getAttribute('idref'),
  };
}

Set<String> _validateManifest(
  XmlElement manifest,
  XmlElement? before,
  List<String> warnings,
) {
  final previousItems = {
    if (before != null)
      for (final item in before.descendants.whereType<XmlElement>())
        if (item.name.local == 'item') _manifestKey(item),
  };
  final items = <String>{};
  for (final item in manifest.childElements.where(
    (e) => e.name.local == 'item',
  )) {
    final id = item.getAttribute('id')?.trim() ?? '';
    final invalid =
        id.isEmpty ||
        !items.add(id) ||
        (item.getAttribute('href')?.trim() ?? '').isEmpty ||
        (item.getAttribute('media-type')?.trim() ?? '').isEmpty;
    if (!invalid) continue;
    const message = 'OPF 清单项必须有唯一 ID、href 和 media-type';
    if (!previousItems.contains(_manifestKey(item))) {
      throw const EpubEditException(message);
    }
    warnings.add('保留原有包问题：$message（$id）');
  }
  return items;
}

String _manifestKey(XmlElement item) => [
  item.getAttribute('id'),
  item.getAttribute('href'),
  item.getAttribute('media-type'),
].toString();

XmlElement? _originalPackage(String? source) {
  if (source == null) return null;
  try {
    return XmlDocument.parse(source).rootElement;
  } catch (_) {
    return null;
  }
}

XmlElement _packageSection(XmlElement package, String name) {
  final sections = package.childElements.where((e) => e.name.local == name);
  if (sections.length != 1) throw EpubEditException('OPF 必须有一个 $name');
  return sections.single;
}
