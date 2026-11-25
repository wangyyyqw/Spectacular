import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_core/editing/epub_editing.dart';

import 'book_editor_controller.dart';

enum EditorSearchScope {
  current('当前文件'),
  opened('已打开文件'),
  selected('指定文档'),
  all('所有文本文件'),
  html('所有 HTML 文件'),
  css('所有 CSS 文件'),
  opf('OPF 文件'),
  ncx('NCX 文件');

  const EditorSearchScope(this.label);
  final String label;
}

typedef _SearchInput = ({
  String query,
  String replacement,
  bool regex,
  bool caseSensitive,
});

class _SearchText {
  _SearchText(this.original)
    : removed = [
        for (final match in RegExp(r'\r(?=\n)').allMatches(original))
          match.start,
      ],
      normalized = original.replaceAll('\r\n', '\n');
  final String original, normalized;
  final List<int> removed;

  int offset(int position) {
    var low = 0, high = removed.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (removed[middle] - middle < position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return position + low;
  }
}

/// 搜索读取源码缓冲，替换在校验后通过正式编辑事务一次写入。
class BookEditorSearch extends ChangeNotifier {
  BookEditorSearch(this.editor) {
    _activePath = editor.activePath;
    _restoreInput();
    _observe();
    query.addListener(_queryChanged);
    replacement.addListener(_replacementChanged);
    editor.addListener(_editorChanged);
    _schedule();
  }

  final BookEditorController editor;
  final query = TextEditingController(), replacement = TextEditingController();
  final queryFocus = FocusNode(), replaceFocus = FocusNode();
  EditorSearchScope scope = EditorSearchScope.current;
  Set<String> selectedPaths = {};
  bool regex = false, caseSensitive = false, wrap = true;
  bool opened = true, searching = false;
  String? error;
  List<EditSearchMatch> matches = [];
  Map<String, String> sources = {};
  int index = -1;
  final _inputs = <String, _SearchInput>{};
  Map<String, String> _buffers = {};
  bool _busy = false;
  String? _activePath;
  int _revision = -1, _token = 0;
  Timer? _timer;
  bool _syncing = false, _disposed = false, _replacing = false;
  int _searchRevision = -1;

  EditSearchMatch? get currentMatch =>
      index < 0 ? null : matches.elementAtOrNull(index);
  String _read(String path) =>
      editor.documents[path]?.code.text ?? editor.session.readText(path);
  _SearchInput get _input => (
    query: query.text,
    replacement: replacement.text,
    regex: regex,
    caseSensitive: caseSensitive,
  );

  void setScope(EditorSearchScope value) {
    if (scope == value) return;
    _rememberInput();
    scope = value;
    if (value == EditorSearchScope.current) _restoreInput();
    _queryChanged();
  }

  void setSelectedPaths(Set<String> paths) {
    selectedPaths = Set.of(paths);
    _schedule();
  }

  void setRegex(bool value) {
    regex = value;
    _queryChanged();
  }

  void setCaseSensitive(bool value) {
    caseSensitive = value;
    _queryChanged();
  }

  void setWrap(bool value) {
    wrap = value;
    notifyListeners();
  }

  void _rememberInput() {
    if (scope == EditorSearchScope.current && _activePath != null) {
      _inputs[_activePath!] = _input;
    }
  }

  _SearchInput _documentInput(BookEditorDocument doc) => _inputs.putIfAbsent(
    doc.path,
    () => (
      query: doc.find.findInputController.text,
      replacement: doc.find.replaceInputController.text,
      regex: doc.find.value?.option.regex ?? false,
      caseSensitive: doc.find.value?.option.caseSensitive ?? false,
    ),
  );

  void _restoreInput() {
    final doc = editor.activeDocument;
    if (doc == null) return;
    final input = _documentInput(doc);
    _syncing = true;
    query.text = input.query;
    replacement.text = input.replacement;
    regex = input.regex;
    caseSensitive = input.caseSensitive;
    _syncing = false;
  }

  void _highlight() {
    final doc = editor.activeDocument;
    if (doc == null) return;
    final find = doc.find;
    _documentInput(doc);
    if (find.value == null) {
      find.findInputController.clear();
      find.value = const CodeFindValue.empty();
    }
    if (find.value!.option.regex != regex) find.toggleRegex();
    if (find.value!.option.caseSensitive != caseSensitive) {
      find.toggleCaseSensitive();
    }
    find.findInputController.text = query.text;
    find.replaceInputController.text = replacement.text;
  }

  void _queryChanged() {
    if (_syncing || _disposed) return;
    _rememberInput();
    _highlight();
    _schedule();
  }

  void _replacementChanged() {
    if (_syncing || _disposed) return;
    _rememberInput();
    _highlight();
    notifyListeners();
  }

  void _observe() {
    _revision = editor.session.revision;
    _busy = editor.busy;
    _buffers = {
      for (final doc in editor.documents.values) doc.path: doc.code.text,
    };
  }

  void _editorChanged() {
    if (_syncing || _disposed) return;
    final busyChanged = _busy != editor.busy;
    final switched = _activePath != editor.activePath;
    if (switched) {
      _rememberInput();
      _activePath = editor.activePath;
      if (scope == EditorSearchScope.current) _restoreInput();
      _highlight();
    }
    final changed =
        _revision != editor.session.revision ||
        !mapEquals(_buffers, {
          for (final doc in editor.documents.values) doc.path: doc.code.text,
        });
    _observe();
    if (changed || switched && scope == EditorSearchScope.current) {
      _schedule();
    } else if (busyChanged) {
      notifyListeners();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _token++;
    searching = query.text.isNotEmpty;
    matches = [];
    sources = {};
    index = -1;
    error = null;
    _timer = Timer(
      const Duration(milliseconds: 200),
      () => unawaited(searchNow()),
    );
    notifyListeners();
  }

  List<EpubEditResource> get searchableResources {
    final resources = {
      for (final item in editor.session.resources)
        if (_isText(item)) item.path: item,
    };
    for (final doc in editor.documents.values) {
      resources.putIfAbsent(
        doc.path,
        () => EpubEditResource(doc.path, '', doc.code.text.length),
      );
    }
    return resources.values.toList()..sort((a, b) => a.path.compareTo(b.path));
  }

  bool _isText(EpubEditResource item) =>
      item.mediaType.startsWith('text/') ||
      item.mediaType.endsWith('+xml') ||
      {
        'application/xml',
        'application/javascript',
        'application/json',
      }.contains(item.mediaType) ||
      RegExp(
        r'\.(xhtml?|html?|css|opf|ncx|xml|js|mjs|json|txt|svg)$',
        caseSensitive: false,
      ).hasMatch(item.path);

  List<String> _paths() => [
    for (final item in searchableResources)
      if (switch (scope) {
        EditorSearchScope.current => item.path == editor.activePath,
        EditorSearchScope.opened => editor.documents.containsKey(item.path),
        EditorSearchScope.selected => selectedPaths.contains(item.path),
        EditorSearchScope.all => true,
        EditorSearchScope.html =>
          item.mediaType == 'application/xhtml+xml' ||
              item.mediaType == 'text/html' ||
              RegExp(
                r'\.(xhtml?|html?)$',
                caseSensitive: false,
              ).hasMatch(item.path),
        EditorSearchScope.css =>
          item.mediaType == 'text/css' ||
              item.path.toLowerCase().endsWith('.css'),
        EditorSearchScope.opf => item.path == editor.session.opfPath,
        EditorSearchScope.ncx =>
          item.mediaType == 'application/x-dtbncx+xml' ||
              item.path.toLowerCase().endsWith('.ncx'),
      })
        item.path,
  ];

  Future<void> searchNow() async {
    _timer?.cancel();
    final token = ++_token, previous = currentMatch;
    final revision = editor.session.revision;
    final found = <EditSearchMatch>[], texts = <String, String>{};
    searching = query.text.isNotEmpty;
    error = null;
    notifyListeners();
    try {
      if (query.text.isNotEmpty) {
        final pattern = RegExp(
          regex ? query.text : RegExp.escape(query.text),
          caseSensitive: caseSensitive,
          multiLine: true,
        );
        await _scan(pattern, token, found, texts);
      }
      if (_disposed || token != _token) return;
      matches = List.unmodifiable(found);
      sources = Map.unmodifiable(texts);
      _searchRevision = revision;
      index = found.indexWhere(
        (match) =>
            match.path == previous?.path && match.start == previous?.start,
      );
      if (index < 0 && found.isNotEmpty) index = 0;
    } catch (failure) {
      if (_disposed || token != _token) return;
      error = failure is FormatException
          ? '正则表达式无效，请检查括号和转义。'
          : '查找失败：$failure';
      matches = [];
      sources = {};
      index = -1;
    } finally {
      if (!_disposed && token == _token) {
        searching = false;
        notifyListeners();
      }
    }
  }

  Future<void> _scan(
    RegExp pattern,
    int token,
    List<EditSearchMatch> found,
    Map<String, String> texts,
  ) async {
    final paths = _paths(), revision = editor.session.revision;
    final isRegex = regex;
    await Future<void>.delayed(Duration.zero);
    for (final path in paths) {
      if (_disposed || token != _token) return;
      final text = _SearchText(texts[path] = _read(path));
      for (final match in pattern.allMatches(text.normalized)) {
        final start = text.offset(match.start), end = text.offset(match.end);
        found.add(
          EditSearchMatch(
            path: path,
            start: start,
            end: end,
            text: text.original.substring(start, end),
            revision: revision,
            regex: isRegex,
            groups: [
              for (var group = 1; group <= match.groupCount; group++)
                match[group],
            ],
          ),
        );
        if (found.length % 200 == 0) await Future<void>.delayed(Duration.zero);
        if (_disposed || token != _token) return;
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  void move(bool previous) {
    if (searching || matches.isEmpty) return;
    var next = index + (previous ? -1 : 1);
    if (!wrap && (next < 0 || next >= matches.length)) return;
    next = (next + matches.length) % matches.length;
    openMatch(next);
  }

  void openMatch(int selected) {
    if (editor.busy ||
        searching ||
        selected < 0 ||
        selected >= matches.length) {
      return;
    }
    final match = matches[selected], text = sources[matches[selected].path]!;
    if (_read(match.path) != text) {
      _schedule();
      return;
    }
    _syncing = true;
    editor.showSource(match.path, offset: match.start);
    _selectMatch(editor.activeDocument!, text, match);
    _activePath = editor.activePath;
    _highlight();
    _observe();
    _syncing = false;
    index = selected;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed &&
          currentMatch == match &&
          editor.activePath == match.path) {
        editor.activeDocument?.code.makeCursorVisible();
      }
    });
  }

  void _selectMatch(
    BookEditorDocument doc,
    String text,
    EditSearchMatch match,
  ) {
    final start = text.substring(0, match.start).split('\n'),
        end = text.substring(0, match.end).split('\n');
    for (final line in [start.length - 1, end.length - 1]) {
      var position = doc.code.lineIndex2Index(line);
      while (position.chunkIndex >= 0) {
        doc.code.expandChunk(position.index);
        position = doc.code.lineIndex2Index(line);
      }
    }
    doc.code.selection = CodeLineSelection(
      baseIndex: doc.code.lineIndex2Index(start.length - 1).index,
      baseOffset: start.last.replaceAll('\r', '').length,
      extentIndex: doc.code.lineIndex2Index(end.length - 1).index,
      extentOffset: end.last.replaceAll('\r', '').length,
    );
    doc.code.makeCursorVisible();
  }

  Future<void> replaceCurrent() => _replace(false);
  Future<void> replaceAll() => _replace(true);

  Future<void> _replace(bool all) async {
    if (editor.busy || _replacing || searching) return;
    final selected = currentMatch;
    if (!all && selected == null) return;
    _replacing = true;
    try {
      if (!await _prepareReplacement()) return;
      final targets = all
          ? matches
          : matches
                .where(
                  (match) =>
                      match.path == selected!.path &&
                      match.start == selected.start &&
                      match.text == selected.text,
                )
                .take(1)
                .toList();
      if (targets.isEmpty) return;
      final writes = _replacementSources(targets);
      if (!editor.runCommand(
        () =>
            ClassStyleEditor(editor.session)
                .writeSources(writes, validate: true),
      )) {
        error = editor.error;
        notifyListeners();
        return;
      }
      await searchNow();
    } finally {
      _replacing = false;
    }
  }

  Future<bool> _prepareReplacement() async {
    if (!editor.flush()) {
      error = editor.error;
      notifyListeners();
      return false;
    }
    final pending = searchNow(), token = _token;
    await pending;
    if (_disposed || token != _token || error != null) return false;
    if (editor.busy ||
        editor.session.revision != _searchRevision ||
        editor.hasPendingText ||
        sources.entries.any((entry) => _read(entry.key) != entry.value)) {
      error = '源码已变化，请重新查找后替换。';
      notifyListeners();
      return false;
    }
    return true;
  }

  Map<String, String> _replacementSources(List<EditSearchMatch> targets) {
    final writes = <String, String>{};
    for (final match in targets.reversed) {
      final text = writes[match.path] ?? sources[match.path]!;
      final replacement = _replacementFor(match);
      final value = sources[match.path]!.contains('\r\n')
          ? replacement.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')
          : replacement;
      writes[match.path] = text.replaceRange(match.start, match.end, value);
    }
    return writes;
  }

  String _replacementFor(EditSearchMatch match) => !match.regex
      ? replacement.text
      : replacement.text.replaceAllMapped(RegExp(r'\$(\d+)'), (group) {
          final number = int.parse(group[1]!);
          return number == 0
              ? match.text
              : number <= match.groups.length
              ? match.groups[number - 1] ?? ''
              : group[0]!;
        });

  void focus({bool all = false}) {
    opened = true;
    if (all) setScope(EditorSearchScope.all);
    _highlight();
    notifyListeners();
    queryFocus.requestFocus();
  }

  void close() {
    opened = false;
    queryFocus.unfocus();
    replaceFocus.unfocus();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token++;
    _timer?.cancel();
    editor.removeListener(_editorChanged);
    query.dispose();
    replacement.dispose();
    queryFocus.dispose();
    replaceFocus.dispose();
    super.dispose();
  }
}
