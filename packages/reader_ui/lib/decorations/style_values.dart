/// 从版本化样式读取有限数值，非法值回退。
double styleNumber(
  Object? value, {
  required double fallback,
  required double min,
  required double max,
}) {
  if (value is! num || !value.isFinite) return fallback;
  return value.toDouble().clamp(min, max);
}

/// 从样式读取 ARGB 颜色。
int? styleColor(Object? value) =>
    value is int && value >= 0 && value <= 0xFFFFFFFF ? value : null;

/// 从样式读取非空字符串。
String? styleString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// 只消费合法对象形态的 JSON。
Map<String, Object?> styleObject(Object? value) =>
    value is Map<String, Object?> ? value : const <String, Object?>{};
