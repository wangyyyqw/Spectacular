import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';

import 'chapter_selectors.dart';
import 'chapter_style_resolver.dart';
import 'generated_chapter_content.dart';
import 'generated_content.dart';
import 'inline_content_builder.dart';

/// 块伪元素和 Flex 生成子项复用正式级联、content 求值及文字测量。
class GeneratedBlockBuilder {
  GeneratedBlockBuilder(this.styles, this.inline, this.content);

  final ChapterStyleResolver styles;
  final InlineContentBuilder inline;
  final GeneratedChapterContent content;

  Set<String> blockPseudosFor(
    List<SelectorElement> chain,
    ComputedStyle parent,
  ) => {
    for (final pseudo in const ['::before', '::after'])
      if (_isBlockPseudo(chain, parent, pseudo)) pseudo,
  };

  bool _isBlockPseudo(
    List<SelectorElement> chain,
    ComputedStyle parent,
    String pseudo,
  ) {
    final raw = content
        .winningPseudoDeclarations(chain, pseudo)['content']
        ?.value
        .trim();
    if (raw == null || raw == 'none' || raw == 'normal') return false;
    final style = styles.pseudoStyleFor(chain, parent, pseudo);
    if (style.display == CssDisplay.none || style.isOutOfFlow) return false;
    return parent.display == CssDisplay.flex ||
        (style.explicitProperties.contains('display') &&
            const {
              CssDisplay.block,
              CssDisplay.flex,
              CssDisplay.listItem,
            }.contains(style.display));
  }

  Future<PageBlock?> build(
    List<SelectorElement> chain,
    String pseudo, {
    int groupId = 0,
  }) async {
    await inline.measure.budget.checkpoint();
    final style = styles.pseudoStyleFor(
      chain,
      styles.chainStyle(chain),
      pseudo,
    );
    final value = content.pseudoContentOf(
      chain,
      pseudo,
      quotes: style.quotes,
      quoteDepth:
          chain.where((view) => view.tag == 'q').length -
          (chain.last.tag == 'q' ? 1 : 0),
    );
    if (value == null) return null;
    final view = ChapterNodeView('reader-generated', const {}, const []);
    styles.promotedInlineStyles[view] = style;
    final generatedChain = [...chain, view];
    final projected = styles.styleForChain(generatedChain);
    final width = styles.snapshot.width;
    if (value.text.isEmpty) {
      return inline.measure.emptyBoxBlock(
        projected,
        width,
        containingHeight: styles.snapshot.pageHeight,
      );
    }
    return _textBlock(value, projected, generatedChain, groupId);
  }

  Future<PageBlock> _textBlock(
    PseudoContent value,
    ComputedStyle style,
    List<SelectorElement> chain,
    int groupId,
  ) async {
    final boxes = await _imageBoxes(value, style, chain);
    final layout = await inline.measure.layout(
      text: value.text,
      style: style,
      maxWidth: inline.measure.textWidthFor(style),
      inlineBoxes: boxes,
    );
    return PageBlock.styled(
      layout: layout,
      style: style,
      containingWidth: styles.snapshot.width,
      textRuleEligible: false,
      groupId: groupId,
      effectiveOpacity: style.effectiveOpacity,
    );
  }

  Future<List<InlineBoxSpec>> _imageBoxes(
    PseudoContent value,
    ComputedStyle style,
    List<SelectorElement> chain,
  ) async {
    final boxes = <InlineBoxSpec>[];
    // 伪元素盒已经消费外边距；其内容图片不能再次消费页面投影内缩。
    final imageStyle = style.withMargins(CssEdges.zero);
    for (final image in value.images) {
      await inline.measure.budget.checkpoint();
      boxes.add(
        inline.inlineImageBox(
          InlineImageSpec(
            offset: image.offset,
            url: image.url,
            width: style.width?.resolve(styles.snapshot.width),
            height: style.height?.resolve(styles.snapshot.width),
            aspectRatio: style.aspectRatio,
          ),
          imageStyle,
          chain,
          inline.measure.textWidthFor(style),
        ),
      );
    }
    return boxes;
  }
}
