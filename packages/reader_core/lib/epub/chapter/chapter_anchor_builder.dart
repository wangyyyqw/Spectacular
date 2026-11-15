import 'package:reader_core/api.dart' show EpubNode, TextBlockNode;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';

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

/// 聚合前应用作者 display 和空白规则，所有后续坐标均以聚合原文为准。
BlockDocument aggregateAnchorDocument(
  BlockDocument display,
  ChapterRawStyles styles,
) => TextAggregator.aggregate(
  display,
  inlineDisplay: (node, _) =>
      switch (styles.styleOf(node).values['display']?.trim().toLowerCase()) {
        'block' => CssDisplay.block,
        'none' => CssDisplay.none,
        'inline-block' => CssDisplay.inlineBlock,
        _ => CssDisplay.inline,
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
    final style = node is TextContentNode ? parent : styles.styleOf(node);
    if (style.display == CssDisplay.none ||
        style.visibility != CssVisibility.visible) {
      return;
    }
    if (node is TextContentNode) {
      _appendText(node);
    } else if (node is BlockNode) {
      _recordElementPath(node.cfi, _offset);
      if (const {'td', 'th', 'caption'}.contains(node.tag)) {
        final text = _cellText(node);
        if (text.isNotEmpty) {
          _appendBlock(node.cfi, text);
        }
      } else {
        final imageCfi =
            const {'img', 'image', 'svg', 'object'}.contains(node.tag)
            ? styles.selectors.imageCfiOf(node)
            : null;
        if (imageCfi != null) {
          _recordElementPath(EpubCfi.parse(imageCfi)!, _offset);
        }
        for (final child in node.children) {
          walk(child, style);
        }
      }
    } else if (node is InlineNode) {
      _recordElementPath(node.cfi, _offset);
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
    if (hasText) _appendBlock(node.cfi, node.text);
  }

  void _appendBlock(EpubCfi cfi, String text) {
    blocks.add(AnchorBlock(cfi: cfi.serialize(), text: text));
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

  String _cellText(EpubNode root) {
    final parts = <String>[];
    void walk(EpubNode node) {
      if (node is TextBlockNode && node.text.trim().isNotEmpty) {
        final emptyBox =
            node is TextContentNode &&
            node.inlineMarks.any((mark) => mark.start == mark.end);
        parts.add(emptyBox ? node.text : node.text.trim());
      } else if (node is BlockNode) {
        node.children.forEach(walk);
      } else if (node is InlineNode) {
        node.children.forEach(walk);
      }
    }

    walk(root);
    return parts.join('\n');
  }
}
