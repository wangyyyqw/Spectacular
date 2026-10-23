import '../position/cfi.dart';
import '../src/api/interfaces.dart';
import '../src/api/models.dart';
import 'document_parser.dart';

/// 默认 display 模式（UA 样式表的最小集合；P2 样式引擎接入后替换）。
enum DisplayMode { block, inline, listItem, table, none }

/// 块级节点。
class BlockNode implements Element {
  /// 创建块节点。
  const BlockNode({
    required this.tag,
    required this.display,
    required this.children,
    required this.cfi,
    required this.attributes,
    required this.start,
    required this.end,
  });

  /// 标签名。
  final String tag;

  /// display 模式。
  final DisplayMode display;

  /// 子节点（块、行内、文本）。
  final List<EpubNode> children;

  /// 解析期绑定的 CFI。
  final EpubCfi cfi;

  /// 属性。
  final Map<String, String> attributes;

  /// 源码起始偏移。
  final int start;

  /// 源码结束偏移。
  final int end;

  /// id 属性。
  String? get id => attributes['id'];
}

/// 行内节点。
class InlineNode implements Element {
  /// 创建行内节点。
  const InlineNode({
    required this.tag,
    required this.children,
    required this.cfi,
    required this.attributes,
    required this.start,
    required this.end,
  });

  /// 标签名。
  final String tag;

  /// 子节点（行内或文本）。
  final List<EpubNode> children;

  /// CFI。
  final EpubCfi cfi;

  /// 属性。
  final Map<String, String> attributes;

  /// 源码起始偏移。
  final int start;

  /// 源码结束偏移。
  final int end;
}

/// 按 display 分派后的章节树。
class BlockDocument implements SpineDocument {
  /// 创建文档。
  BlockDocument({
    required this.spineIndex,
    required this.root,
    required this.source,
  }) : plainText = _collectText(root).join();

  @override
  final int spineIndex;

  @override
  final BlockNode root;

  /// 原始 XHTML。
  final String source;

  @override
  final String plainText;

  @override
  int get charCount => plainText.length;

  static List<String> _collectText(EpubNode node) {
    final buffers = <String>[];
    void walk(EpubNode value) {
      if (value is ParsedText) {
        buffers.add(value.text);
      } else if (value is BlockNode) {
        for (final child in value.children) {
          walk(child);
        }
      } else if (value is InlineNode) {
        for (final child in value.children) {
          walk(child);
        }
      } else if (value is TextBlockNode) {
        buffers.add(value.text);
      }
    }

    walk(node);
    return buffers;
  }
}

/// 按默认 display 构建块节点，并剔除空段落。
abstract final class BlockBuilder {
  static const _blockTags = <String>{
    'body',
    'div',
    'p',
    'section',
    'article',
    'aside',
    'header',
    'footer',
    'main',
    'nav',
    'blockquote',
    'pre',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'dl',
    'dt',
    'dd',
    'figure',
    'figcaption',
    'table',
    'caption',
    'thead',
    'tbody',
    'tfoot',
    'tr',
    'td',
    'th',
    'hr',
    'form',
    'fieldset',
  };

  static const _noDisplayTags = <String>{
    'script',
    'style',
    'head',
    'title',
    'meta',
    'link',
    'base',
    'template',
  };

  /// 构建块树。
  static BlockDocument build(ParsedDocument document) {
    final root =
        _convertElement(document.root, DisplayMode.block)! as BlockNode;
    _removeEmptyParagraphs(root);
    return BlockDocument(
      spineIndex: document.spineIndex,
      root: root,
      source: document.source,
    );
  }

  /// 默认 display。
  static DisplayMode displayFor(String tag) {
    if (_noDisplayTags.contains(tag)) {
      return DisplayMode.none;
    }
    if (tag == 'li') {
      return DisplayMode.listItem;
    }
    if (tag == 'table') {
      return DisplayMode.table;
    }
    if (_blockTags.contains(tag)) {
      return DisplayMode.block;
    }
    return DisplayMode.inline;
  }

  static EpubNode? _convertElement(ParsedElement element, DisplayMode mode) {
    if (mode == DisplayMode.none) {
      return null;
    }
    if (mode == DisplayMode.inline) {
      final children = <EpubNode>[];
      for (final child in element.children) {
        final converted = _convertChild(child, DisplayMode.inline);
        if (converted != null) {
          children.add(converted);
        }
      }
      return InlineNode(
        tag: element.tag,
        children: List<EpubNode>.unmodifiable(children),
        cfi: element.cfi,
        attributes: element.attributes,
        start: element.start,
        end: element.end,
      );
    }

    final children = <EpubNode>[];
    for (final child in element.children) {
      final converted = _convertChild(child, mode);
      if (converted != null) {
        children.add(converted);
      }
    }
    return BlockNode(
      tag: element.tag,
      display: mode,
      children: children,
      cfi: element.cfi,
      attributes: element.attributes,
      start: element.start,
      end: element.end,
    );
  }

  static EpubNode? _convertChild(ParsedNode child, DisplayMode parentMode) {
    if (child is ParsedText) {
      return child;
    }
    if (child is! ParsedElement) {
      return null;
    }
    final mode = displayFor(child.tag);
    if (mode == DisplayMode.none) {
      return null;
    }
    return _convertElement(child, mode);
  }

  static void _removeEmptyParagraphs(BlockNode node) {
    final kept = <EpubNode>[];
    for (final child in node.children) {
      if (child is BlockNode) {
        _removeEmptyParagraphs(child);
        if (_isEmptyParagraph(child)) {
          continue;
        }
      }
      kept.add(child);
    }
    if (!identical(kept, node.children)) {
      node.children
        ..clear()
        ..addAll(kept);
    }
  }

  static bool _isEmptyParagraph(BlockNode node) {
    if (node.tag != 'p') {
      return false;
    }
    for (final child in node.children) {
      if (child is ParsedText && child.text.trim().isNotEmpty) {
        return false;
      }
      if (child is BlockNode || child is InlineNode) {
        return false;
      }
    }
    return true;
  }
}
