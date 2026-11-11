import 'value_tokens.dart';

/// 列表标记类型；custom 的字符串独立保存，避免改变原有计数器类型。
enum CssListStyleType {
  disc,
  circle,
  square,
  decimal,
  lowerRoman,
  upperRoman,
  lowerAlpha,
  upperAlpha,
  none,
  custom,
}

typedef CssListStyleValue = ({
  CssListStyleType type,
  String declaration,
  String? text,
});

abstract final class CssListStyles {
  static const _keywords = <String, CssListStyleType>{
    'disc': CssListStyleType.disc,
    'circle': CssListStyleType.circle,
    'square': CssListStyleType.square,
    'decimal': CssListStyleType.decimal,
    'decimal-leading-zero': CssListStyleType.decimal,
    'lower-roman': CssListStyleType.lowerRoman,
    'upper-roman': CssListStyleType.upperRoman,
    'lower-alpha': CssListStyleType.lowerAlpha,
    'lower-latin': CssListStyleType.lowerAlpha,
    'upper-alpha': CssListStyleType.upperAlpha,
    'upper-latin': CssListStyleType.upperAlpha,
    'none': CssListStyleType.none,
  };

  static CssListStyleValue? type(String raw) {
    final value = raw.trim();
    final text = decodeCssString(value);
    if (text != null) {
      return (type: CssListStyleType.custom, declaration: value, text: text);
    }
    final keyword = value.toLowerCase();
    final type = _keywords[keyword];
    return type == null ? null : (type: type, declaration: keyword, text: null);
  }

  /// 未知裸关键词沿用原来的降级，错误字符串或多值长属性不能覆盖旧值。
  static bool validType(String raw) =>
      type(raw) != null || _bareKeyword.hasMatch(raw.trim());

  /// 完整解析简写后才展开；none 根据另一个已指定项确定所属长属性。
  static Map<String, String>? shorthand(String raw) {
    final tokens = cssValueTokens(raw);
    if (tokens == null || tokens.isEmpty) return null;
    if (tokens.length == 1 &&
        _bareKeyword.hasMatch(tokens.single) &&
        type(tokens.single) == null &&
        !_positions.contains(tokens.single.toLowerCase())) {
      return const {};
    }
    final result = <String, String>{};
    var noneCount = 0;
    for (final token in tokens) {
      final lower = token.toLowerCase();
      if (lower == 'none') {
        noneCount++;
        continue;
      }
      final key = _shorthandKey(token);
      if (key == null || result.containsKey(key)) return null;
      result[key] = key == 'list-style-type' ? type(token)!.declaration : token;
    }
    if (!_applyNone(result, noneCount)) return null;
    return {
      'list-style-type': result['list-style-type'] ?? 'disc',
      'list-style-position': result['list-style-position'] ?? 'outside',
      'list-style-image': result['list-style-image'] ?? 'none',
    };
  }

  static String? _shorthandKey(String token) {
    if (type(token) != null) return 'list-style-type';
    if (_positions.contains(token.toLowerCase())) return 'list-style-position';
    if (token.toLowerCase().startsWith('url(') && token.endsWith(')')) {
      return 'list-style-image';
    }
    return null;
  }

  static bool _applyNone(Map<String, String> result, int count) {
    if (count == 0) return true;
    final hasType = result.containsKey('list-style-type');
    final hasImage = result.containsKey('list-style-image');
    if (count > 2 || (hasType && hasImage)) return false;
    if (count == 2 && (hasType || hasImage)) return false;
    result.putIfAbsent('list-style-type', () => 'none');
    result.putIfAbsent('list-style-image', () => 'none');
    return true;
  }

  static String? position(String raw) => shorthand(raw)?['list-style-position'];
  static String? image(String raw) => shorthand(raw)?['list-style-image'];

  static const _positions = {'inside', 'outside'};
  static final _bareKeyword = RegExp(
    r'^[-_a-zA-Z\u0080-\uFFFF][-_\w\u0080-\uFFFF]*$',
  );
}
