import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;

import 'edit_text_encoding.dart';

const editorMetadataPath = 'META-INF/spectacular-editor.json';

/// 比较真实文档语义，只有确定未改正文、目录或包信息时才免除位置迁移。
class EditChangeClassifier {
  const EditChangeClassifier(this.opfPath, this.readBefore, this.readAfter);
  final String opfPath;
  final Uint8List? Function(String) readBefore;
  final Uint8List? Function(String) readAfter;

  bool cssOnly(Iterable<String> paths) {
    try {
      for (final path in paths) {
        if (!_isStyleChange(path)) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isStyleChange(String path) {
    if (path == editorMetadataPath) {
      final bytes = readAfter(path);
      return bytes == null || jsonDecode(_text(bytes)) is Map;
    }
    if (path.toLowerCase().endsWith('.css') && !_isNonCssResource(path)) {
      return true;
    }
    final before = readBefore(path), after = readAfter(path);
    if (before == null || after == null) return false;
    final old = XmlDocument.parse(_text(before));
    final next = XmlDocument.parse(_text(after));
    if (path == opfPath) {
      return _signature(old.rootElement, package: true) ==
          _signature(next.rootElement, package: true);
    }
    if (old.rootElement.name.local != 'html' ||
        next.rootElement.name.local != 'html') {
      return false;
    }
    return _signature(old.rootElement) == _signature(next.rootElement);
  }

  bool _isNonCssResource(String path) {
    for (final bytes in [readBefore(opfPath), readAfter(opfPath)]) {
      if (bytes == null) continue;
      final package = XmlDocument.parse(_text(bytes));
      for (final item in package.descendants.whereType<XmlElement>()) {
        if (item.name.local != 'item' ||
            item.getAttribute('media-type') == 'text/css') {
          continue;
        }
        final href = item.getAttribute('href');
        if (href != null && Uri.parse(opfPath).resolve(href).path == path) {
          return true;
        }
      }
    }
    return false;
  }

  String _signature(XmlElement root, {bool package = false}) =>
      jsonEncode(_node(root, package: package));

  Object? _node(XmlNode node, {required bool package}) {
    if (node is XmlElement) {
      if (_ignoreElement(node, package)) return null;
      final attributes = <String, String>{
        for (final attr in node.attributes)
          if (package || attr.name.local != 'style')
            attr.name.qualified: attr.value,
      };
      final keys = attributes.keys.toList()..sort();
      return [
        node.name.qualified,
        {for (final key in keys) key: attributes[key]},
        [for (final child in node.children) ?_node(child, package: package)],
      ];
    }
    if (node is XmlText) {
      if ((package || node.parentElement?.name.local == 'head') &&
          node.value.trim().isEmpty) {
        return null;
      }
      return node.value;
    }
    if (node is XmlCDATA) return node.value;
    return node.toXmlString();
  }

  bool _ignoreElement(XmlElement node, bool package) {
    if (package) {
      return node.name.local == 'item' &&
          node.parentElement?.name.local == 'manifest' &&
          node.getAttribute('media-type') == 'text/css';
    }
    if (node.parentElement?.name.local != 'head') return false;
    return node.name.local == 'style' ||
        node.name.local == 'link' &&
            (node.getAttribute('rel') ?? '')
                .split(RegExp(r'\s+'))
                .contains('stylesheet');
  }
}

String _text(Uint8List bytes) => EditTextEncoding.detect(bytes).decode(bytes);

/// 归属只用于安全恢复编辑记录；不完整或类型不符时不猜测归属。
Map<String, dynamic> readEditorMetadata(Uint8List? bytes) {
  try {
    if (bytes == null) return {};
    final value = jsonDecode(_text(bytes));
    if (value is! Map || value['version'] != 1) return {};
    final sheet = value['classStylesheet'];
    final owners = value['classStyleOwners'];
    if (sheet is! String ||
        !_safePath(sheet) ||
        owners is! List ||
        !owners.every(_validOwner)) {
      return {};
    }
    return {'classStylesheet': sheet, 'classStyleOwners': owners};
  } catch (_) {
    return {};
  }
}

bool _validOwner(Object? value) {
  if (value is! Map) return false;
  for (final key in [
    'path',
    'element',
    'signature',
    'className',
    'generatedStyle',
  ]) {
    if (value[key] is! String) return false;
  }
  if (!_safePath(value['path'] as String)) return false;
  final properties = value['properties'];
  return properties is List &&
      properties.every((item) => item is String) &&
      (value['originalStyle'] == null || value['originalStyle'] is String);
}

bool _safePath(String value) =>
    value.isNotEmpty &&
    !value.contains('\\') &&
    !value.contains('\u0000') &&
    !Uri.parse(value).hasScheme &&
    !value.startsWith('/') &&
    value != '..' &&
    !value.startsWith('../') &&
    p.posix.normalize(value) == value;
