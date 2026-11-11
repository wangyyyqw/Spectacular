import 'cascade_rule.dart';
import 'cascade_rule_set.dart';
import 'computed_style.dart';
import 'background_declarations.dart';
import 'fragmentation.dart';
import 'parser.dart';
import 'property_aliases.dart';
import 'selector.dart';

export 'cascade_rule.dart';
export 'cascade_rule_set.dart';

/// 层叠与继承。
abstract final class Cascade {
  /// CSS 继承属性：显式 inherit/unset 与默认继承共用此清单。
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
    'text-orientation',
    'direction',
    'hyphens',
    'word-break',
    'overflow-wrap',
    'font-variant',
    'font-variant-caps',
    'font-variant-ligatures',
    'font-kerning',
    'font-stretch',
    'font-size-adjust',
    'quotes',
    'list-style-type',
    'text-emphasis-style',
    'text-emphasis-color',
    'text-emphasis-position',
    'text-justify',
    'ruby-align',
    'white-space',
    'visibility',
    'word-spacing',
    'text-transform',
    'text-align-last',
    'list-style-position',
    'list-style-image',
    'line-break',
    'tab-size',
    'hanging-punctuation',
    'text-spacing-trim',
    'text-autospace',
    'border-collapse',
    'border-spacing',
    'ruby-position',
    'text-combine-upright',
  };

  /// 计算元素样式。
  ///
  /// [ancestors] 从根到父；[rules] 可乱序传入，按 `order` 稳定排序；
  /// [inlineDeclarations] 为 style 属性；[parent] 用于继承。
  /// [viewportWidth] 只用于媒体查询，缺省沿用 [containingWidth]。
  static ComputedStyle compute({
    required SelectorElement element,
    required List<SelectorElement> ancestors,
    required List<CascadeRule> rules,
    List<CssDeclaration> inlineDeclarations = const <CssDeclaration>[],
    ComputedStyle? parent,
    double rootFontSize = 16,
    double containingWidth = 0,
    double? viewportWidth,
    CssValueContext? valueContext,
  }) {
    final winners = <String, _Winner>{};
    final declarations = <_Candidate>[];
    final sorted = rules is CascadeRuleSet ? rules : CascadeRuleSet(rules);

    var sequence = 0;
    for (final rule in sorted) {
      // @media 过滤（P8-02）：条件不命中视口的规则不参与级联。
      final mediaConditions = rule.rule.mediaConditions.isNotEmpty
          ? rule.rule.mediaConditions
          : <String>[?rule.rule.media];
      if (mediaConditions.any(
        (media) => !mediaMatches(media, viewportWidth ?? containingWidth),
      )) {
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
        declarations.add((
          declaration,
          rule.origin,
          matchedSpecificity,
          sequence,
        ));
      }
    }

    for (final declaration in inlineDeclarations) {
      sequence += 1;
      // 内联 style 同样展开简写：flat 管线重建样式时会把继承来的长属性
      // 标成显式，内联 `font`/`margin` 简写不展开就会被那些长属性顶掉。
      declarations.add((
        declaration,
        CascadeOrigin.inline,
        const Specificity(1, 0, 0, 0),
        sequence,
      ));
    }

    final customProperties = _customProperties(declarations, parent);
    for (final (declaration, origin, specificity, order) in declarations) {
      _considerDeclaration(
        winners,
        _resolveDeclaration(declaration, customProperties),
        origin,
        specificity,
        order,
      );
    }

    // 逻辑属性（`margin-inline-start` 等）在级联期就映射成物理属性，并沿用
    // 原声明的来源/优先级/序号参与竞争：否则 `p{margin:8px 0}` 展开出的
    // `margin-left` 会把优先级更高的 `.lp{margin-inline-start:24px}` 顶掉。
    _applyLogicalProperties(winners, parent);

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
    final explicit = winners.keys.toSet();
    for (final entry in winners.entries) {
      final property = entry.key;
      final winner = entry.value;
      var value = winner.value.trim();
      if (_isGlobalKeyword(value)) value = value.toLowerCase();
      if (value == 'inherit' ||
          (value == 'unset' && inheritedProperties.contains(property))) {
        // 继承属性交给类型化父值，不能把 150% / 2em / bolder 再算一次。
        if (inheritedProperties.contains(property) && parent != null) {
          explicit.remove(property);
          continue;
        }
        final inherited = parent?.computedValue(property);
        if (inherited == null) {
          values[property] = ComputedStyle.initialValue(property, rootFontSize);
        } else {
          values[property] = inherited;
        }
        continue;
      }
      if (value == 'initial' || value == 'unset') {
        value = ComputedStyle.initialValue(property, rootFontSize);
      }
      values[property] = value;
      if (property == 'color' && winner.origin != CascadeOrigin.userAgent) {
        explicitTextColor = true;
      }
    }

    var context =
        valueContext ?? parent?.valueContext ?? const CssValueContext();
    if (!context.rootAxisResolved &&
        (parent?.valueContext.rootAxisResolved ?? false)) {
      context = context.withRootAxis(parent!.valueContext.rootIsVertical);
    }
    final root =
        element.tag == 'html' ||
        (element.tag == 'body' && !ancestors.any((item) => item.tag == 'html'));
    final rootMode = root ? values['writing-mode'] : null;
    if (rootMode != null &&
        (!context.rootAxisResolved || element.tag == 'html')) {
      context = context.withRootAxis(
        ComputedStyle.isVerticalWritingMode(rootMode),
      );
    }
    return ComputedStyle(
      Map<String, String>.unmodifiable(values),
      hasExplicitTextColor: explicitTextColor,
      parent: parent,
      explicitProperties: explicit,
      declaredTextProperties: {
        ...?parent?.declaredTextProperties,
        for (final property in const ['text-align', 'text-spacing-trim'])
          if (winners[property] case final winner?
              when winner.origin != CascadeOrigin.userAgent)
            property,
      },
      customProperties: customProperties,
      rootFontSize: rootFontSize,
      containingWidth: containingWidth,
      valueContext: context,
    );
  }

  static Map<String, String> _customProperties(
    List<_Candidate> declarations,
    ComputedStyle? parent,
  ) {
    final winners = <String, _Winner>{};
    for (final (declaration, origin, specificity, order) in declarations) {
      if (declaration.property.startsWith('--')) {
        _considerDeclaration(winners, declaration, origin, specificity, order);
      }
    }
    final variables = <String, String>{...?parent?.customProperties};
    for (final entry in winners.entries) {
      final value = entry.value.value.trim();
      final keyword = value.toLowerCase();
      if (keyword == 'initial') {
        variables.remove(entry.key);
      } else if (keyword != 'inherit' && keyword != 'unset') {
        variables[entry.key] = value;
      }
    }
    return <String, String>{
      for (final entry in variables.entries)
        entry.key: _substituteVars(entry.value, variables, {entry.key}),
    };
  }

  static CssDeclaration _resolveDeclaration(
    CssDeclaration declaration,
    Map<String, String> variables,
  ) {
    if (declaration.property.startsWith('--') ||
        !declaration.value.contains('var(')) {
      return declaration;
    }
    final value = _substituteVars(declaration.value, variables);
    // 变量替换后无效时按 unset 处理，不能恢复被级联覆盖的旧声明。
    final valid =
        value.isNotEmpty &&
        ComputedStyle.isValidDeclaration(declaration.property, value);
    return CssDeclaration(
      property: declaration.property,
      value: valid ? value : 'unset',
      important: declaration.important,
    );
  }

  /// 逻辑属性 → 物理属性（级联期映射）。
  ///
  /// 书写模式/方向取本级赢家，缺省继承父级（`parent.values`），再缺省
  /// `horizontal-tb` + `ltr`。映射出的物理声明沿用逻辑声明自己的
  /// 来源/优先级/序号，和同名的物理声明按相同规则竞争。
  static void _applyLogicalProperties(
    Map<String, _Winner> winners,
    ComputedStyle? parent,
  ) {
    final logicalKeys = <String>[
      for (final key in winners.keys)
        if (key.contains('-inline-') || key.contains('-block-')) key,
    ];
    if (logicalKeys.isEmpty) {
      return;
    }
    final writingMode =
        winners['writing-mode']?.value.trim() ??
        parent?.values['writing-mode'] ??
        'horizontal-tb';
    final direction =
        winners['direction']?.value.trim() ??
        parent?.values['direction'] ??
        'ltr';
    final map = CssPropertyAliases.logicalPhysicalMap(
      writingMode: writingMode,
      direction: direction,
    );
    for (final logical in logicalKeys) {
      final physical = map[logical];
      final winner = winners[logical];
      if (physical == null || winner == null) {
        continue;
      }
      _consider(
        winners,
        physical,
        winner.value,
        winner.origin,
        winner.level,
        winner.specificity,
        winner.order,
      );
    }
  }

  /// 一条声明进候选集：原文 + 简写展开，共用来源/优先级/序号。
  ///
  /// 简写展开（P9-27）：浏览器在级联前把简写拆成长属性，同名长属性才能
  /// 按优先级正确压过 UA 声明。不展开时作者 `p{margin:8px 0}` 会输给 UA
  /// 的 `p{margin:1em 0}` 拆出的 margin-top；`font` 简写同理（不展开会被
  /// UA/继承来的 font-size 等长属性顶掉）。
  static void _considerDeclaration(
    Map<String, _Winner> winners,
    CssDeclaration declaration,
    CascadeOrigin origin,
    Specificity specificity,
    int sequence,
  ) {
    if (!ComputedStyle.isValidDeclaration(
      declaration.property,
      declaration.value,
    )) {
      return;
    }
    final property = CssFragmentation.canonicalProperty(declaration.property);
    final value = CssFragmentation.canonicalValue(
      declaration.property,
      declaration.value,
    );
    final level = _level(origin, declaration.important);
    _consider(winners, property, value, origin, level, specificity, sequence);
    for (final longhand in _expandShorthand(property, value).entries) {
      _consider(
        winners,
        longhand.key,
        longhand.value,
        origin,
        level,
        specificity,
        sequence,
      );
    }
  }

  /// 盒类与文字简写 → 长属性（P9-27）：与浏览器一致，在级联阶段展开，
  /// 这样作者简写与 UA 长属性按同一属性名比优先级。
  static Map<String, String> _expandShorthand(String property, String value) {
    const sides = <String>['top', 'right', 'bottom', 'left'];
    switch (property) {
      case 'text-emphasis':
        if (_isGlobalKeyword(value)) {
          return {'text-emphasis-style': value, 'text-emphasis-color': value};
        }
        return ComputedStyle.parseTextEmphasisShorthand(value) ??
            const <String, String>{};
      case 'font':
        if (_isGlobalKeyword(value)) {
          return {
            for (final key in ComputedStyle.parseFontShorthand(
              '16px serif',
            )!.keys)
              key: value,
          };
        }
        // `font: 700 17px/1.6 serif` → font-size/family/weight/style/line-height。
        return ComputedStyle.parseFontShorthand(value) ??
            const <String, String>{};
      case 'flex':
        if (_isGlobalKeyword(value)) {
          return <String, String>{
            'flex-grow': value,
            'flex-shrink': value,
            'flex-basis': value,
          };
        }
        return ComputedStyle.parseFlexShorthand(value) ??
            const <String, String>{};
      case 'gap':
        if (_isGlobalKeyword(value)) {
          return {'row-gap': value, 'column-gap': value};
        }
        final parts = value.trim().split(RegExp(r'\s+'));
        if (parts.isEmpty || parts.length > 2) {
          return const <String, String>{};
        }
        return {
          'row-gap': parts[0],
          'column-gap': parts.length == 2 ? parts[1] : parts[0],
        };
      case 'margin':
      case 'padding':
      case 'inset':
        final parts = _splitFourValues(value);
        if (parts == null) {
          return const <String, String>{};
        }
        final prefix = property == 'inset' ? '' : '$property-';
        return <String, String>{
          for (var i = 0; i < 4; i++) '$prefix${sides[i]}': parts[i],
        };
      case 'border':
        return <String, String>{
          for (final side in sides) ..._borderLonghands(side, value),
        };
      case 'border-top':
      case 'border-right':
      case 'border-bottom':
      case 'border-left':
        return _borderLonghands(property.substring(7), value);
      case 'border-width':
      case 'border-style':
      case 'border-color':
        final suffix = property.substring('border-'.length);
        final parts = _splitFourValues(value);
        if (parts == null) {
          return const <String, String>{};
        }
        return <String, String>{
          for (var i = 0; i < 4; i++) 'border-${sides[i]}-$suffix': parts[i],
        };
      case 'outline':
        if (_isGlobalKeyword(value)) {
          return {
            for (final suffix in const ['width', 'style', 'color'])
              'outline-$suffix': value,
          };
        }
        final parts = ComputedStyle.parseOutlineShorthand(value);
        return {
          for (final suffix in const ['width', 'style', 'color'])
            'outline-$suffix':
                parts?[suffix] ?? ComputedStyle.initialValue('outline-$suffix'),
        };
      case 'background-position':
        if (_isGlobalKeyword(value)) {
          return {
            'background-position-x': value,
            'background-position-y': value,
          };
        }
        return CssBackgroundDeclarations.positionLonghands(value) ?? const {};
      case 'list-style':
        if (_isGlobalKeyword(value)) {
          return {
            'list-style-type': value,
            'list-style-position': value,
            'list-style-image': value,
          };
        }
        return CssListStyles.shorthand(value) ?? const {};
      case 'background':
        const longhands = <String>[
          'background-image',
          'background-color',
          'background-repeat',
          'background-position',
          'background-position-x',
          'background-position-y',
          'background-size',
          'background-origin',
          'background-clip',
          'background-attachment',
        ];
        if (_isGlobalKeyword(value)) {
          return <String, String>{
            for (final longhand in longhands) longhand: value,
          };
        }
        final parsed = ComputedStyle.parseBackgroundShorthand(value);
        if (parsed == null) {
          return const <String, String>{};
        }
        final axes = CssBackgroundDeclarations.positionLonghands(
          parsed['background-position'] ?? '0% 0%',
        );
        return <String, String>{
          for (final longhand in longhands)
            longhand:
                axes?[longhand] ??
                parsed[longhand] ??
                ComputedStyle.initialValue(longhand),
        };
      case 'text-decoration':
        if (_isGlobalKeyword(value)) {
          return <String, String>{
            for (final longhand in const [
              'text-decoration-line',
              'text-decoration-style',
              'text-decoration-color',
            ])
              longhand: value,
          };
        }
        return ComputedStyle.parseTextDecorationShorthand(value);
      default:
        return const <String, String>{};
    }
  }

  static bool _isGlobalKeyword(String value) =>
      const {'inherit', 'initial', 'unset'}.contains(value.toLowerCase());

  static Map<String, String> _borderLonghands(String side, String value) {
    final parts = ComputedStyle.parseBorderShorthand(value);
    return {
      for (final suffix in const ['width', 'style', 'color'])
        'border-$side-$suffix': _isGlobalKeyword(value)
            ? value
            : parts?[suffix] ??
                  ComputedStyle.initialValue('border-$side-$suffix'),
    };
  }

  /// 按 1~4 值展开为四边；含括号的函数（rgba(...) 等）不拆。
  static List<String>? _splitFourValues(String value) {
    final tokens = <String>[];
    var depth = 0;
    final buffer = StringBuffer();
    for (final rune in value.trim().runes) {
      final char = String.fromCharCode(rune);
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        depth -= 1;
      }
      if (depth == 0 && (char == ' ' || char == '\t' || char == '\n')) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(char);
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }
    if (tokens.isEmpty || tokens.length > 4) {
      return null;
    }
    final frame = value.contains('/') || value.contains('url(');
    if (frame) {
      return null;
    }
    switch (tokens.length) {
      case 1:
        return <String>[tokens[0], tokens[0], tokens[0], tokens[0]];
      case 2:
        return <String>[tokens[0], tokens[1], tokens[0], tokens[1]];
      case 3:
        return <String>[tokens[0], tokens[1], tokens[2], tokens[1]];
      default:
        return tokens;
    }
  }

  /// 解析 `var(--token[, fallback])`（P9-14）：支持嵌套、回退值、循环保护。
  static String _substituteVars(
    String value,
    Map<String, String> variables, [
    Set<String>? stack,
  ]) {
    if (!value.contains('var(')) {
      return value;
    }
    final active = stack ?? <String>{};
    final result = StringBuffer();
    var index = 0;
    while (true) {
      final start = _nextVariable(value, index);
      if (start < 0) {
        result.write(value.substring(index));
        break;
      }
      result.write(value.substring(index, start));
      final end = _functionEnd(value, start + 3);
      if (end < 0) {
        result.write(value.substring(start));
        break;
      }
      final inner = value.substring(start + 4, end);
      final comma = _topLevelComma(inner);
      final name = (comma < 0 ? inner : inner.substring(0, comma)).trim();
      final fallback = comma < 0 ? null : inner.substring(comma + 1).trim();
      String? resolved;
      if (!active.contains(name)) {
        final raw = variables[name];
        if (raw != null) {
          active.add(name);
          resolved = _substituteVars(raw, variables, active);
          active.remove(name);
        }
      }
      if ((resolved == null || resolved.trim().isEmpty) && fallback != null) {
        resolved = _substituteVars(fallback, variables, active);
      }
      result.write(resolved ?? '');
      index = end + 1;
    }
    return result.toString();
  }

  static int _topLevelComma(String value) {
    var depth = 0;
    String? quote;
    for (var i = 0; i < value.length; i += 1) {
      final char = value[i];
      if (char == r'\') {
        i++;
        continue;
      }
      if (quote != null) {
        if (char == quote) quote = null;
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        depth -= 1;
      } else if (char == ',' && depth == 0) {
        return i;
      }
    }
    return -1;
  }

  static int _nextVariable(String value, int start) {
    String? quote;
    for (var i = start; i < value.length; i++) {
      final char = value[i];
      if (char == r'\') {
        i++;
      } else if (quote != null) {
        if (char == quote) quote = null;
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (value.startsWith('var(', i) &&
          (i == 0 || !_nameCharacter.hasMatch(value[i - 1]))) {
        return i;
      }
    }
    return -1;
  }

  static int _functionEnd(String value, int opening) {
    var depth = 0;
    String? quote;
    for (var i = opening; i < value.length; i++) {
      final char = value[i];
      if (char == r'\') {
        i++;
      } else if (quote != null) {
        if (char == quote) quote = null;
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == '(') {
        depth++;
      } else if (char == ')' && --depth == 0) {
        return i;
      }
    }
    return -1;
  }

  static final _nameCharacter = RegExp(r'[-_\w\u0080-\uFFFF]');

  /// @media 求值（P8-02，CSS 2.1 简化）：媒体类型 all/screen 命中、
  /// print/speech 不命中（阅读器按屏媒渲染）；min/max-width(px) 对
  /// 视口宽；逗号=或、and=与、not=非。
  static bool mediaMatches(String media, double viewportWidth) {
    for (final clause in media.toLowerCase().split(',')) {
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
    final m = RegExp(r'\((min|max)-width\s*:\s*([\d.]+)(px|em)?\)')
        .firstMatch(f);
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
    final propertyKey = property.startsWith('--')
        ? property.trim()
        : property.trim().toLowerCase();
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
    // UA 正常 < 作者正常 < 内联正常 < 作者 !important < 内联 !important。
    // EPUB 的 style 属性也是作者声明，普通内联不能压过 !important。
    CascadeOrigin.userAgent => 0,
    CascadeOrigin.author => important ? 3 : 1,
    CascadeOrigin.inline => important ? 4 : 2,
  };
}

typedef _Candidate = (CssDeclaration, CascadeOrigin, Specificity, int);

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
