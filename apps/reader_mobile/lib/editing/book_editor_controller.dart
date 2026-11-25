import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/reader_page.dart';

import '../reader/reader_settings.dart';

class EditorExportCancelled implements Exception {
  const EditorExportCancelled();
}

/// 打开的源码文档保留自己的光标和输入历史，切换标签不会丢失半成品。
class BookEditorDocument {
  BookEditorDocument(this.path, String text)
    : acceptedText = text,
      _lastInputText = text,
      code = CodeLineEditingController.fromText(
        text,
        CodeLineOptions(
          lineBreak: text.contains('\r\n')
              ? TextLineBreak.crlf
              : TextLineBreak.lf,
        ),
      );

  final String path;
  final CodeLineEditingController code;
  CodeFindController? _find;
  CodeFindController get find =>
      _find ??= CodeFindController(code, const CodeFindValue.empty());
  String acceptedText;
  String _lastInputText;
  String? error;

  void dispose() {
    _find?.dispose();
    code.dispose();
  }
}

typedef SaveEditorDraft = Future<void> Function(
  EpubEditSession session,
  Map<String, String> buffers,
);
typedef CommitEditor = Future<void> Function(EpubEditSession session);

/// 书籍工作副本。所有写入走核心事务，预览只使用有效版本的独立快照。
class BookEditorController extends ChangeNotifier {
  BookEditorController({
    required this.session,
    this.saveDraft,
    this.commit,
    this.export,
    Map<String, String> buffers = const {},
    this.initialTarget,
    this.readingSettings,
    this.discardDraft,
    this.editInitialTarget = false,
    bool recovered = false,
  }) : _savedRevision = recovered ? -1 : session.revision {
    for (final entry in buffers.entries) {
      openDocument(entry.key).code.text = entry.value;
    }
    _subscription = session.changes.listen(_sessionChanged);
    unawaited(refreshPreview());
  }

  final EpubEditSession session;
  final SaveEditorDraft? saveDraft;
  final CommitEditor? commit;
  final CommitEditor? export;
  final Future<void> Function()? discardDraft;
  final bool editInitialTarget;
  final ReaderEditTarget? initialTarget;
  final ReaderSettings? readingSettings;
  bool useReadingSettings = false;
  bool sourceRequested = false;
  final Map<String, BookEditorDocument> documents = {};
  final Map<String, ReaderEditTarget> _previewLocations = {};
  final Set<EpubChapterSource> _retiredSources = {};
  late final StreamSubscription<Object?> _subscription;
  Timer? _debounce;
  Future<void> _draftWrite = Future<void>.value();
  bool _disposed = false;
  bool _syncing = false;
  BookEditorDocument? _sourceRedo;
  Set<String> _committingDocuments = {};
  int _previewToken = 0;
  int _savedRevision;
  int _locationRequest = 0;
  String? _previewPath;
  String? activePath;
  String? error;
  String? draftError;
  bool busy = false;
  bool previewLoading = false;
  EpubChapterSource? previewSource;
  int previewRevision = -1;
  ReaderEditTarget? previewTarget;
  int previewNavigation = 0;

  BookEditorDocument? get activeDocument => documents[activePath];
  int? get sourceOffset {
    final doc = activeDocument;
    if (doc == null) return null;
    final selection = doc.code.unfoldLineSelection;
    return doc.code.text
            .split('\n')
            .take(selection.startIndex)
            .fold<int>(0, (length, line) => length + line.length + 1) +
        selection.startOffset;
  }

  bool get dirty => session.revision != _savedRevision || hasPendingText;
  bool get hasPendingText => documents.values.any(_documentDirty);
  bool get hasErrors => documents.values.any((doc) => doc.error != null);

  void setPreviewSettings(bool enabled) {
    if (useReadingSettings == enabled) return;
    useReadingSettings = enabled;
    _notify();
  }

  /// 从浏览器、标签或查找结果打开文件。正文切章，样式等资源保留对照页。
  void showSource(String path, {int? offset}) {
    final request = ++_locationRequest;
    sourceRequested = true;
    final spine = session.previewPaths.indexOf(path);
    if (spine >= 0 && offset == null) {
      _previewPath = path;
      previewTarget =
          _previewLocations[path] ??
          ReaderEditTarget(
            spineIndex: spine,
            cfi: CfiBuilder()
                .itemRef((spine + 1) * 2)
                .body(4)
                .build()
                .serialize(),
          );
      previewNavigation++;
    }
    openDocument(path, offset: offset);
    if (spine >= 0 && offset != null) {
      unawaited(_locateSourceOffset(path, offset, request));
    }
  }

  Future<void> _locateSourceOffset(String path, int offset, int request) async {
    if (busy || hasPendingText) return;
    try {
      final revision = session.revision;
      final cfi = session.cfiForSourceOffset(path, offset, preview: true);
      if (previewRevision != revision) await refreshPreview();
      if (_disposed ||
          request != _locationRequest ||
          activePath != path ||
          session.revision != revision ||
          hasPendingText ||
          previewRevision != revision) {
        return;
      }
      previewTarget = ReaderEditTarget(
        spineIndex: session.previewPaths.indexOf(path),
        cfi: cfi,
        contentRevision: 'editor-$revision',
      );
      _previewPath = path;
      previewNavigation++;
      error = null;
      _notify();
    } catch (failure) {
      error = '$failure';
      _notify();
    }
  }

  void rememberPreviewLocation(ReaderEditTarget target) {
    if (target.contentRevision != null &&
        target.contentRevision != 'editor-$previewRevision') {
      return;
    }
    previewTarget = target;
    _previewPath = session.previewPaths.elementAtOrNull(target.spineIndex);
    if (_previewPath case final path?) _previewLocations[path] = target;
  }

  bool _documentDirty(BookEditorDocument doc) {
    return doc.code.text != doc.acceptedText;
  }

  BookEditorDocument openDocument(String path, {int? offset}) {
    final doc = documents.putIfAbsent(path, () {
      final created = BookEditorDocument(path, session.readText(path));
      created.code.addListener(() => _inputChanged(created));
      return created;
    });
    activePath = path;
    if (offset != null) {
      final prefix = doc.code.text.substring(
        0,
        offset.clamp(0, doc.code.text.length),
      );
      final lines = prefix.split('\n');
      var position = doc.code.lineIndex2Index(lines.length - 1);
      while (position.chunkIndex >= 0) {
        doc.code.expandChunk(position.index);
        position = doc.code.lineIndex2Index(lines.length - 1);
      }
      doc.code.selection = CodeLineSelection.collapsed(
        index: position.index,
        offset: lines.last.length,
      );
      doc.code.makeCursorVisible();
    }
    _notify();
    return doc;
  }

  bool documentDirty(String path) => _documentDirty(documents[path]!);

  void closeDocument(String path) {
    final doc = documents[path];
    if (doc == null) return;
    if (_documentDirty(doc) && !flush()) return;
    if (activePath == path) FocusManager.instance.primaryFocus?.unfocus();
    if (_sourceRedo == doc) _sourceRedo = null;
    documents.remove(path);
    WidgetsBinding.instance.addPostFrameCallback((_) => doc.dispose());
    if (activePath == path) {
      activePath = documents.keys.lastOrNull;
      if (activePath case final next?) {
        showSource(next);
        return;
      }
    }
    _notify();
  }

  void _inputChanged(BookEditorDocument doc) {
    if (_disposed) return;
    final text = doc.code.text;
    if (text == doc._lastInputText) return;
    doc._lastInputText = text;
    if (_syncing) return;
    _sourceRedo = doc.code.canRedo ? doc : null;
    doc.error = null;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      flush();
      _queueDraft();
    });
    _notify();
  }

  /// 多文档一次校验，失败时保留全部输入及上一份有效预览。
  bool flush() {
    _debounce?.cancel();
    final pending = documents.values.where(_documentDirty).toList();
    if (pending.isEmpty) return true;
    try {
      _committingDocuments = pending.map((doc) => doc.path).toSet();
      ClassStyleEditor(session).writeSources({
        for (final doc in pending) doc.path: doc.code.text,
      }, validate: true);
      for (final doc in pending) {
        doc.error = null;
      }
      error = null;
      _notify();
      return true;
    } catch (failure) {
      error = '$failure';
      for (final doc in pending) {
        doc.error = '$failure';
      }
      _notify();
      return false;
    } finally {
      _committingDocuments = {};
    }
  }

  void _sessionChanged(EpubEditChange change) {
    if (_disposed) return;
    _sourceRedo = null;
    _syncing = true;
    final paths = session.resources.map((item) => item.path).toSet();
    for (final path
        in documents.keys.where((path) => !paths.contains(path)).toList()) {
      final removed = documents.remove(path)!;
      WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
      if (activePath == path) activePath = documents.keys.lastOrNull;
    }
    for (final doc in documents.values) {
      if (!session.resources.any((resource) => resource.path == doc.path)) {
        continue;
      }
      final changedByUser = _documentDirty(doc);
      final next = session.readText(doc.path);
      if ((!changedByUser || _committingDocuments.contains(doc.path)) &&
          doc.code.text != next) {
        doc.code.text = next;
      }
      doc.acceptedText = next;
    }
    _syncing = false;
    final pathsForPreview = session.previewPaths;
    _previewLocations.removeWhere(
      (path, target) =>
          change.changedPaths.contains(path) ||
          pathsForPreview.indexOf(path) != target.spineIndex,
    );
    if (_previewPath != null &&
        (!pathsForPreview.contains(_previewPath) ||
            pathsForPreview.indexOf(_previewPath!) !=
                previewTarget?.spineIndex)) {
      final path = pathsForPreview.contains(_previewPath)
          ? _previewPath!
          : pathsForPreview.contains(activePath)
          ? activePath!
          : pathsForPreview.first;
      final spine = pathsForPreview.indexOf(path);
      if (spine >= 0) {
        _previewPath = path;
        previewTarget = ReaderEditTarget(
          spineIndex: spine,
          cfi: CfiBuilder()
              .itemRef((spine + 1) * 2)
              .body(4)
              .build()
              .serialize(),
        );
        previewNavigation++;
      }
    }
    error = null;
    _queueDraft();
    unawaited(refreshPreview());
    _notify();
  }

  void _queueDraft() {
    final save = saveDraft;
    if (save == null || _disposed) return;
    _draftWrite = _draftWrite.catchError((Object _) {}).then((_) async {
      if (_disposed) return;
      try {
        await save(session, {
          for (final doc in documents.values)
            if (_documentDirty(doc)) doc.path: doc.code.text,
        });
        draftError = null;
      } catch (failure) {
        draftError = '草稿未能写入：$failure';
      }
      _notify();
    });
  }

  Future<void> persistDraft() async {
    _debounce?.cancel();
    _queueDraft();
    await _draftWrite;
    if (draftError != null) throw StateError(draftError!);
  }

  Future<bool> discard() async {
    if (busy) return false;
    busy = true;
    _debounce?.cancel();
    _notify();
    try {
      await _draftWrite;
      await discardDraft?.call();
      return true;
    } catch (failure) {
      error = '丢弃草稿失败：$failure';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> refreshPreview() async {
    final token = ++_previewToken;
    final revision = session.revision;
    previewLoading = true;
    _notify();
    try {
      final source = await session.createPreviewSource(
        includeUnlistedHtml: true,
      );
      if (_disposed || token != _previewToken) {
        source.close();
        return;
      }
      final old = previewSource;
      previewSource = source;
      previewRevision = revision;
      previewTarget ??= initialTarget;
      if (old != null) {
        _retiredSources.add(old);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_retiredSources.remove(old)) old.close();
        });
      }
    } catch (failure) {
      if (!_disposed && token == _previewToken) error = '预览未更新：$failure';
    } finally {
      if (!_disposed && token == _previewToken) {
        previewLoading = false;
        _notify();
      }
    }
  }

  EditableElementRef resolveTarget(ReaderEditTarget target) {
    final fromPreview = target.contentRevision?.startsWith('editor-') == true;
    if (previewRevision != session.revision ||
        hasPendingText ||
        (fromPreview && target.contentRevision != 'editor-$previewRevision')) {
      throw StateError('源码尚未更新到预览，请等待校验完成后再选择段落');
    }
    previewTarget = target;
    return session.resolveEditableElement(
      target.spineIndex,
      target.cfi,
      preview: true,
    );
  }

  Future<EditableElementRef?> locateSource({bool reportErrors = true}) async {
    final request = ++_locationRequest;
    if (busy || !flush()) return null;
    try {
      final doc = activeDocument;
      if (doc == null) throw StateError('请先打开正文源码');
      final offset = _sourceOffset(doc);
      final element = session
          .editableDocument(doc.path)
          .elementAtOffset(offset);
      if (element == null) throw StateError('光标不在正文元素中');
      final cfi = session.cfiForSourceOffset(doc.path, offset, preview: true);
      final revision = session.revision;
      if (previewRevision != revision) await refreshPreview();
      if (_disposed ||
          request != _locationRequest ||
          activeDocument != doc ||
          _sourceOffset(doc) != offset ||
          session.revision != revision ||
          hasPendingText ||
          previewRevision != revision) {
        throw StateError('源码已变化，请重新定位');
      }
      previewTarget = ReaderEditTarget(
        spineIndex: session.previewPaths.indexOf(doc.path),
        cfi: cfi,
        contentRevision: 'editor-$revision',
      );
      _previewPath = doc.path;
      previewNavigation++;
      error = null;
      _notify();
      return element;
    } catch (failure) {
      if (reportErrors) {
        error = '$failure';
        _notify();
      }
      return null;
    }
  }

  int _sourceOffset(BookEditorDocument doc) {
    final selection = doc.code.unfoldLineSelection;
    return doc.code.text
            .split('\n')
            .take(selection.extentIndex)
            .fold<int>(0, (length, line) => length + line.length + 1) +
        selection.extentOffset;
  }

  bool runCommand(VoidCallback action) {
    if (busy) return false;
    if (!flush()) return false;
    try {
      action();
      error = null;
      _notify();
      return true;
    } catch (failure) {
      error = '$failure';
      _notify();
      return false;
    }
  }

  Future<bool> runAsyncCommand(Future<void> Function() action) async {
    if (busy || !flush()) return false;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
      return true;
    } catch (failure) {
      error = '$failure';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  void undo() {
    if (busy) return;
    final doc = activeDocument;
    if (doc != null && _documentDirty(doc) && doc.code.canUndo) {
      doc.code.undo();
    } else {
      runCommand(session.undo);
    }
  }

  void redo() {
    if (busy) return;
    final doc = activeDocument;
    if (doc != null && doc == _sourceRedo && doc.code.canRedo) {
      doc.code.redo();
    } else {
      runCommand(session.redo);
    }
  }

  Future<bool> save() => _perform(commit, saved: true);
  Future<bool> exportBook() => _perform(export);

  Future<bool> _perform(CommitEditor? action, {bool saved = false}) async {
    if (busy || action == null || !flush()) return false;
    busy = true;
    error = null;
    _notify();
    try {
      await _draftWrite;
      await action(session);
      if (saved) _savedRevision = session.revision;
      return true;
    } on EditorExportCancelled {
      return false;
    } catch (failure) {
      error = '$failure';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _previewToken++;
    _debounce?.cancel();
    unawaited(_subscription.cancel());
    for (final doc in documents.values) {
      doc.dispose();
    }
    previewSource?.close();
    for (final source in _retiredSources) {
      source.close();
    }
    _retiredSources.clear();
    session.close();
    super.dispose();
  }
}
