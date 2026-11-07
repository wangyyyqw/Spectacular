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

/// 行内样式标记的匹配主体（真实书适配）：标签、class 集与完整属性。链式组合
/// 供后代/子代选择器匹配（块与行内层级同构）。
class MarkSubject {
  /// 创建主体。
  const MarkSubject({
    required this.tag,
    required this.classes,
    this.attributes = const <String, String>{},
  });

  /// 标签名。
  final String tag;

  /// class 集。
  final Set<String> classes;

  /// 原始属性，保留 id/style 和属性选择器所需的信息。
  final Map<String, String> attributes;
}

/// 一个行内样式标记（真实书适配）：聚合文本中的区间 + 来源元素链
/// （从最外祖先到自身，含块级与行内层级）。样式解析由消费方（章节
/// 源）按作者 CSS 完成；空原子盒用零长度区间保留，不增加正文字数。
class InlineMark {
  /// 创建标记。
  const InlineMark({
    required this.start,
    required this.end,
    required this.tag,
    required this.classes,
    this.chain = const <MarkSubject>[],
  });

  /// 起始偏移（UTF-16，聚合文本坐标系，含）。
  final int start;

  /// 结束偏移（半开）。
  final int end;

  /// 来源元素标签（span/b/strong…）。
  final String tag;

  /// class 列表（文档顺序）。
  final List<String> classes;

  /// 祖先链（最外 → 自身；块级与行内层级混排），后代选择器匹配用。
  final List<MarkSubject> chain;
}

/// 注音标注（P8-08，CSS Ruby 1 flat 近似）：主文本区间 + 注音文本。
class RubyMark {
  /// 创建注音标注。
  const RubyMark({required this.start, required this.end, required this.text});

  /// 主文本区间起始（聚合文本坐标系，含）。
  final int start;

  /// 结束偏移（半开）。
  final int end;

  /// 注音文本（rt 子文本拼接，多 rt 以空格连接）。
  final String text;
}

/// 行内图片标记（P9-06）：聚合文本中 U+FFFC 占位符的下标与来源节点。
///
/// 混合文本里的 `<img>` 保留占位符参与排版，绘制层按 [offset] 把图片
/// 画在占位符字形的位置上（否则只会看到一个豆腐块）。
class InlineImageMark {
  /// 创建标记。
  const InlineImageMark({required this.offset, required this.node});

  /// 占位符在聚合文本中的下标（UTF-16）。
  final int offset;

  /// 图片来源节点（src/width/height/class 等属性）。
  final InlineNode node;
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
    this.rubies = const <RubyMark>[],
    this.inlineImages = const <InlineImageMark>[],
  });

  @override
  final String text;

  /// 样式区间。
  final List<TextRun> runs;

  /// 强制换行位置（`<br>` 与保留的换行符在 text 中的下标）。
  final List<int> hardBreaks;

  /// 行内样式标记（真实书适配）。
  final List<InlineMark> inlineMarks;

  /// 行内图片（P9-06）：U+FFFC 占位符位置与图片节点。
  final List<InlineImageMark> inlineImages;

  /// 注音标注（P8-08）：ruby 主文本区间 + 注音串。
  final List<RubyMark> rubies;

  /// 文本块 CFI（取首个来源文本节点的 CFI）。
  final EpubCfi cfi;

  /// 源码起始偏移。
  final int start;

  /// 源码结束偏移。
  final int end;
}

/// 章节源可在聚合前按作者样式修正行内元素的块边界；缺省保持 UA 行为。
typedef InlineDisplayResolver = CssDisplay Function(
  InlineNode node,
  List<MarkSubject> ancestors,
);

/// 行内元素产生的块及其被跨过的行内祖先，供布局恢复原选择器与继承链。
/// 这是聚合树的结构信息，不改变作者属性或原始 CFI。
class PromotedBlockNode extends BlockNode {
  PromotedBlockNode(BlockNode block, List<InlineNode> ancestors)
    : inlineAncestors = List.unmodifiable(ancestors),
      super(
        tag: block.tag,
        display: block.display,
        children: block.children,
        cfi: block.cfi,
        attributes: block.attributes,
        start: block.start,
        end: block.end,
        containerChain: block.containerChain,
      );

  final List<InlineNode> inlineAncestors;
}

class _OpenInlineMark {
  _OpenInlineMark(this.node, this.ancestors, this.start, this.keepEmpty);
  final InlineNode node;
  final List<MarkSubject> ancestors;
  int start;
  final bool keepEmpty;
}

class _OpenRuby {
  _OpenRuby(this.start);
  int start;
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
typedef WhiteSpaceResolver = CssWhiteSpace Function(
  EpubNode node,
  List<MarkSubject> ancestors,
);

abstract final class TextAggregator {
  /// 记录样式标记的标签（真实书适配）：这些标签的行内元素即使无 class
  /// 也产标记（UA 语义样式：粗斜体/上下标/删除线等）。
  static const _styleMarkTags = <String>{
    'b',
    'strong',
    'em',
    'i',
    'u',
    's',
    'strike',
    'del',
    'ins',
    'code',
    'sub',
    'sup',
    'small',
    'big',
    'mark',
    'font',
    'cite',
    'q',
    'span',
  };

  /// 聚合一个章节。
  ///
  /// [whiteSpace] 决定空白与换行如何保留；`<pre>` 标签始终按 `pre` 处理。
  static BlockDocument aggregate(
    BlockDocument document, {
    CssWhiteSpace whiteSpace = CssWhiteSpace.normal,
    InlineDisplayResolver? inlineDisplay,
    WhiteSpaceResolver? whiteSpaceFor,
  }) {
    final root = _aggregateBlock(
      document.root,
      mode: _WhiteSpaceMode.from(whiteSpace),
      inlineDisplay: inlineDisplay,
      whiteSpaceFor: whiteSpaceFor,
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
    List<MarkSubject> chain = const <MarkSubject>[],
    InlineDisplayResolver? inlineDisplay,
    WhiteSpaceResolver? whiteSpaceFor,
  }) {
    // `<pre>` 标签自带 `white-space: pre` 的 UA 语义。
    final effective = whiteSpaceFor != null
        ? _WhiteSpaceMode.from(whiteSpaceFor(block, chain))
        : block.tag == 'pre'
        ? _WhiteSpaceMode.pre
        : mode;
    // 后代选择器链（真实书对齐）：块级祖先（body→div→p…）入链。
    final blockSubject = MarkSubject(
      tag: block.tag,
      attributes: block.attributes,
      classes: (block.attributes['class'] ?? '')
          .split(RegExp(r'\s+'))
          .where((c) => c.isNotEmpty)
          .toSet(),
    );
    final subjectChain = <MarkSubject>[...chain, blockSubject];
    final accumulator = _TextAccumulator(
      mode: effective,
      fallbackCfi: block.cfi,
      fallbackStart: block.start,
      fallbackEnd: block.end,
    );
    final children = <EpubNode>[];
    final activeInline = <InlineNode>[];
    final activeMarks = <_OpenInlineMark>[];
    final activeRubies = <_OpenRuby>[];

    void flush() {
      // 块边界会清空累积器；跨边界的外层行内标记须分别覆盖前后片段。
      for (final ruby in activeRubies.reversed) {
        accumulator.closeRuby(ruby.start);
      }
      for (final mark in activeMarks.reversed) {
        accumulator.closeMark(
          mark.start,
          mark.node,
          mark.ancestors,
          keepEmpty: mark.keepEmpty,
        );
      }
      final content = accumulator.take();
      if (content != null) {
        children.add(content);
      }
      for (final mark in activeMarks) {
        mark.start = 0;
      }
      for (final ruby in activeRubies) {
        ruby.start = 0;
      }
    }

    String hiddenAwareInlineText(InlineNode node, List<MarkSubject> ancestors) {
      final buffer = StringBuffer();
      void visitInlineText(InlineNode current, List<MarkSubject> chain) {
        final display = inlineDisplay?.call(current, chain);
        if (display == CssDisplay.none) return;
        final childChain = <MarkSubject>[
          ...chain,
          MarkSubject(
            tag: current.tag,
            attributes: current.attributes,
            classes: (current.attributes['class'] ?? '')
                .split(RegExp(r'\s+'))
                .where((c) => c.isNotEmpty)
                .toSet(),
          ),
        ];
        for (final child in current.children) {
          if (child is ParsedText) {
            buffer.write(child.text);
          } else if (child is TextBlockNode) {
            buffer.write(child.text);
          } else if (child is InlineNode) {
            visitInlineText(child, childChain);
          }
        }
      }

      visitInlineText(node, ancestors);
      return buffer.toString();
    }

    void visitInline(
      InlineNode node,
      List<MarkSubject> ancestors,
      _WhiteSpaceMode inheritedMode,
    ) {
      final inlineMode = whiteSpaceFor == null
          ? inheritedMode
          : _WhiteSpaceMode.from(whiteSpaceFor(node, ancestors));
      final display = inlineDisplay?.call(node, ancestors);
      if (display == CssDisplay.none) return;
      if (display == CssDisplay.block) {
        flush();
        final promoted = BlockNode(
          tag: node.tag,
          display: DisplayMode.block,
          children: node.children,
          cfi: node.cfi,
          attributes: node.attributes,
          start: node.start,
          end: node.end,
        );
        children.add(
          PromotedBlockNode(
            _aggregateBlock(
              promoted,
              mode: effective,
              chain: ancestors,
              inlineDisplay: inlineDisplay,
              whiteSpaceFor: whiteSpaceFor,
            ),
            activeInline,
          ),
        );
        return;
      }
      if (node.tag == 'br') {
        accumulator.addBreak();
        return;
      }
      // 注音捕获（P8-08，CSS Ruby 1）：rp（括号）完全忽略；rt/rtc 文本
      // 不进主流，暂存为注音；ruby 收口时把主文本区间 + 注音串记为
      // RubyMark 供渲染层注音趟。
      if (node.tag == 'rp') {
        return;
      }
      if (node.tag == 'rt' || node.tag == 'rtc') {
        accumulator.captureRubyText(hiddenAwareInlineText(node, ancestors));
        return;
      }
      final ruby = node.tag == 'ruby'
          ? _OpenRuby(accumulator.openMark())
          : null;
      if (ruby != null) activeRubies.add(ruby);
      // 行内样式标记：带属性的元素与已知样式标签记录
      // 区间（含祖先链），样式解析由章节源按作者 CSS 完成。
      final markable =
          display == CssDisplay.inlineBlock ||
          node.attributes.isNotEmpty ||
          _styleMarkTags.contains(node.tag);
      final markStart = markable ? accumulator.openMark() : -1;
      final openMark = markable
          ? _OpenInlineMark(
              node,
              ancestors,
              markStart,
              display == CssDisplay.inlineBlock,
            )
          : null;
      activeInline.add(node);
      if (openMark != null) activeMarks.add(openMark);
      if (node.tag == 'img' || node.tag == 'image') {
        accumulator.addImage(node);
      } else {
        final inlineChain = <MarkSubject>[
          ...ancestors,
          MarkSubject(
            tag: node.tag,
            attributes: node.attributes,
            classes: (node.attributes['class'] ?? '')
                .split(RegExp(r'\s+'))
                .where((c) => c.isNotEmpty)
                .toSet(),
          ),
        ];
        for (final child in node.children) {
          if (child is ParsedText) {
            accumulator.addText(child, whiteSpaceMode: inlineMode);
          } else if (child is InlineNode) {
            visitInline(child, inlineChain, inlineMode);
          } else if (child is BlockNode) {
            // 行内节点（尤其链接）可包含 HTML5 允许的块级后代。不能把它
            // 当成行内文本继续拼接：先结束当前文本流，再按块递归聚合，
            // 让 CFI、块边界和外层链接祖先都保留下来。
            flush();
            final aggregated = _aggregateBlock(
              child,
              mode: inlineMode,
              chain: <MarkSubject>[...subjectChain, ...inlineChain],
              inlineDisplay: inlineDisplay,
              whiteSpaceFor: whiteSpaceFor,
            );
            children.add(
              PromotedBlockNode(aggregated, List<InlineNode>.of(activeInline)),
            );
          } else if (child is TextBlockNode) {
            accumulator.addRawText(child.text);
          }
        }
      }
      if (ruby != null) {
        accumulator.closeRuby(ruby.start);
        activeRubies.removeLast();
      }
      if (markable) {
        accumulator.closeMark(
          openMark!.start,
          node,
          ancestors,
          keepEmpty: openMark.keepEmpty,
        );
        activeMarks.removeLast();
      }
      if (display == CssDisplay.inlineBlock) {
        accumulator.endInlineBox();
      }
      activeInline.removeLast();
    }

    for (final child in block.children) {
      if (child is BlockNode) {
        flush();
        children.add(
          _aggregateBlock(
            child,
            mode: effective,
            chain: subjectChain,
            inlineDisplay: inlineDisplay,
            whiteSpaceFor: whiteSpaceFor,
          ),
        );
      } else if (child is InlineNode) {
        // 表格列声明（P9-17）：`colgroup/col` 是纯结构元素，没有文字，
        // 放进聚合流会被丢弃；原样保留给表格布局读取列宽。
        if (child.tag == 'colgroup' || child.tag == 'col') {
          children.add(child);
          continue;
        }
        visitInline(child, subjectChain, effective);
      } else if (child is ParsedText) {
        accumulator.addText(child);
      } else if (child is TextBlockNode) {
        accumulator.addRawText(child.text);
      }
    }
    // 折叠判定必须在 flush（take 会清空缓冲）之前做，否则缓冲已空、
    // 残留文本被误判为「只含图片占位」。
    final onlyImage =
        children.isEmpty &&
            accumulator.images.length == 1 &&
            !accumulator.marks.any((mark) => mark.start == mark.end) &&
            accumulator.hasOnlyImages
        ? accumulator.images.single.node
        : null;
    flush();

    // 纯图块折叠（真实书适配）：块内唯一实质内容是一个 img/image（无
    // 其他文本、无强制换行）时，丢弃占位文本、保留图片属性（src/width/
    // height/class），产出 tag='img' 的块节点供章节源构造图片块。
    if (onlyImage != null) {
      final image = onlyImage;
      return BlockNode(
        tag: 'img',
        display: DisplayMode.block,
        children: const <EpubNode>[],
        cfi: block.cfi,
        attributes: image.attributes,
        start: block.start,
        end: block.end,
        // 折叠丢弃了外层容器，把容器链带上，级联才能还原容器样式。
        containerChain: <({String tag, String classes})>[
          for (final subject in subjectChain)
            (tag: subject.tag, classes: subject.classes.join(' ')),
        ],
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
          containerChain: only.containerChain,
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

  /// 块内遇到的图片行内节点（`<img>`/`<image>`），供纯图块折叠判定
  /// 与行内图片绘制（P9-06）。
  final List<InlineImageMark> images = <InlineImageMark>[];

  /// 行内样式标记（真实书适配）：visitInline 按 open/close 记录。
  final List<InlineMark> marks = <InlineMark>[];

  /// 注音标注（P8-08）：ruby 主文本区间 + 注音串。
  final List<RubyMark> rubies = <RubyMark>[];

  /// 当前 ruby 捕获的注音片段（rt 顺序）。
  final List<String> _rubyTextParts = <String>[];
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

  /// 空原子盒保留零长度标记，不往正文/CFI 坐标写入占位字符。
  void closeMark(
    int start,
    InlineNode node,
    List<MarkSubject> ancestors, {
    bool keepEmpty = false,
  }) {
    final end = _buffer.length;
    if (end <= start && !keepEmpty) {
      return;
    }
    final classes = (node.attributes['class'] ?? '')
        .split(RegExp(r'\s+'))
        .where((c) => c.isNotEmpty)
        .toList(growable: false);
    marks.add(
      InlineMark(
        start: start,
        end: end,
        tag: node.tag,
        classes: classes,
        chain: List<MarkSubject>.unmodifiable([
          ...ancestors,
          MarkSubject(
            tag: node.tag,
            classes: classes.toSet(),
            attributes: node.attributes,
          ),
        ]),
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
    if ((_buffer.isNotEmpty || marks.isNotEmpty) &&
        _lastCodeUnit != 10 &&
        _lastCodeUnit != 32) {
      _buffer.write(' ');
      _lastCodeUnit = 32;
    }
  }

  void addText(ParsedText node, {_WhiteSpaceMode? whiteSpaceMode}) {
    final effective = whiteSpaceMode ?? mode;
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
        if (char == '\n' && effective.keepNewlines) {
          _flushPendingSpace();
          _writeBreak();
          emitted += 1;
          continue;
        }
        if (effective.collapseSpaces) {
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

  /// 盒内尾部折叠空白不泄漏；盒后的空格按新的原子边界保留。
  void endInlineBox() {
    _pendingSpace = false;
    _lastCodeUnit = 0xFFFC;
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
    images.add(InlineImageMark(offset: _buffer.length - 1, node: node));
  }

  /// 注音捕获（P8-08）：rt/rtc 文本不进主流，暂存待 ruby 收口。
  void captureRubyText(String text) {
    if (text.trim().isNotEmpty) {
      _rubyTextParts.add(text.trim());
    }
  }

  /// ruby 收口：主文本区间 [start, 缓冲当前位置) + 暂存注音串。
  void closeRuby(int start) {
    final end = _buffer.length;
    final annotation = _rubyTextParts.join(' ');
    _rubyTextParts.clear();
    if (end > start && annotation.isNotEmpty) {
      rubies.add(RubyMark(start: start, end: end, text: annotation));
    }
  }

  /// 写一个换行并记录强制换行位置（块首换行忽略）。
  void _writeBreak() {
    if (_buffer.isEmpty && marks.isEmpty) {
      return;
    }
    _buffer.write('\n');
    _lastCodeUnit = 10;
    _hardBreaks.add(_buffer.length - 1);
  }

  TextContentNode? take() {
    final content = _buffer.isEmpty && marks.isEmpty
        ? null
        : TextContentNode(
            text: _buffer.toString(),
            runs: List<TextRun>.unmodifiable(_runs),
            hardBreaks: List<int>.unmodifiable(_hardBreaks),
            inlineMarks: marks.isEmpty
                ? const <InlineMark>[]
                : List<InlineMark>.unmodifiable(marks),
            rubies: rubies.isEmpty
                ? const <RubyMark>[]
                : List<RubyMark>.unmodifiable(rubies),
            inlineImages: images.isEmpty
                ? const <InlineImageMark>[]
                : List<InlineImageMark>.unmodifiable(images),
            cfi: _firstText?.cfi ?? fallbackCfi,
            start: _firstText?.start ?? fallbackStart,
            end: _lastText?.end ?? fallbackEnd,
          );
    _buffer.clear();
    _runs.clear();
    _hardBreaks.clear();
    marks.clear();
    rubies.clear();
    images.clear();
    _pendingSpace = false;
    _lastCodeUnit = null;
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
