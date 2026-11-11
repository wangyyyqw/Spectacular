/// 为 html5lib 准备 XHTML 输入及源码偏移映射。
///
/// HTML5 解析器忽略非 void 元素的 `/>` 自闭合标记。合法 XHTML 中的
/// `<div style="clear: both;"/>` 会把后续兄弟节点吞成子节点，聊天消息等
/// 结构会整段串位。这里把这类标签展开成显式开始/结束标签，同时记录每个
/// 转换后位置对应的原始源码偏移，保证 CFI 与源位置不漂移。
class PreparedHtml5Input {
  /// 创建预处理结果。
  const PreparedHtml5Input({
    required this.xhtml,
    required this._sourceOffsets,
    required this.sourceLength,
  });

  /// 交给 html5lib 的等义 XHTML。
  final String xhtml;

  /// 原始 XHTML 长度。
  final int sourceLength;

  final List<int> _sourceOffsets;

  /// 转换后偏移 → 原始源码偏移。
  int originalOffset(int offset) {
    if (offset <= 0 || _sourceOffsets.isEmpty) {
      return 0;
    }
    if (offset >= _sourceOffsets.length) {
      return sourceLength;
    }
    return _sourceOffsets[offset];
  }
}

const Set<String> _voidElements = <String>{
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

/// 预处理 XHTML，并保留转换后位置到原始源码位置的映射。
PreparedHtml5Input prepareHtml5InputWithOffsets(String source) {
  final output = StringBuffer();
  final offsets = <int>[];
  String? rawTextTag;

  void copyRange(int start, int end) {
    for (var i = start; i < end; i++) {
      output.write(source[i]);
      offsets.add(i);
    }
  }

  void writeMapped(String value, int sourceOffset) {
    output.write(value);
    offsets.addAll(List<int>.filled(value.length, sourceOffset));
  }

  /// CDATA 在 HTML5 解析器里会被当作注释丢弃；正文中的 CDATA 必须转成
  /// 等义文本实体。逐字符映射到原源码位置，CFI 的字符偏移仍对应原文。
  void writeCdataText(int start, int end) {
    for (var i = start; i < end; i++) {
      final escaped = switch (source[i]) {
        '&' => '&amp;',
        '<' => '&lt;',
        '>' => '&gt;',
        final value => value,
      };
      for (var j = 0; j < escaped.length; j++) {
        writeMapped(escaped[j], i);
      }
    }
  }

  var cursor = 0;
  while (cursor < source.length) {
    if (source[cursor] != '<') {
      copyRange(cursor, cursor + 1);
      cursor += 1;
      continue;
    }
    if (source.startsWith('<!--', cursor)) {
      final close = source.indexOf('-->', cursor + 4);
      final end = close < 0 ? source.length : close + 3;
      copyRange(cursor, end);
      cursor = end;
      continue;
    }
    if (source.startsWith('<![CDATA[', cursor)) {
      final close = source.indexOf(']]>', cursor + 9);
      final end = close < 0 ? source.length : close + 3;
      if (rawTextTag == null) {
        writeCdataText(cursor + 9, close < 0 ? source.length : close);
      } else {
        copyRange(cursor, end);
      }
      cursor = end;
      continue;
    }
    final tagEnd = _tagEnd(source, cursor);
    if (tagEnd < 0) {
      copyRange(cursor, source.length);
      break;
    }
    if (source.startsWith('</', cursor)) {
      if (rawTextTag != null) {
        final lower = source.substring(cursor, tagEnd + 1).toLowerCase();
        if (lower.startsWith('</$rawTextTag')) {
          rawTextTag = null;
        }
      }
      copyRange(cursor, tagEnd + 1);
      cursor = tagEnd + 1;
      continue;
    }
    if (source.startsWith('<!', cursor) || source.startsWith('<?', cursor)) {
      copyRange(cursor, tagEnd + 1);
      cursor = tagEnd + 1;
      continue;
    }

    var nameStart = cursor + 1;
    while (nameStart < tagEnd && _isXmlSpace(source.codeUnitAt(nameStart))) {
      nameStart += 1;
    }
    var nameEnd = nameStart;
    while (nameEnd < tagEnd && _isTagNameChar(source.codeUnitAt(nameEnd))) {
      nameEnd += 1;
    }
    final tagName = source.substring(nameStart, nameEnd);
    final localName = tagName.split(':').last.toLowerCase();
    final beforeClose = source.substring(cursor, tagEnd).trimRight();
    final selfClosing = beforeClose.endsWith('/');
    if (!selfClosing &&
        !_voidElements.contains(localName) &&
        (localName == 'script' || localName == 'style')) {
      rawTextTag = localName;
    }
    if (!selfClosing || _voidElements.contains(localName)) {
      copyRange(cursor, tagEnd + 1);
      cursor = tagEnd + 1;
      continue;
    }

    final slash = cursor + beforeClose.length - 1;
    copyRange(cursor, slash);
    writeMapped('>', slash);
    writeMapped('</$tagName>', tagEnd + 1);
    cursor = tagEnd + 1;
  }

  return PreparedHtml5Input(
    xhtml: output.toString(),
    sourceOffsets: List<int>.unmodifiable(offsets),
    sourceLength: source.length,
  );
}

int _tagEnd(String source, int start) {
  var quote = '';
  for (var i = start + 1; i < source.length; i++) {
    final char = source[i];
    if (quote.isNotEmpty) {
      if (char == quote) {
        quote = '';
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == '>') {
      return i;
    }
  }
  return -1;
}

bool _isXmlSpace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;

bool _isTagNameChar(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    codeUnit == 0x3A ||
    codeUnit == 0x5F ||
    codeUnit == 0x2D;
