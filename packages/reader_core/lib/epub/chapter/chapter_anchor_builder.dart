import 'package:reader_core/api.dart' show EpubNode, TextBlockNode;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/position/text_cfi_map.dart';

import 'chapter_raw_styles.dart';

const _definitionContainers = {
  'article',
  'aside',
  'blockquote',
  'dd',
  'div',
  'dl',
  'dt',
  'figcaption',
  'figure',
  'li',
  'ol',
  'p',
  'section',
  'td',
  'th',
  'ul',
};

/// 构造原文块树时隐藏注释定义；不生成页面、不改变原始 CFI。
BlockDocument buildAnchorDisplayDocument(
  ParsedDocument parsed,
  Map<String, FootnoteAnchor> references,
  ChapterRawStyles styles,
) {
  final hiddenIds = <String>{};
  for (final anchor in references.values) {
    if (anchor.kind == NoteKind.link ||
        anchor.targetSpine != parsed.spineIndex) {
      continue;
    }
    for (final id in [anchor.targetId, anchor.definitionId]) {
      if (id != null && id.isNotEmpty) hiddenIds.add(id);
    }
  }
  final visibility = _FootnoteVisibility(hiddenIds)..walk(parsed.root);
  return BlockBuilder.build(
    parsed,
    // 空段落仍可通过作者级联承担 clear，必须保留到浮动布局完成。
    preserveEmptyParagraph: (node) => styles.styleOf(node).clear != CssClear.none,
    skipElement: (element) =>
        visibility.hidden.contains(element) ||
        FootnoteParser.isDefinitionElement(element.tag, element.attributes),
  );
}

class _FootnoteVisibility {
  _FootnoteVisibility(this.hiddenIds);
  final Set<String> hiddenIds;
  final Set<ParsedElement> hidden = {};
  final List<ParsedElement> ancestors = [];

  bool walk(ParsedElement element) {
    if (FootnoteParser.isDefinitionElement(element.tag, element.attributes)) {
      hidden.add(element);
      return false;
    }
    var hasBacklink = false;
    ancestors.add(element);
    for (final child in element.children.whereType<ParsedElement>()) {
      hasBacklink = walk(child) || hasBacklink;
    }
    ancestors.removeLast();
    final backlink = FootnoteParser.isBacklink(element.tag, element.attributes);
    final definition =
        hasBacklink && _definitionContainers.contains(element.tag);
    if (hiddenIds.contains(element.id) || definition) {
      hidden.add(_ownerOf(element));
      // 定义已归属到当前块，返回链接不再传播到承载正文的外层容器。
      return false;
    }
    return backlink || hasBacklink;
  }

  ParsedElement _ownerOf(ParsedElement element) {
    if (_definitionContainers.contains(element.tag)) return element;
    for (final parent in ancestors.reversed) {
      if (_definitionContainers.contains(parent.tag)) return parent;
    }
    return element;
  }
}

/// 聚合前应用作者 display、定位块化和空白规则，后续坐标均以聚合原文为准。
BlockDocument aggregateAnchorDocument(
  BlockDocument display,
  ChapterRawStyles styles,
) => TextAggregator.aggregate(
  display,
  inlineDisplay: (node, _) {
    final style = styles.styleOf(node);
    // 绝对/固定定位会块化行内盒，必须在聚合拆分块级后代前保留完整父盒。
    if (style.isOutOfFlow && style.display != CssDisplay.none) {
      return CssDisplay.block;
    }
    return switch (style.values['display']?.trim().toLowerCase()) {
      'block' => CssDisplay.block,
      'none' => CssDisplay.none,
      'inline-block' => CssDisplay.inlineBlock,
      _ => CssDisplay.inline,
    };
  },
  whiteSpaceFor: (node, _) => styles.styleOf(node).whiteSpace,
);

({List<AnchorBlock> blocks, Map<String, int> elementOffsets})
collectChapterAnchors(
  BlockDocument document,
  ChapterRawStyles styles,
  ParsedDocument parsed,
) {
  final collector = _AnchorBlocks(styles, parsed);
  collector.walk(document.root, styles.baseStyle);
  return (
    blocks: List.unmodifiable(collector.blocks),
    elementOffsets: Map.unmodifiable(collector.elementOffsets),
  );
}

class _AnchorBlocks {
  _AnchorBlocks(this.styles, this.parsed);
  final ChapterRawStyles styles;
  final ParsedDocument parsed;
  final List<AnchorBlock> blocks = [];
  final Map<String, int> elementOffsets = {};
  int _offset = 0;

  void walk(EpubNode node, ComputedStyle parent) {
    if (node is TextContentNode) {
      if (parent.visibility == CssVisibility.visible) _appendText(node);
      return;
    }
    final style = styles.styleOf(node);
    if (style.display == CssDisplay.none) return;
    final visible = style.visibility == CssVisibility.visible;
    if (node is BlockNode) {
      if (visible) _recordElementPath(node.cfi, _offset);
      if (visible && const {'td', 'th', 'caption'}.contains(node.tag)) {
        final text = _cellText(node);
        if (text.text.isNotEmpty) {
          _appendBlock(node.cfi, text.text, text.textCfis);
        }
        return;
      }
      if (visible && const {'img', 'image', 'svg', 'object'}.contains(node.tag)) {
        final imageCfi = styles.selectors.imageCfiOf(node);
        if (imageCfi != null) {
          _recordElementPath(EpubCfi.parse(imageCfi)!, _offset);
        }
      }
      for (final child in node.children) {
        walk(child, style);
      }
    } else if (node is InlineNode) {
      if (visible) _recordElementPath(node.cfi, _offset);
      for (final child in node.children) {
        walk(child, style);
      }
    }
  }

  void _appendText(TextContentNode node) {
    final onlyImages =
        node.text.replaceAll('\uFFFC', '').trim().isEmpty &&
        node.inlineMarks.any(
          (mark) => const {'img', 'image', 'svg', 'object'}.contains(mark.tag),
        );
    final hasText = !onlyImages && node.text.trim().isNotEmpty;
    _recordElementPath(node.cfi, _offset);
    for (final image in node.inlineImages) {
      _recordElementPath(
        image.node.cfi,
        _offset + (hasText ? image.offset : 0),
      );
    }
    for (final mark in node.inlineMarks) {
      final id = mark.chain.lastOrNull?.attributes['id'];
      final element = id == null ? null : parsed.elementById(id);
      if (element != null && styles.isVisibleElement(element)) {
        _recordElementPath(element.cfi, _offset + (hasText ? mark.start : 0));
      }
    }
    if (hasText) {
      blocks.add(
        AnchorBlock(
          cfi: node.textCfis?.cfiAt(0) ?? node.cfi.serialize(),
          text: node.text,
          textCfis: node.textCfis,
        ),
      );
      _offset += node.text.length;
    }
  }

  void _appendBlock(EpubCfi cfi, String text, TextCfiMap textCfis) {
    blocks.add(
      AnchorBlock(cfi: cfi.serialize(), text: text, textCfis: textCfis),
    );
    for (final run in textCfis.runs) {
      _recordElementPath(run.cfi, _offset + run.start);
    }
    _offset += text.length;
  }

  /// 聚合可能折叠图片外框或提升行内块，原路径上的容器仍指向首个可见内容。
  void _recordElementPath(EpubCfi cfi, int offset) {
    final segment = cfi.segments.last;
    for (var length = 1; length <= segment.steps.length; length++) {
      if (segment.steps[length - 1].index.isOdd) break;
      final key = EpubCfi([
        ...cfi.segments.take(cfi.segments.length - 1),
        CfiSegment(segment.steps.take(length).toList()),
      ]).serialize();
      elementOffsets.update(
        key,
        (previous) => previous < offset ? previous : offset,
        ifAbsent: () => offset,
      );
    }
  }

  ({String text, TextCfiMap textCfis}) _cellText(EpubNode root) {
    final parts = <String>[];
    final coordinates = TextCfiMapBuilder();
    var offset = 0;
    void walk(EpubNode node) {
      if (node is TextBlockNode && node.text.trim().isNotEmpty) {
        final emptyBox =
            node is TextContentNode &&
            node.inlineMarks.any((mark) => mark.start == mark.end);
        final text = emptyBox ? node.text : node.text.trim();
        if (parts.isNotEmpty) offset += 1;
        if (node is TextContentNode) {
          final leading = emptyBox
              ? 0
              : node.text.length - node.text.trimLeft().length;
          coordinates.addMap(
            (node.textCfis ?? TextCfiMap.linear(node.cfi, node.text.length))
                .slice(leading, leading + text.length),
            offset: offset,
          );
        }
        parts.add(text);
        offset += text.length;
      } else if (node is BlockNode) {
        node.children.forEach(walk);
      } else if (node is InlineNode) {
        node.children.forEach(walk);
      }
    }

    walk(root);
    return (text: parts.join('\n'), textCfis: coordinates.build(offset));
  }
}
