import 'background_values.dart';
import 'length.dart';
import 'value_tokens.dart';

/// 背景长属性的语法与简写展开；层叠优先级仍由 Cascade 处理。
abstract final class CssBackgroundDeclarations {
  static CssBackgroundRepeat? repeat(String? raw) {
    final tokens = cssValueTokens(raw?.trim().toLowerCase() ?? '');
    if (tokens == null || tokens.isEmpty || tokens.length > 2) return null;
    if (tokens.length == 1) {
      if (tokens[0] == 'repeat-x') return CssBackgroundRepeat.repeatX;
      if (tokens[0] == 'repeat-y') return CssBackgroundRepeat.repeatY;
    }
    final x = _repeatMode(tokens[0]);
    final y = _repeatMode(tokens.length == 1 ? tokens[0] : tokens[1]);
    return x == null || y == null ? null : CssBackgroundRepeat.axes(x, y);
  }

  static CssBackgroundRepeatMode? _repeatMode(String value) => switch (value) {
    'repeat' => CssBackgroundRepeatMode.repeat,
    'no-repeat' => CssBackgroundRepeatMode.noRepeat,
    'space' => CssBackgroundRepeatMode.space,
    'round' => CssBackgroundRepeatMode.round,
    _ => null,
  };

  static Map<String, String>? positionLonghands(String raw) {
    final layers = cssValueTokens(raw, separator: ',');
    if (layers == null || layers.isEmpty) return null;
    final x = <String>[];
    final y = <String>[];
    for (final layer in layers) {
      final pair = position(layer);
      if (pair == null) return null;
      x.add(pair.$1);
      y.add(pair.$2);
    }
    return {
      'background-position-x': x.join(', '),
      'background-position-y': y.join(', '),
    };
  }

  static (String, String)? position(String raw) {
    final tokens = cssValueTokens(raw.toLowerCase());
    if (tokens == null || tokens.isEmpty || tokens.length > 2) return null;
    var x = tokens[0];
    var y = tokens.length == 1 ? 'center' : tokens[1];
    if (((x == 'top' || x == 'bottom') &&
            const {'left', 'center', 'right'}.contains(y)) ||
        (x == 'center' && (y == 'left' || y == 'right'))) {
      final swap = x;
      x = y;
      y = swap;
    }
    return validAxis(x, horizontal: true) && validAxis(y, horizontal: false)
        ? (x, y)
        : null;
  }

  static bool validAxis(String raw, {required bool horizontal}) {
    final value = raw.trim().toLowerCase();
    if ((horizontal
            ? const {'left', 'center', 'right'}
            : const {'top', 'center', 'bottom'})
        .contains(value)) {
      return true;
    }
    return resolveCssNumericLength(
          const CssValueContext(
            viewportWidth: 100,
            viewportHeight: 100,
          ).resolveValue(value),
          fontSize: 16,
          rootFontSize: 16,
          percentBase: 100,
        )?.isFinite ??
        false;
  }

  static CssLength? axis(
    String raw, {
    required double fontSize,
    required double rootFontSize,
  }) {
    final value = raw.trim().toLowerCase();
    final keyword = switch (value) {
      'left' || 'top' => 0.0,
      'center' => 50.0,
      'right' || 'bottom' => 100.0,
      _ => null,
    };
    if (keyword != null) return CssLength(keyword, isPercent: true);
    if (value.endsWith('%')) {
      final number = double.tryParse(value.substring(0, value.length - 1));
      if (number != null && number.isFinite) {
        return CssLength(number, isPercent: true);
      }
    }
    final length = resolveCssNumericLength(
      value,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
      percentBase: 0,
    );
    return length == null ? null : CssLength(length);
  }

  /// 一层无效即放弃整个简写，不能用残余 token 覆盖较早的有效声明。
  static Map<String, String>? shorthand(
    String raw, {
    required bool Function(String) isColor,
    required bool Function(String) isImage,
  }) {
    final layers = cssValueTokens(raw, separator: ',');
    if (layers == null || layers.isEmpty) return null;
    final parsed = <Map<String, String>>[];
    for (var i = 0; i < layers.length; i++) {
      final tokens = cssValueTokens(layers[i], separateSlash: true);
      if (tokens == null || tokens.isEmpty) return null;
      final layer = _BackgroundLayerParser(
        tokens,
        isColor: isColor,
        isImage: isImage,
        allowColor: i == layers.length - 1,
      ).parse();
      if (layer == null) return null;
      parsed.add(layer);
    }
    return {
      for (final entry in _initials.entries)
        entry.key: parsed
            .map((layer) => layer[entry.key] ?? entry.value)
            .join(', '),
      'background-color': parsed.last['background-color'] ?? 'transparent',
    };
  }

  static const _initials = {
    'background-image': 'none',
    'background-repeat': 'repeat',
    'background-position': '0% 0%',
    'background-size': 'auto',
    'background-origin': 'padding-box',
    'background-clip': 'border-box',
    'background-attachment': 'scroll',
  };
}

class _BackgroundLayerParser {
  _BackgroundLayerParser(
    this.tokens, {
    required this.isColor,
    required this.isImage,
    required this.allowColor,
  });

  final List<String> tokens;
  final bool Function(String) isColor;
  final bool Function(String) isImage;
  final bool allowColor;
  final values = <String, String>{};
  var index = 0;
  var boxCount = 0;

  Map<String, String>? parse() {
    while (index < tokens.length) {
      if (!_consume(tokens[index++])) return null;
    }
    return values;
  }

  bool _consume(String token) {
    final lower = token.toLowerCase();
    if (isImage(token)) return _put('background-image', token);
    if (isColor(token)) {
      return allowColor && _put('background-color', token);
    }
    if (_repeats.contains(lower)) return _repeat(lower);
    if (const {'scroll', 'fixed', 'local'}.contains(lower)) {
      return _put('background-attachment', lower);
    }
    if (const {'border-box', 'padding-box', 'content-box'}.contains(lower)) {
      if (++boxCount > 2) return false;
      if (boxCount == 1) values['background-origin'] = lower;
      values['background-clip'] = lower;
      return true;
    }
    return _position(token);
  }

  bool _put(String key, String value) {
    if (values.containsKey(key)) return false;
    values[key] = value;
    return true;
  }

  bool _repeat(String first) {
    var value = first;
    if (index < tokens.length &&
        _repeats.contains(tokens[index].toLowerCase())) {
      value = '$first ${tokens[index++].toLowerCase()}';
    }
    return CssBackgroundDeclarations.repeat(value) != null &&
        _put('background-repeat', value);
  }

  bool _position(String first) {
    if (!_positionToken(first)) return false;
    final parts = [first];
    while (index < tokens.length && _positionToken(tokens[index])) {
      parts.add(tokens[index++]);
    }
    final pair = CssBackgroundDeclarations.position(parts.join(' '));
    if (pair == null || !_put('background-position', '${pair.$1} ${pair.$2}')) {
      return false;
    }
    if (index >= tokens.length || tokens[index] != '/') return true;
    index++;
    return _size();
  }

  bool _size() {
    if (index >= tokens.length) return false;
    final first = tokens[index++].toLowerCase();
    if (first == 'cover' || first == 'contain') {
      return _put('background-size', first);
    }
    if (!_sizeToken(first)) return false;
    var value = first;
    if (index < tokens.length && _sizeToken(tokens[index].toLowerCase())) {
      value = '$first ${tokens[index++].toLowerCase()}';
    }
    return _put('background-size', value);
  }

  static bool _positionToken(String value) =>
      CssBackgroundDeclarations.validAxis(value, horizontal: true) ||
      CssBackgroundDeclarations.validAxis(value, horizontal: false);

  static bool _sizeToken(String value) {
    if (value == 'auto') return true;
    final resolved = resolveCssNumericLength(
      const CssValueContext(
        viewportWidth: 100,
        viewportHeight: 100,
      ).resolveValue(value),
      fontSize: 16,
      rootFontSize: 16,
      percentBase: 100,
    );
    return resolved != null && resolved.isFinite && resolved >= 0;
  }

  static const _repeats = {
    'repeat',
    'no-repeat',
    'space',
    'round',
    'repeat-x',
    'repeat-y',
  };
}
