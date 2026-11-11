/// 一次排版的视口快照；长度计算不读取全局窗口或可变会话状态。
class CssValueContext {
  const CssValueContext({
    this.viewportWidth,
    this.viewportHeight,
    this.rootIsVertical = false,
    this.rootAxisResolved = false,
  });

  final double? viewportWidth;
  final double? viewportHeight;
  final bool rootIsVertical;
  final bool rootAxisResolved;

  bool get hasViewport =>
      viewportWidth != null &&
      viewportHeight != null &&
      viewportWidth!.isFinite &&
      viewportHeight!.isFinite &&
      viewportWidth! > 0 &&
      viewportHeight! > 0;

  CssValueContext withRootAxis(bool vertical) => CssValueContext(
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    rootIsVertical: vertical,
    rootAxisResolved: true,
  );

  /// 单位换算只触及数值 token，CSS 字符串与资源 URL 保留原文。
  String resolveValue(String raw) {
    if (!hasViewport || (!raw.contains('v') && !raw.contains('V'))) return raw;
    return raw.replaceAllMapped(_viewportTokens, (match) {
      if (match[1] != null) return match[0]!;
      final base = switch (match[3]!.toLowerCase()) {
        'vw' => viewportWidth!,
        'vh' => viewportHeight!,
        'vi' => rootIsVertical ? viewportHeight! : viewportWidth!,
        'vb' => rootIsVertical ? viewportWidth! : viewportHeight!,
        'vmin' =>
          viewportWidth! < viewportHeight! ? viewportWidth! : viewportHeight!,
        _ =>
          viewportWidth! > viewportHeight! ? viewportWidth! : viewportHeight!,
      };
      return '${double.parse(match[2]!) * base / 100}px';
    });
  }

  /// 所有视口单位在计算样式时冻结为像素，百分比仍由包含块解算。
  Map<String, String> resolveValues(Map<String, String> values) {
    if (!hasViewport) return values;
    Map<String, String>? resolved;
    for (final entry in values.entries) {
      if (entry.key.startsWith('--')) continue;
      final value = resolveValue(entry.value);
      if (value == entry.value) continue;
      resolved ??= Map<String, String>.of(values);
      resolved[entry.key] = value;
    }
    return resolved == null ? values : Map.unmodifiable(resolved);
  }
}

final _viewportTokens = RegExp(
  r'''("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|url\((?:\\.|[^)])*\))|(?<![\w.-])([-+]?(?:\d+(?:\.\d+)?|\.\d+))(vmin|vmax|vh|vw|vi|vb)\b''',
  caseSensitive: false,
);

/// 通用数值长度的解析入口；保留原有 calc 算术和百分比基准。
double? resolveCssNumericLength(
  String raw, {
  required double fontSize,
  required double rootFontSize,
  required double percentBase,
}) {
  final value = raw.trim().toLowerCase();
  if (value.startsWith('calc(')) {
    return _evaluateCalc(
      value,
      fontSize: fontSize,
      rootFontSize: rootFontSize,
      percentBase: percentBase,
    );
  }
  final match = _numericLength.firstMatch(value);
  if (match == null) return null;
  return _lengthNumber(
    double.parse(match[1]!),
    match[2],
    fontSize: fontSize,
    rootFontSize: rootFontSize,
    percentBase: percentBase,
  );
}

final _numericLength = RegExp(
  r'^(-?(?:\d+(?:\.\d+)?|\.\d+))(px|pt|pc|in|cm|mm|em|rem|ex|%)?$',
);

double? _lengthNumber(
  double number,
  String? unit, {
  required double fontSize,
  required double rootFontSize,
  required double percentBase,
}) => switch (unit) {
  null || 'px' => number,
  'pt' => number * 96 / 72,
  'pc' => number * 16,
  'in' => number * 96,
  'cm' => number * 96 / 2.54,
  'mm' => number * 96 / 25.4,
  'em' => number * fontSize,
  'rem' => number * rootFontSize,
  'ex' => number * fontSize * 0.5,
  '%' => number * percentBase / 100,
  _ => null,
};

/// 尺寸值：像素 / 百分比 / auto。
///
/// 解析层只记录数值与单位标记，百分比按基准长度解算留到盒模型计算时。
class CssLength {
  /// 创建尺寸值；[isPercent] 为 true 时 [value] 是百分比数字（如 50 表示
  /// 50%）。
  const CssLength(this.value, {this.isAuto = false, this.isPercent = false});

  /// 关键字 `auto`。
  const CssLength.auto() : value = 0, isAuto = true, isPercent = false;

  /// 数值（像素或百分比数字）。
  final double value;

  /// 是否为关键字 `auto`。
  final bool isAuto;

  /// 是否为百分比。
  final bool isPercent;

  /// 按基准长度解算像素；auto 返回 null。
  double? resolve(double base) {
    if (isAuto) {
      return null;
    }
    return isPercent ? value * base / 100 : value;
  }

  @override
  bool operator ==(Object other) =>
      other is CssLength &&
      other.value == value &&
      other.isAuto == isAuto &&
      other.isPercent == isPercent;

  @override
  int get hashCode => Object.hash(value, isAuto, isPercent);

  @override
  String toString() => isAuto
      ? 'CssLength(auto)'
      : (isPercent ? 'CssLength($value%)' : 'CssLength($value)');
}

/// 保留原来的 calc 运算：百分比基准未知时返回 null。
double? _evaluateCalc(
  String raw, {
  required double fontSize,
  required double rootFontSize,
  required double percentBase,
}) {
  var expression = raw.trim();
  if (expression.toLowerCase().startsWith('calc(') &&
      expression.endsWith(')')) {
    expression = expression.substring(5, expression.length - 1);
  }
  final evaluator = _CalcEvaluator(
    expression,
    fontSize: fontSize,
    rootFontSize: rootFontSize,
    percentBase: percentBase,
  );
  final result = evaluator.evaluate();
  return evaluator.finished ? result : null;
}

final RegExp _calcTokenPattern = RegExp(
  r'(\d+(?:\.\d+)?|\.\d+)(px|pt|pc|in|cm|mm|em|rem|ex|%)?|[()+\-*/]|\s+',
);

class _CalcEvaluator {
  _CalcEvaluator(
    this.source, {
    required this.fontSize,
    required this.rootFontSize,
    required this.percentBase,
  }) {
    _tokenize();
  }

  final String source;
  final double fontSize;
  final double rootFontSize;
  final double percentBase;
  final List<String> _tokens = <String>[];
  int _position = 0;
  bool finished = false;

  void _tokenize() {
    var index = 0;
    while (index < source.length) {
      final match = _calcTokenPattern.matchAsPrefix(source, index);
      if (match == null) {
        _tokens
          ..clear()
          ..add('?');
        return;
      }
      final token = match.group(0)!;
      index = match.end;
      if (token.trim().isEmpty) {
        continue;
      }
      _tokens.add(token.trim());
    }
  }

  double? evaluate() {
    if (_tokens.isEmpty || _tokens.first == '?') {
      return null;
    }
    final value = _parseExpression();
    if (value == null || _position != _tokens.length) {
      return null;
    }
    finished = true;
    return value;
  }

  double? _parseExpression() {
    var left = _parseTerm();
    if (left == null) {
      return null;
    }
    while (_position < _tokens.length) {
      final token = _tokens[_position];
      if (token != '+' && token != '-') {
        break;
      }
      _position += 1;
      final right = _parseTerm();
      if (right == null) {
        return null;
      }
      left = token == '+' ? left! + right : left! - right;
    }
    return left;
  }

  double? _parseTerm() {
    var left = _parseFactor();
    if (left == null) {
      return null;
    }
    while (_position < _tokens.length) {
      final token = _tokens[_position];
      if (token != '*' && token != '/') {
        break;
      }
      _position += 1;
      final right = _parseFactor();
      if (right == null) {
        return null;
      }
      if (token == '*') {
        left = left! * right;
      } else {
        if (right == 0) {
          return null;
        }
        left = left! / right;
      }
    }
    return left;
  }

  double? _parseFactor() {
    if (_position >= _tokens.length) {
      return null;
    }
    final token = _tokens[_position];
    if (token == '-') {
      _position += 1;
      final inner = _parseFactor();
      return inner == null ? null : -inner;
    }
    if (token == '(') {
      _position += 1;
      final inner = _parseExpression();
      if (inner == null ||
          _position >= _tokens.length ||
          _tokens[_position] != ')') {
        return null;
      }
      _position += 1;
      return inner;
    }
    final match = _numericLength.firstMatch(token);
    if (match == null) return null;
    _position += 1;
    // calc 的未提供百分比基准仍保留原来的无效结果。
    if (match[2] == '%' && percentBase == 0) return null;
    return _lengthNumber(
      double.parse(match[1]!),
      match[2],
      fontSize: fontSize,
      rootFontSize: rootFontSize,
      percentBase: percentBase,
    );
  }
}
