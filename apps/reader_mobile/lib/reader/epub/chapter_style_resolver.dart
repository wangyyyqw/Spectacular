import 'dart:math' as math;

import 'package:reader_core/api.dart' hide ComputedStyle, Paginator;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/text_aggregator.dart';

import 'chapter_layout_job.dart';
import 'chapter_selectors.dart';
import 'chapter_styles.dart';
import 'block_style_helpers.dart';
import 'generated_content.dart';

/// 一次章节作业的级联与容器样式临时状态；全部度量输入来自快照。
class ChapterStyleResolver {
  ChapterStyleResolver(this.snapshot, this.selectorIndex, this.preparedStyles);

  final LayoutSnapshot snapshot;
  final ChapterSelectors selectorIndex;
  final ChapterCascadePreparation preparedStyles;
  double get contentWidth => snapshot.width;
  late final ComputedStyle style = _applyCustomFont(
    snapshot.overrides.apply(snapshot.baseStyle, containingWidth: contentWidth),
  );
  CascadeRuleSet get cascadeRules => preparedStyles.cascadeRules;
  Map<String, List<AuxiliaryCssRule>> get pseudoRules =>
      preparedStyles.pseudoRules;
  final Map<String, ComputedStyle> chainStyleCache = {};
  final Map<SelectorElement, String> viewKeys = {};
  final Map<SelectorElement, ComputedStyle> promotedInlineStyles = {};
  final Map<EpubNode, SelectorElement> fallbackViews = {};
  final Map<SelectorElement, PageContainer> retainedContainers = {};
  final Set<SelectorElement> splitInlineContainers = {};
  final Map<String, CascadeRuleSet> pseudoCascadeRules = {};
  int fallbackViewId = 0;
  bool containerBorderedForLastChain = false;
  double promotedLeftForLastChain = 0;
  double effectiveOpacityForLastChain = 1;

  ComputedStyle _applyCustomFont(ComputedStyle computed) =>
      snapshot.fonts.applyCustomFont(computed, snapshot.overrides);
  double _textWidthFor(ComputedStyle style) =>
      math.max(24, style.contentBoxWidth(contentWidth));
  bool _ruleMediaMatches(String? media, List<String> conditions) =>
      ruleMediaMatches(media, conditions, contentWidth);

  SelectorElement selectorViewOf(EpubNode node) {
    final original = selectorIndex.chainOf(node)?.last;
    if (original != null) return original;
    return fallbackViews.putIfAbsent(node, () {
      final (tag, attributes, children) = switch (node) {
        BlockNode() => (node.tag, node.attributes, node.children),
        InlineNode() => (node.tag, node.attributes, node.children),
        _ => ('reader-anonymous', const <String, String>{}, const <EpubNode>[]),
      };
      return ChapterNodeView(tag, attributes, [
        for (final child in children)
          if (child is BlockNode || child is InlineNode) selectorViewOf(child),
      ], cacheIdentity: 'generated:${fallbackViewId++}');
    });
  }

  ComputedStyle chainStyle(List<SelectorElement> chain) {
    if (chain.isEmpty) {
      return style;
    }
    final promoted = promotedInlineStyles[chain.last];
    if (promoted != null) return promoted;
    var containing = contentWidth;
    for (final ancestor in chain.take(chain.length - 1)) {
      final box = retainedContainers[ancestor];
      if (box != null) containing = box.contentWidth;
    }
    final key = '${_chainKey(chain, viewKeys, cascadeRules)}@$containing';
    return chainStyleCache.putIfAbsent(key, () {
      final parent = chain.length > 1
          ? chainStyle(chain.sublist(0, chain.length - 1))
          : style;
      return _applyCustomFont(
        Cascade.compute(
          element: chain.last,
          ancestors: chain.sublist(0, chain.length - 1),
          rules: cascadeRules.candidatesFor(chain.last),
          inlineDeclarations: snapshot.fonts.rewriteDeclarations(
            inlineDeclarationsOf(chain.last.attributes['style']),
          ),
          parent: parent,
          rootFontSize: style.fontSize,
          containingWidth: containing,
          viewportWidth: contentWidth,
        ),
      );
    });
  }

  double textWidthInFloat(List<SelectorElement> chain, double floatWidth) {
    var firstChild = chain.length - 1;
    for (var i = chain.length - 2; i >= 0; i--) {
      if (floatSideOfStyle(chainStyle(chain.sublist(0, i + 1))) != null) {
        firstChild = i + 1;
        break;
      }
    }
    // 浮动内容宽不含自身占位外边距；只扣内部各层原始盒模型，避免
    // styleForChain 为绘制累加的祖先边距被重复扣除。
    var width = floatWidth;
    for (var i = firstChild; i < chain.length; i++) {
      width = chainStyle(chain.sublist(0, i + 1)).contentBoxWidth(width);
    }
    return math.max(24.0, width);
  }

  ComputedStyle pseudoStyleFor(
    List<SelectorElement> ancestors,
    ComputedStyle parent,
    String pseudo,
  ) {
    if (ancestors.isEmpty) {
      return parent;
    }
    final rules = pseudoCascadeRules.putIfAbsent(
      pseudo,
      () => CascadeRuleSet([
        for (final (index, rule)
            in (pseudoRules[pseudo] ?? const <AuxiliaryCssRule>[]).indexed)
          CascadeRule(
            rule: CssRule(
              selector: rule.selectorText,
              declarations: rule.declarations,
              media: rule.media,
              mediaConditions: rule.mediaConditions,
            ),
            origin: CascadeOrigin.author,
            order: index,
          ),
      ]),
    );
    return _applyCustomFont(
      Cascade.compute(
        element: ancestors.last,
        ancestors: ancestors.sublist(0, ancestors.length - 1),
        rules: rules.candidatesFor(ancestors.last),
        parent: parent,
        rootFontSize: style.fontSize,
        containingWidth: _textWidthFor(parent),
        viewportWidth: contentWidth,
      ),
    );
  }

  CssDisplay inlineDisplay(InlineNode node, List<MarkSubject> ancestors) {
    final structural = selectorIndex.chainOf(node);
    final computed = chainStyle(
      structural ??
          [
            for (final ancestor in ancestors)
              ChapterNodeView(ancestor.tag, ancestor.attributes, const []),
            ChapterNodeView(node.tag, node.attributes, const []),
          ],
    );
    // ComputedStyle 的块排版缺省值是 block；仅明确的块/隐藏声明改变聚合。
    return switch (computed.values['display']?.trim().toLowerCase()) {
      'block' => CssDisplay.block,
      'none' => CssDisplay.none,
      'inline-block' => CssDisplay.inlineBlock,
      _ => CssDisplay.inline,
    };
  }

  double listIndentOf(List<SelectorElement> ancestors) {
    var indent = 0.0;
    for (var i = 0; i < ancestors.length; i++) {
      final tag = ancestors[i].tag.toLowerCase();
      if (tag != 'ul' && tag != 'ol') {
        continue;
      }
      final style = chainStyle(ancestors.sublist(0, i + 1));
      indent +=
          style.margin.left + style.borders.left.width + style.padding.left;
    }
    return indent;
  }

  List<SelectorElement> inlineMarkChain(
    InlineMark mark,
    List<SelectorElement> ancestors,
  ) {
    // CSS 提升的 span 也可能是当前块；按来源属性身份截去已在上下文中的链。
    final start =
        mark.chain.lastIndexWhere(
          (subject) => ancestors.any(
            (ancestor) =>
                ancestor.tag == subject.tag &&
                identical(ancestor.attributes, subject.attributes),
          ),
        ) +
        1;
    return [
      ...ancestors,
      for (final subject in mark.chain.skip(start))
        ChapterNodeView(
          subject.tag.toLowerCase(),
          subject.attributes.containsKey('class') || subject.classes.isEmpty
              ? subject.attributes
              : {'class': subject.classes.join(' '), ...subject.attributes},
          const <SelectorElement>[],
        ),
    ];
  }

  ComputedStyle inlineMarkStyle(InlineMark mark, InlineStyleContext context) {
    final chain = inlineMarkChain(mark, context.ancestors);
    var parent = context.style;
    // 正文覆盖已作用于块样式；行内后缀从最终父样式继承，不再重算作者块。
    // 表格与标题传入各自原样式，继续保留作者的字号策略。
    for (var i = context.ancestors.length; i < chain.length; i++) {
      parent = _cascadeInlineSuffix(chain, i, parent, context.width);
    }
    return _inlineReaderFont(parent, context);
  }

  List<StyledRun> resolveInlineRuns(
    List<InlineMark> marks,
    InlineStyleContext context,
  ) {
    if (marks.isEmpty) return const [];
    final ordered = _inlineRunBoundaries(marks);
    final runs = <StyledRun>[];
    for (var i = 0; i < ordered.length - 1; i++) {
      final winner = _InlineRunWinner(ordered[i], ordered[i + 1]);
      for (final mark in marks) {
        if (winner.covers(mark)) {
          winner.accept(mark, inlineMarkStyle(mark, context));
        }
      }
      if (winner.run case final run?) runs.add(run);
    }
    return runs;
  }

  /// 生产构块按每个标记与区间检查预算；同步入口保留给锚点与兼容调用。
  Future<List<StyledRun>> resolveInlineRunsAsync(
    List<InlineMark> marks,
    InlineStyleContext context, {
    Future<void> Function()? checkpoint,
  }) async {
    if (checkpoint != null) await checkpoint();
    if (marks.isEmpty) return const [];
    final boundaries = <int>{0};
    for (final mark in marks) {
      if (checkpoint != null) await checkpoint();
      boundaries
        ..add(mark.start)
        ..add(mark.end);
    }
    final ordered = boundaries.toList()..sort();
    final runs = <StyledRun>[];
    for (var i = 0; i < ordered.length - 1; i++) {
      if (checkpoint != null) await checkpoint();
      final winner = _InlineRunWinner(ordered[i], ordered[i + 1]);
      for (final mark in marks) {
        if (checkpoint != null) await checkpoint();
        if (!winner.covers(mark)) continue;
        winner.accept(
          mark,
          await inlineMarkStyleAsync(mark, context, checkpoint: checkpoint),
        );
      }
      if (winner.run case final run?) runs.add(run);
    }
    return runs;
  }

  static List<int> _inlineRunBoundaries(List<InlineMark> marks) {
    final boundaries = <int>{0};
    for (final mark in marks) {
      boundaries
        ..add(mark.start)
        ..add(mark.end);
    }
    return boundaries.toList()..sort();
  }

  /// 行内后缀级联也可分片；同步方法沿用同一字体和继承规则。
  Future<ComputedStyle> inlineMarkStyleAsync(
    InlineMark mark,
    InlineStyleContext context, {
    Future<void> Function()? checkpoint,
  }) async {
    if (checkpoint != null) await checkpoint();
    final chain = inlineMarkChain(mark, context.ancestors);
    var parent = context.style;
    for (var i = context.ancestors.length; i < chain.length; i++) {
      if (checkpoint != null) await checkpoint();
      parent = _cascadeInlineSuffix(chain, i, parent, context.width);
    }
    return _inlineReaderFont(parent, context);
  }

  ComputedStyle _cascadeInlineSuffix(
    List<SelectorElement> chain,
    int index,
    ComputedStyle parent,
    double width,
  ) => Cascade.compute(
    element: chain[index],
    ancestors: chain.sublist(0, index),
    rules: cascadeRules.candidatesFor(chain[index]),
    inlineDeclarations: snapshot.fonts.rewriteDeclarations(
      inlineDeclarationsOf(chain[index].attributes['style']),
    ),
    parent: parent,
    rootFontSize: style.fontSize,
    containingWidth: width,
    viewportWidth: contentWidth,
  );

  ComputedStyle _inlineReaderFont(
    ComputedStyle parent,
    InlineStyleContext context,
  ) {
    final family = snapshot.overrides.isCustomFont
        ? null
        : context.readerFontFamily;
    return _applyCustomFont(
      family == null ? parent : parent.withTypography(fontFamily: family),
    );
  }

  // 保留旧入口的命名参数，内部将容器投影与本块声明分开计算。
  ComputedStyle styleForChain(
    List<SelectorElement> chain, {
    int quoteDepth = 0,
    bool firstInContainer = false,
    bool lastInContainer = false,
    double listIndent = 0,
    double firstLineIndent = 0,
    CssListStylePosition? listPosition,
  }) {
    containerBorderedForLastChain = false;
    promotedLeftForLastChain = 0;
    final computed = chainStyle(chain);
    effectiveOpacityForLastChain = computed.effectiveOpacity;
    final projection = _projectAncestors(
      chain,
      firstInContainer,
      lastInContainer,
    );
    containerBorderedForLastChain = projection.bordered;
    if (projection.declarations.isEmpty &&
        projection.left == 0 &&
        projection.right == 0 &&
        listIndent == 0 &&
        firstLineIndent == 0) {
      return computed;
    }
    projection.left += listIndent;
    promotedLeftForLastChain = projection.left;
    final declarations = _projectBlockDeclarations(
      computed,
      projection,
      firstLineIndent,
      listPosition,
    );
    return _projectedStyle(computed, declarations);
  }

  ComputedStyle _projectedStyle(
    ComputedStyle computed,
    Map<String, String> declarations,
  ) => ComputedStyle(
    declarations,
    parent: style,
    explicitProperties: declarations.keys.toSet(),
    declaredTextProperties: computed.declaredTextProperties,
    hasExplicitTextColor: computed.hasExplicitTextColor,
    containingWidth: contentWidth,
    rootFontSize: style.fontSize,
  );

  _ContainerProjection _projectAncestors(
    List<SelectorElement> chain,
    bool first,
    bool last,
  ) {
    final projection = _ContainerProjection();
    for (var index = 0; index < chain.length - 1; index++) {
      _projectAncestor(projection, chain, index, first, last);
    }
    return projection;
  }

  void _projectAncestor(
    _ContainerProjection projection,
    List<SelectorElement> chain,
    int index,
    bool first,
    bool last,
  ) {
    // 列表缩进独立解算；body/html 盒由阅读器页面接管。
    if (const {'ul', 'ol', 'li', 'body', 'html'}.contains(chain[index].tag)) {
      return;
    }
    final ancestorStyle = chainStyle(chain.sublist(0, index + 1));
    final retained = retainedContainers[chain[index]];
    if (retained != null) {
      projection.left = retained.contentLeft;
      projection.right =
          contentWidth - retained.contentLeft - retained.contentWidth;
      return;
    }
    final nearest = index == chain.length - 2;
    if (nearest && ancestorStyle.borders.hasBorder) projection.bordered = true;
    for (final property in _promotedBoxProps) {
      final value = ancestorStyle.values[property];
      if (value != null) projection.declarations[property] = value;
    }
    if (nearest) {
      _projectVerticalEdges(
        projection.declarations,
        ancestorStyle,
        first,
        last,
      );
    }
    projection.left += ancestorStyle.padding.left + ancestorStyle.margin.left;
    projection.right +=
        ancestorStyle.padding.right + ancestorStyle.margin.right;
  }

  static void _projectVerticalEdges(
    Map<String, String> declarations,
    ComputedStyle ancestor,
    bool first,
    bool last,
  ) {
    final top = ancestor.borders.top;
    if (first && top.width > 0) {
      declarations['border-top'] =
          '${top.width}px ${borderStyleName(top.style)} #${colorToHex(top.color)}';
    }
    final bottom = ancestor.borders.bottom;
    if (last && bottom.width > 0) {
      declarations['border-bottom'] =
          '${bottom.width}px ${borderStyleName(bottom.style)} #${colorToHex(bottom.color)}';
    }
    if (first && ancestor.padding.top > 0) {
      declarations['padding-top'] = '${ancestor.padding.top}px';
    }
    if (last && ancestor.padding.bottom > 0) {
      declarations['padding-bottom'] = '${ancestor.padding.bottom}px';
    }
  }

  static Map<String, String> _projectBlockDeclarations(
    ComputedStyle computed,
    _ContainerProjection projection,
    double firstLineIndent,
    CssListStylePosition? listPosition,
  ) {
    final declarations = <String, String>{
      ...projection.declarations,
      ...computed.values,
    };
    if (projection.left > 0) {
      declarations['margin-left'] =
          '${computed.margin.left + projection.left}px';
    }
    if (projection.right > 0) {
      declarations['margin-right'] =
          '${computed.margin.right + projection.right}px';
    }
    if (firstLineIndent > 0) {
      declarations['text-indent'] =
          '${computed.textIndent + firstLineIndent}px';
    }
    if (listPosition != null) {
      declarations['list-style-position'] = switch (listPosition) {
        CssListStylePosition.inside => 'inside',
        CssListStylePosition.outside => 'outside',
      };
    }
    return declarations;
  }

  ComputedStyle styleFor(
    String tag, {
    Map<String, String>? attributes,
    int quoteDepth = 0,
  }) {
    final self = ChapterNodeView(
      tag,
      attributes ?? const <String, String>{},
      const <SelectorElement>[],
    );
    return styleForChain(<SelectorElement>[self], quoteDepth: quoteDepth);
  }

  FloatSide? floatSideOf(
    Map<String, String> attributes, {
    List<SelectorElement> ancestors = const <SelectorElement>[],
  }) {
    final inline = attributes['style'] ?? '';
    final inlineMatch = RegExp(
      r'float\s*:\s*(left|right)',
      caseSensitive: false,
    ).firstMatch(inline);
    if (inlineMatch != null) {
      return inlineMatch.group(1)!.toLowerCase() == 'left'
          ? FloatSide.left
          : FloatSide.right;
    }
    final align = attributes['align']?.toLowerCase();
    if (align == 'left' || align == 'right') {
      return align == 'left' ? FloatSide.left : FloatSide.right;
    }
    final view = ChapterNodeView('img', <String, String>{
      if (attributes['class'] != null) 'class': attributes['class']!,
    }, const <SelectorElement>[]);
    final imgStyle = chainStyle([...ancestors, view]);
    final declared = imgStyle.values['float']?.toLowerCase();
    if (declared == 'left' || declared == 'right') {
      return declared == 'left' ? FloatSide.left : FloatSide.right;
    }
    // P8-06：display:inline-block 的小图按左浮近似——后续文字绕排
    // 右侧，获得「头像+名」类并排视觉（flat 无行内盒的真实近似）。
    // 限定显式小尺寸（宽属性 ≤200px），大图仍走普通块。
    if (imgStyle.display == CssDisplay.inlineBlock) {
      final widthAttr = double.tryParse(
        (attributes['width'] ?? '').replaceAll(RegExp(r'[^0-9.]'), ''),
      );
      if (widthAttr != null && widthAttr > 0 && widthAttr <= 200) {
        return FloatSide.left;
      }
    }
    return null;
  }

  /// 首字符 run：合并作者 `::first-letter` 声明与 `initial-letter` 的首字
  /// 下沉语义，借用行内 run 机制放大首字并撑高首行。
  StyledRun? firstLetterRun(
    List<AuxiliaryCssRule> rules,
    List<SelectorElement> ancestors,
    String text,
    ComputedStyle baseStyle, {
    bool sizeInitialLetter = true,
  }) {
    if (ancestors.isEmpty || text.isEmpty) return null;
    final declarations = _firstLetterDeclarations(rules, ancestors);
    final initialLines = baseStyle.initialLetterLines;
    final hasInitial = initialLines != null && initialLines > 0;
    if (sizeInitialLetter && hasInitial) {
      final extent = baseStyle.lineHeight * initialLines;
      declarations.putIfAbsent('font-size', () => '${extent * 0.85}px');
      declarations.putIfAbsent('line-height', () => '${extent}px');
    }
    if (declarations.isEmpty && !hasInitial) return null;
    var start = 0;
    while (start < text.length && isWhitespace(text.codeUnitAt(start))) {
      start += 1;
    }
    if (start >= text.length) return null;
    return StyledRun(
      start: start,
      end: start + 1,
      style: ComputedStyle(
        declarations,
        parent: baseStyle,
        explicitProperties: declarations.keys.toSet(),
        containingWidth: contentWidth,
        rootFontSize: baseStyle.fontSize,
      ),
    );
  }

  Map<String, String> _firstLetterDeclarations(
    List<AuxiliaryCssRule> rules,
    List<SelectorElement> ancestors,
  ) {
    final declarations = <String, String>{};
    final parents = ancestors.sublist(0, ancestors.length - 1);
    for (final rule in rules) {
      if (!_ruleMediaMatches(rule.media, rule.mediaConditions)) continue;
      if (!rule.selectors.selectors.any(
        (selector) => selector.matches(ancestors.last, parents),
      )) {
        continue;
      }
      for (final declaration in rule.declarations) {
        declarations[declaration.property] = declaration.value;
      }
    }
    return declarations;
  }

  static String _chainKey(
    List<SelectorElement> chain,
    Map<SelectorElement, String> viewKeys,
    CascadeRuleSet rules,
  ) => chain
      .map(
        (view) => viewKeys.putIfAbsent(view, () {
          final attrKeys = view.attributes.keys.toList()..sort();
          final attrs = [
            for (final key in attrKeys) '$key=${view.attributes[key]}',
          ].join(';');
          final identity =
              view is ChapterNodeView &&
                  rules.candidatesFor(view).usesTreePosition
              ? view.cacheIdentity
              : '';
          return '${view.tag}|$attrs|$identity';
        }),
      )
      .join('>');

  static const _promotedBoxProps = <String>{
    // P9-22：容器上的 duokan-bleed 要传导到子块（横幅图出血）。
    'duokan-bleed', '-duokan-bleed',
    // 水平内缩不在这里传导：容器的 padding/margin 由 extraLeft/extraRight
    // 累加进子块 margin（见下方循环），两边都做会重复计算（P9-27）。
    'background-color', 'border-left', 'border-right',
    // P9-03：容器的背景图与尺寸/平铺/定位一并透传，卡片纹理不再丢失。
    'background-image', 'background-size', 'background-position',
    'background-repeat', 'background-origin', 'background-clip',
  };
}

typedef InlineStyleContext = ({
  List<SelectorElement> ancestors,
  ComputedStyle style,
  double width,
  String? readerFontFamily,
});

/// 每个边界区间独立选取最深级联，同深度仍按原标记顺序覆盖。
class _InlineRunWinner {
  _InlineRunWinner(this.start, this.end);
  final int start;
  final int end;
  ComputedStyle? _style;
  int _depth = -1;

  bool covers(InlineMark mark) =>
      mark.start <= start &&
      end <= mark.end &&
      mark.chain.isNotEmpty &&
      mark.chain.length >= _depth;

  void accept(InlineMark mark, ComputedStyle computed) {
    if (computed.explicitProperties.isEmpty) return;
    _style = computed;
    _depth = mark.chain.length;
  }

  StyledRun? get run {
    final computed = _style;
    return computed == null
        ? null
        : StyledRun(
            start: start,
            end: end,
            style: computed,
            baselineShift: computed.verticalAlignShift,
          );
  }
}

class _ContainerProjection {
  final Map<String, String> declarations = {};
  double left = 0;
  double right = 0;
  bool bordered = false;
}
