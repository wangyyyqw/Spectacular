import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:csslib/parser.dart' as csslib;
import 'package:csslib/visitor.dart' as cssast;
import 'package:xml/xml.dart';

import '../css/cascade.dart';
import '../css/computed_style.dart';
import '../css/parser.dart';
import '../css/selector.dart';
import 'editable_document.dart';
import 'epub_edit_session.dart';
import 'package_editor.dart';

part 'class_style_sources.dart';
part 'class_style_ownership.dart';

class ClassStyleConflict {
  const ClassStyleConflict(
    this.path,
    this.selector,
    this.property,
    this.reason,
  );
  final String path;
  final String selector;
  final String property;
  final String reason;
}

class ClassStyleDeclaration {
  const ClassStyleDeclaration({
    required this.path,
    required this.selector,
    required this.property,
    required this.value,
    this.important = false,
    this.media,
  });
  final String path;
  final String selector;
  final String property;
  final String value;
  final bool important;
  final String? media;
}

class ClassStyleReport {
  const ClassStyleReport({
    required this.className,
    required this.elementCount,
    required this.chapterCount,
    required this.conflicts,
    required this.declarations,
    required this.sources,
    this.effectiveValues = const {},
  });
  final String className;
  final int elementCount;
  final int chapterCount;
  final List<ClassStyleConflict> conflicts;
  final Map<String, String> declarations;
  final List<ClassStyleDeclaration> sources;
  final Map<String, List<String>> effectiveValues;
}

/// 普通类规则保存在真实 CSS 中；用户确认的覆盖同样写入标准 XHTML。
class ClassStyleEditor {
  ClassStyleEditor(this.session);
  final EpubEditSession session;
  String get stylesheetPath {
    final recorded = session.metadata['classStylesheet'] as String?;
    if (recorded != null) return recorded;
    final paths = session.resources.map((r) => r.path).toSet();
    final directory = p.posix.dirname(session.opfPath);
    var index = 0;
    String candidate;
    do {
      candidate = p.posix.join(
        directory,
        'spectacular-edit${index == 0 ? '' : '-$index'}.css',
      );
      index++;
    } while (paths.contains(candidate));
    return candidate;
  }

  ClassStyleReport inspect(
    String className, {
    Map<String, String> proposed = const {},
    double viewportWidth = 360,
  }) {
    _checkClass(className);
    final current = _declarations(className);
    final values = {...current, ...proposed}
      ..removeWhere((_, value) => value.trim().isEmpty);
    final targets = _targets(className);
    final conflicts = <ClassStyleConflict>[];
    final sources = <ClassStyleDeclaration>[];
    final seen = <String>{};
    final effective = <String, Set<String>>{};
    final computed = _EffectiveStyleCache(viewportWidth);
    for (final target in targets) {
      _inspectTarget(target, className, values, conflicts, sources, seen);
      for (final entry in computed.forTarget(target).values.entries) {
        effective.putIfAbsent(entry.key, () => {}).add(entry.value);
      }
    }
    return ClassStyleReport(
      className: className,
      elementCount: targets.length,
      chapterCount: targets.map((t) => t.node.path).toSet().length,
      conflicts: conflicts,
      declarations: current,
      sources: sources,
      effectiveValues: {
        for (final entry in effective.entries) entry.key: entry.value.toList(),
      },
    );
  }

  ClassStyleReport apply(
    String className,
    Map<String, String> values, {
    bool unifyConflicts = false,
    double viewportWidth = 360,
  }) {
    _checkClass(className);
    _validateValues(values);
    final report = inspect(
      className,
      proposed: values,
      viewportWidth: viewportWidth,
    );
    final path = stylesheetPath;
    final before = session.resources.any((r) => r.path == path)
        ? session.readText(path)
        : '';
    final css = _replaceRule(before, className, values);
    final targets = _targets(className);
    session.transaction('修改全书 .$className 样式', (tx) {
      _ensureStylesheet(tx, path);
      tx.writeText(path, css);
      final owned = _owners(tx.metadata);
      _updateOwned(tx, owned, className, _simpleDeclarations(css, className));
      if (unifyConflicts) {
        _unify(tx, owned, targets, className, values, report.conflicts);
      }
      tx.metadata['classStyleOwners'] = owned;
      _persistOwnership(tx);
    });
    return report;
  }

  /// 源码修改管理 CSS 时，同步仍受管理的内联覆盖；其他文件照常写入。
  void writeSource(String path, String text) => writeSources({path: text});

  void writeSources(Map<String, String> documents, {bool validate = false}) {
    session.transaction('编辑源码', (tx) {
      for (final entry in documents.entries) {
        tx.writeText(entry.key, entry.value);
      }
      final managed = session.metadata['classStylesheet'] as String?;
      final text = documents[managed];
      if (text == null || CssParser.parse(text).warnings.isNotEmpty) return;
      final owned = _owners(tx.metadata);
      final classes = owned.map((e) => e['className'] as String).toSet();
      for (final name in classes) {
        _updateOwned(tx, owned, name, _simpleDeclarations(text, name));
      }
      tx.metadata['classStyleOwners'] = owned;
      _persistOwnership(tx);
    }, validate: validate);
  }

  void _persistOwnership(EpubEditTransaction tx) {
    tx.writeText(
      'META-INF/spectacular-editor.json',
      jsonEncode({
        'version': 1,
        'classStylesheet': tx.metadata['classStylesheet'],
        'classStyleOwners': tx.metadata['classStyleOwners'],
      }),
    );
  }

  Map<String, String> _declarations(String className) {
    final path = session.metadata['classStylesheet'] as String?;
    return path == null
        ? {}
        : _simpleDeclarations(session.readText(path), className);
  }

  void _ensureStylesheet(EpubEditTransaction tx, String path) {
    tx.metadata['classStylesheet'] = path;
    final opf = XmlDocument.parse(tx.readText(session.opfPath));
    final manifest = opf.descendants.whereType<XmlElement>().firstWhere(
      (e) => e.name.local == 'manifest',
    );
    if (!manifest.childElements.any(
      (e) =>
          resolveEditReference(
            session.opfPath,
            e.getAttribute('href') ?? '',
          ).$1 ==
          path,
    )) {
      final ids = manifest.childElements
          .map((e) => e.getAttribute('id'))
          .toSet();
      var id = 'spectacular-edit';
      var count = 1;
      while (ids.contains(id)) {
        id = 'spectacular-edit-${count++}';
      }
      manifest.children.add(
        XmlElement(XmlName.parts('item'), [
          XmlAttribute(XmlName.parts('id'), id),
          XmlAttribute(
            XmlName.parts('href'),
            relativeEditReference(session.opfPath, path),
          ),
          XmlAttribute(XmlName.parts('media-type'), 'text/css'),
        ]),
      );
      tx.writeText(session.opfPath, opf.toXmlString());
    }
    for (final resource in session.resources.where(
      (r) => r.mediaType == 'application/xhtml+xml',
    )) {
      final text = tx.readText(resource.path);
      final doc = EditableDocument.parse(text, path: resource.path);
      final linked = doc.elements.any(
        (e) =>
            e.tag == 'link' &&
            resolveEditReference(
                  resource.path,
                  e.attributes['href'] ?? '',
                ).$1 ==
                path,
      );
      if (linked) continue;
      final head = doc.elements.where((e) => e.tag == 'head').firstOrNull;
      if (head == null) {
        throw EpubEditException('${resource.path} 缺少 head，不能添加共享样式');
      }
      final prefix = head.qualifiedName.contains(':')
          ? '${head.qualifiedName.split(':').first}:'
          : '';
      final link =
          '<${prefix}link rel="stylesheet" type="text/css" href="${escapeXmlAttribute(relativeEditReference(resource.path, path))}"/>';
      tx.writeText(
        resource.path,
        head.replaceInner('${head.innerXml}\n$link\n'),
      );
    }
  }
}

void _checkClass(String name) {
  if (name.isEmpty || name.contains(RegExp(r'\s')) || name.contains('\u0000')) {
    throw const FormatException('类名必须是一个完整的非空 class token');
  }
}

String _selector(String name) {
  if (RegExp(r'^-?[_a-zA-Z\u0080-\uffff][_a-zA-Z0-9\u0080-\uffff-]*$')
      .hasMatch(name)) {
    return '.$name';
  }
  return '.${name.runes.map((rune) => '\\${rune.toRadixString(16)} ').join()}';
}

bool _isClassRule(CssRule rule, String name) =>
    rule.selector.trim() == '.$name' ||
    rule.selector.trim() == _selector(name).trim();

Map<String, String> _simpleDeclarations(String css, String name) => {
  for (final rule in CssParser.parse(css).rules)
    if (_isClassRule(rule, name) &&
        rule.media == null &&
        rule.mediaConditions.isEmpty)
      for (final declaration in rule.declarations)
        declaration.property:
            '${declaration.value}${declaration.important ? ' !important' : ''}',
};

void _validateValues(Map<String, String> values) {
  for (final entry in values.entries) {
    if (!RegExp(r'^(?:--)?[a-zA-Z][a-zA-Z0-9-]*$').hasMatch(entry.key)) {
      throw FormatException('CSS 属性无效：${entry.key}');
    }
    if (entry.value.trim().isEmpty) continue;
    final sheet = CssParser.parse('x { ${entry.key}: ${entry.value}; }');
    final declarations = sheet.rules.firstOrNull?.declarations ?? [];
    if (sheet.warnings.isNotEmpty ||
        sheet.rules.length != 1 ||
        declarations.length != 1 ||
        declarations.single.property != entry.key ||
        !ComputedStyle.isValidDeclaration(
          entry.key,
          declarations.single.value,
        )) {
      throw FormatException('CSS 值无效：${entry.key}: ${entry.value}');
    }
  }
}

String _replaceRule(String css, String name, Map<String, String> values) {
  final parsed = CssParser.parse(css);
  if (parsed.warnings.isNotEmpty) {
    throw const FormatException('共享 CSS 有语法问题，请先在源码中修正');
  }
  final declarations = _simpleDeclarations(css, name)
    ..addAll(values)
    ..removeWhere((_, value) => value.trim().isEmpty);
  final ast = csslib.parse(css);
  final ranges =
      ast.topLevels
          .whereType<cssast.RuleSet>()
          .where((rule) {
            final selector = rule.selectorGroup?.span?.text.trim();
            return selector == '.$name' || selector == _selector(name).trim();
          })
          .map(
            (rule) =>
                (rule.span.start.offset, rule.declarationGroup.span.end.offset),
          )
          .toList()
        ..sort((a, b) => b.$1.compareTo(a.$1));
  var cleaned = css;
  for (final range in ranges) {
    cleaned = cleaned.replaceRange(range.$1, range.$2, '');
  }
  if (declarations.isEmpty) return cleaned;
  return '$cleaned\n${_selector(name).trim()} {\n${declarations.entries.map((e) => '  ${e.key}: ${e.value};').join('\n')}\n}\n';
}
