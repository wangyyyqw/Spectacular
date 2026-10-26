/// 属性名别名与私有属性映射（P9-13）。
///
/// 中文精排 EPUB（多看、掌阅、QQ 阅读）大量使用厂商私有属性：
/// `-duokan-text-indent`、`duokan-paragraph-align`、`-duokan-text-fill` 等。
/// 这些属性不是标准 CSS，但语义与标准属性一一对应；在解析入口统一改名，
/// 后续层叠、计算、绘制全部走标准路径，不必在每个消费点各写一次兼容。
abstract final class CssPropertyAliases {
  /// 多看私有属性 → 标准属性（键为去掉前导 `-` 后的小写名）。
  static const Map<String, String> _aliases = <String, String>{
    'duokan-text-indent': 'text-indent',
    'duokan-paragraph-align': 'text-align',
    'duokan-text-align': 'text-align',
    'duokan-line-height': 'line-height',
    'duokan-letter-spacing': 'letter-spacing',
    'duokan-break-inside': 'break-inside',
    'duokan-page-break-inside': 'page-break-inside',
    'duokan-page-break-before': 'page-break-before',
    'duokan-page-break-after': 'page-break-after',
    'duokan-text-color': 'color',
    // 多看渐变文字：取第一个色标当纯色（渐变本身不支持）。
    'duokan-text-fill': 'color',
    'duokan-text-shadow': 'text-shadow',
    'duokan-text-decoration': 'text-decoration',
    'duokan-font-weight': 'font-weight',
    // 多看排版方向族（竖排 P5 未接入，先按标准属性保存）。
    'duokan-writing-mode': 'writing-mode',
    'duokan-writing-orientation': 'writing-mode',
    'duokan-text-orientation': 'writing-mode',
    'duokan-block-progression': 'writing-mode',
    // 多看段前后距。
    'duokan-margin-before': 'margin-top',
    'duokan-margin-after': 'margin-bottom',
    'duokan-padding-before': 'padding-top',
    'duokan-padding-after': 'padding-bottom',
    'epub-writing-mode': 'writing-mode',
    'epub-text-emphasis': 'text-emphasis',
    'epub-text-emphasis-style': 'text-emphasis-style',
    'epub-text-emphasis-color': 'text-emphasis-color',
  };

  /// 解析一条声明：返回标准属性名与（可能被规整的）值。
  static (String, String) resolve(String property, String value) {
    final raw = property.trim().toLowerCase();
    final normalized = raw.startsWith('-') ? raw.substring(1) : raw;
    final target = _aliases[normalized];
    if (target == null) {
      return (raw, value);
    }
    if (normalized.endsWith('text-fill')) {
      final color = _firstColor(value);
      if (color != null) {
        return (target, color);
      }
    }
    return (target, value);
  }

  static final RegExp _colorPattern = RegExp(
    r'(#[0-9a-fA-F]{3,8}|rgba?\([^)]*\)|hsla?\([^)]*\))',
  );

  static String? _firstColor(String value) =>
      _colorPattern.firstMatch(value)?.group(1);

  /// 值级别的私有关键字（`vertical-align: duokan-middle-line` 等）。
  static String normalizeValue(String value) {
    final trimmed = value.trim();
    if (trimmed == 'duokan-middle-line') {
      return 'middle';
    }
    return trimmed;
  }
}
