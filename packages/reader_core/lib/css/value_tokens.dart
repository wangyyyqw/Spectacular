/// 按顶层分隔符或空白切分，字符串与函数内部保持完整。
List<String>? cssValueTokens(
  String raw, {
  String? separator,
  bool separateSlash = false,
}) => _CssValueTokenizer(raw, separator, separateSlash).parse();

class _CssValueTokenizer {
  _CssValueTokenizer(this.raw, this.separator, this.separateSlash);

  final String raw;
  final String? separator;
  final bool separateSlash;
  final result = <String>[];
  var index = 0;
  var start = 0;
  var depth = 0;
  String? quote;

  List<String>? parse() {
    for (; index < raw.length; index++) {
      final char = raw[index];
      if (char == r'\') {
        index++;
        continue;
      }
      if (_stringChar(char)) continue;
      if (char == '/' && index + 1 < raw.length && raw[index + 1] == '*') {
        if (!_comment()) return null;
        continue;
      }
      if (char == '(') depth++;
      if (char == ')') depth--;
      if (depth < 0) return null;
      if (depth == 0) _boundary(char);
    }
    if (quote != null || depth != 0) return null;
    _push(raw.length, retainEmpty: separator != null);
    return result;
  }

  bool _stringChar(String char) {
    if (quote != null) {
      if (char == quote) {
        quote = null;
        if (depth == 0 && separator == null) _push(index + 1);
      }
      return true;
    }
    if (char != '"' && char != "'") return false;
    if (depth == 0 && separator == null) _push(index);
    quote = char;
    return true;
  }

  bool _comment() {
    final end = raw.indexOf('*/', index + 2);
    if (end < 0) return false;
    if (depth == 0 && separator == null) {
      _push(index);
      start = end + 2;
    }
    index = end + 1;
    return true;
  }

  void _boundary(String char) {
    if (char == ')' && separator == null) {
      _push(index + 1);
    } else if (char == '/' && separateSlash) {
      _push(index);
      result.add('/');
      start = index + 1;
    } else if (separator == null ? _white.hasMatch(char) : char == separator) {
      _push(index, retainEmpty: separator != null);
      start = index + 1;
    }
  }

  void _push(int end, {bool retainEmpty = false}) {
    final token = raw.substring(start, end).trim();
    if (token.isNotEmpty || retainEmpty) result.add(token);
    start = end;
  }
}

final _white = RegExp(r'[\t\n\r\f ]');
final _hex = RegExp(r'[0-9a-fA-F]');

/// 解码完整 CSS 字符串；非法码点替换为 U+FFFD，转义换行不产生字符。
String? decodeCssString(String raw) {
  if (raw.length < 2 || (raw[0] != '"' && raw[0] != "'")) return null;
  if (raw[raw.length - 1] != raw[0]) return null;
  final output = StringBuffer();
  for (var i = 1; i < raw.length - 1; i++) {
    final char = raw[i];
    if (char == raw[0] || char == '\n' || char == '\r' || char == '\f') {
      return null;
    }
    if (char != '\\') {
      output.write(char);
      continue;
    }
    if (++i >= raw.length - 1) return null;
    if (raw[i] == '\n' || raw[i] == '\r' || raw[i] == '\f') {
      if (raw[i] == '\r' && raw[i + 1] == '\n') i++;
      continue;
    }
    final start = i;
    while (i < raw.length - 1 && i - start < 6 && _hex.hasMatch(raw[i])) {
      i++;
    }
    if (i == start) {
      output.write(raw[i]);
      continue;
    }
    final code = int.parse(raw.substring(start, i), radix: 16);
    output.writeCharCode(
      code == 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)
          ? 0xfffd
          : code,
    );
    if (i < raw.length - 1 && _white.hasMatch(raw[i])) {
      if (raw[i] == '\r' && raw[i + 1] == '\n') i++;
    } else {
      i--;
    }
  }
  return output.toString();
}
