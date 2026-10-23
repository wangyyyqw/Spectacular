import '../position/cfi.dart';
import '../src/api/models.dart';
import 'block_builder.dart';
import 'document_parser.dart';

/// 一个样式区间（P1-16 只记录范围，样式由后续样式层填充）。
class TextRun {
  /// 创建区间。
  const TextRun({required this.start, required this.end});

  /// 起始偏移（UTF-16）。
  final int start;

  /// 结束偏移（半开）。
  final int end;
}

/// 聚合后的文本块。
class TextContentNode implements TextBlockNode {
  /// 创建文本块。
  const TextContentNode({
    required this.text,
    required this.runs,
    required this.hardBreaks,
    required this.cfi,
    required this.start,
    required this.end,
  });

  @override
  final String text;

  /// 样式区间。
  final List<TextRun> runs;

  /// 强制换行位置（`<br>` 产生的 `\n` 在 text 中的下标）。
  final List<int> hardBreaks;

  /// 文本块 CFI（取首个来源文本节点的 CFI）。
  final EpubCfi cfi;

  /// 源码起始偏移。
  final int start;

  /// 源码结束偏移。
  final int end;
}

/// 把块树中的行内内容聚合为可测量文本。
abstract final class TextAggregator {
  /// 聚合一个章节。
  static BlockDocument aggregate(BlockDocument document) {
    final root = _aggregateBlock(
      document.root,
      preserve: document.root.tag == 'pre',
    );
    return BlockDocument(
      spineIndex: document.spineIndex,
      root: root,
      source: document.source,
    );
  }

  static BlockNode _aggregateBlock(BlockNode block, {required bool preserve}) {
    final accumulator = _TextAccumulator(
      preserve: preserve,
      fallbackCfi: block.cfi,
      fallbackStart: block.start,
      fallbackEnd: block.end,
    );
    final children = <EpubNode>[];

    void flush() {
      final content = accumulator.take();
      if (content != null) {
        children.add(content);
      }
    }

    void visitInline(InlineNode node) {
      if (node.tag == 'br') {
        accumulator.addBreak();
        return;
      }
      if (node.tag == 'img' || node.tag == 'image') {
        accumulator.addPlaceholder();
        return;
      }
      for (final child in node.children) {
        if (child is ParsedText) {
          accumulator.addText(child);
        } else if (child is InlineNode) {
          visitInline(child);
        } else if (child is TextBlockNode) {
          accumulator.addRawText(child.text);
        }
      }
    }

    for (final child in block.children) {
      if (child is BlockNode) {
        flush();
        children.add(
          _aggregateBlock(child, preserve: preserve || child.tag == 'pre'),
        );
      } else if (child is InlineNode) {
        visitInline(child);
      } else if (child is ParsedText) {
        accumulator.addText(child);
      } else if (child is TextBlockNode) {
        accumulator.addRawText(child.text);
      }
    }
    flush();

    return BlockNode(
      tag: block.tag,
      display: block.display,
      children: children,
      cfi: block.cfi,
      attributes: block.attributes,
      start: block.start,
      end: block.end,
    );
  }
}

class _TextAccumulator {
  _TextAccumulator({
    required this.preserve,
    required this.fallbackCfi,
    required this.fallbackStart,
    required this.fallbackEnd,
  });

  final bool preserve;
  final EpubCfi fallbackCfi;
  final int fallbackStart;
  final int fallbackEnd;
  final StringBuffer _buffer = StringBuffer();
  final List<TextRun> _runs = <TextRun>[];
  final List<int> _hardBreaks = <int>[];
  bool _pendingSpace = false;
  int? _lastCodeUnit;
  ParsedText? _firstText;
  ParsedText? _lastText;

  void addText(ParsedText node) {
    final value = node.text;
    if (value.isEmpty) {
      return;
    }
    _firstText ??= node;
    _lastText = node;
    final runStart = _buffer.length;
    var emitted = 0;
    for (final char in value.split('')) {
      if (!preserve && _isCollapsibleWhitespace(char)) {
        _pendingSpace = true;
        continue;
      }
      if (!preserve && _pendingSpace) {
        if (_buffer.isNotEmpty && _lastCodeUnit != 10) {
          _buffer.write(' ');
          _lastCodeUnit = 32;
          emitted += 1;
        }
        _pendingSpace = false;
      }
      _buffer.write(char);
      _lastCodeUnit = char.codeUnitAt(0);
      emitted += 1;
    }
    if (emitted > 0) {
      _runs.add(TextRun(start: runStart, end: _buffer.length));
    }
  }

  void addRawText(String value) {
    if (value.isEmpty) {
      return;
    }
    _buffer.write(value);
    _runs.add(
      TextRun(start: _buffer.length - value.length, end: _buffer.length),
    );
  }

  void addBreak() {
    _pendingSpace = false;
    if (_buffer.isNotEmpty) {
      _buffer.write('\n');
      _lastCodeUnit = 10;
      _hardBreaks.add(_buffer.length - 1);
    }
  }

  void addPlaceholder() {
    _pendingSpace = false;
    _buffer.write('\uFFFC');
    _lastCodeUnit = 0xFFFC;
    _runs.add(TextRun(start: _buffer.length - 1, end: _buffer.length));
  }

  TextContentNode? take() {
    if (_buffer.isEmpty) {
      return null;
    }
    final text = _buffer.toString();
    final content = TextContentNode(
      text: text,
      runs: List<TextRun>.unmodifiable(_runs),
      hardBreaks: List<int>.unmodifiable(_hardBreaks),
      cfi: _firstText?.cfi ?? fallbackCfi,
      start: _firstText?.start ?? fallbackStart,
      end: _lastText?.end ?? fallbackEnd,
    );
    _buffer.clear();
    _runs.clear();
    _hardBreaks.clear();
    _firstText = null;
    _lastText = null;
    return content;
  }

  static bool _isCollapsibleWhitespace(String char) =>
      char == ' ' ||
      char == '\t' ||
      char == '\n' ||
      char == '\r' ||
      char == '\f';
}
