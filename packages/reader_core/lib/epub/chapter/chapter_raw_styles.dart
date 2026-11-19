import 'package:reader_core/api.dart' show EpubNode;
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/css/ua_stylesheet.dart';
import 'package:reader_core/parser/document_parser.dart';

import 'chapter_selectors.dart';
import 'chapter_styles.dart' show inlineDeclarationsOf, ruleMediaMatches;
import 'pseudo_element_selector.dart';

/// 原文结构的作者级联，不读取用户字体、装饰或原生文字测量状态。
class ChapterRawStyles {
  ChapterRawStyles(
    this.selectors,
    this.baseStyle,
    this.width,
    List<CssStylesheet> sheets,
  ) : rules = CascadeRuleSet([
        ...uaRules(),
        for (final (index, sheet) in sheets.indexed)
          ...CascadeRule.fromStylesheet(
            sheet,
            origin: CascadeOrigin.author,
            startOrder: 1000 + index * 10000,
          ),
      ]),
      _pseudoRules = _fontPseudoRules(sheets);

  final ChapterSelectors selectors;
  final ComputedStyle baseStyle;
  final double width;
  final CascadeRuleSet rules;
  final List<CascadeRuleSet> _pseudoRules;
  final Map<SelectorElement, ComputedStyle> _anchorStyles = {};
  final Map<SelectorElement, ComputedStyle> _visibilityStyles = {};

  ComputedStyle styleOf(EpubNode node) =>
      _styleFor(selectors.chainOf(node) ?? const [], useBase: true);

  /// 一次遍历分别记录快照依赖的计算字族、声明中命中的书内字族。
  ({Set<String> referenced, List<CssFontFace> candidates}) collectFonts(
    Iterable<List<SelectorElement>> chains,
    List<CssStylesheet> sheets,
  ) {
    final faces = [for (final sheet in sheets) ...sheet.fontFaces];
    final declared = {for (final face in faces) face.family.toLowerCase()};
    final referenced = <String>{};
    final matched = <String>{};
    for (final chain in chains) {
      referenced.addAll(_familiesFor(chain));
      if (matched.length == declared.length) continue;
      for (final declaration in _fontDeclarationsFor(chain)) {
        if (declaration.property == 'font' ||
            declaration.property == 'font-family' ||
            declaration.property.startsWith('--')) {
          final value = declaration.value.toLowerCase();
          matched.addAll(declared.where(value.contains));
        }
      }
    }
    return (
      referenced: Set.unmodifiable(referenced),
      candidates: List.unmodifiable(
        faces.where((face) => matched.contains(face.family.toLowerCase())),
      ),
    );
  }

  Iterable<CssDeclaration> _fontDeclarationsFor(
    List<SelectorElement> chain,
  ) sync* {
    final element = chain.last;
    final ancestors = chain.sublist(0, chain.length - 1);
    bool matches(CascadeRule rule) => rule.selectors.selectors.any(
      (selector) => selector.matches(element, ancestors),
    );

    yield* inlineDeclarationsOf(element.attributes['style']);
    for (final rule in rules.candidatesFor(element)) {
      if (ruleMediaMatches(rule.rule.media, rule.rule.mediaConditions, width) &&
          matches(rule)) {
        yield* rule.rule.declarations;
      }
    }
    for (final group in _pseudoRules) {
      for (final rule in group) {
        if (matches(rule)) yield* rule.rule.declarations;
      }
    }
  }

  Iterable<String> _familiesFor(List<SelectorElement> chain) sync* {
    final parent = _styleFor(chain, useBase: true);
    yield* parent.fontFamilies;
    for (final pseudo in _pseudoRules) {
      yield* Cascade.compute(
        element: chain.last,
        ancestors: chain.sublist(0, chain.length - 1),
        rules: pseudo.candidatesFor(chain.last),
        parent: parent,
        rootFontSize: baseStyle.fontSize,
        containingWidth: width,
        viewportWidth: width,
      ).fontFamilies;
    }
  }

  static List<CascadeRuleSet> _fontPseudoRules(List<CssStylesheet> sheets) {
    final result = <CascadeRuleSet>[];
    for (final pseudo in [
      '::before',
      '::after',
      '::first-letter',
      '::first-line',
    ]) {
      final rules = <CascadeRule>[];
      for (final sheet in sheets) {
        for (final rule in sheet.rules) {
          for (final selector in rule.selector.split(',')) {
            final main = originatingSelector(selector, pseudo);
            if (main == null) continue;
            rules.add(
              CascadeRule(
                rule: CssRule(
                  selector: main,
                  declarations: rule.declarations,
                  media: rule.media,
                  mediaConditions: rule.mediaConditions,
                ),
                origin: CascadeOrigin.author,
                order: rules.length,
              ),
            );
          }
        }
      }
      if (rules.isNotEmpty) result.add(CascadeRuleSet(rules));
    }
    return result;
  }

  ComputedStyle _styleFor(
    List<SelectorElement> chain, {
    required bool useBase,
  }) {
    final cache = useBase ? _anchorStyles : _visibilityStyles;
    ComputedStyle? style = useBase ? baseStyle : null;
    for (var i = 0; i < chain.length; i++) {
      final parent = style;
      style = cache.putIfAbsent(
        chain[i],
        () => Cascade.compute(
          element: chain[i],
          ancestors: chain.sublist(0, i),
          rules: rules.candidatesFor(chain[i]),
          inlineDeclarations: inlineDeclarationsOf(
            chain[i].attributes['style'],
          ),
          parent: parent,
          rootFontSize: baseStyle.fontSize,
          containingWidth: width,
          viewportWidth: width,
        ),
      );
    }
    return style ?? baseStyle;
  }

  /// 满屏分析保留原路径的空 parent 起点与 visibility 子元素覆盖规则。
  bool isRendered(EpubNode node) {
    final chain = selectors.chainOf(node);
    if (chain == null) return true;
    _styleFor(chain, useBase: false);
    if (chain.any(
      (view) => _visibilityStyles[view]?.display == CssDisplay.none,
    )) {
      return false;
    }
    return _visibilityStyles[chain.last]?.visibility != CssVisibility.hidden;
  }

  /// 进度索引保留正文原文的可见性口径，隐藏子树不占图片顺序。
  bool isVisibleElement(ParsedElement element) {
    final chain = selectors.chainForElement(element);
    _styleFor(chain, useBase: true);
    return chain.every((view) {
      final style = _anchorStyles[view]!;
      return style.display != CssDisplay.none &&
          style.visibility == CssVisibility.visible;
    });
  }
}
