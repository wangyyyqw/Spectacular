import 'css_completion_data.dart';

enum CssCompletionMode { stylesheet, xhtml, property, value }

class CssCompletionItem {
  const CssCompletionItem({
    required this.label,
    required this.detail,
    required this.insertText,
    required this.caretOffset,
    this.continueValues = false,
  });
  final String label, detail, insertText;
  final int caretOffset;
  final bool continueValues;
}

class CssCompletionRequest {
  const CssCompletionRequest({
    required this.start,
    required this.end,
    required this.items,
    required this.label,
  });
  final int start, end;
  final List<CssCompletionItem> items;
  final String label;
}

typedef _CssRegion = ({int start, int end, bool inline});
typedef _Token = ({int start, int end, String prefix});

CssCompletionRequest? completeCss(
  String text,
  int offset, {
  CssCompletionMode mode = CssCompletionMode.stylesheet,
  String? property,
  bool explicit = false,
}) {
  if (offset < 0 || offset > text.length) return null;
  if (mode == CssCompletionMode.value && property?.trim().isNotEmpty != true) {
    return null;
  }
  if (mode == CssCompletionMode.property || mode == CssCompletionMode.value) {
    final state = _CssState(text, true)..scan(offset);
    if (state.blocked) return null;
    return _complete(
      text,
      offset,
      0,
      text.length,
      mode == CssCompletionMode.value ? property : null,
      propertyOnly: mode == CssCompletionMode.property,
      explicit: explicit,
    );
  }
  final region = mode == CssCompletionMode.xhtml
      ? _htmlRegion(text, offset)
      : (start: 0, end: text.length, inline: false);
  if (region == null) return null;
  final css = text.substring(region.start, region.end);
  final cursor = offset - region.start;
  final state = _CssState(css, region.inline, entities: region.inline)
    ..scan(cursor);
  if (!state.declarations || state.blocked) return null;
  final before = _masked(css.substring(state.segment, cursor));
  final colon = _declarationColon(before);
  final name = colon < 0 ? null : before.substring(0, colon).trim();
  if (name != null && !_propertyName.hasMatch(name)) return null;
  if (name == null &&
      before.trim().isNotEmpty &&
      !_propertyName.hasMatch(before.trim())) {
    return null;
  }
  if (_selectorAhead(css, cursor)) return null;
  return _complete(
    text,
    offset,
    region.start + state.segment,
    region.end,
    name,
    explicit: explicit,
  );
}

final _propertyName = RegExp(r'^[-_a-zA-Z][-_a-zA-Z0-9]*$');
final _word = RegExp(r'[-_a-zA-Z0-9.!#%]');

int _declarationColon(String text) {
  var brackets = 0;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '[') brackets++;
    if (text[i] == ']') brackets--;
    if (text[i] == ':' && brackets == 0) return i;
  }
  return -1;
}

bool _selectorAhead(String text, int offset) {
  String? quote;
  var parentheses = 0;
  for (var i = offset; i < text.length; i++) {
    final char = text[i];
    if (quote != null) {
      if (char == '\\') {
        i++;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == '/' && i + 1 < text.length && text[i + 1] == '*') {
      final close = text.indexOf('*/', i + 2);
      if (close < 0) return false;
      i = close + 1;
      continue;
    }
    if (char == '(') parentheses++;
    if (char == ')') parentheses--;
    if (parentheses > 0) continue;
    if (char == '{') return true;
    if (char == ';' || char == '}') return false;
  }
  return false;
}

CssCompletionRequest? _complete(
  String text,
  int offset,
  int lower,
  int upper,
  String? property, {
  bool propertyOnly = false,
  bool explicit = false,
}) {
  final token = _tokenAt(text, offset, lower, upper);
  final beginsValue =
      property != null &&
      RegExp(r':\s*$').hasMatch(_masked(text.substring(lower, offset)));
  if (!explicit && token.prefix.isEmpty && !beginsValue) return null;
  final isProperty = property == null;
  final names = isProperty
      ? cssPropertyDetails.keys.toList()
      : _values(text, property.toLowerCase(), token.prefix);
  final sorted = _rank(names, token.prefix);
  if (sorted.isEmpty) return null;
  return CssCompletionRequest(
    start: token.start,
    end: token.end,
    label: isProperty ? 'CSS 属性' : '$property 的值',
    items: [
      for (final name in sorted)
        isProperty
            ? _propertyItem(name, text, token, upper, propertyOnly)
            : _valueItem(
                name,
                property.toLowerCase(),
                text.substring(token.end, upper),
              ),
    ],
  );
}

_Token _tokenAt(String text, int offset, int lower, int upper) {
  var start = offset, end = offset;
  while (start > lower && _word.hasMatch(text[start - 1])) {
    start--;
  }
  while (end < upper && _word.hasMatch(text[end])) {
    end++;
  }
  final function = RegExp(r'var\(\s*--[-\w]*\)?$')
      .firstMatch(text.substring(lower, offset));
  if (function != null) {
    start = lower + function.start;
    if (end < upper && text[end] == ')') end++;
  }
  return (start: start, end: end, prefix: text.substring(start, offset));
}

List<String> _rank(Iterable<String> names, String raw) {
  final prefix = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final collapsed = prefix.replaceAll('-', '');
  int score(String name) {
    final candidate = name.toLowerCase();
    if (candidate.startsWith(prefix)) return 0;
    if (collapsed.isNotEmpty &&
        candidate.replaceAll('-', '').startsWith(collapsed)) {
      return 1;
    }
    final parts = candidate.split('-'), pieces = prefix.split('-');
    if (pieces.length > 1 &&
        pieces.length <= parts.length &&
        List.generate(
          pieces.length,
          (i) => parts[i].startsWith(pieces[i]),
        ).every((value) => value)) {
      return 2;
    }
    return 3;
  }

  return names.toSet().where((name) => score(name) < 3).toList()..sort((a, b) {
    if (prefix.isEmpty) {
      const secondary = {'inherit', 'initial', 'unset', 'revert', '!important'};
      final group =
          (secondary.contains(a) ? 1 : 0) - (secondary.contains(b) ? 1 : 0);
      if (group != 0) return group;
    }
    final difference = score(a).compareTo(score(b));
    return difference != 0 ? difference : a.compareTo(b);
  });
}

CssCompletionItem _propertyItem(
  String name,
  String text,
  _Token token,
  int upper,
  bool only,
) {
  if (only) {
    return CssCompletionItem(
      label: name,
      detail: cssPropertyDetails[name]!,
      insertText: name,
      caretOffset: name.length,
    );
  }
  var next = token.end;
  while (next < upper && text[next].trim().isEmpty) {
    next++;
  }
  if (next < upper && text[next] == ':') {
    var value = next + 1;
    while (value < upper && text[value].trim().isEmpty) {
      value++;
    }
    return CssCompletionItem(
      label: name,
      detail: cssPropertyDetails[name]!,
      insertText: name,
      caretOffset: name.length + value - token.end,
      continueValues: true,
    );
  }
  final insert = '$name: ${next < upper && text[next] == ';' ? '' : ';'}';
  return CssCompletionItem(
    label: name,
    detail: cssPropertyDetails[name]!,
    insertText: insert,
    caretOffset: name.length + 2,
    continueValues: true,
  );
}

CssCompletionItem _valueItem(String value, String property, String suffix) {
  final opening = value.indexOf('(');
  final existingFunction = value.endsWith('()') && suffix.startsWith('(');
  final insert = existingFunction ? value.substring(0, opening) : value;
  return CssCompletionItem(
    label: value,
    detail: value.startsWith('var(')
        ? '引用当前缓冲中的 CSS 变量'
        : cssValueDetails[value] ??
              '${cssPropertyDetails[property] ?? '属性'}建议值',
    insertText: insert,
    caretOffset: value.endsWith('()') ? opening + 1 : value.length,
  );
}

List<String> _values(String text, String property, String prefix) {
  final number = RegExp(
    r'^([-+]?(?:\d+(?:\.\d*)?|\.\d+))([a-z%]*)$',
    caseSensitive: false,
  ).firstMatch(prefix);
  return [
    ...cssValuesFor(property),
    if (number != null && cssHasLengthValues(property))
      for (final unit in ['px', 'em', 'rem', '%', 'pt', 'ex', 'vw', 'vh'])
        '${number[1]}$unit',
    for (final name in _variables(text)) 'var($name)',
  ];
}

Set<String> _variables(String text) {
  final clean = _masked(text);
  return {
    for (final match in RegExp(r'(--[-_a-zA-Z0-9]+)\s*:').allMatches(clean))
      match[1]!,
  };
}

/// 顺序扫描未完成源码，屏蔽注释、字符串和函数；花括号只跟踪声明层级。
class _CssState {
  _CssState(this.text, bool inline, {this.entities = false})
    : blocks = [inline];
  final String text;
  final bool entities;
  final List<bool> blocks;
  String? quote;
  bool comment = false;
  final functions = <String>[];
  int segment = 0;
  bool get declarations => blocks.last;
  bool get blocked =>
      quote != null || comment || functions.any((name) => name != 'var');

  // 保持单次顺序扫描，状态分支紧邻字符推进，避免拆散后漏跳转义字符。
  void scan(int end) {
    for (var i = 0; i < end; i++) {
      final entity = entities ? _quoteEntity.matchAsPrefix(text, i) : null;
      final char = entity == null ? text[i] : _quoteCharacter(entity[0]!);
      if (entity != null) i = entity.end - 1;
      if (comment) {
        if (char == '*' && i + 1 < end && text[i + 1] == '/') {
          comment = false;
          i++;
        }
        continue;
      }
      if (quote != null) {
        if (char == '\\') {
          i++;
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == '/' && i + 1 < end && text[i + 1] == '*') {
        comment = true;
        i++;
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '(') {
        final name =
            RegExp(r'[-\w]+$').firstMatch(text.substring(segment, i))?[0] ?? '';
        functions.add(name.toLowerCase());
      } else if (char == ')' && functions.isNotEmpty) {
        functions.removeLast();
      }
      if (functions.isNotEmpty) continue;
      if (char == '{') {
        final prelude = _masked(text.substring(segment, i))
            .trim()
            .toLowerCase();
        blocks.add(!_ruleContainer.hasMatch(prelude));
        segment = i + 1;
      } else if (char == '}') {
        if (blocks.length > 1) blocks.removeLast();
        segment = i + 1;
      } else if (char == ';') {
        segment = i + 1;
      }
    }
  }
}

final _ruleContainer = RegExp(
  r'^@(?:media|supports|layer|container|document|scope|(?:-\w+-)?keyframes)\b',
);

final _quoteEntity = RegExp(
  r'&(?:quot|apos|#0*(?:34|39)|#x0*(?:22|27));',
  caseSensitive: false,
);
String _quoteCharacter(String entity) =>
    RegExp(r'(?:quot|34|22);$', caseSensitive: false).hasMatch(entity)
    ? '"'
    : "'";

String _masked(String text) => text.replaceAllMapped(
  RegExp(
    r'''/\*[\s\S]*?(?:\*/|$)|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*' '''.trim(),
  ),
  (match) => ' ' * match[0]!.length,
);

_CssRegion? _htmlRegion(String text, int offset) {
  var cursor = 0;
  while (cursor < text.length) {
    final opening = text.indexOf('<', cursor);
    if (opening < 0 || opening > offset) return null;
    if (text.startsWith('<!--', opening) ||
        text.startsWith('<![CDATA[', opening)) {
      final marker = text.startsWith('<!--', opening) ? '-->' : ']]>';
      final close = text.indexOf(marker, opening + 4);
      cursor = close < 0 ? text.length : close + marker.length;
      if (offset < cursor) return null;
      continue;
    }
    final tag = _htmlTag(text, opening, offset);
    if (tag.region != null) return tag.region;
    if (offset <= tag.end) return null;
    cursor = tag.end + 1;
    if ({'style', 'script', 'textarea', 'title'}.contains(tag.name)) {
      final end = RegExp(
        '</(?:[\\w-]+:)?${tag.name}\\s*>',
        caseSensitive: false,
      ).firstMatch(text.substring(cursor));
      final close = end == null ? text.length : cursor + end.start;
      if (offset <= close) {
        return tag.name == 'style'
            ? (start: cursor, end: close, inline: false)
            : null;
      }
      cursor = end == null ? text.length : cursor + end.end;
    }
  }
  return null;
}

typedef _HtmlTag = ({String name, int end, _CssRegion? region});

_HtmlTag _htmlTag(String text, int start, int offset) {
  final name = RegExp(r'<\s*([\w:-]+)').matchAsPrefix(text, start);
  var cursor = name?.end ?? start + 1;
  while (cursor < text.length) {
    if (text[cursor] == '>') break;
    final attribute = RegExp(r'''([\w:-]+)\s*=\s*(["'])''')
        .matchAsPrefix(text, cursor);
    if (attribute == null) {
      cursor++;
      continue;
    }
    final end = text.indexOf(attribute[2]!, attribute.end);
    final boundary = end < 0 ? text.length : end;
    if (offset >= attribute.end && offset <= boundary) {
      return (
        name: '',
        end: boundary,
        region: attribute[1]!.toLowerCase() == 'style'
            ? (start: attribute.end, end: boundary, inline: true)
            : null,
      );
    }
    cursor = boundary + 1;
  }
  return (
    name: name?[1]?.split(':').last.toLowerCase() ?? '',
    end: cursor,
    region: null,
  );
}
