/// 分页声明的规范槽位与阅读器策略。
///
/// CSS Fragmentation 3 §3.4 要求旧的 page-break-* 与 break-* 共同参与
/// 层叠；这里在竞争前改名，避免消费端各自决定新旧属性的优先级。
abstract final class CssFragmentation {
  static const _breakInsideValues = {
    'auto',
    'avoid',
    'avoid-page',
    'avoid-column',
    'avoid-region',
  };
  static const _breakValues = {
    'auto',
    'always',
    'avoid',
    'avoid-page',
    'page',
    'left',
    'right',
    'recto',
    'verso',
    'avoid-column',
    'column',
    'avoid-region',
    'region',
  };
  static const _legacyProperties = {
    'page-break-before',
    'page-break-after',
    'page-break-inside',
    'orphans',
    'widows',
  };

  /// 阅读器按合法断点尽量填满页面，不执行孤行／寡行限制。
  /// 该策略也覆盖作者的 !important 声明，与强制断页和成组规则独立。
  static bool isIgnored(String property) =>
      property == 'orphans' || property == 'widows';

  /// 旧属性是新属性的别名；原始声明仍由 CSS AST 保留用于诊断。
  static String canonicalProperty(String property) => switch (property) {
    'page-break-before' => 'break-before',
    'page-break-after' => 'break-after',
    'page-break-inside' => 'break-inside',
    _ => property,
  };

  static bool isBreakProperty(String property) => const {
    'break-before',
    'break-after',
    'break-inside',
  }.contains(canonicalProperty(property));

  /// 旧 always 对应分页介质的 page；CSS-wide 关键字不在这里解算。
  static String canonicalValue(String property, String value) {
    if (!isBreakProperty(property)) return value;
    final normalized = value.trim().toLowerCase();
    return normalized == 'always' ? 'page' : normalized;
  }

  /// 已实现的分页语义；left/right 暂只强制换页，不补奇偶空白页。
  static bool forcesPage(String? value) =>
      const {'page', 'left', 'right'}.contains(value);

  static bool avoidsPage(String? value) =>
      value == 'avoid' || value == 'avoid-page';

  /// 保留规范中的列／区域值，其当前行为不冒充页分页能力。
  static bool isValidValue(String property, String raw) {
    final value = raw.trim().toLowerCase();
    if (const {'inherit', 'initial', 'unset'}.contains(value) ||
        raw.contains('var(')) {
      return true;
    }
    if (property == 'page-break-inside') {
      return const {'auto', 'avoid'}.contains(value);
    }
    if (property.startsWith('page-break-')) {
      return const {'auto', 'always', 'avoid', 'left', 'right'}.contains(value);
    }
    if (property == 'break-inside') {
      return _breakInsideValues.contains(value);
    }
    return _breakValues.contains(value);
  }

  static bool _needsNormalization(Map<String, String> values) {
    if (_legacyProperties.any(values.containsKey)) return true;
    for (final property in const [
      'break-before',
      'break-after',
      'break-inside',
    ]) {
      final value = values[property];
      if (value == null) continue;
      if (!isValidValue(property, value) ||
          value != canonicalValue(property, value) ||
          const {'inherit', 'initial', 'unset'}.contains(value)) {
        return true;
      }
    }
    return false;
  }

  /// 直接构造样式的兼容入口，按 Map 声明顺序合并新旧别名。
  static Map<String, String> normalizeValues(
    Map<String, String> values, {
    String? Function(String)? inheritedValue,
  }) {
    if (!_needsNormalization(values)) return values;
    final result = <String, String>{};
    for (final entry in values.entries) {
      if (isIgnored(entry.key)) continue;
      if (isBreakProperty(entry.key) && !isValidValue(entry.key, entry.value)) {
        continue;
      }
      final property = canonicalProperty(entry.key);
      final value = canonicalValue(entry.key, entry.value);
      result[property] = isBreakProperty(property)
          ? switch (value) {
              'inherit' => inheritedValue?.call(property) ?? 'auto',
              'initial' || 'unset' => 'auto',
              _ => value,
            }
          : value;
    }
    return Map<String, String>.unmodifiable(result);
  }

  static Set<String> normalizeProperties(Set<String> properties) {
    if (!_legacyProperties.any(properties.contains)) return properties;
    return {
      for (final property in properties)
        if (!isIgnored(property)) canonicalProperty(property),
    };
  }
}
