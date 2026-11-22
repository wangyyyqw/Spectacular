import 'parser.dart';

/// 阅读器私有契约层（P7-17）：应用通过 CSS 向引擎表达意图，
/// 作者 CSS 不可用。
///
/// 私有命名空间：
/// - 伪类 `:-reader-source(...)`（内容来源）、`:-reader-blank`（空段）等；
/// - 属性 `-reader-*`（如 `-reader-table-fit`、`-reader-image-frame`）。
///
/// 纪律：私有钩子**只允许 UA 与阅读器覆盖层 origin 使用**；作者 CSS
/// 使用时整条规则丢弃（选择器含私有伪类）或剥除声明（属性），并记录
/// 诊断——防止作者 CSS 绕过排版约束。
abstract final class ReaderContract {
  /// 私有属性前缀。
  static const String propertyPrefix = '-reader-';

  /// 私有伪类标记（出现在选择器文本中）。
  static const String pseudoMarker = ':-reader-';

  /// 预留契约名（随对应任务启用；登记于此作为命名空间台账）。
  static const Set<String> reservedProperties = <String>{
    '-reader-table-fit', // 整表缩放（P3-17 评估）
    '-reader-image-frame', // 图片相框（P3-09 评估）
    '-reader-title-page', // 标题页居中
    '-reader-txt-top-image', // 章首置顶图
  };

  /// 选择器是否使用私有伪类。
  static bool selectorIsPrivate(String selector) =>
      selector.contains(pseudoMarker);

  /// 属性是否私有。
  static bool propertyIsPrivate(String property) =>
      property.trim().toLowerCase().startsWith(propertyPrefix);

  /// 过滤一条作者规则：私有选择器 → 整条丢弃；私有属性 → 剥除声明。
  ///
  /// 返回 null 表示整条丢弃；警告随规则解析诊断走（[CssRule.warnings]
  /// 由 [filterAuthorStylesheet] 汇总）。
  static CssRule? filterAuthorRule(CssRule rule, List<String> warnings) {
    if (selectorIsPrivate(rule.selector)) {
      warnings.add(
        'E_READER_PRIVATE_IN_AUTHOR: 选择器「${rule.selector}」使用私有伪类'
        ' $pseudoMarker*，整条规则已丢弃',
      );
      return null;
    }
    final dropped = rule.declarations
        .where((declaration) => propertyIsPrivate(declaration.property))
        .map((declaration) => declaration.property)
        .toSet();
    if (dropped.isEmpty) {
      return rule;
    }
    warnings.add(
      'E_READER_PRIVATE_IN_AUTHOR: 声明 ${dropped.join('、')} 为阅读器私有'
      '属性（$propertyPrefix*），已从「${rule.selector}」剥除',
    );
    return CssRule(
      selector: rule.selector,
      declarations: List<CssDeclaration>.unmodifiable(
        rule.declarations.where(
          (declaration) => !propertyIsPrivate(declaration.property),
        ),
      ),
      media: rule.media,
      mediaConditions: rule.mediaConditions,
    );
  }

  /// 过滤作者样式表：逐条过滤并返回清洗后的规则与警告。
  static (List<CssRule>, List<String>) filterAuthorStylesheet(
    List<CssRule> rules,
  ) {
    final warnings = <String>[];
    final cleaned = <CssRule>[];
    for (final rule in rules) {
      final filtered = filterAuthorRule(rule, warnings);
      if (filtered != null) {
        cleaned.add(filtered);
      }
    }
    return (cleaned, warnings);
  }
}
