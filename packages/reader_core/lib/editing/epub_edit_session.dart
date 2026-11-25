import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart' as xml;

import '../epub/epub_document.dart';
import '../epub/epub_chapter_source.dart';
import '../epub/chapter/chapter_preview_cache.dart';
import '../epub/chapter/chapter_structure.dart';
import '../epub/opf.dart';
import '../parser/document_parser.dart';
import '../parser/cfi_children.dart';
import '../position/cfi.dart';
import '../source/format_opener.dart';
import 'editable_document.dart';
import 'edit_text_encoding.dart';
import 'edit_validation.dart';
import 'edit_change_classifier.dart';
import 'edit_reference_validation.dart';

class EpubEditResource {
  const EpubEditResource(this.path, this.mediaType, this.size);
  final String path;
  final String mediaType;
  final int size;
}

class EpubEditSummary {
  const EpubEditSummary({required this.changedPaths, required this.cssOnly});
  final Set<String> changedPaths;
  final bool cssOnly;
  int get count => changedPaths.length;
}

class EpubEditHistoryEntry {
  const EpubEditHistoryEntry(this.label, this.changedPaths);
  final String label;
  final Set<String> changedPaths;
}

class EpubEditChange extends EpubEditHistoryEntry {
  const EpubEditChange(super.label, super.changedPaths, this.revision);
  final int revision;
}

/// 原归档只读，事务只保留修改条目；宿主负责草稿文件与书架替换。
class EpubEditSession {
  EpubEditSession._(
    this.baseFile,
    this._document,
    this.baseDigest,
    this._baseWarnings,
  );
  static const maxHistoryEntries = 100;
  static const maxHistoryBytes = 32 * 1024 * 1024;

  static Future<EpubEditSession> open(
    File file, {
    Map<String, dynamic>? draft,
    Uint8List Function(String reference)? readBlob,
  }) async {
    final opened = await openEpubFile(file);
    final document = opened.document;
    if (document == null) {
      throw EpubEditException(opened.report.message ?? 'EPUB 无法打开');
    }
    try {
      final digest = (await sha256.bind(file.openRead()).first).toString();
      final session = EpubEditSession._(
        file.absolute,
        document,
        digest,
        List.of(opened.report.warnings),
      );
      session._metadata = readEditorMetadata(
        document.archive.readBytes(editorMetadataPath),
      );
      final stylesheet = session._metadata['classStylesheet'] as String?;
      if (stylesheet != null && !document.archive.contains(stylesheet)) {
        session._metadata.clear();
      }
      if (draft != null) session._restoreDraft(draft, readBlob);
      return session;
    } catch (_) {
      document.archive.close();
      rethrow;
    }
  }

  final File baseFile;
  final String baseDigest;
  final EpubDocumentImpl _document;
  final List<String> _baseWarnings;
  final _events = StreamController<EpubEditChange>.broadcast(sync: true);
  Map<String, Uint8List?> _overrides = {};
  Map<String, dynamic> _metadata = {};
  final _undo = <_EditState>[];
  final _previewCache = ChapterPreviewCache<ChapterStructure>();
  final _resourceDigests = Expando<String>();
  final _redo = <_EditState>[];
  int _revision = 0;
  int get revision => _revision;
  int get previewCacheEntryCount => _previewCache.length;
  bool _closed = false;
  bool _inTransaction = false;
  int historyDiscarded = 0;
  late OpfPackage _lastPackage = _document.package;
  late String _lastOpfPath = _document.opfPath;
  int _summaryRevision = -1;
  EpubEditSummary? _summary;
  List<String> _validationWarnings = const [];
  List<String> get validationWarnings => List.unmodifiable(_validationWarnings);

  String get opfPath {
    if (!_overrides.containsKey('META-INF/container.xml')) {
      return _lastOpfPath = _document.opfPath;
    }
    final bytes = readBytes('META-INF/container.xml');
    if (bytes == null) return _lastOpfPath;
    try {
      final path = normalizePath(validateEditContainer(bytes));
      if (readBytes(path) != null) _lastOpfPath = path;
    } on Exception {
      return _lastOpfPath;
    }
    return _lastOpfPath;
  }

  Stream<EpubEditChange> get changes => _events.stream;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get isClosed => _closed;
  Map<String, dynamic> get metadata =>
      Map.unmodifiable(_copyMetadata(_metadata));
  Set<String> get changedPaths => Set.unmodifiable(_overrides.keys);
  List<EpubEditHistoryEntry> get history =>
      List.unmodifiable(_undo.map((state) => state.entry));
  EpubEditSummary get summary {
    if (_summaryRevision != revision) {
      _summary = EpubEditSummary(
        changedPaths: changedPaths,
        cssOnly: EditChangeClassifier(
          opfPath,
          _document.archive.readBytes,
          readBytes,
        ).cssOnly(changedPaths),
      );
      _summaryRevision = revision;
    }
    return _summary!;
  }

  /// 新的 map 与字节副本可交给草稿持久层或 writer，不暴露内部可变状态。
  Map<String, Uint8List?> get resourceOverrides => {
    for (final entry in _overrides.entries)
      entry.key: entry.value == null ? null : Uint8List.fromList(entry.value!),
  };

  List<String> get spinePaths => [
    for (final item in _package.spine) resolvePath(item.href, opfPath),
  ];
  List<String> get previewPaths {
    final reading = spinePaths;
    return [
      ...reading,
      for (final file in resources)
        if ((file.mediaType == 'application/xhtml+xml' ||
                file.mediaType == 'text/html') &&
            !reading.contains(file.path))
          file.path,
    ];
  }

  OpfPackage get _package {
    try {
      final package = OpfParser.parse(readText(opfPath));
      if (package.manifest.isNotEmpty &&
          package.spine.isNotEmpty &&
          !package.warnings.any((note) => note.startsWith('spine 引用'))) {
        _lastPackage = package;
      }
    } catch (_) {
      // 源码草稿允许暂时非法，文件树继续使用最后有效的包清单。
    }
    return _lastPackage;
  }

  List<EpubEditResource> get resources {
    final types = {
      for (final item in _package.manifest)
        resolvePath(item.href, opfPath): item.mediaType,
    };
    final names = {..._document.archive.names, ..._overrides.keys};
    return [
      for (final name in names)
        if (!_overrides.containsKey(name) || _overrides[name] != null)
          EpubEditResource(
            name,
            types[name] ?? '',
            _overrides[name]?.length ??
                _document.archive.uncompressedSizeOf(name) ??
                0,
          ),
    ];
  }

  Uint8List? readBytes(String path) {
    _checkOpen();
    path = normalizePath(path);
    final bytes = _overrides.containsKey(path)
        ? _overrides[path]
        : _document.archive.readBytes(path);
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  String readText(String path) {
    final bytes = readBytes(path);
    if (bytes == null) throw EpubEditException('资源不存在：$path');
    return EditTextEncoding.detect(bytes).decode(bytes);
  }

  EditableDocument editableDocument(String path) => EditableDocument.parse(
    readText(path),
    path: normalizePath(path),
    revision: revision,
  );

  EditableElementRef resolveEditableElement(
    int spineIndex,
    String cfi, {
    bool preview = false,
  }) {
    final paths = preview ? previewPaths : spinePaths;
    if (spineIndex < 0 || spineIndex >= paths.length) {
      throw const EpubEditException('章节不存在');
    }
    final target = EpubCfi.parse(cfi);
    if (target == null || target.isRange) {
      throw const EpubEditException('需要精确的点 CFI');
    }
    final path = paths[spineIndex];
    final editable = editableDocument(path);
    final parsed = DocumentParser.parse(
      xhtml: editable.source,
      spineIndex: spineIndex,
    );
    if (parsed.parseDiagnostics.isNotEmpty) {
      throw const EpubEditException('容错文档不能按 CFI 自动写入');
    }
    final node = parsed.nodeAtCfi(target);
    if (node == null ||
        !_sameSteps(node.cfi, target) ||
        (target.charOffset != null &&
            (node is! ParsedText || target.charOffset! > node.text.length))) {
      throw const EpubEditException('CFI 不再精确匹配原文');
    }
    final element = editable.elementAtOffset(node.start);
    if (element == null) throw const EpubEditException('没有可靠的源码元素');
    return element;
  }

  void checkElement(EditableElementRef element) {
    if (editDigest(readText(element.path)) != element.sourceDigest) {
      throw const EpubEditException('原文已变化，请重新选择元素');
    }
  }

  /// 从原始元素范围生成正文 CFI，并反向核验，拒绝容错或过期映射。
  String cfiForElement(EditableElementRef element, {bool preview = false}) {
    checkElement(element);
    final spine = (preview ? previewPaths : spinePaths).indexOf(element.path);
    if (spine < 0) throw const EpubEditException('此文件不在阅读顺序中');
    final parsed = DocumentParser.parse(
      xhtml: readText(element.path),
      spineIndex: spine,
    );
    if (parsed.parseDiagnostics.isNotEmpty) {
      throw const EpubEditException('容错文档不能精确定位到预览');
    }
    final pending = <ParsedElement>[parsed.root];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (node.start == element.start && node.tag == element.tag) {
        final cfi = node.cfi.serialize();
        final resolved = resolveEditableElement(spine, cfi, preview: preview);
        if (resolved.start == element.start && resolved.end == element.end) {
          return cfi;
        }
        break;
      }
      pending.addAll(node.children.whereType<ParsedElement>());
    }
    throw const EpubEditException('光标不在可精确定位的正文元素中');
  }

  String cfiForSourceOffset(String path, int offset, {bool preview = false}) {
    path = normalizePath(path);
    final spine = (preview ? previewPaths : spinePaths).indexOf(path);
    if (spine < 0) throw const EpubEditException('此文件不在阅读顺序中');
    final source = readText(path);
    RangeError.checkValueInInterval(offset, 0, source.length, 'offset');
    final parsed = DocumentParser.parse(xhtml: source, spineIndex: spine);
    if (parsed.parseDiagnostics.isNotEmpty) {
      throw const EpubEditException('容错文档不能精确定位到预览');
    }
    for (final text in parsed.textNodes) {
      if (offset >= text.start && offset <= text.end) {
        return text.cfi
            .withCharOffset(_sourceTextOffset(source, text, offset))
            .serialize();
      }
    }
    final element = editableDocument(path).elementAtOffset(offset);
    if (element == null) {
      throw const EpubEditException('光标不在可精确定位的正文元素中');
    }
    return cfiForElement(element, preview: preview);
  }

  void transaction(
    String label,
    void Function(EpubEditTransaction tx) apply, {
    bool validate = true,
  }) {
    _checkOpen();
    if (_inTransaction) throw const EpubEditException('不能嵌套编辑事务');
    _inTransaction = true;
    try {
      final tx = EpubEditTransaction._(this);
      apply(tx);
      if (validate) tx._validate();
      _commit(label, tx);
    } finally {
      _inTransaction = false;
    }
  }

  void replaceWith(EpubEditSession candidate, {required String label}) {
    _checkOpen();
    candidate.validate();
    final beforePaths = resources.map((resource) => resource.path).toSet();
    final afterPaths = candidate.resources
        .map((resource) => resource.path)
        .toSet();
    final writes = <String, Uint8List?>{};
    for (final path in {...beforePaths, ...afterPaths}) {
      final before = readBytes(path);
      final after = candidate.readBytes(path);
      if (!listEquals(before, after)) writes[path] = after;
    }
    validateEditPackage(
      candidate.readText(candidate.opfPath),
      candidate.opfPath,
      original: readText(opfPath),
    );
    EditReferenceValidator(
      readBytes,
      candidate.readBytes,
      afterPaths,
      beforePaths,
    ).validate(writes.keys.toSet());
    transaction(label, (tx) {
      for (final entry in writes.entries) {
        if (entry.value case final bytes?) {
          tx.writeBytes(entry.key, bytes);
        } else {
          tx.remove(entry.key);
        }
      }
      tx.metadata
        ..clear()
        ..addAll(candidate.metadata);
    });
  }

  void _commit(String label, EpubEditTransaction tx) {
    final metadata = _copyMetadata(tx.metadata);
    if (tx._writes.isEmpty && jsonEncode(metadata) == jsonEncode(_metadata)) {
      return;
    }
    final paths = Set<String>.unmodifiable(tx._writes.keys);
    final before = _EditState(
      Map.of(_overrides),
      _copyMetadata(_metadata),
      EpubEditHistoryEntry(label, paths),
    );
    _overrides = {..._overrides, ...tx._writes};
    _metadata = metadata;
    _undo.add(before);
    _redo.clear();
    _pruneHistory();
    _notify(label, paths);
  }

  void undo() => _moveHistory(_undo, _redo, '撤销');
  void redo() => _moveHistory(_redo, _undo, '重做');
  void _moveHistory(List<_EditState> from, List<_EditState> to, String action) {
    _checkOpen();
    if (from.isEmpty) return;
    final next = from.removeLast();
    to.add(
      _EditState(Map.of(_overrides), _copyMetadata(_metadata), next.entry),
    );
    _overrides = Map.of(next.overrides);
    _metadata = _copyMetadata(next.metadata);
    _pruneHistory();
    _notify('$action：${next.entry.label}', next.entry.changedPaths);
  }

  void _notify(String label, Set<String> paths) {
    _revision += 1;
    _events.add(EpubEditChange(label, paths, revision));
  }

  Future<EpubChapterSource> createPreviewSource({
    ReaderOpenOptions options = const ReaderOpenOptions(),
    bool includeUnlistedHtml = false,
  }) {
    _checkOpen();
    validate();
    final overrides = resourceOverrides;
    if (includeUnlistedHtml && previewPaths.length != spinePaths.length) {
      overrides[opfPath] = utf8.encode(_previewPackage());
    }
    return EpubChapterSource.openFile(
      baseFile,
      contentWidth: options.contentWidth,
      contentHeight: options.contentHeight,
      style: options.style,
      trimTextEdges: options.trimTextEdges,
      contentVersion: '编辑:$baseDigest',
      resourceOverrides: overrides,
      previewCache: _previewCache,
      resourceVersions: {
        for (final entry in overrides.entries)
          entry.key: entry.value == null
              ? 'deleted'
              : (_resourceDigests[entry.value!] ??= sha256
                    .convert(entry.value!)
                    .toString()),
      },
    );
  }

  String _previewPackage() {
    final document = XmlDocument.parse(readText(opfPath));
    final manifest = document.descendants.whereType<XmlElement>().firstWhere(
      (node) => node.name.local == 'manifest',
    );
    final spine = document.descendants.whereType<XmlElement>().firstWhere(
      (node) => node.name.local == 'spine',
    );
    final reading = spinePaths.toSet();
    final ids = {
      for (final item in manifest.childElements.where(
        (node) => node.name.local == 'item',
      ))
        resolvePath(item.getAttribute('href')!, opfPath): item.getAttribute(
          'id',
        )!,
    };
    for (final path in previewPaths.where((path) => !reading.contains(path))) {
      spine.children.add(
        XmlElement(XmlName.parts('itemref', prefix: spine.name.prefix), [
          XmlAttribute(XmlName.parts('idref'), ids[path]!),
        ]),
      );
    }
    return document.toXmlString();
  }

  /// 预览和导出的强校验闸门；无效草稿仍可保存，但不能发布为 EPUB。
  void validate() {
    _checkOpen();
    final tx = EpubEditTransaction._(this).._writes.addAll(_overrides);
    tx._validate();
    final paths = resources.map((entry) => entry.path).toSet();
    final warnings = [
      ..._baseWarnings,
      ...validateEditPackage(
        readText(opfPath),
        opfPath,
        original: _document.archive.readString(opfPath),
      ),
    ];
    warnings.addAll(
      EditReferenceValidator(
        _document.archive.readBytes,
        readBytes,
        paths,
        _document.archive.names.toSet(),
      ).validate(changedPaths),
    );
    _validationWarnings = warnings;
  }

  int get historyBytes {
    final seen = HashSet<Uint8List>.identity()
      ..addAll(_overrides.values.whereType<Uint8List>());
    var bytes = 0;
    for (final state in [..._undo, ..._redo]) {
      bytes += utf8.encode(jsonEncode(state.metadata)).length;
      for (final value in state.overrides.values.whereType<Uint8List>()) {
        if (seen.add(value)) bytes += value.length;
      }
    }
    return bytes;
  }

  void _pruneHistory() {
    while (_undo.length + _redo.length > maxHistoryEntries ||
        historyBytes > maxHistoryBytes) {
      final oldest = _undo.isNotEmpty ? _undo : _redo;
      if (oldest.isEmpty) break;
      oldest.removeAt(0);
      historyDiscarded++;
    }
  }

  Map<String, dynamic> toDraft({
    String Function(String, Uint8List)? storeBlob,
  }) => {
    'version': 1,
    'baseDigest': baseDigest,
    'revision': revision,
    'metadata': _copyMetadata(_metadata),
    'entries': {
      for (final entry in _overrides.entries)
        entry.key: entry.value == null
            ? null
            : storeBlob == null
            ? {'base64': base64Encode(entry.value!)}
            : {'blob': storeBlob(entry.key, Uint8List.fromList(entry.value!))},
    },
  };

  void _restoreDraft(
    Map<String, dynamic> draft,
    Uint8List Function(String)? readBlob,
  ) {
    if (draft['version'] != 1 || draft['baseDigest'] != baseDigest) {
      throw const EpubEditException('草稿与原书版本不一致');
    }
    final entries = Map<String, dynamic>.from(draft['entries'] as Map);
    transaction('恢复草稿', (tx) {
      for (final entry in entries.entries) {
        if (entry.value == null) {
          tx.remove(entry.key);
          continue;
        }
        final data = Map<String, dynamic>.from(entry.value as Map);
        final blob = data['blob'] as String?;
        if (blob != null && readBlob == null) {
          throw const EpubEditException('草稿资源读取器缺失');
        }
        tx.writeBytes(
          entry.key,
          blob == null
              ? base64Decode(data['base64'] as String)
              : readBlob!(blob),
        );
      }
      tx.metadata.clear();
      tx.metadata.addAll(
        Map<String, dynamic>.from(draft['metadata'] as Map? ?? {}),
      );
    }, validate: false);
    _revision = (draft['revision'] as int? ?? 0) + 1;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _document.archive.close();
    _overrides.clear();
    _previewCache.clear();
    _undo.clear();
    _redo.clear();
    unawaited(_events.close());
  }

  void _checkOpen() {
    if (_closed) throw const EpubEditException('编辑会话已关闭');
  }
}

class EpubEditTransaction {
  EpubEditTransaction._(this._session)
    : metadata = _copyMetadata(_session._metadata);
  final EpubEditSession _session;
  final _writes = <String, Uint8List?>{};
  final Map<String, dynamic> metadata;

  Uint8List? readBytes(String path) {
    path = normalizePath(path);
    final bytes = _writes.containsKey(path)
        ? _writes[path]
        : _session.readBytes(path);
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  String readText(String path) {
    final bytes = readBytes(path);
    if (bytes == null) throw EpubEditException('资源不存在：$path');
    return EditTextEncoding.detect(bytes).decode(bytes);
  }

  void writeText(String path, String text) {
    final before = readBytes(path) ?? Uint8List(0);
    writeBytes(path, EditTextEncoding.detect(before).encode(text));
  }

  void writeBytes(String path, Uint8List bytes) =>
      _writes[normalizePath(path)] = Uint8List.fromList(bytes);
  void remove(String path) => _writes[normalizePath(path)] = null;

  void _validate() {
    for (final entry in _writes.entries) {
      final bytes = entry.value;
      if (bytes == null) continue;
      validateEditResource(entry.key, bytes);
      if (entry.key == 'META-INF/container.xml') {
        final path = normalizePath(validateEditContainer(bytes));
        if (readBytes(path) == null) {
          throw const EpubEditException('container.xml 指向不存在的 OPF 文件');
        }
      }
    }
    _copyMetadata(metadata);
  }
}

class _EditState {
  const _EditState(this.overrides, this.metadata, this.entry);
  final Map<String, Uint8List?> overrides;
  final Map<String, dynamic> metadata;
  final EpubEditHistoryEntry entry;
}

Map<String, dynamic> _copyMetadata(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

String normalizePath(String path) {
  final normalized = p.posix.normalize(path.replaceAll('\\', '/'));
  if (normalized == '.' ||
      normalized.startsWith('/') ||
      normalized == '..' ||
      normalized.startsWith('../') ||
      normalized.contains('\u0000')) {
    throw const EpubEditException('资源路径必须位于 EPUB 内');
  }
  return normalized;
}

String resolvePath(String href, String basePath) => normalizePath(
  p.posix.join(
    p.posix.dirname(basePath),
    // 清单可直接使用中文路径，先规范化为 ASCII URI 再解码已有转义。
    Uri.decodeComponent(Uri.parse(href.split('#').first).toString()),
  ),
);

bool _sameSteps(EpubCfi actual, EpubCfi expected) =>
    actual.spine == expected.spine &&
    actual.body == expected.body &&
    actual.itemref == expected.itemref &&
    actual.steps.length == expected.steps.length &&
    List.generate(
      actual.steps.length,
      (i) => actual.steps[i] == expected.steps[i],
    ).every((value) => value);

int _sourceTextOffset(String source, ParsedText text, int offset) {
  var length = 0;
  for (final event in xml.parseEvents(
    source,
    entityMapping: cfiEntityMapping,
    withLocation: true,
  )) {
    final cdata = event is xml.XmlCDATAEvent;
    if (event is! xml.XmlTextEvent && !cdata) continue;
    final start = event.start! + (cdata ? 9 : 0);
    final end = event.stop! - (cdata ? 3 : 0);
    if (end <= text.start) continue;
    if (start >= offset) break;
    var prefix = source.substring(start, offset.clamp(start, end));
    if (!cdata) {
      final entity = prefix.lastIndexOf('&');
      if (entity > prefix.lastIndexOf(';')) {
        prefix = prefix.substring(0, entity);
      }
      prefix = cfiEntityMapping.decode(prefix);
    }
    length += prefix.length;
    if (end >= offset) break;
  }
  return length;
}
