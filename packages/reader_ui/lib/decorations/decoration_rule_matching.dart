import 'decoration_rules.dart';

/// 跨段最多七段，不截断超限正则输入。
const decorationRuleParagraphLimit = 7;
const decorationRuleMaxPattern = 512;
const decorationRuleMaxInput = 32768;
const decorationRuleMaxResults = 1024;

/// Dart 的 $ 会匹配尾换行之前；内部改写为严格末尾匹配。
String decorationRegexSource(String pattern) {
  final output = StringBuffer();
  var inClass = false;
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (char == r'\' && i + 1 < pattern.length) {
      output.write(char);
      output.write(pattern[++i]);
      continue;
    }
    if (char == '[') inClass = true;
    if (char == ']') inClass = false;
    output.write(char == r'$' && !inClass ? r'$(?![\s\S])' : char);
  }
  return output.toString();
}

String? validateDecorationRule(ReaderDecorationRuleType type, String pattern) {
  if (!type.needsPattern) return null;
  if (pattern.trim().isEmpty) return '请输入匹配内容';
  if (type != ReaderDecorationRuleType.regex) return null;
  if (pattern.length > decorationRuleMaxPattern) return '正则模式最多 512 字符';
  // 保留 RE2 的受限语义；实际运行仍由可终止 isolate 隔离。
  if (RegExp(r'\(\?[=!<]|\\[1-9]|(?:\*|\+|\?|\{\d+(?:,\d*)?\})\+')
      .hasMatch(pattern)) {
    return '正则不支持环视、反向引用和占有量词';
  }
  var depth = 0;
  var inClass = false;
  var expansion = pattern.length;
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (char == r'\') {
      i++;
      continue;
    }
    if (char == '[') inClass = true;
    if (char == ']') inClass = false;
    if (inClass) continue;
    if (char == '(' && ++depth > 16) return '正则分组嵌套不能超过 16 层';
    if (char == ')') depth--;
    if (char == '{') {
      final end = pattern.indexOf('}', i + 1);
      if (end < 0) continue;
      final counts = pattern
          .substring(i + 1, end)
          .split(',')
          .map(int.tryParse)
          .whereType<int>();
      for (final count in counts) {
        if (count > 100 || count > 0 && expansion > 32768 ~/ count) {
          return '正则计数量词展开过大';
        }
      }
      final count = counts.fold<int>(1, (a, b) => a > b ? a : b);
      expansion *= count;
    }
  }
  try {
    RegExp(pattern, unicode: true);
  } on FormatException {
    return '正则格式无效，请修改规则后重新生成预览';
  }
  return null;
}

List<(int, int)> decorationQuoteRanges(
  String text, {
  required bool single,
  int maxParagraphs = 1,
}) {
  final quotes = single
      ? const {'‘': '’', "'": "'"}
      : const {'“': '”', '「': '」', '『': '』', '"': '"'};
  final result = <(int, int)>[];
  var index = 0;
  while (index < text.length) {
    final open = text[index];
    final close = quotes[open];
    if (close == null) {
      index++;
      continue;
    }
    var end = -1;
    var separators = 0;
    for (var cursor = index + 1; cursor < text.length; cursor++) {
      final char = text[cursor];
      if (char == close) {
        end = cursor + 1;
        break;
      }
      if (open != close && char == open) break;
      if (char == '\n' || char == '\r') {
        if (++separators >= maxParagraphs) break;
        while (cursor + 1 < text.length &&
            (text[cursor + 1] == '\n' || text[cursor + 1] == '\r')) {
          cursor++;
        }
      }
    }
    if (end < 0) {
      end = index + 1;
      while (end < text.length && text[end] != '\n' && text[end] != '\r') {
        end++;
      }
    }
    result.add((index, end));
    index = end;
  }
  return result;
}

List<(int, int)> decorationDelimiterRanges(
  String text,
  String pattern,
  int maxParagraphs,
) {
  final value = pattern.trim();
  if (value.isEmpty) return [];
  final open = value.length.isOdd
      ? value
      : value.substring(0, value.length ~/ 2);
  final close = value.length.isOdd ? value : value.substring(value.length ~/ 2);
  final result = <(int, int)>[];
  var start = -1;
  var index = 0;
  var separators = 0;
  var skippedOpen = -1;
  while (index < text.length) {
    if (start < 0) {
      start = text.indexOf(open, index);
      if (start < 0) break;
      index = start + open.length;
      separators = 0;
      skippedOpen = -1;
      continue;
    }
    if (text[index] == '\n') {
      if (skippedOpen < 0 &&
          open.startsWith('\n') &&
          text.startsWith(open, index)) {
        skippedOpen = index;
      }
      if (++separators >= maxParagraphs) {
        start = -1;
        index = skippedOpen >= 0 ? skippedOpen : index + 1;
      } else {
        index++;
      }
    } else if (text.startsWith(close, index) &&
        (open != close || index > start + open.length)) {
      index += close.length;
      result.add((start, index));
      start = -1;
    } else if (open != close && text.startsWith(open, index)) {
      start = index;
      index += open.length;
      separators = 0;
      skippedOpen = -1;
    } else {
      index++;
    }
  }
  return result;
}

List<(int, int)> subtractDecorationRanges(
  (int, int) source,
  List<(int, int)> excluded,
) {
  final sorted =
      excluded.where((r) => r.$1 < source.$2 && r.$2 > source.$1).toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));
  final result = <(int, int)>[];
  var cursor = source.$1;
  for (final range in sorted) {
    if (range.$1 > cursor) {
      result.add((cursor, range.$1.clamp(cursor, source.$2)));
    }
    if (range.$2 > cursor) cursor = range.$2;
    if (cursor >= source.$2) break;
  }
  if (cursor < source.$2) result.add((cursor, source.$2));
  return result;
}
