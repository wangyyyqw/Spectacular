import '../parser/block_builder.dart';
import '../parser/text_aggregator.dart';
import '../position/text_cfi_map.dart';
import '../src/api/models.dart';
import 'text_offsets.dart';

/// 阅读显示方式；原文始终保留，定位与业务存储不使用转换后的字面值。
enum ReaderChineseMode {
  original,
  simplified,
  traditional;

  static ReaderChineseMode fromId(String? id) =>
      values.firstWhere((value) => value.name == id, orElse: () => original);
}

typedef ConvertedReaderText = ({String text, TextOffsetMap? offsets});

/// 宿主提供纯数据可传递的转换函数，核心不依赖具体语言或原生库。
class ReaderTextConversion {
  const ReaderTextConversion({required this.id, required this.convert});

  final String id;
  final ConvertedReaderText Function(String text) convert;

  BlockDocument apply(BlockDocument document) => BlockDocument(
    spineIndex: document.spineIndex,
    root: _node(document.root) as BlockNode,
    source: document.source,
  );

  EpubNode _node(EpubNode node) {
    if (node is TextContentNode) return _text(node);
    if (node is! BlockNode) return node;
    if (const {'code', 'pre', 'script', 'style'}.contains(node.tag)) {
      return node;
    }
    final block = BlockNode(
      tag: node.tag,
      display: node.display,
      children: [for (final child in node.children) _node(child)],
      cfi: node.cfi,
      attributes: node.attributes,
      start: node.start,
      end: node.end,
      containerChain: node.containerChain,
    );
    return node is PromotedBlockNode
        ? PromotedBlockNode(block, node.inlineAncestors)
        : block;
  }

  TextContentNode _text(TextContentNode node) {
    final result = convert(node.text);
    final offsets = result.offsets;
    int at(int offset) => offsets?.at(offset) ?? offset;
    return TextContentNode(
      text: result.text,
      runs: [
        for (final run in node.runs)
          TextRun(start: at(run.start), end: at(run.end)),
      ],
      hardBreaks: [for (final offset in node.hardBreaks) at(offset)],
      leadingBreakCount: node.leadingBreakCount,
      cfi: node.cfi,
      start: node.start,
      end: node.end,
      textCfis: (node.textCfis ?? TextCfiMap.linear(node.cfi, node.text.length))
          .transformed(offsets),
      inlineMarks: [
        for (final mark in node.inlineMarks)
          InlineMark(
            start: at(mark.start),
            end: at(mark.end),
            tag: mark.tag,
            classes: mark.classes,
            chain: mark.chain,
          ),
      ],
      rubies: [
        for (final ruby in node.rubies)
          RubyMark(
            start: at(ruby.start),
            end: at(ruby.end),
            text: convert(ruby.text).text,
            chain: ruby.chain,
          ),
      ],
      inlineImages: [
        for (final image in node.inlineImages)
          InlineImageMark(offset: at(image.offset), node: image.node),
      ],
    );
  }
}
