import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/paint/image_size.dart';

import 'chapter_styles.dart';
import 'chapter_style_resolver.dart';
import 'generated_content.dart';

/// 章节内按文档顺序维护生成内容与计数器，和样式解析、文字测量分离。
class GeneratedChapterContent {
  GeneratedChapterContent(this.styles, this.resolveImageUrl);
  final ChapterStyleResolver styles;
  final String Function(String) resolveImageUrl;
  final Map<String, int> cssCounters = {};

  /// 内在尺寸预测使用独立计数器快照，不推进正式构块的文档序状态。
  GeneratedChapterContent measurementSnapshot() =>
      GeneratedChapterContent(styles, resolveImageUrl)
        ..cssCounters.addAll(cssCounters);
  List<AuxiliaryCssRule> get auxiliaryRules =>
      styles.preparedStyles.auxiliaryRules;
  Map<String, List<AuxiliaryCssRule>> get pseudoRules =>
      styles.preparedStyles.pseudoRules;
  bool _ruleMediaMatches(String? media, List<String> conditions) =>
      ruleMediaMatches(media, conditions, styles.snapshot.width);

  Map<String, String> rawDeclarationsFor(List<SelectorElement> ancestors) {
    if (ancestors.isEmpty) {
      return const <String, String>{};
    }
    final element = ancestors.last;
    final parents = ancestors.sublist(0, ancestors.length - 1);
    final result = <String, String>{};
    for (final rule in auxiliaryRules) {
      if (!rule.selectors.selectors.any(
        (selector) => selector.matches(element, parents),
      )) {
        continue;
      }
      for (final declaration in rule.declarations) {
        result[declaration.property] = declaration.value.trim();
      }
    }
    for (final declaration in inlineDeclarationsOf(
      element.attributes['style'],
    )) {
      result[declaration.property] = declaration.value.trim();
    }
    return result;
  }

  ({String size, String position}) objectFitBackground(
    List<SelectorElement> ancestors,
    ImageIntrinsicSize? intrinsic, {
    required double boxWidth,
    required double boxHeight,
  }) {
    final declarations = rawDeclarationsFor(ancestors);
    final fit = declarations['object-fit']?.trim();
    final declaredPosition = declarations['object-position']?.trim();
    const center = 'center center';
    final position = declaredPosition == null || declaredPosition.isEmpty
        ? center
        : declaredPosition;
    switch (fit) {
      case 'fill':
        // 不保持比例，拉满盒子。
        return (size: '100% 100%', position: position);
      case 'none':
        // 原始尺寸，超出即裁切（背景不缩放）。
        return (size: 'auto', position: position);
      case 'scale-down':
        // min(none, contain)：原图比盒子大时缩到 contain，否则原尺寸。
        final larger =
            intrinsic != null &&
            boxWidth > 0 &&
            boxHeight > 0 &&
            (intrinsic.width > boxWidth || intrinsic.height > boxHeight);
        return (size: larger ? 'contain' : 'auto', position: position);
      case 'cover':
        return (size: 'cover', position: position);
      case 'contain':
      default:
        return (size: 'contain', position: position);
    }
  }

  void applyCounterMap(Map<String, String> declarations) {
    void apply(String property, int Function(int current, int value) step) {
      final raw = declarations[property];
      if (raw == null || raw.isEmpty) {
        return;
      }
      final tokens = raw.split(RegExp(r'\s+'));
      for (var i = 0; i < tokens.length; i += 1) {
        final name = tokens[i];
        if (name.isEmpty || name == 'none') {
          continue;
        }
        var value = property == 'counter-reset' ? 0 : 1;
        if (i + 1 < tokens.length) {
          final parsed = int.tryParse(tokens[i + 1]);
          if (parsed != null) {
            value = parsed;
            i += 1;
          }
        }
        cssCounters[name] = step(cssCounters[name] ?? 0, value);
      }
    }

    apply('counter-reset', (_, value) => value);
    apply('counter-increment', (current, value) => current + value);
  }

  void applyCounters(List<SelectorElement> ancestors) {
    applyCounterMap(rawDeclarationsFor(ancestors));
  }

  String formatCounter(int value, String style) => switch (style) {
    'decimal-leading-zero' =>
      value.abs() < 10 ? '${value < 0 ? '-' : ''}0${value.abs()}' : '$value',
    'lower-alpha' || 'lower-latin' => alphaCounter(value).toLowerCase(),
    'upper-alpha' || 'upper-latin' => alphaCounter(value),
    'lower-roman' => romanCounter(value).toLowerCase(),
    'upper-roman' => romanCounter(value),
    _ => '$value',
  };

  (String, String) quotePairAt(CssQuotes quotes, int depth) {
    switch (quotes) {
      case CssQuotesNone():
        return ('', '');
      case CssQuotesPairs(:final pairs):
        final pair = pairs[depth.clamp(0, pairs.length - 1)];
        return (pair.open, pair.close);
      case CssQuotesAuto():
        return depth == 0 ? ('\u201C', '\u201D') : ('\u2018', '\u2019');
    }
  }

  Map<String, CssDeclaration> winningPseudoDeclarations(
    List<SelectorElement> ancestors,
    String pseudo,
  ) {
    if (ancestors.isEmpty) {
      return const <String, CssDeclaration>{};
    }
    final element = ancestors.last;
    final parents = ancestors.sublist(0, ancestors.length - 1);
    final winners =
        <
          String,
          ({
            CssDeclaration declaration,
            int important,
            Specificity specificity,
            int order,
          })
        >{};
    for (final (order, rule)
        in (pseudoRules[pseudo] ?? const <AuxiliaryCssRule>[]).indexed) {
      if (!_ruleMediaMatches(rule.media, rule.mediaConditions)) {
        continue;
      }
      Specificity? matched;
      for (final selector in rule.selectors.selectors) {
        if (!selector.matches(element, parents)) {
          continue;
        }
        if (matched == null || selector.specificity.compareTo(matched) > 0) {
          matched = selector.specificity;
        }
      }
      if (matched == null) {
        continue;
      }
      for (final declaration in rule.declarations) {
        final important = declaration.important ? 1 : 0;
        final current = winners[declaration.property];
        if (current != null &&
            (important < current.important ||
                (important == current.important &&
                    (matched.compareTo(current.specificity) < 0 ||
                        (matched == current.specificity &&
                            order < current.order))))) {
          continue;
        }
        winners[declaration.property] = (
          declaration: declaration,
          important: important,
          specificity: matched,
          order: order,
        );
      }
    }
    return {
      for (final entry in winners.entries) entry.key: entry.value.declaration,
    };
  }

  String resolveContentImageUrl(String raw) {
    final lower = raw.toLowerCase();
    if (raw.isEmpty ||
        lower.startsWith('data:') ||
        lower.startsWith('http://') ||
        lower.startsWith('https://')) {
      return raw;
    }
    return resolveImageUrl(raw);
  }

  PseudoContent? pseudoContentOf(
    List<SelectorElement> ancestors,
    String pseudo, {
    required CssQuotes quotes,
    required int quoteDepth,
  }) {
    if (ancestors.isEmpty) {
      return null;
    }
    final declarations = winningPseudoDeclarations(ancestors, pseudo);
    final content = declarations['content'];
    if (content == null) {
      return null;
    }
    final value = content.value.trim();
    if (value == 'normal' || value == 'none') {
      return null;
    }
    // 伪元素规则里的计数器声明先生效（见 applyCounterMap 注释）。
    applyCounterMap(<String, String>{
      for (final entry in declarations.entries)
        if (entry.key == 'counter-reset' || entry.key == 'counter-increment')
          entry.key: entry.value.value,
    });
    final evaluated = evaluateContentValue(
      value,
      ancestors: ancestors,
      quotes: quotes,
      quoteDepth: quoteDepth,
      counterValue: (name, style) =>
          formatCounter(cssCounters[name] ?? 0, style),
    );
    return PseudoContent(
      text: evaluated.text,
      images: [
        for (final image in evaluated.images)
          PseudoContentImage(
            offset: image.offset,
            url: resolveContentImageUrl(image.url),
          ),
      ],
    );
  }
}
