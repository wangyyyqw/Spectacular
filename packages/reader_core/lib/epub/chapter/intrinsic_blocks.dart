import 'dart:math' as math;

import 'package:reader_core/api.dart' show EpubNode, TextBlockNode;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/intrinsic_widths.dart';
import 'package:reader_core/parser/block_builder.dart';

import 'chapter_flow.dart';
import 'chapter_selectors.dart';
import 'chapter_style_resolver.dart';
import 'chapter_text_measurer.dart';
import 'container_blocks.dart';
import 'generated_chapter_content.dart';
import 'text_block_builder.dart';

typedef _PredictionState = ({
  GeneratedChapterContent generation,
  ListContext? list,
});

/// 仅预测普通横排容器的内容占宽；不构块、不分页、不修改正式计数器。
class ChapterIntrinsicMeasurer {
  ChapterIntrinsicMeasurer(this.styles, this.text, this.content);

  final ChapterStyleResolver styles;
  final TextBlockBuilder text;
  final GeneratedChapterContent content;
  ChapterTextMeasurer get measure => text.measure;

  Future<IntrinsicWidths> contentWidths(
    BlockNode node,
    List<SelectorElement> chain,
    double availableWidth, {
    ListContext? list,
  }) => _children(node, chain, availableWidth, (
    generation: content.measurementSnapshot(),
    list: list?.measurementSnapshot(),
  ));

  Future<IntrinsicWidths> _children(
    BlockNode node,
    List<SelectorElement> chain,
    double availableWidth,
    _PredictionState state,
  ) async {
    var widths = IntrinsicWidths.zero;
    final style = styles.chainStyle(chain);
    final childList = _childList(node, style, state.list);
    final childState = (generation: state.generation, list: childList);
    final anonymous = retainsContainer(node, style);
    for (final child in node.children) {
      await measure.budget.checkpoint();
      final context = child is TextBlockNode && anonymous
          ? [...chain, const ChapterNodeView('reader-anonymous', {}, [])]
          : chain;
      widths = widths.includeBlock(
        await _nodeWidths(child, context, availableWidth, childState),
      );
    }
    return widths;
  }

  Future<IntrinsicWidths> _nodeWidths(
    EpubNode node,
    List<SelectorElement> ancestors,
    double availableWidth,
    _PredictionState state,
  ) async {
    await measure.budget.checkpoint();
    if (node is TextBlockNode) {
      return text.measureIntrinsicContent(
        node,
        BlockPosition(ancestors: ancestors, list: state.list),
        state.generation,
      );
    }
    if (node is! BlockNode) return IntrinsicWidths.zero;
    final chain = [...ancestors, styles.selectorViewOf(node)];
    final style = styles.chainStyle(chain);
    if (style.display == CssDisplay.none || style.isOutOfFlow) {
      return IntrinsicWidths.zero;
    }
    final model = BoxModel.fromStyle(style, containingWidth: availableWidth);
    if (!ChapterTextMeasurer.isOrdinaryHorizontalBlock(style) ||
        const {'img', 'image', 'object', 'table'}.contains(node.tag)) {
      // 特殊格式与替换元素沿用已有可用宽，不宣称完整内在尺寸算法。
      final width =
          model.resolveContentWidth(availableWidth) +
          model.horizontalInset +
          model.margin.horizontal;
      return IntrinsicWidths(minContent: width, maxContent: width);
    }
    final widths = await _children(node, chain, availableWidth, state);
    return _outerWidths(model, style, widths);
  }

  static ListContext? _childList(
    BlockNode node,
    ComputedStyle style,
    ListContext? parent,
  ) {
    if (node.tag == 'li' && parent != null) parent.markerPending = true;
    if (node.tag != 'ul' && node.tag != 'ol') return parent;
    return ListContext(
      node.tag,
      (parent?.depth ?? -1) + 1,
      inside: style.listStylePosition == CssListStylePosition.inside,
    );
  }

  static IntrinsicWidths _outerWidths(
    BoxModel model,
    ComputedStyle style,
    IntrinsicWidths content,
  ) {
    final inset =
        model.horizontalInset +
        (style.marginLeftIsAuto ? 0 : model.margin.left) +
        (style.marginRightIsAuto ? 0 : model.margin.right);
    double contribution(double available) => math.max(
      0,
      inset +
          model.resolveContentWidth(
            available + inset,
            intrinsicWidths: content,
          ),
    );
    return IntrinsicWidths(
      minContent: contribution(content.minContent),
      maxContent: contribution(content.maxContent),
    );
  }
}
