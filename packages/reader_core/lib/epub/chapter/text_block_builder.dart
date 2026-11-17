import 'dart:math' as math;

import 'package:reader_core/api.dart' show EpubNode, TextBlockNode;
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_size.dart';
import 'package:reader_core/css/property_aliases.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/intrinsic_widths.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_core/position/text_cfi_map.dart';

import 'prose_spacing_defaults.dart';
import 'block_style_helpers.dart';
import 'chapter_flow.dart';
import 'chapter_selectors.dart';
import 'chapter_style_resolver.dart';
import 'chapter_styles.dart' show inlineDeclarationsOf, ruleMediaMatches;
import 'chapter_text_measurer.dart';
import 'container_blocks.dart';
import 'generated_chapter_content.dart';
import 'generated_content.dart';
import 'image_block_builder.dart';
import 'inline_content_builder.dart';
import 'text_coordinates.dart';

/// 聚合文字到分页块的构建过程；每段坐标和临时盒子只在本次调用中存在。
class TextBlockBuilder {
  TextBlockBuilder(this.styles, this.inline, this.content, this.flow)
    : images = ImageBlockBuilder(styles, inline, content);

  final ChapterStyleResolver styles;
  final InlineContentBuilder inline;
  final GeneratedChapterContent content;
  final ChapterFlow flow;
  final ImageBlockBuilder images;
  ChapterTextMeasurer get measure => inline.measure;
  double get contentWidth => styles.snapshot.width;
  double get contentHeight => styles.snapshot.height;

  Future<void> build(TextBlockNode node, BlockPosition position) async {
    await measure.budget.checkpoint();
    final context = await _context(node, position);
    final authored = _authoredStyle(context);
    if (await _buildEmptyBox(context, authored)) return;
    final generated = await _generatedText(context, authored.style);
    final body = await _bodyStyle(context, authored);
    final metrics = await _metrics(context, body);
    if (await _buildImageOnly(context, generated)) return;
    final expanded = await _expandGeneratedText(context, body, generated);
    final dropped = await _extractDropCap(context, body, expanded, generated);
    final paragraph = await _inlineParagraph(context, body, generated, dropped);
    final measured = await _measureParagraph(
      context,
      body,
      metrics,
      paragraph,
      generated,
    );
    await _appendBlocks(context, body, metrics, measured);
  }

  /// 容器预测复用正文的字号分类与行内级联；只推进调用方的计数器快照。
  Future<IntrinsicWidths> measureIntrinsicContent(
    TextBlockNode node,
    BlockPosition position,
    GeneratedChapterContent generation,
  ) async {
    final context = await _context(node, position);
    final authored = _authoredStyle(context);
    final body = await _bodyStyle(context, authored);
    final generated = await _generatedText(context, body.style, generation);
    final paragraph = await _expandGeneratedText(context, body, generated);
    final marker = _nextMarker(context, body.style);
    final measureStyle = await _markerMeasureStyle(context, body, marker);
    return measure.intrinsicWidths(
      paragraph.text,
      measureStyle,
      runs: await _intrinsicRuns(context, body, generated, paragraph),
    );
  }

  Future<List<StyledRun>> _intrinsicRuns(
    _BlockContext context,
    _BodyStyle body,
    _GeneratedText generated,
    _ParagraphText paragraph,
  ) async {
    final runs = await styles.resolveInlineRuns(
      paragraph.marks,
      _inlineContext(context, body),
      checkpoint: measure.budget.checkpoint,
    );
    final measuredRuns = _pseudoRuns(
      context,
      body.style,
      generated,
      paragraph,
      runs,
    );
    final letter = _hasFirstLineText(context, generated)
        ? styles.firstLetterRun(
            styles.preparedStyles.firstLetterRules,
            context.ancestors,
            paragraph.text,
            body.style,
          )
        : null;
    if (letter != null) measuredRuns.add(letter);
    return styles.snapshot.textOverlays.resolve(
      blockCfi: context.cfi,
      textCfis: paragraph.textCfis,
      text: paragraph.text,
      style: body.style,
      runs: measuredRuns,
    );
  }

  Future<_BlockContext> _context(
    TextBlockNode node,
    BlockPosition position,
  ) async {
    var eligible = true;
    for (final element in position.ancestors) {
      await measure.budget.checkpoint();
      if (element.tag == 'header' ||
          element.tag == 'footer' ||
          FootnoteParser.isDefinitionElement(element.tag, element.attributes)) {
        eligible = false;
        break;
      }
    }
    return _BlockContext(node, position, eligible);
  }

  _AuthoredStyle _authoredStyle(_BlockContext context) {
    final position = context.position;
    final listIndent = context.isListItem
        ? styles.listIndentOf(position.ancestors)
        : 0.0;
    final projected = styles.styleForChain(
      position.ancestors,
      quoteDepth: position.quoteDepth,
      firstInContainer: position.firstInContainer,
      lastInContainer: position.lastInContainer,
      listIndent: listIndent,
    );
    // 定位块的祖先内缩由包含块原点消费，不能再次投影到自身 margin。
    final relative = projected.isOutOfFlow
        ? styles.chainStyle(position.ancestors)
        : projected;
    final isRelative = relative.position == CssPosition.relative;
    final offsets = (
      left: isRelative ? relative.left?.resolve(contentWidth) ?? 0.0 : 0.0,
      top: isRelative ? relative.top?.resolve(contentHeight) ?? 0.0 : 0.0,
    );
    // 普通段落的投影参数完全相同，只有列表需要补充标记位置后再计算。
    final style = context.isListItem
        ? styles.styleForChain(
            position.ancestors,
            quoteDepth: position.quoteDepth,
            firstInContainer: position.firstInContainer,
            lastInContainer: position.lastInContainer,
            listIndent: listIndent,
            listPosition: position.list!.inside
                ? CssListStylePosition.inside
                : CssListStylePosition.outside,
          )
        : relative;
    // 后续样式查询会覆盖 resolver 的临时旗标，必须立即冻结到本段。
    return _AuthoredStyle(style, listIndent, offsets, (
      bordered: styles.containerBorderedForLastChain,
      opacity: styles.effectiveOpacityForLastChain,
    ));
  }

  Future<bool> _buildEmptyBox(
    _BlockContext context,
    _AuthoredStyle authored,
  ) async {
    final node = context.node;
    final hasEmptyInlineBox = await _hasEmptyInlineBox(node);
    if (node.text.trim().isNotEmpty ||
        hasEmptyInlineBox ||
        (node is TextContentNode && node.leadingBreakCount > 0)) {
      return false;
    }
    // 空盒先于计数器和伪内容处理，沿用原章节遍历的语义顺序。
    final floatBox =
        authored.style.isOutOfFlow || floatSideOfStyle(authored.style) == null
        ? null
        : styles.floatBoxForChain(context.ancestors);
    final block = await measure.emptyBoxBlock(
      floatBox?.container.style ?? authored.style,
      floatBox?.containingWidth ?? contentWidth,
      containingHeight: contentHeight,
      floatBox: floatBox,
    );
    measure.budget.check();
    if (block != null) flow.blocks.add(block);
    return true;
  }

  Future<bool> _hasEmptyInlineBox(TextBlockNode node) async {
    if (node is! TextContentNode) return false;
    for (final mark in node.inlineMarks) {
      await measure.budget.checkpoint();
      if (mark.start == mark.end) return true;
    }
    return false;
  }

  Future<_GeneratedText> _generatedText(
    _BlockContext context,
    ComputedStyle style, [
    GeneratedChapterContent? generation,
  ]) async {
    final source = generation ?? content;
    final chain = _pseudoChain(context);
    if (context.tag != 'reader-anonymous') source.applyCounters(chain);
    var qNesting = 0;
    for (final ancestor in context.ancestors) {
      await measure.budget.checkpoint();
      if (ancestor.tag == 'q') qNesting += 1;
    }
    final qLevel = context.tag == 'q' && qNesting > 0 ? qNesting - 1 : qNesting;
    return _GeneratedText(
      _inlinePseudoContent(chain, source, style, '::before', qLevel),
      _inlinePseudoContent(chain, source, style, '::after', qLevel),
      context.node is TextContentNode,
      qLevel,
    );
  }

  PseudoContent? _inlinePseudoContent(
    List<SelectorElement> chain,
    GeneratedChapterContent source,
    ComputedStyle style,
    String pseudo,
    int quoteDepth,
  ) {
    final blockPseudos = chain.isEmpty
        ? const <String>{}
        : styles.blockPseudoElements[chain.last] ?? const <String>{};
    return blockPseudos.contains(pseudo)
        ? null
        : source.pseudoContentOf(
            chain,
            pseudo,
            quotes: style.quotes,
            quoteDepth: quoteDepth,
          );
  }

  List<SelectorElement> _pseudoChain(_BlockContext context) =>
      context.tag == 'reader-anonymous' &&
          context.ancestors.length > 1 &&
          styles.blockPseudoElements.containsKey(
            context.ancestors[context.ancestors.length - 2],
          )
      ? context.ancestors.sublist(0, context.ancestors.length - 1)
      : context.ancestors;

  Future<_BodyStyle> _bodyStyle(
    _BlockContext context,
    _AuthoredStyle authored,
  ) async {
    final compact = await _compactComponent(context, authored.style);
    final structured = _hasStructuredTitleText(
      context.node.text,
      authored.style,
    );
    var special = compact || context.position.containerFloat != null;
    var promoted = false;
    for (final view in context.ancestors) {
      await measure.budget.checkpoint();
      final container = styles.retainedContainers[view]?.style;
      special =
          special ||
          (container != null &&
              (container.display == CssDisplay.flex ||
                  (container.columnCount ?? 1) > 1 ||
                  container.columnWidth != null));
      promoted = promoted || styles.promotedInlineStyles.containsKey(view);
    }
    final preserveHeadingLayout = special || promoted;
    special = special || promoted || structured;
    var style = proseSpacingDefaults(
      authored.style,
      context.ancestors,
      context.node.text,
      specialComponent: special,
    );
    final applyReader =
        !context.isHeading && !structured && !special && !promoted;
    // 提升块及其后代已在行内级联中继承最终字号，不能再按作者父字号缩放。
    if (!promoted) {
      style = _applyBlockTypography(context, style, applyReader: applyReader);
      if (!preserveHeadingLayout) {
        style = _applyHeadingLineHeight(context, style);
      }
    }
    return _BodyStyle(authored, style, compact, structured, applyReader);
  }

  ComputedStyle _applyBlockTypography(
    _BlockContext context,
    ComputedStyle style, {
    required bool applyReader,
  }) {
    if (applyReader) {
      final relativeSize =
          _nestedRelativeFontSize(context) ?? _scopedRelativeFontSize(context);
      if (relativeSize != null) {
        style = styles.scaleBlockTypography(
          style,
          context.ancestors,
          relativeSize,
          scaleTextWidth: true,
        );
      }
      return styles.snapshot.overrides
          .copyWith(fontSize: relativeSize)
          .applyTypography(style);
    }
    final readerSize = _scaledComponentFontSize(context);
    return readerSize == null
        ? style
        : styles.scaleBlockTypography(style, context.ancestors, readerSize);
  }

  /// 普通标题继承正文基准时使用阅读行高，保留局部作者行高声明。
  ComputedStyle _applyHeadingLineHeight(
    _BlockContext context,
    ComputedStyle style,
  ) {
    final height = styles.snapshot.overrides.lineHeight;
    if (!context.isHeading || height == null) return style;
    final ancestors = context.ancestors;
    for (var index = 0; index < ancestors.length; index++) {
      if (const {'html', 'body'}.contains(ancestors[index].tag)) continue;
      final authored = styles.chainStyle(ancestors.sublist(0, index + 1));
      if (authored.explicitProperties.contains('line-height')) return style;
    }
    return style.withTypography(lineHeightFactor: height);
  }

  static final _absoluteFontSize = RegExp(
    r'^(?:\d|\.\d).*(?:px|pt|pc|cm|mm|in)$',
  );

  /// 保留块及祖先的相对字号，继承值与显式声明使用同一缩放基准。
  double? _scaledComponentFontSize(_BlockContext context) {
    final readerSize = styles.snapshot.overrides.fontSize;
    // 匿名行内块继承原元素的字号，不能把它误当成新的正文字号基准。
    final ancestors = context.tag == 'reader-anonymous'
        ? context.ancestors.sublist(0, context.ancestors.length - 1)
        : context.ancestors;
    if (readerSize == null || ancestors.length < 2) {
      return null;
    }
    final computed = styles.chainStyle(ancestors);
    final raw = fontSizeDeclarationOf(computed);
    if (raw != null && _absoluteFontSize.hasMatch(raw)) {
      return null;
    }
    // rem 相对章节根字号，不能用已被作者缩小的父容器作为分母。
    final referenceSize = CssFontSizes.usesRoot(raw)
        ? styles.style.fontSize
        : _fontSizeReference(ancestors);
    if (referenceSize <= 0) return null;
    return readerSize * computed.fontSize / referenceSize;
  }

  /// 全局文档与正文基准由阅读设置替换；局部相对字号一直累乘到块自身。
  /// 绝对长度开始新的字号基准，祖先 rem/关键字则回到章节根基准。
  double _fontSizeReference(List<SelectorElement> ancestors) {
    var reference = styles.style.fontSize;
    for (var length = 1; length < ancestors.length; length += 1) {
      final chain = ancestors.sublist(0, length);
      final authored = styles.chainStyle(chain);
      final raw = fontSizeDeclarationOf(authored);
      if (raw == null) continue;
      final proseBase =
          const {'html', 'body', 'p'}.contains(chain.last.tag) &&
          !_hasScopedDeclaration(chain, const {'font-size', 'font'});
      if (_absoluteFontSize.hasMatch(raw) ||
          (proseBase && CssFontSizes.usesRoot(raw))) {
        reference = authored.fontSize;
      } else if (proseBase) {
        // 拆出的匿名正文沿用段落基准，只抵消全局声明，保留外围组件比例。
        final parent = styles.chainStyle(chain.sublist(0, length - 1));
        if (parent.fontSize > 0) {
          reference *= authored.fontSize / parent.fontSize;
        }
      } else if (CssFontSizes.usesRoot(raw)) {
        reference = styles.style.fontSize;
      }
    }
    return reference;
  }

  /// 普通正文也继承作者容器的完整比例，不能直接恢复为阅读器满字号。
  double? _nestedRelativeFontSize(_BlockContext context) {
    final scaled = _scaledComponentFontSize(context);
    if (scaled == null) return null;
    final ancestors = context.ancestors;
    for (var length = 2; length < ancestors.length; length += 1) {
      final ancestor = styles.chainStyle(ancestors.sublist(0, length));
      if (!ancestor.explicitProperties.contains('font-size') &&
          !ancestor.explicitProperties.contains('font')) {
        continue;
      }
      final raw = fontSizeDeclarationOf(ancestor);
      if (raw != null && !_absoluteFontSize.hasMatch(raw)) {
        return scaled;
      }
    }
    return null;
  }

  /// class/id/内联声明的 em、rem、百分字号共用标题的相对缩放规则。
  /// 全局正文基准仍由阅读器控制，作者盒模型不注入阅读器字号。
  double? _scopedRelativeFontSize(_BlockContext context) {
    if (!_hasScopedFontSize(context)) return null;
    return _scaledComponentFontSize(context);
  }

  /// 组件自己通过 class/id/内联样式声明字号时，保留相对比例；普通 `p` 或
  /// `body` 上的作者字号继续由阅读器字号覆盖。
  bool _hasScopedFontSize(_BlockContext context) =>
      _hasScopedDeclaration(context.ancestors, const {'font-size', 'font'});

  bool _hasScopedDeclaration(
    List<SelectorElement> ancestors,
    Set<String> properties, {
    bool localToElement = false,
  }) {
    if (ancestors.isEmpty) return false;
    final current = ancestors.last;
    final parents = ancestors.sublist(0, ancestors.length - 1);
    if (inlineDeclarationsOf(current.attributes['style'])
        .any((declaration) => properties.contains(declaration.property))) {
      return true;
    }
    for (final rule in styles.cascadeRules.candidatesFor(current)) {
      if (rule.origin != CascadeOrigin.author ||
          !ruleMediaMatches(
            rule.rule.media,
            rule.rule.mediaConditions,
            contentWidth,
          ) ||
          !rule.rule.declarations.any(
            (declaration) => properties.contains(declaration.property),
          )) {
        continue;
      }
      if (rule.selectors.selectors.any(
        (selector) =>
            selector.matches(current, parents) &&
            _isScopedSelector(selector, localToElement),
      )) {
        return true;
      }
    }
    return false;
  }

  static bool _isScopedSelector(ComplexSelector selector, bool localToElement) {
    if (!localToElement) {
      return selector.specificity.id > 0 || selector.specificity.classCount > 0;
    }
    // `.wrapper p` 是容器内正文基准；当前元素自身的限定才是局部组件边距。
    final part = selector.parts.last;
    return part.id != null ||
        part.classes.isNotEmpty ||
        part.attributeTests.isNotEmpty ||
        part.pseudos.isNotEmpty;
  }

  Future<bool> _compactComponent(
    _BlockContext context,
    ComputedStyle blockStyle,
  ) async {
    final ancestors = context.ancestors;
    final parent = ancestors.length > 1
        ? styles.chainStyle(ancestors.sublist(0, ancestors.length - 1))
        : null;
    if (parent == null || blockStyle.fontSize >= parent.fontSize * 0.9) {
      return false;
    }
    for (var i = 0; i < ancestors.length - 1; i++) {
      await measure.budget.checkpoint();
      final factor = styles
          .chainStyle(ancestors.sublist(0, i + 1))
          .lineHeightFactor;
      if (factor != null && factor <= 1.05) return true;
    }
    return false;
  }

  Future<_BlockMetrics> _metrics(_BlockContext context, _BodyStyle body) async {
    final marker = _nextMarker(context, body.style);
    final measurement = await _markerMeasureStyle(context, body, marker);
    final list = context.position.list;
    final listMetrics = _ListMetrics(
      marker,
      measurement,
      context.isListItem && context.position.listFirst ? list!.spaceBefore : 0,
      context.isListItem && context.position.listLast ? list!.spaceAfter : 0,
    );
    var splitFragment = false;
    for (final ancestor in context.ancestors) {
      await measure.budget.checkpoint();
      if (styles.promotedInlineStyles.containsKey(ancestor) ||
          (context.tag == 'reader-anonymous' &&
              styles.splitInlineContainers.contains(ancestor))) {
        splitFragment = true;
        break;
      }
    }
    final paragraphSpacing = _paragraphSpacing(context, body, splitFragment);
    final absoluteBox = body.style.isOutOfFlow
        ? body.style.resolveAbsoluteBox(
            containingWidth: contentWidth,
            containingHeight: contentHeight,
          )
        : null;
    return _BlockMetrics(listMetrics, paragraphSpacing, absoluteBox);
  }

  ({double? before, double? after}) _paragraphSpacing(
    _BlockContext context,
    _BodyStyle body,
    bool splitFragment,
  ) {
    final spacing = styles.snapshot.overrides.paragraphSpacing;
    if (spacing == null ||
        context.isHeading ||
        context.tag == 'reader-anonymous' ||
        context.tag == 'li' ||
        body.style.cssFloat != CssFloat.none ||
        splitFragment ||
        body.structuredTitle ||
        body.compact) {
      return (before: null, after: null);
    }
    final logical = CssPropertyAliases.logicalPhysicalMap(
      writingMode: body.authored.style.writingMode.name,
      direction: body.authored.style.direction.name,
    );
    // 通用正文段距由阅读器控制；局部作者边距逐侧保留，不连带豁免另一侧。
    double? overrideFor(String side) =>
        _hasScopedDeclaration(context.ancestors, {
          'margin',
          'margin-$side',
          for (final entry in logical.entries)
            if (entry.value == 'margin-$side') entry.key,
        }, localToElement: true)
        ? null
        : spacing;
    return (before: overrideFor('top'), after: overrideFor('bottom'));
  }

  String? _nextMarker(_BlockContext context, ComputedStyle style) {
    final list = context.position.list;
    if (!context.isListItem || !list!.markerPending) return null;
    list.markerPending = false;
    final text = list.nextMarker(
      style.listStyleType,
      customMarker: style.listStyleString,
    );
    return text.isEmpty ? (style.listStyleImage == null ? null : '') : text;
  }

  Future<ComputedStyle> _markerMeasureStyle(
    _BlockContext context,
    _BodyStyle body,
    String? marker,
  ) async {
    final inside = body.style.values.containsKey('list-style-position')
        ? body.style.listStylePosition == CssListStylePosition.inside
        : context.position.list?.inside ?? false;
    if (marker == null || !inside) return body.style;
    final indent = await measure.insideMarkerIndent(marker, body.style);
    final position = context.position;
    final style = styles.styleForChain(
      position.ancestors,
      quoteDepth: position.quoteDepth,
      firstInContainer: position.firstInContainer,
      lastInContainer: position.lastInContainer,
      listIndent: body.authored.listIndent,
      firstLineIndent: indent,
    );
    return _applyBlockTypography(
      context,
      style,
      applyReader: body.applyReaderTypography,
    );
  }

  Future<bool> _buildImageOnly(
    _BlockContext context,
    _GeneratedText generated,
  ) async {
    final paragraph = _ParagraphText.fromNode(context.node);
    final node = context.node;
    if ((node is TextContentNode && node.leadingBreakCount > 0) ||
        paragraph.text.trim() != '\uFFFC' ||
        paragraph.images.length != 1 ||
        generated.prefix.isNotEmpty ||
        generated.suffix.isNotEmpty) {
      return false;
    }
    final image = paragraph.images.single.node;
    final footnote = await _imageOnlyFootnote(paragraph, image);
    final blocks = await images.build(
      BlockNode(
        tag: image.tag,
        display: DisplayMode.block,
        children: const <EpubNode>[],
        cfi: image.cfi,
        attributes: image.attributes,
        start: image.start,
        end: image.end,
      ),
      BlockPosition(
        ancestors: context.ancestors,
        containerFloat: context.position.containerFloat,
        containerFloatWidth: context.position.containerFloatWidth,
        containerFloatGroup: context.position.containerFloatGroup,
      ),
      footnotes: <PageFootnote>[?footnote],
    );
    measure.budget.check();
    flow.blocks.addAll(blocks);
    return true;
  }

  Future<PageFootnote?> _imageOnlyFootnote(
    _ParagraphText paragraph,
    InlineNode image,
  ) async {
    for (final mark in paragraph.marks) {
      await measure.budget.checkpoint();
      final footnote = inline.footnoteForReference(
        mark.tag,
        mark.chain.isEmpty ? const {} : mark.chain.last.attributes,
        paragraph.text.substring(mark.start, mark.end),
        start: 0,
        end: 1,
      );
      if (footnote != null) return footnote;
    }
    return inline.footnoteForReference(
      image.tag,
      image.attributes,
      '',
      start: 0,
      end: 1,
    );
  }

  Future<_ParagraphText> _expandGeneratedText(
    _BlockContext context,
    _BodyStyle body,
    _GeneratedText generated,
  ) async {
    var paragraph = _ParagraphText.fromNode(context.node);
    final marks = await _quoteMarks(context, paragraph, generated.qLevel);
    final insertions = await _quoteInsertions(marks, body.style.quotes);
    final quoted = await _quotedText(paragraph.text, insertions);
    if (insertions.isNotEmpty ||
        generated.prefix.isNotEmpty ||
        generated.suffix.isNotEmpty) {
      paragraph = await _remapParagraph(
        paragraph,
        '${generated.prefix}$quoted${generated.suffix}',
        await _quoteCoordinates(insertions, generated.prefix.length),
      );
    }
    return _ParagraphText(
      paragraph.text,
      paragraph.marks,
      paragraph.images,
      paragraph.rubies,
      await _pseudoImages(generated, paragraph.text),
      textCfis: paragraph.textCfis,
    );
  }

  Future<List<InlineMark>> _quoteMarks(
    _BlockContext context,
    _ParagraphText paragraph,
    int qLevel,
  ) async {
    final result = <InlineMark>[];
    if (context.tag == 'q' && qLevel >= 0) {
      final chain = <MarkSubject>[];
      for (final element in context.ancestors) {
        await measure.budget.checkpoint();
        chain.add(
          MarkSubject(
            tag: element.tag.toLowerCase(),
            classes: (element.attributes['class'] ?? '')
                .split(RegExp(r'\s+'))
                .where((value) => value.isNotEmpty)
                .toSet(),
            attributes: element.attributes,
          ),
        );
      }
      result.add(
        InlineMark(
          start: 0,
          end: paragraph.text.length,
          tag: 'q',
          classes: const [],
          chain: chain,
        ),
      );
    }
    for (final mark in paragraph.marks) {
      await measure.budget.checkpoint();
      if (mark.tag.toLowerCase() == 'q' && mark.end > mark.start) {
        result.add(mark);
      }
    }
    return result;
  }

  Future<List<QuoteInsertion>> _quoteInsertions(
    List<InlineMark> marks,
    CssQuotes quotes,
  ) async {
    if (quotes is CssQuotesNone) return const [];
    final insertions = <QuoteInsertion>[];
    for (final mark in marks) {
      await measure.budget.checkpoint();
      var depth = -1;
      for (final other in marks) {
        await measure.budget.checkpoint();
        if (other.start <= mark.start && other.end >= mark.end) depth += 1;
      }
      final pair = content.quotePairAt(quotes, depth);
      insertions.add(
        QuoteInsertion(
          offset: mark.start,
          text: pair.$1,
          depth: depth,
          opening: true,
        ),
      );
      insertions.add(
        QuoteInsertion(
          offset: mark.end,
          text: pair.$2,
          depth: depth,
          opening: false,
        ),
      );
    }
    insertions.sort(_compareQuoteInsertions);
    return insertions;
  }

  static int _compareQuoteInsertions(QuoteInsertion a, QuoteInsertion b) {
    final byOffset = a.offset.compareTo(b.offset);
    if (byOffset != 0) return byOffset;
    // 相邻先闭后开，嵌套开启从外到内，关闭从内到外。
    if (a.opening != b.opening) return a.opening ? 1 : -1;
    return a.opening ? a.depth.compareTo(b.depth) : b.depth.compareTo(a.depth);
  }

  Future<String> _quotedText(
    String text,
    List<QuoteInsertion> insertions,
  ) async {
    if (insertions.isEmpty) return text;
    final quoted = StringBuffer();
    var cursor = 0;
    for (final insertion in insertions) {
      await measure.budget.checkpoint();
      quoted
        ..write(text.substring(cursor, insertion.offset))
        ..write(insertion.text);
      cursor = insertion.offset;
    }
    quoted.write(text.substring(cursor));
    return quoted.toString();
  }

  Future<_CoordinateMapping> _quoteCoordinates(
    List<QuoteInsertion> insertions,
    int prefixLength,
  ) async {
    final boundaries = <(int, int, int)>[];
    var inserted = 0;
    var cursor = 0;
    while (cursor < insertions.length) {
      await measure.budget.checkpoint();
      final offset = insertions[cursor].offset;
      var atOffset = 0;
      while (cursor < insertions.length &&
          insertions[cursor].offset == offset) {
        final insertion = insertions[cursor++];
        atOffset += insertion.text.length;
      }
      inserted += atOffset;
      boundaries.add((offset, inserted, atOffset));
    }
    return _CoordinateMapping(
      (offset) => _quoteOffset(boundaries, offset, prefixLength, start: true),
      (offset) => _quoteOffset(boundaries, offset, prefixLength, start: false),
    );
  }

  static int _quoteOffset(
    List<(int, int, int)> boundaries,
    int offset,
    int prefixLength, {
    required bool start,
  }) {
    var low = 0;
    var high = boundaries.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (boundaries[middle].$1 < offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final before = low == 0 ? 0 : boundaries[low - 1].$2;
    // 起点跳过此处关闭及开启的引号，终点停在它们之前。
    final insertedHere =
        start && low < boundaries.length && boundaries[low].$1 == offset
        ? boundaries[low].$3
        : 0;
    return prefixLength + offset + before + insertedHere;
  }

  Future<List<PseudoImageMark>> _pseudoImages(
    _GeneratedText generated,
    String text,
  ) async {
    if (!generated.active) return const [];
    final result = <PseudoImageMark>[];
    for (final image
        in generated.before?.images ?? const <PseudoContentImage>[]) {
      await measure.budget.checkpoint();
      result.add(
        PseudoImageMark(
          offset: image.offset,
          url: image.url,
          pseudo: '::before',
        ),
      );
    }
    final suffixStart = text.length - generated.suffix.length;
    for (final image
        in generated.after?.images ?? const <PseudoContentImage>[]) {
      await measure.budget.checkpoint();
      result.add(
        PseudoImageMark(
          offset: suffixStart + image.offset,
          url: image.url,
          pseudo: '::after',
        ),
      );
    }
    return result;
  }

  Future<_DropCapResult> _extractDropCap(
    _BlockContext context,
    _BodyStyle body,
    _ParagraphText paragraph,
    _GeneratedText generated,
  ) async {
    final lines = body.style.initialLetterLines;
    if (!_hasFirstLineText(context, generated) ||
        lines == null ||
        lines <= 0 ||
        paragraph.text.isEmpty ||
        floatSideOfStyle(body.style) != null ||
        context.position.containerFloat != null) {
      return _DropCapResult(paragraph, null);
    }
    final letter = styles.firstLetterRun(
      styles.preparedStyles.firstLetterRules,
      context.ancestors,
      paragraph.text,
      body.style,
      sizeInitialLetter: false,
    );
    if (letter == null) return _DropCapResult(paragraph, null);
    var end = letter.end;
    if (end < paragraph.text.length &&
        isHighSurrogate(paragraph.text.codeUnitAt(letter.start)) &&
        isLowSurrogate(paragraph.text.codeUnitAt(end))) {
      end += 1;
    }
    final cap = _DropCap(
      paragraph.text.substring(letter.start, end),
      letter.style,
      lines,
      paragraph.textCfis?.slice(letter.start, end),
    );
    final mapping = _CoordinateMapping.removal(letter.start, end);
    final remaining = await _remapParagraph(
      paragraph,
      paragraph.text.substring(0, letter.start) + paragraph.text.substring(end),
      mapping,
    );
    return _DropCapResult(remaining, cap);
  }

  Future<_ParagraphText> _remapParagraph(
    _ParagraphText paragraph,
    String text,
    _CoordinateMapping mapping, {
    List<InlineMark>? marks,
  }) async => _ParagraphText(
    text,
    marks ?? await _remapMarks(paragraph.marks, mapping),
    await _remapImages(paragraph.images, mapping),
    mapping.remapRubies
        ? await _remapRubies(paragraph.rubies, mapping)
        : paragraph.rubies,
    await _remapPseudoImages(paragraph.pseudoImages, mapping),
    textCfis: await paragraph.textCfis?.remapAsync(
      length: text.length,
      start: mapping.start,
      end: mapping.end,
      checkpoint: measure.budget.checkpoint,
    ),
  );

  Future<List<InlineMark>> _remapMarks(
    List<InlineMark> marks,
    _CoordinateMapping mapping,
  ) async {
    final result = <InlineMark>[];
    for (final mark in marks) {
      await measure.budget.checkpoint();
      final start = mapping.start(mark.start);
      final end = mapping.end(mark.end);
      if (mapping.removeEmpty && end <= start) continue;
      result.add(
        InlineMark(
          start: start,
          end: end,
          tag: mark.tag,
          classes: mark.classes,
          chain: mark.chain,
        ),
      );
    }
    return result;
  }

  Future<List<InlineImageMark>> _remapImages(
    List<InlineImageMark> images,
    _CoordinateMapping mapping,
  ) async {
    final result = <InlineImageMark>[];
    for (final image in images) {
      await measure.budget.checkpoint();
      if (mapping.keepOffset?.call(image.offset) == false) continue;
      result.add(
        InlineImageMark(offset: mapping.start(image.offset), node: image.node),
      );
    }
    return result;
  }

  Future<List<RubyMark>> _remapRubies(
    List<RubyMark> rubies,
    _CoordinateMapping mapping,
  ) async {
    final result = <RubyMark>[];
    for (final ruby in rubies) {
      await measure.budget.checkpoint();
      final start = mapping.start(ruby.start);
      final end = mapping.end(ruby.end);
      if (mapping.removeEmpty && end <= start) continue;
      result.add(
        RubyMark(start: start, end: end, text: ruby.text, chain: ruby.chain),
      );
    }
    return result;
  }

  Future<List<PseudoImageMark>> _remapPseudoImages(
    List<PseudoImageMark> images,
    _CoordinateMapping mapping,
  ) async {
    final result = <PseudoImageMark>[];
    for (final image in images) {
      await measure.budget.checkpoint();
      if (mapping.keepOffset?.call(image.offset) == false) continue;
      result.add(
        PseudoImageMark(
          offset: mapping.start(image.offset),
          url: image.url,
          pseudo: image.pseudo,
        ),
      );
    }
    return result;
  }

  Future<_InlineParagraph> _inlineParagraph(
    _BlockContext context,
    _BodyStyle body,
    _GeneratedText generated,
    _DropCapResult dropped,
  ) async {
    final inlineContext = _inlineContext(context, body);
    final extracted = await _extractInlineElements(
      context,
      body,
      dropped.paragraph,
      inlineContext,
    );
    final runs = await styles.resolveInlineRuns(
      extracted.paragraph.marks,
      inlineContext,
      checkpoint: measure.budget.checkpoint,
    );
    final styledRuns = _pseudoRuns(
      context,
      body.style,
      generated,
      extracted.paragraph,
      runs,
    );
    final images = await _inlineImages(
      context,
      body,
      extracted.paragraph,
      inlineContext,
      extracted.elements,
    );
    return _InlineParagraph(
      _DropCapResult(extracted.paragraph, dropped.cap),
      extracted.elements,
      styledRuns,
      images,
      _hasFirstLineText(context, generated),
    );
  }

  bool _hasFirstLineText(_BlockContext context, _GeneratedText generated) =>
      context.node is! TextContentNode ||
      (context.node as TextContentNode).leadingBreakCount == 0 ||
      generated.prefix.isNotEmpty;

  InlineStyleContext _inlineContext(_BlockContext context, _BodyStyle body) => (
    ancestors: context.ancestors,
    style: body.style,
    width: measure.textWidthFor(
      body.style,
      preserveNarrowWidth: styles.preservesContainerWidth(context.ancestors),
    ),
    readerFontFamily: body.applyReaderTypography
        ? styles.snapshot.overrides.fontFamily
        : null,
  );

  Future<({_ParagraphText paragraph, _InlineElements elements})>
  _extractInlineElements(
    _BlockContext context,
    _BodyStyle body,
    _ParagraphText initial,
    InlineStyleContext inlineContext,
  ) async {
    var paragraph = initial;
    final elements = _InlineElements();
    if (context.node is! TextContentNode ||
        floatSideOfStyle(body.style) != null ||
        context.position.containerFloat != null) {
      return (paragraph: paragraph, elements: elements);
    }
    final limit = initial.marks.length + initial.images.length;
    for (var guard = 0; guard < limit; guard += 1) {
      await measure.budget.checkpoint();
      final extracted = await inline.extractInlineFloat(
        text: paragraph.text,
        marks: paragraph.marks,
        images: paragraph.images,
        context: inlineContext,
        textCfis: paragraph.textCfis,
      );
      if (extracted == null) break;
      _recordExtractedElements(elements, extracted);
      // 保留旧提取器的 ruby 口径；图片与生成图片跟随摘除坐标重映射。
      paragraph = await _remapParagraph(
        paragraph,
        extracted.text,
        _CoordinateMapping(
          extracted.remapOffset,
          extracted.remapOffset,
          keepOffset: (offset) => !extracted.removed(offset),
          remapRubies: false,
        ),
        marks: extracted.marks,
      );
    }
    return (paragraph: paragraph, elements: elements);
  }

  void _recordExtractedElements(
    _InlineElements elements,
    InlineFloatExtraction extracted,
  ) {
    if (extracted.block case final block?) elements.floats.add(block);
    if (extracted.inlineBox == null) return;
    elements.boxes = inline.appendInlineBox(elements.boxes, extracted);
    if (extracted.footnote case final footnote?) {
      elements.footnotes.add(footnote);
    }
  }

  List<StyledRun> _pseudoRuns(
    _BlockContext context,
    ComputedStyle parent,
    _GeneratedText generated,
    _ParagraphText paragraph,
    List<StyledRun> runs,
  ) => [
    if (generated.prefix.isNotEmpty)
      _pseudoRun(
        start: 0,
        end: generated.prefix.length,
        text: generated.prefix,
        style: styles.pseudoStyleFor(_pseudoChain(context), parent, '::before'),
      ),
    ...runs,
    if (generated.suffix.isNotEmpty)
      _pseudoRun(
        start: paragraph.text.length - generated.suffix.length,
        end: paragraph.text.length,
        text: generated.suffix,
        style: styles.pseudoStyleFor(_pseudoChain(context), parent, '::after'),
      ),
  ];

  StyledRun _pseudoRun({
    required int start,
    required int end,
    required String text,
    required ComputedStyle style,
  }) {
    final run = StyledRun(start: start, end: end, style: style);
    // 单图生成内容的边距与装饰由替换图盒统一占宽，文字内容在首尾计一次。
    final replacedImage = text == '\uFFFC';
    return StyledRun(
      start: start,
      end: end,
      style: style,
      inlineLeadingInset: replacedImage
          ? 0
          : style.margin.left + run.leadingInset,
      inlineTrailingInset: replacedImage
          ? 0
          : style.margin.right + run.trailingInset,
    );
  }

  Future<List<InlineImageSpec>> _inlineImages(
    _BlockContext context,
    _BodyStyle body,
    _ParagraphText paragraph,
    InlineStyleContext inlineContext,
    _InlineElements elements,
  ) async {
    final result = <InlineImageSpec>[];
    for (final mark in paragraph.images) {
      await measure.budget.checkpoint();
      final attributes = mark.node.attributes;
      final src =
          attributes['src'] ??
          attributes['xlink:href'] ??
          attributes['href'] ??
          attributes['data'];
      if (src == null || src.isEmpty) continue;
      final chain = _imageChain(context, paragraph, mark);
      final imageStyle = styles.chainStyle(chain);
      final image = _imageSpec(mark.offset, inline.imageUrl(src), imageStyle);
      await inline.prepareImageIntrinsicSize(image.url);
      result.add(image);
      if (imageStyle.writingMode == CssWritingMode.horizontalTb) {
        elements.boxes.add(
          inline.inlineImageBox(image, imageStyle, chain, inlineContext.width),
        );
      }
    }
    for (final mark in paragraph.pseudoImages) {
      await measure.budget.checkpoint();
      final style = styles.pseudoStyleFor(
        _pseudoChain(context),
        body.style,
        mark.pseudo,
      );
      final image = _imageSpec(mark.offset, mark.url, style);
      await inline.prepareImageIntrinsicSize(image.url);
      result.add(image);
      if (style.writingMode == CssWritingMode.horizontalTb) {
        elements.boxes.add(
          inline.inlineImageBox(
            image,
            style,
            context.ancestors,
            inlineContext.width,
          ),
        );
      }
    }
    return result;
  }

  List<SelectorElement> _imageChain(
    _BlockContext context,
    _ParagraphText paragraph,
    InlineImageMark image,
  ) {
    final source = paragraph.marks
        .where(
          (mark) => mark.start == image.offset && mark.tag == image.node.tag,
        )
        .firstOrNull;
    return source == null
        ? [
            ...context.ancestors,
            ChapterNodeView(image.node.tag, image.node.attributes, const []),
          ]
        : styles.inlineMarkChain(source, context.ancestors);
  }

  InlineImageSpec _imageSpec(int offset, String url, ComputedStyle style) =>
      InlineImageSpec(
        offset: offset,
        url: url,
        width: style.width?.resolve(contentWidth),
        height: style.height?.resolve(contentWidth),
        aspectRatio: style.aspectRatio,
      );

  Future<List<PageFootnote>> _footnotes(_InlineParagraph paragraph) async {
    final notes = _FootnoteCollector(inline, paragraph.elements.footnotes);
    final text = paragraph.dropped.paragraph;
    for (final mark in text.marks) {
      await measure.budget.checkpoint();
      notes.add(
        mark.tag,
        mark.chain.isEmpty ? const {} : mark.chain.last.attributes,
        text.text.substring(mark.start, mark.end),
        mark.start,
        mark.end,
      );
    }
    for (final image in text.images) {
      await measure.budget.checkpoint();
      notes.add(
        image.node.tag,
        image.node.attributes,
        '',
        image.offset,
        image.offset + 1,
      );
    }
    return notes.result;
  }

  Future<List<StyledRun>> _paragraphRuns(
    _BlockContext context,
    _BodyStyle body,
    _BlockMetrics metrics,
    _InlineParagraph paragraph, {
    ({ComputedStyle style, List<StyledRun> runs})? firstLine,
  }) async {
    final runs = <StyledRun>[];
    for (final run in firstLine?.runs ?? paragraph.runs) {
      await measure.budget.checkpoint();
      final replaced = paragraph.elements.boxes.any(
        (box) =>
            box.replacesPlaceholder &&
            run.start == box.offset &&
            run.end == box.offset + 1,
      );
      if (replaced) {
        if (firstLine == null) {
          _preserveImageInlineSpacing(run, paragraph.elements);
        }
      } else {
        runs.add(run);
      }
    }
    if (paragraph.hasFirstLineText && paragraph.dropped.cap == null) {
      final letter = styles.firstLetterRun(
        styles.preparedStyles.firstLetterRules,
        context.ancestors,
        paragraph.dropped.paragraph.text,
        body.style,
        firstLineStyle: firstLine?.style,
      );
      if (letter != null) runs.add(letter);
    }
    return styles.snapshot.textOverlays.resolve(
      blockCfi: _contentCfi(context, paragraph),
      textCfis: paragraph.dropped.paragraph.textCfis,
      text: paragraph.dropped.paragraph.text,
      style: firstLine?.style ?? metrics.list.measureStyle,
      runs: runs,
    );
  }

  Future<List<StyledRun>> _firstLineRuns(
    _BlockContext context,
    _BodyStyle body,
    _BlockMetrics metrics,
    _InlineParagraph paragraph,
    ({ComputedStyle style, _GeneratedText generated}) firstLine,
  ) async {
    final inherited = _inlineContext(context, body);
    final runs = await styles.resolveInlineRuns(
      paragraph.dropped.paragraph.marks,
      (
        ancestors: inherited.ancestors,
        style: firstLine.style,
        width: inherited.width,
        readerFontFamily: inherited.readerFontFamily,
      ),
      checkpoint: measure.budget.checkpoint,
    );
    return _paragraphRuns(
      context,
      body,
      metrics,
      paragraph,
      firstLine: (
        style: firstLine.style,
        runs: _pseudoRuns(
          context,
          firstLine.style,
          firstLine.generated,
          paragraph.dropped.paragraph,
          runs,
        ),
      ),
    );
  }

  void _preserveImageInlineSpacing(StyledRun run, _InlineElements elements) {
    // 图片盒已包含自身装饰；只保留解析器明确记录的祖先首尾占宽。
    final leading = run.inlineLeadingInset ?? 0;
    final trailing = run.inlineTrailingInset ?? 0;
    if (leading == 0 && trailing == 0) return;
    elements.boxes = [
      ...elements.boxes,
      if (leading > 0)
        InlineBoxSpec(
          offset: run.start,
          width: leading,
          height: 0,
          payload: InlineSpacingEdge.leading,
        ),
      if (trailing > 0)
        InlineBoxSpec(
          offset: run.end,
          width: trailing,
          height: 0,
          payload: InlineSpacingEdge.trailing,
        ),
    ];
  }

  /// 纯空行只占布局高度，不能把源码空白节点作为可保存的正文锚点。
  String? _contentCfi(_BlockContext context, _InlineParagraph paragraph) =>
      paragraph.dropped.paragraph.text.isEmpty
      ? null
      : paragraph.dropped.paragraph.textCfis?.cfiAt(0) ?? context.cfi;

  Future<_MeasuredParagraph> _measureParagraph(
    _BlockContext context,
    _BodyStyle body,
    _BlockMetrics metrics,
    _InlineParagraph paragraph,
    _GeneratedText generated,
  ) async {
    final notes = await _footnotes(paragraph);
    final runs = await _paragraphRuns(context, body, metrics, paragraph);
    final firstLineStyle = paragraph.hasFirstLineText
        ? styles.firstLineStyleFor(context.ancestors, metrics.list.measureStyle)
        : null;
    final firstLineRuns = firstLineStyle == null
        ? null
        : await _firstLineRuns(context, body, metrics, paragraph, (
            style: firstLineStyle,
            generated: generated,
          ));
    final text = paragraph.dropped.paragraph;
    final rubies = await _rubyAnnotations(context, body, text);
    final width = await _paragraphWidth(context, body, metrics, paragraph, (
      runs: runs,
      rubies: rubies,
    ));
    final layout = await measure.layout(
      text: text.text,
      style: metrics.list.measureStyle,
      maxWidth: width,
      runs: runs,
      rubies: rubies,
      inlineBoxes: paragraph.elements.boxes,
      preserveContentWidth:
          metrics.list.measureStyle.writingMode !=
              CssWritingMode.horizontalTb ||
          metrics.list.measureStyle.cssFloat != CssFloat.none ||
          styles.preservesContainerWidth(context.ancestors),
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
    );
    return _MeasuredParagraph(
      _layoutBounds(
        await _withLeadingBreaks(
          context,
          metrics,
          paragraph,
          generated,
          await _fillParagraphLines(
            context,
            body,
            paragraph,
            generated,
            layout,
          ),
        ),
        body.style,
        metrics.list.measureStyle,
      ),
      paragraph,
      notes,
      rubies,
      (
        cfi: _contentCfi(context, paragraph),
        map: await text.textCfis?.transformedAsync(
          layout.inputOffsets,
          checkpoint: measure.budget.checkpoint,
        ),
      ),
    );
  }

  Future<TextLayoutResult> _fillParagraphLines(
    _BlockContext context,
    _BodyStyle body,
    _InlineParagraph paragraph,
    _GeneratedText generated,
    TextLayoutResult layout,
  ) async {
    if (!body.applyReaderTypography ||
        layout.lines.length < 2 ||
        paragraph.dropped.cap != null ||
        paragraph.dropped.paragraph.rubies.isNotEmpty ||
        paragraph.elements.boxes.isNotEmpty ||
        paragraph.elements.floats.isNotEmpty ||
        generated.prefix.isNotEmpty ||
        generated.suffix.isNotEmpty) {
      return layout;
    }
    final filled = fillProseLineEnds(body.style, context.ancestors, layout);
    if (identical(filled, layout) ||
        await _hasAuthoredProseSpacing(context, paragraph)) {
      return layout;
    }
    return filled;
  }

  Future<bool> _hasAuthoredProseSpacing(
    _BlockContext context,
    _InlineParagraph paragraph,
  ) async {
    const properties = {'letter-spacing', 'word-spacing', 'text-justify'};
    final seen = <SelectorElement>{};
    final chains = [
      context.ancestors,
      for (final mark in paragraph.dropped.paragraph.marks)
        styles.inlineMarkChain(mark, context.ancestors),
    ];
    for (final chain in chains) {
      for (var i = 0; i < chain.length; i++) {
        if (!seen.add(chain[i])) continue;
        await measure.budget.checkpoint();
        final authored = styles.chainStyle(chain.sublist(0, i + 1));
        if (authored.explicitProperties.any(properties.contains)) return true;
      }
    }
    return false;
  }

  Future<TextLayoutResult> _withLeadingBreaks(
    _BlockContext context,
    _BlockMetrics metrics,
    _InlineParagraph paragraph,
    _GeneratedText generated,
    TextLayoutResult layout,
  ) async {
    final node = context.node;
    if (node is! TextContentNode || node.leadingBreakCount == 0) return layout;
    // 仅补横排普通首行；前缀、首字下沉和竖排仍沿用原有布局顺序。
    if (layout.isVertical ||
        generated.prefix.isNotEmpty ||
        paragraph.dropped.cap != null) {
      return layout;
    }
    final strut = await _emptyLineStrut(
      metrics.list.measureStyle,
      layout.maxWidth,
    );
    if (strut == null) return layout;
    final firstStyle = styles.firstLineStyleFor(
      context.ancestors,
      metrics.list.measureStyle,
    );
    // 缓存仍只保存正文几何，补空行时新建结果，保持文字、样式区间及 CFI。
    return _prependEmptyLines(
      layout,
      strut,
      node.leadingBreakCount,
      hasContent: layout.text.isNotEmpty || paragraph.elements.boxes.isNotEmpty,
      firstStrut: firstStyle == null
          ? strut
          : await _emptyLineStrut(firstStyle, layout.maxWidth) ?? strut,
    );
  }

  Future<LineBox?> _emptyLineStrut(ComputedStyle style, double width) async =>
      (await measure.layout(
        text: ' ',
        style: style,
        maxWidth: width,
      )).lines.firstOrNull;

  TextLayoutResult _prependEmptyLines(
    TextLayoutResult layout,
    LineBox strut,
    int count, {
    required bool hasContent,
    required LineBox firstStrut,
  }) {
    final shift = firstStrut.height + strut.height * (count - 1);
    final lines = <LineBox>[
      for (var i = 0; i < count; i++)
        _emptyLine(
          i == 0 ? firstStrut : strut,
          i == 0 ? 0 : firstStrut.height + strut.height * (i - 1),
          !hasContent && i == count - 1,
        ),
      if (hasContent)
        for (final line in layout.lines) line.copyWith(top: line.top + shift),
    ];
    return TextLayoutResult(
      text: layout.text,
      lines: lines,
      width: layout.width,
      height: shift + (hasContent ? layout.height : 0),
      maxWidth: layout.maxWidth,
      runs: layout.runs,
      isRtl: layout.isRtl,
      writingMode: layout.writingMode,
      plainTextLayout: layout.plainTextLayout,
      firstLineStyle: layout.firstLineStyle,
      firstLineRuns: layout.firstLineRuns,
      sourceRuns: layout.sourceRuns,
      inputOffsets: layout.inputOffsets,
    );
  }

  LineBox _emptyLine(LineBox strut, double top, bool isLastLine) => LineBox(
    start: 0,
    end: 0,
    top: top,
    height: strut.height,
    baseline: strut.baseline - strut.top + top,
    width: 0,
    isHardBreak: true,
    isLastLine: isLastLine,
  );

  Future<double> _paragraphWidth(
    _BlockContext context,
    _BodyStyle body,
    _BlockMetrics metrics,
    _InlineParagraph paragraph,
    ({List<StyledRun> runs, List<RubyAnnotation> rubies}) annotations,
  ) async {
    final style = metrics.list.measureStyle;
    final floating =
        style.cssFloat != CssFloat.none &&
        !style.isOutOfFlow &&
        style.writingMode == CssWritingMode.horizontalTb;
    final autoFloat = floating && (style.width == null || style.width!.isAuto);
    if ((!autoFloat && !style.hasIntrinsicWidth) ||
        (!floating &&
            (!ChapterTextMeasurer.isOrdinaryHorizontalBlock(style) ||
                context.position.containerFloat != null))) {
      return _measureWidth(context, body, metrics);
    }
    final widths = await measure.intrinsicWidths(
      paragraph.dropped.paragraph.text,
      style,
      runs: annotations.runs,
      rubies: annotations.rubies,
      inlineBoxes: paragraph.elements.boxes,
    );
    return BoxModel.fromStyle(
      style,
      containingWidth: contentWidth,
    ).resolveContentWidth(contentWidth, intrinsicWidths: widths);
  }

  Future<List<RubyAnnotation>> _rubyAnnotations(
    _BlockContext context,
    _BodyStyle body,
    _ParagraphText text,
  ) async {
    final annotations = <RubyAnnotation>[];
    final inlineContext = _inlineContext(context, body);
    for (final ruby in text.rubies) {
      await measure.budget.checkpoint();
      final chain = ruby.chain;
      final style = chain.isEmpty
          ? null
          : await styles.inlineMarkStyle(
              InlineMark(
                start: ruby.start,
                end: ruby.end,
                tag: chain.last.tag,
                classes: chain.last.classes.toList(),
                chain: chain,
              ),
              inlineContext,
              checkpoint: measure.budget.checkpoint,
            );
      annotations.add(
        RubyAnnotation(
          start: ruby.start,
          end: ruby.end,
          text: ruby.text,
          style: style,
        ),
      );
    }
    return annotations;
  }

  double _measureWidth(
    _BlockContext context,
    _BodyStyle body,
    _BlockMetrics metrics,
  ) {
    final verticalLength = _verticalFlexColumnLength(
      context,
      metrics.list.measureStyle,
    );
    if (verticalLength != null) return verticalLength;
    final position = context.position;
    return floatSideOfStyle(body.style) == null &&
            position.containerFloat != null &&
            position.containerFloatWidth != null
        ? styles.textWidthInFloat(
            context.ancestors,
            position.containerFloatWidth!,
          )
        : measure.textWidthFor(
            metrics.list.measureStyle,
            preserveNarrowWidth: styles.preservesContainerWidth(
              context.ancestors,
            ),
          );
  }

  /// 横向 Flex 中竖排子项的内联轴是纵向；父盒横向留白不能缩短列长。
  double? _verticalFlexColumnLength(
    _BlockContext context,
    ComputedStyle style,
  ) {
    if (style.writingMode == CssWritingMode.horizontalTb ||
        style.isOutOfFlow ||
        context.ancestors.length < 2) {
      return null;
    }
    final parent = styles.chainStyle(
      context.ancestors.sublist(0, context.ancestors.length - 1),
    );
    if (parent.display != CssDisplay.flex ||
        parent.flexDirection != CssFlexDirection.row ||
        parent.writingMode != CssWritingMode.horizontalTb) {
      return null;
    }
    final parentBox = BoxModel.fromStyle(parent, containingWidth: contentWidth);
    final available = parentBox.resolveContentHeight(
      math.max(
        0,
        contentHeight - parent.margin.vertical - parentBox.verticalInset,
      ),
      containingHeight: contentHeight,
    );
    final box = BoxModel.fromStyle(style, containingWidth: contentWidth);
    return math.max(1, available - style.margin.vertical - box.verticalInset);
  }

  TextLayoutResult _layoutBounds(
    TextLayoutResult layout,
    ComputedStyle blockStyle,
    ComputedStyle measureStyle,
  ) {
    var result = layout;
    if (blockStyle.isOutOfFlow && blockStyle.width != null) {
      final box = BoxModel.fromStyle(blockStyle, containingWidth: contentWidth);
      final width =
          (box.contentWidth ?? 0) +
          box.padding.horizontal +
          box.borders.left +
          box.borders.right;
      result = pageBlockWithLayoutWidth(result, width: width, maxWidth: width);
    }
    final declaredWidth =
        measureStyle.width != null && !measureStyle.width!.isAuto;
    if (measureStyle.writingMode != CssWritingMode.horizontalTb &&
        !declaredWidth &&
        result.width.isFinite &&
        result.width > 0 &&
        result.width != result.maxWidth) {
      result = pageBlockWithLayoutWidth(result, maxWidth: result.width);
    }
    return result;
  }

  Future<void> _appendBlocks(
    _BlockContext context,
    _BodyStyle body,
    _BlockMetrics metrics,
    _MeasuredParagraph paragraph,
  ) async {
    await _appendLeadingBlocks(context, body, metrics, paragraph);
    measure.budget.check();
    if (paragraph.layout.lineCount == 0) return;
    final side =
        floatSideOfStyle(body.style) ?? context.position.containerFloat;
    final inFlow = !body.style.isOutOfFlow && side == null;
    final incomingShift = inFlow ? flow.pendingRelativeTop : 0.0;
    if (inFlow) flow.pendingRelativeTop = 0;
    final spacing = _blockSpacing(body, metrics, incomingShift);
    if (side != null) {
      flow.blocks.add(_floatBlock(context, body, paragraph, spacing, side));
      return;
    }
    var block = _styledBlock(context, body, metrics, paragraph, spacing);
    block = _relativeBlock(block, body.authored.relative);
    if (body.authored.relative.top != 0) {
      flow.pendingRelativeTop += body.authored.relative.top;
    }
    if (_isStructuredHeading(context, body.style, paragraph.layout)) {
      block = block.withSpacing(breakAfterAvoid: true);
    }
    if (body.style.position == CssPosition.fixed) {
      flow.fixedBlocks.add(block);
    } else {
      flow.blocks.add(block);
    }
  }

  static ({double before, double after}) _blockSpacing(
    _BodyStyle body,
    _BlockMetrics metrics,
    double incomingShift,
  ) => (
    before:
        (metrics.paragraphSpacing.before ?? body.style.margin.top) +
        metrics.list.before -
        incomingShift,
    after:
        (metrics.paragraphSpacing.after ?? body.style.margin.bottom) +
        metrics.list.after,
  );

  Future<void> _appendLeadingBlocks(
    _BlockContext context,
    _BodyStyle body,
    _BlockMetrics metrics,
    _MeasuredParagraph paragraph,
  ) async {
    final leading = List<PageBlock>.of(paragraph.inline.elements.floats);
    final cap = paragraph.inline.dropped.cap;
    if (cap != null) {
      leading.add(
        await measure.dropCapBlock(
          text: cap.text,
          style: cap.style,
          bodyLineHeight:
              paragraph.layout.lines.firstOrNull?.height ??
              body.style.lineHeight,
          lineCount: cap.lines,
          gap: body.style.fontSize * 0.25,
          effectiveOpacity: body.authored.container.opacity,
          startCfi: context.cfi,
          textCfis: cap.textCfis,
        ),
      );
    }
    if (_retainsInlineFloatParagraph(context, body, paragraph, leading)) {
      await _wrapInlineFloatParagraph(context, body, metrics, leading);
    }
    measure.budget.check();
    flow.blocks.addAll(leading);
  }

  bool _retainsInlineFloatParagraph(
    _BlockContext context,
    _BodyStyle body,
    _MeasuredParagraph paragraph,
    List<PageBlock> leading,
  ) =>
      leading.isNotEmpty &&
      paragraph.layout.lineCount == 0 &&
      !body.style.isOutOfFlow &&
      body.style.cssFloat == CssFloat.none &&
      context.position.containerFloat == null &&
      body.style.writingMode == CssWritingMode.horizontalTb &&
      const {
        CssOverflow.hidden,
        CssOverflow.auto,
        CssOverflow.scroll,
      }.contains(body.style.overflow);

  Future<void> _wrapInlineFloatParagraph(
    _BlockContext context,
    _BodyStyle body,
    _BlockMetrics metrics,
    List<PageBlock> leading,
  ) async {
    final raw = styles
        .chainStyle(context.ancestors)
        .scaleRelativeTypography(body.style.fontSize);
    final spacing = _blockSpacing(body, metrics, 0);
    final style = raw.withMargins(
      CssEdges(
        top: spacing.before,
        bottom: spacing.after,
        left: raw.margin.left,
        right: raw.margin.right,
      ),
    );
    final width = _inlineContext(context, body).width;
    final model = BoxModel.fromStyle(style, containingWidth: width);
    final container = InlineFloatContainer(
      style: style,
      left: body.style.margin.left,
      width: model.borderBoxWidth(width),
    );
    leading.insert(0, _inlineFloatSpacer(width));
    leading.add(_inlineFloatSpacer(width));
    await wrapContainerBlocks(
      leading,
      0,
      container,
      checkpoint: measure.budget.checkpoint,
    );
  }

  static PageBlock _inlineFloatSpacer(double width) => PageBlock(
    layout: TextLayoutResult(
      text: '',
      lines: const [],
      width: width,
      height: 0,
      maxWidth: width,
    ),
  );

  // 此处多数行是既有参数透传；将包含块与外边距一起求解，避免拆分后坐标不一致。
  PageBlock _floatBlock(
    _BlockContext context,
    _BodyStyle body,
    _MeasuredParagraph paragraph,
    ({double before, double after}) spacing,
    FloatSide side,
  ) {
    final box = floatSideOfStyle(body.style) == null
        ? null
        : styles.floatBoxForChain(context.ancestors);
    final own = box == null
        ? body.style.margin
        : styles.chainStyle(context.ancestors)
              .scaleRelativeTypography(body.style.fontSize)
              .margin;
    // 父内缩参与浮动可用区域，不能再当作每个浮动自身的外边距重复占宽。
    final style = box == null
        ? body.style
        : body.style.withMargins(
            CssEdges(
              top: body.style.margin.top,
              bottom: body.style.margin.bottom,
              left: own.left,
              right: own.right,
            ),
          );
    return measure.floatedTextBlock(
      layout: paragraph.layout,
      style: style,
      side: side,
      spaceBefore: spacing.before,
      spaceAfter: spacing.after,
      inlineImages: paragraph.images,
      footnotes: paragraph.footnotes,
      rubies: paragraph.rubies.isEmpty ? null : paragraph.rubies,
      startCfi: paragraph.contentCfi,
      textCfis: paragraph.textCfis,
      textRuleEligible: context.textRuleEligible,
      groupId:
          side == context.position.containerFloat &&
              context.position.containerFloat != null
          ? context.position.containerFloatGroup
          : context.position.groupId,
      containerSides: body.authored.container.bordered,
      effectiveOpacity: body.authored.container.opacity,
      containingLeft: box?.containingLeft,
      containingWidth: box?.containingWidth,
    );
  }

  PageBlock _styledBlock(
    _BlockContext context,
    _BodyStyle body,
    _BlockMetrics metrics,
    _MeasuredParagraph paragraph,
    ({double before, double after}) spacing,
  ) => PageBlock.styled(
    layout: paragraph.layout,
    style: styles.intrinsicBlockStyle(
      body.style,
      context.ancestors,
      paragraph.layout.maxWidth,
    ),
    containingWidth: contentWidth,
    startCfi: paragraph.contentCfi,
    textCfis: paragraph.textCfis,
    textRuleEligible: context.textRuleEligible,
    groupId: context.position.groupId,
    listMarker: metrics.list.marker,
    spaceBefore: spacing.before,
    spaceAfter: spacing.after,
    rubies: paragraph.rubies.isEmpty ? null : paragraph.rubies,
    inlineImages: paragraph.images,
    footnotes: paragraph.footnotes,
    absolute: body.style.isOutOfFlow,
    absoluteTop: metrics.absoluteBox?.top,
    absoluteLeft: metrics.absoluteBox?.left,
    bleedLeft: body.style.bleed.left,
    bleedRight: body.style.bleed.right,
    bleedTop: body.style.bleed.top,
    bleedBottom: body.style.bleed.bottom,
    containerSides: body.authored.container.bordered,
    effectiveOpacity: body.authored.container.opacity,
  );

  PageBlock _relativeBlock(
    PageBlock block,
    ({double left, double top}) relative,
  ) {
    if (relative.left == 0 && relative.top == 0) return block;
    // 按原相对定位分支复制字段，保留其视觉搬移与相邻段距抵扣口径。
    return PageBlock(
      layout: block.layout,
      style: block.style,
      spaceBefore: block.spaceBefore + relative.top,
      spaceAfter: math.max(0.0, block.spaceAfter - relative.top),
      topInset: block.topInset,
      bottomInset: block.bottomInset,
      leftInset: block.leftInset + relative.left,
      startCfi: block.startCfi,
      endCfi: block.endCfi,
      textCfis: block.textCfis,
      textRuleEligible: block.textRuleEligible,
      groupId: block.groupId,
      listMarker: block.listMarker,
      rubies: block.rubies,
      inlineImages: block.inlineImages,
      footnotes: block.footnotes,
      absolute: block.absolute,
      absoluteTop: block.absoluteTop,
      absoluteLeft: block.absoluteLeft,
      bleedLeft: block.bleedLeft,
      bleedRight: block.bleedRight,
      bleedTop: block.bleedTop,
      bleedBottom: block.bleedBottom,
      containerSides: block.containerSides,
      effectiveOpacity: block.effectiveOpacity,
      declaredContentHeight: block.declaredContentHeight,
      verticalContentWidth: block.verticalContentWidth,
    );
  }

  static bool _hasStructuredTitleText(String text, ComputedStyle style) =>
      !text.contains('\uFFFC') &&
      text.trim().length <= 40 &&
      (style.textAlign == CssTextAlign.center ||
          style.borders.hasBorder ||
          style.padding.horizontal > 0);

  static bool _isStructuredHeading(
    _BlockContext context,
    ComputedStyle style,
    TextLayoutResult layout,
  ) =>
      !context.isHeading &&
      layout.lineCount > 0 &&
      layout.lineCount <= 2 &&
      layout.text.trim().isNotEmpty &&
      _hasStructuredTitleText(layout.text, style);
}

class _BlockContext {
  _BlockContext(this.node, this.position, this.textRuleEligible)
    : cfi = node is TextContentNode ? node.cfi.serialize() : null;
  final TextBlockNode node;
  final BlockPosition position;
  final bool textRuleEligible;
  List<SelectorElement> get ancestors => position.ancestors;
  String get tag => ancestors.isEmpty ? 'body' : ancestors.last.tag;
  bool get isHeading => const {
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  }.contains(tag == 'reader-anonymous' ? position.blockTag : tag);
  bool get isListItem => tag == 'li' && position.list != null;
  final String? cfi;
}

class _AuthoredStyle {
  const _AuthoredStyle(
    this.style,
    this.listIndent,
    this.relative,
    this.container,
  );
  final ComputedStyle style;
  final double listIndent;
  final ({double left, double top}) relative;
  final ({bool bordered, double opacity}) container;
}

class _BodyStyle {
  const _BodyStyle(
    this.authored,
    this.style,
    this.compact,
    this.structuredTitle,
    this.applyReaderTypography,
  );
  final _AuthoredStyle authored;
  final ComputedStyle style;
  final bool compact;
  final bool structuredTitle;
  final bool applyReaderTypography;
}

class _ListMetrics {
  const _ListMetrics(this.marker, this.measureStyle, this.before, this.after);
  final String? marker;
  final ComputedStyle measureStyle;
  final double before;
  final double after;
}

class _BlockMetrics {
  const _BlockMetrics(this.list, this.paragraphSpacing, this.absoluteBox);
  final _ListMetrics list;
  final ({double? before, double? after}) paragraphSpacing;
  final CssAbsoluteBox? absoluteBox;
}

class _GeneratedText {
  const _GeneratedText(this.before, this.after, this.active, this.qLevel);
  final PseudoContent? before;
  final PseudoContent? after;
  final bool active;
  final int qLevel;
  String get prefix => active ? before?.text ?? '' : '';
  String get suffix => active ? after?.text ?? '' : '';
}

/// 所有 UTF-16 范围共享一个文字版本，变换后一起生成下一份坐标输入。
class _ParagraphText {
  const _ParagraphText(
    this.text,
    this.marks,
    this.images,
    this.rubies,
    this.pseudoImages, {
    this.textCfis,
  });
  factory _ParagraphText.fromNode(TextBlockNode node) => node is TextContentNode
      ? _ParagraphText(
          node.text,
          node.inlineMarks,
          node.inlineImages,
          node.rubies,
          const [],
          textCfis:
              node.textCfis ?? TextCfiMap.linear(node.cfi, node.text.length),
        )
      : _ParagraphText(node.text, const [], const [], const [], const []);
  final String text;
  final List<InlineMark> marks;
  final List<InlineImageMark> images;
  final List<RubyMark> rubies;
  final List<PseudoImageMark> pseudoImages;
  final TextCfiMap? textCfis;
}

class _CoordinateMapping {
  const _CoordinateMapping(
    this.start,
    this.end, {
    this.keepOffset,
    this.removeEmpty = false,
    this.remapRubies = true,
  });
  factory _CoordinateMapping.removal(int start, int end) {
    int remap(int offset) => offset <= start
        ? offset
        : offset >= end
        ? offset - (end - start)
        : start;
    return _CoordinateMapping(
      remap,
      remap,
      keepOffset: (offset) => offset < start || offset >= end,
      removeEmpty: true,
    );
  }
  final int Function(int) start;
  final int Function(int) end;
  final bool Function(int)? keepOffset;
  final bool removeEmpty;
  final bool remapRubies;
}

class _DropCap {
  const _DropCap(this.text, this.style, this.lines, this.textCfis);
  final String text;
  final ComputedStyle style;
  final double lines;
  final TextCfiMap? textCfis;
}

class _DropCapResult {
  const _DropCapResult(this.paragraph, this.cap);
  final _ParagraphText paragraph;
  final _DropCap? cap;
}

class _InlineElements {
  final List<PageBlock> floats = [];
  List<InlineBoxSpec> boxes = [];
  final List<PageFootnote> footnotes = [];
}

class _InlineParagraph {
  const _InlineParagraph(
    this.dropped,
    this.elements,
    this.runs,
    this.images,
    this.hasFirstLineText,
  );
  final _DropCapResult dropped;
  final _InlineElements elements;
  final List<StyledRun> runs;
  final List<InlineImageSpec> images;
  final bool hasFirstLineText;
}

class _FootnoteCollector {
  _FootnoteCollector(this.inline, List<PageFootnote> boxNotes)
    : result = List.of(boxNotes);
  final InlineContentBuilder inline;
  final List<PageFootnote> result;
  final Set<int> seen = {};
  void add(
    String tag,
    Map<String, String> attributes,
    String text,
    int start,
    int end,
  ) {
    if (seen.contains(start)) return;
    final note = inline.footnoteForReference(
      tag,
      attributes,
      text,
      start: start,
      end: end,
    );
    if (note == null) return;
    seen.add(start);
    result.add(note);
  }
}

class _MeasuredParagraph {
  const _MeasuredParagraph(
    this.layout,
    this.inline,
    this._footnotes,
    this._rubies,
    this.coordinates,
  );
  final TextLayoutResult layout;
  final _InlineParagraph inline;
  final List<PageFootnote> _footnotes;
  final List<RubyAnnotation> _rubies;
  final ({String? cfi, TextCfiMap? map}) coordinates;
  String? get contentCfi => coordinates.cfi;
  TextCfiMap? get textCfis => coordinates.map;

  List<InlineImageSpec> get images {
    final offsets = layout.inputOffsets;
    if (offsets == null) return inline.images;
    return [
      for (final image in inline.images)
        InlineImageSpec(
          offset: offsets.at(image.offset),
          url: image.url,
          width: image.width,
          height: image.height,
          aspectRatio: image.aspectRatio,
        ),
    ];
  }

  List<PageFootnote> get footnotes {
    final offsets = layout.inputOffsets;
    if (offsets == null) return _footnotes;
    return [
      for (final note in _footnotes)
        PageFootnote(
          start: offsets.at(note.start),
          end: offsets.at(note.end),
          label: note.label,
          kind: note.kind,
          text: note.text,
          imageUrls: note.imageUrls,
        ),
    ];
  }

  List<RubyAnnotation> get rubies {
    final offsets = layout.inputOffsets;
    if (offsets == null) return _rubies;
    return [
      for (final ruby in _rubies)
        RubyAnnotation(
          start: offsets.at(ruby.start),
          end: offsets.at(ruby.end),
          text: ruby.text,
          style: ruby.style,
        ),
    ];
  }
}
