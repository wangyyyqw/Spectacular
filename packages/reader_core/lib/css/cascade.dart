import 'computed_style.dart';
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

/// 层叠与继承。
abstract final class Cascade {
  /// 权威继承字段（技术方案 §51.2 的 18 项）。
  static const inheritedProperties = <String>{
    'color',
    'font-family',
    'font-size',
    'font-style',
    'font-weight',
    'line-height',
    'letter-spacing',
    'text-align',
    'text-indent',
    'text-shadow',
    'writing-mode',
    'list-style-type',
    'text-emphasis-style',
    'text-emphasis-color',
    'text-emphasis-position',
    'text-justify',
    'ruby-align',
    'white-space',
  };

  /// 计算元素样式。
  ///
  /// [ancestors] 从根到父；[rules] 可乱序传入，按 `order` 稳定排序；
  /// [inlineDeclarations] 为 style 属性；[parent] 用于继承。
  static ComputedStyle compute({
    required SelectorElement element,
    required List<SelectorElement> ancestors,
    required List<CascadeRule> rules,
    List<CssDeclaration> inlineDeclarations = const <CssDeclaration>[],
    ComputedStyle? parent,
    double rootFontSize = 16,
    double containingWidth = 0,
  }) {
    final winners = <String, _Winner>{};
    final sorted =
        <(CascadeRule, int)>[
          for (var i = 0; i < rules.length; i++) (rules[i], i),
        ]..sort((a, b) {
          final byOrder = a.$1.order.compareTo(b.$1.order);
          return byOrder != 0 ? byOrder : a.$2.compareTo(b.$2);
        });

    var sequence = 0;
    for (final entry in sorted) {
      final rule = entry.$1;
      // @media 过滤（P8-02）：条件不命中视口的规则不参与级联。
      final media = rule.rule.media;
      if (media != null && !mediaMatches(media, containingWidth)) {
        continue;
      }
      Specificity? matchedSpecificity;
      for (final selector in rule.selectors.selectors) {
        if (!selector.matches(element, ancestors)) {
          continue;
        }
        if (matchedSpecificity == null ||
            selector.specificity.compareTo(matchedSpecificity) > 0) {
          matchedSpecificity = selector.specificity;
        }
      }
      if (matchedSpecificity == null) {
        continue;
      }
      for (final declaration in rule.rule.declarations) {
        sequence += 1;
        _consider(
          winners,
          declaration.property,
          declaration.value,
          rule.origin,
          _level(rule.origin, declaration.important),
          matchedSpecificity,
          sequence,
        );
        // `list-style` 简写展开（P9-12）：不展开的话作者简写会被 UA 的
        // `ul { list-style-type: disc }` 长属性按属性名抢先命中。
        if (declaration.property == 'list-style') {
          final keyword = ComputedStyle.parseListStyleTypeKeyword(
            declaration.value,
          );
          if (keyword != null) {
            _consider(
              winners,
              'list-style-type',
              keyword.$2,
              rule.origin,
              _level(rule.origin, declaration.important),
              matchedSpecificity,
              sequence,
            );
          }
        }
      }
    }

    for (final declaration in inlineDeclarations) {
      sequence += 1;
      _consider(
        winners,
        declaration.property,
        declaration.value,
        CascadeOrigin.inline,
        _level(CascadeOrigin.inline, declaration.important),
        const Specificity(1, 0, 0, 0),
        sequence,
      );
    }

    final values = <String, String>{};
    if (parent != null) {
      for (final property in inheritedProperties) {
        final value = parent.values[property];
        if (value != null) {
          values[property] = value;
        }
      }
    }
    var explicitTextColor = false;
    for (final entry in winners.entries) {
      final property = entry.key;
      final winner = entry.value;
      var value = winner.value.trim();
      if (value == 'inherit' ||
          (value == 'unset' && inheritedProperties.contains(property))) {
        final inherited = parent?.values[property];
        if (inherited == null) {
          values.remove(property);
        } else {
          values[property] = inherited;
        }
        continue;
      }
      values[property] = value;
      if (property == 'color' && winner.origin != CascadeOrigin.userAgent) {
        explicitTextColor = true;
      }
    }

    return ComputedStyle(
      Map<String, String>.unmodifiable(values),
      hasExplicitTextColor: explicitTextColor,
      parent: parent,
      explicitProperties: winners.keys.toSet(),
      rootFontSize: rootFontSize,
      containingWidth: containingWidth,
    );
  }

  /// @media 求值（P8-02，CSS 2.1 简化）：媒体类型 all/screen 命中、
  /// print/speech 不命中（阅读器按屏媒渲染）；min/max-width(px) 对
  /// 视口宽；逗号=或、and=与、not=非。
  static bool mediaMatches(String media, double viewportWidth) {
    for (final clause in media.split(',')) {
      if (_mediaClause(clause.trim(), viewportWidth)) {
        return true;
      }
    }
    return false;
  }

  static bool _mediaClause(String clause, double width) {
    var text = clause;
    var negate = false;
    if (text.startsWith('not ')) {
      negate = true;
      text = text.substring(4).trim();
    }
    if (text.startsWith('only ')) {
      text = text.substring(5).trim();
    }
    var result = true;
    for (final part in text.split(RegExp(r'\s+and\s+'))) {
      if (!_mediaFeature(part.trim(), width)) {
        result = false;
        break;
      }
    }
    return negate ? !result : result;
  }

  static bool _mediaFeature(String feature, double width) {
    final f = feature.toLowerCase();
    if (f.isEmpty || f == 'all' || f == 'screen') {
      return true;
    }
    if (f == 'print' || f == 'speech' || f == 'handheld' || f == 'aural') {
      return false;
    }
    final m = RegExp(
      r'\((min|max)-width\s*:\s*([\d.]+)(px|em)?\)',
    ).firstMatch(f);
    if (m == null) {
      return false;
    }
    final isMin = m.group(1) == 'min';
    final value = double.tryParse(m.group(2)!) ?? 0;
    final unit = m.group(3);
    final px = unit == 'em' ? value * 16 : value;
    return isMin ? width >= px : width <= px;
  }

  static void _consider(
    Map<String, _Winner> winners,
    String property,
    String value,
    CascadeOrigin origin,
    int level,
    Specificity specificity,
    int order,
  ) {
    final propertyKey = property.trim().toLowerCase();
    if (propertyKey.isEmpty || value.trim().isEmpty) {
      return;
    }
    final candidate = _Winner(
      value: value,
      origin: origin,
      level: level,
      specificity: specificity,
      order: order,
    );
    final current = winners[propertyKey];
    if (current == null || candidate.compareTo(current) >= 0) {
      winners[propertyKey] = candidate;
    }
  }

  static int _level(CascadeOrigin origin, bool important) => switch (origin) {
    // UA 正常 < 作者正常 < 作者 !important < 内联正常 < 内联 !important。
    // 与方案 §7.2 的合并顺序一致；标准 CSS 中作者 !important 通常高于
    // 内联正常，这里按阅读器方案固定为内联优先。
    CascadeOrigin.userAgent => 0,
    CascadeOrigin.author => important ? 2 : 1,
    CascadeOrigin.inline => important ? 4 : 3,
  };
}

class _Winner implements Comparable<_Winner> {
  const _Winner({
    required this.value,
    required this.origin,
    required this.level,
    required this.specificity,
    required this.order,
  });

  final String value;
  final CascadeOrigin origin;
  final int level;
  final Specificity specificity;
  final int order;

  @override
  int compareTo(_Winner other) {
    final byLevel = level.compareTo(other.level);
    if (byLevel != 0) {
      return byLevel;
    }
    final bySpecificity = specificity.compareTo(other.specificity);
    if (bySpecificity != 0) {
      return bySpecificity;
    }
    return order.compareTo(other.order);
  }
}
