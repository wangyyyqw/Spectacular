part of 'class_style_editor.dart';

List<Map<String, dynamic>> _owners(Map<String, dynamic> metadata) => [
  for (final value in metadata['classStyleOwners'] as List? ?? const [])
    Map<String, dynamic>.from(value as Map),
];

String _elementKey(EditableElementRef node) {
  final id = node.attributes['id'];
  if (id != null && id.isNotEmpty) return '${node.tag}#$id';
  return [...node.ancestors, node]
      .map(
        (element) =>
            '${element.qualifiedName}:${element.parent?.children.indexOf(element) ?? 0}',
      )
      .join('/');
}

EditableElementRef? _ownedElement(
  String source,
  String path,
  Map<String, dynamic> owner,
) {
  final nodes = EditableDocument.parse(source, path: path).elements.where(
    (e) =>
        _elementKey(e) == owner['element'] &&
        e.classes.contains(owner['className']),
  );
  if (nodes.length != 1) return null;
  final node = nodes.single;
  return _elementSignature(node) == owner['signature'] ? node : null;
}

/// 归属基于元素身份、属性和生成声明；修改正文或后代不能取消样式管理。
String _elementSignature(EditableElementRef node) => editDigest(
  '${node.qualifiedName}|${Map.of(node.attributes)..remove('style')}',
);

String _generatedStyle(String? original, Map<String, String> values) {
  final prefix = original?.trimRight() ?? '';
  final tail = values.entries
      .map(
        (entry) =>
            '${entry.key}: ${entry.value.replaceFirst(RegExp(r'\s*!\s*important\s*$', caseSensitive: false), '')} !important;',
      )
      .join(' ');
  return '${prefix.isEmpty ? '' : '$prefix${prefix.endsWith(';') ? '' : ';'} '}$tail';
}

List<Map<String, dynamic>> _elementOwners(
  List<Map<String, dynamic>> owners,
  String path,
  String key,
) => owners.where((o) => o['path'] == path && o['element'] == key).toList();

extension _ClassOwnership on ClassStyleEditor {
  void _updateOwned(
    EpubEditTransaction tx,
    List<Map<String, dynamic>> owners,
    String className,
    Map<String, String> values,
  ) {
    final targets = List.of(owners.where((e) => e['className'] == className));
    for (final owner in targets) {
      if (!owners.contains(owner)) continue;
      final path = owner['path'] as String;
      final group = _elementOwners(owners, path, owner['element'] as String);
      final source = tx.readBytes(path) == null ? null : tx.readText(path);
      final node = source == null ? null : _ownedElement(source, path, owner);
      if (node == null || node.attributes['style'] != owner['generatedStyle']) {
        owners.removeWhere(group.contains);
        continue;
      }
      owner['properties'] = (owner['properties'] as List)
          .cast<String>()
          .where(values.containsKey)
          .toList();
      _renderOwners(tx, owners, group, node);
    }
  }

  void _renderOwners(
    EpubEditTransaction tx,
    List<Map<String, dynamic>> owners,
    List<Map<String, dynamic>> group,
    EditableElementRef node,
  ) {
    final original = group.first['originalStyle'] as String?;
    final combined = <String, String>{};
    final css = tx.readText(stylesheetPath);
    for (final owner in group) {
      final declared = _simpleDeclarations(css, owner['className'] as String);
      final properties = (owner['properties'] as List).cast<String>();
      owner['properties'] = properties.where(declared.containsKey).toList();
      for (final property in (owner['properties'] as List).cast<String>()) {
        combined[property] = declared[property]!;
      }
    }
    owners.removeWhere(
      (o) => group.contains(o) && (o['properties'] as List).isEmpty,
    );
    final next = combined.isEmpty
        ? original
        : _generatedStyle(original, combined);
    tx.writeText(node.path, node.replaceAttribute('style', next));
    for (final owner in group.where(owners.contains)) {
      owner['originalStyle'] = original;
      owner['generatedStyle'] = next;
    }
  }

  void _unify(
    EpubEditTransaction tx,
    List<Map<String, dynamic>> owners,
    List<_StyleTarget> targets,
    String className,
    Map<String, String> values,
    List<ClassStyleConflict> conflicts,
  ) {
    for (final target in targets) {
      final targetConflicts = <ClassStyleConflict>[];
      _inspectTarget(target, className, values, targetConflicts, [], {});
      final proposed = <String, String>{
        for (final entry in values.entries)
          if (entry.value.isNotEmpty &&
              targetConflicts.any((c) => c.property == entry.key))
            entry.key: entry.value,
      };
      if (proposed.isNotEmpty) {
        _overrideTarget(tx, owners, target.node, className, proposed);
      }
    }
  }

  void _overrideTarget(
    EpubEditTransaction tx,
    List<Map<String, dynamic>> owners,
    EditableElementRef originalNode,
    String className,
    Map<String, String> values,
  ) {
    final path = originalNode.path;
    final key = _elementKey(originalNode);
    final doc = EditableDocument.parse(tx.readText(path), path: path);
    final node = doc.elements.singleWhere((e) => _elementKey(e) == key);
    var group = _elementOwners(owners, path, key);
    if (group.any(
      (o) =>
          o['generatedStyle'] != node.attributes['style'] ||
          o['signature'] != _elementSignature(node),
    )) {
      owners.removeWhere(group.contains);
      group = [];
    }
    final original = group.isEmpty
        ? node.attributes['style']
        : group.first['originalStyle'] as String?;
    final previous = group
        .where((o) => o['className'] == className)
        .firstOrNull;
    final properties = {
      ...?((previous?['properties'] as List?)?.cast<String>()),
      ...values.keys,
    };
    if (previous != null) {
      owners.remove(previous);
      group.remove(previous);
    }
    final added = <String, dynamic>{
      'path': path,
      'element': key,
      'signature': _elementSignature(node),
      'className': className,
      'properties': properties.toList(),
      'originalStyle': original,
      'generatedStyle': node.attributes['style'],
    };
    owners.add(added);
    group.add(added);
    _renderOwners(tx, owners, group, node);
  }
}
