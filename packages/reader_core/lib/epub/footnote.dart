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
  numberedSequence,
  unresolved,
}

/// 一条注释锚点：正文中的引用 → 注释目标。
class FootnoteAnchor {
  /// 创建锚点。
  const FootnoteAnchor({
    required this.sourceSpine,
    required this.referenceKey,
    required this.href,
    required this.label,
    required this.kind,
    required this.targetSpine,
    required this.strategy,
    this.sourceId,
    this.targetId,
    this.noteText,
    this.noteImages = const <String>[],
    this.crossDocument = false,
    this.heuristicReference = false,
    this.definitionId,
  });

  /// 引用所在 spine。
  final int sourceSpine;

  /// 正文引用节点的稳定匹配键。
  ///
  /// XHTML 解析与排版聚合使用两棵节点树；键由标签、属性和可见文字组成，
  /// 让聚合出的行内标记无需依赖 XML 解析器的源码偏移即可找回注释正文。
  final String referenceKey;

  /// 原始 href。
  final String href;

  /// 引用文字（如 `[1]`）。
  final String label;

  /// 注释类型。
  final NoteKind kind;

  /// 引用元素或紧邻前置空锚点的 id。
  final String? sourceId;

  /// 目标所在 spine；未解析为 -1。
  final int targetSpine;

  /// 目标元素 id；按文字前缀兜底时可能为空。
  final String? targetId;

  /// 目标注释容器文字。
  final String? noteText;

  /// 目标注释内的图片（ZIP 内绝对路径）。
  final List<String> noteImages;

  /// 是否跨文档。
  final bool crossDocument;

  /// 引用本身只有 `<sup>`、数字注号等弱特征，需目标也像注释才接收。
  final bool heuristicReference;

  /// 注释定义容器 id；目标 id 在内部节点时用于隐藏整个定义块。
  final String? definitionId;

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

typedef _CompoundNoteId = ({String file, String number, bool backlink});
typedef _RecoveredNote = ({
  FootnoteDocument document,
  XmlElement element,
  XmlElement container,
});

/// 注释锚点解析：不修改原书 DOM。
abstract final class FootnoteParser {
  static final RegExp _referenceAttributePattern = RegExp(
    r'\b(?:href|title)\s*=',
    caseSensitive: false,
  );
  static final RegExp _numberedNoteIdPattern = RegExp(
    r'^(note|noteBack)_(\d+)$',
    caseSensitive: false,
  );

  /// 快速判断章节源码是否可能包含注释入口。
  ///
  /// 完整解析一章 XML 并遍历全部节点成本不低。普通章节通常没有链接、注号
  /// 属性或阅读器图片注类名；先做保守的文本判定，可跳过这类章节的第二次
  /// XML 解析。命中任一特征仍走完整解析，避免损失注释兼容性。
  static bool mayContainReferences(String xhtml) {
    final lower = xhtml.toLowerCase();
    if (_referenceAttributePattern.hasMatch(xhtml)) {
      return true;
    }
    for (final marker in const <String>[
      'data-wr-footernote',
      'reader_footer_note',
      'js_readerfooternote',
      'data-reeden-footnote-body',
      'zy-footnote',
      'duokan-footnote',
      'qqreader-footnote',
      'zhangyue-footnote',
      'epub-footnote',
    ]) {
      if (lower.contains(marker)) {
        return true;
      }
    }
    return false;
  }

  /// 生成正文引用节点的稳定匹配键。
  static String referenceKey(
    String tag,
    Map<String, String> attributes,
    String text,
  ) {
    const keys = <String>[
      'id',
      'href',
      'class',
      'role',
      'epub:type',
      'title',
      'alt',
      'data-wr-footernote',
      'reader_footer_note',
      'js_readerFooterNote',
      'data-reeden-footnote-body',
      'zy-footnote',
    ];
    final normalized = <String, String>{
      for (final entry in attributes.entries)
        entry.key.toLowerCase(): entry.value,
    };
    final parts = <String>[tag.toLowerCase()];
    for (final key in keys) {
      parts.add('$key=${normalized[key.toLowerCase()] ?? ''}');
    }
    parts.add('text=${_normalizeText(text)}');
    return parts.join('\u001f');
  }

  /// 是否为返回正文的反向链接，不应作为注释入口。
  static bool isBacklink(String tag, Map<String, String> attributes) {
    final type = (attributes['epub:type'] ?? '').toLowerCase();
    final role = (attributes['role'] ?? '').toLowerCase();
    final classes = (attributes['class'] ?? '').toLowerCase().split(
      RegExp(r'\s+'),
    );
    return type.contains('backlink') ||
        role == 'doc-backlink' ||
        classes.contains('duokan-footnote-back') ||
        classes.contains('footnote-backref');
  }

  /// 是否为可直接显示的注释入口（不含无 href 的普通链接）。
  static bool isDirectReference(String tag, Map<String, String> attributes) {
    if (isBacklink(tag, attributes)) {
      return false;
    }
    if (_directContent(tag, attributes) != null) {
      return true;
    }
    if (_directImageSource(attributes) != null) {
      return true;
    }
    return _isImageNoteReference(tag, attributes);
  }

  /// 是否为注释定义容器（注释正文在阅读页中应隐藏）。
  static bool isDefinitionElement(String tag, Map<String, String> attributes) {
    final lowerTag = tag.toLowerCase();
    if (const <String>{
      'a',
      'img',
      'image',
      'span',
      'sup',
      'sub',
    }.contains(lowerTag)) {
      return false;
    }
    final type = (attributes['epub:type'] ?? '').toLowerCase();
    final role = (attributes['role'] ?? '').toLowerCase();
    final classes = (attributes['class'] ?? '')
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .toSet();
    if (type.split(RegExp(r'\s+')).contains('footnotes') ||
        type.contains('endnotes') ||
        type == 'footnote' ||
        type == 'endnote' ||
        type == 'rearnote' ||
        role == 'doc-footnote' ||
        role == 'doc-endnote' ||
        role == 'doc-endnotes') {
      return true;
    }
    if (classes.contains('duokan-footnote-content') ||
        classes.contains('duokan-footnote-item') ||
        classes.contains('reeden-footnote-content') ||
        classes.contains('reeden-footnote-item') ||
        classes.contains('qqreader-footnote') ||
        classes.contains('zhangyue-footnote') ||
        classes.contains('epub-footnote') ||
        classes.contains('footnotes') ||
        classes.contains('endnotes')) {
      return true;
    }
    if (lowerTag == 'aside' &&
        (classes.contains('footnote') ||
            classes.contains('endnote') ||
            _noteLikeId(attributes['id']))) {
      return true;
    }
    return const <String>{'li', 'dd', 'div', 'section'}.contains(lowerTag) &&
        _noteLikeId(attributes['id']) &&
        (classes.any((value) => value.contains('footnote')) ||
            classes.any((value) => value.contains('endnote')));
  }

  /// 解析 href 所指向的 ZIP 内路径；无 `#fragment` 时返回 null。
  static String? targetPathOf(FootnoteAnchor anchor, String sourcePath) {
    final hash = anchor.href.indexOf('#');
    if (hash < 0) {
      return null;
    }
    return _resolvePath(
      anchor.href.substring(0, hash),
      _dirOf(sourcePath),
      sourcePath,
    );
  }

  /// 按链接、复合片段及紧随章节的编号线索加载候选，不扫描整书正文。
  /// 有效锚点优先；候选在 resolve 中通过回链或同号定义序列确认。
  static Set<String> targetPaths(
    FootnoteDocument source,
    Iterable<String> availablePaths, {
    String? followingPath,
  }) {
    final paths = <String>{};
    final hints = <String>{};
    for (final anchor in source.anchors) {
      final path = targetPathOf(anchor, source.path);
      if (path != null) paths.add(path);
      final hint = _compoundReference(source, anchor);
      if (hint != null) hints.add(hint.file);
    }
    if (hints.isNotEmpty) {
      for (final path in availablePaths) {
        if (hints.any((hint) => p.posix.basename(path).endsWith(hint))) {
          paths.add(path);
        }
      }
    }
    // 多个编号入口被转换成同一个章首链接时，只补读紧随的候选定义章。
    if (followingPath != null && _numberedReferences(source).isNotEmpty) {
      paths.add(followingPath);
    }
    return paths;
  }

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

    final labels = _splitReferenceLabels(document);
    final anchors = <FootnoteAnchor>[];
    for (final element in document.descendants.whereType<XmlElement>()) {
      final tag = element.name.local.toLowerCase();
      final attributes = _attributesOf(element);
      if (isBacklink(tag, attributes)) {
        continue;
      }
      if (!attributes.containsKey('href') && _hasAncestor(element, 'a')) {
        continue;
      }
      final href = attributes['href']?.trim() ?? '';
      final hash = href.indexOf('#');
      final hasFragment = hash >= 0 && hash < href.length - 1;
      final directContent =
          _directContent(tag, attributes) ??
          (tag == 'a' ? _nestedDirectContent(element) : null);
      final directImage = _isImageNoteReference(tag, attributes);
      final contentAction =
          attributes['data-reader-action'] == 'true' && href.isNotEmpty;
      final directImageSource =
          _directImageSource(attributes) ??
          (tag == 'a' ? _nestedDirectImageSource(element) : null);
      if (!hasFragment &&
          directContent == null &&
          !directImage &&
          !contentAction &&
          directImageSource == null) {
        continue;
      }
      if (_insideDefinition(element)) continue;
      final targetPath = hasFragment
          ? targetPathOf(
              FootnoteAnchor(
                sourceSpine: spineIndex,
                referenceKey: '',
                href: href,
                label: '',
                kind: NoteKind.link,
                targetSpine: -1,
                strategy: AnchorStrategy.unresolved,
              ),
              path,
            )
          : null;
      final fragment = hasFragment ? href.substring(hash + 1) : '';
      final text = _normalizeText(element.innerText);
      final label = labels[element] ?? text;
      final sourceId = _referenceId(element);
      final kind = _kindOf(element, fragment, null);
      final imageNote = directImage ? attributes['alt']?.trim() : null;
      final directText = directContent ?? imageNote;
      final noteImages = directImageSource == null
          ? const <String>[]
          : <String>[_resolveImageSource(directImageSource, path)];
      anchors.add(
        FootnoteAnchor(
          sourceSpine: spineIndex,
          referenceKey: referenceKey(tag, attributes, text),
          href: href,
          label: label,
          kind: contentAction
              ? NoteKind.link
              : directText != null || directImageSource != null
              ? NoteKind.footnote
              : kind,
          sourceId: sourceId == null || sourceId.isEmpty ? null : sourceId,
          targetSpine: -1,
          targetId: null,
          noteText: directText,
          noteImages: noteImages,
          strategy: AnchorStrategy.unresolved,
          crossDocument: targetPath != null && targetPath != path,
          heuristicReference: _isHeuristicReference(element, label),
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

  /// 括号与数字可被拆进相邻的 a/b/sup；仅合并同一块内、同 id/href 的连续注号标签。
  static Map<XmlElement, String> _splitReferenceLabels(XmlDocument document) {
    final labels = <XmlElement, String>{};
    final group = <XmlElement>[];
    void flush() {
      final label = group.map((element) => element.innerText).join();
      if (group.length > 1 && RegExp(r'^\[\d+\]$').hasMatch(label)) {
        for (final element in group) {
          labels[element] = label;
        }
      }
      group.clear();
    }

    for (final node in document.descendants) {
      if (node is XmlText) {
        if (node.value.trim().isNotEmpty &&
            node.parentElement?.name.local != 'a' &&
            !(node.parentElement != null &&
                _hasAncestor(node.parentElement!, 'a'))) {
          flush();
        }
      } else if (node is XmlElement && node.name.local == 'a') {
        final previous = group.lastOrNull;
        if (previous != null &&
            (previous.getAttribute('id') != node.getAttribute('id') ||
                previous.getAttribute('href') != node.getAttribute('href') ||
                !identical(_referenceBlock(previous), _referenceBlock(node)))) {
          flush();
        }
        if ((node.getAttribute('id') ?? '').isNotEmpty) group.add(node);
      } else if (node is XmlElement &&
          const {'br', 'img', 'image', 'object'}.contains(node.name.local)) {
        flush();
      }
    }
    flush();
    return labels;
  }

  static XmlElement? _referenceBlock(XmlElement element) {
    for (final parent in element.ancestors.whereType<XmlElement>()) {
      if (const {
        'p',
        'div',
        'li',
        'td',
        'h1',
        'h2',
        'h3',
        'h4',
        'body',
      }.contains(parent.name.local)) {
        return parent;
      }
    }
    return null;
  }

  /// 定义块内的无标记返回链接也不属于正文入口，保留其文字供注文读取。
  static bool _insideDefinition(XmlElement element) {
    var parent = element.parent;
    while (parent is XmlElement) {
      if (isDefinitionElement(parent.name.local, _attributesOf(parent))) {
        return true;
      }
      parent = parent.parent;
    }
    return false;
  }

  /// 在已解析的文档集合中解析锚点目标。
  static List<FootnoteAnchor> resolve({
    required FootnoteDocument source,
    required Map<String, FootnoteDocument> documents,
  }) {
    final resolved = <FootnoteAnchor>[];
    final numberedTargets = _numberedNoteTargets(source, documents);
    // 拆分注号的各字符共享同一恢复结果，避免逐字符重复扫描定义章。
    final compoundTargets = <(String?, String, String), _RecoveredNote?>{};
    for (final anchor in source.anchors) {
      final hash = anchor.href.indexOf('#');
      if (hash < 0) {
        resolved.add(
          _withTarget(
            anchor,
            -1,
            null,
            anchor.noteText,
            AnchorStrategy.unresolved,
          ),
        );
        continue;
      }
      final targetPath = _resolvePath(
        anchor.href.substring(0, hash),
        _dirOf(source.path),
        source.path,
      );
      final fragment = anchor.href.substring(hash + 1);
      var target = documents[targetPath];
      if (target == null) {
        resolved.add(
          _withTarget(anchor, -1, null, null, AnchorStrategy.unresolved),
        );
        continue;
      }

      String? targetId = fragment;
      var element = target.ids[fragment];
      var strategy = AnchorStrategy.directId;
      XmlElement? recoveredContainer;
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
        final recovered = compoundTargets.putIfAbsent((
          anchor.sourceId,
          anchor.href,
          anchor.label,
        ), () => _compoundBacklinkTarget(source, anchor, documents));
        if (recovered != null) {
          target = recovered.document;
          element = recovered.element;
          targetId = element.getAttribute('id');
          recoveredContainer = recovered.container;
          strategy = AnchorStrategy.backlink;
        }
      }

      final numbered = numberedTargets[anchor.referenceKey];
      if (numbered != null &&
          (element == null ||
              (!_isLikelyNoteTarget(element) &&
                  _pairedNoteContainer(source, anchor, target, element) ==
                      null))) {
        target = numbered.document;
        element = numbered.element;
        targetId = element.getAttribute('id');
        recoveredContainer = numbered.container;
        strategy = AnchorStrategy.numberedSequence;
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
      final pairedContainer =
          recoveredContainer ??
          (targetKind == NoteKind.link &&
                  anchor.kind == NoteKind.link &&
                  anchor.heuristicReference
              ? _pairedNoteContainer(source, anchor, target, element)
              : null);
      final kind = targetKind == NoteKind.endnote
          ? NoteKind.endnote
          : anchor.kind != NoteKind.link
          ? anchor.kind
          : targetKind != NoteKind.link
          ? targetKind
          : anchor.heuristicReference &&
                (_isLikelyNoteTarget(element) || pairedContainer != null)
          ? NoteKind.footnote
          : NoteKind.link;
      final container =
          pairedContainer ??
          _noteContainer(element, allowEnclosingBlock: kind != NoteKind.link);
      final definitionId = _definitionContainerId(element);
      final noteText = _noteText(container, anchor.label);
      final noteImages = _noteImages(container, target.path);
      resolved.add(
        FootnoteAnchor(
          sourceSpine: anchor.sourceSpine,
          referenceKey: anchor.referenceKey,
          href: anchor.href,
          label: anchor.label,
          kind: kind,
          sourceId: anchor.sourceId,
          targetSpine: target.spineIndex,
          targetId: targetId,
          noteText: anchor.noteText ?? noteText,
          noteImages: noteImages.isNotEmpty ? noteImages : anchor.noteImages,
          crossDocument: target.spineIndex != source.spineIndex,
          heuristicReference: anchor.heuristicReference,
          definitionId: definitionId,
          strategy: strategy,
        ),
      );
    }
    return resolved;
  }

  static String? _numberedId(String? value, {bool reference = false}) {
    final match = _numberedNoteIdPattern.firstMatch(value ?? '');
    if (match == null ||
        match[1]!.toLowerCase() != (reference ? 'noteback' : 'note')) {
      return null;
    }
    return match[2];
  }

  /// 同号 id、可见标签及共同的无注释语义目标形成一组断链入口。
  static Map<String, FootnoteAnchor> _numberedReferences(
    FootnoteDocument source,
  ) {
    final groups = <String, Map<String, FootnoteAnchor>>{};
    for (final anchor in source.anchors) {
      final number = _numberedId(anchor.sourceId, reference: true);
      if (number == null ||
          anchor.kind != NoteKind.link ||
          (anchor.label != number && anchor.label != '[$number]') ||
          targetPathOf(anchor, source.path) != source.path) {
        continue;
      }
      final hash = anchor.href.indexOf('#');
      final target = source.ids[_decode(anchor.href.substring(hash + 1))];
      if (target != null && _isLikelyNoteTarget(target)) continue;
      (groups[anchor.href] ??= {})[number] = anchor;
    }
    return groups.values.where((group) => group.length >= 2).singleOrNull ??
        const {};
  }

  /// 相邻章至少有两个同号段首定义才恢复；重复 id 或多组候选不猜测。
  static Map<String, _RecoveredNote> _numberedNoteTargets(
    FootnoteDocument source,
    Map<String, FootnoteDocument> documents,
  ) {
    final references = _numberedReferences(source);
    if (source.spineIndex < 0 || references.isEmpty) return const {};
    final target = documents.values
        .where((document) => document.spineIndex == source.spineIndex + 1)
        .singleOrNull;
    if (target == null) return const {};
    final definitions = _numberedDefinitions(target, references);
    return {
      for (final entry in definitions.entries)
        references[entry.key]!.referenceKey: (
          document: target,
          element: entry.value,
          container: _numberedNoteContents(_referenceBlock(entry.value)!),
        ),
    };
  }

  static Map<String, XmlElement> _numberedDefinitions(
    FootnoteDocument target,
    Map<String, FootnoteAnchor> references,
  ) {
    final groups = <XmlElement, Map<String, XmlElement>>{};
    for (final element in target.elements) {
      final number = _numberedId(element.getAttribute('id'));
      final anchor = references[number];
      if (anchor == null || _normalizeText(element.innerText) != anchor.label) {
        continue;
      }
      final block = _referenceBlock(element);
      final owner = block?.parentElement;
      if (owner == null ||
          !_startsContainer(element, block!) ||
          _noteText(block, anchor.label) == null) {
        continue;
      }
      final group = groups[owner] ??= {};
      if (group.containsKey(number)) return const {};
      group[number!] = element;
    }
    return groups.values.where((group) => group.length >= 2).singleOrNull ??
        const {};
  }

  /// 注文延续到下一条编号定义之前，复制节点以保留原 DOM 与后续章节。
  static XmlElement _numberedNoteContents(XmlElement first) {
    final nodes = <XmlNode>[];
    for (final node in first.parentElement!.children.skipWhile(
      (node) => !identical(node, first),
    )) {
      if (nodes.isNotEmpty &&
          node is XmlElement &&
          [
            node,
            ...node.descendants.whereType<XmlElement>(),
          ].any((element) => _numberedId(element.getAttribute('id')) != null)) {
        break;
      }
      nodes.add(node.copy());
    }
    return XmlElement(XmlName.parts('aside'), const [], nodes);
  }

  static FootnoteAnchor _withTarget(
    FootnoteAnchor anchor,
    int targetSpine,
    String? targetId,
    String? noteText,
    AnchorStrategy strategy,
  ) => FootnoteAnchor(
    sourceSpine: anchor.sourceSpine,
    referenceKey: anchor.referenceKey,
    href: anchor.href,
    label: anchor.label,
    kind: anchor.kind,
    sourceId: anchor.sourceId,
    targetSpine: targetSpine,
    targetId: targetId,
    noteText: noteText ?? anchor.noteText,
    noteImages: anchor.noteImages,
    crossDocument: targetSpine != anchor.sourceSpine && targetSpine >= 0,
    heuristicReference: anchor.heuristicReference,
    definitionId: anchor.definitionId,
    strategy: strategy,
  );

  static NoteKind _kindOf(
    XmlElement element,
    String fragment,
    XmlElement? target,
  ) {
    final type = _epubType(element);
    if (type.contains('noteref') || type == 'footnote') {
      return NoteKind.footnote;
    }
    if (type == 'endnote' || type == 'rearnote') {
      return NoteKind.endnote;
    }
    final role = (element.getAttribute('role') ?? '').toLowerCase();
    if (role == 'doc-noteref' || role == 'doc-footnote') {
      return NoteKind.footnote;
    }
    if (role == 'doc-endnote') {
      return NoteKind.endnote;
    }
    final classes = _classes(element);
    if (classes.any((c) => c.contains('noteref') || c.contains('footnote'))) {
      return NoteKind.footnote;
    }
    if (target != null) {
      return _kindOfElement(target, fragment);
    }
    return NoteKind.link;
  }

  static bool _isHeuristicReference(XmlElement element, String label) {
    final tag = element.name.local.toLowerCase();
    final alt = element.getAttribute('alt')?.trim() ?? '';
    return _hasAncestor(element, 'sup') ||
        RegExp(
          r'^(?:[*＊†‡]|[\[\(（〔［【]?\d+[\]\)）〕］】]?)$',
        ).hasMatch(label) ||
        (tag == 'img' && RegExp(r'^\d+$').hasMatch(alt));
  }

  static _CompoundNoteId? _compoundNoteId(String? value) {
    if (value == null) return null;
    final match = RegExp(
      r'^(.+\.(?:xhtml|html|htm))_(note|noteBack)_(\d+)$',
      caseSensitive: false,
    ).firstMatch(_decode(value));
    return match == null
        ? null
        : (
            file: match[1]!,
            number: match[3]!,
            backlink: match[2]!.toLowerCase() == 'noteback',
          );
  }

  static _CompoundNoteId? _compoundReference(
    FootnoteDocument source,
    FootnoteAnchor anchor,
  ) {
    if (!anchor.href.startsWith('#') ||
        source.ids.containsKey(_decode(anchor.href.substring(1)))) {
      return null;
    }
    final hint = _compoundNoteId(anchor.href.substring(1));
    final origin = _compoundNoteId(anchor.sourceId);
    if (hint == null ||
        origin == null ||
        hint.backlink ||
        origin.backlink ||
        hint.number != origin.number ||
        origin.file != p.posix.basename(source.path) ||
        (anchor.label != hint.number && anchor.label != '[${hint.number}]')) {
      return null;
    }
    return hint;
  }

  /// 文件名后缀只用于缩小候选；完整 id、段首同号及返回引用必须共同成立且唯一。
  /// 保留完整候选扫描以统一判断跨文件歧义；遇到多个有效目标时不恢复。
  static _RecoveredNote? _compoundBacklinkTarget(
    FootnoteDocument source,
    FootnoteAnchor anchor,
    Map<String, FootnoteDocument> documents,
  ) {
    final hint = _compoundReference(source, anchor);
    if (hint == null) return null;
    _RecoveredNote? result;
    for (final target in documents.values) {
      if (target.path == source.path ||
          !p.posix.basename(target.path).endsWith(hint.file)) {
        continue;
      }
      final containers = <XmlElement>{};
      for (final element in target.elements) {
        final id = _compoundNoteId(element.getAttribute('id'));
        if (id == null ||
            !id.backlink ||
            id.number != hint.number ||
            id.file != p.posix.basename(target.path)) {
          continue;
        }
        final container = _referenceBlock(element);
        if (container == null ||
            !containers.add(container) ||
            !_startsContainer(element, container) ||
            _noteText(container, '[${hint.number}]') == null ||
            !_hasCompoundReturn(source, anchor, container, id)) {
          continue;
        }
        if (result != null && !identical(result.container, container)) {
          return null;
        }
        result = (document: target, element: element, container: container);
      }
    }
    return result;
  }

  static bool _hasCompoundReturn(
    FootnoteDocument source,
    FootnoteAnchor reference,
    XmlElement container,
    _CompoundNoteId id,
  ) {
    final labels = <String, StringBuffer>{};
    for (final node in container.descendants.whereType<XmlElement>()) {
      if (node.name.local != 'a') continue;
      final href = node.getAttribute('href') ?? '';
      if (!href.startsWith('#')) continue;
      final origin = _compoundNoteId(node.getAttribute('id'));
      final hint = _compoundNoteId(href.substring(1));
      if (origin != id ||
          hint == null ||
          !hint.backlink ||
          hint.number != id.number ||
          !p.posix.basename(source.path).endsWith(hint.file)) {
        continue;
      }
      (labels[href] ??= StringBuffer()).write(_normalizeText(node.innerText));
    }
    return labels.values.any((label) => label.toString() == reference.label);
  }

  /// 一些 EPUB 将返回位置写在注号之前的独立空 a 元素上。
  static String? _referenceId(XmlElement element) {
    final own = element.getAttribute('id')?.trim();
    if (own != null && own.isNotEmpty) return own;
    final siblings = element.parent?.children;
    if (siblings == null) return null;
    for (var index = siblings.indexOf(element) - 1; index >= 0; index--) {
      final sibling = siblings[index];
      if (sibling is XmlText && sibling.value.trim().isEmpty) continue;
      if (sibling is! XmlElement ||
          sibling.name.local != 'a' ||
          sibling.getAttribute('href') != null ||
          sibling.children.any(
            (child) => child is! XmlText || child.value.trim().isNotEmpty,
          )) {
        return null;
      }
      final id = sibling.getAttribute('id')?.trim();
      return id == null || id.isEmpty ? null : id;
    }
    return null;
  }

  /// 无注释语义时，以段首定义锚点、相同注号和精确返回位置确认注文。
  /// 普通正文中的双向链接不能仅凭数字或目标 id 被隐藏。
  static XmlElement? _pairedNoteContainer(
    FootnoteDocument source,
    FootnoteAnchor anchor,
    FootnoteDocument target,
    XmlElement element,
  ) {
    final sourceId = anchor.sourceId;
    if (sourceId == null || anchor.label.isEmpty) return null;
    final container = _noteContainerOrNull(element, allowEnclosingBlock: true);
    if (container == null ||
        !_startsContainer(element, container) ||
        _noteText(container, anchor.label) == null) {
      return null;
    }
    for (final backlink in container.descendants.whereType<XmlElement>()) {
      if (backlink.name.local != 'a' ||
          _normalizeText(backlink.innerText) != anchor.label) {
        continue;
      }
      final href = backlink.getAttribute('href')?.trim() ?? '';
      final hash = href.indexOf('#');
      if (hash < 0 || _decode(href.substring(hash + 1)) != sourceId) continue;
      final path = _resolvePath(
        href.substring(0, hash),
        _dirOf(target.path),
        target.path,
      );
      if (path == source.path) return container;
    }
    return null;
  }

  static bool _startsContainer(XmlElement element, XmlElement container) {
    if (identical(element, container)) return true;
    for (final node in container.descendants) {
      if (identical(node, element)) return true;
      if (node is XmlText && node.value.trim().isNotEmpty) return false;
      if (node is XmlElement &&
          const {'img', 'image', 'svg', 'object'}.contains(node.name.local)) {
        return false;
      }
    }
    return false;
  }

  static bool _isLikelyNoteTarget(XmlElement element) {
    return _noteLikeId(element.getAttribute('id')) ||
        _noteContainerOrNull(element) != null;
  }

  static NoteKind _kindOfElement(XmlElement element, String fragment) {
    final type = _epubType(element);
    final role = (element.getAttribute('role') ?? '').toLowerCase();
    if (type.contains('endnote') ||
        type.contains('rearnote') ||
        role == 'doc-endnote' ||
        role == 'doc-endnotes') {
      return NoteKind.endnote;
    }
    if (type.contains('footnote') ||
        role == 'doc-footnote' ||
        (_classes(element).any(_isFootnoteClass) &&
            !element.name.local.endsWith('ref'))) {
      return NoteKind.footnote;
    }
    final ancestor = _noteContainerOrNull(element);
    if (ancestor != null &&
        (_hasNoteSemantics(ancestor) ||
            _noteLikeId(ancestor.getAttribute('id')))) {
      return _hasEndnoteSemantics(ancestor)
          ? NoteKind.endnote
          : NoteKind.footnote;
    }
    if (_noteLikeId(element.getAttribute('id'))) {
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
        final href = (anchor.getAttribute('href') ?? '').trim();
        if (anchor.name.local == 'a' &&
            (href == '#$sourceId' || href.endsWith('#$sourceId'))) {
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

  static String? _definitionContainerId(XmlElement element) {
    var current = element;
    for (var depth = 0; depth < 6; depth++) {
      final tag = current.name.local;
      if (tag == 'body') {
        break;
      }
      final id = current.getAttribute('id')?.trim();
      if (id != null &&
          id.isNotEmpty &&
          (_hasNoteSemantics(current) ||
              current != element &&
                  const <String>{
                    'aside',
                    'li',
                    'dd',
                    'td',
                    'blockquote',
                    'section',
                  }.contains(tag))) {
        return id;
      }
      final parent = current.parent;
      if (parent is! XmlElement) {
        break;
      }
      current = parent;
    }
    return null;
  }

  static XmlElement _noteContainer(
    XmlElement element, {
    bool allowEnclosingBlock = false,
  }) {
    return _noteContainerOrNull(
          element,
          allowEnclosingBlock: allowEnclosingBlock,
        ) ??
        element;
  }

  static XmlElement? _noteContainerOrNull(
    XmlElement element, {
    bool allowEnclosingBlock = false,
  }) {
    const blockTags = <String>{
      'article',
      'aside',
      'blockquote',
      'dd',
      'div',
      'dl',
      'dt',
      'figcaption',
      'figure',
      'li',
      'ol',
      'p',
      'section',
      'td',
      'th',
      'ul',
    };
    var current = element;
    for (var depth = 0; depth < 6; depth++) {
      if (current.name.local == 'body') {
        break;
      }
      if (_hasNoteSemantics(current) ||
          const <String>{
            'aside',
            'li',
            'p',
            'dd',
            'td',
            'blockquote',
            'section',
          }.contains(current.name.local)) {
        if (_hasNoteSemantics(current) ||
            _noteLikeId(current.getAttribute('id')) ||
            _hasBacklinkDescendant(current)) {
          return current;
        }
      }
      if (_classes(current).any(
        (value) =>
            value.contains('footnote-content') ||
            value.contains('footnote-item'),
      )) {
        return current;
      }
      if (allowEnclosingBlock && blockTags.contains(current.name.local)) {
        return current;
      }
      final parent = current.parent;
      if (parent is! XmlElement) {
        break;
      }
      current = parent;
    }
    return null;
  }

  static String? _noteText(XmlElement container, String label) {
    final buffer = StringBuffer();
    void visit(XmlNode node) {
      if (node is XmlText) {
        buffer.write(node.value);
        return;
      }
      if (node is! XmlElement ||
          isBacklink(node.name.local, _attributesOf(node))) {
        return;
      }
      final tag = node.name.local.toLowerCase();
      if (tag == 'br') {
        buffer.write('\n');
        return;
      }
      if (tag == 'img' || tag == 'image') {
        return;
      }
      final block = const <String>{
        'p',
        'div',
        'li',
        'aside',
        'section',
        'blockquote',
        'dd',
        'td',
        'ul',
        'ol',
      }.contains(tag);
      if (block && buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
        buffer.write('\n');
      }
      for (final child in node.children) {
        visit(child);
      }
      if (block && !buffer.toString().endsWith('\n')) {
        buffer.write('\n');
      }
    }

    for (final child in container.children) {
      visit(child);
    }
    var text = buffer
        .toString()
        .split('\n')
        .map(_normalizeText)
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();
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
    return text;
  }

  static List<String> _noteImages(XmlElement container, String targetPath) {
    final baseDir = _dirOf(targetPath);
    final result = <String>[];
    final candidates = <XmlElement>[
      container,
      ...container.descendants.whereType<XmlElement>(),
    ];
    for (final image in candidates) {
      if (image.name.local != 'img' && image.name.local != 'image') {
        continue;
      }
      final src =
          image.getAttribute('src') ??
          image.getAttribute('xlink:href') ??
          image.getAttribute('href');
      if (src == null || src.trim().isEmpty) {
        continue;
      }
      final resolved = _resolvePath(src.trim(), baseDir, targetPath);
      if (!result.contains(resolved)) {
        result.add(resolved);
      }
    }
    return List<String>.unmodifiable(result);
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

  static Map<String, String> _attributesOf(XmlElement element) => {
    for (final attribute in element.attributes)
      attribute.name.qualified: attribute.value,
  };

  static String? _directContent(String tag, Map<String, String> attributes) {
    for (final key in const <String>[
      'data-wr-footernote',
      'reader_footer_note',
      'js_readerFooterNote',
      'data-reeden-footnote-body',
      'zy-footnote',
    ]) {
      final value = attributes[key]?.trim();
      if (value != null && value.isNotEmpty && !_looksLikeImageSource(value)) {
        return value;
      }
    }
    if (tag.toLowerCase() == 'a') {
      final title = attributes['title']?.trim();
      if (title != null && title.isNotEmpty) {
        return title;
      }
    }
    return null;
  }

  static String? _nestedDirectContent(XmlElement element) {
    for (final child in element.descendants.whereType<XmlElement>()) {
      final content = _directContent(child.name.local, _attributesOf(child));
      if (content != null) {
        return content;
      }
    }
    return null;
  }

  static String? _nestedDirectImageSource(XmlElement element) {
    for (final child in element.descendants.whereType<XmlElement>()) {
      final source = _directImageSource(_attributesOf(child));
      if (source != null) {
        return source;
      }
    }
    return null;
  }

  static String? _directImageSource(Map<String, String> attributes) {
    for (final key in const <String>[
      'data-wr-footernote',
      'reader_footer_note',
      'js_readerFooterNote',
      'zy-footnote',
    ]) {
      final value = attributes[key]?.trim();
      if (value != null && _looksLikeImageSource(value)) {
        return value;
      }
    }
    return null;
  }

  static bool _looksLikeImageSource(String value) {
    final lower = value.toLowerCase();
    if (lower.startsWith('file:')) {
      return true;
    }
    if (lower.contains(RegExp(r'\s'))) {
      return false;
    }
    return RegExp(r'\.(?:apng|avif|bmp|gif|jpe?g|png|svg|webp)(?:[?#].*)?$')
        .hasMatch(lower);
  }

  /// 多看、QQ/微信读书、掌阅的弹注图标都把正文放在 `alt` 中。
  static bool _isImageNoteReference(
    String tag,
    Map<String, String> attributes,
  ) {
    if (tag.toLowerCase() != 'img' ||
        (attributes['alt']?.trim().isEmpty ?? true)) {
      return false;
    }
    final classes = (attributes['class'] ?? '')
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .toSet();
    return const <String>{
      'duokan-footnote',
      'qqreader-footnote',
      'zhangyue-footnote',
      'epub-footnote',
    }.any(classes.contains);
  }

  static String _resolveImageSource(String source, String documentPath) {
    final value = source.toLowerCase().startsWith('file:')
        ? source.substring(5)
        : source;
    return _resolvePath(value, _dirOf(documentPath), documentPath);
  }

  static bool _isFootnoteClass(String value) {
    final lower = value.toLowerCase();
    return lower.contains('footnote') ||
        lower.contains('endnote') ||
        lower.contains('rearnote') ||
        lower == 'noteref' ||
        lower == 'doc-noteref';
  }

  static bool _hasNoteSemantics(XmlElement element) {
    final type = _epubType(element);
    final role = (element.getAttribute('role') ?? '').toLowerCase();
    return _isNoteType(type) ||
        role == 'doc-footnote' ||
        role == 'doc-endnote' ||
        role == 'doc-endnotes' ||
        _classes(element).any(_isFootnoteClass);
  }

  static bool _isNoteType(String value) {
    final types = value.toLowerCase().split(RegExp(r'\s+')).toSet();
    return types.any(
      (type) => const <String>{
        'footnote',
        'footnotes',
        'endnote',
        'endnotes',
        'rearnote',
      }.contains(type),
    );
  }

  static bool _hasEndnoteSemantics(XmlElement element) {
    final type = _epubType(element);
    final role = (element.getAttribute('role') ?? '').toLowerCase();
    return type.contains('endnote') ||
        type.contains('rearnote') ||
        role == 'doc-endnote' ||
        role == 'doc-endnotes';
  }

  static bool _hasBacklinkDescendant(XmlElement element) {
    for (final child in element.descendants.whereType<XmlElement>()) {
      if (isBacklink(child.name.local, _attributesOf(child))) {
        return true;
      }
    }
    return false;
  }

  static bool _noteLikeId(String? value) {
    final id = value?.trim().toLowerCase() ?? '';
    return id.isNotEmpty &&
        RegExp(
          r'^(?:fn|redfn|n|note|footnote|endnote|rearnote)[\s._:-]*\d+(?:[\s._:-]*\d+)*$',
        ).hasMatch(id);
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
      text.replaceAll('\uFFFC', '').replaceAll(RegExp(r'\s+'), ' ').trim();

  // XML 保留实体必须交给解析器解码，提前展开会把正文变成标签或截断属性。
  // 这里只兼容 XML 未内建的 HTML 空格实体，沿用原来的空格口径。
  static String _sanitizeEntities(String text) =>
      text.replaceAll('&nbsp;', ' ');

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
