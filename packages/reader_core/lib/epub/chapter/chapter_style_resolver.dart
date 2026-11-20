import 'dart:math' as math;

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:reader_core/api.dart' hide ComputedStyle, Paginator;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_size.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/text_aggregator.dart';

import 'chapter_layout_job.dart';
import 'chapter_selectors.dart';
import 'chapter_styles.dart';
import 'chapter_text_measurer.dart';
import 'block_style_helpers.dart';
import 'generated_content.dart';

/// 一次章节作业的级联与容器样式临时状态；全部度量输入来自快照。
class ChapterStyleResolver {
  ChapterStyleResolver(this.snapshot, this.selectorIndex, this.preparedStyles);

  final LayoutSnapshot snapshot;
  final ChapterSelectors selectorIndex;
  final ChapterCascadePreparation preparedStyles;
  double get contentWidth => snapshot.width;
  late final CssValueContext valueContext = _viewportContext();

  CssValueContext _viewportContext() {
    final context = CssValueContext(
      viewportWidth: snapshot.width,
      viewportHeight: snapshot.height,
    );
    final html = selectorIndex.htmlElement;
    if (html == null) return context;
    final root = Cascade.compute(
      element: html,
      ancestors: const [],
      rules: cascadeRules.candidatesFor(html),
      inlineDeclarations: inlineDeclarationsOf(html.attributes['style']),
      parent: style,
      rootFontSize: style.fontSize,
      containingWidth: contentWidth,
      viewportWidth: contentWidth,
      valueContext: context,
    );
    return root.explicitProperties.contains('writing-mode')
        ? root.valueContext
        : context;
  }

  late final ComputedStyle style = _applyCustomFont(
    snapshot.overrides.applyCascadeBase(
      snapshot.baseStyle,
      containingWidth: contentWidth,
    ),
  );
  CascadeRuleSet get cascadeRules => preparedStyles.cascadeRules;
  Map<String, List<AuxiliaryCssRule>> get pseudoRules =>
      preparedStyles.pseudoRules;
  final Map<String, ComputedStyle> chainStyleCache = {};
  final Map<SelectorElement, String> viewKeys = {};
  final Map<SelectorElement, ComputedStyle> promotedInlineStyles = {};
  final Map<EpubNode, SelectorElement> fallbackViews = {};
  final Map<SelectorElement, PageContainer> retainedContainers = {};
  final Map<SelectorElement, Set<String>> blockPseudoElements = {};
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
    final containing = _containingWidthFor(chain);
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
          valueContext: valueContext,
        ),
      );
    });
  }

  double _containingWidthFor(List<SelectorElement> chain) {
    var width = contentWidth;
    for (var index = 0; index < chain.length - 1; index++) {
      final box = retainedContainers[chain[index]];
      if (box != null) width = box.flowWidth;
    }
    return width;
  }

  /// 作者限宽、内在容器和多栏后代保留真实内容宽，不再套用正文最小宽度。
  bool preservesContainerWidth(List<SelectorElement> chain) => chain.any((
    view,
  ) {
    final container = retainedContainers[view];
    return container != null &&
        ((container.style.width != null && !container.style.width!.isAuto) ||
            container.style.hasIntrinsicWidth ||
            MulticolGeometry.fromStyle(
                  container.style,
                  container.contentWidth,
                ) !=
                null);
  });

  /// 在原父内容盒中分配 auto 外边距，再把变化量加到已有页面投影上。
  ComputedStyle intrinsicBlockStyle(
    ComputedStyle computed,
    List<SelectorElement> chain,
    double contentWidth,
  ) {
    if (!computed.hasIntrinsicWidth) return computed;
    final authored = chainStyle(chain);
    final used = authored.withIntrinsicMargins(
      contentWidth: contentWidth,
      containingWidth: _containingWidthFor(chain),
    );
    if (identical(authored, used)) return computed;
    return computed.withMargins(
      CssEdges(
        top: computed.margin.top,
        right:
            computed.margin.right + used.margin.right - authored.margin.right,
        bottom: computed.margin.bottom,
        left: computed.margin.left + used.margin.left - authored.margin.left,
      ),
    );
  }

  /// 正文相对列宽与字号一起求解，再把 auto 边距的变化叠加到页面投影。
  ComputedStyle scaleBlockTypography(
    ComputedStyle computed,
    List<SelectorElement> chain,
    double fontSize, {
    bool scaleTextWidth = false,
  }) {
    final authored = chainStyle(chain);
    final containingWidth = _containingWidthFor(chain);
    final width = scaleTextWidth
        ? _textWidthAtFontSize(authored, fontSize, containingWidth)
        : null;
    final scaled = authored.scaleRelativeTypography(
      fontSize,
      resolvedWidth: width,
    );
    final margins = _scaledBlockMargins(scaled, containingWidth);
    return computed
        .scaleRelativeTypography(fontSize, resolvedWidth: width)
        .withMargins(
          CssEdges(
            top: computed.margin.top + margins.top - authored.margin.top,
            right:
                computed.margin.right + margins.right - authored.margin.right,
            bottom:
                computed.margin.bottom +
                margins.bottom -
                authored.margin.bottom,
            left: computed.margin.left + margins.left - authored.margin.left,
          ),
        );
  }

  static double? _textWidthAtFontSize(
    ComputedStyle style,
    double fontSize,
    double containingWidth,
  ) => ChapterTextMeasurer.isOrdinaryHorizontalBlock(style)
      ? resolveCssNumericLength(
          style.values['width'] ?? '',
          fontSize: fontSize,
          rootFontSize: style.cssRootFontSize,
          percentBase: containingWidth,
        )
      : null;

  static CssEdges _scaledBlockMargins(ComputedStyle style, double width) {
    final leftAuto = style.marginLeftIsAuto;
    final rightAuto = style.marginRightIsAuto;
    if (!ChapterTextMeasurer.isOrdinaryHorizontalBlock(style) ||
        style.width == null ||
        style.width!.isAuto ||
        (!leftAuto && !rightAuto)) {
      return style.margin;
    }
    // 在原父内容盒中按最终列宽重分配 auto 边距，内边距与边框不随正文缩放。
    final model = BoxModel.fromStyle(style, containingWidth: width);
    final remaining = math.max(
      0.0,
      width -
          model.resolveContentWidth(width) -
          model.horizontalInset -
          (leftAuto ? 0 : style.margin.left) -
          (rightAuto ? 0 : style.margin.right),
    );
    final share = leftAuto && rightAuto ? remaining / 2 : remaining;
    return CssEdges(
      top: style.margin.top,
      right: rightAuto ? share : style.margin.right,
      bottom: style.margin.bottom,
      left: leftAuto ? share : style.margin.left,
    );
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

  /// 单图折叠路径也能从原始祖先链还原浮动整盒，避免按图片宽占位。
  PageFloatBox? floatBoxForChain(List<SelectorElement> chain) {
    var left = 0.0;
    var width = contentWidth;
    PageFloatBox? result;
    for (var index = 0; index < chain.length; index++) {
      final view = chain[index];
      if (view.tag == 'html') continue;
      final computed = chainStyle(chain.sublist(0, index + 1));
      final model = BoxModel.fromStyle(computed, containingWidth: width);
      final container =
          retainedContainers[view] ??
          PageContainer(
            style: computed,
            left: left + computed.margin.left,
            width: model.borderBoxWidth(model.resolveContentWidth(width)),
          );
      if (floatSideOfStyle(computed) != null) {
        result = PageFloatBox(
          container: container,
          containingLeft: left,
          containingWidth: width,
        );
      }
      left = container.contentLeft;
      width = container.flowWidth;
    }
    return result;
  }

  ComputedStyle pseudoStyleFor(
    List<SelectorElement> ancestors,
    ComputedStyle parent,
    String pseudo,
  ) => _applyCustomFont(
    _auxiliaryStyleFor(
      ancestors,
      parent,
      pseudo,
      pseudoRules[pseudo] ?? const [],
    ),
  );

  /// 首行只传递伪元素允许的文字与背景属性，不把盒尺寸当作首行样式。
  ComputedStyle? firstLineStyleFor(
    List<SelectorElement> ancestors,
    ComputedStyle parent,
  ) {
    if (ancestors.isEmpty || preparedStyles.firstLineRules.isEmpty) return null;
    final computed = _auxiliaryStyleFor(
      ancestors,
      parent,
      '::first-line',
      preparedStyles.firstLineRules,
    );
    return computed.explicitProperties.isEmpty
        ? null
        : _applyCustomFont(computed);
  }

  ComputedStyle _auxiliaryStyleFor(
    List<SelectorElement> ancestors,
    ComputedStyle parent,
    String pseudo,
    List<AuxiliaryCssRule> auxiliary,
  ) {
    if (ancestors.isEmpty) {
      return parent;
    }
    final rules = pseudoCascadeRules.putIfAbsent(
      pseudo,
      () => _auxiliaryCascadeRules(auxiliary, pseudo),
    );
    // 用户字体覆盖会增加显式 font-family；伪元素是否命中只看作者级联。
    return Cascade.compute(
      element: ancestors.last,
      ancestors: ancestors.sublist(0, ancestors.length - 1),
      rules: rules.candidatesFor(ancestors.last),
      parent: parent,
      rootFontSize: style.fontSize,
      containingWidth:
          retainedContainers[ancestors.last]?.contentWidth ??
          _textWidthFor(parent),
      viewportWidth: contentWidth,
      valueContext: valueContext,
    );
  }

  static CascadeRuleSet _auxiliaryCascadeRules(
    List<AuxiliaryCssRule> auxiliary,
    String pseudo,
  ) => CascadeRuleSet([
    for (final (index, rule) in auxiliary.indexed)
      CascadeRule(
        rule: CssRule(
          selector: rule.selectorText,
          declarations: pseudo == '::first-line'
              ? rule.declarations
                    .where(
                      (declaration) => _firstLineProperty(declaration.property),
                    )
                    .toList(growable: false)
              : rule.declarations,
          media: rule.media,
          mediaConditions: rule.mediaConditions,
        ),
        origin: CascadeOrigin.author,
        order: index,
      ),
  ]);

  static bool _firstLineProperty(String property) =>
      property.startsWith('font') ||
      property.startsWith('background') ||
      property.startsWith('text-decoration') ||
      property.startsWith('text-emphasis') ||
      property.startsWith('--') ||
      const {
        'color',
        'word-spacing',
        'letter-spacing',
        'vertical-align',
        'text-transform',
        'line-height',
        'text-shadow',
      }.contains(property);

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

  /// 构块按每个标记与区间检查预算，不返回取消作业的部分结果。
  Future<List<StyledRun>> resolveInlineRuns(
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
          await inlineMarkStyle(mark, context, checkpoint: checkpoint),
        );
      }
      if (winner.run case final run?) runs.add(run);
    }
    return runs;
  }

  /// 行内后缀从最终父样式继承，按链节点检查预算。
  Future<ComputedStyle> inlineMarkStyle(
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
  ) {
    final computed = Cascade.compute(
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
      valueContext: valueContext,
    );
    final readerSize = snapshot.overrides.fontSize;
    final rootSize = style.fontSize;
    final rawSize = fontSizeDeclarationOf(computed);
    if (readerSize == null ||
        rootSize <= 0 ||
        !CssFontSizes.usesRoot(rawSize)) {
      return computed;
    }
    // em 已从最终父字号解算；rem 单独改用阅读器根基准，盒模型仍先按原书解算。
    return computed.scaleRelativeTypography(
      readerSize * computed.fontSize / rootSize,
    );
  }

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
    final rawProjectedBleed =
        projection.declarations['duokan-bleed'] ??
        projection.declarations['-duokan-bleed'];
    final preserveBleedImageWidths =
        chain.isNotEmpty &&
        const {'img', 'image', 'object'}.contains(chain.last.tag) &&
        (computed.bleed.any || CssBleed.parse(rawProjectedBleed).any);
    final declarations = _projectBlockDeclarations(
      computed,
      projection,
      firstLineIndent,
      listPosition,
      _containingWidthFor(chain),
      preserveBleedImageWidths: preserveBleedImageWidths,
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
    valueContext: computed.valueContext,
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
    // 祖先出血仅供图片盒兼容投影，普通后代的背景和边框仍使用自身盒。
    if (chain.isEmpty ||
        !const {'img', 'image', 'object'}.contains(chain.last.tag)) {
      projection.declarations.remove('duokan-bleed');
      projection.declarations.remove('-duokan-bleed');
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
    // 列表缩进独立解算；html 不进入章节根盒。
    if (const {'ul', 'ol', 'li', 'html'}.contains(chain[index].tag)) {
      return;
    }
    final ancestorStyle = chainStyle(chain.sublist(0, index + 1));
    final retained = retainedContainers[chain[index]];
    if (retained != null) {
      projection.hasIntrinsicContainer |= retained.style.hasIntrinsicWidth;
      projection.left = retained.contentLeft;
      projection.right =
          contentWidth - retained.contentLeft - retained.flowWidth;
      return;
    }
    if (chain[index].tag == 'body') {
      // 单图根节点折叠后没有保留容器，仍累计原始 body 的水平盒。
      projection.left +=
          ancestorStyle.margin.left +
          ancestorStyle.borders.left.width +
          ancestorStyle.padding.left;
      projection.right +=
          ancestorStyle.margin.right +
          ancestorStyle.borders.right.width +
          ancestorStyle.padding.right;
      return;
    }
    _projectLooseAncestor(
      projection,
      ancestorStyle,
      index == chain.length - 2,
      (first, last),
    );
  }

  void _projectLooseAncestor(
    _ContainerProjection projection,
    ComputedStyle ancestorStyle,
    bool nearest,
    (bool, bool) edges,
  ) {
    if (nearest && ancestorStyle.borders.hasBorder) projection.bordered = true;
    for (final property in _promotedBoxProps) {
      final value = ancestorStyle.values[property];
      if (value != null) projection.declarations[property] = value;
    }
    if (nearest) {
      _projectVerticalEdges(
        projection.declarations,
        ancestorStyle,
        edges.$1,
        edges.$2,
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
    double containingWidth, {
    required bool preserveBleedImageWidths,
  }) {
    final declarations = <String, String>{
      ...projection.declarations,
      ..._resolvedProjectionValues(computed),
      if (!preserveBleedImageWidths)
        ..._resolvedWidthValues(computed, containingWidth),
    };
    if (projection.left > 0) {
      declarations['margin-left'] =
          '${computed.margin.left + projection.left}px';
    }
    if (projection.right > 0 ||
        (projection.hasIntrinsicContainer && projection.right < 0)) {
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

  /// 水平尺寸先按原父内容宽解算，页面投影不再改变百分比与 calc 的基准。
  static Map<String, String> _resolvedWidthValues(
    ComputedStyle style,
    double containingWidth,
  ) => {
    for (final entry in {
      'width': style.width,
      'min-width': style.minWidth,
      'max-width': style.maxWidth,
    }.entries)
      if (entry.value != null &&
          !entry.value!.isAuto &&
          entry.value!.resolve(containingWidth) != null)
        entry.key: '${entry.value!.resolve(containingWidth)}px',
  };

  /// 只投影盒位置，不按页面宽度或根字号重算已解算的相对属性。
  static Map<String, String> _resolvedProjectionValues(ComputedStyle style) => {
    ...style.values,
    'font-size': '${style.fontSize}px',
    'font-weight': '${style.fontWeight}',
    // 无单位因子继续供后代继承；百分比和长度继承最终绝对行高。
    'line-height':
        style.unitlessLineHeightFactor?.toString() ??
        (style.lineHeightFactor == null ? 'normal' : '${style.lineHeight}px'),
    for (final property in const [
      'margin-top',
      'margin-right',
      'margin-bottom',
      'margin-left',
      'padding-top',
      'padding-right',
      'padding-bottom',
      'padding-left',
    ])
      if (style.values[property]?.contains('%') ?? false)
        property: style.computedValue(property)!,
  };

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

  /// 首字 run：合并作者首字伪元素声明与 `initial-letter` 的首字
  /// 下沉语义，借用行内 run 机制放大首字并撑高首行。
  StyledRun? firstLetterRun(
    List<AuxiliaryCssRule> rules,
    List<SelectorElement> ancestors,
    String text,
    ComputedStyle baseStyle, {
    bool sizeInitialLetter = true,
    ComputedStyle? firstLineStyle,
  }) {
    if (ancestors.isEmpty || text.isEmpty) return null;
    final parent =
        firstLineStyle ?? firstLineStyleFor(ancestors, baseStyle) ?? baseStyle;
    final letterStyle = _auxiliaryStyleFor(
      ancestors,
      parent,
      '::first-letter',
      rules,
    );
    final initialLines = baseStyle.initialLetterLines;
    final hasInitial = initialLines != null && initialLines > 0;
    if (letterStyle.explicitProperties.isEmpty && !hasInitial) return null;
    var start = 0;
    while (start < text.length && isWhitespace(text.codeUnitAt(start))) {
      start += 1;
    }
    if (start >= text.length) return null;
    return StyledRun(
      start: start,
      end: start + text.substring(start).characters.first.length,
      style: _applyCustomFont(
        sizeInitialLetter && hasInitial
            ? _initialLetterStyle(
                letterStyle,
                parent,
                baseStyle.lineHeight * initialLines,
              )
            : letterStyle,
      ),
    );
  }

  ComputedStyle _initialLetterStyle(
    ComputedStyle letterStyle,
    ComputedStyle parent,
    double extent,
  ) {
    final defaults = <String, String>{
      if (!letterStyle.explicitProperties.contains('font-size'))
        'font-size': '${extent * 0.85}px',
      if (!letterStyle.explicitProperties.contains('line-height'))
        'line-height': '${extent}px',
    };
    return ComputedStyle(
      {...letterStyle.values, ...defaults},
      // 与作者首字声明同层计算，保留非继承装饰及相对单位的原父基准。
      parent: parent,
      explicitProperties: {...letterStyle.explicitProperties, ...defaults.keys},
      hasExplicitTextColor: letterStyle.hasExplicitTextColor,
      declaredTextProperties: letterStyle.declaredTextProperties,
      customProperties: letterStyle.customProperties,
      containingWidth: _textWidthFor(parent),
      rootFontSize: style.fontSize,
      valueContext: valueContext,
    );
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
    // P9-22：横幅图仍接收祖先出血，普通后代由 _projectAncestors 排除。
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
  double _leadingInset = 0;
  double _trailingInset = 0;

  bool covers(InlineMark mark) =>
      mark.start <= start && end <= mark.end && mark.chain.isNotEmpty;

  void accept(InlineMark mark, ComputedStyle computed) {
    // 文字取最深级联；每层元素的盒边只在其真实首尾占宽一次。
    final borders = computed.borders;
    final atomic =
        computed.display == CssDisplay.inlineBlock ||
        mark.tag == 'img' ||
        mark.tag == 'image' ||
        mark.tag == 'object' &&
            (mark.chain.last.attributes['data']?.trim().isNotEmpty ?? false);
    if (!atomic && mark.start == start) {
      _leadingInset +=
          math.max(0, computed.margin.left) +
          computed.padding.left +
          (borders.left.isVisible ? borders.left.width : 0);
    }
    if (!atomic && mark.end == end) {
      _trailingInset +=
          math.max(0, computed.margin.right) +
          computed.padding.right +
          (borders.right.isVisible ? borders.right.width : 0);
    }
    if (mark.chain.length < _depth) return;
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
            inlineLeadingInset: _leadingInset,
            inlineTrailingInset: _trailingInset,
          );
  }
}

class _ContainerProjection {
  final Map<String, String> declarations = {};
  double left = 0;
  double right = 0;
  bool bordered = false;
  bool hasIntrinsicContainer = false;
}
