import '../css/computed_style.dart';
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

/// 一个行内样式标记（真实书适配）：聚合文本中的区间 + 来源元素结构
/// （标签与 class）。样式解析由消费方（章节源）按作者 CSS 完成——
/// 聚合器只记结构，不依赖 CSS 层。
class InlineMark {
  /// 创建标记。
  const InlineMark({
    required this.start,
    required this.end,
    required this.tag,
    required this.classes,
  });

  /// 起始偏移（UTF-16，聚合文本坐标系，含）。
  final int start;

  /// 结束偏移（半开）。
  final int end;

  /// 来源元素标签（span/b/strong…）。
  final String tag;

  /// class 列表（文档顺序）。
  final List<String> classes;
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
    this.inlineMarks = const <InlineMark>[],
  });

  @override
  final String text;

  /// 样式区间。
  final List<TextRun> runs;

  /// 强制换行位置（`<br>` 与保留的换行符在 text 中的下标）。
  final List<int> hardBreaks;

  /// 行内样式标记（真实书适配）。
  final List<InlineMark> inlineMarks;

  /// 文本块 CFI（取首个来源文本节点的 CFI）。
  final EpubCfi cfi;

  /// 源码起始偏移。
  final int start;

  /// 源码结束偏移。
  final int end;
}

/// `white-space` 在聚合阶段的行为（§65、CSS Text 3）。
class _WhiteSpaceMode {
  const _WhiteSpaceMode({
    required this.collapseSpaces,
    required this.keepNewlines,
  });

  /// 是否把连续空白折叠成一个空格。
  final bool collapseSpaces;

  /// 是否保留换行符（并记为强制换行）。
  final bool keepNewlines;

  static const normal = _WhiteSpaceMode(
    collapseSpaces: true,
    keepNewlines: false,
  );
  static const nowrap = _WhiteSpaceMode(
    collapseSpaces: true,
    keepNewlines: false,
  );
  static const pre = _WhiteSpaceMode(collapseSpaces: false, keepNewlines: true);
  static const preWrap = _WhiteSpaceMode(
    collapseSpaces: false,
    keepNewlines: true,
  );
  static const preLine = _WhiteSpaceMode(
    collapseSpaces: true,
    keepNewlines: true,
  );

  static _WhiteSpaceMode from(CssWhiteSpace whiteSpace) => switch (whiteSpace) {
    CssWhiteSpace.normal => normal,
    CssWhiteSpace.nowrap => nowrap,
    CssWhiteSpace.pre => pre,
    CssWhiteSpace.preWrap => preWrap,
    CssWhiteSpace.preLine => preLine,
  };
}

/// 把块树中的行内内容聚合为可测量文本。
abstract final class TextAggregator {
  /// 记录样式标记的标签（真实书适配）：这些标签的行内元素即使无 class
  /// 也产标记（UA 语义样式：粗斜体/上下标/删除线等）。
  static const _styleMarkTags = <String>{
    'b', 'strong', 'em', 'i', 'u', 's', 'strike', 'del', 'ins',
    'code', 'sub', 'sup', 'small', 'big', 'mark', 'font', 'cite', 'q',
  };
  /// 聚合一个章节。
  ///
  /// [whiteSpace] 决定空白与换行如何保留；`<pre>` 标签始终按 `pre` 处理。
  static BlockDocument aggregate(
    BlockDocument document, {
    CssWhiteSpace whiteSpace = CssWhiteSpace.normal,
  }) {
    final root = _aggregateBlock(
      document.root,
      mode: _WhiteSpaceMode.from(whiteSpace),
    );
    return BlockDocument(
      spineIndex: document.spineIndex,
      root: root,
      source: document.source,
    );
  }

  static BlockNode _aggregateBlock(
    BlockNode block, {
    required _WhiteSpaceMode mode,
  }) {
    // `<pre>` 标签自带 `white-space: pre` 的 UA 语义。
    final effective = block.tag == 'pre' ? _WhiteSpaceMode.pre : mode;
    final accumulator = _TextAccumulator(
      mode: effective,
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
      // 行内样式标记（真实书适配）：带 class 的元素与已知样式标签记录
      // 区间，样式解析由章节源按作者 CSS 完成。
      final markable =
          node.attributes.containsKey('class') ||
          _styleMarkTags.contains(node.tag);
      final markStart = markable ? accumulator.openMark() : -1;
      if (node.tag == 'img' || node.tag == 'image') {
        accumulator.addImage(node);
      } else {
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
      if (markable) {
        accumulator.closeMark(markStart, node);
      }
    }

    for (final child in block.children) {
      if (child is BlockNode) {
        flush();
        children.add(_aggregateBlock(child, mode: effective));
      } else if (child is InlineNode) {
        visitInline(child);
      } else if (child is ParsedText) {
        accumulator.addText(child);
      } else if (child is TextBlockNode) {
        accumulator.addRawText(child.text);
      }
    }
    // 折叠判定必须在 flush（take 会清空缓冲）之前做，否则缓冲已空、
    // 残留文本被误判为「只含图片占位」。
    final imageOnly = accumulator.images.length == 1 && accumulator.hasOnlyImages;
    flush();

    // 纯图块折叠（真实书适配）：块内唯一实质内容是一个 img/image（无
    // 其他文本、无强制换行）时，丢弃占位文本、保留图片属性（src/width/
    // height/class），产出 tag='img' 的块节点供章节源构造图片块。
    if (imageOnly) {
      final image = accumulator.images.single;
      return BlockNode(
        tag: 'img',
        display: DisplayMode.block,
        children: const <EpubNode>[],
        cfi: block.cfi,
        attributes: image.attributes,
        start: block.start,
        end: block.end,
      );
    }
    // 外层容器折叠：聚合后子节点恰好是一个已折叠的 img 块（div>div>img）；
    // 有任何文本内容时 children 会多于 1 个，不会误折叠。
    if (children.length == 1 && children.single is BlockNode) {
      final only = children.single as BlockNode;
      if (only.tag == 'img' && only.children.isEmpty) {
        return BlockNode(
          tag: 'img',
          display: DisplayMode.block,
          children: const <EpubNode>[],
          cfi: block.cfi,
          attributes: only.attributes,
          start: block.start,
          end: block.end,
        );
      }
    }

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
    required this.mode,
    required this.fallbackCfi,
    required this.fallbackStart,
    required this.fallbackEnd,
  });

  final _WhiteSpaceMode mode;
  final EpubCfi fallbackCfi;
  final int fallbackStart;
  final int fallbackEnd;
  final StringBuffer _buffer = StringBuffer();
  final List<TextRun> _runs = <TextRun>[];
  final List<int> _hardBreaks = <int>[];

  /// 块内遇到的图片行内节点（`<img>`/`<image>`），供纯图块折叠判定。
  final List<InlineNode> images = <InlineNode>[];

  /// 行内样式标记（真实书适配）：visitInline 按 open/close 记录。
  final List<InlineMark> marks = <InlineMark>[];
  bool _pendingSpace = false;
  int? _lastCodeUnit;
  ParsedText? _firstText;
  ParsedText? _lastText;

  /// 开一个样式标记：先把挂起空格落盘（与文本 run 坐标一致），返回
  /// 缓冲当前位置。
  int openMark() {
    _flushPendingSpace();
    return _buffer.length;
  }

  /// 关一个样式标记；区间为空（无文本）时丢弃。
  void closeMark(int start, InlineNode node) {
    final end = _buffer.length;
    if (end <= start) {
      return;
    }
    marks.add(
      InlineMark(
        start: start,
        end: end,
        tag: node.tag,
        classes: (node.attributes['class'] ?? '')
            .split(RegExp(r'\s+'))
            .where((c) => c.isNotEmpty)
            .toList(growable: false),
      ),
    );
  }

  /// 缓冲是否只含图片占位（\uFFFC 与空白），无任何真实文本与换行。
  bool get hasOnlyImages {
    if (images.isEmpty) {
      return false;
    }
    for (final char in _buffer.toString().split('')) {
      if (char != '\uFFFC' && !_isCollapsibleWhitespace(char)) {
        return false;
      }
    }
    return _hardBreaks.isEmpty;
  }

  /// 把挂起的折叠空格补出来（行首与换行后不补）。
  void _flushPendingSpace() {
    if (!_pendingSpace) {
      return;
    }
    _pendingSpace = false;
    if (_buffer.isNotEmpty && _lastCodeUnit != 10) {
      _buffer.write(' ');
      _lastCodeUnit = 32;
    }
  }

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
      if (_isCollapsibleWhitespace(char)) {
        if (char == '\n' && mode.keepNewlines) {
          _flushPendingSpace();
          _writeBreak();
          emitted += 1;
          continue;
        }
        if (mode.collapseSpaces) {
          _pendingSpace = true;
          continue;
        }
        _flushPendingSpace();
        _buffer.write(char);
        _lastCodeUnit = char.codeUnitAt(0);
        emitted += 1;
        continue;
      }
      _flushPendingSpace();
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
    _writeBreak();
  }

  void addPlaceholder() {
    _pendingSpace = false;
    _buffer.write('\uFFFC');
    _lastCodeUnit = 0xFFFC;
    _runs.add(TextRun(start: _buffer.length - 1, end: _buffer.length));
  }

  /// 行内图片：占位符照写（保持 CFI/选区语义），同时记录节点供纯图
  /// 块折叠（图片属性在 InlineNode.attributes 上）。
  void addImage(InlineNode node) {
    addPlaceholder();
    images.add(node);
  }

  /// 写一个换行并记录强制换行位置（块首换行忽略）。
  void _writeBreak() {
    if (_buffer.isEmpty) {
      return;
    }
    _buffer.write('\n');
    _lastCodeUnit = 10;
    _hardBreaks.add(_buffer.length - 1);
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
      inlineMarks: marks.isEmpty
          ? const <InlineMark>[]
          : List<InlineMark>.unmodifiable(marks),
      cfi: _firstText?.cfi ?? fallbackCfi,
      start: _firstText?.start ?? fallbackStart,
      end: _lastText?.end ?? fallbackEnd,
    );
    _buffer.clear();
    _runs.clear();
    _hardBreaks.clear();
    marks.clear();
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
