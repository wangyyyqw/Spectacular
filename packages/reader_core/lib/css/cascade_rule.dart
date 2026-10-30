import 'parser.dart';
import 'reader_contract.dart';
import 'selector.dart';

/// 样式来源。
enum CascadeOrigin { userAgent, author, inline }

/// 带来源与文档顺序的规则。
class CascadeRule {
  /// 从已解析 CSS 规则创建；选择器在此解析。
  CascadeRule({required this.rule, required this.origin, this.order = 0})
    : selectors = SelectorParser.parse(rule.selector);

  /// 从多规则样式表批量创建。
  ///
  /// 作者 origin（P7-17）：私有钩子过滤——`-reader-*` 属性剥除、
  /// `:-reader-*` 伪类规则整条丢弃，警告写入 [warnings]（可空收集器）。
  static List<CascadeRule> fromStylesheet(
    CssStylesheet sheet, {
    required CascadeOrigin origin,
    int startOrder = 0,
    List<String>? warnings,
  }) {
    var rules = sheet.rules;
    if (origin == CascadeOrigin.author) {
      final (cleaned, contractWarnings) = ReaderContract.filterAuthorStylesheet(
        rules,
      );
      rules = cleaned;
      warnings?.addAll(contractWarnings);
    }
    return <CascadeRule>[
      for (var i = 0; i < rules.length; i++)
        CascadeRule(rule: rules[i], origin: origin, order: startOrder + i),
    ];
  }

  /// 原始规则。
  final CssRule rule;

  /// 选择器组。
  final SelectorList selectors;

  /// 来源。
  final CascadeOrigin origin;

  /// 文档顺序（越小越靠前）。
  final int order;
}
