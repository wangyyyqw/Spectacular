import 'package:re_editor/re_editor.dart';

/// XHTML 使用标签配对；CSS 由调用方继续选择 DefaultCodeChunkAnalyzer。
/// 只做折叠定位，不替代编辑内核的 XML 校验；损坏处之后不猜测结构。
class XhtmlChunkAnalyzer implements CodeChunkAnalyzer {
  const XhtmlChunkAnalyzer();

  @override
  List<CodeChunk> run(CodeLines codeLines) => _TagChunks(codeLines).run();
}

typedef _OpenTag = ({String name, int? line});
typedef _Tag = ({String name, bool closing, bool empty, int end});

class _TagChunks {
  _TagChunks(CodeLines lines) : source = _ChunkSource(lines);
  final _ChunkSource source;
  final _stack = <_OpenTag>[];
  final _chunks = <int, CodeChunk>{};

  List<CodeChunk> run() {
    var offset = 0;
    while ((offset = source.text.indexOf('<', offset)) >= 0) {
      final skipped = _skipSpecial(source.text, offset);
      if (skipped != null) {
        if (skipped < 0) break;
        offset = skipped;
        continue;
      }
      if (_rawText && !_rawClosing(offset)) {
        offset++;
        continue;
      }
      final tag = _readTag(source.text, offset);
      if (tag == null || !_accept(tag, source.lineAt(offset))) break;
      offset = tag.end;
    }
    return _chunks.values.toList()..sort((a, b) => a.index.compareTo(b.index));
  }

  bool get _rawText =>
      _stack.isNotEmpty &&
      const {'style', 'script'}.contains(_stack.last.name.split(':').last);

  bool _rawClosing(int offset) {
    final prefix = '</${_stack.last.name}';
    if (!source.text.startsWith(prefix, offset)) return false;
    final end = offset + prefix.length;
    return end < source.text.length &&
        (source.text[end] == '>' || _space.hasMatch(source.text[end]));
  }

  bool _accept(_Tag tag, int? line) {
    if (tag.empty) return true;
    if (!tag.closing) {
      _stack.add((name: tag.name, line: line));
      return true;
    }
    if (_stack.isEmpty || _stack.last.name != tag.name) return false;
    final opening = _stack.removeLast();
    final first = opening.line;
    if (first == null || line == null || line <= first) return true;
    if (line - first == 1 && !source.collapsed.contains(first)) return true;
    if ((_chunks[first]?.end ?? -1) < line) {
      _chunks[first] = CodeChunk(first, line);
    }
    return true;
  }
}

/// 展开隐藏行只用于词法分析；结果仍映射到 ReEditor 的可见行坐标。
class _ChunkSource {
  _ChunkSource(CodeLines lines) {
    final buffer = StringBuffer();
    var visible = 0;
    for (final segment in lines.segments) {
      for (final line in segment) {
        if (line.chunkParent) collapsed.add(visible);
        _append(buffer, line, visible++);
      }
    }
    text = buffer.toString();
  }
  late final String text;
  final collapsed = <int>{};
  final _starts = <int>[];
  final _visibleLines = <int?>[];

  void _append(StringBuffer buffer, CodeLine line, int visible) {
    final pending = <({CodeLine line, int? visible})>[
      (line: line, visible: visible),
    ];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      _starts.add(buffer.length);
      _visibleLines.add(next.visible);
      buffer.writeln(next.line.text);
      for (final child in next.line.chunks.reversed) {
        pending.add((line: child, visible: null));
      }
    }
  }

  int? lineAt(int offset) {
    var low = 0, high = _starts.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_starts[middle] <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low == 0 ? null : _visibleLines[low - 1];
  }
}

final _space = RegExp(r'\s');
final _opening = RegExp(
  r'''^<([A-Za-z_][A-Za-z0-9_.:-]*)(?:\s+[A-Za-z_:][A-Za-z0-9_.:-]*\s*=\s*(?:"[^"]*"|'[^']*'))*\s*(/?)>$''',
);
final _closing = RegExp(r'^</([A-Za-z_][A-Za-z0-9_.:-]*)\s*>$');

_Tag? _readTag(String source, int start) {
  final end = _markupEnd(source, start + 1);
  if (end < 0) return null;
  final token = source.substring(start, end);
  final close = _closing.firstMatch(token);
  if (close != null) {
    return (name: close[1]!, closing: true, empty: false, end: end);
  }
  final open = _opening.firstMatch(token);
  return open == null
      ? null
      : (name: open[1]!, closing: false, empty: open[2] == '/', end: end);
}

int? _skipSpecial(String source, int start) {
  for (final delimiter in const {
    '<!--': '-->',
    '<![CDATA[': ']]>',
    '<?': '?>',
  }.entries) {
    if (!source.startsWith(delimiter.key, start)) continue;
    final end = source.indexOf(delimiter.value, start + delimiter.key.length);
    return end < 0 ? -1 : end + delimiter.value.length;
  }
  if (source.startsWith('<!DOCTYPE', start)) {
    return _markupEnd(source, start + 9, declaration: true);
  }
  return null;
}

int _markupEnd(String source, int start, {bool declaration = false}) {
  String? quote;
  var brackets = 0;
  for (var i = start; i < source.length; i++) {
    final character = source[i];
    if (quote != null) {
      if (character == quote) quote = null;
    } else if (character == '"' || character == "'") {
      quote = character;
    } else if (declaration && source.startsWith('<!--', i)) {
      final end = source.indexOf('-->', i + 4);
      if (end < 0) return -1;
      i = end + 2;
    } else if (declaration && character == '[') {
      brackets++;
    } else if (declaration && character == ']') {
      if (--brackets < 0) return -1;
    } else if (character == '>' && brackets == 0) {
      return i + 1;
    } else if (!declaration && character == '<') {
      return -1;
    }
  }
  return -1;
}
