import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// 注释类型。
enum NoteKind { footnote, endnote, link }

/// 锚点解析策略，便于统计与降级。
enum AnchorStrategy {
  directId,
  caseInsensitiveId,
  backlink,
  textPrefix,
  unresolved,
}

/// 一条注释锚点：正文中的引用 → 注释目标。
class FootnoteAnchor {
  /// 创建锚点。
  const FootnoteAnchor({
    required this.sourceSpine,
    required this.href,
    required this.label,
    required this.kind,
    required this.targetSpine,
    required this.strategy,
    this.sourceId,
    this.targetId,
    this.noteText,
    this.crossDocument = false,
  });

  /// 引用所在 spine。
  final int sourceSpine;

  /// 原始 href。
  final String href;

  /// 引用文字（如 `[1]`）。
  final String label;

  /// 注释类型。
  final NoteKind kind;

  /// 引用元素的 id。
  final String? sourceId;

  /// 目标所在 spine；未解析为 -1。
  final int targetSpine;

  /// 目标元素 id；按文字前缀兜底时可能为空。
  final String? targetId;

  /// 目标注释容器文字（截断）。
  final String? noteText;

  /// 是否跨文档。
  final bool crossDocument;

  /// 解析策略。
  final AnchorStrategy strategy;
}

/// 单章解析结果。
class FootnoteDocument {
  /// 创建解析结果。
  FootnoteDocument({
    required this.spineIndex,
    required this.path,
    required this.ids,
    required this.elements,
    required this.anchors,
  });

  /// spine 序号。
  final int spineIndex;

  /// ZIP 内绝对路径。
  final String path;

  /// id → 元素。
  final Map<String, XmlElement> ids;

  /// 全部元素（按文档顺序）。
  final List<XmlElement> elements;

  /// 引用锚点。
  final List<FootnoteAnchor> anchors;
}

/// 注释锚点解析：不修改原书 DOM。
abstract final class FootnoteParser {
  /// 解析单章 XHTML，收集 id 与引用候选。
  static FootnoteDocument parse({
    required int spineIndex,
    required String path,
    required String xhtml,
  }) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(_sanitizeEntities(_stripBom(xhtml)));
    } on FormatException {
      return FootnoteDocument(
        spineIndex: spineIndex,
        path: path,
        ids: const <String, XmlElement>{},
        elements: const <XmlElement>[],
        anchors: const <FootnoteAnchor>[],
      );
    }

    final ids = <String, XmlElement>{};
    for (final element in document.descendants.whereType<XmlElement>()) {
      final id = element.getAttribute('id')?.trim();
      if (id != null && id.isNotEmpty) {
        ids.putIfAbsent(id, () => element);
      }
    }

    final baseDir = _dirOf(path);
    final anchors = <FootnoteAnchor>[];
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'a') {
        continue;
      }
      final href = element.getAttribute('href')?.trim() ?? '';
      final hash = href.indexOf('#');
      if (hash < 0 || hash == href.length - 1) {
        continue;
      }
      final targetPath = _resolvePath(href.substring(0, hash), baseDir, path);
      final fragment = href.substring(hash + 1);
      final label = _normalizeText(element.innerText);
      final sourceId = element.getAttribute('id')?.trim();
      final kind = _kindOf(element, fragment, null);
      anchors.add(
        FootnoteAnchor(
          sourceSpine: spineIndex,
          href: href,
          label: label,
          kind: kind,
          sourceId: sourceId == null || sourceId.isEmpty ? null : sourceId,
          targetSpine: -1,
          targetId: null,
          strategy: AnchorStrategy.unresolved,
          crossDocument: targetPath != path,
        ),
      );
    }

    return FootnoteDocument(
      spineIndex: spineIndex,
      path: path,
      ids: ids,
      elements: document.descendants.whereType<XmlElement>().toList(
        growable: false,
      ),
      anchors: List<FootnoteAnchor>.unmodifiable(anchors),
    );
  }

  /// 在已解析的文档集合中解析锚点目标。
  static List<FootnoteAnchor> resolve({
    required FootnoteDocument source,
    required Map<String, FootnoteDocument> documents,
  }) {
    final resolved = <FootnoteAnchor>[];
    for (final anchor in source.anchors) {
      final hash = anchor.href.indexOf('#');
      final targetPath = _resolvePath(
        anchor.href.substring(0, hash),
        _dirOf(source.path),
        source.path,
      );
      final fragment = anchor.href.substring(hash + 1);
      final target = documents[targetPath];
      if (target == null) {
        resolved.add(
          _withTarget(anchor, -1, null, null, AnchorStrategy.unresolved),
        );
        continue;
      }

      String? targetId = fragment;
      var element = target.ids[fragment];
      var strategy = AnchorStrategy.directId;
      if (element == null) {
        final lower = fragment.toLowerCase();
        for (final entry in target.ids.entries) {
          if (entry.key.toLowerCase() == lower) {
            element = entry.value;
            targetId = entry.key;
            strategy = AnchorStrategy.caseInsensitiveId;
            break;
          }
        }
      }

      if (element == null) {
        final byBacklink = _findBacklinkTarget(target, anchor.sourceId);
        if (byBacklink != null) {
          element = byBacklink;
          targetId = byBacklink.getAttribute('id');
          strategy = AnchorStrategy.backlink;
        }
      }

      if (element == null) {
        final byText = _findTextPrefixTarget(target, anchor.label);
        if (byText != null) {
          element = byText;
          targetId = byText.getAttribute('id');
          strategy = AnchorStrategy.textPrefix;
        }
      }

      if (element == null) {
        resolved.add(
          _withTarget(
            anchor,
            target.spineIndex,
            null,
            null,
            AnchorStrategy.unresolved,
          ),
        );
        continue;
      }

      final targetKind = _kindOfElement(element, fragment);
      final kind = anchor.kind == NoteKind.link && targetKind != NoteKind.link
          ? targetKind
          : anchor.kind;
      final container = _noteContainer(element);
      resolved.add(
        FootnoteAnchor(
          sourceSpine: anchor.sourceSpine,
          href: anchor.href,
          label: anchor.label,
          kind: kind,
          sourceId: anchor.sourceId,
          targetSpine: target.spineIndex,
          targetId: targetId,
          noteText: _noteText(container, anchor.label),
          crossDocument: target.spineIndex != source.spineIndex,
          strategy: strategy,
        ),
      );
    }
    return resolved;
  }

  static FootnoteAnchor _withTarget(
    FootnoteAnchor anchor,
    int targetSpine,
    String? targetId,
    String? noteText,
    AnchorStrategy strategy,
  ) => FootnoteAnchor(
    sourceSpine: anchor.sourceSpine,
    href: anchor.href,
    label: anchor.label,
    kind: anchor.kind,
    sourceId: anchor.sourceId,
    targetSpine: targetSpine,
    targetId: targetId,
    noteText: noteText,
    crossDocument: targetSpine != anchor.sourceSpine && targetSpine >= 0,
    strategy: strategy,
  );

  static NoteKind _kindOf(
    XmlElement element,
    String fragment,
    XmlElement? target,
  ) {
    final type = _epubType(element);
    if (type.contains('noteref') || type.contains('footnote')) {
      return NoteKind.footnote;
    }
    if (type.contains('endnote')) {
      return NoteKind.endnote;
    }
    final classes = _classes(element);
    if (classes.any((c) => c.contains('noteref') || c.contains('footnote'))) {
      return NoteKind.footnote;
    }
    if (_hasAncestor(element, 'sup')) {
      return NoteKind.footnote;
    }
    if (RegExp(r'^[\[\(（]?\d+[\]\)）]?$')
        .hasMatch(_normalizeText(element.innerText))) {
      return NoteKind.footnote;
    }
    if (target != null) {
      return _kindOfElement(target, fragment);
    }
    return NoteKind.link;
  }

  static NoteKind _kindOfElement(XmlElement element, String fragment) {
    final type = _epubType(element);
    if (type.contains('endnote')) {
      return NoteKind.endnote;
    }
    if (type.contains('footnote') ||
        element.name.local == 'aside' ||
        _classes(element).any((c) => c.contains('footnote'))) {
      return NoteKind.footnote;
    }
    return NoteKind.link;
  }

  static XmlElement? _findBacklinkTarget(
    FootnoteDocument target,
    String? sourceId,
  ) {
    if (sourceId == null || sourceId.isEmpty) {
      return null;
    }
    for (final element in target.ids.values) {
      for (final anchor in element.descendants.whereType<XmlElement>()) {
        if (anchor.name.local == 'a' &&
            (anchor.getAttribute('href') ?? '').trim() == '#$sourceId') {
          return _containerWithId(_noteContainer(anchor));
        }
      }
    }
    return null;
  }

  static XmlElement? _findTextPrefixTarget(
    FootnoteDocument target,
    String label,
  ) {
    final prefixes = _candidatePrefixes(label);
    if (prefixes.isEmpty) {
      return null;
    }
    for (final element in target.elements) {
      if (element.name.local != 'li' &&
          !(element.name.local == 'p' &&
              _classes(element).any((c) => c.contains('footnote')))) {
        continue;
      }
      final text = _normalizeText(element.innerText);
      if (prefixes.any((prefix) => text.startsWith(prefix))) {
        return element;
      }
    }
    return null;
  }

  static XmlElement _containerWithId(XmlElement element) {
    var current = element;
    while (current.name.local != 'body') {
      final id = current.getAttribute('id')?.trim();
      if (id != null && id.isNotEmpty) {
        return current;
      }
      final parent = current.parent;
      if (parent is! XmlElement) {
        break;
      }
      current = parent;
    }
    return element;
  }

  static XmlElement _noteContainer(XmlElement element) {
    var current = element;
    for (var depth = 0; depth < 6; depth++) {
      if (current.name.local == 'body') {
        break;
      }
      if (current.name.local == 'aside' ||
          current.name.local == 'li' ||
          current.name.local == 'p' ||
          _classes(current).any((c) => c.contains('footnote'))) {
        return current;
      }
      final parent = current.parent;
      if (parent is! XmlElement) {
        break;
      }
      current = parent;
    }
    return element;
  }

  static String? _noteText(XmlElement container, String label) {
    var text = _normalizeText(container.innerText);
    for (final prefix in _candidatePrefixes(label)) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length).trim();
        break;
      }
    }
    text = text.replaceFirst(RegExp(r'^[\]\)）:：、.]+'), '').trim();
    if (text.isEmpty) {
      return null;
    }
    return text.length <= 500 ? text : '${text.substring(0, 500)}…';
  }

  static List<String> _candidatePrefixes(String label) {
    final text = label.trim();
    if (text.isEmpty) {
      return const <String>[];
    }
    var core = text;
    while (core.isNotEmpty && '([（'.contains(core[0])) {
      core = core.substring(1);
    }
    while (core.isNotEmpty && ')]）'.contains(core[core.length - 1])) {
      core = core.substring(0, core.length - 1);
    }
    core = core.trim();
    return <String>{
      text,
      if (core.isNotEmpty) core,
      if (core.isNotEmpty) '($core)',
      if (core.isNotEmpty) '（$core）',
      if (core.isNotEmpty) '$core)',
      if (core.isNotEmpty) '$core）',
    }.toList(growable: false);
  }

  static String _epubType(XmlElement element) {
    final values = <String>[];
    for (final attribute in element.attributes) {
      if (attribute.name.local == 'type' &&
          (attribute.name.prefix == 'epub' ||
              attribute.value.contains('noteref') ||
              attribute.value.contains('footnote') ||
              attribute.value.contains('endnote'))) {
        values.add(attribute.value);
      }
    }
    return values.join(' ');
  }

  static List<String> _classes(XmlElement element) =>
      (element.getAttribute('class') ?? '')
          .split(RegExp(r'\s+'))
          .where((value) => value.isNotEmpty)
          .toList(growable: false);

  static bool _hasAncestor(XmlElement element, String tag) {
    var parent = element.parent;
    while (parent is XmlElement) {
      if (parent.name.local == tag) {
        return true;
      }
      parent = parent.parent;
    }
    return false;
  }

  static String _resolvePath(String href, String baseDir, String selfPath) {
    if (href.isEmpty) {
      return selfPath;
    }
    final decoded = _decode(href);
    final normalized = decoded.startsWith('/')
        ? _normalize(decoded)
        : _normalize(p.posix.join(baseDir, decoded));
    return normalized;
  }

  static String _decode(String value) {
    if (!value.contains('%')) {
      return value;
    }
    try {
      return Uri.decodeFull(value);
    } on FormatException {
      return value;
    }
  }

  static String _normalizeText(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _sanitizeEntities(String text) =>
      text.replaceAllMapped(RegExp(r'&([a-zA-Z][a-zA-Z0-9]+);'), (match) {
        const known = <String, String>{
          'amp': '&',
          'lt': '<',
          'gt': '>',
          'quot': '"',
          'apos': "'",
          'nbsp': ' ',
        };
        return known[match[1]] ?? match[0]!;
      });

  static String _stripBom(String text) =>
      text.startsWith('\uFEFF') ? text.substring(1) : text;

  static String _dirOf(String path) {
    final dir = p.posix.dirname(path.replaceAll('\\', '/'));
    return dir == '.' ? '' : dir;
  }

  static String _normalize(String path) {
    var result = path.replaceAll('\\', '/');
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    return p.posix.normalize(result);
  }
}
