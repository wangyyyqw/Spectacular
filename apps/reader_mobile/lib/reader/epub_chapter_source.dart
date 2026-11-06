import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, Rect;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:path/path.dart' as p;
import 'package:reader_core/api.dart' hide ComputedStyle, Paginator;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/book_font_loader.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/stylesheet_loader.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/css/ua_stylesheet.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/block_flow.dart' show collapseMargins;
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/line_breaker.dart';
// api.dart 也导出了同名的 `LineBreaker` 接口，这里给具体实现加前缀，
// 以便打开小数行高开关（见 [EpubChapterSource.open]）。
import 'package:reader_core/layout/line_breaker.dart' as line_breaker;
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/perf/trace.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart'
    show ParsedDocument, ParsedElement;
import 'package:reader_core/parser/full_bleed.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_core/paint/image_size.dart';
import 'package:reader_core/position/cfi.dart' show cfiWithCharOffset;
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/text/font_coverage.dart';
import 'package:reader_core/text/xhtml_text.dart';
import 'package:reader_ui/reader_session.dart';

import 'bounded_cache.dart';
import 'prose_spacing_defaults.dart';

/// 从 EPUB 文档读取章节并提供分页结果。
class EpubChapterSource
    implements
        RestylableChapterSource,
        ResizableChapterSource,
        TocChapterSource,
        ReaderTextOverlaySource {
  EpubChapterSource._({
    required this.document,
    required this.baseContentWidth,
    required this.baseContentHeight,
    required this.baseStyle,
    required this.trimTextEdges,
  });

  /// 打开 EPUB 并创建来源。
  static Future<EpubChapterSource> open(
    Uint8List bytes, {
    double contentWidth = 320,
    double contentHeight = 480,
    ComputedStyle? style,
    bool verifyCrc = true,
    bool trimTextEdges = true,
  }) async {
    // 小数行高（T1 实验开关）：Skia 会把行盒高取整成整数，CSS 的
    // `line-height: 1.7` × 15px = 25.5 会变成 26，列表/表格行位置逐行
    // 累积偏移（31-list-nested 14 项、12-table 残余都是它）。
    line_breaker.LineBreaker.preserveFractionalLineHeight = true;
    final result = await openEpub(bytes, verifyCrc: verifyCrc);
    final document = result.document;
    if (document == null) {
      throw StateError(result.report.message ?? '打开 EPUB 失败');
    }
    return EpubChapterSource._(
      document: document,
      baseContentWidth: contentWidth,
      baseContentHeight: contentHeight,
      // 基础样式只给字号与字族：行高不能写死——写死 1.5 会让书籍的
      // `line-height: normal` 永远走不到（T2 已按字体度量实现 normal≈1.4），
      // 单元格/正文行高因此比浏览器高 1~2px。真实阅读器的 1.5 由
      // ReaderOverrides(lineHeight:) 注入，不依赖这里。
      baseStyle:
          style ??
          ComputedStyle(const <String, String>{
            'font-size': '16px',
            'font-family': 'serif',
          }),
      trimTextEdges: trimTextEdges,
    );
  }

  /// 已打开文档。
  final EpubDocumentImpl document;

  /// 目录（P4-11）：每项自带目标 spine 序号。
  @override
  List<TocEntry> get toc => document.toc;

  /// 原始正文区宽（未扣设置页边距）。
  final double baseContentWidth;

  /// 原始正文区高。
  final double baseContentHeight;

  /// 书籍基础样式。
  final ComputedStyle baseStyle;

  /// 是否回收页首/页尾的行高留白。
  ///
  /// 阅读模式默认开启；CSS 属性对照需要完整行盒时显式关闭。
  final bool trimTextEdges;

  ReaderOverrides _overrides = const ReaderOverrides();

  ReaderTextOverlayResolver _textOverlayResolver = ReaderTextOverlayResolver(
    const [],
    colors: false,
  );

  /// 阅读页传入的正文区尺寸（旋转/窗口变化后由 ReaderSession 设置）。
  double? _viewportContentWidth;
  double? _viewportContentHeight;
  double? _viewportContentTopInset;

  /// 段落布局缓存（P2-26）：同一文本+样式的重复测量直接复用。
  final TextLayoutCache _layoutCache = TextLayoutCache();

  /// 表格最小内容宽只依赖样式与文本片段；缓存单字/词段宽度，避免同一
  /// 章节的多张表格反复创建 TextPainter。
  final BoundedCache<String, double> _textWidthCache = BoundedCache(4096);

  /// 排版缓存三层（P7-23；对照 Reeden document/styles/pagination，
  /// 550 号 §0）：
  /// - document：聚合后的章节文本（解析+聚合结果），键=spineIndex；
  /// - styles：块级样式由 [styleFor] 按（基准+覆盖）即时派生，缓存键
  ///   只含影响该层的最小变量集（字号/行高/对齐/边距/几何）；
  /// - pagination：页缓存与页索引，键=spineIndex+排版指纹（几何+设置
  ///   排版字段）。主题颜色不进任何键 → 切主题零重排。
  // 作者 display 取决于媒体条件；每章仅保留最近一次排版环境的聚合结果。
  final Map<
    int,
    ({String key, BlockDocument document, _ParsedSelectorIndex selectors})
  >
  _displayDocumentCache = {};
  final List<int> _displayDocumentCacheOrder = <int>[];
  final BoundedCache<String, AnchorChapter> _anchorChapterCache = BoundedCache(
    2,
  );

  /// 当前书的注释正文缓存：引用节点键 → 已解析注释。
  final BoundedCache<int, Map<String, FootnoteAnchor>> _footnoteReferenceCache =
      BoundedCache(chapterIndexCacheLimit);
  // 满屏判定与紧随的正文聚合共用一次解析；不长期保留第二棵原始树。
  BlockDocument? _pendingBlockDocument;
  // 原始元素树提供结构伪类/兄弟组合器所需的真实 childElements。
  _ParsedSelectorIndex? _pendingSelectorIndex;

  /// white-space 原文保留（P9-28）：命中章节的判定结果与两遍保留模式
  /// 聚合的文本节点（键 = 源码起止偏移），见 [_preservedTexts]。
  final BoundedCache<int, bool> _preservingWhiteSpaceCache = BoundedCache(
    chapterIndexCacheLimit,
  );
  final BoundedCache<int, Map<String, TextContentNode>> _preservedRawTexts =
      BoundedCache(chapterIndexCacheLimit);
  final BoundedCache<int, Map<String, TextContentNode>> _preservedPreLineTexts =
      BoundedCache(chapterIndexCacheLimit);

  /// 页缓存（key = paginationKey）：按章 LRU，上限 [pageCacheChapterLimit] 章
  /// （§44.4：只留当前章 ±2）。
  final Map<String, List<PageContent>> _pageCache =
      <String, List<PageContent>>{};

  /// LRU 顺序（最近使用的在末尾）。
  final List<String> _pageCacheOrder = <String>[];

  /// 每个分页键实际引用的书内字族，用于字体增量加载后的定向失效。
  final Map<String, Set<String>> _paginationFontFamilies =
      <String, Set<String>>{};

  /// 页缓存保留的章数上限（当前章 ±2）。
  static const int pageCacheChapterLimit = 5;

  /// styles 层块缓存上限：与页缓存一致，只保留最近排版过的章。
  static const int blockCacheChapterLimit = pageCacheChapterLimit;

  /// document 层缓存上限：聚合树与选择器视图只保留最近使用的章。
  static const int documentCacheChapterLimit = pageCacheChapterLimit;

  /// 章节派生轻量索引上限：与已测块树使用同一章节窗口。
  static const int chapterIndexCacheLimit = pageCacheChapterLimit;

  /// 样式表 AST 上限；典型书远低于此值，异常书也不无界增长。
  static const int cssSheetCacheLimit = 32;

  /// 图片尺寸正值/缺失值上限；仅保存路径与尺寸，不保存图片字节。
  static const int imageIntrinsicCacheLimit = 512;

  void _touchPageCache(String key) {
    _pageCacheOrder.remove(key);
    _pageCacheOrder.add(key);
  }

  void _putPageCache(String key, List<PageContent> pages) {
    _pageCache[key] = pages;
    _touchPageCache(key);
    while (_pageCache.length > pageCacheChapterLimit) {
      final oldest = _pageCacheOrder.removeAt(0);
      _pageCache.remove(oldest);
      _pageIndexCache.remove(oldest);
    }
  }

  /// styles 层缓存：章节聚合树 → 已级联样式并完成行测量的块树。
  ///
  /// 页索引重放（P7-22）只需块边界与行几何；没有这层时每次重放都要
  /// 重新跑一遍样式与测量。固定定位块不进流，必须与正文块成对保存。
  final Map<
    String,
    ({List<PageBlock> flow, List<PageBlock> fixed, PageBackground? background})
  >
  _blockCache = {};
  final List<String> _blockCacheOrder = <String>[];
  int _blockCacheHits = 0;

  void _touchBlockCache(String key) {
    _blockCacheOrder.remove(key);
    _blockCacheOrder.add(key);
  }

  void _putBlockCache(
    String key, {
    required List<PageBlock> flow,
    required List<PageBlock> fixed,
    required PageBackground? background,
  }) {
    _blockCache[key] = (flow: flow, fixed: fixed, background: background);
    _touchBlockCache(key);
    while (_blockCache.length > blockCacheChapterLimit) {
      _blockCache.remove(_blockCacheOrder.removeAt(0));
    }
  }

  /// styles 层块缓存命中次数（测试/诊断用）。
  int get blockCacheHits => _blockCacheHits;
  int _displayDocumentCacheHits = 0;

  /// 章节结构缓存命中次数（测试/诊断用）。
  int get displayDocumentCacheHits => _displayDocumentCacheHits;

  void _touchDisplayDocumentCache(int spineIndex) {
    _displayDocumentCacheOrder.remove(spineIndex);
    _displayDocumentCacheOrder.add(spineIndex);
  }

  void _putDisplayDocumentCache(
    int spineIndex, {
    required String key,
    required BlockDocument document,
    required _ParsedSelectorIndex selectors,
  }) {
    _displayDocumentCache[spineIndex] = (
      key: key,
      document: document,
      selectors: selectors,
    );
    _touchDisplayDocumentCache(spineIndex);
    while (_displayDocumentCache.length > documentCacheChapterLimit) {
      _displayDocumentCache.remove(_displayDocumentCacheOrder.removeAt(0));
    }
  }

  void _clearDisplayDocumentCache() {
    _displayDocumentCache.clear();
    _displayDocumentCacheOrder.clear();
    _anchorChapterCache.clear();
  }

  Map<String, FootnoteAnchor> _footnoteReferences(int spineIndex) =>
      _footnoteReferenceCache.putIfAbsent(spineIndex, () {
        final refs = <String, FootnoteAnchor>{};
        for (final anchor in document.resolveFootnotes(spineIndex)) {
          refs.putIfAbsent(anchor.referenceKey, () => anchor);
        }
        return Map<String, FootnoteAnchor>.unmodifiable(refs);
      });

  Set<String> _hiddenFootnoteIds(
    int spineIndex,
    Map<String, FootnoteAnchor> references,
  ) => {
    for (final anchor in references.values) ...[
      if (anchor.kind != NoteKind.link &&
          anchor.targetSpine == spineIndex &&
          anchor.targetId != null &&
          anchor.targetId!.isNotEmpty)
        anchor.targetId!,
      if (anchor.kind != NoteKind.link &&
          anchor.targetSpine == spineIndex &&
          anchor.definitionId != null &&
          anchor.definitionId!.isNotEmpty)
        anchor.definitionId!,
    ],
  };

  static const Set<String> _footnoteDefinitionContainerTags = <String>{
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

  /// 注释目标可能位于无 id 的外层块中，需要隐藏最近的定义容器。
  static Set<ParsedElement> _hiddenFootnoteElements(
    ParsedElement root,
    Set<String> hiddenIds,
  ) {
    final hidden = <ParsedElement>{};
    final ancestors = <ParsedElement>[];
    bool walk(ParsedElement element) {
      final id = element.id;
      var hasBacklink = false;
      ancestors.add(element);
      for (final child in element.children) {
        if (child is ParsedElement) {
          hasBacklink = walk(child) || hasBacklink;
        }
      }
      ancestors.removeLast();
      final isBacklink = FootnoteParser.isBacklink(
        element.tag,
        element.attributes,
      );
      // 跨文档定义页可能没有 epub:type/class，仅由“正文 → 定义”的返回
      // 链接标识；这类容器也要从阅读流中移除。
      final isBacklinkContainer =
          hasBacklink && _footnoteDefinitionContainerTags.contains(element.tag);
      if ((id != null && hiddenIds.contains(id)) || isBacklinkContainer) {
        var owner = element;
        for (var index = ancestors.length - 1; index >= 0; index--) {
          if (_footnoteDefinitionContainerTags.contains(ancestors[index].tag)) {
            owner = ancestors[index];
            break;
          }
        }
        hidden.add(owner);
      }
      return isBacklink || hasBacklink;
    }

    walk(root);
    return hidden;
  }

  BlockDocument _buildDisplayDocument(ParsedDocument parsed, int spineIndex) {
    final references = _footnoteReferences(spineIndex);
    final hiddenIds = _hiddenFootnoteIds(spineIndex, references);
    final hiddenElements = _hiddenFootnoteElements(parsed.root, hiddenIds);
    return BlockBuilder.build(
      parsed,
      skipElement: (element) =>
          hiddenElements.contains(element) ||
          FootnoteParser.isDefinitionElement(element.tag, element.attributes),
    );
  }

  /// 覆盖迁移复用正文聚合与作者空白规则，不生成整章分页或解码图片。
  AnchorChapter anchorChapter(int spineIndex) {
    final cacheKey = _structureKey(spineIndex);
    final cached = _anchorChapterCache[cacheKey];
    if (cached != null) return cached;
    final display = _displayDocumentCache[spineIndex];
    final reusableDisplay = display != null && display.key == cacheKey;
    final parsed = reusableDisplay ? null : document.parseDocument(spineIndex);
    final selectors = reusableDisplay
        ? display.selectors
        : _ParsedSelectorIndex(parsed!.root);
    final rules = CascadeRuleSet([
      ...uaRules(),
      for (final (index, sheet) in _chapterStylesheets(spineIndex).indexed)
        ...CascadeRule.fromStylesheet(
          sheet,
          origin: CascadeOrigin.author,
          startOrder: 1000 + index * 10000,
        ),
    ]);
    ComputedStyle styleOf(EpubNode node) =>
        _anchorNodeStyle(node, selectors, rules);
    CssDisplay displayOf(InlineNode node, List<MarkSubject> ancestors) =>
        switch (styleOf(node).values['display']?.trim().toLowerCase()) {
          'block' => CssDisplay.block,
          'none' => CssDisplay.none,
          'inline-block' => CssDisplay.inlineBlock,
          _ => CssDisplay.inline,
        };
    final tree = reusableDisplay
        ? display.document
        : TextAggregator.aggregate(
            _buildDisplayDocument(parsed!, spineIndex),
            inlineDisplay: displayOf,
          );
    final chapter = AnchorChapter(
      spineIndex: spineIndex,
      href: document.spine[spineIndex].href,
      title: _anchorChapterTitle(spineIndex),
      readable: !document.progressExcludedSpineIndexes.contains(spineIndex),
      blocks: _anchorBlocks(tree.root, spineIndex, styleOf, displayOf),
    );
    _anchorChapterCache[cacheKey] = chapter;
    return chapter;
  }

  ComputedStyle _anchorNodeStyle(
    EpubNode node,
    _ParsedSelectorIndex selectors,
    CascadeRuleSet rules,
  ) {
    final chain = selectors.chainOf(node) ?? const <SelectorElement>[];
    var style = baseStyle;
    for (var i = 0; i < chain.length; i++) {
      style = Cascade.compute(
        element: chain[i],
        ancestors: chain.sublist(0, i),
        rules: rules.candidatesFor(chain[i]),
        inlineDeclarations: _inlineDeclarationsOf(chain[i].attributes['style']),
        parent: style,
        rootFontSize: baseStyle.fontSize,
        containingWidth: contentWidth,
        viewportWidth: contentWidth,
      );
    }
    return style;
  }

  String _anchorChapterTitle(int spineIndex) {
    for (final row in flattenToc(toc)) {
      if (row.entry.spineIndex == spineIndex) return row.entry.title;
    }
    return '';
  }

  List<AnchorBlock> _anchorBlocks(
    EpubNode root,
    int spineIndex,
    ComputedStyle Function(EpubNode) styleOf,
    InlineDisplayResolver displayOf,
  ) {
    final result = <AnchorBlock>[];
    void walk(EpubNode node, ComputedStyle parentStyle) {
      // 聚合文本没有元素选择器身份，正文同样继承所在块的完整级联链。
      final style = node is TextContentNode ? parentStyle : styleOf(node);
      if (style.display == CssDisplay.none ||
          style.visibility != CssVisibility.visible) {
        return;
      }
      if (node is TextContentNode) {
        final text = _textNodeFor(
          spineIndex,
          node,
          style.whiteSpace,
          displayOf,
        );
        if (text.text.trim().isNotEmpty) {
          result.add(AnchorBlock(cfi: node.cfi.serialize(), text: text.text));
        }
      } else if (node is BlockNode) {
        if (const {'td', 'th', 'caption'}.contains(node.tag)) {
          final text = _anchorCellText(node);
          if (text.isNotEmpty) {
            result.add(AnchorBlock(cfi: node.cfi.serialize(), text: text));
          }
        } else {
          for (final child in node.children) {
            walk(child, style);
          }
        }
      } else if (node is InlineNode) {
        for (final child in node.children) {
          walk(child, style);
        }
      }
    }

    walk(root, baseStyle);
    return result;
  }

  String _anchorCellText(EpubNode root) {
    final parts = <String>[];
    void walk(EpubNode node) {
      if (node is TextBlockNode && node.text.trim().isNotEmpty) {
        final hasEmptyBox =
            node is TextContentNode &&
            node.inlineMarks.any((mark) => mark.start == mark.end);
        parts.add(hasEmptyBox ? node.text : node.text.trim());
      } else if (node is BlockNode) {
        node.children.forEach(walk);
      } else if (node is InlineNode) {
        node.children.forEach(walk);
      }
    }

    walk(root);
    return parts.join('\n');
  }

  /// 缓存报告（P4-32）：页缓存章数与容量。
  String get cacheReport =>
      '页缓存 ${_pageCache.length}/$pageCacheChapterLimit 章；'
      '块缓存 ${_blockCache.length}/$blockCacheChapterLimit 章；'
      '文档缓存 ${_displayDocumentCache.length}/$documentCacheChapterLimit 章；'
      '样式章索引 ${_chapterSheetCache.length}/$chapterIndexCacheLimit 章；'
      '级联准备 ${_chapterCascadeCache.length}/$chapterIndexCacheLimit 组；'
      '基础级联 ${_baseChapterCascadeCache.length}/$chapterIndexCacheLimit 组；'
      '满屏索引 ${_fullBleedCache.length}/$chapterIndexCacheLimit 章；'
      '脚注索引 ${_footnoteReferenceCache.length}/$chapterIndexCacheLimit 章；'
      '空白索引 ${_preservingWhiteSpaceCache.length}/$chapterIndexCacheLimit 章；'
      '字体 face ${_fontFacesSeen.length} 个/${_bookFontEngines.length} 族；'
      '文本宽度 ${_textWidthCache.length}/4096 条；'
      '图片索引 ${_imageIntrinsicCache.length}/$imageIntrinsicCacheLimit 个；'
      '纯文本缓存 ${_plainTextCache.length}/$chapterIndexCacheLimit 章';
  final Map<String, Uint8List> _pageIndexCache = <String, Uint8List>{};

  /// 排版层指纹（P7-23）：几何 + 设置的排版字段；颜色不参与（绘制层
  /// 即时生效，不失效任何缓存）。
  String _paginationKey(int spineIndex) =>
      '$spineIndex@${contentWidth.toString()}x${contentHeight.toString()}'
      '|top=${_contentTopInset.toString()}'
      '|spacing=$textSpacingRevision'
      '|${_overrides.fingerprint}'
      '|text=${_textOverlayResolver.typographyFingerprint}';

  /// 原文解析与 display 聚合只依赖章节和视口宽度；阅读设置变化时可复用。
  String _structureKey(int spineIndex) =>
      '$spineIndex@width=${contentWidth.toString()}';

  /// 失效与续排日志（P7-27；对照 Reeden 失效诊断带 old/new——
  /// 「批量排版缓存失效. 因为屏幕尺寸变更. old: 」）。
  ///
  /// 每条：`reason | oldKey -> newKey`，能回答「这次失效是谁引起的、
  /// 丢了哪几层」。四类诱因可区分：
  /// `configChanged`（设置排版字段）/ `viewportSizeChanged`（几何）/
  /// `indexMissing`（页索引缺失或损坏）/ `indexSchemaMismatch`（换代）。
  final List<String> invalidationLog = <String>[];

  void _logInvalidation(String reason, String oldKey, String newKey) {
    if (invalidationLog.length >= 200) {
      invalidationLog.removeAt(0);
    }
    invalidationLog.add('$reason | $oldKey -> $newKey');
  }

  /// 当前阅读器设置。
  ReaderOverrides get overrides => _overrides;

  /// 仅清空页缓存（保留页索引与 styles 层块缓存）：供冷启动重放路径
  /// 测试与 P7-27 续排使用——页索引仍在时 loadChapter 直接按边界出页。
  void clearPaginationCache() {
    _pageCache.clear();
    _pageCacheOrder.clear();
  }

  /// 测试钩子：注入索引字节（可注入损坏字节验证容错路径）。
  void injectPageIndexForTest(int spineIndex, Uint8List bytes) {
    _pageIndexCache[_paginationKey(spineIndex)] = bytes;
  }

  /// 正文区宽：优先用阅读页实测值（已扣页边距），否则基础宽扣设置页边距。
  double get contentWidth =>
      _viewportContentWidth ??
      math.max(
        80,
        baseContentWidth -
            (_overrides.padding?.left ?? 0) -
            (_overrides.padding?.right ?? 0),
      );

  /// 正文区高：优先用阅读页实测值（已扣页边距），否则基础高扣设置页边距。
  double get contentHeight =>
      _viewportContentHeight ??
      math.max(
        120,
        baseContentHeight -
            (_overrides.padding?.top ?? 0) -
            (_overrides.padding?.bottom ?? 0),
      );

  /// 整页到正文的真实上内缩，包含安全区及页眉槽，不只是设置中的边距。
  double get _contentTopInset =>
      _viewportContentTopInset ?? (_overrides.padding?.top ?? 0);

  /// 章首出血图从页顶排起；后续正文跟随图盒，不重复预留页眉槽。
  double _chapterTopPadding(List<PageBlock> blocks) {
    final first = blocks
        .where(
          (block) =>
              !block.absolute &&
              block.style?.display != CssDisplay.none &&
              (block.layout.lineCount > 0 || block.height > 0),
        )
        .firstOrNull;
    if (first == null ||
        first.floatSide != null ||
        !first.bleedTop ||
        first.bleedBottom ||
        first.layout.text.isNotEmpty ||
        first.style?.backgroundImage == null) {
      return 0;
    }
    return -_contentTopInset;
  }

  /// 文本块的排版宽度 = 块的内容盒宽（CSS 2.1 §10.3.3）。
  ///
  /// flat 管线把块级水平内缩折算进绘制左偏移（PagePainter 取
  /// `slice.leftInset + style.margin.left`），排版宽度必须同步扣掉同一份
  /// 内缩——否则带 margin/padding 的段落整体右移、压出正文区右缘被裁切
  /// （真机：作者 CSS `body`/`p` 各 1% 外边距 → 正文右偏且缺右缘字）。
  /// 解算规则由 [ComputedStyle.contentBoxWidth] 统一承担：
  /// - `width: auto`（含未声明）：内容宽 = 正文区宽 - margin - padding -
  ///   border；
  /// - 声明 `width`：按 `box-sizing` 折算内容宽——`content-box` 下声明值
  ///   就是内容宽，`border-box` 下声明值已含 padding+border，必须再扣掉，
  ///   否则 `.bb{box-sizing:border-box;width:200px;padding:10px;border:3px}`
  ///   会按 200px 排版（内容宽 174px 却排 200px，行宽溢出正文区）；
  /// - 最后按 min/max-width 钳制（min 优先）。
  ///
  /// 依赖：T2 在 ComputedStyle 侧提供的 `contentBoxWidth`（把 box-sizing /
  /// 百分比基准 / min-max 钳制收敛在一处，与 `BoxModel` 同口径）；这里只
  /// 保留 24px 的下限，避免极窄区间测不出行。
  double _textWidthFor(ComputedStyle style) =>
      math.max(24.0, style.contentBoxWidth(contentWidth));

  /// 容器级浮动分组号的起点（W12）：普通块组的 groupId 从 1 起，
  /// 容器浮动组用 [floatGroupBase] + 序号，分页时按组整体占位。
  static const int floatGroupBase = 500000;

  /// 相邻外边距折叠，但浮动/绝对定位块不参与（CSS 2.1 §8.3.1：浮动元素
  /// 的 margin 不与任何相邻 margin 折叠），也不打断相邻在流兄弟的折叠
  ///——把它们先摘出来，只折叠连续的在流块，再放回原位。
  ///
  /// 之前直接对整条块链折叠，浮动的段前/段后距被挪到邻居身上，多行浮动
  /// 段落的静态位置因此偏了十几像素（38-float-clear）。
  static List<PageBlock> _collapseMarginsIgnoringFloats(
    List<PageBlock> blocks,
  ) {
    final flow = <PageBlock>[];
    final positions = <int>[];
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].floatSide != null || blocks[i].absolute) {
        continue;
      }
      flow.add(blocks[i]);
      positions.add(i);
    }
    if (flow.length < 2) {
      return blocks;
    }
    final collapsed = PageBlock.collapseAdjacentMargins(flow);
    final result = List<PageBlock>.of(blocks);
    for (var i = 0; i < positions.length; i++) {
      result[positions[i]] = collapsed[i];
    }
    return result;
  }

  /// UA 里承担列表近似缩进的那条规则（见 [cascadeRules] 过滤）。
  static bool _isUaListIndentRule(CssRule rule) =>
      rule.selector.trim() == 'li' &&
      rule.declarations.any(
        (declaration) => declaration.property == 'margin-left',
      );

  /// 级联后的浮动方向（f）；未浮动返回 null。
  static FloatSide? _floatSideOfStyle(ComputedStyle style) =>
      switch (style.cssFloat) {
        CssFloat.left => FloatSide.left,
        CssFloat.right => FloatSide.right,
        CssFloat.none => null,
      };

  /// 只改宽/最大宽的重建：`writingMode`/`isRtl` 必须一起带上，否则下游
  /// （绘制/选区/分页）会把竖排块当横排处理（35-writing-mode 曾因此走错
  /// 绘制路径）。
  static TextLayoutResult withLayoutWidth(
    TextLayoutResult source, {
    double? width,
    double? maxWidth,
  }) => TextLayoutResult(
    text: source.text,
    lines: source.lines,
    width: width ?? source.width,
    height: source.height,
    maxWidth: maxWidth ?? source.maxWidth,
    runs: source.runs,
    isRtl: source.isRtl,
    writingMode: source.writingMode,
    plainTextLayout: source.plainTextLayout,
  );

  /// 浮动文本块：`PageBlock.styled` 不透传 floatSide，这里按同一口径
  /// 直接构造（内缩 = 边框 + 内边距；声明高度走 [BoxModel] 解算）。
  PageBlock _floatedTextBlock({
    required TextLayoutResult layout,
    required ComputedStyle style,
    required FloatSide side,
    required double spaceBefore,
    required double spaceAfter,
    List<InlineImageSpec> inlineImages = const <InlineImageSpec>[],
    List<PageFootnote> footnotes = const <PageFootnote>[],
    bool textRuleEligible = true,
    List<RubyAnnotation>? rubies,
    String? startCfi,
    int groupId = 0,
    bool containerSides = false,
    double effectiveOpacity = 1,
    double? containingLeft,
    double? containingWidth,
  }) {
    final model = BoxModel.fromStyle(style, containingWidth: contentWidth);
    return PageBlock(
      layout: layout,
      style: style,
      floatSide: side,
      effectiveOpacity: effectiveOpacity,
      spaceBefore: spaceBefore,
      spaceAfter: spaceAfter,
      topInset: model.borders.top + model.padding.top,
      bottomInset: model.borders.bottom + model.padding.bottom,
      leftInset: model.borders.left + model.padding.left,
      inlineImages: inlineImages,
      footnotes: footnotes,
      textRuleEligible: textRuleEligible,
      rubies: rubies,
      declaredContentHeight: model.resolveContentHeight(
        layout.height,
        containingHeight: contentHeight,
      ),
      verticalContentWidth: layout.isVertical
          ? model.resolveContentWidth(contentWidth)
          : null,
      startCfi: startCfi,
      groupId: groupId,
      containerSides: containerSides,
      floatContainingLeft: containingLeft,
      floatContainingWidth: containingWidth,
    );
  }

  /// `initial-letter` 首字块：只保留字符自身的文字样式，清空段落盒的
  /// 背景、边框、内边距和上下外边距，右侧留出 [gap] 给正文绕排。
  PageBlock _dropCapBlock({
    required String text,
    required ComputedStyle style,
    required double bodyLineHeight,
    required double lineCount,
    required double gap,
    required double effectiveOpacity,
    String? startCfi,
  }) {
    final extent = bodyLineHeight * lineCount;
    final declarations = <String, String>{
      'margin': '0 ${gap.toStringAsFixed(2)}px 0 0',
      'padding': '0',
      'border': '0',
      'background-color': 'transparent',
      'background-image': 'none',
      'line-height': '${extent.toStringAsFixed(2)}px',
      'float': 'left',
    };
    if (!style.explicitProperties.contains('font-size')) {
      declarations['font-size'] = '${(extent * 0.85).toStringAsFixed(2)}px';
    }
    final dropStyle = ComputedStyle(
      declarations,
      parent: style,
      explicitProperties: declarations.keys.toSet(),
      containingWidth: contentWidth,
      rootFontSize: style.fontSize,
    );
    final measured = _layoutCache.layout(
      text: text,
      style: dropStyle,
      maxWidth: contentWidth,
      hasGlyph: _hasBookFontGlyph,
    );
    final glyphWidth = measured.lines.isEmpty
        ? 1.0
        : measured.lines.first.advanceWidth.clamp(1.0, contentWidth);
    return _floatedTextBlock(
      layout: withLayoutWidth(
        measured,
        width: glyphWidth,
        maxWidth: glyphWidth,
      ),
      style: dropStyle,
      side: FloatSide.left,
      spaceBefore: 0,
      spaceAfter: 0,
      startCfi: startCfi,
      effectiveOpacity: effectiveOpacity,
    );
  }

  /// 构建满屏图页：整页单块 + 背景图 cover（复用 P2-13 背景管线与
  /// PagePainter.imageLookup），边距归零（用未扣设置页边距的基准尺寸）。
  /// 解码由 ReaderPage 的 imageCache 异步完成，revision 触发重绘。
  /// `position: fixed` 的每页重复（W18）：固定定位块相对页面定位，分页
  /// 完成后给每一页追加一份覆盖切片（不占流高、不影响分页）。
  List<PageContent> _withFixedOverlays(
    List<PageContent> pages,
    List<PageBlock> fixedBlocks,
  ) {
    if (fixedBlocks.isEmpty || pages.isEmpty) {
      return pages;
    }
    final overlays = <PageBlockSlice>[
      for (final block in fixedBlocks)
        PageBlockSlice(
          block: block,
          startLine: 0,
          endLine: block.layout.lineCount,
          height: block.height,
          overlay: true,
          absoluteTop:
              block.style
                  ?.resolveAbsoluteBox(
                    containingWidth: contentWidth,
                    containingHeight: baseContentHeight,
                  )
                  ?.top ??
              0,
          leftInset:
              block.style
                  ?.resolveAbsoluteBox(
                    containingWidth: contentWidth,
                    containingHeight: baseContentHeight,
                  )
                  ?.left ??
              0,
        ),
    ];
    return [
      for (final page in pages)
        PageContent(
          spineIndex: page.spineIndex,
          pageIndex: page.pageIndex,
          slices: [...page.slices, ...overlays],
          usedHeight: page.usedHeight,
          pageHeight: page.pageHeight,
          topPadding: page.topPadding,
          background: page.background,
        ),
    ];
  }

  /// 章内图片 src → 包内路径（相对 OPF 的章目录解析）。
  String _chapterImageUrl(int spineIndex, String src) {
    final item = document.spine[spineIndex];
    final chapterBase = p.posix.dirname(
      document.resources.resolve(
            item.href,
            baseDir: p.posix.dirname(document.opfPath),
          ) ??
          item.href,
    );
    return document.resources.resolve(src, baseDir: chapterBase) ?? src;
  }

  /// 图片原始尺寸（与 collect 的预取共用缓存；读不到时返回 null）。
  ImageIntrinsicSize? _intrinsicSizeOfUrl(String url) {
    final cached = _imageIntrinsicCache[url];
    if (cached != null) {
      return cached;
    }
    if (_imageIntrinsicMiss.containsKey(url)) {
      return null;
    }
    final bytes = document.archive.readBytes(url);
    final size = bytes == null ? null : ImageSizeParser.readImageSize(bytes);
    if (size == null) {
      _imageIntrinsicMiss[url] = true;
    } else {
      _imageIntrinsicCache[url] = size;
    }
    return size;
  }

  /// 同目录的 `~slim` 高清封面变体（多看按屏幕比例选择）。
  String? _slimVariantUrl(String url) {
    final slash = url.lastIndexOf('/');
    final dot = url.lastIndexOf('.');
    if (dot <= slash || url.substring(0, dot).endsWith('~slim')) {
      return null;
    }
    return '${url.substring(0, dot)}~slim${url.substring(dot)}';
  }

  /// 全屏页按页面比例在 `a.jpg` 与 `a~slim.jpg` 中取更接近的一张。
  ///
  /// 多看封面常同时提供 4:3 与 16:9 两个版本；若只取主图，竖屏设备会
  /// 出现上下白边，或被迫用 cover 大幅裁边。尺寸读不到时保持原图。
  String _selectFullscreenImage(int spineIndex, String imageSrc) {
    final originalUrl = _chapterImageUrl(spineIndex, imageSrc);
    final slimUrl = _slimVariantUrl(originalUrl);
    if (slimUrl == null) {
      return originalUrl;
    }
    final slimSize = _intrinsicSizeOfUrl(slimUrl);
    if (slimSize == null) {
      return originalUrl;
    }
    final originalSize = _intrinsicSizeOfUrl(originalUrl);
    if (originalSize == null) {
      return slimUrl;
    }
    final pageRatio = contentWidth / math.max(1.0, contentHeight);
    final originalRatio =
        originalSize.width / math.max(1.0, originalSize.height);
    final slimRatio = slimSize.width / math.max(1.0, slimSize.height);
    return (slimRatio - pageRatio).abs() < (originalRatio - pageRatio).abs()
        ? slimUrl
        : originalUrl;
  }

  List<PageContent> _buildFullBleedPages(
    int spineIndex,
    String imageSrc,
    String paginationKey, {
    bool contain = false,
    bool bleed = false,
    String? resolvedImageUrl,
  }) {
    final width = math.max(80.0, contentWidth);
    final height = math.max(120.0, contentHeight);
    final imageUrl = resolvedImageUrl ?? _chapterImageUrl(spineIndex, imageSrc);
    // 整页图铺法：多看全屏页默认 cover（铺满，可能裁边）；`fitwindow`
    // 用 contain 并在页内居中（插图上下居中、不裁切）。
    final blockStyle = ComputedStyle(<String, String>{
      ...baseStyle.values,
      'background-image': 'url($imageUrl)',
      'background-size': contain ? 'contain' : 'cover',
      'background-position': 'center center',
      'background-repeat': 'no-repeat',
    });
    // 整页高的空行块：无 runs（不画字），块盒即整页，背景铺满。
    final layout = TextLayoutResult(
      text: '',
      lines: [
        LineBox(
          start: 0,
          end: 0,
          top: 0,
          height: height,
          baseline: height,
          width: width,
        ),
      ],
      width: width,
      height: height,
      maxWidth: width,
      runs: const <StyledRun>[],
    );
    // 全屏页用出血标记让绘制层横向顶到页面边缘（不看页边距）；
    // 上下同出血，绘制层才能把整页图铺满屏幕（含页眉页脚槽）。
    final block = PageBlock(
      layout: layout,
      style: blockStyle,
      bleedLeft: bleed,
      bleedRight: bleed,
      bleedTop: bleed,
      bleedBottom: bleed,
    );
    final pages = Paginator(pageHeight: height)
        .measureChapter(blocks: [block], spineIndex: spineIndex)
        .pages;
    _pageIndexCache[paginationKey] = PageIndex.from(
      ChapterPagination(
        spineIndex: spineIndex,
        pages: pages,
        pageHeight: height,
        totalHeight: 0,
      ),
      [block],
    ).encode();
    return pages;
  }

  ComputedStyle? _resolvedBaseStyle;

  /// 文本块样式：同一环境复用书籍样式叠加阅读器覆盖的结果。
  ComputedStyle get style => _resolvedBaseStyle ??= _applyCustomFont(
    _overrides.apply(baseStyle, containingWidth: contentWidth),
  );

  /// 字体策略只改字族，标题、表格与行内元素继续保留作者的字号与盒样式。
  ComputedStyle _applyCustomFont(ComputedStyle computed) {
    if (!_overrides.isCustomFont) return computed;
    // CSS 变量在级联后才展开，此时补齐族名映射并保留完整回退链。
    final families = [
      for (final family in computed.fontFamilies)
        _bookFontEngines[family.toLowerCase()] ?? family,
    ];
    if (!_overrides.overrideEmbeddedFonts &&
        families.any(_embeddedFontEngines.contains)) {
      return listEquals(families, computed.fontFamilies)
          ? computed
          : computed.withTypography(fontFamilyList: families);
    }
    return computed.withTypography(fontFamily: _overrides.fontFamily);
  }

  /// 替换原文覆盖；字体度量变更重排，颜色变更保留全部测量缓存。
  @override
  Future<bool> applyTextOverlays(List<ReaderTextOverlay> overlays) async {
    final next = ReaderTextOverlayResolver(overlays, colors: false);
    final previous = _textOverlayResolver.typographyFingerprint;
    final fingerprint = next.typographyFingerprint;
    _textOverlayResolver = next;
    if (previous == fingerprint) return false;
    _layoutGeneration += 1;
    _logInvalidation('textTypographyChanged', previous, fingerprint);
    _pageCache.clear();
    _pageCacheOrder.clear();
    _paginationFontFamilies.clear();
    _pageIndexCache.clear();
    _blockCache.clear();
    _blockCacheOrder.clear();
    return true;
  }

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    final previous = _overrides;
    _overrides = overrides;
    _resolvedBaseStyle = null;
    // 失效矩阵（P7-23）：只有排版字段（字号/行高/对齐/边距）变化才
    // 失效 pagination 层与段落缓存；颜色变化零重排（绘制层即时生效）。
    if (previous.fingerprint != overrides.fingerprint) {
      _layoutGeneration += 1;
      // 只换字族/内嵌字体开关：分页键与段落缓存键都带设置指纹，旧字体的
      // 结果留在缓存里互不干扰，切回同一字体时能直接命中，不再整章重排。
      if (_isFontOnlyChange(previous, overrides)) {
        _logInvalidation(
          'fontFamilyChanged',
          previous.fingerprint,
          overrides.fingerprint,
        );
        return;
      }
      _logInvalidation(
        'configChanged',
        previous.fingerprint,
        overrides.fingerprint,
      );
      _layoutCache.clear();
      _textWidthCache.clear();
      _pageCache.clear();
      _pageCacheOrder.clear();
      _paginationFontFamilies.clear();
      _pageIndexCache.clear();
      _blockCache.clear();
      _blockCacheOrder.clear();
    }
  }

  /// 除字体（字族、内嵌字体开关）外的排版字段是否完全一致。
  static bool _isFontOnlyChange(
    ReaderOverrides previous,
    ReaderOverrides next,
  ) =>
      previous.fontSize == next.fontSize &&
      previous.lineHeight == next.lineHeight &&
      previous.paragraphSpacing == next.paragraphSpacing &&
      previous.textAlign == next.textAlign &&
      previous.padding == next.padding;

  @override
  Future<bool> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
  }) async {
    final nextWidth = math.max(80.0, width);
    final nextHeight = math.max(120.0, height);
    final previousWidth = contentWidth;
    final previousHeight = contentHeight;
    final previousTopInset = _contentTopInset;
    _viewportContentWidth = nextWidth;
    _viewportContentHeight = nextHeight;
    _viewportContentTopInset = math.max(0.0, topInset);
    if (previousWidth == nextWidth &&
        previousHeight == nextHeight &&
        previousTopInset == _contentTopInset) {
      return false;
    }
    _layoutGeneration += 1;
    _resolvedBaseStyle = null;
    // 尺寸变化等同重排：几何进排版键（P7-23 矩阵「几何全失效」）。
    _logInvalidation(
      'viewportSizeChanged',
      '${previousWidth.toString()}x${previousHeight.toString()} top=$previousTopInset',
      '${nextWidth.toString()}x${nextHeight.toString()} top=$_contentTopInset',
    );
    _layoutCache.clear();
    _textWidthCache.clear();
    _pageCache.clear();
    _pageCacheOrder.clear();
    _paginationFontFamilies.clear();
    _pageIndexCache.clear();
    _blockCache.clear();
    _blockCacheOrder.clear();
    _clearDisplayDocumentCache();
    _fullBleedCache.clear();
    return true;
  }

  /// 埋点用的书籍标识（P4-31）；由打开方按需设置。
  String? bookIdForTrace;

  @override
  int get chapterCount => document.spine.length;

  /// 满屏判定缓存（P3-10）：spineIndex → 分析结果；聚合文本含 U+FFFC
  /// 才做深度分析，普通文字章零开销。
  final BoundedCache<int, FullBleedChapter> _fullBleedCache = BoundedCache(
    chapterIndexCacheLimit,
  );

  /// 图片原始尺寸缓存（按解析后 URL，跨章复用）；读取失败记 miss 防
  /// 重复解压。
  final BoundedCache<String, ImageIntrinsicSize> _imageIntrinsicCache =
      BoundedCache(imageIntrinsicCacheLimit);
  final BoundedCache<String, bool> _imageIntrinsicMiss = BoundedCache(
    imageIntrinsicCacheLimit,
  );

  /// 作者样式表缓存：CSS 文件 URL → 解析结果（跨章共享）；章节 → 该章
  /// link 的样式表序列（文档顺序，级联后声明覆盖先声明）。
  final BoundedCache<String, CssStylesheet> _cssSheetCache = BoundedCache(
    cssSheetCacheLimit,
  );
  final BoundedCache<int, List<CssStylesheet>> _chapterSheetCache =
      BoundedCache(chapterIndexCacheLimit);
  final BoundedCache<_CssSheetSetKey, _ChapterCascadePreparation>
  _chapterCascadeCache = BoundedCache(chapterIndexCacheLimit);
  final BoundedCache<_CssSheetSetKey, _ChapterCascadePreparation>
  _baseChapterCascadeCache = BoundedCache(chapterIndexCacheLimit);

  /// 书内字体（P3-01/02 接入 flat 管线）：@font-face 注册器与引擎族名
  /// 映射；族名同时包含实际字形摘要，隔离同 OPF 路径、同标识的不同书。
  BookFontLoader? _fontLoader;
  final Set<String> _fontFacesSeen = <String>{};
  Future<void>? _fontRegistration;
  Set<String>? _bookFontDirectories;

  /// 书内字族 → 引擎族名（键为小写 CSS 族名）。
  ///
  /// [BookFontLoader] 把 `@font-face` 注册成 `bi_<bookId>_<族>`，TextPainter
  /// 只认这个引擎族名；书名 CSS 里的 `font-family: "mm"` 不改写就等于整条
  /// font-face 链路白建（真书：章号被画成缺字方块）。
  final Map<String, String> _bookFontEngines = <String, String>{};
  int _bookFontRevision = 0;
  // local() 别名没有包内字节，不能作为保留内嵌字体的依据。
  final Set<String> _embeddedFontEngines = <String>{};
  final Map<String, FontCoverage> _bookFontCoverages = <String, FontCoverage>{};

  bool _closed = false;
  int _layoutGeneration = 0;

  /// 是否已关闭。
  bool get isClosed => _closed;

  /// 释放章节派生缓存、字体字节与归档内容。
  ///
  /// 阅读页销毁后不再需要本来源；大书原始 ZIP、按需解压条目、三层分页缓存
  /// 和段落布局缓存均在这里同步释放，避免重复进入书籍时内存持续叠加。
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _layoutGeneration += 1;
    _layoutCache.clear();
    _textWidthCache.clear();
    _pageCache.clear();
    _pageCacheOrder.clear();
    _paginationFontFamilies.clear();
    _pageIndexCache.clear();
    _blockCache.clear();
    _blockCacheOrder.clear();
    _clearDisplayDocumentCache();
    _pendingBlockDocument = null;
    _pendingSelectorIndex = null;
    _preservingWhiteSpaceCache.clear();
    _preservedRawTexts.clear();
    _preservedPreLineTexts.clear();
    _fullBleedCache.clear();
    _imageIntrinsicCache.clear();
    _imageIntrinsicMiss.clear();
    _cssSheetCache.clear();
    _chapterSheetCache.clear();
    _chapterCascadeCache.clear();
    _baseChapterCascadeCache.clear();
    _footnoteReferenceCache.clear();
    _fontLoader?.clear();
    _fontFacesSeen.clear();
    _bookFontDirectories = null;
    _bookFontEngines.clear();
    _bookFontRevision = 0;
    _embeddedFontEngines.clear();
    _bookFontCoverages.clear();
    _resolvedBaseStyle = null;
    _plainTextCache.clear();
    _opfPageFlagsCache = null;
    document.archive.close();
  }

  String get _bookId => 'bk-${document.opfPath.hashCode}';

  /// 注册章内 `@font-face`（真实书适配）：书内字体按 face 键去重后
  /// 经 BookFontLoader 注册到引擎；字节解析沿用图片的多路径回退
  /// （直读 → OPF 目录 → 各章节目录）。
  Future<void> _ensureBookFonts(List<CssFontFace> requestedFaces) async {
    // 连续跳章可能同时请求字体；去重标记不等于注册已完成。
    while (_fontRegistration != null) {
      await _fontRegistration!;
    }
    if (_closed) return;
    final faces = requestedFaces;
    if (faces.isEmpty) {
      return;
    }
    final loader = _fontLoader ??= BookFontLoader(
      bookId: _bookId,
      contentAddressed: true,
    );
    // 已注册过 face 的族也要补进映射：先打开的章节声明了 @font-face、
    // 后面章节只用 `font-family` 引用同一族（真书常见），此时 pending 为空。
    _syncBookFontEngines(loader, faces);
    final pending = <CssFontFace>[];
    for (final face in faces) {
      final key =
          '${face.family}|${face.normalizedWeight}|${face.normalizedStyle}';
      if (_fontFacesSeen.add(key)) {
        pending.add(face);
      }
    }
    if (pending.isEmpty) {
      return;
    }
    final registration = loader.load(pending, resolveBytes: _readBookFont).then(
      (_) {
        if (_closed) {
          loader.clear();
        } else {
          _syncBookFontEngines(loader, faces);
        }
      },
    );
    _fontRegistration = registration;
    try {
      await registration;
    } finally {
      if (identical(_fontRegistration, registration)) _fontRegistration = null;
    }
  }

  /// 只返回当前章节 CSS 实际引用的内嵌字族。
  ///
  /// 真实书常在全局样式表声明上百个可选字体，单章只命中其中几种。过去
  /// 首次排版会读取并注册整张字体清单，真机上会额外阻塞超过一秒；这里先
  /// 用已解析的选择器找出命中的字体声明，未命中的 face 等后续章节用到时
  /// 再增量注册。
  List<CssFontFace> _usedBookFonts(
    List<CssStylesheet> sheets,
    _ParsedSelectorIndex selectorIndex,
  ) {
    final faces = <CssFontFace>[for (final sheet in sheets) ...sheet.fontFaces];
    if (faces.isEmpty ||
        (_overrides.isCustomFont && _overrides.overrideEmbeddedFonts)) {
      return const <CssFontFace>[];
    }

    final families = <String>{
      for (final face in faces) face.family.toLowerCase(),
    };
    final wanted = <String>{};

    void inspectDeclarations(List<CssDeclaration> declarations) {
      for (final declaration in declarations) {
        if (declaration.property != 'font' &&
            declaration.property != 'font-family' &&
            !declaration.property.startsWith('--')) {
          continue;
        }
        final value = declaration.value.toLowerCase();
        for (final family in families) {
          if (value.contains(family)) {
            wanted.add(family);
          }
        }
      }
    }

    final prepared = _prepareBaseChapterCascade(sheets);
    bool matches(
      List<SelectorElement> chain,
      Iterable<ComplexSelector> selectors,
    ) {
      final element = chain.last;
      final ancestors = chain.sublist(0, chain.length - 1);
      return selectors.any((selector) => selector.matches(element, ancestors));
    }

    for (final chain in selectorIndex.chains) {
      inspectDeclarations(
        _inlineDeclarationsOf(chain.last.attributes['style']),
      );
      for (final rule in prepared.cascadeRules.candidatesFor(chain.last)) {
        final media = rule.rule.media;
        if (media != null && !Cascade.mediaMatches(media, contentWidth)) {
          continue;
        }
        if (!matches(chain, rule.selectors.selectors)) {
          continue;
        }
        inspectDeclarations(rule.rule.declarations);
      }
      for (final rule in prepared.firstLetterRules) {
        if (matches(chain, rule.selectors.selectors)) {
          inspectDeclarations(rule.declarations);
        }
      }
      for (final rules in prepared.pseudoRules.values) {
        for (final rule in rules) {
          if (matches(chain, rule.selectors.selectors)) {
            inspectDeclarations(rule.declarations);
          }
        }
      }
    }
    return <CssFontFace>[
      for (final face in faces)
        if (wanted.contains(face.family.toLowerCase())) face,
    ];
  }

  Future<Uint8List?> _readBookFont(String url) async {
    if (_closed) return null;
    // 只解析路径，不先读出原字节；所有成功分支统一经过解混淆入口。
    var path = document.archive.contains(url)
        ? url
        : document.resources.resolve(url);
    if (path == null) {
      // 同目录章节只试一次，保留首次出现顺序；缺失字体不逐章重复归一化。
      final directories = _bookFontDirectories ??= {
        for (final item in document.spine) p.posix.dirname(item.href),
      };
      for (final baseDir in directories) {
        path = document.resources.resolve(url, baseDir: baseDir);
        if (path != null) break;
      }
    }
    return path == null ? null : document.readFontBytes('/$path');
  }

  /// 把已注册成功的族收进「CSS 族名 → 引擎族名」映射。
  ///
  /// 只收注册成功的（[BookFontLoader.engineFamily] 非空）：加载失败的族
  /// 保持原样，让 `font-family` 回退链继续生效。
  void _syncBookFontEngines(BookFontLoader loader, List<CssFontFace> faces) {
    final changedFamilies = <String>{};
    void putEngine(String family, String engine) {
      final key = family.toLowerCase();
      final previous = _bookFontEngines[key];
      if (previous == engine) {
        return;
      }
      changedFamilies.add(key);
      _bookFontEngines[key] = engine;
      if (previous != null) {
        _bookFontCoverages.remove(previous);
        _embeddedFontEngines.remove(previous);
      }
    }

    for (final face in faces) {
      final engine = loader.engineFamily(face.family);
      if (engine != null) {
        putEngine(face.family, engine);
        final coverage = loader.coverage(face.family);
        if (coverage != null) {
          _embeddedFontEngines.add(engine);
          _bookFontCoverages[engine] = coverage;
        }
        continue;
      }
      // 只在 `local()` 中声明系统宋体/黑体等的书籍字体没有可嵌入字节。
      // 保留原族名会让引擎把其 cmap 中的 glyph 0 画成黑方块；复用现有
      // 内置字族别名，既贴近浏览器 local() 结果，也能继续按字形回退。
      for (final source in face.sources) {
        final alias = source.isLocal
            ? FontFamilyAliases.resolve(source.ref)
            : null;
        if (alias != null) {
          putEngine(face.family, alias);
          break;
        }
      }
    }
    if (changedFamilies.isNotEmpty) {
      _invalidateBookFontLayouts(changedFamilies);
    }
  }

  /// 只让引用本次新增字族的章节失效。
  ///
  /// 大书会按章增量注册字体；若每次清空全部章节，已读章节回访会重新解析、
  /// 级联和测量。分页键记录了实际引用的书内字族，未引用新字族的章节可以
  /// 安全保留。
  void _invalidateBookFontLayouts(Set<String> changedFamilies) {
    _logInvalidation('fontFacesChanged', 'cached', changedFamilies.join(','));
    _bookFontRevision += 1;
    _layoutCache.clear();
    _textWidthCache.clear();
    _chapterCascadeCache.clear();

    bool affected(String paginationKey) {
      final dependencies = _paginationFontFamilies[paginationKey];
      // 依赖未知时保守失效，避免沿用缺字重的旧布局。
      return dependencies == null || dependencies.any(changedFamilies.contains);
    }

    for (final key in _pageCache.keys.toList(growable: false)) {
      if (!affected(key)) continue;
      _pageCache.remove(key);
      _pageCacheOrder.remove(key);
      _blockCache.remove(key);
      _blockCacheOrder.remove(key);
      _pageIndexCache.remove(key);
      _paginationFontFamilies.remove(key);
    }
  }

  bool _hasBookFontGlyph(String family, int codeUnit) {
    final customCoverage = FontCoverageRegistry.covers(family, codeUnit);
    if (customCoverage != null) return customCoverage;
    final engine = FontFamilyAliases.resolve(family) ?? family;
    final coverage = _bookFontCoverages[family] ?? _bookFontCoverages[engine];
    // 楷体目前没有内置字节，未知的 `builtin_*` 主族不会触发 TextStyle
    // 的逐字回退；显式判缺后可落到已有字族，避免豆腐块。黑体已随应用
    // 注册全量思源黑体，与内置宋体一样交给 TextStyle 回退链处理。
    if (engine == FontFamilyAliases.kai) {
      return coverage?.covers(codeUnit) ?? false;
    }
    return coverage == null || coverage.covers(codeUnit);
  }

  /// 在已解析选择器上替换字体声明，避免字体注册前后重复解析整份 CSS。
  _ChapterCascadePreparation _rewriteBookFontPreparation(
    _ChapterCascadePreparation base,
  ) {
    if (_bookFontEngines.isEmpty) {
      return base;
    }
    _AuxiliaryCssRule rewriteAuxiliary(_AuxiliaryCssRule rule) => (
      selectors: rule.selectors,
      declarations: _rewriteBookFontDeclarations(rule.declarations),
      selectorText: rule.selectorText,
      media: rule.media,
    );
    return _ChapterCascadePreparation(
      auxiliaryRules: List<_AuxiliaryCssRule>.unmodifiable(
        base.auxiliaryRules.map(rewriteAuxiliary),
      ),
      firstLetterRules: List<_AuxiliaryCssRule>.unmodifiable(
        base.firstLetterRules.map(rewriteAuxiliary),
      ),
      pseudoRules: Map<String, List<_AuxiliaryCssRule>>.unmodifiable({
        for (final entry in base.pseudoRules.entries)
          entry.key: List<_AuxiliaryCssRule>.unmodifiable(
            entry.value.map(rewriteAuxiliary),
          ),
      }),
      cascadeRules: CascadeRuleSet([
        for (final rule in base.cascadeRules)
          rule.origin == CascadeOrigin.author
              ? rule.withDeclarations(
                  _rewriteBookFontDeclarations(rule.rule.declarations),
                )
              : rule,
      ]),
    );
  }

  /// 逐条改写声明；未命中时返回原列表（调用方用 identical 判重）。
  List<CssDeclaration> _rewriteBookFontDeclarations(
    List<CssDeclaration> declarations,
  ) {
    if (_bookFontEngines.isEmpty) {
      return declarations;
    }
    var changed = false;
    final rewritten = <CssDeclaration>[];
    for (final declaration in declarations) {
      final shorthand = declaration.property == 'font'
          ? ComputedStyle.parseFontShorthand(declaration.value)
          : null;
      final family =
          shorthand?['font-family'] ??
          (declaration.property == 'font-family' ? declaration.value : null);
      final value = family == null ? null : _rewriteFontFamilyList(family);
      if (family == null || value == family) {
        rewritten.add(declaration);
        continue;
      }
      changed = true;
      // 使用引擎现有简写解析器，保留字重、字号、行高及重置属性。
      for (final entry in (shorthand ?? {'font-family': family}).entries) {
        rewritten.add(
          CssDeclaration(
            property: entry.key,
            value: entry.key == 'font-family' ? value! : entry.value,
            important: declaration.important,
          ),
        );
      }
    }
    return changed ? rewritten : declarations;
  }

  /// 解析作者选择器并建立级联索引。字体注册前后共享这一层。
  _ChapterCascadePreparation _prepareBaseChapterCascade(
    List<CssStylesheet> sheets,
  ) {
    final key = _CssSheetSetKey(sheets, 0);
    return _baseChapterCascadeCache.putIfAbsent(key, () {
      final auxiliaryRules = List<_AuxiliaryCssRule>.unmodifiable(
        _prepareAuxiliaryRules(sheets),
      );
      final firstLetterRules = List<_AuxiliaryCssRule>.unmodifiable(
        _prepareFirstLetterRules(sheets),
      );
      final pseudoRules = Map<String, List<_AuxiliaryCssRule>>.unmodifiable({
        for (final pseudo in ['::before', '::after'])
          pseudo: List<_AuxiliaryCssRule>.unmodifiable(
            _prepareAuxiliaryRules(sheets, pseudo: pseudo),
          ),
      });
      final cascadeRules = CascadeRuleSet([
        // 列表缩进改由列表容器的级联盒计算；UA 的近似 li 缩进会重复叠加。
        for (final rule in uaRules())
          if (!_isUaListIndentRule(rule.rule)) rule,
        for (var i = 0; i < sheets.length; i++)
          ...CascadeRule.fromStylesheet(
            sheets[i],
            origin: CascadeOrigin.author,
            startOrder: 1000 + i * 10000,
          ),
      ]);
      return _ChapterCascadePreparation(
        auxiliaryRules: auxiliaryRules,
        firstLetterRules: firstLetterRules,
        pseudoRules: pseudoRules,
        cascadeRules: cascadeRules,
      );
    });
  }

  /// 同一组作者样式表准备一次；字体增量注册后只替换声明并复用选择器。
  _ChapterCascadePreparation _prepareChapterCascade(
    List<CssStylesheet> sheets,
  ) {
    final base = _prepareBaseChapterCascade(sheets);
    if (_bookFontEngines.isEmpty) {
      return base;
    }
    final key = _CssSheetSetKey(sheets, _bookFontRevision);
    return _chapterCascadeCache.putIfAbsent(
      key,
      () => _rewriteBookFontPreparation(base),
    );
  }

  /// `font-family: "mm", "楷体", serif` → 逐个族名替换为引擎族名。
  String _rewriteFontFamilyList(String value) {
    var changed = false;
    final parts = <String>[];
    for (final raw in value.split(',')) {
      final name = _unquoteFontFamily(raw.trim());
      final engine = _bookFontEngines[name.toLowerCase()];
      if (engine == null) {
        parts.add(raw);
        continue;
      }
      parts.add('"$engine"');
      changed = true;
    }
    return changed ? parts.join(',') : value;
  }

  static String _unquoteFontFamily(String raw) {
    if (raw.length >= 2 &&
        ((raw.startsWith('"') && raw.endsWith('"')) ||
            (raw.startsWith("'") && raw.endsWith("'")))) {
      return raw.substring(1, raw.length - 1);
    }
    return raw;
  }

  List<CssStylesheet> _chapterStylesheets(int spineIndex) {
    final sheets = _chapterSheetCache.putIfAbsent(spineIndex, () {
      final item = document.spine[spineIndex];
      final xhtmlPath =
          document.resources.resolve(
            item.href,
            baseDir: p.posix.dirname(document.opfPath),
          ) ??
          item.href;
      final xhtmlBytes = document.archive.readBytes(xhtmlPath);
      if (xhtmlBytes == null) {
        return const <CssStylesheet>[];
      }
      final sources = CssParser.extractFromXhtml(
        utf8.decode(xhtmlBytes, allowMalformed: true),
      ).sources;
      final loader = CssStylesheetLoader(
        resolveUrl: (url, baseDir) =>
            document.resources.resolve(url, baseDir: baseDir) ?? url,
        prepareInline: (css, baseDir) =>
            _absolutizeSheet(CssParser.parse(css), baseDir),
        readSheet: (url) => _cssSheetCache.putIfAbsent(url, () {
          final bytes = document.archive.readBytes(url);
          if (bytes == null) {
            return const CssStylesheet(rules: [], imports: [], warnings: []);
          }
          return _absolutizeSheet(
            CssParser.parse(utf8.decode(bytes, allowMalformed: true)),
            p.posix.dirname(url),
          );
        }),
      );
      return loader.load(sources, p.posix.dirname(xhtmlPath));
    });
    // 缓存完整来源，在重排时重新判断媒体条件，旋转后不沿用旧视口结果。
    return [
      for (final sheet in sheets)
        if (sheet.mediaConditions.every(
          (media) => Cascade.mediaMatches(media, contentWidth),
        ))
          sheet,
    ];
  }

  /// 章节作者 CSS 是否声明了「保留空白」族的 `white-space`
  /// （pre / pre-wrap / pre-line / break-spaces）。
  ///
  /// 命中才需要第二遍保留模式的聚合（见 [_preservedTexts]），普通书零
  /// 额外开销。
  bool _chapterDeclaresPreservingWhiteSpace(int spineIndex) {
    return _preservingWhiteSpaceCache.putIfAbsent(spineIndex, () {
      for (final sheet in _chapterStylesheets(spineIndex)) {
        for (final rule in sheet.rules) {
          for (final declaration in rule.declarations) {
            if (declaration.property != 'white-space') {
              continue;
            }
            final value = declaration.value.trim().toLowerCase();
            if (value.startsWith('pre') || value.contains('break-spaces')) {
              return true;
            }
          }
        }
      }
      return false;
    });
  }

  /// 再聚合一遍章节（保留原文），返回「源码起止偏移 → 文本节点」。
  ///
  /// [TextAggregator] 一次只能按章级选一种空白模式，作者 CSS 里按选择器
  /// 声明的 `white-space: pre` 族到不了聚合阶段，换行与连续空格会先被
  /// 折叠掉、排版层再也拿不回来。这里对命中章节按保留模式重跑一遍（同
  /// 一份块树，纯字符串处理，不重新解析 XHTML），pre 族块从这份结果里取
  /// 文本，其余块继续用默认折叠结果。
  Map<String, TextContentNode> _preservedTexts(
    int spineIndex,
    CssWhiteSpace whiteSpace, [
    InlineDisplayResolver? inlineDisplay,
  ]) {
    final cache = whiteSpace == CssWhiteSpace.preLine
        ? _preservedPreLineTexts
        : _preservedRawTexts;
    final cached = cache[spineIndex];
    if (cached != null) {
      return cached;
    }
    final result = <String, TextContentNode>{};
    if (_chapterDeclaresPreservingWhiteSpace(spineIndex)) {
      final aggregated = TextAggregator.aggregate(
        document.parseBlocks(spineIndex),
        inlineDisplay: inlineDisplay,
        whiteSpace: whiteSpace == CssWhiteSpace.preLine
            ? CssWhiteSpace.preLine
            : CssWhiteSpace.preWrap,
      );
      void walk(EpubNode node) {
        if (node is TextContentNode) {
          result['${node.start}:${node.end}'] = node;
        } else if (node is BlockNode) {
          for (final child in node.children) {
            walk(child);
          }
        }
      }

      walk(aggregated.root);
    }
    cache[spineIndex] = result;
    return result;
  }

  /// 首字伪元素规则在章级解析一次，避免每个段落重复扫描整份 CSS。
  static List<_AuxiliaryCssRule> _prepareFirstLetterRules(
    List<CssStylesheet> sheets,
  ) {
    const pseudo = '::first-letter';
    final result = <_AuxiliaryCssRule>[];
    for (final sheet in sheets) {
      for (final rule in sheet.rules) {
        for (final raw in rule.selector.split(',')) {
          final selector = raw.trim();
          if (!selector.endsWith(pseudo)) {
            continue;
          }
          final main = selector.substring(0, selector.length - pseudo.length);
          if (main.isEmpty) {
            continue;
          }
          final parsed = SelectorParser.parse(main);
          if (parsed.selectors.isNotEmpty) {
            result.add((
              selectors: parsed,
              declarations: rule.declarations,
              selectorText: main,
              media: rule.media,
            ));
          }
        }
      }
    }
    return result;
  }

  /// 取块排版用的文本节点：pre 族块换成保留原文的同一节点，其余块沿用
  /// 聚合器已折叠的文本（行为与改动前完全一致）。
  TextBlockNode _textNodeFor(
    int spineIndex,
    TextBlockNode node,
    CssWhiteSpace whiteSpace, [
    InlineDisplayResolver? inlineDisplay,
  ]) {
    if (whiteSpace != CssWhiteSpace.pre &&
        whiteSpace != CssWhiteSpace.preWrap &&
        whiteSpace != CssWhiteSpace.preLine) {
      return node;
    }
    if (node is! TextContentNode) {
      return node;
    }
    final texts = _preservedTexts(spineIndex, whiteSpace, inlineDisplay);
    return texts['${node.start}:${node.end}'] ?? node;
  }

  PageBlock? _emptyBoxBlock(
    ComputedStyle style,
    double contentWidth, {
    required double containingHeight,
  }) {
    if (style.display == CssDisplay.none ||
        style.visibility != CssVisibility.visible) {
      return null;
    }
    final hasBackground =
        style.backgroundColor.a > 0 || style.backgroundImage != null;
    final hasBorder = style.borders.hasBorder;
    final hasClearance = style.clear != CssClear.none;
    final declaredHeight = style.height?.resolve(
      contentWidth,
      viewportHeight: containingHeight,
    );
    final declaredMinHeight = style.minHeight?.resolve(
      contentWidth,
      viewportHeight: containingHeight,
    );
    if (!hasBackground &&
        !hasBorder &&
        !hasClearance &&
        (declaredHeight == null || declaredHeight <= 0) &&
        (declaredMinHeight == null || declaredMinHeight <= 0)) {
      return null;
    }
    var contentHeight = declaredHeight ?? 0.0;
    if (declaredMinHeight != null && declaredMinHeight > contentHeight) {
      contentHeight = declaredMinHeight;
    }
    final absoluteBox = style.resolveAbsoluteBox(
      containingWidth: contentWidth,
      containingHeight: containingHeight,
    );
    final model = BoxModel.fromStyle(style, containingWidth: contentWidth);
    final boxWidth =
        absoluteBox?.width ??
        (style.isOutOfFlow ? 0.0 : model.resolveContentWidth(contentWidth));
    return PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: '',
        style: style,
        maxWidth: boxWidth,
        hasGlyph: _hasBookFontGlyph,
      ),
      style: style,
      containingWidth: contentWidth,
      absolute: style.isOutOfFlow,
      absoluteTop: absoluteBox?.top,
      absoluteLeft: absoluteBox?.left,
    );
  }

  /// 相对 URL 需要解析的属性（P9-03）：背景图与列表标记图。
  static const _urlProperties = <String>{
    'background-image',
    'background',
    'border-image',
    'border-image-source',
    'content',
    'list-style-image',
    'list-style',
  };

  static final RegExp _cssUrlPattern = RegExp(r'url\(\s*([^)]*?)\s*\)');

  /// 把样式表里的相对 `url()` 解析成书内绝对路径。
  ///
  /// 级联只保存声明字符串，绘制层用 `imageLookup(url)` 查解码图；不先解析
  /// 的话 `url(../Images/x.jpg)` 与资源索引的键对不上，背景图永远画不出来。
  CssStylesheet _absolutizeSheet(CssStylesheet sheet, String baseDir) {
    if (sheet.rules.isEmpty) {
      return sheet;
    }
    var changed = false;
    final rules = <CssRule>[];
    for (final rule in sheet.rules) {
      var ruleChanged = false;
      final declarations = <CssDeclaration>[];
      for (final declaration in rule.declarations) {
        if (_urlProperties.contains(declaration.property) &&
            declaration.value.contains('url(')) {
          final value = _resolveCssUrls(declaration.value, baseDir);
          if (value != declaration.value) {
            ruleChanged = true;
            changed = true;
            declarations.add(
              CssDeclaration(
                property: declaration.property,
                value: value,
                important: declaration.important,
              ),
            );
            continue;
          }
        }
        declarations.add(declaration);
      }
      rules.add(
        ruleChanged
            ? CssRule(
                selector: rule.selector,
                declarations: List.unmodifiable(declarations),
                media: rule.media,
              )
            : rule,
      );
    }
    if (!changed) {
      return sheet;
    }
    return CssStylesheet(
      rules: List.unmodifiable(rules),
      imports: sheet.imports,
      warnings: sheet.warnings,
      fontFaces: sheet.fontFaces,
    );
  }

  /// 解析声明值里的每个 `url()`；解析不到的资源保持原样。
  String _resolveCssUrls(String value, String baseDir) {
    return value.replaceAllMapped(_cssUrlPattern, (match) {
      var raw = (match.group(1) ?? '').trim();
      if (raw.length >= 2 &&
          ((raw.startsWith('"') && raw.endsWith('"')) ||
              (raw.startsWith("'") && raw.endsWith("'")))) {
        raw = raw.substring(1, raw.length - 1).trim();
      }
      if (raw.isEmpty ||
          raw.startsWith('data:') ||
          raw.startsWith('http://') ||
          raw.startsWith('https://')) {
        return match.group(0) ?? '';
      }
      final resolved = document.resources.resolve(raw, baseDir: baseDir);
      return resolved == null ? (match.group(0) ?? '') : 'url("$resolved")';
    });
  }

  /// 从 body 的级联结果取整页背景；书籍未声明背景图时返回 null。
  ///
  /// 只取 `background-image` 与尺寸/平铺/定位：页面底色仍由阅读主题决定。
  static PageBackground? _pageBackgroundFrom(ComputedStyle style) {
    final url = style.backgroundImage;
    if (url == null || url.isEmpty) {
      return null;
    }
    return PageBackground(
      imageUrl: url,
      size: style.backgroundSize,
      repeat: style.backgroundRepeat,
      position: style.backgroundPosition,
    );
  }

  /// 边框线型名（P8-05c 拼合声明用）。
  static String _borderStyleName(CssBorderStyle value) => switch (value) {
    CssBorderStyle.solid => 'solid',
    CssBorderStyle.dashed => 'dashed',
    CssBorderStyle.dotted => 'dotted',
    CssBorderStyle.double => 'double',
    _ => 'solid',
  };

  /// 颜色转 #RRGGBB（P8-05c 拼合声明用）。
  static String _colorToHex(Color color) {
    return (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  }

  /// 链缓存键（P8-02）：tag#id.class 按链拼接。
  /// 内联 style 属性声明解析（P8-02）：`k:v; k2:v2 !important` →
  /// 引擎 CssDeclaration（参与 inline 源级联）。
  static List<CssDeclaration> _inlineDeclarationsOf(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <CssDeclaration>[];
    }
    final result = <CssDeclaration>[];
    for (final part in raw.split(';')) {
      final colon = part.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      var value = part.substring(colon + 1).trim();
      var important = false;
      if (value.toLowerCase().endsWith('!important')) {
        important = true;
        value = value.substring(0, value.length - '!important'.length).trim();
      }
      final property = part.substring(0, colon).trim().toLowerCase();
      if (property.isNotEmpty &&
          value.isNotEmpty &&
          !property.startsWith('-')) {
        result.add(
          CssDeclaration(
            property: property,
            value: value,
            important: important,
          ),
        );
      }
    }
    return result;
  }

  /// `content` 值求值（W20）：字符串字面量、attr()、counter()/counters()、
  /// open-quote/close-quote、url() 可任意拼接（CSS 2.1 §12.2）。
  /// url() 生成 U+FFFC 占位符，并记录图片在图中的位置。
  static _PseudoContent _evaluateContentValue(
    String raw, {
    required List<SelectorElement> ancestors,
    required CssQuotes quotes,
    required int quoteDepth,
    required String Function(String name, String style) counterValue,
  }) {
    final element = ancestors.isEmpty ? null : ancestors.last;
    (String, String) pairAt(int depth) {
      switch (quotes) {
        case CssQuotesNone():
          return ('', '');
        case CssQuotesPairs(:final pairs):
          final pair = pairs[depth.clamp(0, pairs.length - 1)];
          return (pair.open, pair.close);
        case CssQuotesAuto():
          return depth == 0 ? ('\u201C', '\u201D') : ('\u2018', '\u2019');
      }
    }

    final out = StringBuffer();
    final images = <_PseudoContentImage>[];
    var i = 0;
    while (i < raw.length) {
      final ch = raw[i];
      if (ch == '"' || ch == "'") {
        final end = raw.indexOf(ch, i + 1);
        if (end < 0) {
          break;
        }
        out.write(raw.substring(i + 1, end));
        i = end + 1;
        continue;
      }
      if (ch.trim().isEmpty) {
        i += 1;
        continue;
      }
      final start = i;
      var depth = 0;
      while (i < raw.length) {
        final c = raw[i];
        if (c == '(') {
          depth += 1;
        } else if (c == ')') {
          depth -= 1;
        } else if (depth == 0 && c.trim().isEmpty) {
          break;
        }
        i += 1;
      }
      final token = raw.substring(start, i).trim();
      if (token.isEmpty) {
        continue;
      }
      final lowerToken = token.toLowerCase();
      if (token == 'open-quote') {
        out.write(pairAt(quoteDepth).$1);
      } else if (token == 'close-quote') {
        out.write(pairAt(quoteDepth).$2);
      } else if (token == 'no-open-quote' || token == 'no-close-quote') {
        continue;
      } else if (token.startsWith('attr(') && token.endsWith(')')) {
        final name = token.substring(5, token.length - 1).trim();
        out.write(element?.attributes[name] ?? '');
      } else if (token.startsWith('counter(') && token.endsWith(')')) {
        final args = token
            .substring(8, token.length - 1)
            .split(',')
            .map((part) => part.trim())
            .toList();
        out.write(
          counterValue(args.first, args.length > 1 ? args[1] : 'decimal'),
        );
      } else if (token.startsWith('counters(') && token.endsWith(')')) {
        final args = token
            .substring(9, token.length - 1)
            .split(',')
            .map((part) => part.trim())
            .toList();
        out.write(
          counterValue(args.first, args.length > 2 ? args[2] : 'decimal'),
        );
      } else if (lowerToken.startsWith('url(') && token.endsWith(')')) {
        var url = token.substring(4, token.length - 1).trim();
        if (url.length >= 2 &&
            ((url.startsWith('"') && url.endsWith('"')) ||
                (url.startsWith("'") && url.endsWith("'")))) {
          url = url.substring(1, url.length - 1).trim();
        }
        if (url.isEmpty || url.toLowerCase() == 'none') {
          continue;
        }
        out.write('\uFFFC');
        images.add(_PseudoContentImage(offset: out.length - 1, url: url));
      }
    }
    return _PseudoContent(
      text: out.toString(),
      images: List<_PseudoContentImage>.unmodifiable(images),
    );
  }

  /// `counter(name, upper-alpha)` 之类的字母计数（1 起）。
  static String _alphaCounter(int value) {
    if (value <= 0) {
      return '$value';
    }
    final codes = <int>[];
    var n = value;
    while (n > 0) {
      final rem = (n - 1) % 26;
      codes.add(65 + rem);
      n = (n - 1) ~/ 26;
    }
    return String.fromCharCodes(codes.reversed);
  }

  /// `counter(name, upper-roman)` 的罗马数字（1..3999）。
  static String _romanCounter(int value) {
    if (value <= 0 || value > 3999) {
      return '$value';
    }
    const numerals = <(int, String)>[
      (1000, 'M'),
      (900, 'CM'),
      (500, 'D'),
      (400, 'CD'),
      (100, 'C'),
      (90, 'XC'),
      (50, 'L'),
      (40, 'XL'),
      (10, 'X'),
      (9, 'IX'),
      (5, 'V'),
      (4, 'IV'),
      (1, 'I'),
    ];
    final buffer = StringBuffer();
    var n = value;
    for (final (amount, symbol) in numerals) {
      while (n >= amount) {
        buffer.write(symbol);
        n -= amount;
      }
    }
    return buffer.toString();
  }

  /// 首字符 run：合并作者 `::first-letter` 声明与 `initial-letter` 的首字
  /// 下沉语义，借用行内 run 机制放大首字并撑高首行。
  StyledRun? _firstLetterRun(
    List<_AuxiliaryCssRule> rules,
    List<SelectorElement> ancestors,
    String text,
    ComputedStyle baseStyle, {
    bool sizeInitialLetter = true,
  }) {
    if (ancestors.isEmpty || text.isEmpty) {
      return null;
    }
    final declarations = <String, String>{};
    final parents = ancestors.sublist(0, ancestors.length - 1);
    for (final rule in rules) {
      final media = rule.media;
      if (media != null && !Cascade.mediaMatches(media, contentWidth)) {
        continue;
      }
      var matched = false;
      for (final selector in rule.selectors.selectors) {
        if (selector.matches(ancestors.last, parents)) {
          matched = true;
          break;
        }
      }
      if (matched) {
        for (final declaration in rule.declarations) {
          declarations[declaration.property] = declaration.value;
        }
      }
    }
    final initialLetterLines = baseStyle.initialLetterLines;
    final hasInitialLetter =
        initialLetterLines != null && initialLetterLines > 0;
    if (sizeInitialLetter && hasInitialLetter) {
      // `initial-letter: n` 的首值表示占用 n 行；用绝对行高让首行精确
      // 让出 n 倍正文行距。两值写法的下沉行数暂按首值近似。
      final extent = baseStyle.lineHeight * initialLetterLines;
      // 字形实际墨高可能大于 line-height；略收小字号，避免字体度量的
      // ascent+descent 把浮动盒撑过 n 行、多挤掉一行正文。
      declarations.putIfAbsent('font-size', () => '${extent * 0.85}px');
      declarations.putIfAbsent('line-height', () => '${extent}px');
    }
    if (declarations.isEmpty && !hasInitialLetter) {
      return null;
    }
    // 首字符 = 首个非空白字符。
    var start = 0;
    while (start < text.length && _isWhitespace(text.codeUnitAt(start))) {
      start += 1;
    }
    if (start >= text.length) {
      return null;
    }
    return StyledRun(
      start: start,
      end: start + 1,
      style: ComputedStyle(
        declarations,
        parent: baseStyle,
        explicitProperties: declarations.keys.toSet(),
        containingWidth: contentWidth,
        rootFontSize: baseStyle.fontSize,
      ),
    );
  }

  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D;

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  static String _chainKey(
    List<SelectorElement> chain,
    Map<SelectorElement, String> viewKeys,
    CascadeRuleSet rules,
  ) => chain
      .map(
        (view) => viewKeys.putIfAbsent(view, () {
          final attrKeys = view.attributes.keys.toList()..sort();
          final attrs = [
            for (final key in attrKeys) '$key=${view.attributes[key]}',
          ].join(';');
          final identity =
              view is _NodeView && rules.candidatesFor(view).usesTreePosition
              ? view.cacheIdentity
              : '';
          return '${view.tag}|$attrs|$identity';
        }),
      )
      .join('>');

  /// 浮动分页会把一段拆为多个块，仍保留容器真实首末标记供装饰占位使用。
  static List<PageContainerFragment> _containerFragmentsFor(
    PageBlock block, {
    required bool starts,
    required bool ends,
  }) => [
    for (final fragment in block.containers)
      PageContainerFragment(
        container: fragment.container,
        startsHere: starts && fragment.startsHere,
        endsHere: ends && fragment.endsHere,
        topInset: fragment.topInset,
        bottomInset: fragment.bottomInset,
      ),
  ];

  /// 有块级后代的普通容器保留盒结构，浮动和特殊排版仍走各自路径。
  static bool _retainsContainer(BlockNode node, ComputedStyle style) {
    const tags = {
      'div',
      'section',
      'article',
      'aside',
      'main',
      'header',
      'footer',
      'blockquote',
      'figure',
    };
    final splitInlineFlow =
        node is PromotedBlockNode ||
        node.children.any((child) => child is PromotedBlockNode);
    return (tags.contains(node.tag) || splitInlineFlow) &&
        node.children.any((child) => child is BlockNode) &&
        style.cssFloat == CssFloat.none &&
        style.position == CssPosition.static &&
        style.writingMode == CssWritingMode.horizontalTb;
  }

  /// 页面根 `flex-direction: column` 的主轴居中。
  ///
  /// flat 管线没有完整 Flex 布局；这里只补页面根最常见的
  /// `min-height: 100vh + justify-content: center` 版权页/扉页。用空白
  /// 垫片推进正文流，保留所有后代块的 CFI、容器装饰与注释偏移。
  static void _alignPageRootFlexColumn({
    required List<PageBlock> blocks,
    required int start,
    required ComputedStyle containerStyle,
    required double pageWidth,
    required double pageHeight,
  }) {
    if (start >= blocks.length) {
      return;
    }
    final align = containerStyle.justifyContent;
    if (align != CssJustifyContent.center &&
        align != CssJustifyContent.flexEnd) {
      return;
    }
    var naturalHeight = 0.0;
    for (final block in blocks.skip(start)) {
      if (block.absolute || block.floatSide != null) {
        continue;
      }
      naturalHeight +=
          block.leadingExtent + block.height + block.trailingExtent;
    }
    final model = BoxModel.fromStyle(
      containerStyle,
      containingWidth: pageWidth,
    );
    final availableHeight = math.max(0.0, pageHeight - model.verticalInset);
    final declaredHeight = math.min(
      model.resolveContentHeight(naturalHeight, containingHeight: pageHeight),
      availableHeight,
    );
    final free = math.max(0.0, declaredHeight - naturalHeight);
    final offset =
        model.padding.top +
        model.borders.top +
        (align == CssJustifyContent.center ? free / 2 : free);
    if (offset <= 0.01) {
      return;
    }
    blocks.insert(
      start,
      PageBlock(
        layout: TextLayoutResult(
          text: '',
          lines: [
            LineBox(
              start: 0,
              end: 0,
              top: 0,
              height: offset,
              baseline: offset,
              width: pageWidth,
            ),
          ],
          width: pageWidth,
          height: offset,
          maxWidth: pageWidth,
          runs: const <StyledRun>[],
        ),
      ),
    );
  }

  /// 单行/换行 Flex 容器：在 flat 管线内排行内主轴位置，不引入完整 Flex 算法。
  ///
  /// 每个直接子项映射成表格单元格载荷，复用其文本、背景图、边框和垂直
  /// 对齐绘制。支持 `flex-wrap: wrap/wrap-reverse` 的按行分组；
  /// `flex-direction: column` 与 `align-content` 仍走原块流/起点近似。
  static PageBlock? _flexRowBlock({
    required ComputedStyle containerStyle,
    required double containerWidth,
    required List<List<PageBlock>> items,
    required double containingWidth,
    required double pageContentHeight,
    int groupId = 0,
  }) {
    final members = <PageBlock>[
      for (final item in items)
        for (final block in item) block,
    ];
    if (members.isEmpty) {
      return null;
    }

    double horizontalInset(PageBlock block) {
      final style = block.style;
      if (style == null) {
        return 0;
      }
      return style.padding.horizontal +
          style.borders.left.width +
          style.borders.right.width;
    }

    // Flex 子项未声明 width 时按内容收缩，不能沿用块流测出的整行可用宽。
    double intrinsicContentWidth(
      PageBlock block, {
      bool ignoreDeclaredWidth = false,
    }) {
      final available = block.layout.maxWidth.isFinite
          ? block.layout.maxWidth
          : block.layout.width;
      final style = block.style;
      if (!ignoreDeclaredWidth && style?.width != null) {
        return BoxModel.fromStyle(
          style!,
          containingWidth: containingWidth,
        ).resolveContentWidth(containerWidth);
      }
      if (block.table != null) {
        return available;
      }
      final measured = block.layout.width;
      return measured.isFinite && measured > 0
          ? math.min(measured, available)
          : available;
    }

    // flex-basis 优先于 width；border-box 的基准含 padding/border。
    double flexBaseWidth(PageBlock block) {
      final style = block.style;
      final basis = style?.flexBasis;
      if (style?.flexBasisIsContent ?? false) {
        return intrinsicContentWidth(block, ignoreDeclaredWidth: true) +
            horizontalInset(block);
      }
      if (style != null && basis != null && !basis.isAuto) {
        final resolved = basis.resolve(containerWidth);
        if (resolved != null) {
          final inset = horizontalInset(block);
          return math.max(
            0,
            style.boxSizing == CssBoxSizing.borderBox
                ? resolved
                : resolved + inset,
          );
        }
      }
      return intrinsicContentWidth(block) + horizontalInset(block);
    }

    final itemWidths = <double>[];
    final itemHeights = <double>[];
    for (final item in items) {
      var width = 0.0;
      var height = 0.0;
      for (final block in item) {
        width = math.max(width, flexBaseWidth(block));
        height +=
            block.spaceBefore +
            block.topInset +
            block.height +
            block.bottomInset +
            block.spaceAfter;
      }
      itemWidths.add(width);
      itemHeights.add(height);
    }

    final gap = math.max(0.0, containerStyle.columnGap ?? 0.0);
    final wraps = containerStyle.flexWrap != CssFlexWrap.nowrap;
    var rows = <List<int>>[];
    if (wraps) {
      var row = <int>[];
      var rowWidth = 0.0;
      for (var i = 0; i < items.length; i++) {
        final nextWidth = row.isEmpty
            ? itemWidths[i]
            : rowWidth + gap + itemWidths[i];
        if (row.isNotEmpty && nextWidth > containerWidth + 0.5) {
          rows.add(row);
          row = <int>[];
          rowWidth = itemWidths[i];
        } else {
          rowWidth = nextWidth;
        }
        row.add(i);
      }
      if (row.isNotEmpty) {
        rows.add(row);
      }
    } else {
      rows.add(List<int>.generate(items.length, (index) => index));
    }
    if (containerStyle.flexWrap == CssFlexWrap.wrapReverse) {
      rows = rows.reversed.toList();
    }

    // 每行先按 flex-basis 分组，再分配正/负剩余空间。收缩权重按规范取
    // flex-shrink × 基准尺寸，避免所有子项被无条件等分压缩。
    for (final row in rows) {
      final baseTotal =
          row.fold(0.0, (sum, index) => sum + itemWidths[index]) +
          gap * math.max(0, row.length - 1);
      final free = containerWidth - baseTotal;
      if (free > 0) {
        final totalGrow = row.fold(
          0.0,
          (sum, index) => sum + (items[index].first.style?.flexGrow ?? 0),
        );
        if (totalGrow > 0) {
          for (final index in row) {
            final grow = items[index].first.style?.flexGrow ?? 0;
            itemWidths[index] += free * grow / totalGrow;
          }
        }
      } else if (free < 0) {
        final shrinkWeights = <int, double>{
          for (final index in row)
            index:
                (items[index].first.style?.flexShrink ?? 1) * itemWidths[index],
        };
        final totalWeight = shrinkWeights.values.fold(0.0, (a, b) => a + b);
        if (totalWeight > 0) {
          for (final index in row) {
            final reduction = -free * shrinkWeights[index]! / totalWeight;
            itemWidths[index] = math.max(0, itemWidths[index] - reduction);
          }
        }
      }
    }

    final rowHeights = [
      for (final row in rows)
        row.fold(0.0, (height, index) => math.max(height, itemHeights[index])),
    ];
    final rowGap = wraps && rows.length > 1
        ? math.max(0.0, containerStyle.rowGap ?? 0.0)
        : 0.0;
    final naturalHeight =
        rowHeights.fold(0.0, (sum, height) => sum + height) +
        rowGap * math.max(0, rows.length - 1);
    final declaredHeight = BoxModel.fromStyle(
      containerStyle,
      containingWidth: containingWidth,
    ).resolveContentHeight(naturalHeight, containingHeight: pageContentHeight);
    final layoutHeight = math.max(declaredHeight, naturalHeight);
    if (!wraps) {
      // 单行 Flex 的交叉轴可用高仍是容器声明高，align-items 以此为基准。
      rowHeights[0] = math.max(rowHeights[0], declaredHeight);
    }

    final freeCross = math.max(0.0, layoutHeight - naturalHeight);
    var contentOffset = 0.0;
    var lineGap = rowGap;
    if (wraps && rows.length > 1) {
      switch (containerStyle.alignContent) {
        case CssAlignContent.stretch:
          final extra = freeCross / rows.length;
          for (var i = 0; i < rowHeights.length; i++) {
            rowHeights[i] += extra;
          }
          break;
        case CssAlignContent.flexEnd:
          contentOffset = containerStyle.flexWrap == CssFlexWrap.wrapReverse
              ? 0
              : freeCross;
          break;
        case CssAlignContent.center:
          contentOffset = freeCross / 2;
          break;
        case CssAlignContent.spaceBetween:
          lineGap += freeCross / (rows.length - 1);
          break;
        case CssAlignContent.spaceAround:
          final extra = freeCross / rows.length;
          contentOffset = extra / 2;
          lineGap += extra;
          break;
        case CssAlignContent.spaceEvenly:
          final extra = freeCross / (rows.length + 1);
          contentOffset = extra;
          lineGap += extra;
          break;
        case CssAlignContent.flexStart:
          contentOffset = containerStyle.flexWrap == CssFlexWrap.wrapReverse
              ? freeCross
              : 0;
          break;
      }
    }
    final rowTops = <double>[];
    var rowTop = contentOffset;
    for (var i = 0; i < rowHeights.length; i++) {
      rowTops.add(rowTop);
      rowTop += rowHeights[i];
      if (i + 1 < rowHeights.length) {
        rowTop += lineGap;
      }
    }

    final cells = <TableCellRender>[];
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final rowHeight = rowHeights[rowIndex];
      final itemsWidth =
          row.fold(0.0, (sum, index) => sum + itemWidths[index]) +
          gap * math.max(0, row.length - 1);
      final free = math.max(0.0, containerWidth - itemsWidth);
      var cursor = switch (containerStyle.justifyContent) {
        CssJustifyContent.flexEnd => free,
        CssJustifyContent.center => free / 2,
        _ => 0.0,
      };
      final distributedGap = switch (containerStyle.justifyContent) {
        CssJustifyContent.spaceBetween when row.length > 1 =>
          free / (row.length - 1),
        CssJustifyContent.spaceAround when row.isNotEmpty => free / row.length,
        CssJustifyContent.spaceEvenly => free / (row.length + 1),
        _ => 0.0,
      };
      if (containerStyle.justifyContent == CssJustifyContent.spaceAround) {
        cursor = distributedGap / 2;
      } else if (containerStyle.justifyContent ==
          CssJustifyContent.spaceEvenly) {
        cursor = distributedGap;
      }
      for (final itemIndex in row) {
        final item = items[itemIndex];
        final itemWidth = itemWidths[itemIndex];
        final itemHeight = itemHeights[itemIndex];
        final crossOffset = switch (containerStyle.alignItems) {
          CssAlignItems.flexEnd => math.max(0.0, rowHeight - itemHeight),
          CssAlignItems.center => math.max(0.0, (rowHeight - itemHeight) / 2),
          _ => 0.0,
        };
        var itemY = rowTops[rowIndex] + crossOffset;
        final itemContainer = _commonFlexItemContainer(item);
        if (itemContainer != null) {
          cells.add(
            TableCellRender(
              row: rowIndex,
              rect: Rect.fromLTWH(
                cursor,
                itemY,
                math.min(itemWidth, containerWidth),
                itemHeight,
              ),
              layout: TextLayoutEngine.layout(
                text: '',
                style: itemContainer.style,
                maxWidth: itemWidth,
              ),
              style: itemContainer.style,
            ),
          );
        }
        for (final block in item) {
          final style = block.style ?? containerStyle;
          itemY += block.spaceBefore;
          final declaredWidth = style.width?.resolve(itemWidth);
          final ownWidth = item.length > 1 && declaredWidth != null
              ? math.min(
                  itemWidth,
                  BoxModel.fromStyle(
                    style,
                    containingWidth: itemWidth,
                  ).borderBoxWidth(declaredWidth),
                )
              : itemWidth;
          final cellLeft =
              cursor +
              switch (style.resolvedTextAlign) {
                CssTextAlign.center => (itemWidth - ownWidth) / 2,
                CssTextAlign.end || CssTextAlign.right => itemWidth - ownWidth,
                _ => 0.0,
              };
          final borderHeight =
              block.topInset + block.height + block.bottomInset;
          cells.add(
            TableCellRender(
              row: rowIndex,
              rect: Rect.fromLTWH(
                cellLeft,
                itemY,
                math.min(ownWidth, containerWidth),
                borderHeight,
              ),
              layout: block.layout,
              style: style,
              startCfi: block.startCfi,
            ),
          );
          itemY += borderHeight + block.spaceAfter;
        }
        cursor += itemWidth + gap + distributedGap;
      }
    }

    final text = members.map((block) => block.layout.text).join();
    final layout = TextLayoutResult(
      text: text,
      lines: [
        LineBox(
          start: 0,
          end: text.length,
          top: 0,
          height: layoutHeight,
          baseline: layoutHeight,
          width: containerWidth,
        ),
      ],
      width: containerWidth,
      height: layoutHeight,
      maxWidth: containerWidth,
      runs: const <StyledRun>[],
    );
    final flexRow = PageBlock.styled(
      layout: layout,
      style: containerStyle,
      containingWidth: containingWidth,
      groupId: groupId,
      startCfi: members.first.startCfi,
      endCfi: members.last.endCfi,
      table: TableRenderSpec(
        cells: cells,
        columnXs: const <double>[0],
        rowYs: <double>[...rowTops, rowTop],
        tableWidth: containerWidth,
        flex: true,
      ),
      declaredContentHeight: layoutHeight,
    );
    return flexRow;
  }

  /// Flex 直接子项的公共盒。卡片类容器在 `_wrapContainerBlocks` 后
  /// 会挂到每个后代块上，取所有成员的共同前缀即可还原该子项背景。
  static PageContainer? _commonFlexItemContainer(List<PageBlock> item) {
    if (item.isEmpty || item.first.containers.isEmpty) {
      return null;
    }
    var count = item.first.containers.length;
    for (final block in item.skip(1)) {
      count = math.min(count, block.containers.length);
      for (var index = 0; index < count; index += 1) {
        if (!identical(
          block.containers[index].container,
          item.first.containers[index].container,
        )) {
          count = index;
          break;
        }
      }
      if (count == 0) {
        return null;
      }
    }
    return item.first.containers.first.container;
  }

  /// 横排分页默认闭合带框容器；作者的显式 slice 优先。
  static bool _clonesContainerDecoration(ComputedStyle style) {
    final value =
        (style.values['box-decoration-break'] ??
                style.values['-webkit-box-decoration-break'])
            ?.trim()
            .toLowerCase();
    if (value == 'slice') return false;
    return value == 'clone' || style.borders.hasBorder;
  }

  /// 卡片开头的短标题跟随至少一行正文，不把整个长卡片锁为不可分组。
  static bool _isContainerHeading(PageBlock block) {
    if (block.absolute || block.floatSide != null) return false;
    final table = block.table;
    if (table != null) {
      return table.rowYs.length == 2 &&
          table.cells.isNotEmpty &&
          table.cells.every((cell) => cell.layout.lineCount <= 2);
    }
    final hasText =
        block.layout.text.trim().isNotEmpty ||
        block.layout.lines.any(
          (line) => line.inlineBoxes.any((box) {
            final payload = box.spec.payload;
            return payload is PageBlock &&
                payload.layout.text.trim().isNotEmpty;
          }),
        );
    return hasText && block.layout.lineCount > 0 && block.layout.lineCount <= 2;
  }

  /// 竖排和分栏尚未按各自分页轴预留续框空间，仍保持切片语义。
  static List<PageBlock> _configureContainerDecoration(List<PageBlock> blocks) {
    bool specialStyle(ComputedStyle? style) =>
        style != null &&
        (style.writingMode != CssWritingMode.horizontalTb ||
            (style.columnCount ?? 1) > 1 ||
            (style.columnWidth != null && !style.columnWidth!.isAuto));
    final special = blocks.any(
      (block) =>
          specialStyle(block.style) ||
          block.containers.any((f) => specialStyle(f.container.style)),
    );
    if (!special) return blocks;
    final replacements = <PageContainer, PageContainer>{};
    PageContainer sliced(PageContainer box) => replacements.putIfAbsent(
      box,
      () => PageContainer(
        style: box.style,
        left: box.left,
        width: box.width,
        isPageRoot: box.isPageRoot,
      ),
    );
    return [
      for (final block in blocks)
        if (block.containers.isEmpty)
          block
        else
          block.withSpacing(
            containers: [
              for (final fragment in block.containers)
                PageContainerFragment(
                  container: sliced(fragment.container),
                  startsHere: fragment.startsHere,
                  endsHere: fragment.endsHere,
                  topInset: fragment.topInset,
                  bottomInset: fragment.bottomInset,
                ),
            ],
          ),
    ];
  }

  /// 辅助属性仅匹配相关规则；选择器在章级解析一次，正文段落直接复用。
  static List<_AuxiliaryCssRule> _prepareAuxiliaryRules(
    List<CssStylesheet> sheets, {
    String? pseudo,
  }) {
    const rawProperties = {
      'counter-reset',
      'counter-increment',
      'object-fit',
      'object-position',
    };
    final result = <_AuxiliaryCssRule>[];
    for (final sheet in sheets) {
      for (final rule in sheet.rules) {
        if (!rule.declarations.any(
          (declaration) => pseudo == null
              ? rawProperties.contains(declaration.property)
              : declaration.property == 'content',
        )) {
          continue;
        }
        if (pseudo == null && rule.selector.contains('::')) continue;
        for (final raw in rule.selector.split(',')) {
          var selector = raw.trim();
          if (pseudo != null) {
            if (!selector.endsWith(pseudo)) continue;
            selector = selector.substring(0, selector.length - pseudo.length);
          }
          if (selector.isEmpty) continue;
          final parsed = SelectorParser.parse(selector);
          if (parsed.selectors.isNotEmpty) {
            result.add((
              selectors: parsed,
              declarations: rule.declarations,
              selectorText: selector,
              media: rule.media,
            ));
          }
        }
      }
    }
    return result;
  }

  /// 把容器的垂直占位和独立绘制片段挂到首末后代，不改变原文/CFI。
  static void _wrapContainerBlocks(
    List<PageBlock> blocks,
    int start,
    PageContainer container, {
    double? paragraphSpacing,
  }) {
    if (start == blocks.length) return;
    final style = container.style;
    final top = style.padding.top + style.borders.top.width;
    final bottom = style.padding.bottom + style.borders.bottom.width;
    // 含浮动的容器，上内边距必须先作为独立在流空间推进游标。若直接
    // 挂在首个在流块上，浮动仍按填充前的游标定位，后续浮动（气泡）
    // 又会把整段内边距计入静态位置，消息间距会被放大。
    final hasFloatChild = blocks
        .skip(start)
        .any((block) => block.floatSide != null);
    final hasTopSpacer = hasFloatChild && top > 0;
    if (hasTopSpacer) {
      blocks.insert(
        start,
        PageBlock(
          layout: TextLayoutResult(
            text: '',
            lines: const <LineBox>[],
            width: container.contentWidth,
            height: top,
            maxWidth: container.contentWidth,
            runs: const <StyledRun>[],
          ),
          containers: <PageContainerFragment>[
            PageContainerFragment(container: container, startsHere: true),
          ],
        ),
      );
      start += 1;
    }
    // 容器上内边距必须落在第一个在流块上：浮动块由独立覆盖层绘制，
    // 把顶部留白挂在浮动上只会推移覆盖层，不会推进正文游标，标题/名字
    // 会和头像错位。下内边距同理优先交给最后一个在流块。
    var topTarget = start;
    for (var i = start; i < blocks.length; i++) {
      if (blocks[i].floatSide == null && !blocks[i].absolute) {
        topTarget = i;
        break;
      }
    }
    var bottomTarget = start;
    for (var i = blocks.length - 1; i >= start; i--) {
      if (blocks[i].floatSide == null && !blocks[i].absolute) {
        bottomTarget = i;
        break;
      }
    }
    // 无上边框/内边距的块容器与首个在流子块发生外边距折叠：父、子 margin
    // 取较大者，而不是相加。保留在 spaceBefore 上还能继续与外层折叠。
    final containerCollapses =
        paragraphSpacing == null && _containerCollapsesMargins(style);
    final collapseTop = top == 0 && containerCollapses;
    final collapseBottom = bottom == 0 && containerCollapses;
    for (var i = start; i < blocks.length; i++) {
      final block = blocks[i];
      final first = i == start;
      final last = i == blocks.length - 1;
      blocks[i] = block.withSpacing(
        breakAfterAvoid:
            block.breakAfterAvoid ||
            (first && !last && _isContainerHeading(block)),
        spaceBefore: first && collapseTop
            ? collapseMargins(style.margin.top, block.spaceBefore)
            : block.spaceBefore,
        spaceAfter: last && collapseBottom
            ? collapseMargins(block.spaceAfter, style.margin.bottom)
            : block.spaceAfter,
        topInset:
            block.topInset +
            (i == topTarget
                ? (hasTopSpacer ? 0 : top) +
                      (collapseTop ? 0 : (paragraphSpacing ?? style.margin.top))
                : 0),
        bottomInset:
            block.bottomInset +
            (i == bottomTarget
                ? bottom +
                      (collapseBottom
                          ? 0
                          : (paragraphSpacing ?? style.margin.bottom))
                : 0),
        containers: [
          PageContainerFragment(
            container: container,
            startsHere: first && !hasTopSpacer,
            endsHere: last,
            topInset: first && !hasTopSpacer ? block.leadingExtent + top : 0,
            bottomInset: last ? block.trailingExtent + bottom : 0,
          ),
          ...block.containers,
        ],
      );
    }
  }

  /// 容器是否可与首个/末个在流子块折叠上下外边距。
  ///
  /// 建立独立块格式化上下文的盒子（浮动、定位、非 visible overflow、
  /// inline-block/table/flex 等）不折叠；普通 block/list-item 才折叠。
  static bool _containerCollapsesMargins(ComputedStyle style) {
    final blockLevel =
        style.display == CssDisplay.block ||
        style.display == CssDisplay.listItem;
    return blockLevel &&
        style.cssFloat == CssFloat.none &&
        style.position != CssPosition.absolute &&
        style.position != CssPosition.fixed &&
        style.overflow == CssOverflow.visible;
  }

  /// 祖先传导的盒类近似属性：flat 无嵌套盒子，容器面板（背景/左右
  /// 边框/左右内边距）由后代块拼合呈现（P3-30 marginBox 路径消费）。
  static const _promotedBoxProps = <String>{
    // P9-22：容器上的 duokan-bleed 要传导到子块（横幅图出血）。
    'duokan-bleed', '-duokan-bleed',
    // 水平内缩不在这里传导：容器的 padding/margin 由 extraLeft/extraRight
    // 累加进子块 margin（见下方循环），两边都做会重复计算（P9-27）。
    'background-color', 'border-left', 'border-right',
    // P9-03：容器的背景图与尺寸/平铺/定位一并透传，卡片纹理不再丢失。
    'background-image', 'background-size', 'background-position',
    'background-repeat', 'background-origin', 'background-clip',
  };

  /// 标题标签族：阅读器字号/行高覆盖不作用于标题（标题排版跟随书籍
  /// 样式族，段距也保留自身间距）。
  static const _headingTags = <String>{'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

  /// 书籍常用带色条/居中样式表示标题，而不是语义 `h1..h6`。
  static bool _hasStructuredTitleStyle(ComputedStyle style) =>
      style.textAlign == CssTextAlign.center ||
      style.borders.hasBorder ||
      style.padding.horizontal > 0;

  /// 含行内图片占位符的短段落是图文正文，不按纯文字标题处理。
  static bool _hasStructuredTitleText(String text, ComputedStyle style) =>
      !text.contains('\uFFFC') &&
      text.trim().length <= 40 &&
      _hasStructuredTitleStyle(style);

  /// 短且带明显视觉结构的块标题，避免只身留在页底。
  static bool _isStructuredHeading({
    required String tag,
    required ComputedStyle style,
    required String text,
    required int lineCount,
  }) {
    final compact = text.trim();
    return !_headingTags.contains(tag) &&
        lineCount > 0 &&
        lineCount <= 2 &&
        compact.isNotEmpty &&
        _hasStructuredTitleText(text, style);
  }

  /// CJK 与全角字符通常可在相邻字符之间断行。
  static bool _isCjkBreakRune(int rune) =>
      (rune >= 0x2E80 && rune <= 0x303F) ||
      (rune >= 0x3040 && rune <= 0x30FF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xAC00 && rune <= 0xD7AF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0xFF00 && rune <= 0xFFEF) ||
      (rune >= 0x1F000 && rune <= 0x1FAFF);

  /// min-content 的近似：中文逐字可断，拉丁词保持完整。
  double _minContentTextWidth({
    required String text,
    required bool breakEverywhere,
    required ComputedStyle style,
  }) {
    final segments = <String>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      segments.add(buffer.toString());
      buffer.clear();
    }

    for (final rune in text.runes) {
      if (rune == 0x09 || rune == 0x0A || rune == 0x0D || rune == 0x20) {
        flush();
        continue;
      }
      if (breakEverywhere || _isCjkBreakRune(rune)) {
        flush();
        segments.add(String.fromCharCode(rune));
        continue;
      }
      buffer.writeCharCode(rune);
    }
    flush();
    final missing = <String>{
      for (final segment in segments)
        if (!_textWidthCache.containsKey(_textWidthKey(segment, style)))
          segment,
    };
    for (final entry in TextLayoutEngine.measureTextWidths(
      texts: missing,
      style: style,
      hasGlyph: _hasBookFontGlyph,
    ).entries) {
      _textWidthCache[_textWidthKey(entry.key, style)] = entry.value;
    }
    return segments.fold<double>(
      0,
      (widest, segment) =>
          math.max(widest, _textWidthCache[_textWidthKey(segment, style)] ?? 0),
    );
  }

  String _textWidthKey(String text, ComputedStyle style) =>
      '$_bookFontRevision|${style.layoutFingerprint}\u0000$text';

  /// 图片显示尺寸（P9-08）：书籍 CSS 的 `width/height` 优先（px/%/em），
  /// 其次 HTML `width/height` 属性，缺边按原始宽高比补齐；都没有时按全宽
  /// 近似。高超出页高时钳制（contain 绘制不变形）。
  (double, double) _resolveImageDisplaySize(
    Map<String, String> attributes,
    ImageIntrinsicSize? intrinsic,
    double maxWidth,
    double maxHeight, {
    double? cssWidth,
    double? cssHeight,
    double? cssMaxWidth,
    double? cssMaxHeight,
    double? aspectRatio,
  }) {
    final widthLimit = cssMaxWidth == null
        ? maxWidth
        : math.min(maxWidth, cssMaxWidth);
    final heightLimit = cssMaxHeight == null
        ? maxHeight
        : math.min(maxHeight, cssMaxHeight);
    double? parseLength(String? raw, double percentBase) {
      if (raw == null) {
        return null;
      }
      final value = raw.trim();
      if (value.isEmpty) {
        return null;
      }
      if (value.endsWith('%')) {
        final pct = double.tryParse(value.substring(0, value.length - 1));
        if (pct == null) {
          return null;
        }
        return percentBase * pct / 100;
      }
      return double.tryParse(value.replaceAll('px', '').trim());
    }

    var width = cssWidth ?? parseLength(attributes['width'], maxWidth);
    var height = cssHeight ?? parseLength(attributes['height'], maxHeight);
    if (width != null && width > widthLimit) {
      width = widthLimit;
    }
    if (height != null && height > heightLimit) {
      height = heightLimit;
    }
    if (width == null && height == null) {
      if (intrinsic == null && aspectRatio == null) {
        return (widthLimit, heightLimit * 0.6);
      }
      width = widthLimit;
    }
    if (width != null && height == null) {
      if (aspectRatio != null) {
        height = width / aspectRatio;
      } else if (intrinsic != null) {
        height = width * intrinsic.height / intrinsic.width;
      }
    } else if (height != null && width == null) {
      if (aspectRatio != null) {
        width = height * aspectRatio;
      } else if (intrinsic != null) {
        width = height * intrinsic.width / intrinsic.height;
      }
    }
    width ??= widthLimit;
    height ??= aspectRatio == null ? width * 0.75 : width / aspectRatio;
    if (height > heightLimit) {
      height = heightLimit;
    }
    return (width, height);
  }

  /// 行内替换图按原始尺寸收缩，不沿用块图的默认全宽。
  ImageDisplaySize _inlineImageSize(
    ComputedStyle style,
    ImageIntrinsicSize? intrinsic,
    double availableWidth,
  ) {
    final model = BoxModel.fromStyle(style, containingWidth: availableWidth);
    var width = model.contentWidth;
    var height = model.contentHeight;
    final ratio = style.aspectRatio;
    if (ratio != null) {
      if (width != null && height == null) height = width / ratio;
      if (height != null && width == null) width = height * ratio;
    }
    if (width == null && height == null && intrinsic == null) {
      height = style.fontSize;
      width = height * (ratio ?? 1);
    }
    final size = ImageDisplaySizing.compute(
      maxWidth: math.max(
        1,
        availableWidth - model.horizontalInset - model.margin.horizontal,
      ),
      intrinsicWidth: intrinsic?.width,
      intrinsicHeight: intrinsic?.height,
      cssWidth: width,
      cssHeight: height,
    );
    return ImageDisplaySize(
      width: model.borderBoxWidth(size.width),
      height: model.borderBoxHeight(size.height),
    );
  }

  List<StyledRun> _sliceTextRuns(TextLayoutResult layout, int start, int end) {
    final runs = <StyledRun>[];
    for (final run in layout.runs) {
      final runStart = math.max(run.start, start);
      final runEnd = math.min(run.end, end);
      if (runEnd <= runStart) continue;
      runs.add(
        StyledRun(
          start: runStart - start,
          end: runEnd - start,
          style: run.style,
          baselineShift: run.baselineShift,
          syntheticFontFallback: run.syntheticFontFallback,
        ),
      );
    }
    return runs;
  }

  /// 浮动绕排重测保留行内样式与原子盒，并将偏移平移到待测子串。
  TextLayoutResult _relayoutFloatText(
    PageBlock block,
    ComputedStyle style,
    double width, {
    int start = 0,
  }) {
    // text-indent 只作用于源块的首行。浮动占位变化或跨页后会从中间
    // 重排同一段落，续排首行不能再次缩进，否则绕排结束处会凭空分段。
    final layoutStyle = start == 0
        ? style
        : style.withTypography(textIndent: 0);
    final boxes = [
      for (final line in block.layout.lines)
        for (final box in line.inlineBoxes)
          if (box.offset >= start) box.spec.atOffset(box.offset - start),
    ];
    final text = block.layout.text.substring(start);
    final runs = _sliceTextRuns(block.layout, start, block.layout.text.length);
    final rubies = [
      for (final ruby in block.rubies ?? const <RubyAnnotation>[])
        if (ruby.end > start)
          RubyAnnotation(
            start: math.max(0, ruby.start - start),
            end: ruby.end - start,
            text: ruby.text,
          ),
    ];
    return boxes.isEmpty
        ? _layoutCache.layout(
            text: text,
            style: layoutStyle,
            maxWidth: width,
            runs: runs,
            rubies: rubies,
            hasGlyph: _hasBookFontGlyph,
          )
        : TextLayoutEngine.layout(
            text: text,
            style: layoutStyle,
            maxWidth: width,
            runs: runs,
            inlineBoxes: boxes,
            rubies: rubies,
            hasGlyph: _hasBookFontGlyph,
          );
  }

  /// 章节纯文本按章 LRU；全书搜索后不长期保留整本正文副本。
  final BoundedCache<int, String> _plainTextCache = BoundedCache(
    chapterIndexCacheLimit,
  );

  /// 章节纯文本：扫描式全文搜索用。
  ///
  /// 走「原始 XHTML → 剥标签」的轻量路径，跳过完整解析与排版（156MB 全书
  /// 约 2 秒 → 数百毫秒）。文本细节与排版结果可能有差异，所以搜索命中后要按
  /// 块级文本重新校验偏移，不能直接拿它算 CFI。
  String chapterPlainText(int spineIndex) {
    if (_closed) return '';
    final cached = _plainTextCache[spineIndex];
    if (cached != null) {
      return cached;
    }
    String text;
    try {
      final xhtml = document.chapterXhtml(spineIndex);
      text = xhtml == null ? '' : xhtmlToPlainText(xhtml);
    } catch (_) {
      text = '';
    }
    _plainTextCache[spineIndex] = text;
    return text;
  }

  /// OPF `itemref` 上的多看页属性（按 spine 序缓存）。
  Map<int, OpfPageFlags>? _opfPageFlagsCache;

  /// 解析 OPF `itemref` 的多看页属性，按 spine 序返回。
  ///
  /// 引擎的 OPF 解析只保留 manifest 的 `properties`，spine `itemref` 上的
  /// `duokan-page-fullscreen` / `duokan-page-fitwindow` / `page-spread-*`
  /// 被丢弃（docs/duokan-private-css.md「OPF 页属性」），这里在章节源直接
  /// 扫一遍 OPF 原文补回。spine 序与引擎一致：只统计 `idref` 非空且在
  /// manifest 中存在的 `itemref`。
  Map<int, OpfPageFlags> _opfPageFlags() {
    final cached = _opfPageFlagsCache;
    if (cached != null) {
      return cached;
    }
    final flags = <int, OpfPageFlags>{};
    _opfPageFlagsCache = flags;
    try {
      final bytes = document.archive.readBytes(document.opfPath);
      if (bytes == null) {
        return flags;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final manifestIds = <String>{
        for (final match in RegExp(r'<item\b[^>]*>').allMatches(text))
          if ((_tagAttr(match.group(0)!, 'id') ?? '').isNotEmpty)
            _tagAttr(match.group(0)!, 'id')!,
      };
      var spineIndex = 0;
      for (final match in RegExp(r'<itemref\b[^>]*>').allMatches(text)) {
        final tag = match.group(0)!;
        final idref = _tagAttr(tag, 'idref') ?? '';
        if (idref.isEmpty || !manifestIds.contains(idref)) {
          continue;
        }
        // 属性既可能写在 `properties="a b"` 里（EPUB 3 标准写法，多看
        // 同样如此），也可能直接写成独立属性，两种都收。
        final tokens = <String>{
          ...(_tagAttr(tag, 'properties') ?? '').split(RegExp(r'\s+')),
          for (final attribute in RegExp(r'([\w:.-]+)\s*=').allMatches(tag))
            attribute.group(1)!,
        };
        bool has(String name) => tokens.contains(name);
        final spreadLeft =
            has('page-spread-left') ||
            has('duokan-page-fullscreen-spread-left');
        final spreadRight =
            has('page-spread-right') ||
            has('duokan-page-fullscreen-spread-right');
        flags[spineIndex] = OpfPageFlags(
          // 全屏跨页的左右页也是全屏页。
          fullScreen:
              has('duokan-page-fullscreen') || spreadLeft || spreadRight,
          fitWindow: has('duokan-page-fitwindow'),
          spreadLeft: spreadLeft,
          spreadRight: spreadRight,
        );
        spineIndex += 1;
      }
    } catch (_) {
      // OPF 读不到/解码失败：按普通章节处理（不影响分页）。
    }
    return flags;
  }

  /// 章节的多看页属性（OPF `itemref`）；未标记返回 [OpfPageFlags.none]。
  OpfPageFlags chapterPageFlags(int spineIndex) =>
      _opfPageFlags()[spineIndex] ?? OpfPageFlags.none;

  /// 从标签文本里取属性值（OPF 扫描用；属性值不含裸引号）。
  static String? _tagAttr(String tag, String name) {
    final escaped = RegExp.escape(name);
    final doubleQuoted = RegExp('(?:^|\\s)$escaped\\s*=\\s*"([^"]*)"')
        .firstMatch(tag);
    if (doubleQuoted != null) {
      return doubleQuoted.group(1);
    }
    return RegExp("(?:^|\\s)$escaped\\s*=\\s*'([^']*)'")
        .firstMatch(tag)
        ?.group(1);
  }

  /// 章节是否走满屏路径（单图无正文无宽高属性，§8.6）。
  FullBleedChapter fullBleedAnalysis(int spineIndex) {
    return _fullBleedCache.putIfAbsent(spineIndex, () {
      final parsed = document.parseDocument(spineIndex);
      final blocks = _buildDisplayDocument(parsed, spineIndex);
      _pendingBlockDocument = blocks;
      final selectorIndex = _ParsedSelectorIndex(parsed.root);
      _pendingSelectorIndex = selectorIndex;
      final structural = analyzeFullBleed(blocks);
      if (!structural.isFullBleed) {
        return structural;
      }
      // 快路只覆盖真会绘制的唯一图片；隐藏图交给普通路径按 CSS 剔除。
      final rules = CascadeRuleSet([
        ...uaRules(),
        for (var i = 0; i < _chapterStylesheets(spineIndex).length; i++)
          ...CascadeRule.fromStylesheet(
            _chapterStylesheets(spineIndex)[i],
            origin: CascadeOrigin.author,
            startOrder: 1000 + i * 10000,
          ),
      ]);
      bool isRendered(EpubNode node) {
        final chain = selectorIndex.chainOf(node);
        if (chain == null) return true;
        ComputedStyle? style;
        for (var i = 0; i < chain.length; i++) {
          style = Cascade.compute(
            element: chain[i],
            ancestors: chain.sublist(0, i),
            rules: rules.candidatesFor(chain[i]),
            inlineDeclarations: _inlineDeclarationsOf(
              chain[i].attributes['style'],
            ),
            parent: style,
            rootFontSize: baseStyle.fontSize,
            containingWidth: contentWidth,
            viewportWidth: contentWidth,
          );
          if (style.display == CssDisplay.none) return false;
        }
        return style?.visibility != CssVisibility.hidden;
      }

      return analyzeFullBleed(blocks, isRendered: isRendered);
    });
  }

  /// 浮动感知分页（flat 管线接入，引擎 FloatOccupancy 区间模型）：
  /// - 浮动图不占流高，按侧登记占位，覆盖切片渲染（overlay/absoluteTop）；
  /// - 文本按「同占位状态」行批切段，保留行内样式重测窄幅区间，区间外回全宽；
  /// - clear：流游标推到该侧浮动底边并移除已满足占位；
  /// - 页界：浮动不跨页（整块移下页），收页时占位清空。
  List<PageContent> _paginateWithFloats(List<PageBlock> blocks, int spine) {
    const gap = 8.0;
    final width = contentWidth;
    final height = contentHeight;
    final pages = <PageContent>[];
    var slices = <PageBlockSlice>[];
    var y = 0.0;
    final occupancy = FloatOccupancy();
    // 浮动定位用的流锚点：本页最后一个在流块的「内容底边」和它自己的
    // 下外边距。浮动框的外边距盒顶就落在这条线上（CSS 2.1 §9.5：静态
    // 位置 = 当前流位置，随后再叠加自身 margin-top）。
    var hasFlowOnPage = false;
    var lastContentBottom = 0.0;
    var lastBottomMargin = 0.0;

    void noteFlow(double contentBottom, double bottomMargin) {
      hasFlowOnPage = true;
      lastContentBottom = contentBottom;
      lastBottomMargin = bottomMargin;
    }

    void closePage() {
      // 容行时预留、收页时挂到末个在流片段，浮动覆盖层不推进正文。
      final lastFlow = slices.lastIndexWhere((slice) => !slice.overlay);
      if (lastFlow >= 0) {
        final last = slices[lastFlow];
        final decoration = last.block.containerBottomInset(last.endLine);
        slices[lastFlow] = last.withBottomDecoration(decoration);
        y += decoration;
      }
      pages.add(
        PageContent(
          spineIndex: spine,
          pageIndex: pages.length,
          slices: List.unmodifiable(slices),
          usedHeight: y,
          pageHeight: height,
          topPadding: 0,
        ),
      );
      slices = <PageBlockSlice>[];
      y = 0;
      hasFlowOnPage = false;
      lastContentBottom = 0;
      lastBottomMargin = 0;
      occupancy.clear();
    }

    double leadingOf(PageBlock block, {bool starts = true}) =>
        (starts ? block.leadingExtent : 0) +
        (hasFlowOnPage ? 0 : block.containerTopInset(starts ? 0 : 1));

    double prepareAtomicBlock(PageBlock block) {
      final bottom = block.containerBottomInset(block.layout.lineCount);
      if (y > 0 &&
          y + leadingOf(block) + block.height + block.trailingExtent + bottom >
              height) {
        closePage();
      }
      return leadingOf(block);
    }

    // 浮动块的静态位置（f）：CSS 2.1 §9.5——浮动框的外边距盒顶不得高于
    // 它所在的行盒顶。行盒顶 = 当前位置 + 下一个在流块的段前距（相邻块
    // 的 margin 已经折叠到该块上），浮动再往下让出自己的 margin-top。
    // 旧实现直接把浮动放在流游标处，页首浮动比正文高一个段距；多行浮动
    // 段落起点偏十几像素（38-float-clear）。
    final nextFlowLeading = List<double>.filled(blocks.length, 0);
    var upcomingLeading = 0.0;
    for (var i = blocks.length - 1; i >= 0; i--) {
      nextFlowLeading[i] = upcomingLeading;
      final candidate = blocks[i];
      if (!candidate.absolute && candidate.floatSide == null) {
        upcomingLeading = candidate.leadingExtent;
      }
    }

    /// 行内浮动的包含块。没有显式信息的块级浮动仍按整页版心排布。
    ({double left, double width}) floatRegion(PageBlock block) {
      final left = (block.floatContainingLeft ?? 0.0)
          .clamp(0.0, width)
          .toDouble();
      final regionWidth = (block.floatContainingWidth ?? width)
          .clamp(0.0, math.max(0.0, width - left))
          .toDouble();
      return (left: left, width: regionWidth);
    }

    double occupiedLeftWithin(double top, double bottom, double regionLeft) {
      var used = 0.0;
      for (final item in occupancy.items) {
        if (item.side == FloatSide.left &&
            item.rect.top < bottom &&
            item.rect.bottom > top) {
          used = math.max(used, item.rect.right - regionLeft);
        }
      }
      return math.max(0.0, used);
    }

    double occupiedRightWithin(double top, double bottom, double regionRight) {
      var used = 0.0;
      for (final item in occupancy.items) {
        if (item.side == FloatSide.right &&
            item.rect.top < bottom &&
            item.rect.bottom > top) {
          used = math.max(used, regionRight - item.rect.left);
        }
      }
      return math.max(0.0, used);
    }

    /// 浮动排布（CSS 2.1 §9.5.1）：同一行还有空位就并排——左浮动贴已有
    /// 左浮动的右缘、右浮动贴已有右浮动的左缘；放不下就落到该侧浮动底边
    /// 另起一行。多列网格（双列目录）靠这条把同宽浮块两两并排。
    ({double top, double x}) placeFloat({
      required double preferredTop,
      required double occupiedWidth,
      required double heightPx,
      required FloatSide side,
      required double regionLeft,
      required double regionWidth,
    }) {
      // 候选行位：静态位置，以及所有浮动底边（行边界）。逐行尝试比
      // 「直接落到最底边」更接近 CSS——同一行的矮浮块下面还能继续并排。
      final rows = <double>{preferredTop};
      for (final item in occupancy.items) {
        if (item.rect.bottom > preferredTop + 0.01) {
          rows.add(item.rect.bottom);
        }
      }
      final ordered = rows.toList()..sort();
      for (final top in ordered) {
        final leftUsed = occupiedLeftWithin(top, top + heightPx, regionLeft);
        final rightUsed = occupiedRightWithin(
          top,
          top + heightPx,
          regionLeft + regionWidth,
        );
        if (leftUsed + rightUsed + occupiedWidth <= regionWidth + 0.5) {
          final x = side == FloatSide.left
              ? regionLeft + leftUsed
              : regionLeft + regionWidth - rightUsed - occupiedWidth;
          return (top: top, x: x);
        }
      }
      // 所有行位都放不下：落到该侧浮动底边另起一行。
      return (top: math.max(preferredTop, occupancy.maxBottom(side)), x: 0);
    }

    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      // 绝对定位（P9-19）：不占流高，直接作为覆盖切片挂到当前页。
      if (block.absolute) {
        final top = (block.absoluteTop ?? y)
            .clamp(0.0, math.max(0.0, height - 1))
            .toDouble();
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: 0,
            endLine: block.layout.lineCount,
            height: block.height,
            overlay: true,
            absoluteTop: top,
            leftInset: block.absoluteLeft ?? 0,
          ),
        );
        continue;
      }
      final floatSide = block.floatSide;
      if (floatSide != null) {
        final region = floatRegion(block);
        // 容器浮动组（W12）：一个被 flat 管线拆成多个子块的浮动容器
        //（双列目录 `.dk-toc-item{float:left;width:48%}`）作为一个浮动盒
        // 整体占位，组内块自上而下堆叠、相邻段距取大——否则每个子块各
        // 自成为独立浮块，同一容器的段落会并排排成一行。
        if (block.groupId >= floatGroupBase) {
          final groupBlocks = <PageBlock>[block];
          var next = blockIndex + 1;
          while (next < blocks.length &&
              blocks[next].groupId == block.groupId &&
              blocks[next].floatSide == floatSide) {
            groupBlocks.add(blocks[next]);
            next += 1;
          }
          final first = groupBlocks.first;
          final groupStyle = first.style;
          final groupInsetX = groupStyle == null
              ? 0.0
              : groupStyle.padding.horizontal +
                    groupStyle.borders.left.width +
                    groupStyle.borders.right.width;
          final groupContentW = first.layout.maxWidth.isFinite
              ? math.min(first.layout.maxWidth, region.width)
              : first.layout.width;
          final groupBorderW = math.min(
            region.width,
            groupContentW + groupInsetX,
          );
          final groupMarginLeft = groupStyle?.margin.left ?? 0;
          final groupMarginRight = groupStyle?.margin.right ?? 0;
          final groupLeftSpace = floatSide == FloatSide.left
              ? groupMarginLeft
              : groupMarginLeft;
          final groupRightSpace = groupMarginRight;
          final groupOccupied = math.min(
            region.width,
            groupLeftSpace + groupBorderW + groupRightSpace,
          );
          // 组内各块的边框盒顶（相对组边框盒顶）与组总高。
          final borderTops = <double>[];
          var cursor = 0.0;
          for (var i = 0; i < groupBlocks.length; i++) {
            final member = groupBlocks[i];
            if (i > 0) {
              cursor += math.max(
                groupBlocks[i - 1].spaceAfter,
                member.spaceBefore,
              );
            }
            borderTops.add(cursor);
            cursor += member.topInset + member.height + member.bottomInset;
          }
          final groupBorderHeight = cursor;
          final groupMarginTop = first.spaceBefore;
          final groupMarginBottom = groupBlocks.last.spaceAfter;
          final groupFlowTop = hasFlowOnPage
              ? lastContentBottom + lastBottomMargin
              : nextFlowLeading[blockIndex] + first.containerTopInset(0);
          if (y > 0 &&
              groupFlowTop +
                      groupMarginTop +
                      groupBorderHeight +
                      groupMarginBottom +
                      groupBlocks.last.containerBottomInset(
                        groupBlocks.last.layout.lineCount,
                      ) >
                  height) {
            closePage();
          }
          final groupPlacement = placeFloat(
            preferredTop:
                (hasFlowOnPage
                    ? lastContentBottom + lastBottomMargin
                    : nextFlowLeading[blockIndex] +
                          first.containerTopInset(0)) +
                groupMarginTop,
            occupiedWidth: groupOccupied,
            heightPx: groupBorderHeight + groupMarginBottom,
            side: floatSide,
            regionLeft: region.left,
            regionWidth: region.width,
          );
          final groupOccupiedX = groupPlacement.x;
          final groupBoxX = groupOccupiedX + groupLeftSpace;
          final groupTop = groupPlacement.top;
          occupancy.insert(
            BoxOccupied(
              rect: Rect.fromLTWH(
                groupOccupiedX,
                groupTop - groupMarginTop,
                groupOccupied,
                groupMarginTop + groupBorderHeight + groupMarginBottom,
              ),
              baseline: groupTop,
              side: floatSide,
            ),
          );
          for (var i = 0; i < groupBlocks.length; i++) {
            final member = groupBlocks[i];
            slices.add(
              PageBlockSlice(
                block: member,
                startLine: 0,
                endLine: member.layout.lineCount,
                height: member.height,
                overlay: true,
                absoluteTop: groupTop + borderTops[i],
                leftInset: math.max(0.0, groupBoxX - groupMarginLeft),
              ),
            );
          }
          blockIndex += groupBlocks.length - 1;
          continue;
        }
        final h = block.height;
        // 浮动盒宽（f）：内容宽取测量用的 maxWidth（声明 width 已由
        // [_textWidthFor] 折成内容宽），加内边距/边框得到边框盒；外侧再
        // 让出外边距——外边距属于浮动外框，正文不得进入。没有外边距的
        // 一侧补 [gap] 呼吸位（书内浮动图通常不带外边距）。
        final style = block.style;
        final insetX = style == null
            ? 0.0
            : style.padding.horizontal +
                  style.borders.left.width +
                  style.borders.right.width;
        final contentW = block.layout.maxWidth.isFinite
            ? math.min(block.layout.maxWidth, region.width)
            : block.layout.width;
        final borderW = math.min(region.width, contentW + insetX);
        final marginLeft = style?.margin.left ?? 0;
        final marginRight = style?.margin.right ?? 0;
        // 朝版心的一侧才占位：左边距只对右浮动的左侧有意义，右边距反之。
        // 呼吸位只给图片浮动（文字浮动按 CSS 外边距排，多列网格 48%+2%
        // 不能额外加 8px，否则两列并排会溢出换行）。
        final breathingGap = block.layout.text.isEmpty ? gap : 0.0;
        final leftSpace = floatSide == FloatSide.left
            ? marginLeft
            : math.max(marginLeft, breathingGap);
        final rightSpace = floatSide == FloatSide.right
            ? marginRight
            : math.max(marginRight, breathingGap);
        final occupied = math.min(
          region.width,
          leftSpace + borderW + rightSpace,
        );
        // 静态位置 = 当前流位置（上一个在流块的内容底边 + 它的下外边距；
        // 页首无在流块时用下一个在流块的段前距），再叠加自身 margin-top
        //（浮动的 margin 不参与折叠，原样相加）。
        double flowPosition() => hasFlowOnPage
            ? lastContentBottom + lastBottomMargin
            : nextFlowLeading[blockIndex] + block.containerTopInset(0);
        final preferredTop = flowPosition() + block.spaceBefore;
        final ownTop = style == null
            ? 0.0
            : style.padding.top +
                  (style.borders.top.isVisible ? style.borders.top.width : 0);
        final ownBottom = style == null
            ? 0.0
            : style.padding.bottom +
                  (style.borders.bottom.isVisible
                      ? style.borders.bottom.width
                      : 0);
        final overlayHeight = block.topInset + h + block.bottomInset;
        if (y > 0 &&
            preferredTop +
                    overlayHeight +
                    block.containerBottomInset(block.layout.lineCount) >
                height) {
          closePage();
        }
        final placement = placeFloat(
          preferredTop: flowPosition() + block.spaceBefore,
          occupiedWidth: occupied,
          heightPx: overlayHeight,
          side: floatSide,
          regionLeft: region.left,
          regionWidth: region.width,
        );
        final occupiedX = placement.x;
        final boxX = occupiedX + leftSpace;
        final floatY = placement.top;
        occupancy.insert(
          BoxOccupied(
            rect: Rect.fromLTWH(
              occupiedX,
              floatY + block.topInset - ownTop,
              occupied,
              ownTop + h + ownBottom,
            ),
            baseline: floatY,
            side: floatSide,
          ),
        );
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: 0,
            endLine: block.layout.lineCount,
            height: overlayHeight,
            leadingExtent: block.topInset,
            trailingExtent: block.bottomInset,
            overlay: true,
            absoluteTop: floatY,
            // 绘制层会在 leftInset 之上再加一次 margin.left，浮动框定位
            // 用的是边框盒左缘，这里先把外边距扣掉（否则右浮动整体右移）。
            leftInset: math.max(0.0, boxX - marginLeft),
          ),
        );
        continue;
      }
      // clear（P3-14 语义）：推到该侧浮动底边并移除已满足占位；推移
      // 量以空白垫片切片占位（渲染层按切片累计 y，空隙须显式承载）。
      final clear = block.style?.clear ?? CssClear.none;
      if (clear != CssClear.none) {
        var bottom = y;
        if (clear == CssClear.left || clear == CssClear.both) {
          bottom = math.max(bottom, occupancy.maxBottom(FloatSide.left));
        }
        if (clear == CssClear.right || clear == CssClear.both) {
          bottom = math.max(bottom, occupancy.maxBottom(FloatSide.right));
        }
        occupancy.removeSatisfiedBelow(bottom, FloatSide.left);
        occupancy.removeSatisfiedBelow(bottom, FloatSide.right);
        if (bottom > y) {
          final delta = bottom - y;
          final spacer = PageBlock(
            layout: TextLayoutResult(
              text: '',
              lines: [
                LineBox(
                  start: 0,
                  end: 0,
                  top: 0,
                  height: delta,
                  baseline: delta,
                  width: width,
                ),
              ],
              width: width,
              height: delta,
              maxWidth: width,
              runs: const <StyledRun>[],
            ),
            containers: _containerFragmentsFor(
              block,
              starts: false,
              ends: false,
            ),
          );
          slices.add(
            PageBlockSlice(
              block: spacer,
              startLine: 0,
              endLine: 1,
              height: delta,
            ),
          );
          y = bottom;
        }
      }
      // 浮动章节仍要遵守 break-after: avoid：标题能放进当前页，但下一段
      // 的首行放不下时，整段标题移到下页，不能只身留在页底。
      final blockFlowHeight = math.max(block.height, block.layout.height);
      final blockExtent =
          leadingOf(block) + blockFlowHeight + block.trailingExtent;
      if (block.breakAfterAvoid &&
          y > 0 &&
          blockIndex + 1 < blocks.length &&
          blockExtent <= height) {
        PageBlock? next;
        for (var i = blockIndex + 1; i < blocks.length; i++) {
          if (!blocks[i].absolute && blocks[i].floatSide == null) {
            next = blocks[i];
            break;
          }
        }
        if (next != null && !next.pageBreakBefore && !block.pageBreakAfter) {
          final nextNeed =
              next.leadingExtent +
              (next.layout.lines.isEmpty
                  ? 0.0
                  : next.layout.lines.first.height) +
              (next.layout.lineCount <= 1 ? next.trailingExtent : 0.0) +
              next.containerBottomInset(1);
          final pairExtent = blockExtent + nextNeed;
          // 即使标题和下一段首行本身超过一页，也应先把标题移到下页：
          // 避免规则优先于“标题能否单页容纳”，否则会出现标题独留页底。
          if (height - y < pairExtent) {
            closePage();
          }
        }
      }
      // 表格按当前页真实剩余高度切行；续页由 tablePiece 重复表头。
      final tableRows = block.table == null
          ? 0
          : Paginator.splittableTableRows(block);
      if (tableRows > 1) {
        final headerRows = Paginator.tableHeaderRows(block);
        var rowStart = 0;
        while (rowStart < tableRows) {
          final firstCandidate = rowStart == 0 && headerRows > 0
              ? math.min(tableRows, headerRows + 1)
              : rowStart + 1;
          PageBlock? fitted;
          var fittedEnd = rowStart;
          var fittedLeading = 0.0;
          for (
            var candidate = firstCandidate;
            candidate <= tableRows;
            candidate++
          ) {
            final piece = Paginator.tablePiece(block, rowStart, candidate);
            final leading = leadingOf(piece);
            final extent = leading + piece.height + piece.trailingExtent;
            if (y + extent + piece.containerBottomInset(1) <= height + 0.01) {
              fitted = piece;
              fittedEnd = candidate;
              fittedLeading = leading;
            } else {
              break;
            }
          }
          if (fitted == null) {
            if (y > 0) {
              closePage();
              continue;
            }
            fitted = Paginator.tablePiece(block, rowStart, firstCandidate);
            fittedEnd = firstCandidate;
            fittedLeading = leadingOf(fitted);
          }
          final extent = fittedLeading + fitted.height + fitted.trailingExtent;
          slices.add(
            PageBlockSlice(
              block: fitted,
              startLine: 0,
              endLine: 1,
              height: extent,
              leadingExtent: fittedLeading,
              trailingExtent: fitted.trailingExtent,
              leftInset: fitted.leftInset,
            ),
          );
          noteFlow(
            y + fittedLeading + fitted.height,
            fitted.style?.margin.bottom ?? fitted.spaceAfter,
          );
          y += extent;
          rowStart = fittedEnd;
          if (rowStart < tableRows) {
            closePage();
          }
        }
        if (block.pageBreakAfter) {
          closePage();
        }
        continue;
      }
      // 空布局块（浮动章节）：整块原子入流。否则会被当成空文本块静默
      // 丢掉，空文本块还会让收页循环空转。
      if (block.layout.lineCount == 0 ||
          block.table != null ||
          block.layout.text.isEmpty) {
        final leading = prepareAtomicBlock(block);
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: 0,
            endLine: block.layout.lineCount,
            height: leading + block.height + block.trailingExtent,
            leadingExtent: leading,
            trailingExtent: block.trailingExtent,
            leftInset: block.leftInset,
          ),
        );
        noteFlow(
          y + leading + block.height,
          block.style?.margin.bottom ?? block.spaceAfter,
        );
        y += leading + block.height + block.trailingExtent;
        continue;
      }
      // 声明盒高块（height/min-height/overflow 裁剪）：浮动流里按原子块
      // 处理。逐行批切段会按行高重建切片高，把盒内留白/裁剪全丢掉
      //（`.ov{height:40px}` 曾按 3 行 75px 占位）。
      final boxHeight = block.height;
      if ((boxHeight - block.measuredHeight).abs() > 0.5 ||
          block.clipsContent) {
        final leading = prepareAtomicBlock(block);
        final boxStyle = block.style ?? style;
        final available = _textWidthFor(boxStyle);
        final flowLeft = block.leftInset + boxStyle.margin.left;
        final occupiedLeft = occupiedLeftWithin(y, y + boxHeight, flowLeft);
        final occupiedRight = occupiedRightWithin(
          y,
          y + boxHeight,
          flowLeft + available,
        );
        final batchWidth = math.max(
          24.0,
          available - occupiedLeft - occupiedRight,
        );
        final measured = _relayoutFloatText(block, boxStyle, batchWidth);
        // overflow: visible 保留盒外全部行；显式裁剪时保留行顶位于盒内的
        // 行，末尾整行绘制仍由切片矩形裁掉，与浏览器部分可见行一致。
        final taken = block.clipsContent
            ? visibleLineCountWithinHeight(measured.lines, boxHeight)
            : measured.lineCount;
        final visibleHeight = measured.lines
            .take(taken)
            .fold(0.0, (sum, line) => sum + line.height);
        if (taken > 0) {
          final segLines = [
            for (final line in measured.lines.take(taken))
              line.copyWith(offsetX: line.offsetX + occupiedLeft),
          ];
          final segText = block.layout.text.substring(0, segLines.last.end);
          final segLayout = TextLayoutResult(
            text: segText,
            lines: segLines,
            width: batchWidth,
            height: visibleHeight,
            maxWidth: batchWidth,
            runs: _sliceTextRuns(measured, 0, segText.length),
            plainTextLayout: measured.plainTextLayout,
          );
          slices.add(
            PageBlockSlice(
              block: PageBlock(
                layout: segLayout,
                style: block.style,
                pageBreakBefore: block.pageBreakBefore,
                pageBreakAfter: block.pageBreakAfter,
                startCfi: block.startCfi,
                textRuleEligible: block.textRuleEligible,
                breakInsideAvoid: block.breakInsideAvoid,
                breakAfterAvoid: block.breakAfterAvoid,
                leftInset: block.leftInset,
                topInset: block.topInset,
                bottomInset: block.bottomInset,
                containers: block.containers,
                effectiveOpacity: block.effectiveOpacity,
                declaredContentHeight: boxHeight,
              ),
              startLine: 0,
              endLine: taken,
              height: leading + boxHeight + block.trailingExtent,
              leadingExtent: leading,
              trailingExtent: block.trailingExtent,
              leftInset: block.leftInset,
            ),
          );
        }
        noteFlow(
          y + leading + boxHeight,
          block.style?.margin.bottom ?? block.spaceAfter,
        );
        y += leading + boxHeight + block.trailingExtent;
        continue;
      }
      // 行批切段（f）：一个源块只产出一个 PageBlock，绕排只改变行的起始
      // x（写进 LineBox.offsetX）。此前按「同占位状态」把段落切成多个块，
      // 块的宽度/行数于是对不上浏览器的「一个 <p> 一个块」。
      final fullText = block.layout.text;
      final textStyle = block.style ?? style;
      final available = _textWidthFor(textStyle);
      final flowLeft = block.leftInset + textStyle.margin.left;
      final flowRight = flowLeft + available;
      var charCursor = 0;
      while (charCursor < fullText.length) {
        final leadingLeft = leadingOf(block, starts: charCursor == 0);
        final blockLines = <LineBox>[];
        var blockHeight = 0.0;
        while (charCursor < fullText.length) {
          final probe = block.layout.lines.first.height;
          final lineY = y + leadingLeft + blockHeight;
          final occupiedLeft = occupiedLeftWithin(
            lineY,
            lineY + probe,
            flowLeft,
          );
          final occupiedRight = occupiedRightWithin(
            lineY,
            lineY + probe,
            flowRight,
          );
          final narrowed = occupiedLeft > 0 || occupiedRight > 0;
          final batchWidth = math.max(
            24.0,
            available - occupiedLeft - occupiedRight,
          );
          final measured = _relayoutFloatText(
            block,
            textStyle,
            batchWidth,
            start: charCursor,
          );
          // 取行：直到占位状态变化（下一行的区间不同）、页尽或文本尽。
          var taken = 0;
          var batchHeight = 0.0;
          while (taken < measured.lineCount) {
            final lineH = measured.lines[taken].height;
            final finished =
                charCursor + measured.lines[taken].end >= fullText.length;
            final bottom =
                block.containerBottomInset(
                  finished ? block.layout.lineCount : 0,
                ) +
                (finished ? block.trailingExtent : 0);
            if (y + leadingLeft + blockHeight + batchHeight + lineH + bottom >
                height) {
              break;
            }
            final nextY = y + leadingLeft + blockHeight + batchHeight;
            final nextLeft = occupiedLeftWithin(nextY, nextY + lineH, flowLeft);
            final nextRight = occupiedRightWithin(
              nextY,
              nextY + lineH,
              flowRight,
            );
            if ((nextLeft > 0 || nextRight > 0) != narrowed ||
                (narrowed &&
                    (nextLeft != occupiedLeft || nextRight != occupiedRight))) {
              break;
            }
            batchHeight += lineH;
            taken += 1;
          }
          if (taken == 0) {
            if (y > 0 || blockLines.isNotEmpty) {
              // 本页放不下：交给收页重排；页首强行占一行避免死循环。
              break;
            }
            taken = 1;
            batchHeight = measured.lines.first.height;
          }
          for (var i = 0; i < taken; i++) {
            final line = measured.lines[i];
            final lineStart = charCursor + line.start;
            final lineEnd = charCursor + line.end;
            blockLines.add(
              LineBox(
                start: lineStart,
                end: lineEnd,
                top: blockHeight + line.top,
                height: line.height,
                baseline: blockHeight + line.baseline,
                width: line.width,
                indent: line.indent,
                isLastLine: lineEnd >= fullText.length,
                offsetX: line.offsetX + occupiedLeft,
                justifyExtra: line.justifyExtra,
                justifyMode: line.justifyMode,
                spacing: line.spacing,
                isHardBreak: line.isHardBreak,
                ellipsized: line.ellipsized,
                ellipsisWidth: line.ellipsisWidth,
                hyphenated: line.hyphenated,
                hyphenWidth: line.hyphenWidth,
                inlineBoxes: [
                  for (final box in line.inlineBoxes)
                    InlineBoxPlacement(
                      offset: box.offset + charCursor,
                      left: box.left,
                      width: box.width,
                      height: box.height,
                      ascent: box.ascent,
                      descent: box.descent,
                      spec: box.spec.atOffset(box.offset + charCursor),
                    ),
                ],
              ),
            );
          }
          blockHeight += batchHeight;
          charCursor += measured.lines[taken - 1].end;
        }
        if (blockLines.isEmpty) {
          // 页首也放不下任何一行：收页重试（此时必然 y > 0）。
          closePage();
          continue;
        }
        final finished = charCursor >= fullText.length;
        final segLayout = TextLayoutResult(
          text: fullText.substring(0, blockLines.last.end),
          lines: List<LineBox>.unmodifiable(blockLines),
          width: available,
          height: blockHeight,
          maxWidth: available,
          runs: block.layout.runs,
          plainTextLayout: block.layout.plainTextLayout,
        );
        final trailing = finished ? block.trailingExtent : 0.0;
        slices.add(
          PageBlockSlice(
            block: PageBlock(
              layout: segLayout,
              style: block.style,
              pageBreakBefore: block.pageBreakBefore,
              pageBreakAfter: block.pageBreakAfter,
              startCfi: block.startCfi,
              textRuleEligible: block.textRuleEligible,
              breakInsideAvoid: block.breakInsideAvoid,
              breakAfterAvoid: block.breakAfterAvoid,
              leftInset: block.leftInset,
              topInset: block.topInset,
              bottomInset: block.bottomInset,
              containers: _containerFragmentsFor(
                block,
                starts: blockLines.first.start == 0,
                ends: finished,
              ),
              // 切片保留本段已排到的行内图片/注音；显示层按行号过滤，
              // 续页仍能画出本页范围内的占位图。
              inlineImages: <InlineImageSpec>[
                for (final image in block.inlineImages)
                  if (image.offset < blockLines.last.end) image,
              ],
              rubies: <RubyAnnotation>[
                for (final ruby in block.rubies ?? const <RubyAnnotation>[])
                  if (ruby.start < blockLines.last.end) ruby,
              ],
              effectiveOpacity: block.effectiveOpacity,
            ),
            startLine: 0,
            endLine: blockLines.length,
            height: leadingLeft + blockHeight + trailing,
            leadingExtent: leadingLeft,
            trailingExtent: trailing,
            leftInset: block.leftInset,
          ),
        );
        noteFlow(
          y + leadingLeft + blockHeight,
          block.style?.margin.bottom ?? block.spaceAfter,
        );
        y += leadingLeft + blockHeight + trailing;
        if (!finished) {
          closePage();
        }
      }
    }
    if (slices.isNotEmpty || pages.isEmpty) {
      closePage();
    }
    return pages;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (_closed) {
      throw StateError('章节来源已关闭');
    }
    return _loadChapterPages(spineIndex, _layoutGeneration);
  }

  bool _isCurrentLayout(int generation) =>
      !_closed && generation == _layoutGeneration;

  /// 聚合树与选择器视图必须来自同一次解析，重排时也成对复用。
  (BlockDocument, _ParsedSelectorIndex) _takeChapterStructure(int spineIndex) {
    final pending = _pendingBlockDocument;
    final selectors = _pendingSelectorIndex;
    _pendingBlockDocument = null;
    _pendingSelectorIndex = null;
    final cached = _displayDocumentCache[spineIndex];
    if (cached?.key == _structureKey(spineIndex)) {
      _displayDocumentCacheHits += 1;
      _touchDisplayDocumentCache(spineIndex);
      return (cached!.document, cached.selectors);
    }
    if (pending?.spineIndex == spineIndex && selectors != null) {
      return (pending!, selectors);
    }
    final parsed = document.parseDocument(spineIndex);
    return (
      _buildDisplayDocument(parsed, spineIndex),
      _ParsedSelectorIndex(parsed.root),
    );
  }

  /// 分页主体：产物不带整页背景，由 [loadChapter] 统一贴上。
  Future<List<PageContent>> _loadChapterPages(
    int spineIndex,
    int layoutGeneration,
  ) async {
    final trace = readerTraceEnabled ? ReaderTrace.instance : null;
    final traceBook = bookIdForTrace;
    final watch = trace == null ? null : (Stopwatch()..start());
    final stageWatch = trace == null ? null : (Stopwatch()..start());
    final paginationKey = _paginationKey(spineIndex);
    _paginationFontFamilies.putIfAbsent(paginationKey, () => <String>{});
    final cachedPages = _pageCache[paginationKey];
    if (cachedPages != null) {
      _touchPageCache(paginationKey);
      if (trace != null) {
        trace.count(ReaderTraceCounter.pageCacheHit, bookId: traceBook);
        trace.record(
          ReaderTraceName.pageRenderReuse,
          watch!.elapsedMicroseconds,
          bookId: traceBook,
        );
      }
      return cachedPages;
    }
    if (trace != null) {
      trace.count(ReaderTraceCounter.pageCacheMiss, bookId: traceBook);
    }
    // styles 层命中：聚合树、级联样式与行测量都已完成，只需按页索引
    // 重放（或重新分页）。页缓存清空后的章节回访走这里。
    final cachedBlocks = _blockCache[paginationKey];
    if (cachedBlocks != null) {
      _blockCacheHits += 1;
      _touchBlockCache(paginationKey);
      final pages = _paginateBlocks(
        spineIndex,
        paginationKey,
        cachedBlocks.flow,
        cachedBlocks.fixed,
        cachedBlocks.background,
        layoutGeneration,
      );
      if (trace != null) {
        trace.record(
          ReaderTraceName.chapterLayout,
          watch!.elapsedMicroseconds,
          bookId: traceBook,
        );
      }
      return pages;
    }
    // 满屏图页（P3-10，§8.6）：单图无正文无宽高属性 → 整页单块、
    // 多看全屏页（OPF `duokan-page-*`）：封面/插图整页铺满，正文样式
    // 不参与——body 的 padding/字号不会把封面裁小。`fitwindow` 用
    // contain 上下居中，其余全屏页 cover 铺满。
    final pageFlags = chapterPageFlags(spineIndex);
    if (pageFlags.isFullPage) {
      final singleImage = fullBleedAnalysis(spineIndex).singleImageSrc;
      if (singleImage != null && singleImage.isNotEmpty) {
        // `fullscreen` 必须铺满查看区域；若书内有 `~slim` 变体，优先选
        // 与当前页面比例更接近的一张，避免只靠 cover 裁掉封面信息。
        // `fitwindow` 的语义不同，保持 contain。
        final imageUrl = pageFlags.fitWindow
            ? _chapterImageUrl(spineIndex, singleImage)
            : _selectFullscreenImage(spineIndex, singleImage);
        final pages = _buildFullBleedPages(
          spineIndex,
          singleImage,
          paginationKey,
          contain: pageFlags.fitWindow,
          bleed: true,
          resolvedImageUrl: imageUrl,
        );
        if (_isCurrentLayout(layoutGeneration)) {
          _putPageCache(paginationKey, pages);
        }
        if (trace != null) {
          trace.record(
            ReaderTraceName.chapterLayout,
            watch!.elapsedMicroseconds,
            bookId: traceBook,
          );
        }
        return pages;
      }
    }
    // 边距归零、背景图 cover。先于普通聚合判定。
    final fullBleed = fullBleedAnalysis(spineIndex);
    if (fullBleed.isFullBleed) {
      final pages = _buildFullBleedPages(
        spineIndex,
        fullBleed.singleImageSrc!,
        paginationKey,
      );
      if (_isCurrentLayout(layoutGeneration)) {
        _putPageCache(paginationKey, pages);
      }
      if (trace != null) {
        trace.record(
          ReaderTraceName.chapterLayout,
          watch!.elapsedMicroseconds,
          bookId: traceBook,
        );
      }
      return pages;
    }
    // 满屏扫描后的原树直接交给作者 display 聚合；已有结果不重复解析。
    final displayCached = _displayDocumentCache[spineIndex];
    var (document, selectorIndex) = _takeChapterStructure(spineIndex);
    if (trace != null) {
      trace.record(
        ReaderTraceName.chapterStructure,
        stageWatch!.elapsedMicroseconds,
        bookId: traceBook,
      );
      stageWatch.reset();
    }
    // 图片块（真实书适配）：聚合树中折叠出的 img 块 → 背景图块。
    // 先预取章内图片的原始尺寸（同步按 URL 缓存，跨章复用），供
    // collect 按属性宽/高与宽高比换算显示尺寸。
    final spineItem = this.document.spine[spineIndex];
    final chapterBase = p.posix.dirname(
      this.document.resources.resolve(
            spineItem.href,
            baseDir: p.posix.dirname(this.document.opfPath),
          ) ??
          spineItem.href,
    );
    final imageSizes = <String, ImageIntrinsicSize>{};
    void gatherImageSrcs(BlockNode node) {
      if (node.tag == 'img' && node.children.isEmpty) {
        // SVG 折叠链：<image xlink:href> 的属性整体保留，src 键名兼容。
        final src = node.attributes['src'] ?? node.attributes['xlink:href'];
        if (src != null && src.isNotEmpty) {
          final url =
              this.document.resources.resolve(src, baseDir: chapterBase) ?? src;
          if (!imageSizes.containsKey(url)) {
            var size = _imageIntrinsicCache[url];
            if (size == null && !_imageIntrinsicMiss.containsKey(url)) {
              final bytes = this.document.archive.readBytes(url);
              size = bytes == null
                  ? null
                  : ImageSizeParser.readImageSize(bytes);
              if (size == null) {
                _imageIntrinsicMiss[url] = true;
              } else {
                _imageIntrinsicCache[url] = size;
              }
            }
            if (size != null) {
              imageSizes[url] = size;
            }
          }
        }
      }
      for (final child in node.children) {
        if (child is BlockNode) {
          gatherImageSrcs(child);
        }
      }
    }

    // 可变：collect 之后按 CSS 相邻兄弟折叠上下边距，再交给分页。
    var blocks = <PageBlock>[];
    // `position: fixed`（W18）：相对页面定位、每页重复——不进流，分页完成
    // 后给每一页追加覆盖切片。
    final fixedBlocks = <PageBlock>[];
    final chapterFootnotes = _footnoteReferences(spineIndex);
    PageFootnote? footnoteForReference(
      String tag,
      Map<String, String> attributes,
      String visibleText, {
      required int start,
      required int end,
    }) {
      final anchor =
          chapterFootnotes[FootnoteParser.referenceKey(
            tag,
            attributes,
            visibleText,
          )];
      if (anchor == null || anchor.kind == NoteKind.link) {
        return null;
      }
      return PageFootnote(
        start: start,
        end: end,
        label: anchor.label,
        kind: anchor.kind,
        text: anchor.noteText,
        imageUrls: anchor.noteImages,
      );
    }

    final retainedContainers = <SelectorElement, PageContainer>{};
    final splitInlineContainers = <SelectorElement>{};

    // 块级样式（P8-02 链式级联）：UA（uaRules）+ 作者样式表（私有钩子
    // 契约过滤）+ 内联 style 三源进 Cascade.compute——特异性/!important/
    // @media/继承（18 项继承表）全部由引擎处理；flat 管线只补盒类近似
    // 传导与引用深度。前缀缓存：同容器兄弟块共享祖先计算结果。
    final sheets = _chapterStylesheets(spineIndex);
    final usedBookFonts = _usedBookFonts(sheets, selectorIndex);
    _paginationFontFamilies[paginationKey] = <String>{
      for (final face in usedBookFonts) face.family.toLowerCase(),
    };
    await _ensureBookFonts(usedBookFonts);
    if (_closed) throw StateError('章节来源已关闭');
    if (!_isCurrentLayout(layoutGeneration)) {
      return const <PageContent>[];
    }
    // 字体改写、辅助规则和级联索引随样式表组合复用；书籍的数百章通常
    // 共享同一份全局 CSS。
    final preparedStyles = _prepareChapterCascade(sheets);
    if (trace != null) {
      trace.record(
        ReaderTraceName.chapterStyles,
        stageWatch!.elapsedMicroseconds,
        bookId: traceBook,
      );
      stageWatch.reset();
    }
    final auxiliaryRules = preparedStyles.auxiliaryRules;
    final firstLetterRules = preparedStyles.firstLetterRules;
    final pseudoRules = preparedStyles.pseudoRules;
    // ---------- 内容生成（W20）：计数器 / 引号 / object-fit ----------
    /// CSS 计数器状态（§12.4）：扁平管线按文档序遍历，用单层映射近似
    /// 树作用域（真书里章节编号几乎都是 `h1 { counter-increment: chapter }`
    /// + `h1::before { content: counter(chapter) }` 这种平铺用法）。
    final cssCounters = <String, int>{};

    /// 取元素命中的作者声明（规则按出现顺序覆盖，内联最后）——只用于
    /// ComputedStyle 还没建模的属性：`counter-*`、`content`、`object-*`。
    Map<String, String> rawDeclarationsFor(List<SelectorElement> ancestors) {
      if (ancestors.isEmpty) {
        return const <String, String>{};
      }
      final element = ancestors.last;
      final parents = ancestors.sublist(0, ancestors.length - 1);
      final result = <String, String>{};
      for (final rule in auxiliaryRules) {
        if (!rule.selectors.selectors.any(
          (selector) => selector.matches(element, parents),
        )) {
          continue;
        }
        for (final declaration in rule.declarations) {
          result[declaration.property] = declaration.value.trim();
        }
      }
      for (final declaration in _inlineDeclarationsOf(
        element.attributes['style'],
      )) {
        result[declaration.property] = declaration.value.trim();
      }
      return result;
    }

    /// `object-fit`（W20）：图片块用 background-image 绘制，这里把 CSS
    /// `object-fit` / `object-position` 映射成等价的 background-size/position——
    /// `contain`/`cover` 与整页图铺法共用同一套语义（不重复实现缩放/裁切算法）。
    ({String size, String position}) objectFitBackground(
      List<SelectorElement> ancestors,
      ImageIntrinsicSize? intrinsic, {
      required double boxWidth,
      required double boxHeight,
    }) {
      final declarations = rawDeclarationsFor(ancestors);
      final fit = declarations['object-fit']?.trim();
      final declaredPosition = declarations['object-position']?.trim();
      const center = 'center center';
      final position = declaredPosition == null || declaredPosition.isEmpty
          ? center
          : declaredPosition;
      switch (fit) {
        case 'fill':
          // 不保持比例，拉满盒子。
          return (size: '100% 100%', position: position);
        case 'none':
          // 原始尺寸，超出即裁切（背景不缩放）。
          return (size: 'auto', position: position);
        case 'scale-down':
          // min(none, contain)：原图比盒子大时缩到 contain，否则原尺寸。
          final larger =
              intrinsic != null &&
              boxWidth > 0 &&
              boxHeight > 0 &&
              (intrinsic.width > boxWidth || intrinsic.height > boxHeight);
          return (size: larger ? 'contain' : 'auto', position: position);
        case 'cover':
          return (size: 'cover', position: position);
        case 'contain':
        default:
          return (size: 'contain', position: position);
      }
    }

    /// 按一份声明表应用计数器（元素自身或伪元素规则）。
    ///
    /// CSS 2.1 §12.4：`counter-increment` 可以写在 `::before` 规则里
    ///（`li::before { counter-increment: item; content: counter(item) }`
    /// 是最常见的章节/列表自动编号写法），因此伪元素规则里的计数器声明
    /// 必须在求值 `content` 之前生效。
    void applyCounterMap(Map<String, String> declarations) {
      void apply(String property, int Function(int current, int value) step) {
        final raw = declarations[property];
        if (raw == null || raw.isEmpty) {
          return;
        }
        final tokens = raw.split(RegExp(r'\s+'));
        for (var i = 0; i < tokens.length; i += 1) {
          final name = tokens[i];
          if (name.isEmpty || name == 'none') {
            continue;
          }
          var value = property == 'counter-reset' ? 0 : 1;
          if (i + 1 < tokens.length) {
            final parsed = int.tryParse(tokens[i + 1]);
            if (parsed != null) {
              value = parsed;
              i += 1;
            }
          }
          cssCounters[name] = step(cssCounters[name] ?? 0, value);
        }
      }

      apply('counter-reset', (_, value) => value);
      apply('counter-increment', (current, value) => current + value);
    }

    /// `counter-reset` / `counter-increment`（缺省值 0 / +1）。
    void applyCounters(List<SelectorElement> ancestors) {
      applyCounterMap(rawDeclarationsFor(ancestors));
    }

    /// 计数器值按 `counter(name, <style>)` 的 style 格式化（默认 decimal）。
    String formatCounter(int value, String style) => switch (style) {
      'decimal-leading-zero' =>
        value.abs() < 10 ? '${value < 0 ? '-' : ''}0${value.abs()}' : '$value',
      'lower-alpha' || 'lower-latin' => _alphaCounter(value).toLowerCase(),
      'upper-alpha' || 'upper-latin' => _alphaCounter(value),
      'lower-roman' => _romanCounter(value).toLowerCase(),
      'upper-roman' => _romanCounter(value),
      _ => '$value',
    };

    /// 当前引号对（按嵌套层级取；`auto` 用中英文默认 “ ”、第二层 ‘ ’）。
    (String, String) quotePairAt(CssQuotes quotes, int depth) {
      switch (quotes) {
        case CssQuotesNone():
          return ('', '');
        case CssQuotesPairs(:final pairs):
          final pair = pairs[depth.clamp(0, pairs.length - 1)];
          return (pair.open, pair.close);
        case CssQuotesAuto():
          return depth == 0 ? ('\u201C', '\u201D') : ('\u2018', '\u2019');
      }
    }

    /// 伪元素没有进入 ComputedStyle 的属性（content/counter-*）按同一套
    /// 级联优先级取胜者：!important > 特异性 > 出现顺序，并过滤 @media。
    Map<String, CssDeclaration> winningPseudoDeclarations(
      List<SelectorElement> ancestors,
      String pseudo,
    ) {
      if (ancestors.isEmpty) {
        return const <String, CssDeclaration>{};
      }
      final element = ancestors.last;
      final parents = ancestors.sublist(0, ancestors.length - 1);
      final winners =
          <
            String,
            ({
              CssDeclaration declaration,
              int important,
              Specificity specificity,
              int order,
            })
          >{};
      for (final (order, rule)
          in (pseudoRules[pseudo] ?? const <_AuxiliaryCssRule>[]).indexed) {
        final media = rule.media;
        if (media != null && !Cascade.mediaMatches(media, contentWidth)) {
          continue;
        }
        Specificity? matched;
        for (final selector in rule.selectors.selectors) {
          if (!selector.matches(element, parents)) {
            continue;
          }
          if (matched == null || selector.specificity.compareTo(matched) > 0) {
            matched = selector.specificity;
          }
        }
        if (matched == null) {
          continue;
        }
        for (final declaration in rule.declarations) {
          final important = declaration.important ? 1 : 0;
          final current = winners[declaration.property];
          if (current != null &&
              (important < current.important ||
                  (important == current.important &&
                      (matched.compareTo(current.specificity) < 0 ||
                          (matched == current.specificity &&
                              order < current.order))))) {
            continue;
          }
          winners[declaration.property] = (
            declaration: declaration,
            important: important,
            specificity: matched,
            order: order,
          );
        }
      }
      return {
        for (final entry in winners.entries) entry.key: entry.value.declaration,
      };
    }

    String resolveContentImageUrl(String raw) {
      final lower = raw.toLowerCase();
      if (raw.isEmpty ||
          lower.startsWith('data:') ||
          lower.startsWith('http://') ||
          lower.startsWith('https://')) {
        return raw;
      }
      return this.document.resources.resolve(raw, baseDir: chapterBase) ?? raw;
    }

    /// 生成内容求值：字符串 / attr() / counter() / open-quote / url() 可拼接。
    _PseudoContent? pseudoContentOf(
      List<SelectorElement> ancestors,
      String pseudo, {
      required CssQuotes quotes,
      required int quoteDepth,
    }) {
      if (ancestors.isEmpty) {
        return null;
      }
      final declarations = winningPseudoDeclarations(ancestors, pseudo);
      final content = declarations['content'];
      if (content == null) {
        return null;
      }
      final value = content.value.trim();
      if (value == 'normal' || value == 'none') {
        return null;
      }
      // 伪元素规则里的计数器声明先生效（见 applyCounterMap 注释）。
      applyCounterMap(<String, String>{
        for (final entry in declarations.entries)
          if (entry.key == 'counter-reset' || entry.key == 'counter-increment')
            entry.key: entry.value.value,
      });
      final evaluated = _evaluateContentValue(
        value,
        ancestors: ancestors,
        quotes: quotes,
        quoteDepth: quoteDepth,
        counterValue: (name, style) =>
            formatCounter(cssCounters[name] ?? 0, style),
      );
      return _PseudoContent(
        text: evaluated.text,
        images: [
          for (final image in evaluated.images)
            _PseudoContentImage(
              offset: image.offset,
              url: resolveContentImageUrl(image.url),
            ),
        ],
      );
    }

    final cascadeRules = preparedStyles.cascadeRules;

    final chainStyleCache = <String, ComputedStyle>{};
    // 只给候选规则依赖结构位置的节点加身份；普通同形段落仍可共享样式。
    final viewKeys = <SelectorElement, String>{};
    final promotedInlineStyles = <SelectorElement, ComputedStyle>{};
    final fallbackViews = <EpubNode, SelectorElement>{};
    var fallbackViewId = 0;

    SelectorElement selectorViewOf(EpubNode node) {
      final original = selectorIndex.chainOf(node)?.last;
      if (original != null) return original;
      return fallbackViews.putIfAbsent(node, () {
        final (tag, attributes, children) = switch (node) {
          BlockNode() => (node.tag, node.attributes, node.children),
          InlineNode() => (node.tag, node.attributes, node.children),
          _ => (
            'reader-anonymous',
            const <String, String>{},
            const <EpubNode>[],
          ),
        };
        return _NodeView(tag, attributes, [
          for (final child in children)
            if (child is BlockNode || child is InlineNode)
              selectorViewOf(child),
        ], cacheIdentity: 'generated:${fallbackViewId++}');
      });
    }

    var figureSeq = 0;
    // P9-25：最近一次 styleForChain 的最近容器是否带可见边框。局部状态，
    // 调用后立刻读取，避免为同一链再跑一次级联。
    var containerBorderedForLastChain = false;
    // 最近一次 styleForChain 为对齐祖先盒累计到的左偏移。纯图块折叠后
    // 仍要区分「祖先容器位移」和「图片自身 margin」，否则外层 auto margin
    // 会被误当图片 margin，吞掉内层 text-align 的居中余量。
    var promotedLeftForLastChain = 0.0;
    // 嵌套 opacity（W5）：flat 管线重建块样式会丢父链，这里把级联链上的
    // 祖先累计不透明度单独记下来供 PageBlock 使用（绘制层据此 saveLayer）。
    var effectiveOpacityForLastChain = 1.0;

    /// 链式级联样式（P8-02）：链上每级元素经 Cascade.compute（UA +
    /// 作者 + 内联三源、特异性、!important、@media），继承语义由引擎
    /// 的 18 项继承表保证；前缀缓存使同容器兄弟块共享祖先计算结果。
    ComputedStyle chainStyle(List<SelectorElement> chain) {
      if (chain.isEmpty) {
        return style;
      }
      final promoted = promotedInlineStyles[chain.last];
      if (promoted != null) return promoted;
      var containing = contentWidth;
      for (final ancestor in chain.take(chain.length - 1)) {
        final box = retainedContainers[ancestor];
        if (box != null) containing = box.contentWidth;
      }
      final key = '${_chainKey(chain, viewKeys, cascadeRules)}@$containing';
      return chainStyleCache.putIfAbsent(key, () {
        final parent = chain.length > 1
            ? chainStyle(chain.sublist(0, chain.length - 1))
            : style;
        return _applyCustomFont(
          Cascade.compute(
            element: chain.last,
            ancestors: chain.sublist(0, chain.length - 1),
            rules: cascadeRules.candidatesFor(chain.last),
            inlineDeclarations: _rewriteBookFontDeclarations(
              _inlineDeclarationsOf(chain.last.attributes['style']),
            ),
            parent: parent,
            rootFontSize: style.fontSize,
            containingWidth: containing,
            viewportWidth: contentWidth,
          ),
        );
      });
    }

    double textWidthInFloat(List<SelectorElement> chain, double floatWidth) {
      var firstChild = chain.length - 1;
      for (var i = chain.length - 2; i >= 0; i--) {
        if (_floatSideOfStyle(chainStyle(chain.sublist(0, i + 1))) != null) {
          firstChild = i + 1;
          break;
        }
      }
      // 浮动内容宽不含自身占位外边距；只扣内部各层原始盒模型，避免
      // styleForChain 为绘制累加的祖先边距被重复扣除。
      var width = floatWidth;
      for (var i = firstChild; i < chain.length; i++) {
        width = chainStyle(chain.sublist(0, i + 1)).contentBoxWidth(width);
      }
      return math.max(24.0, width);
    }

    final pseudoCascadeRules = <String, CascadeRuleSet>{};

    /// 伪元素自身声明参与级联；其默认样式继承生成它的元素。
    ComputedStyle pseudoStyleFor(
      List<SelectorElement> ancestors,
      ComputedStyle parent,
      String pseudo,
    ) {
      if (ancestors.isEmpty) {
        return parent;
      }
      final rules = pseudoCascadeRules.putIfAbsent(
        pseudo,
        () => CascadeRuleSet([
          for (final (index, rule)
              in (pseudoRules[pseudo] ?? const <_AuxiliaryCssRule>[]).indexed)
            CascadeRule(
              rule: CssRule(
                selector: rule.selectorText,
                declarations: rule.declarations,
                media: rule.media,
              ),
              origin: CascadeOrigin.author,
              order: index,
            ),
        ]),
      );
      return _applyCustomFont(
        Cascade.compute(
          element: ancestors.last,
          ancestors: ancestors.sublist(0, ancestors.length - 1),
          rules: rules.candidatesFor(ancestors.last),
          parent: parent,
          rootFontSize: style.fontSize,
          containingWidth: _textWidthFor(parent),
          viewportWidth: contentWidth,
        ),
      );
    }

    CssDisplay inlineDisplay(InlineNode node, List<MarkSubject> ancestors) {
      final structural = selectorIndex.chainOf(node);
      final computed = chainStyle(
        structural ??
            [
              for (final ancestor in ancestors)
                _NodeView(ancestor.tag, ancestor.attributes, const []),
              _NodeView(node.tag, node.attributes, const []),
            ],
      );
      // ComputedStyle 的块排版缺省值是 block；仅明确的块/隐藏声明改变聚合。
      return switch (computed.values['display']?.trim().toLowerCase()) {
        'block' => CssDisplay.block,
        'none' => CssDisplay.none,
        'inline-block' => CssDisplay.inlineBlock,
        _ => CssDisplay.inline,
      };
    }

    if (displayCached?.key == _structureKey(spineIndex)) {
      document = displayCached!.document;
    } else {
      document = TextAggregator.aggregate(
        document,
        whiteSpace: style.whiteSpace,
        inlineDisplay: inlineDisplay,
      );
      _putDisplayDocumentCache(
        spineIndex,
        key: _structureKey(spineIndex),
        document: document,
        selectors: selectorIndex,
      );
      _preservedRawTexts.remove(spineIndex);
      _preservedPreLineTexts.remove(spineIndex);
    }
    chainStyleCache.clear();
    gatherImageSrcs(document.root);
    if (trace != null) {
      trace.record(
        ReaderTraceName.chapterAggregate,
        stageWatch!.elapsedMicroseconds,
        bookId: traceBook,
      );
      stageWatch.reset();
    }

    // 整页背景（P9-04）：body 的 background-image 画在页面层，不透传到块上
    // （透传会让每段文字各铺一次背景图）。
    final bodyView = _NodeView(
      'body',
      document.root.attributes,
      const <SelectorElement>[],
    );
    final bodyBackground = _pageBackgroundFrom(
      chainStyle(<SelectorElement>[bodyView]),
    );

    /// 列表项水平缩进（g）：累加祖先里每个 ul/ol 的「左边距 + 左边框 +
    /// 左内边距」。浏览器里 li 内容左缘就在这些盒内缩之后，作者写
    /// `ul { padding-left: 28px }` 时必须跟着变（旧实现写死 40px）。
    double listIndentOf(List<SelectorElement> ancestors) {
      var indent = 0.0;
      for (var i = 0; i < ancestors.length; i++) {
        final tag = ancestors[i].tag.toLowerCase();
        if (tag != 'ul' && tag != 'ol') {
          continue;
        }
        final style = chainStyle(ancestors.sublist(0, i + 1));
        indent +=
            style.margin.left + style.borders.left.width + style.padding.left;
      }
      return indent;
    }

    /// `list-style-position: inside` 的首行缩进 = 标记宽 + 间隙。
    ///
    /// 实测 Chromium：文字标记的缩进 = 标记字形宽 + 0.333em；符号标记
    /// （disc/circle/square，引擎按几何图形绘制）的标记框宽约 1.067em，
    /// 同样再加 0.333em 间隙。
    double insideMarkerIndent(String marker, ComputedStyle style) {
      const gapEm = 0.333;
      const symbolAdvanceEm = 1.067;
      final isSymbol = marker == '•' || marker == '○' || marker == '▪';
      final advance = isSymbol
          ? style.fontSize * symbolAdvanceEm
          : _layoutCache
                .layout(text: marker, style: style, maxWidth: contentWidth)
                .lines
                .first
                .width;
      return advance + style.fontSize * gapEm;
    }

    /// CSS `vertical-align` → 行内盒的竖直对齐（引擎只区分四种）。
    InlineBoxVerticalAlign inlineBoxAlignOf(CssVerticalAlign align) =>
        switch (align) {
          CssVerticalAlign.top => InlineBoxVerticalAlign.top,
          CssVerticalAlign.bottom => InlineBoxVerticalAlign.bottom,
          CssVerticalAlign.middle => InlineBoxVerticalAlign.middle,
          _ => InlineBoxVerticalAlign.baseline,
        };

    List<SelectorElement> inlineMarkChain(
      InlineMark mark,
      List<SelectorElement> ancestors,
    ) {
      // CSS 提升的 span 也可能是当前块；按来源属性身份截去已在上下文中的链。
      final start =
          mark.chain.lastIndexWhere(
            (subject) => ancestors.any(
              (ancestor) =>
                  ancestor.tag == subject.tag &&
                  identical(ancestor.attributes, subject.attributes),
            ),
          ) +
          1;
      return [
        ...ancestors,
        for (final subject in mark.chain.skip(start))
          _NodeView(
            subject.tag.toLowerCase(),
            subject.attributes.containsKey('class') || subject.classes.isEmpty
                ? subject.attributes
                : {'class': subject.classes.join(' '), ...subject.attributes},
            const <SelectorElement>[],
          ),
      ];
    }

    ComputedStyle inlineMarkStyle(
      InlineMark mark,
      _InlineStyleContext context,
    ) {
      final chain = inlineMarkChain(mark, context.ancestors);
      var parent = context.style;
      // 正文覆盖已作用于块样式；行内后缀从最终父样式继承，不再重算作者块。
      // 表格与标题传入各自原样式，继续保留作者的字号策略。
      for (var i = context.ancestors.length; i < chain.length; i++) {
        parent = Cascade.compute(
          element: chain[i],
          ancestors: chain.sublist(0, i),
          rules: cascadeRules.candidatesFor(chain[i]),
          inlineDeclarations: _rewriteBookFontDeclarations(
            _inlineDeclarationsOf(chain[i].attributes['style']),
          ),
          parent: parent,
          rootFontSize: style.fontSize,
          containingWidth: context.width,
          viewportWidth: contentWidth,
        );
      }
      final readerFontFamily = _overrides.isCustomFont
          ? null
          : context.readerFontFamily;
      return _applyCustomFont(
        readerFontFamily == null
            ? parent
            : parent.withTypography(fontFamily: readerFontFamily),
      );
    }

    List<StyledRun> resolveInlineRuns(
      List<InlineMark> marks,
      _InlineStyleContext context,
    ) {
      if (marks.isEmpty) {
        return const <StyledRun>[];
      }
      final boundaries = <int>{0};
      for (final mark in marks) {
        boundaries
          ..add(mark.start)
          ..add(mark.end);
      }
      final ordered = boundaries.toList()..sort();
      final runs = <StyledRun>[];
      for (var i = 0; i < ordered.length - 1; i++) {
        final start = ordered[i];
        final end = ordered[i + 1];
        ComputedStyle? resolved;
        var resolvedDepth = -1;
        for (final mark in marks) {
          if (mark.start > start || end > mark.end || mark.chain.isEmpty) {
            continue;
          }
          if (mark.chain.length < resolvedDepth) continue;
          final computed = inlineMarkStyle(mark, context);
          if (computed.explicitProperties.isEmpty) {
            continue;
          }
          // 聚合标记按子→父关闭，优先最深的完整级联，避免外层盖掉内层。
          resolved = computed;
          resolvedDepth = mark.chain.length;
        }
        if (resolved != null) {
          runs.add(
            StyledRun(
              start: start,
              end: end,
              style: resolved,
              // 上下标位移（P9-07）：引擎只提供位移量，必须由调用方写进
              // run，否则 vertical-align: super/sub 在真书里不生效。
              baselineShift: resolved.verticalAlignShift,
            ),
          );
        }
      }
      return runs;
    }

    bool inlineDescendantOf(InlineMark child, InlineMark parent) =>
        parent.chain.isNotEmpty &&
        child.chain.length > parent.chain.length &&
        child.start >= parent.start &&
        child.end <= parent.end &&
        identical(
          child.chain[parent.chain.length - 1].attributes,
          parent.chain.last.attributes,
        );

    List<InlineBoxSpec> appendInlineBox(
      List<InlineBoxSpec> existingBoxes,
      _InlineFloatExtraction extracted,
    ) => [
      for (final existing in existingBoxes)
        existing.atOffset(extracted.remapOffset(existing.offset)),
      if (extracted.inlineBox != null) extracted.inlineBox!,
    ];

    PageBlock inlineImagePayload(
      ComputedStyle imageStyle,
      List<SelectorElement> chain,
      String url,
      ImageDisplaySize size,
    ) {
      final fit = objectFitBackground(
        chain,
        _intrinsicSizeOfUrl(url),
        boxWidth: size.width,
        boxHeight: size.height,
      );
      final payloadStyle = ComputedStyle({
        ...imageStyle.values,
        'background-image': 'url($url)',
        'background-size': rawDeclarationsFor(chain).containsKey('object-fit')
            ? fit.size
            : '100% 100%',
        'background-position': fit.position,
        'background-repeat': 'no-repeat',
        'background-origin': 'content-box',
      });
      return PageBlock(
        layout: TextLayoutResult(
          text: '',
          lines: const [],
          width: size.width,
          height: size.height,
          maxWidth: size.width,
        ),
        style: payloadStyle,
      );
    }

    InlineBoxSpec inlineImageBox(
      InlineImageSpec image,
      ComputedStyle imageStyle,
      List<SelectorElement> chain,
      double availableWidth,
    ) {
      final size = _inlineImageSize(
        imageStyle,
        _intrinsicSizeOfUrl(image.url),
        availableWidth,
      );
      return InlineBoxSpec(
        offset: image.offset,
        replacesPlaceholder: true,
        width: size.width,
        height: size.height,
        verticalAlign: inlineBoxAlignOf(imageStyle.verticalAlign),
        marginLeft: imageStyle.margin.left,
        marginRight: imageStyle.margin.right,
        marginTop: imageStyle.margin.top,
        marginBottom: imageStyle.margin.bottom,
        contentBaseline: size.height,
        payload: inlineImagePayload(imageStyle, chain, image.url, size),
      );
    }

    /// 行内元素浮动提取（W17）。
    ///
    /// `span.talent-tag { float: right }` / `img.avatar { float: left }`
    /// 这类浮动挂在**行内元素**上，flat 管线里它们只是行内 run，永远不会
    /// 变成块，浮动因此完全不生效。这里把它们从段落文本流里摘出来，生成
    /// 独立浮动块（位置/绕排沿用块级浮动机制，段落行靠 offsetX 收窄），
    /// 只处理段落**开头或结尾**的行内浮动（真书的标签/头像都在段首或段
    /// 尾；段中间的行内浮动需要行级切分，属引擎核心能力）。
    _InlineFloatExtraction? extractInlineFloat({
      required String text,
      required List<InlineMark> marks,
      required List<InlineImageMark> images,
      required _InlineStyleContext context,
    }) {
      if (marks.isEmpty) {
        return null;
      }
      final ancestors = context.ancestors;
      final availableWidth = context.width;

      for (final mark in marks) {
        if (mark.chain.isEmpty || mark.end < mark.start) {
          continue;
        }
        // 图片标记（占位符）交给下面的图片分支处理，避免把 U+FFFC 当成
        // 文本浮动块（占位符宽 1em，图片会缩成 16px）。
        final markTag = mark.tag.toLowerCase();
        if (markTag == 'img' || markTag == 'image') {
          continue;
        }
        final inlineStyle = inlineMarkStyle(mark, context);
        final side = _floatSideOfStyle(inlineStyle);
        // `display: inline-block`：盒子交给行排版（T1 的 InlineBoxSpec），
        // 宽高含 padding/border，整块不跨行、放不下换行。
        final inlineBlock =
            side == null && inlineStyle.display == CssDisplay.inlineBlock;
        if (side == null && !inlineBlock) {
          continue;
        }
        // 聚合标记按子到父关闭；先提取最外原子盒，避免内盒成为正文兄弟。
        if (marks.any(
          (parent) =>
              inlineDescendantOf(mark, parent) &&
              inlineMarkStyle(parent, context).display ==
                  CssDisplay.inlineBlock,
        )) {
          continue;
        }
        final rawContent = text.substring(mark.start, mark.end);
        final children = [
          for (final child in marks)
            if (inlineDescendantOf(child, mark)) child,
        ];
        bool hasBoxAt(int boundary, {required bool end}) => children.any(
          (child) =>
              (end ? child.end : child.start) == boundary &&
              inlineMarkStyle(child, context).display == CssDisplay.inlineBlock,
        );
        final leftTrimmed = hasBoxAt(mark.start, end: false)
            ? rawContent
            : rawContent.trimLeft();
        final content = hasBoxAt(mark.end, end: true)
            ? leftTrimmed
            : leftTrimmed.trimRight();
        if (content.isEmpty && !inlineBlock) {
          continue;
        }
        final model = BoxModel.fromStyle(
          inlineStyle,
          containingWidth: availableWidth,
        );
        final contentStart =
            mark.start + rawContent.length - leftTrimmed.length;
        final contentMarks = [
          for (final child in children)
            InlineMark(
              start: (child.start - contentStart).clamp(0, content.length),
              end: (child.end - contentStart).clamp(0, content.length),
              tag: child.tag,
              classes: child.classes,
              chain: child.chain,
            ),
        ];
        var contentWidthLimit = math.max(
          content.isEmpty ? 0.0 : 1.0,
          model.resolveContentWidth(availableWidth),
        );
        ({String text, List<InlineMark> marks, List<InlineBoxSpec> boxes})
        extractContentBoxes(_InlineStyleContext innerContext) {
          var innerText = content;
          var innerMarks = contentMarks;
          var boxes = <InlineBoxSpec>[];
          for (var i = 0; i < contentMarks.length; i++) {
            final extracted = extractInlineFloat(
              text: innerText,
              marks: innerMarks,
              images: const [],
              context: innerContext,
            );
            if (extracted == null || extracted.block != null) break;
            innerText = extracted.text;
            innerMarks = extracted.marks;
            boxes = appendInlineBox(boxes, extracted);
          }
          return (text: innerText, marks: innerMarks, boxes: boxes);
        }

        TextLayoutResult layoutContent() {
          final innerContext = (
            ancestors: inlineMarkChain(mark, context.ancestors),
            style: inlineStyle,
            width: contentWidthLimit,
            readerFontFamily: context.readerFontFamily,
          );
          final flow = extractContentBoxes(innerContext);
          final runs = resolveInlineRuns(flow.marks, innerContext);
          if (flow.boxes.isNotEmpty) {
            return TextLayoutEngine.layout(
              text: flow.text,
              style: inlineStyle,
              maxWidth: contentWidthLimit,
              runs: runs,
              inlineBoxes: flow.boxes,
              hasGlyph: _hasBookFontGlyph,
            );
          }
          return flow.text.isEmpty
              ? TextLayoutResult(
                  text: '',
                  lines: const [],
                  width: 0,
                  height: 0,
                  maxWidth: contentWidthLimit,
                )
              : _layoutCache.layout(
                  text: flow.text,
                  style: inlineStyle,
                  maxWidth: contentWidthLimit,
                  runs: runs,
                  hasGlyph: _hasBookFontGlyph,
                );
        }

        var layout = layoutContent();
        PageBlock? floatBlock;
        InlineBoxSpec? boxSpec;
        if (inlineBlock) {
          // 自动宽标签按内容收缩，整盒换行；背景、边框与文字共享几何。
          if (model.contentWidth == null) {
            final preferred =
                layout.width + model.horizontalInset + model.margin.horizontal;
            contentWidthLimit = math.max(
              content.isEmpty ? 0.0 : 1.0,
              model.resolveContentWidth(
                inlineStyle.whiteSpace == CssWhiteSpace.nowrap
                    ? preferred
                    : math.min(availableWidth, preferred),
              ),
            );
            layout = layoutContent();
          }
          final contentHeightValue = model.resolveContentHeight(
            layout.height,
            containingHeight: contentHeight,
          );
          boxSpec = InlineBoxSpec(
            offset: mark.start,
            width: model.borderBoxWidth(contentWidthLimit),
            height: model.borderBoxHeight(contentHeightValue),
            verticalAlign: inlineBoxAlignOf(inlineStyle.verticalAlign),
            marginLeft: inlineStyle.margin.left,
            marginRight: inlineStyle.margin.right,
            marginTop: inlineStyle.margin.top,
            marginBottom: inlineStyle.margin.bottom,
            // 保留内容排版高；实测基线路径以 margin 盒与文字 strut 合成行高。
            contentHeight: layout.height,
            // CSS 2.2 §10.8.1：取实际末行基线；无行或非 visible 取底部 margin。
            contentBaseline:
                layout.lines.isEmpty ||
                    inlineStyle.overflow != CssOverflow.visible
                ? model.borderBoxHeight(contentHeightValue) +
                      model.margin.bottom
                : model.padding.top +
                      model.borders.top +
                      layout.lines.last.baseline,
            // 绘制载荷：盒子内部已构建好的块（背景/边框/文字都在其中），
            // 绘制层按 placement 矩形把它画在行内。
            payload: PageBlock.styled(
              layout: layout,
              style: inlineStyle,
              containingWidth: contentWidth,
            ),
          );
        } else {
          if (inlineStyle.width == null) {
            // 行内浮动没有声明宽时按 shrink-to-fit 处理：浮动盒宽 = 内容宽
            //（分页器读 maxWidth 当声明宽，不收缩会把整行都占掉）。
            layout = withLayoutWidth(layout, maxWidth: layout.width);
          }
          floatBlock = _floatedTextBlock(
            layout: layout,
            style: inlineStyle,
            side: side!,
            spaceBefore: inlineStyle.margin.top,
            spaceAfter: inlineStyle.margin.bottom,
            containingLeft:
                context.style.margin.left +
                context.style.borders.left.width +
                context.style.padding.left,
            containingWidth: context.width,
          );
        }
        // 从段落文本里摘掉这段内容，其余偏移重映射。
        // - 行内浮动：连相邻一个空格一起摘（浮动脱离文本流，留空格会多算宽度）；
        // - 行内块：**保留元素边界处的空格**（CSS 里 inline-block 前后空白是
        //   保留的，只有行首/行尾才折叠）——否则 53 的行宽会比浏览器少 4.36。
        var removeStart = mark.start;
        var removeEnd = mark.end;
        if (side != null) {
          if (removeEnd < text.length && text[removeEnd] == ' ') {
            removeEnd += 1;
          } else if (removeStart > 0 && text[removeStart - 1] == ' ') {
            removeStart -= 1;
          }
        }
        final removed = removeEnd - removeStart;
        final newText =
            text.substring(0, removeStart) + text.substring(removeEnd);
        int remap(int offset) {
          if (offset <= removeStart) {
            return offset;
          }
          if (offset >= removeEnd) {
            return offset - removed;
          }
          return removeStart;
        }

        final newMarks = <InlineMark>[
          for (final other in marks)
            if (!identical(other, mark) &&
                !inlineDescendantOf(other, mark) &&
                (other.end <= removeStart ||
                    other.start >= removeEnd ||
                    inlineDescendantOf(mark, other)))
              InlineMark(
                start: remap(other.start),
                end: remap(other.end),
                tag: other.tag,
                classes: other.classes,
                chain: other.chain,
              ),
        ];
        final extractedFootnote = inlineBlock
            ? footnoteForReference(
                mark.tag,
                mark.chain.isEmpty
                    ? const <String, String>{}
                    : mark.chain.last.attributes,
                rawContent,
                start: removeStart,
                end: removeStart + 1,
              )
            : null;
        return _InlineFloatExtraction(
          text: newText,
          marks: newMarks,
          block: floatBlock,
          // 行内盒插在摘除点（盒内内容已由 payload 提供）。
          inlineBox: boxSpec == null
              ? null
              : InlineBoxSpec(
                  offset: removeStart,
                  width: boxSpec.width,
                  height: boxSpec.height,
                  verticalAlign: boxSpec.verticalAlign,
                  marginLeft: boxSpec.marginLeft,
                  marginRight: boxSpec.marginRight,
                  marginTop: boxSpec.marginTop,
                  marginBottom: boxSpec.marginBottom,
                  baselineOffset: boxSpec.baselineOffset,
                  contentHeight: boxSpec.contentHeight,
                  contentBaseline: boxSpec.contentBaseline,
                  payload: boxSpec.payload,
                ),
          footnote: extractedFootnote,
          remapOffset: remap,
          removeStart: removeStart,
          removeEnd: removeEnd,
        );
      }
      // 行内图片浮动（`img.avatar { float: left }`）：占位符从文本流摘掉，
      // 图片按自身 CSS/属性尺寸生成浮动块。
      for (final imageMark in images) {
        final attributes = imageMark.node.attributes;
        final src = attributes['src'] ?? attributes['xlink:href'];
        if (src == null || src.isEmpty || imageMark.offset >= text.length) {
          continue;
        }
        final imageStyle = chainStyle(<SelectorElement>[
          ...ancestors,
          _NodeView(imageMark.node.tag, attributes, const <SelectorElement>[]),
        ]);
        final side = _floatSideOfStyle(imageStyle);
        if (side == null) {
          continue;
        }
        final url =
            this.document.resources.resolve(src, baseDir: chapterBase) ?? src;
        final size = _resolveImageDisplaySize(
          attributes,
          _intrinsicSizeOfUrl(url),
          contentWidth,
          contentHeight,
          cssWidth: imageStyle.width?.resolve(contentWidth),
          cssHeight: imageStyle.height?.resolve(contentHeight),
          cssMaxWidth: imageStyle.maxWidth?.resolve(contentWidth),
          cssMaxHeight: imageStyle.maxHeight?.resolve(contentHeight),
          aspectRatio: imageStyle.aspectRatio,
        );
        final objectFit = objectFitBackground(
          <SelectorElement>[
            ...ancestors,
            _NodeView(
              imageMark.node.tag,
              attributes,
              const <SelectorElement>[],
            ),
          ],
          _intrinsicSizeOfUrl(url),
          boxWidth: size.$1,
          boxHeight: size.$2,
        );
        final imageBlockStyle = ComputedStyle(<String, String>{
          // 保住 img 自身的盒模型/边距与继承样式；只用 baseStyle 会吞掉
          // `img { margin: ...; padding: ...; border: ... }`。
          ...imageStyle.values,
          'background-image': 'url($url)',
          'background-size': objectFit.size,
          'background-position': objectFit.position,
          'background-repeat': 'no-repeat',
        });
        final layout = TextLayoutResult(
          text: '',
          lines: [
            LineBox(
              start: 0,
              end: 0,
              top: 0,
              height: size.$2,
              baseline: size.$2,
              width: size.$1,
            ),
          ],
          width: size.$1,
          height: size.$2,
          maxWidth: size.$1,
          runs: const <StyledRun>[],
        );
        final block = _floatedTextBlock(
          layout: layout,
          style: imageBlockStyle,
          side: side,
          spaceBefore: imageBlockStyle.margin.top,
          spaceAfter: imageBlockStyle.margin.bottom,
          containingLeft:
              context.style.margin.left +
              context.style.borders.left.width +
              context.style.padding.left,
          containingWidth: context.width,
        );
        final removeStart = imageMark.offset;
        final removeEnd = imageMark.offset + 1;
        final newText =
            text.substring(0, removeStart) + text.substring(removeEnd);
        int remap(int offset) {
          if (offset <= removeStart) {
            return offset;
          }
          if (offset >= removeEnd) {
            return offset - 1;
          }
          return removeStart;
        }

        return _InlineFloatExtraction(
          text: newText,
          inlineBox: null,
          marks: <InlineMark>[
            for (final other in marks)
              if (other.end <= removeStart || other.start >= removeEnd)
                InlineMark(
                  start: remap(other.start),
                  end: remap(other.end),
                  tag: other.tag,
                  classes: other.classes,
                  chain: other.chain,
                ),
          ],
          block: block,
          remapOffset: remap,
          removeStart: removeStart,
          removeEnd: removeEnd,
        );
      }
      return null;
    }

    TextLayoutResult layoutCellContent(
      String text,
      List<InlineMark> marks,
      List<SelectorElement> ancestors,
      ComputedStyle cellStyle,
      double width,
    ) {
      var remainingText = text;
      var remainingMarks = marks;
      var boxes = <InlineBoxSpec>[];
      final context = (
        ancestors: ancestors,
        style: cellStyle,
        width: width,
        readerFontFamily: null,
      );
      for (var i = 0; i < marks.length; i++) {
        final extracted = extractInlineFloat(
          text: remainingText,
          marks: remainingMarks,
          images: const [],
          context: context,
        );
        // 格内浮动仍沿用原来的文字近似，避免在此丢弃脱流内容。
        if (extracted == null || extracted.block != null) break;
        remainingText = extracted.text;
        remainingMarks = extracted.marks;
        boxes = appendInlineBox(boxes, extracted);
      }
      final runs = resolveInlineRuns(remainingMarks, context);
      return boxes.isEmpty
          ? _layoutCache.layout(
              text: remainingText,
              style: cellStyle,
              maxWidth: width,
              runs: runs,
              hasGlyph: _hasBookFontGlyph,
            )
          : TextLayoutEngine.layout(
              text: remainingText,
              style: cellStyle,
              maxWidth: width,
              runs: runs,
              inlineBoxes: boxes,
              hasGlyph: _hasBookFontGlyph,
            );
    }

    /// 块级样式入口（P8-02）：链式级联结果 + 容器盒类近似传导 +
    /// 引用深度边距叠加。P8-05c：容器的上下边框拼合——首个后代块画
    /// 上边框、末个画下边框（flat 无嵌套盒子的面板整框近似）。
    ComputedStyle styleForChain(
      List<SelectorElement> chain, {
      int quoteDepth = 0,
      bool firstInContainer = false,
      bool lastInContainer = false,
      double listIndent = 0,
      double firstLineIndent = 0,
      CssListStylePosition? listPosition,
    }) {
      containerBorderedForLastChain = false;
      promotedLeftForLastChain = 0;
      final computed = chainStyle(chain);
      effectiveOpacityForLastChain = computed.effectiveOpacity;
      // 容器盒类近似传导：flat 无嵌套盒子，祖先的背景/左右边框/
      // 左右内边距透传给子块（子块自身声明优先；水平间距相加）。
      final promoted = <String, String>{};
      var extraLeft = 0.0;
      var extraRight = 0.0;
      for (var i = 0; i < chain.length - 1; i++) {
        // 列表容器（ul/ol/li）的水平缩进由 li 的 UA margin-left 承担
        // （flat 近似），不再经盒传导叠加（避免 40+40 双重缩进）。
        // body/html 的盒属性由阅读器接管（页面边距/整页背景走各自通道），
        // 也不能透传到每个正文块——否则书籍 body 背景色会盖住主题背景。
        final ancestorTag = chain[i].tag;
        if (ancestorTag == 'ul' ||
            ancestorTag == 'ol' ||
            ancestorTag == 'li' ||
            ancestorTag == 'body' ||
            ancestorTag == 'html') {
          continue;
        }
        final ancStyle = chainStyle(chain.sublist(0, i + 1));
        final retained = retainedContainers[chain[i]];
        if (retained != null) {
          // 后代使用容器内容区；右侧同时吸收容器声明宽留下的空白。
          extraLeft = retained.contentLeft;
          extraRight =
              contentWidth - retained.contentLeft - retained.contentWidth;
          continue;
        }
        if (i == chain.length - 2 && ancStyle.borders.hasBorder) {
          containerBorderedForLastChain = true;
        }
        final values = ancStyle.values;
        for (final prop in _promotedBoxProps) {
          final value = values[prop];
          if (value != null) {
            promoted[prop] = value;
          }
        }
        // 上下边框拼合（P8-05c）：只画在容器首个/末个可见后代块上。
        final isNearestContainer = i == chain.length - 2;
        if (isNearestContainer) {
          final top = ancStyle.borders.top;
          if (firstInContainer && top.width > 0) {
            promoted['border-top'] =
                '${top.width}px ${_borderStyleName(top.style)} '
                '#${_colorToHex(top.color)}';
          }
          final bottom = ancStyle.borders.bottom;
          if (lastInContainer && bottom.width > 0) {
            promoted['border-bottom'] =
                '${bottom.width}px ${_borderStyleName(bottom.style)} '
                '#${_colorToHex(bottom.color)}';
          }
          // 容器上下内边距同样拼合到首个/末个后代块上（P9-03）：
          // 只透传左右内边距会让面板上下贴字，没有内边距的呼吸感。
          if (firstInContainer && ancStyle.padding.top > 0) {
            promoted['padding-top'] = '${ancStyle.padding.top}px';
          }
          if (lastInContainer && ancStyle.padding.bottom > 0) {
            promoted['padding-bottom'] = '${ancStyle.padding.bottom}px';
          }
        }
        extraLeft += ancStyle.padding.left + ancStyle.margin.left;
        extraRight += ancStyle.padding.right + ancStyle.margin.right;
      }
      // 引用深度（M2→P8-02 语义演进）：blockquote 的 UA 左右边距经
      // 盒传导逐层累加（嵌套两层 80px，与 CSS 盒嵌套近似一致），
      // quoteDepth 不再叠加（避免双重计算）。
      if (promoted.isEmpty &&
          extraLeft == 0 &&
          extraRight == 0 &&
          listIndent == 0 &&
          firstLineIndent == 0) {
        return computed;
      }
      // 列表缩进（g）：li 的水平缩进来自列表容器的级联盒，不再靠 UA 的
      // 40px 近似；`list-style-position: inside` 的首行缩进走 text-indent
      //（行排版器只作用首行，与浏览器「标记并入首行」一致）。
      extraLeft += listIndent;
      promotedLeftForLastChain = extraLeft;
      final declarations = <String, String>{...promoted, ...computed.values};
      if (extraLeft > 0) {
        declarations['margin-left'] = '${computed.margin.left + extraLeft}px';
      }
      if (extraRight > 0) {
        declarations['margin-right'] =
            '${computed.margin.right + extraRight}px';
      }
      if (firstLineIndent > 0) {
        declarations['text-indent'] =
            '${computed.textIndent + firstLineIndent}px';
      }
      if (listPosition != null) {
        // 列表项重建样式时父链换成了阅读器基础样式，`list-style-position`
        // 的继承会丢（CSS 里它是继承属性），必须显式带上容器值。
        declarations['list-style-position'] = switch (listPosition) {
          CssListStylePosition.inside => 'inside',
          CssListStylePosition.outside => 'outside',
        };
      }
      // 容器 padding/border 折算子块内缩（复用盒传导声明）。
      return ComputedStyle(
        declarations,
        parent: style,
        explicitProperties: declarations.keys.toSet(),
        declaredTextProperties: computed.declaredTextProperties,
        hasExplicitTextColor: computed.hasExplicitTextColor,
        containingWidth: contentWidth,
        rootFontSize: style.fontSize,
      );
    }

    /// 兼容入口：按（标签, 属性）构造单元素视图走链式级联。
    ComputedStyle styleFor(
      String tag, {
      Map<String, String>? attributes,
      int quoteDepth = 0,
    }) {
      final self = _NodeView(
        tag,
        attributes ?? const <String, String>{},
        const <SelectorElement>[],
      );
      return styleForChain(<SelectorElement>[self], quoteDepth: quoteDepth);
    }

    /// 行内样式区间（P8-02）：聚合标记链（块级 + 行内祖先 → 自身）转
    /// 匹配视图走引擎级联；自身有显式声明的区间产出 StyledRun。
    /// 浮动方向检测（flat 管线接入）：内联 style `float:`、历史 `align`
    /// 属性、作者 CSS class 规则三处来源（P8-02：CSS 规则经引擎级联）。
    FloatSide? floatSideOf(
      Map<String, String> attributes, {
      List<SelectorElement> ancestors = const <SelectorElement>[],
    }) {
      final inline = attributes['style'] ?? '';
      final inlineMatch = RegExp(
        r'float\s*:\s*(left|right)',
        caseSensitive: false,
      ).firstMatch(inline);
      if (inlineMatch != null) {
        return inlineMatch.group(1)!.toLowerCase() == 'left'
            ? FloatSide.left
            : FloatSide.right;
      }
      final align = attributes['align']?.toLowerCase();
      if (align == 'left' || align == 'right') {
        return align == 'left' ? FloatSide.left : FloatSide.right;
      }
      final view = _NodeView('img', <String, String>{
        if (attributes['class'] != null) 'class': attributes['class']!,
      }, const <SelectorElement>[]);
      final imgStyle = chainStyle([...ancestors, view]);
      final declared = imgStyle.values['float']?.toLowerCase();
      if (declared == 'left' || declared == 'right') {
        return declared == 'left' ? FloatSide.left : FloatSide.right;
      }
      // P8-06：display:inline-block 的小图按左浮近似——后续文字绕排
      // 右侧，获得「头像+名」类并排视觉（flat 无行内盒的真实近似）。
      // 限定显式小尺寸（宽属性 ≤200px），大图仍走普通块。
      if (imgStyle.display == CssDisplay.inlineBlock) {
        final widthAttr = double.tryParse(
          (attributes['width'] ?? '').replaceAll(RegExp(r'[^0-9.]'), ''),
        );
        if (widthAttr != null && widthAttr > 0 && widthAttr <= 200) {
          return FloatSide.left;
        }
      }
      return null;
    }

    void collectImageBlock(
      BlockNode node,
      List<SelectorElement> ancestors, {
      FloatSide? containerFloat,
      double? containerFloatWidth,
      int containerFloatGroup = 0,
      List<PageFootnote> footnotes = const <PageFootnote>[],
    }) {
      // src 键名兼容 SVG <image xlink:href> 折叠链。
      final src = node.attributes['src'] ?? node.attributes['xlink:href'];
      if (src == null || src.isEmpty) {
        return;
      }
      final url =
          this.document.resources.resolve(src, baseDir: chapterBase) ?? src;
      // 图片自身 CSS（P9-08）：img.xxx { width: 36px; height: auto } 这类
      // 声明的尺寸必须优先于表现属性，否则插图/头像会按整宽绘制。
      // 折叠块的容器链（P9-22）：纯图块折叠丢掉的外层容器（如
      // `div.textdE1 { duokan-bleed }`）在这里补回级联链。
      final foldedChain = node.containerChain.isEmpty
          ? ancestors
          : <SelectorElement>[
              for (final hint in node.containerChain)
                _NodeView(
                  hint.tag,
                  hint.classes.isEmpty
                      ? const <String, String>{}
                      : <String, String>{'class': hint.classes},
                  const <SelectorElement>[],
                ),
            ];
      final imageView = _NodeView(
        node.tag,
        node.attributes,
        const <SelectorElement>[],
      );
      final imageChain = <SelectorElement>[...foldedChain, imageView];
      final imageStyle = styleForChain(imageChain);
      final intrinsic = imageSizes[url] ?? _intrinsicSizeOfUrl(url);
      final promotedLeft = promotedLeftForLastChain;
      // 图片块：祖先累计 opacity 同样透传（嵌套容器里的半透明图）。
      final imageOpacity = effectiveOpacityForLastChain;
      // 出血图（P9-22）：显示宽按页面宽（正文宽 + 页边距）计算，
      // 否则横幅只按正文宽缩放，左右留白与多看/阅微不一致。
      final bleed = imageStyle.bleed;
      final pageInsetLeft = _overrides.padding?.left ?? 0;
      final pageInsetRight = _overrides.padding?.right ?? 0;
      final bleedWidth =
          contentWidth +
          (bleed.left ? pageInsetLeft : 0) +
          (bleed.right ? pageInsetRight : 0);
      // 纯图块会被聚合器提升到父容器之外，祖先宽度只保留在
      // `containerChain` 中。这里重走折叠链求可用内容宽，否则
      // `div{width:35%} img{width:100%}` 会把图片放大到整页正文宽。
      var imageContainingWidth = bleedWidth;
      if (!bleed.left && !bleed.right) {
        var availableWidth = contentWidth;
        for (var i = 0; i < foldedChain.length; i++) {
          final tag = foldedChain[i].tag;
          if (tag == 'body' || tag == 'html') {
            continue;
          }
          final containerStyle = chainStyle(foldedChain.sublist(0, i + 1));
          final model = BoxModel.fromStyle(
            containerStyle,
            containingWidth: availableWidth,
          );
          final resolvedWidth = model.resolveContentWidth(availableWidth);
          availableWidth = resolvedWidth;
        }
        imageContainingWidth = availableWidth;
      }
      var size = _resolveImageDisplaySize(
        node.attributes,
        intrinsic,
        imageContainingWidth,
        contentHeight,
        cssWidth: imageStyle.width?.resolve(imageContainingWidth),
        cssHeight: imageStyle.height?.resolve(contentHeight),
        cssMaxWidth: imageStyle.maxWidth?.resolve(imageContainingWidth),
        cssMaxHeight: imageStyle.maxHeight?.resolve(contentHeight),
        aspectRatio: imageStyle.aspectRatio,
      );
      // max-width 会在绘制期把边框盒收窄；图片高度必须同步按比例收窄，
      // 否则 `<img style="max-width:60%; height:auto">` 会得到一个过高的
      // 盒子，contain 绘制后上下出现大块空白。
      if (imageStyle.maxWidth != null) {
        final constrainedWidth = BoxModel.fromStyle(
          imageStyle,
          containingWidth: imageContainingWidth,
        ).resolveContentWidth(imageContainingWidth);
        if (constrainedWidth < size.$1) {
          size = (constrainedWidth, size.$2 * constrainedWidth / size.$1);
        }
      }
      // 容器级浮动（W12）：`.avatar` 这类浮动挂在图片外面的容器/行内
      // 元素上，图片自身没有 float 属性，这里用容器浮动兜底。纯图块被
      // 聚合器折叠时容器不在祖先链上（只留 containerChain 提示），
      // 所以再按折叠链逐层查一次 float。
      FloatSide? chainFloat;
      double? chainFloatWidth;
      for (var i = foldedChain.length; i >= 1; i -= 1) {
        final chainStyleValue = chainStyle(foldedChain.sublist(0, i));
        final side = _floatSideOfStyle(chainStyleValue);
        if (side != null) {
          chainFloat = side;
          chainFloatWidth = _textWidthFor(chainStyleValue);
          break;
        }
      }
      final floatSide =
          floatSideOf(node.attributes, ancestors: foldedChain) ??
          containerFloat ??
          chainFloat;
      final floatColumnWidth = containerFloat != null
          ? containerFloatWidth
          : chainFloatWidth;
      if (floatSide != null) {
        // 浮动图钳宽（≤45% 正文宽），高按原始比例换算（P3-12 绕排前提）。
        final maxW = contentWidth * 0.45;
        var w = size.$1;
        var h = size.$2;
        if (w > maxW) {
          h = h * maxW / w;
          w = maxW;
        }
        size = (w, h);
      }
      var blockWidth = floatSide != null ? size.$1 : contentWidth;
      if (floatSide != null && floatColumnWidth != null) {
        // 容器浮动（多列网格）：图片按容器内容宽收窄，否则会把整列撑满。
        blockWidth = math.min(blockWidth, floatColumnWidth);
        if (size.$1 > blockWidth) {
          size = (blockWidth, size.$2 * blockWidth / size.$1);
        }
      }
      // object-fit（W20）：解析书籍样式里的 object-fit，映射成图片背景
      // 的铺法；未声明时保持 contain（等比完整显示，P9-08 原行为）。
      final objectFit = objectFitBackground(
        <SelectorElement>[
          ...foldedChain,
          _NodeView(node.tag, node.attributes, const <SelectorElement>[]),
        ],
        intrinsic,
        boxWidth: size.$1,
        boxHeight: size.$2,
      );
      final imageModel = BoxModel.fromStyle(
        imageStyle,
        containingWidth: imageContainingWidth,
      );
      // styleForChain 把祖先 margin/padding 折算进图片 margin 只为摆放整块；
      // 图片自身的 auto margin 必须以画廊内容宽重新解算，不能把两层偏移
      // 混在一起后再拿来计算 text-align 的剩余空间。
      final baseImageStyle = chainStyle(imageChain);
      final ownImageStyle = ComputedStyle(
        baseImageStyle.values,
        parent: baseImageStyle,
        explicitProperties: baseImageStyle.explicitProperties,
        containingWidth: imageContainingWidth,
      );
      final inlineLevel =
          ownImageStyle.display == CssDisplay.inline ||
          ownImageStyle.display == CssDisplay.inlineBlock;
      var usedMarginLeft = promotedLeft + ownImageStyle.margin.left;
      final widthIsAuto =
          ownImageStyle.width == null || ownImageStyle.width!.isAuto;
      final autoMargins =
          widthIsAuto &&
          (ownImageStyle.marginLeftIsAuto || ownImageStyle.marginRightIsAuto);
      if (floatSide == null &&
          !imageStyle.isOutOfFlow &&
          (autoMargins || inlineLevel)) {
        final marginBoxWidth =
            size.$1 +
            imageModel.horizontalInset +
            ownImageStyle.margin.horizontal;
        final slack = math.max(0.0, imageContainingWidth - marginBoxWidth);
        usedMarginLeft += autoMargins
            ? switch ((
                ownImageStyle.marginLeftIsAuto,
                ownImageStyle.marginRightIsAuto,
              )) {
                (true, true) => slack / 2,
                (true, false) => slack,
                _ => 0.0,
              }
            : switch (ownImageStyle.resolvedTextAlign) {
                CssTextAlign.center => slack / 2,
                CssTextAlign.end || CssTextAlign.right => slack,
                _ => 0.0,
              };
      }
      final blockStyle = ComputedStyle(<String, String>{
        // 图片块替换了原 img 盒，必须沿用 img 的盒模型与边距；否则图片
        // 与题注间距、图片之间的累计位置都会和浏览器偏离。
        ...imageStyle.values,
        // height 单独声明时 style 没有 width，边框盒会按整页宽绘制背景；
        // 写入解算后的 used width，让背景、边框与图片占位宽一致。
        'width': '${size.$1}px',
        // 纯图块已从行内提升为独立块，必须显式落成父级 text-align
        // 解出的行内左缘，否则 `width:80%; text-align:center` 会贴左。
        'margin-left': '${usedMarginLeft}px',
        'background-image': 'url($url)',
        'background-size': objectFit.size,
        // 出血图（多看 `duokan-bleed`）：块盒被撑到页面边缘后，`contain`
        // 会把图在更高的盒子里居中，看起来顶部多出一截安全区。出血方向
        // 改成贴边对齐，图才能贴住屏幕边。
        'background-position': bleed.top
            ? 'center top'
            : (bleed.bottom ? 'center bottom' : objectFit.position),
        'background-repeat': 'no-repeat',
      });
      // 空行盒块：无 runs（不画字），块盒即图片显示区，背景按 object-fit
      // 映射的铺法绘制（默认 contain：等比完整显示，不变形）。
      final layout = TextLayoutResult(
        text: '',
        lines: [
          LineBox(
            start: 0,
            end: 0,
            top: 0,
            height: size.$2,
            baseline: size.$2,
            width: blockWidth,
          ),
        ],
        width: blockWidth,
        height: size.$2,
        maxWidth: blockWidth,
        runs: const <StyledRun>[],
      );
      final usedImageModel = BoxModel.fromStyle(
        blockStyle,
        containingWidth: contentWidth,
      );
      final directFootnote = footnoteForReference(
        node.tag,
        node.attributes,
        '',
        start: 0,
        end: 1,
      );
      final imageFootnote = footnotes.isNotEmpty
          ? footnotes
          : <PageFootnote>[?directFootnote];
      blocks.add(
        PageBlock(
          layout: layout,
          style: blockStyle,
          pageBreakBefore: blockStyle.pageBreakBefore,
          pageBreakAfter: blockStyle.pageBreakAfter,
          breakInsideAvoid: blockStyle.breakInsideAvoid,
          breakAfterAvoid: blockStyle.breakAfterAvoid,
          spaceBefore: blockStyle.margin.top,
          spaceAfter: blockStyle.margin.bottom,
          topInset: usedImageModel.borders.top + usedImageModel.padding.top,
          bottomInset:
              usedImageModel.borders.bottom + usedImageModel.padding.bottom,
          leftInset: usedImageModel.borders.left + usedImageModel.padding.left,
          floatSide: floatSide,
          bleedLeft: imageStyle.bleed.left,
          bleedRight: imageStyle.bleed.right,
          bleedTop: imageStyle.bleed.top,
          bleedBottom: imageStyle.bleed.bottom,
          effectiveOpacity: imageOpacity,
          groupId: containerFloat != null
              ? containerFloatGroup
              : (chainFloat != null && containerFloatGroup > 0
                    ? containerFloatGroup
                    : 0),
          declaredContentHeight: usedImageModel.resolveContentHeight(
            layout.height,
            containingHeight: contentHeight,
          ),
          footnotes: imageFootnote,
        ),
      );
    }

    /// 表格收集（flat 管线接入）：聚合树 tr/td → 格自然宽/测高闭包 →
    /// 两遍列宽 + 网格 + 行边界切分；每页片产出一个带渲染载荷的块。
    /// 嵌套表/行分组（thead/tbody）按树序展开；caption 暂并入文字流。
    void collectTable(BlockNode tableNode, List<SelectorElement> ancestors) {
      // 表格自身与单元格样式必须走完整祖先链（P9-16）：书籍大量使用
      // `table.t-head-tb td { padding: 0; border: none }` 这类后代选择器，
      // 只拿 `td` 自身匹配会全部落空，单元格永远用 UA 的 3px 内边距。
      final tableView = _NodeView(
        'table',
        tableNode.attributes,
        const <SelectorElement>[],
      );
      final tableChain = <SelectorElement>[...ancestors, tableView];
      final tableStyle = styleForChain(tableChain);
      final caption = tableNode.children
          .whereType<BlockNode>()
          .where((child) => child.tag == 'caption')
          .firstOrNull;
      final tableAvailableWidth = math.max(
        1.0,
        contentWidth - tableStyle.margin.horizontal,
      );
      final tableInBorderedContainer = containerBorderedForLastChain;
      // 表格块同样要带祖先累计 opacity（单元格自己读 cellStyle）。
      final tableOpacity = effectiveOpacityForLastChain;
      // 表格边框模型（a~e）：`border-collapse: collapse` 时相邻单元格共用
      // 一条边线（每格只分摊一半）、且没有 border-spacing；separate 模式
      // 按 `border-spacing` 在列间/行间与四周留白。
      final collapse = tableStyle.borderCollapse == CssBorderCollapse.collapse;
      final spacingX = collapse ? 0.0 : tableStyle.borderSpacing.left;
      final spacingY = collapse ? 0.0 : tableStyle.borderSpacing.top;

      // 单元格内缩统一走引擎口径（T1 的 [tableCellInsetFor]）：separate
      // 模式 = 内边距 + 边框；collapse 模式下相邻格共用一条边线，边框由
      // 表格统一绘制，单元格自身不再计边框——否则行高比浏览器多 1px
      //（12-table 的 32 vs 30）。
      double horizontalInset(ComputedStyle style) =>
          tableCellInsetFor(style, collapse: collapse).horizontal;

      /// 单元格垂直占位（口径同 [horizontalInset]）。
      double verticalInset(ComputedStyle style) =>
          tableCellInsetFor(style, collapse: collapse).vertical;

      final rows = <List<BlockNode>>[];
      final rowNodes = <BlockNode>[];
      final rowInHeader = <bool>[];
      void walkRows(EpubNode node, {bool inHeader = false}) {
        if (node is! BlockNode) {
          return;
        }
        if (node.tag == 'tr') {
          final cells = node.children
              .whereType<BlockNode>()
              .where((c) => c.tag == 'td' || c.tag == 'th')
              .toList();
          if (cells.isNotEmpty) {
            rows.add(cells);
            rowNodes.add(node);
            rowInHeader.add(inHeader);
          }
          return;
        }
        if (node.tag == 'td' || node.tag == 'th') {
          return;
        }
        final childInHeader = inHeader || node.tag == 'thead';
        for (final child in node.children) {
          walkRows(child, inHeader: childInHeader);
        }
      }

      walkRows(tableNode);
      if (rows.isEmpty) {
        // 无行的表格（构建异常）：退化为文字流（格样式近似）。
        void emitText(EpubNode node) {
          if (node is TextBlockNode) {
            if (node.text.trim().isNotEmpty) {
              final cellStyle = styleFor('td');
              final result = _layoutCache.layout(
                text: node.text,
                style: cellStyle,
                maxWidth: tableAvailableWidth,
                hasGlyph: _hasBookFontGlyph,
              );
              if (result.lineCount > 0) {
                blocks.add(
                  PageBlock.styled(
                    layout: result,
                    style: cellStyle,
                    containingWidth: tableAvailableWidth,
                  ),
                );
              }
            }
          } else if (node is BlockNode) {
            for (final child in node.children) {
              emitText(child);
            }
          } else if (node is InlineNode) {
            for (final child in node.children) {
              emitText(child);
            }
          }
        }

        for (final child in tableNode.children) {
          emitText(child);
        }
        return;
      }

      // 格文本与样式：子树文本按序拼接（格内嵌套块以空行分隔）。
      /// 单元格文本 + 行内样式标记（P9-26）：单元格里的 span（RANK 标签）
      /// 需要按行内 run 绘制颜色/字号/边框，只取纯文本会丢掉整层样式。
      ({String text, List<InlineMark> marks}) cellContentOf(
        BlockNode cell,
        List<SelectorElement> chain,
      ) {
        final buffer = StringBuffer();
        final marks = <InlineMark>[];
        void walk(EpubNode node, List<MarkSubject> ancestors) {
          if (node is TextContentNode) {
            // 聚合后的文本节点：文本已合并，行内标记挂在 inlineMarks 上
            // （相对该节点文本的偏移），这里按 trim 后的坐标整体平移。
            final raw = node.text;
            final hasEmptyBox = node.inlineMarks.any(
              (mark) => mark.start == mark.end,
            );
            // 空盒前后仍有可见空白，不能按纯文本单元格去掉首尾空格。
            final trimmed = hasEmptyBox ? raw : raw.trim();
            if (trimmed.isEmpty && node.inlineMarks.isEmpty) {
              return;
            }
            final leading = hasEmptyBox
                ? 0
                : raw.length - raw.trimLeft().length;
            if (buffer.isNotEmpty) {
              buffer.write('\n');
            }
            final offset = buffer.length;
            buffer.write(trimmed);
            for (final mark in node.inlineMarks) {
              final start = math.max(0, mark.start - leading);
              final end = math.min(trimmed.length, mark.end - leading);
              if (end < start) {
                continue;
              }
              marks.add(
                InlineMark(
                  start: offset + start,
                  end: offset + end,
                  tag: mark.tag,
                  classes: mark.classes,
                  chain: mark.chain,
                ),
              );
            }
            return;
          }
          if (node is TextBlockNode) {
            final trimmed = node.text.trim();
            if (trimmed.isEmpty) {
              return;
            }
            if (buffer.isNotEmpty) {
              buffer.write('\n');
            }
            buffer.write(trimmed);
          } else if (node is BlockNode) {
            for (final child in node.children) {
              walk(child, ancestors);
            }
          } else if (node is InlineNode) {
            final classes = (node.attributes['class'] ?? '')
                .split(RegExp(r'\s+'))
                .where((c) => c.isNotEmpty)
                .toList(growable: false);
            final subject = MarkSubject(
              tag: node.tag,
              classes: classes.toSet(),
              attributes: node.attributes,
            );
            final next = <MarkSubject>[...ancestors, subject];
            final start = buffer.length;
            for (final child in node.children) {
              walk(child, next);
            }
            final end = buffer.length;
            if (end > start) {
              marks.add(
                InlineMark(
                  start: start,
                  end: end,
                  tag: node.tag,
                  classes: classes,
                  chain: List<MarkSubject>.unmodifiable(next),
                ),
              );
            }
          }
        }

        final cellAncestors = <MarkSubject>[
          for (final element in chain)
            MarkSubject(
              tag: element.tag,
              attributes: element.attributes,
              classes: (element.attributes['class'] ?? '')
                  .split(RegExp(r'\s+'))
                  .where((c) => c.isNotEmpty)
                  .toSet(),
            ),
        ];
        walk(cell, cellAncestors);
        return (text: buffer.toString(), marks: marks);
      }

      // 列声明宽（P9-17）：`<col>` 的 CSS/属性宽优先，其次首行单元格；
      // 表宽同样先看 CSS `width`，再看 HTML 属性。
      // `<col>/<colgroup>` 在块树里是行内节点（UA display: table-column），
      // 这里同时接受块节点与行内节点。
      final columnElements = <({String tag, Map<String, String> attributes})>[];
      void walkColumns(EpubNode node) {
        if (node is BlockNode) {
          if (node.tag == 'col') {
            columnElements.add((tag: node.tag, attributes: node.attributes));
            return;
          }
          for (final child in node.children) {
            walkColumns(child);
          }
        } else if (node is InlineNode) {
          if (node.tag == 'col') {
            columnElements.add((tag: node.tag, attributes: node.attributes));
            return;
          }
          for (final child in node.children) {
            walkColumns(child);
          }
        }
      }

      walkColumns(tableNode);

      double? declaredLength(
        ComputedStyle style,
        Map<String, String> attributes,
      ) {
        final css = style.width;
        if (css != null && !css.isAuto) {
          return css.isPercent
              ? tableAvailableWidth * css.value / 100
              : css.value;
        }
        final raw = attributes['width']?.trim();
        if (raw == null || raw.isEmpty) {
          return null;
        }
        if (raw.endsWith('%')) {
          final percent = double.tryParse(raw.substring(0, raw.length - 1));
          return percent == null ? null : tableAvailableWidth * percent / 100;
        }
        return double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
      }

      var columnCount = 0;
      for (final row in rows) {
        var count = 0;
        for (final cell in row) {
          count += int.tryParse(cell.attributes['colspan']?.trim() ?? '') ?? 1;
        }
        columnCount = math.max(columnCount, count);
      }

      final columnSpecified = <double?>[
        for (var i = 0; i < columnCount; i += 1) null,
      ];
      // 列宽声明是否为百分比（e）：百分比要以「表宽 - border-spacing」
      // 为基准解算，fixed 分支需要区分。
      final columnPercent = <bool>[
        for (var i = 0; i < columnCount; i += 1) false,
      ];
      bool declaredIsPercent(
        ComputedStyle style,
        Map<String, String> attributes,
      ) {
        final css = style.width;
        if (css != null && !css.isAuto) {
          return css.isPercent;
        }
        final raw = attributes['width']?.trim() ?? '';
        return raw.endsWith('%');
      }

      for (var i = 0; i < columnElements.length && i < columnCount; i += 1) {
        final column = columnElements[i];
        final columnStyle = styleForChain(<SelectorElement>[
          ...tableChain,
          _NodeView(column.tag, column.attributes, const <SelectorElement>[]),
        ]);
        columnSpecified[i] = declaredLength(columnStyle, column.attributes);
        columnPercent[i] = declaredIsPercent(columnStyle, column.attributes);
      }

      double? tableWidthPx;
      double? tableWidthPercent;
      final tableWidthRaw = tableNode.attributes['width'];
      if (tableWidthRaw != null && tableWidthRaw.trim().isNotEmpty) {
        final trimmed = tableWidthRaw.trim();
        if (trimmed.endsWith('%')) {
          tableWidthPercent =
              (double.tryParse(trimmed.substring(0, trimmed.length - 1)) ??
                  100) /
              100;
        } else {
          tableWidthPx = double.tryParse(trimmed);
        }
      }
      final cssTableWidth = tableStyle.width;
      if (tableWidthPx == null &&
          tableWidthPercent == null &&
          cssTableWidth != null &&
          !cssTableWidth.isAuto) {
        if (cssTableWidth.isPercent) {
          tableWidthPercent = cssTableWidth.value / 100;
        } else {
          tableWidthPx = cssTableWidth.value;
        }
      }

      // 每格：样式、全宽自然测量、按宽测高闭包。
      final cellStyles = <List<ComputedStyle>>[];
      final specs = <List<TableCellSpec>>[];
      final cellLayouts = <List<TextLayoutResult Function(double)>>[];
      final cellHeights = <List<double Function(double)>>[];
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
        final row = rows[rowIndex];
        final rowView = _NodeView(
          rowNodes[rowIndex].tag,
          rowNodes[rowIndex].attributes,
          const <SelectorElement>[],
        );
        final styles = <ComputedStyle>[];
        final rowSpecs = <TableCellSpec>[];
        final rowLayouts = <TextLayoutResult Function(double)>[];
        final rowHeights = <double Function(double)>[];
        for (final cell in row) {
          final cellChain = <SelectorElement>[
            ...tableChain,
            rowView,
            _NodeView(cell.tag, cell.attributes, const <SelectorElement>[]),
          ];
          final cellStyle = chainStyle(cellChain);
          final content = cellContentOf(cell, cellChain);
          final text = content.text;
          final hasContent = text.isNotEmpty || content.marks.isNotEmpty;
          TextLayoutResult measureCell(double width) => hasContent
              ? layoutCellContent(
                  text,
                  content.marks,
                  cellChain,
                  cellStyle,
                  math.max(8.0, width - horizontalInset(cellStyle)),
                )
              : TextLayoutResult(
                  text: '',
                  lines: const [],
                  width: 0,
                  height: 0,
                  maxWidth: width,
                );
          double measureHeight(double width) {
            final inset = verticalInset(cellStyle);
            final natural = !hasContent
                ? cellStyle.lineHeight * 0.6 + inset
                : measureCell(width).height + inset;
            final declared = cellStyle.height?.resolve(baseContentHeight);
            if (declared == null) {
              return natural;
            }
            final boxHeight = cellStyle.boxSizing == CssBoxSizing.borderBox
                ? declared
                : declared + inset;
            return math.max(natural, boxHeight);
          }

          rowLayouts.add(measureCell);
          rowHeights.add(measureHeight);
          final colspan =
              int.tryParse(cell.attributes['colspan']?.trim() ?? '') ?? 1;
          // rowspan（a）：跨行格的高度回填与合并矩形都靠它，之前完全
          // 没解析，跨行格按单行高排版。
          final rowspan =
              int.tryParse(cell.attributes['rowspan']?.trim() ?? '') ?? 1;
          double naturalWidth(double width, ComputedStyle cs) {
            if (!hasContent) {
              return 0;
            }
            final measured = measureCell(width);
            var widest = 0.0;
            for (final line in measured.lines) {
              widest = math.max(widest, line.width);
            }
            return widest + horizontalInset(cs);
          }

          double minContentWidth(ComputedStyle cs) {
            if (!hasContent) {
              return 0;
            }
            final width = _minContentTextWidth(
              text: text,
              breakEverywhere:
                  cs.wordBreak == CssWordBreak.breakAll ||
                  cs.overflowWrap == CssOverflowWrap.anywhere,
              style: cs,
            );
            var minWidth = width;
            if (content.marks.isNotEmpty || text.contains('\uFFFC')) {
              // 行内图片/盒子可能宽于文字；窄宽测量兜住这类内容。
              minWidth = math.max(
                minWidth,
                measureCell(8).lines.fold<double>(
                  0,
                  (widest, line) => math.max(widest, line.width),
                ),
              );
            }
            return minWidth + horizontalInset(cs);
          }

          styles.add(cellStyle);
          rowSpecs.add(
            TableCellSpec(
              naturalWidth: naturalWidth(tableAvailableWidth, cellStyle),
              minWidth: minContentWidth(cellStyle),
              colspan: colspan,
              rowspan: rowspan,
              measureHeight: measureHeight,
            ),
          );
        }
        cellStyles.add(styles);
        cellLayouts.add(rowLayouts);
        cellHeights.add(rowHeights);
        specs.add(rowSpecs);
      }

      // 首行单元格的 CSS/属性宽补齐尚未声明的列（P9-17）。
      var firstRowColumn = 0;
      for (var i = 0; i < rows.first.length; i += 1) {
        final cell = rows.first[i];
        final span =
            int.tryParse(cell.attributes['colspan']?.trim() ?? '') ?? 1;
        if (firstRowColumn < columnCount &&
            columnSpecified[firstRowColumn] == null) {
          columnSpecified[firstRowColumn] = declaredLength(
            cellStyles.first[i],
            cell.attributes,
          );
          columnPercent[firstRowColumn] = declaredIsPercent(
            cellStyles.first[i],
            cell.attributes,
          );
        }
        firstRowColumn += span;
      }

      final fixedLayout = tableStyle.tableLayout == CssTableLayout.fixed;
      final List<double> columnWidths;
      final List<double> rowHeights;
      final double tableWidthPxFinal;
      if (fixedLayout) {
        // `table-layout: fixed`（e）：声明列保持声明宽（百分比以
        //「表宽 - border-spacing」为基准，与浏览器一致），剩余空间平分给
        // 未声明列；列宽是「边框盒宽」= 内容宽 + 该列单元格内缩。
        var target = tableWidthPercent != null
            ? tableAvailableWidth * tableWidthPercent.clamp(0.0, 1.0)
            : (tableWidthPx ?? tableAvailableWidth);
        target = target.clamp(0.0, tableAvailableWidth);
        final columnSpace = math.max(
          0.0,
          target - spacingX * (columnCount + 1),
        );
        // 第一行单元格样式 → 每列的内缩（跨列格按首个覆盖列取）。
        final columnInset = List<double>.filled(columnCount, 0);
        var insetColumn = 0;
        for (var i = 0; i < rows.first.length; i += 1) {
          final span =
              int.tryParse(rows.first[i].attributes['colspan']?.trim() ?? '') ??
              1;
          final inset = horizontalInset(cellStyles.first[i]);
          for (
            var c = insetColumn;
            c < insetColumn + span && c < columnCount;
            c += 1
          ) {
            columnInset[c] = inset;
          }
          insetColumn += span;
        }
        final widths = List<double>.filled(columnCount, 0);
        var specifiedTotal = 0.0;
        var autoColumns = 0;
        for (var c = 0; c < columnCount; c += 1) {
          final specified = columnSpecified[c];
          if (specified == null) {
            autoColumns += 1;
            continue;
          }
          final content =
              (c < columnPercent.length &&
                  columnPercent[c] &&
                  tableAvailableWidth > 0)
              ? specified * columnSpace / tableAvailableWidth
              : specified;
          widths[c] = content + columnInset[c];
          specifiedTotal += widths[c];
        }
        if (autoColumns > 0) {
          final share =
              math.max(0.0, columnSpace - specifiedTotal) / autoColumns;
          for (var c = 0; c < columnCount; c += 1) {
            if (columnSpecified[c] == null) {
              widths[c] = share;
            }
          }
        } else if (specifiedTotal > columnSpace && specifiedTotal > 0) {
          final scale = columnSpace / specifiedTotal;
          for (var c = 0; c < columnCount; c += 1) {
            widths[c] *= scale;
          }
        }
        columnWidths = widths;
        tableWidthPxFinal =
            widths.fold(0.0, (sum, width) => sum + width) +
            spacingX * (columnCount + 1);
        // 行高：先按单行格取大，再把跨行格溢出部分均摊（a）。
        final heights = List<double>.filled(rows.length, 0);
        final rowspans = <List<int>>[];
        for (var r = 0; r < rows.length; r += 1) {
          final spans = <int>[];
          var column = 0;
          for (var i = 0; i < rows[r].length; i += 1) {
            final colSpan =
                int.tryParse(rows[r][i].attributes['colspan']?.trim() ?? '') ??
                1;
            final rowSpan =
                int.tryParse(rows[r][i].attributes['rowspan']?.trim() ?? '') ??
                1;
            spans.add(rowSpan);
            var cellWidth = 0.0;
            for (
              var c = column;
              c < column + colSpan && c < columnCount;
              c += 1
            ) {
              cellWidth += widths[c];
            }
            column += colSpan;
            if (rowSpan > 1) {
              continue;
            }
            final height = cellHeights[r][i](cellWidth);
            heights[r] = math.max(heights[r], height);
          }
          rowspans.add(spans);
        }
        for (var r = 0; r < rows.length; r += 1) {
          var column = 0;
          for (var i = 0; i < rows[r].length; i += 1) {
            final span =
                int.tryParse(rows[r][i].attributes['colspan']?.trim() ?? '') ??
                1;
            final rowSpan = rowspans[r][i];
            var cellWidth = 0.0;
            for (var c = column; c < column + span && c < columnCount; c += 1) {
              cellWidth += widths[c];
            }
            column += span;
            if (rowSpan <= 1) {
              continue;
            }
            final height = cellHeights[r][i](cellWidth);
            final spanRows = math.min(rowSpan, rows.length - r);
            var current = 0.0;
            for (var k = 0; k < spanRows; k += 1) {
              current += heights[r + k];
            }
            if (height <= current) {
              continue;
            }
            final extra = (height - current) / spanRows;
            for (var k = 0; k < spanRows; k += 1) {
              heights[r + k] += extra;
            }
          }
        }
        rowHeights = heights;
      } else {
        final measured = TableGridMeasurer.measureGrid(
          rows: specs,
          columnSpecified: columnSpecified,
          tableWidthPx: tableWidthPx,
          tableWidthPercent: tableWidthPercent,
          containerWidth: tableAvailableWidth,
          borderSpacingX: spacingX,
          borderSpacingY: spacingY,
        );
        columnWidths = measured.columnWidths;
        rowHeights = measured.rowHeights;
        tableWidthPxFinal = measured.tableWidth;
      }
      final grid = TableGridLayout(
        rows: specs,
        columnWidths: columnWidths,
        rowHeights: rowHeights,
        borderSpacingX: spacingX,
        borderSpacingY: spacingY,
      );
      var headerRowCount = 0;
      while (headerRowCount < rowInHeader.length &&
          rowInHeader[headerRowCount]) {
        headerRowCount += 1;
      }
      final gridRowYs = grid.rowYs;
      final gridColumnXs = grid.columnXs;
      final headerHeight = headerRowCount > 0 ? gridRowYs[headerRowCount] : 0.0;
      PageBlock? captionBlock;
      var captionOnTop = false;
      var captionOnBottom = false;
      if (caption != null) {
        final captionChain = <SelectorElement>[
          ...tableChain,
          _NodeView(caption.tag, caption.attributes, const <SelectorElement>[]),
        ];
        final captionStyle = styleForChain(captionChain);
        final captionContent = cellContentOf(caption, captionChain);
        if (captionContent.text.isNotEmpty || captionContent.marks.isNotEmpty) {
          final layout = layoutCellContent(
            captionContent.text,
            captionContent.marks,
            captionChain,
            captionStyle,
            math.max(8.0, tableWidthPxFinal - horizontalInset(captionStyle)),
          );
          captionBlock = PageBlock.styled(
            layout: layout,
            style: captionStyle,
            startCfi: caption.cfi.serialize(),
            containingWidth: tableWidthPxFinal,
            spaceBefore:
                captionStyle.margin.top +
                (tableStyle.captionSide == CssCaptionSide.top
                    ? tableStyle.margin.top
                    : 0),
            spaceAfter:
                captionStyle.margin.bottom +
                (tableStyle.captionSide == CssCaptionSide.bottom
                    ? tableStyle.margin.bottom
                    : 0),
          );
          captionOnTop = tableStyle.captionSide == CssCaptionSide.top;
          captionOnBottom = tableStyle.captionSide == CssCaptionSide.bottom;
        }
      }
      // 格终布局（按最终列宽）与渲染格。
      final allCells = <TableCellRender>[];
      for (var r = 0; r < rows.length; r++) {
        for (var c = 0; c < rows[r].length; c++) {
          final rect = grid.cellRectAt(r, c);
          if (rect == null) {
            continue;
          }
          final cellStyle = cellStyles[r][c];
          final layout = cellLayouts[r][c](rect.rect.width);
          allCells.add(
            TableCellRender(
              row: r,
              rect: rect.rect,
              layout: layout,
              style: cellStyle,
              startCfi: rows[r][c].cfi.serialize(),
            ),
          );
        }
      }
      // 行边界切分（P3-20，c）：行高含 border-spacing 的纵向占位——每行
      // 带一份间距，切片高才会与 grid.rowYs 的差值一致（整表高 =
      // grid.size.height，含首尾各一份间距）。
      final paddedRowHeights = <double>[
        for (final height in rowHeights) height + spacingY,
      ];
      // 不在这里按假定页高预先切片：实际页首可能已有标题/图片，预留的
      // 页高会在真正的分页器里产生多段，导致同一页重复出现表头。保留整表，
      // 交给 Paginator 按当前页真实剩余高度切行并逐页重复表头。
      final slices = <TablePageSlice>[
        TablePageSlice(
          firstRow: 0,
          lastRow: rowHeights.length,
          drawnHeight: paddedRowHeights.fold(
            0.0,
            (sum, height) => sum + height,
          ),
          clippedRowHeight: 0,
        ),
      ];
      if (captionBlock != null && captionOnTop) {
        blocks.add(captionBlock);
      }
      for (var sliceIndex = 0; sliceIndex < slices.length; sliceIndex += 1) {
        final slice = slices[sliceIndex];
        final repeatsHeader = sliceIndex > 0 && headerRowCount > 0;
        final headerOffset = repeatsHeader ? headerHeight : 0.0;
        final sliceTop = gridRowYs[slice.firstRow];
        var dataSliceHeight = slice.clippedRowHeight > 0
            ? slice.clippedRowHeight
            : slice.drawnHeight;
        // 末段落补上表格底部的最后一份纵向间距。
        if (slice.lastRow >= rowHeights.length) {
          dataSliceHeight += spacingY;
        }
        final sliceHeight = dataSliceHeight + headerOffset;
        // rowspan 格可能从上一片开始、延伸到本片：按矩形相交保留并裁到
        // 本片可见范围，否则分组列会在续片整列消失。
        final sliceBottom = sliceTop + dataSliceHeight;
        final cells = allCells
            .where(
              (cell) =>
                  !(repeatsHeader && cell.row < headerRowCount) &&
                  cell.rect.bottom > sliceTop + 0.01 &&
                  cell.rect.top < sliceBottom - 0.01,
            )
            .map(
              (cell) => TableCellRender(
                row: cell.row,
                rect: Rect.fromLTRB(
                  cell.rect.left,
                  math.max(0.0, cell.rect.top - sliceTop) + headerOffset,
                  cell.rect.right,
                  math.min(dataSliceHeight, cell.rect.bottom - sliceTop) +
                      headerOffset,
                ),
                layout: cell.layout,
                style: cell.style,
                startCfi: cell.startCfi,
              ),
            )
            .toList();
        if (repeatsHeader) {
          cells.insertAll(
            0,
            allCells
                .where((cell) => cell.row < headerRowCount)
                .map(
                  (cell) => TableCellRender(
                    row: cell.row,
                    rect: Rect.fromLTRB(
                      cell.rect.left,
                      math.max(0.0, cell.rect.top),
                      cell.rect.right,
                      math.min(headerHeight, cell.rect.bottom),
                    ),
                    layout: cell.layout,
                    style: cell.style,
                    startCfi: cell.startCfi,
                  ),
                ),
          );
        }
        blocks.add(
          PageBlock.styled(
            style: ComputedStyle(
              {...tableStyle.values, 'width': '${tableWidthPxFinal}px'},
              parent: tableStyle,
              containingWidth: contentWidth,
              explicitProperties: tableStyle.explicitProperties,
            ),
            containingWidth: contentWidth,
            // P9-25：带边框容器内的表格块同样参与背景/边框拼合。
            containerSides: tableInBorderedContainer,
            effectiveOpacity: tableOpacity,
            // caption 属于表格的外框：外边距落在标题外侧，避免标题前后
            // 各折叠一次表格外边距。跨页切片只保留首片/末片的外边距。
            spaceBefore: sliceIndex == 0 && !captionOnTop
                ? tableStyle.margin.top
                : 0,
            spaceAfter: sliceIndex == slices.length - 1 && !captionOnBottom
                ? tableStyle.margin.bottom
                : 0,
            layout: TextLayoutResult(
              text: '',
              lines: [
                LineBox(
                  start: 0,
                  end: 0,
                  top: 0,
                  height: sliceHeight,
                  baseline: sliceHeight,
                  width: tableWidthPxFinal,
                ),
              ],
              width: tableWidthPxFinal,
              height: sliceHeight,
              maxWidth: tableWidthPxFinal,
              runs: const <StyledRun>[],
            ),
            table: TableRenderSpec(
              cells: cells,
              columnXs: gridColumnXs,
              rowYs: [
                if (repeatsHeader)
                  for (var r = 0; r <= headerRowCount; r++) gridRowYs[r],
                for (
                  var r = repeatsHeader ? slice.firstRow + 1 : slice.firstRow;
                  r <= slice.lastRow;
                  r += 1
                )
                  gridRowYs[r] - sliceTop + headerOffset,
                if (slice.clippedRowHeight > 0)
                  slice.clippedRowHeight + headerOffset,
              ],
              tableWidth: tableWidthPxFinal,
              headerRowCount: headerRowCount,
              headerHeight: headerHeight,
            ),
          ),
        );
      }
      if (captionBlock != null && captionOnBottom) {
        blocks.add(captionBlock);
      }
    }

    // 容器级浮动分组号（W12）：超过 [floatGroupBase] 的 groupId 表示
    // 「同一个被拆开的浮动容器」，分页时整组当一个浮动盒处理。
    var containerFloatSeq = 0;
    // 相对定位 top 的抵扣量：下移 top 后，下一个块要以更小的段前距开始，
    // 才能保证后续内容流位置不变（相对定位不占流）。
    var pendingRelativeTop = 0.0;

    void collect(
      EpubNode node,
      String blockTag, {
      Map<String, String>? attributes,
      int groupId = 0,
      _ListContext? list,
      int quoteDepth = 0,
      List<SelectorElement> ancestors = const <SelectorElement>[],
      bool firstInContainer = false,
      bool lastInContainer = false,
      bool listFirst = false,
      bool listLast = false,
      FloatSide? containerFloat,
      double? containerFloatWidth,
      int containerFloatGroup = 0,
    }) {
      if (node is TextBlockNode) {
        final cfi = node is TextContentNode ? node.cfi.serialize() : null;
        final textRuleEligible = !ancestors.any(
          (element) =>
              element.tag == 'header' ||
              element.tag == 'footer' ||
              FootnoteParser.isDefinitionElement(
                element.tag,
                element.attributes,
              ),
        );
        // 链末位即当前块上下文（P8-02：链式级联含全部祖先）。
        final tag = ancestors.isEmpty ? 'body' : ancestors.last.tag;
        final isHeading = _headingTags.contains(tag);
        // 列表项（g）：水平缩进来自列表容器的级联盒，标记只挂在首块。
        final isListItem = tag == 'li' && list != null;
        final listIndent = isListItem ? listIndentOf(ancestors) : 0.0;
        // `position: relative` 的视觉偏移（不占流）：left 走左右 margin
        // 等量搬移，top 走「段前距 + 段后距」互补（内容与盒子一起下移，
        // 但块的流内占高不变）。
        final relativeProbe = styleForChain(
          ancestors,
          quoteDepth: quoteDepth,
          firstInContainer: firstInContainer,
          lastInContainer: lastInContainer,
          listIndent: listIndent,
        );
        final isRelative = relativeProbe.position == CssPosition.relative;
        final relativeLeft = isRelative
            ? (relativeProbe.left?.resolve(contentWidth) ?? 0.0)
            : 0.0;
        final relativeTop = isRelative
            ? (relativeProbe.top?.resolve(contentHeight) ?? 0.0)
            : 0.0;
        // 块样式先算：`white-space` 决定用折叠态文本还是保留原文的文本
        // （逐块生效，聚合器只能在章级选一种模式）。
        var blockStyle = styleForChain(
          ancestors,
          quoteDepth: quoteDepth,
          firstInContainer: firstInContainer,
          lastInContainer: lastInContainer,
          listIndent: listIndent,
          listPosition: isListItem
              ? (list.inside
                    ? CssListStylePosition.inside
                    : CssListStylePosition.outside)
              : null,
        );
        // 容器拼合（P9-25）：卡片/面板里的子块要把背景与左右边框延伸到
        // 段距，才能拼回整片面板（四边框闭合）。
        final inBorderedContainer = containerBorderedForLastChain;
        // 祖先累计 opacity：必须在后续任何 styleForChain 调用前读走。
        final blockOpacity = effectiveOpacityForLastChain;
        final textNode = _textNodeFor(
          spineIndex,
          node,
          blockStyle.whiteSpace,
          inlineDisplay,
        );
        final text = textNode.text;
        final hasEmptyInlineBox =
            textNode is TextContentNode &&
            textNode.inlineMarks.any((mark) => mark.start == mark.end);
        if (text.trim().isEmpty && !hasEmptyInlineBox) {
          // 空元素但盒子可见（声明尺寸 / 背景 / 边框）：仍要占位。
          // 真书里的分隔线、头像占位、章首留白 div 都是这种形态；早期直接
          // 丢弃会让后续内容整体上移（69-border-radius-percent 暴露）。
          final emptyBox = _emptyBoxBlock(
            blockStyle,
            contentWidth,
            containingHeight: baseContentHeight,
          );
          if (emptyBox != null) {
            blocks.add(emptyBox);
          }
          return;
        }
        // 计数器（W20）：元素自身的 counter-reset/increment 在生成
        // ::before 之前生效（CSS 2.1 §12.4），章节自动编号靠这条。
        applyCounters(ancestors);
        // 引号嵌套层级 = 祖先里 <q> 的个数（含自身；current 取上一层）。
        final qNesting = ancestors.where((a) => a.tag == 'q').length;
        final qLevel = tag == 'q' && qNesting > 0 ? qNesting - 1 : qNesting;
        // 伪元素生成内容（P8-09/W20）：::before/::after 的 content——
        // 字符串、attr()、counter()/counters()、open-quote/close-quote 可拼接。
        final beforeContent = pseudoContentOf(
          ancestors,
          '::before',
          quotes: blockStyle.quotes,
          quoteDepth: qLevel,
        );
        final afterContent = pseudoContentOf(
          ancestors,
          '::after',
          quotes: blockStyle.quotes,
          quoteDepth: qLevel,
        );
        // 阅读器排版覆盖（reader origin 高于 author）：字号/行高/对齐作用
        // 在级联结果之上，否则作者 p{font-size;line-height} 会让设置失效。
        // 标题不参与——标题字号/行高继续跟随书籍样式族。
        // 紧凑行高组件（聊天名字、气泡、注释标签等）也不能被正文覆盖
        // 成一个 17px/1.6 的正文块：这些元素由作者主动缩到父级以下，
        // 放大后会挤高消息高度并与头像错位。
        final parentStyle = ancestors.length > 1
            ? chainStyle(ancestors.sublist(0, ancestors.length - 1))
            : null;
        var hasCompactAncestor = false;
        for (var i = 0; i < ancestors.length - 1; i++) {
          final ancestorStyle = chainStyle(ancestors.sublist(0, i + 1));
          final factor = ancestorStyle.lineHeightFactor;
          if (factor != null && factor <= 1.05) {
            hasCompactAncestor = true;
            break;
          }
        }
        final compactAuthoredComponent =
            parentStyle != null &&
            blockStyle.fontSize < parentStyle.fontSize * 0.9 &&
            hasCompactAncestor;
        // 非语义标题（如带左边色条的 div.xbt2、居中扉页文字）也保留
        // 作者字号、行高与段距，阅读器排版只接管普通正文。
        final structuredTitle =
            !isHeading && _hasStructuredTitleText(text, blockStyle);
        final specialComponent =
            compactAuthoredComponent ||
            containerFloat != null ||
            ancestors.any((view) {
              final container = retainedContainers[view]?.style;
              return container != null &&
                  (container.display == CssDisplay.flex ||
                      (container.columnCount ?? 1) > 1 ||
                      container.columnWidth != null);
            }) ||
            ancestors.any(promotedInlineStyles.containsKey) ||
            _hasStructuredTitleText(text, blockStyle);
        blockStyle = proseSpacingDefaults(
          blockStyle,
          ancestors,
          text,
          specialComponent: specialComponent,
        );
        final applyReaderTypography =
            !isHeading &&
            !structuredTitle &&
            !specialComponent &&
            !ancestors.any(promotedInlineStyles.containsKey);
        if (applyReaderTypography) {
          blockStyle = overrides.applyTypography(blockStyle);
        }
        // 绝对/固定定位（P9-19/W18）：脱离正常流（不推进 y、不计页高）。
        // 偏移解算统一交给分页层（paginator `_resolveAbsolute`）：包含块 =
        // 页面内容盒、left/top 优先于 right/bottom、两侧都 auto 用静态位置、
        // width:auto 走 shrink-to-fit——章节源不再重复算偏移。
        final isOutOfFlow = blockStyle.isOutOfFlow;
        final isFixed = blockStyle.position == CssPosition.fixed;
        // 绝对/固定定位偏移解算走 T2 的 `resolveAbsoluteBox`：包含块 =
        // 页面内容盒（百分比也按它解算）、left/top 优先、都 auto 时返回
        // null（分页层据此回退静态位置 = 本来会被排到的流位置）。
        final outOfFlowBox = isOutOfFlow
            ? blockStyle.resolveAbsoluteBox(
                containingWidth: contentWidth,
                containingHeight: baseContentHeight,
              )
            : null;
        final absoluteTop = outOfFlowBox?.top;
        final absoluteLeft = outOfFlowBox?.left;
        // 段间距（阅读器设置优先）：只作用于正文段落；标题与列表项保留
        // 书籍自身的间距族。null 时沿用块 margin 并交给相邻折叠。
        final splitInlineFragment =
            ancestors.any(promotedInlineStyles.containsKey) ||
            (tag == 'reader-anonymous' &&
                ancestors.any(splitInlineContainers.contains));
        final paragraphSpacing =
            isHeading ||
                tag == 'li' ||
                splitInlineFragment ||
                structuredTitle ||
                compactAuthoredComponent
            ? null
            : overrides.paragraphSpacing;
        // 列表标记（P3-23）：每个 li 一项标记，只挂在该项首个文本块上
        //（li 内多段时不能重复编号）。
        String? marker;
        if (isListItem && list.markerPending) {
          list.markerPending = false;
          final markerText = list.nextMarker(blockStyle.listStyleType);
          marker = markerText.isEmpty
              ? (blockStyle.listStyleImage == null ? null : '')
              : markerText;
        }
        // `list-style-position: inside`（g）：标记并入首行，首行让出
        // 「标记宽 + 间隙」；outside 保持整行宽度（标记画在内容框外）。
        // 该属性在 CSS 里继承，li 自己声明时优先，否则取列表容器的值。
        final markerInside =
            blockStyle.values.containsKey('list-style-position')
            ? blockStyle.listStylePosition == CssListStylePosition.inside
            : list?.inside ?? false;
        // 缩进只作用于测量样式：浏览器的计算样式 text-indent 仍是 0
        //（缩进来::marker 盒），块样式保持原样，绘制按行的 offsetX 走。
        var measureStyle = blockStyle;
        if (marker != null && markerInside) {
          measureStyle = styleForChain(
            ancestors,
            quoteDepth: quoteDepth,
            firstInContainer: firstInContainer,
            lastInContainer: lastInContainer,
            listIndent: listIndent,
            firstLineIndent: insideMarkerIndent(marker, blockStyle),
          );
          if (!isHeading) {
            measureStyle = overrides.applyTypography(measureStyle);
          }
        }
        // 列表容器段距（g）：容器不产出块，上下外边距/内边距/边框由首项
        // 与末项承担（分页层再做相邻折叠）。
        final listSpacingBefore = isListItem && listFirst
            ? list.spaceBefore
            : 0.0;
        final listSpacingAfter = isListItem && listLast ? list.spaceAfter : 0.0;
        // 行内样式区间（P8-02）：聚合标记链 → 引擎级联 → StyledRun 混排；
        // ::first-letter（P8-09）：命中规则时首字符放大 run 追加。
        // 行内元素浮动（W17）：段落首/尾的行内浮动元素（span 标签、
        // img 头像）摘出来单独成块，段落剩余文本按行 offsetX 绕排。
        // 段落自身是浮动块时不做（避免嵌套浮动互相干扰）。
        final paragraphIsFloat =
            _floatSideOfStyle(blockStyle) != null || containerFloat != null;
        final inlineFloats = <PageBlock>[];
        final inlineBoxFootnotes = <PageFootnote>[];
        var inlineBoxes = <InlineBoxSpec>[];
        var paragraphText = text;
        var paragraphMarks = textNode is TextContentNode
            ? textNode.inlineMarks
            : const <InlineMark>[];
        var paragraphImages = textNode is TextContentNode
            ? textNode.inlineImages
            : const <InlineImageMark>[];
        var paragraphRubies = textNode is TextContentNode
            ? textNode.rubies
            : const <RubyMark>[];
        final pseudoPrefix = textNode is TextContentNode
            ? beforeContent?.text ?? ''
            : '';
        final pseudoSuffix = textNode is TextContentNode
            ? afterContent?.text ?? ''
            : '';
        // 图片与题注分属两个块时，图片不能当普通行内占位符：浮动/窄容器里
        // 占位符只有一行高，绘制会被切片裁掉，容器高度也不含图片。
        if (paragraphText.trim() == '\uFFFC' &&
            paragraphImages.length == 1 &&
            pseudoPrefix.isEmpty &&
            pseudoSuffix.isEmpty) {
          final image = paragraphImages.single.node;
          PageFootnote? imageFootnote;
          for (final mark in paragraphMarks) {
            imageFootnote = footnoteForReference(
              mark.tag,
              mark.chain.isEmpty
                  ? const <String, String>{}
                  : mark.chain.last.attributes,
              paragraphText.substring(mark.start, mark.end),
              start: 0,
              end: 1,
            );
            if (imageFootnote != null) {
              break;
            }
          }
          imageFootnote ??= footnoteForReference(
            image.tag,
            image.attributes,
            '',
            start: 0,
            end: 1,
          );
          collectImageBlock(
            BlockNode(
              tag: image.tag,
              display: DisplayMode.block,
              children: const <EpubNode>[],
              cfi: image.cfi,
              attributes: image.attributes,
              start: image.start,
              end: image.end,
            ),
            ancestors,
            containerFloat: containerFloat,
            containerFloatWidth: containerFloatWidth,
            containerFloatGroup: containerFloatGroup,
            footnotes: <PageFootnote>[?imageFootnote],
          );
          return;
        }
        // `<q>` 是聚合后的行内标记，不能只按块标签补引号；把每个 q 的
        // 开闭引号插回文本，同时重映射样式区间、注音与行内图片偏移。
        final quoteMarks = <InlineMark>[
          if (tag == 'q' && qLevel >= 0)
            InlineMark(
              start: 0,
              end: paragraphText.length,
              tag: 'q',
              classes: const <String>[],
              chain: ancestors
                  .map((element) {
                    final classes = (element.attributes['class'] ?? '')
                        .split(RegExp(r'\s+'))
                        .where((value) => value.isNotEmpty)
                        .toSet();
                    return MarkSubject(
                      tag: element.tag.toLowerCase(),
                      classes: classes,
                      attributes: element.attributes,
                    );
                  })
                  .toList(growable: false),
            ),
          for (final mark in paragraphMarks)
            if (mark.tag.toLowerCase() == 'q' && mark.end > mark.start) mark,
        ];
        final quoteInsertions = <_QuoteInsertion>[];
        for (var i = 0; i < quoteMarks.length; i++) {
          final mark = quoteMarks[i];
          if (blockStyle.quotes is CssQuotesNone) {
            continue;
          }
          final depth =
              quoteMarks
                  .where(
                    (other) =>
                        other.start <= mark.start && other.end >= mark.end,
                  )
                  .length -
              1;
          final pair = quotePairAt(blockStyle.quotes, depth);
          quoteInsertions
            ..add(
              _QuoteInsertion(
                offset: mark.start,
                text: pair.$1,
                depth: depth,
                opening: true,
              ),
            )
            ..add(
              _QuoteInsertion(
                offset: mark.end,
                text: pair.$2,
                depth: depth,
                opening: false,
              ),
            );
        }
        quoteInsertions.sort((a, b) {
          final byOffset = a.offset.compareTo(b.offset);
          if (byOffset != 0) {
            return byOffset;
          }
          // 相邻 q 先闭后开；嵌套 q 同时开启时外层优先，同时关闭时内层优先。
          if (a.opening != b.opening) {
            return a.opening ? 1 : -1;
          }
          return a.opening
              ? a.depth.compareTo(b.depth)
              : b.depth.compareTo(a.depth);
        });
        int mappedBoundary(int offset, {required bool includeOpening}) {
          var inserted = 0;
          for (final insertion in quoteInsertions) {
            if (insertion.offset < offset ||
                (includeOpening &&
                    insertion.opening &&
                    insertion.offset == offset)) {
              inserted += insertion.text.length;
            }
          }
          return pseudoPrefix.length + offset + inserted;
        }

        if (quoteInsertions.isNotEmpty) {
          final quoted = StringBuffer();
          var cursor = 0;
          for (final insertion in quoteInsertions) {
            quoted
              ..write(paragraphText.substring(cursor, insertion.offset))
              ..write(insertion.text);
            cursor = insertion.offset;
          }
          quoted.write(paragraphText.substring(cursor));
          paragraphText = quoted.toString();
          paragraphMarks = <InlineMark>[
            for (final mark in paragraphMarks)
              InlineMark(
                start: mappedBoundary(mark.start, includeOpening: true),
                end: mappedBoundary(mark.end, includeOpening: false),
                tag: mark.tag,
                classes: mark.classes,
                chain: mark.chain,
              ),
          ];
          paragraphImages = <InlineImageMark>[
            for (final image in paragraphImages)
              InlineImageMark(
                offset: mappedBoundary(image.offset, includeOpening: true),
                node: image.node,
              ),
          ];
          paragraphRubies = <RubyMark>[
            for (final ruby in paragraphRubies)
              RubyMark(
                start: mappedBoundary(ruby.start, includeOpening: true),
                end: mappedBoundary(ruby.end, includeOpening: false),
                text: ruby.text,
              ),
          ];
        } else if (pseudoPrefix.isNotEmpty || pseudoSuffix.isNotEmpty) {
          paragraphMarks = <InlineMark>[
            for (final mark in paragraphMarks)
              InlineMark(
                start: pseudoPrefix.length + mark.start,
                end: pseudoPrefix.length + mark.end,
                tag: mark.tag,
                classes: mark.classes,
                chain: mark.chain,
              ),
          ];
          paragraphImages = <InlineImageMark>[
            for (final image in paragraphImages)
              InlineImageMark(
                offset: pseudoPrefix.length + image.offset,
                node: image.node,
              ),
          ];
          paragraphRubies = <RubyMark>[
            for (final ruby in paragraphRubies)
              RubyMark(
                start: pseudoPrefix.length + ruby.start,
                end: pseudoPrefix.length + ruby.end,
                text: ruby.text,
              ),
          ];
        }
        paragraphText = '$pseudoPrefix$paragraphText$pseudoSuffix';
        final paragraphWithoutPseudoLength =
            paragraphText.length - pseudoPrefix.length - pseudoSuffix.length;
        var pseudoImageMarks = <_PseudoImageMark>[
          if (textNode is TextContentNode)
            for (final image
                in beforeContent?.images ?? const <_PseudoContentImage>[])
              _PseudoImageMark(
                offset: image.offset,
                url: image.url,
                pseudo: '::before',
              ),
          if (textNode is TextContentNode)
            for (final image
                in afterContent?.images ?? const <_PseudoContentImage>[])
              _PseudoImageMark(
                offset:
                    pseudoPrefix.length +
                    paragraphWithoutPseudoLength +
                    image.offset,
                url: image.url,
                pseudo: '::after',
              ),
        ];
        // `initial-letter` 的首字符必须脱离正文行盒，作为一个左侧浮动块
        // 占住 n 行；正文随后按剩余宽度重排，才能得到真正的多行绕排。
        String? dropCapText;
        ComputedStyle? dropCapStyle;
        final initialLetterLines = blockStyle.initialLetterLines;
        if (initialLetterLines != null &&
            initialLetterLines > 0 &&
            paragraphText.isNotEmpty &&
            _floatSideOfStyle(blockStyle) == null &&
            containerFloat == null) {
          final firstLetter = _firstLetterRun(
            firstLetterRules,
            ancestors,
            paragraphText,
            blockStyle,
            sizeInitialLetter: false,
          );
          if (firstLetter != null) {
            final start = firstLetter.start;
            var end = firstLetter.end;
            if (end < paragraphText.length &&
                _isHighSurrogate(paragraphText.codeUnitAt(start)) &&
                _isLowSurrogate(paragraphText.codeUnitAt(end))) {
              end += 1;
            }
            dropCapText = paragraphText.substring(start, end);
            dropCapStyle = firstLetter.style;
            int remap(int offset) {
              if (offset <= start) {
                return offset;
              }
              if (offset >= end) {
                return offset - (end - start);
              }
              return start;
            }

            paragraphText =
                paragraphText.substring(0, start) +
                paragraphText.substring(end);
            paragraphMarks = <InlineMark>[
              for (final mark in paragraphMarks)
                if (remap(mark.end) > remap(mark.start))
                  InlineMark(
                    start: remap(mark.start),
                    end: remap(mark.end),
                    tag: mark.tag,
                    classes: mark.classes,
                    chain: mark.chain,
                  ),
            ];
            paragraphImages = <InlineImageMark>[
              for (final image in paragraphImages)
                if (image.offset < start || image.offset >= end)
                  InlineImageMark(
                    offset: remap(image.offset),
                    node: image.node,
                  ),
            ];
            paragraphRubies = <RubyMark>[
              for (final ruby in paragraphRubies)
                if (remap(ruby.end) > remap(ruby.start))
                  RubyMark(
                    start: remap(ruby.start),
                    end: remap(ruby.end),
                    text: ruby.text,
                  ),
            ];
            pseudoImageMarks = <_PseudoImageMark>[
              for (final image in pseudoImageMarks)
                if (image.offset < start || image.offset >= end)
                  _PseudoImageMark(
                    offset: remap(image.offset),
                    url: image.url,
                    pseudo: image.pseudo,
                  ),
            ];
          }
        }
        final inlineContext = (
          ancestors: ancestors,
          style: blockStyle,
          width: _textWidthFor(blockStyle),
          readerFontFamily: applyReaderTypography
              ? _overrides.fontFamily
              : null,
        );
        if (!paragraphIsFloat && textNode is TextContentNode) {
          // 一段里可能有多个行内浮动（如职业标签 + 天赋标签），逐个摘出。
          final extractionLimit =
              paragraphMarks.length + paragraphImages.length;
          for (var guard = 0; guard < extractionLimit; guard += 1) {
            final extracted = extractInlineFloat(
              text: paragraphText,
              marks: paragraphMarks,
              images: paragraphImages,
              context: inlineContext,
            );
            if (extracted == null) {
              break;
            }
            final floatBlock = extracted.block;
            if (floatBlock != null) {
              inlineFloats.add(floatBlock);
            }
            final box = extracted.inlineBox;
            if (box != null) {
              inlineBoxes = appendInlineBox(inlineBoxes, extracted);
              final footnote = extracted.footnote;
              if (footnote != null) {
                inlineBoxFootnotes.add(footnote);
              }
            }
            paragraphText = extracted.text;
            paragraphMarks = extracted.marks;
            pseudoImageMarks = <_PseudoImageMark>[
              for (final image in pseudoImageMarks)
                if (!extracted.removed(image.offset))
                  _PseudoImageMark(
                    offset: extracted.remapOffset(image.offset),
                    url: image.url,
                    pseudo: image.pseudo,
                  ),
            ];
            paragraphImages = <InlineImageMark>[
              for (final image in paragraphImages)
                if (!extracted.removed(image.offset))
                  InlineImageMark(
                    offset: extracted.remapOffset(image.offset),
                    node: image.node,
                  ),
            ];
          }
        }
        var runs = resolveInlineRuns(paragraphMarks, inlineContext);
        if (pseudoPrefix.isNotEmpty) {
          runs = [
            StyledRun(
              start: 0,
              end: pseudoPrefix.length,
              style: pseudoStyleFor(ancestors, blockStyle, '::before'),
            ),
            ...runs,
          ];
        }
        if (pseudoSuffix.isNotEmpty) {
          runs = [
            ...runs,
            StyledRun(
              start: paragraphText.length - pseudoSuffix.length,
              end: paragraphText.length,
              style: pseudoStyleFor(ancestors, blockStyle, '::after'),
            ),
          ];
        }
        // 行内图片（P9-06）：占位符 → 书内图片路径 + 书籍 CSS 尺寸。
        final inlineImages = <InlineImageSpec>[];
        if (paragraphImages.isNotEmpty) {
          for (final mark in paragraphImages) {
            final attributesForImage = mark.node.attributes;
            final src =
                attributesForImage['src'] ?? attributesForImage['xlink:href'];
            if (src == null || src.isEmpty) {
              continue;
            }
            final url =
                this.document.resources.resolve(src, baseDir: chapterBase) ??
                src;
            final sourceMark = paragraphMarks
                .where(
                  (candidate) =>
                      candidate.start == mark.offset &&
                      candidate.tag == mark.node.tag,
                )
                .firstOrNull;
            final imageChain = sourceMark == null
                ? <SelectorElement>[
                    ...ancestors,
                    _NodeView(
                      mark.node.tag,
                      attributesForImage,
                      const <SelectorElement>[],
                    ),
                  ]
                : inlineMarkChain(sourceMark, ancestors);
            final imageStyle = chainStyle(imageChain);
            inlineImages.add(
              InlineImageSpec(
                offset: mark.offset,
                url: url,
                width: imageStyle.width?.resolve(contentWidth),
                height: imageStyle.height?.resolve(contentWidth),
                aspectRatio: imageStyle.aspectRatio,
              ),
            );
            if (imageStyle.writingMode == CssWritingMode.horizontalTb) {
              inlineBoxes.add(
                inlineImageBox(
                  inlineImages.last,
                  imageStyle,
                  imageChain,
                  inlineContext.width,
                ),
              );
            }
          }
        }
        for (final mark in pseudoImageMarks) {
          final imageStyle = pseudoStyleFor(ancestors, blockStyle, mark.pseudo);
          inlineImages.add(
            InlineImageSpec(
              offset: mark.offset,
              url: mark.url,
              width: imageStyle.width?.resolve(contentWidth),
              height: imageStyle.height?.resolve(contentWidth),
              aspectRatio: imageStyle.aspectRatio,
            ),
          );
        }
        final paragraphFootnotes = <PageFootnote>[...inlineBoxFootnotes];
        final seenFootnoteOffsets = <int>{};
        void addFootnote(
          String tag,
          Map<String, String> attributes,
          String visibleText,
          int start, {
          required int end,
        }) {
          if (seenFootnoteOffsets.contains(start)) {
            return;
          }
          final footnote = footnoteForReference(
            tag,
            attributes,
            visibleText,
            start: start,
            end: end,
          );
          if (footnote == null) {
            return;
          }
          seenFootnoteOffsets.add(start);
          paragraphFootnotes.add(footnote);
        }

        for (final mark in paragraphMarks) {
          final attributes = mark.chain.isEmpty
              ? const <String, String>{}
              : mark.chain.last.attributes;
          addFootnote(
            mark.tag,
            attributes,
            paragraphText.substring(mark.start, mark.end),
            mark.start,
            end: mark.end,
          );
        }
        for (final image in paragraphImages) {
          addFootnote(
            image.node.tag,
            image.node.attributes,
            '',
            image.offset,
            end: image.offset + 1,
          );
        }
        // 替换图的 vertical-align 已由原子盒参与排版，不能再作为文字 run 抬升。
        runs = [
          for (final run in runs)
            if (!inlineBoxes.any(
              (box) =>
                  box.replacesPlaceholder &&
                  run.start == box.offset &&
                  run.end == box.offset + 1,
            ))
              run,
        ];
        final firstLetter = dropCapText == null
            ? _firstLetterRun(
                firstLetterRules,
                ancestors,
                paragraphText,
                blockStyle,
              )
            : null;
        if (firstLetter != null) {
          runs = [...runs, firstLetter];
        }
        final contentCfi = dropCapText == null || cfi == null
            ? cfi
            : cfiWithCharOffset(cfi, dropCapText.length);
        runs = _textOverlayResolver.resolve(
          blockCfi: contentCfi,
          text: paragraphText,
          style: measureStyle,
          runs: runs,
        );
        // 浮动块（f/W12）：`float` 走级联后的计算样式；容器上的 float
        //（如双列目录 `.dk-toc-item`）经传导带给子块，子块按容器内容宽
        // 排版并整体进同一个浮动盒。
        final ownFloatSide = _floatSideOfStyle(blockStyle);
        final floatSide = ownFloatSide ?? containerFloat;
        final measureWidth =
            ownFloatSide == null &&
                containerFloat != null &&
                containerFloatWidth != null
            ? textWidthInFloat(ancestors, containerFloatWidth)
            : _textWidthFor(measureStyle);
        // 绝对/固定定位且声明了宽：分页层解算 left/right 时把 layout.width
        // 当盒宽用，所以要把「最长行宽」换成**边框盒宽**（声明内容宽 +
        // padding + 可见 border），贴右/贴底才和浏览器一致。
        double? outOfFlowBoxWidth;
        if (isOutOfFlow && blockStyle.width != null) {
          final flowModel = BoxModel.fromStyle(
            blockStyle,
            containingWidth: contentWidth,
          );
          outOfFlowBoxWidth =
              (flowModel.contentWidth ?? 0) +
              flowModel.padding.horizontal +
              flowModel.borders.left +
              flowModel.borders.right;
        }
        var layout = inlineBoxes.isEmpty
            ? _layoutCache.layout(
                text: paragraphText,
                style: measureStyle,
                maxWidth: measureWidth,
                runs: runs,
                rubies: [
                  for (final ruby in paragraphRubies)
                    RubyAnnotation(
                      start: ruby.start,
                      end: ruby.end,
                      text: ruby.text,
                    ),
                ],
                hasGlyph: _hasBookFontGlyph,
              )
            : TextLayoutEngine.layout(
                text: paragraphText,
                style: measureStyle,
                maxWidth: measureWidth,
                runs: runs,
                inlineBoxes: inlineBoxes,
                rubies: [
                  for (final ruby in paragraphRubies)
                    RubyAnnotation(
                      start: ruby.start,
                      end: ruby.end,
                      text: ruby.text,
                    ),
                ],
                hasGlyph: _hasBookFontGlyph,
              );
        if (outOfFlowBoxWidth != null) {
          layout = withLayoutWidth(
            layout,
            width: outOfFlowBoxWidth,
            maxWidth: outOfFlowBoxWidth,
          );
        }
        // 竖排（W19）：行排版层给出的 `layout.width` 是**列带总宽**
        //（列数 × 列宽），块的内容宽就取它——沿用整页宽
        //（`layout.maxWidth`）会让块盒比浏览器宽一截（35-writing-mode）。
        // 作者声明了 width 时不能覆盖，否则 `.box{width:54px}` 会被压成
        // 单列字宽；只有 auto 宽才收紧到实际列带。
        final hasDeclaredWidth =
            measureStyle.width != null && !measureStyle.width!.isAuto;
        if (measureStyle.writingMode != CssWritingMode.horizontalTb &&
            !hasDeclaredWidth &&
            layout.width.isFinite &&
            layout.width > 0 &&
            layout.width != layout.maxWidth) {
          layout = withLayoutWidth(layout, maxWidth: layout.width);
        }
        if (inlineFloats.isNotEmpty) {
          // 浮动块排在段落之前：分页时它们先占位，段落行按剩余宽度收窄。
          blocks.addAll(inlineFloats);
        }
        if (dropCapText != null && dropCapStyle != null) {
          blocks.add(
            _dropCapBlock(
              text: dropCapText,
              style: dropCapStyle,
              bodyLineHeight: layout.lines.first.height,
              lineCount: initialLetterLines!,
              gap: blockStyle.fontSize * 0.25,
              effectiveOpacity: blockOpacity,
              startCfi: cfi,
            ),
          );
        }
        // 首字拆出后，正文块内偏移 0 已对应原文偏移
        // dropCapText.length；锚点 CFI 也同步前移，标注区间才不会错一位。
        if (layout.lineCount > 0) {
          // 相对定位只抵扣下一个常规流块；绝对/固定定位和浮动不占流，
          // 不能在中途吞掉抵扣，否则其后的正文会整体多下移一次。
          final inFlow = !isOutOfFlow && floatSide == null;
          final incomingShift = inFlow ? pendingRelativeTop : 0.0;
          if (inFlow) {
            pendingRelativeTop = 0;
          }
          // 注意：段前距允许为负（作者负 margin 与上段段后距折叠后的结果），
          // 这里不能 clamp 到 0，否则 P8-05 的负 margin 失效。
          final spaceBefore =
              (paragraphSpacing ?? blockStyle.margin.top) +
              listSpacingBefore -
              incomingShift;
          final spaceAfter =
              (paragraphSpacing ?? blockStyle.margin.bottom) + listSpacingAfter;
          if (floatSide != null) {
            blocks.add(
              _floatedTextBlock(
                layout: layout,
                style: blockStyle,
                side: floatSide,
                spaceBefore: spaceBefore,
                spaceAfter: spaceAfter,
                inlineImages: inlineImages,
                footnotes: paragraphFootnotes,
                rubies: paragraphRubies.isNotEmpty
                    ? [
                        for (final ruby in paragraphRubies)
                          RubyAnnotation(
                            start: ruby.start,
                            end: ruby.end,
                            text: ruby.text,
                          ),
                      ]
                    : null,
                startCfi: contentCfi,
                textRuleEligible: textRuleEligible,
                // 容器浮动组用专属组号（分页时整组当一个浮动盒）。
                groupId: floatSide == containerFloat && containerFloat != null
                    ? containerFloatGroup
                    : groupId,
                containerSides: inBorderedContainer,
                effectiveOpacity: blockOpacity,
              ),
            );
            return;
          }
          var textBlock = PageBlock.styled(
            layout: layout,
            style: blockStyle,
            containingWidth: contentWidth,
            startCfi: contentCfi,
            textRuleEligible: textRuleEligible,
            groupId: groupId,
            listMarker: marker,
            // 块级上下边距进分页几何（含负值）：作者/UA margin 生效，
            // 阅读器段距设置优先；相邻段在分页层折叠取大
            //（PageBlock.collapseAdjacentMargins）。列表项另加容器段距。
            spaceBefore: spaceBefore,
            spaceAfter: spaceAfter,
            // P8-08：注音标注透传渲染层。
            rubies: paragraphRubies.isNotEmpty
                ? [
                    for (final ruby in paragraphRubies)
                      RubyAnnotation(
                        start: ruby.start,
                        end: ruby.end,
                        text: ruby.text,
                      ),
                  ]
                : null,
            // P9-06：行内图片（U+FFFC 占位）透传给绘制层。
            inlineImages: inlineImages,
            footnotes: paragraphFootnotes,
            // P9-19：绝对定位块（不占流高，绘制在页内绝对坐标）。
            absolute: isOutOfFlow,
            absoluteTop: absoluteTop,
            absoluteLeft: absoluteLeft,
            // P9-22：多看出血（背景/边框延伸到页面边缘）。
            bleedLeft: blockStyle.bleed.left,
            bleedRight: blockStyle.bleed.right,
            bleedTop: blockStyle.bleed.top,
            bleedBottom: blockStyle.bleed.bottom,
            // P9-25：带边框容器内部的块，背景/左右边框拼合。
            containerSides: inBorderedContainer,
            effectiveOpacity: blockOpacity,
          );
          if (relativeLeft != 0 || relativeTop != 0) {
            // `position: relative`：只挪视觉位置、不占流。
            // - left：只加 leftInset（盒子声明宽不变、文字与块顶一起右移）；
            // - top：段前距 +top 让内容下移，并把等量抵扣登记给下一个块，
            //   由它缩短段前距，保持后续内容流位置不变。
            textBlock = PageBlock(
              layout: textBlock.layout,
              style: textBlock.style,
              spaceBefore: textBlock.spaceBefore + relativeTop,
              // 段后距同时扣掉这 top：折叠后相邻间距要缩小同量，否则
              // 后续内容会被推下去（相对定位不占流）。
              spaceAfter: math.max(0.0, textBlock.spaceAfter - relativeTop),
              topInset: textBlock.topInset,
              bottomInset: textBlock.bottomInset,
              leftInset: textBlock.leftInset + relativeLeft,
              startCfi: textBlock.startCfi,
              endCfi: textBlock.endCfi,
              textRuleEligible: textBlock.textRuleEligible,
              groupId: textBlock.groupId,
              listMarker: textBlock.listMarker,
              rubies: textBlock.rubies,
              inlineImages: textBlock.inlineImages,
              footnotes: textBlock.footnotes,
              absolute: textBlock.absolute,
              absoluteTop: textBlock.absoluteTop,
              absoluteLeft: textBlock.absoluteLeft,
              bleedLeft: textBlock.bleedLeft,
              bleedRight: textBlock.bleedRight,
              bleedTop: textBlock.bleedTop,
              bleedBottom: textBlock.bleedBottom,
              containerSides: textBlock.containerSides,
              effectiveOpacity: textBlock.effectiveOpacity,
              declaredContentHeight: textBlock.declaredContentHeight,
              verticalContentWidth: textBlock.verticalContentWidth,
            );
            if (relativeTop != 0) {
              pendingRelativeTop += relativeTop;
            }
          }
          if (_isStructuredHeading(
            tag: tag,
            style: blockStyle,
            text: layout.text,
            lineCount: layout.lineCount,
          )) {
            textBlock = textBlock.withSpacing(breakAfterAvoid: true);
          }
          if (isFixed) {
            // 固定定位块每页重复，分页后再逐页追加（见 _withFixedOverlays）。
            fixedBlocks.add(textBlock);
          } else {
            blocks.add(textBlock);
          }
        }
      } else if (node is BlockNode) {
        final sourceAncestors = ancestors;
        if (node is PromotedBlockNode && node.inlineAncestors.isNotEmpty) {
          ancestors = [
            ...ancestors,
            for (final ancestor in node.inlineAncestors)
              _NodeView(ancestor.tag, ancestor.attributes, const []),
          ];
        }
        // display:none 容器子树剔除（P8-07，WHATWG 15.3.1 语义）：容器
        // 自身样式为 none 时整棵子树不产出（含 [hidden]/input[type=
        // hidden]/dialog:not([open]) 等经级联命中的形态）。
        if (chainStyle(<SelectorElement>[...ancestors, selectorViewOf(node)])
                .display ==
            CssDisplay.none) {
          return;
        }
        // 折叠出的纯图块（真实书适配）：构造背景图块（contain 居中），
        // 块高按属性尺寸/原始宽高比换算。
        if (node.tag == 'img' && node.children.isEmpty) {
          collectImageBlock(
            node,
            ancestors,
            containerFloat: containerFloat,
            containerFloatWidth: containerFloatWidth,
            containerFloatGroup: containerFloatGroup,
          );
          return;
        }
        // 表格块（flat 管线接入）：格布局测量 + 行边界切分 + 渲染载荷。
        if (node.tag == 'table') {
          final tableWatch = trace == null ? null : (Stopwatch()..start());
          collectTable(node, ancestors);
          if (trace != null) {
            trace.record(
              ReaderTraceName.chapterTables,
              tableWatch!.elapsedMicroseconds,
              bookId: traceBook,
            );
          }
          return;
        }
        // 分隔线复用正常层叠与盒模型；空行只承担分页，不引入文字行高。
        if (node.tag == 'hr' && node.children.isEmpty) {
          final hrStyle = styleForChain(
            [...ancestors, selectorViewOf(node)],
            quoteDepth: quoteDepth,
            firstInContainer: firstInContainer,
            lastInContainer: lastInContainer,
          );
          final ruleWidth = BoxModel.fromStyle(
            hrStyle,
            containingWidth: contentWidth,
          ).resolveContentWidth(contentWidth);
          blocks.add(
            PageBlock.styled(
              layout: TextLayoutResult(
                text: '',
                lines: [
                  LineBox(
                    start: 0,
                    end: 0,
                    top: 0,
                    height: 0,
                    baseline: 0,
                    width: ruleWidth,
                  ),
                ],
                width: ruleWidth,
                height: 0,
                maxWidth: ruleWidth,
                runs: const <StyledRun>[],
              ),
              style: hrStyle,
              containingWidth: contentWidth,
            ),
          );
          return;
        }
        // 空元素但盒子可见（声明尺寸/背景/边框）：占位块。
        // 真书里的分隔线、头像占位、章首留白 div 都是这种形态；早期整块
        // 丢弃会让后续内容整体上移一个盒高（69-border-radius-percent 暴露）。
        if (node.children.isEmpty) {
          final emptyBox = _emptyBoxBlock(
            chainStyle(<SelectorElement>[...ancestors, selectorViewOf(node)]),
            contentWidth,
            containingHeight: baseContentHeight,
          );
          if (emptyBox != null) {
            blocks.add(emptyBox);
            return;
          }
        }
        // 整组不可切（P7-26）：figure（图+题注）内的块标记同组。
        var childGroup = groupId;
        if (node.tag == 'figure') {
          figureSeq += 1;
          childGroup = figureSeq;
        }
        // 引用深度（M2）：blockquote 每层 +1，容器左右边距叠加到子块。
        final childQuoteDepth = node.tag == 'blockquote'
            ? quoteDepth + 1
            : quoteDepth;
        // 匹配阶段与布局阶段复用节点身份，避免兄弟伪类失配或同形段落串用缓存。
        final selfView = selectorViewOf(node);
        final childAncestors = <SelectorElement>[...ancestors, selfView];
        if (node is PromotedBlockNode) {
          var parent = chainStyle(sourceAncestors);
          final applyReaderTypography =
              !sourceAncestors.any(promotedInlineStyles.containsKey) &&
              !_headingTags.contains(sourceAncestors.lastOrNull?.tag);
          if (applyReaderTypography) {
            parent = overrides.applyTypography(parent);
          }
          // display 只改盒类型，字号仍从最终父正文继承，与普通行内标签相同。
          promotedInlineStyles[selfView] = inlineMarkStyle(
            InlineMark(
              start: 0,
              end: 0,
              tag: node.tag,
              classes: const [],
              chain: [
                for (final inline in node.inlineAncestors)
                  MarkSubject(
                    tag: inline.tag,
                    classes: const {},
                    attributes: inline.attributes,
                  ),
                MarkSubject(
                  tag: node.tag,
                  classes: const {},
                  attributes: node.attributes,
                ),
              ],
            ),
            (
              ancestors: sourceAncestors,
              style: parent,
              width: contentWidth,
              readerFontFamily: applyReaderTypography
                  ? _overrides.fontFamily
                  : null,
            ),
          );
        }
        // 容器级浮动传导（W12）：flat 管线把容器拆成子块后，容器上的
        // `float`/`width` 会整条丢掉（双列目录 `.dk-toc-item{float:left;
        // width:48%}` 因此排成单列）。这里把容器浮动按「传导白名单」的
        // 思路带给子块：子块整体当作一个浮动盒（同一 groupId 分组）。
        var childContainerFloat = containerFloat;
        var childContainerFloatWidth = containerFloatWidth;
        var childContainerFloatGroup = containerFloatGroup;
        final selfStyle = chainStyle(childAncestors);
        final isFlexRow =
            selfStyle.display == CssDisplay.flex &&
            selfStyle.flexDirection == CssFlexDirection.row;
        final isPageRootFlexColumn =
            selfStyle.display == CssDisplay.flex &&
            selfStyle.flexDirection == CssFlexDirection.column &&
            node.tag == 'body';
        final retainedStart = blocks.length;
        PageContainer? retained;
        if (containerFloat == null &&
            (isFlexRow || _retainsContainer(node, selfStyle))) {
          final parentBoxes = ancestors
              .map((a) => retainedContainers[a])
              .nonNulls;
          final parentBox = parentBoxes.isEmpty ? null : parentBoxes.last;
          final availableWidth = parentBox?.contentWidth ?? contentWidth;
          final model = BoxModel.fromStyle(
            selfStyle,
            containingWidth: availableWidth,
          );
          retained = PageContainer(
            style: selfStyle,
            left: (parentBox?.contentLeft ?? 0) + selfStyle.margin.left,
            width: model.borderBoxWidth(
              model.resolveContentWidth(availableWidth),
            ),
            cloneDecoration: _clonesContainerDecoration(selfStyle),
            isPageRoot: identical(node, document.root),
          );
          retainedContainers[selfView] = retained;
          if (!isFlexRow &&
              node.children.any((child) => child is PromotedBlockNode)) {
            splitInlineContainers.add(selfView);
          }
        }
        final selfFloat = _floatSideOfStyle(selfStyle);
        if (selfFloat != null) {
          containerFloatSeq += 1;
          childContainerFloat = selfFloat;
          // 容器宽 = 内容盒宽（多列容器一般写百分比/固定宽）。
          childContainerFloatWidth = _textWidthFor(selfStyle);
          childContainerFloatGroup = floatGroupBase + containerFloatSeq;
        } else if (containerFloat != null) {
          // 浮动容器内部再嵌块级元素：继续用同一组。
          childContainerFloat = containerFloat;
          childContainerFloatWidth = containerFloatWidth;
          childContainerFloatGroup = containerFloatGroup;
        }
        // 列表上下文（P3-23/g）：ul/ol 开新层，并把容器的上下盒空白
        //（外边距 + 边框 + 内边距）交给首项/末项承担；li 沿用所在列表。
        // 容器不产出块，这些空白不接就是列表整体上移（用例 11/30 的 6px）。
        _ListContext? childList = list;
        if (node.tag == 'ul' || node.tag == 'ol') {
          final containerStyle = chainStyle(childAncestors);
          childList = _ListContext(
            node.tag,
            (list?.depth ?? -1) + 1,
            spaceBefore:
                containerStyle.margin.top +
                containerStyle.borders.top.width +
                containerStyle.padding.top,
            spaceAfter:
                containerStyle.margin.bottom +
                containerStyle.borders.bottom.width +
                containerStyle.padding.bottom,
            inside:
                containerStyle.listStylePosition == CssListStylePosition.inside,
          );
        } else if (node.tag == 'li' && list != null) {
          childList = list;
          // 每个 li 各有一枚标记：进 li 时置位，由该项首个文本块消费。
          list.markerPending = true;
        }
        // 首末容器位（P8-05c）：按块级子序标记，供上下边框拼合。
        final blockChildren = <EpubNode>[
          for (final child in node.children)
            if (child is BlockNode) child,
        ];
        final flexItems = <List<PageBlock>>[];
        for (final child in node.children) {
          var childFirst = firstInContainer;
          var childLast = lastInContainer;
          if (child is BlockNode && blockChildren.isNotEmpty) {
            childFirst = identical(child, blockChildren.first);
            childLast = identical(child, blockChildren.last);
          }
          // 列表项的首/末位置：列表容器按块级子序判定，li 内部继续传导
          //（否则 li 里的文本块拿不到「首项」信息，标记与容器段距会丢）。
          final isListContainer = node.tag == 'ul' || node.tag == 'ol';
          final isListItem = node.tag == 'li';
          final itemStart = blocks.length;
          collect(
            child,
            node.tag,
            attributes: node.attributes,
            groupId: childGroup,
            list: childList,
            quoteDepth: childQuoteDepth,
            ancestors: retained != null && child is TextBlockNode
                ? [
                    ...childAncestors,
                    _NodeView('reader-anonymous', const {}, const []),
                  ]
                : childAncestors,
            firstInContainer: childFirst,
            lastInContainer: childLast,
            listFirst: isListContainer
                ? identical(child, blockChildren.first)
                : (isListItem && listFirst),
            listLast: isListContainer
                ? identical(child, blockChildren.last)
                : (isListItem && listLast),
            containerFloat: childContainerFloat,
            containerFloatWidth: childContainerFloatWidth,
            containerFloatGroup: childContainerFloatGroup,
          );
          if (isFlexRow && blocks.length > itemStart) {
            flexItems.add(blocks.sublist(itemStart));
          }
        }
        if (isFlexRow && retained != null) {
          final flexRow = _flexRowBlock(
            containerStyle: selfStyle,
            containerWidth: retained.contentWidth,
            items: flexItems,
            containingWidth: contentWidth,
            pageContentHeight: contentHeight,
            groupId: childGroup,
          );
          if (flexRow != null) {
            blocks.replaceRange(retainedStart, blocks.length, <PageBlock>[
              flexRow,
            ]);
          }
        }
        if (isPageRootFlexColumn) {
          _alignPageRootFlexColumn(
            blocks: blocks,
            start: retainedStart,
            containerStyle: selfStyle,
            pageWidth: contentWidth,
            pageHeight: contentHeight,
          );
        }
        if (retained != null && !isFlexRow) {
          _wrapContainerBlocks(
            blocks,
            retainedStart,
            retained,
            paragraphSpacing:
                splitInlineContainers.contains(selfView) && node.tag == 'p'
                ? overrides.paragraphSpacing
                : null,
          );
        }
      } else if (node is InlineNode) {
        for (final child in node.children) {
          collect(
            child,
            blockTag,
            attributes: attributes,
            groupId: groupId,
            list: list,
            quoteDepth: quoteDepth,
            ancestors: ancestors,
            firstInContainer: firstInContainer,
            lastInContainer: lastInContainer,
            listFirst: listFirst,
            listLast: listLast,
            containerFloat: containerFloat,
            containerFloatWidth: containerFloatWidth,
            containerFloatGroup: containerFloatGroup,
          );
        }
      }
    }

    collect(
      document.root,
      'body',
      attributes: document.root.attributes,
      ancestors: [
        _NodeView('body', document.root.attributes, const <SelectorElement>[]),
      ],
    );
    if (trace != null) {
      trace.record(
        ReaderTraceName.chapterCollect,
        stageWatch!.elapsedMicroseconds,
        bookId: traceBook,
      );
      stageWatch.reset();
    }

    // 相邻块上下外边距折叠（CSS 2.1 §8.3.1）：段距取 max，而不是两段
    // margin 相加。分页器、浮动分页与页索引重放共用这批块对象，
    // PageIndex.from 按块身份记录块序号，必须先折叠再分页。
    blocks = _configureContainerDecoration(blocks);
    blocks = _collapseMarginsIgnoringFloats(blocks);

    if (_isCurrentLayout(layoutGeneration)) {
      _putBlockCache(
        paginationKey,
        flow: blocks,
        fixed: fixedBlocks,
        background: bodyBackground,
      );
    }
    final pages = _paginateBlocks(
      spineIndex,
      paginationKey,
      blocks,
      fixedBlocks,
      bodyBackground,
      layoutGeneration,
    );
    if (trace != null) {
      trace.record(
        ReaderTraceName.chapterPagination,
        stageWatch!.elapsedMicroseconds,
        bookId: traceBook,
      );
      trace.record(
        ReaderTraceName.chapterLayout,
        watch!.elapsedMicroseconds,
        bookId: traceBook,
      );
    }
    return pages;
  }

  /// 补齐纯装饰章的空页，并把同一章的整页背景写入最终页。
  ///
  /// 页缓存保存的是可直接绘制的页；块缓存则持有背景，供
  /// [clearPaginationCache] 后重放时重新贴回，避免两份缓存独立淘汰。
  List<PageContent> _finishChapterPages(
    int spineIndex,
    List<PageContent> source,
    PageBackground? background,
  ) {
    var pages = source;
    if (pages.isEmpty) {
      // 纯装饰章（制作页/书籍信息/作者签名：只有 display:none 标题 +
      // 空段，靠 body 背景图呈现）必须仍产出一页（P9-21）。否则阅读器
      // 认为该章没有页面，翻页/进度会跳过甚至越界。
      pages = <PageContent>[
        PageContent(
          spineIndex: spineIndex,
          pageIndex: 0,
          slices: const <PageBlockSlice>[],
          usedHeight: 0,
          pageHeight: contentHeight,
          topPadding: 0,
        ),
      ];
    }
    if (background == null) {
      return pages;
    }
    return <PageContent>[
      for (final page in pages) page.withBackground(background),
    ];
  }

  /// 对已构建的块树分页或按页索引重放（styles 层命中时跳过重建）。
  List<PageContent> _paginateBlocks(
    int spineIndex,
    String paginationKey,
    List<PageBlock> blocks,
    List<PageBlock> fixedBlocks,
    PageBackground? background,
    int layoutGeneration,
  ) {
    // 浮动章（flat 管线接入）：含浮动块的章节走浮动感知手动分页
    //（引擎 FloatOccupancy 区间模型），不进 Paginator 与页索引重放。
    if (blocks.any((b) => b.floatSide != null)) {
      final floated = _withFixedOverlays(
        _paginateWithFloats(blocks, spineIndex),
        fixedBlocks,
      );
      final pages = _finishChapterPages(spineIndex, floated, background);
      if (_isCurrentLayout(layoutGeneration)) {
        _putPageCache(paginationKey, pages);
      }
      return pages;
    }

    // pagination 层（P7-23）：先试页索引重放（P7-22），跳过分页状态
    // 机；索引缺失/损坏/schema 不匹配时静默重排并回写索引。
    final hasAbsoluteBlocks = blocks.any((block) => block.absolute);
    // 页索引重放只按「行高之和 + leading/trailing」重建切片，声明高度
    //（height/min-height/overflow 裁剪）的块盒内留白/裁剪信息会丢，
    // 二次进入与首次分页可能差几 px；含这类块的章节跳过重放与写入。
    final hasBoxHeightBlocks = blocks.any(
      (block) =>
          (block.height - block.measuredHeight).abs() > 0.01 ||
          block.clipsContent,
    );
    final skipPageIndex = hasAbsoluteBlocks || hasBoxHeightBlocks;
    final cachedIndexBytes = skipPageIndex
        ? null
        : _pageIndexCache[paginationKey];
    if (cachedIndexBytes != null) {
      final index = PageIndex.decode(cachedIndexBytes);
      if (index != null) {
        final replayed = PageIndex.apply(
          index,
          blocks,
          spineIndex: spineIndex,
          trimTextEdges: trimTextEdges,
        );
        if (replayed != null) {
          final pages = _finishChapterPages(spineIndex, replayed, background);
          if (_isCurrentLayout(layoutGeneration)) {
            _putPageCache(paginationKey, pages);
          }
          return pages;
        }
        _logInvalidation('indexSchemaMismatch', paginationKey, paginationKey);
      } else {
        _logInvalidation('indexCorrupted', paginationKey, paginationKey);
      }
      _pageIndexCache.remove(paginationKey);
    }
    final pages = _withFixedOverlays(
      Paginator(
        pageHeight: contentHeight,
        pageWidth: contentWidth,
        topPadding: _chapterTopPadding(blocks),
        trimTextEdges: trimTextEdges,
      ).measureChapter(blocks: blocks, spineIndex: spineIndex).pages,
      fixedBlocks,
    );
    final finished = _finishChapterPages(spineIndex, pages, background);
    if (!_isCurrentLayout(layoutGeneration)) {
      return finished;
    }
    _putPageCache(paginationKey, finished);
    if (!skipPageIndex) {
      _pageIndexCache[paginationKey] = PageIndex.from(
        ChapterPagination(
          spineIndex: spineIndex,
          pages: finished,
          pageHeight: contentHeight,
          totalHeight: 0,
        ),
        blocks,
      ).encode();
    }
    return finished;
  }
}

/// 列表上下文（P3-23）：类型 + 嵌套深度 + ol 序号计数。
class _ListContext {
  _ListContext(
    this.type,
    this.depth, {
    this.spaceBefore = 0,
    this.spaceAfter = 0,
    this.inside = false,
  });

  /// 'ul' 或 'ol'。
  final String type;

  /// 嵌套深度（0 起）。
  final int depth;

  /// 列表容器在首项之前占的高度（容器外边距 + 上边框 + 上内边距）。
  ///
  /// flat 管线不产出容器块，容器的上下外边距必须由首/末项承担，否则
  /// 列表整体上移（用例 11/30 的首项 y 差 6px）。
  final double spaceBefore;

  /// 列表容器在末项之后占的高度（下边框 + 下内边距 + 下外边距）。
  final double spaceAfter;

  /// 列表容器的 `list-style-position: inside`（CSS 里该属性继承，但
  /// ComputedStyle 目前按不继承实现，所以由容器把值带给 li）。
  final bool inside;

  /// 当前 li 还没挂标记（进入新 li 时置位，首个文本块消费后清除）。
  bool markerPending = false;

  int _olCounter = 0;

  /// 当前项的标记文本（P9-12）：优先按 `list-style-type` 选择
  ///（decimal/roman/alpha 等），`none` 不画标记；未声明时 ol 递增序号、
  /// ul 按深度取 disc→circle→square（Reeden 630 §0-#4 嵌套类型轮换）。
  String nextMarker(CssListStyleType style) {
    if (type == 'ol') {
      _olCounter += 1;
      return switch (style) {
        CssListStyleType.none => '',
        CssListStyleType.lowerRoman => '${_roman(_olCounter).toLowerCase()}.',
        CssListStyleType.upperRoman => '${_roman(_olCounter)}.',
        CssListStyleType.lowerAlpha => '${_alpha(_olCounter).toLowerCase()}.',
        CssListStyleType.upperAlpha => '${_alpha(_olCounter).toUpperCase()}.',
        CssListStyleType.circle => '○$_olCounter.',
        CssListStyleType.square => '▪$_olCounter.',
        _ => '$_olCounter.',
      };
    }
    return switch (style) {
      CssListStyleType.none => '',
      CssListStyleType.circle => '○',
      CssListStyleType.square => '▪',
      CssListStyleType.decimal => '${_olCounter += 1}.',
      CssListStyleType.lowerRoman => '${_roman(++_olCounter).toLowerCase()}.',
      CssListStyleType.upperRoman => '${_roman(++_olCounter)}.',
      CssListStyleType.lowerAlpha => '${_alpha(++_olCounter).toLowerCase()}.',
      CssListStyleType.upperAlpha => '${_alpha(++_olCounter).toUpperCase()}.',
      CssListStyleType.disc => const <String>['•', '○', '▪'][depth.clamp(0, 2)],
    };
  }

  static String _roman(int value) {
    if (value <= 0 || value > 3999) {
      return '$value';
    }
    const table = <(int, String)>[
      (1000, 'M'),
      (900, 'CM'),
      (500, 'D'),
      (400, 'CD'),
      (100, 'C'),
      (90, 'XC'),
      (50, 'L'),
      (40, 'XL'),
      (10, 'X'),
      (9, 'IX'),
      (5, 'V'),
      (4, 'IV'),
      (1, 'I'),
    ];
    var rest = value;
    final buffer = StringBuffer();
    for (final (amount, symbol) in table) {
      while (rest >= amount) {
        buffer.write(symbol);
        rest -= amount;
      }
    }
    return buffer.toString();
  }

  static String _alpha(int value) {
    if (value <= 0) {
      return '$value';
    }
    var rest = value;
    final buffer = StringBuffer();
    while (rest > 0) {
      final remainder = (rest - 1) % 26;
      buffer.write(String.fromCharCode(97 + remainder));
      rest = (rest - 1) ~/ 26;
    }
    return String.fromCharCodes(buffer.toString().codeUnits.reversed);
  }
}

/// 选择器匹配视图（P8-02）：flat 管线聚合树的节点适配 SelectorElement。
/// 兄弟池（子代组合器回溯）只读属性层——子视图 childElements 为空表。
class _NodeView implements SelectorElement {
  /// 创建视图。
  const _NodeView(
    this.tag,
    this.attributes,
    this.childElements, {
    this.cacheIdentity = '',
  });

  @override
  final String tag;

  @override
  final Map<String, String> attributes;

  @override
  final List<SelectorElement> childElements;

  /// 原始源码区间；区分同一路径形状的不同元素，避免结构伪类缓存串用。
  final String cacheIdentity;
}

/// 把原始解析树包装成结构完整的原生选择器视图。
class _ParsedSelectorIndex {
  _ParsedSelectorIndex(ParsedElement root) {
    _NodeView build(ParsedElement element) {
      final view = _NodeView(element.tag, element.attributes, [
        for (final child in element.children)
          if (child is ParsedElement) build(child),
      ], cacheIdentity: '${element.start}:${element.end}');
      _views[_key(element.tag, element.start, element.end)] = view;
      return view;
    }

    build(root);
    void index(ParsedElement element, List<SelectorElement> ancestors) {
      final children = element.children.whereType<ParsedElement>();
      final self = _views[_key(element.tag, element.start, element.end)];
      if (self == null) return;
      final chain = [...ancestors, self];
      _chains[_key(element.tag, element.start, element.end)] = chain;
      if (element.tag == 'img' || element.tag == 'image') {
        _imageChains[element.attributes] = chain;
        final src =
            element.attributes['src'] ??
            element.attributes['xlink:href'] ??
            element.attributes['href'];
        if (src != null) (_imageChainsBySrc[src] ??= []).add(chain);
      }
      for (final child in children) {
        index(child, chain);
      }
    }

    index(root, const []);
  }

  final Map<String, List<SelectorElement>> _chains = {};
  final Map<String, _NodeView> _views = {};
  final Map<Map<String, String>, List<SelectorElement>> _imageChains = {};
  final Map<String, List<List<SelectorElement>>> _imageChainsBySrc = {};

  /// 当前文档每个已解析元素从根到自身的真实选择器链。
  Iterable<List<SelectorElement>> get chains => _chains.values;

  List<SelectorElement>? chainOf(EpubNode node) {
    final (tag, start, end, attributes) = switch (node) {
      InlineNode() => (node.tag, node.start, node.end, node.attributes),
      BlockNode() => (node.tag, node.start, node.end, node.attributes),
      _ => ('', -1, -1, const <String, String>{}),
    };
    if (tag == 'img' || tag == 'image') {
      final exact = _imageChains[attributes];
      if (exact != null) return exact;
      final src =
          attributes['src'] ?? attributes['xlink:href'] ?? attributes['href'];
      final sameSrc = src == null ? null : _imageChainsBySrc[src];
      if (sameSrc?.length == 1) return sameSrc!.single;
    }
    return _chains[_key(tag, start, end)];
  }

  static String _key(String tag, int start, int end) => '$tag:$start:$end';
}

/// OPF `itemref` 上的多看页属性（`duokan-page-*` / `page-spread-*`）。
///
/// 语义见 docs/duokan-private-css.md「OPF 页属性」：
/// - `duokan-page-fullscreen`（含 `-spread-left/right`）：封面或插图整页
///   显示，正文样式不参与（cover 铺满，可能裁边）；
/// - `duokan-page-fitwindow`：插图页在窗口内 contain 适配、上下居中；
/// - `page-spread-left/right`：双页模式的左右页标记（单页模式下列入全屏）。
class OpfPageFlags {
  /// 创建页属性。
  const OpfPageFlags({
    this.fullScreen = false,
    this.fitWindow = false,
    this.spreadLeft = false,
    this.spreadRight = false,
  });

  /// 未标记任何页属性。
  static const OpfPageFlags none = OpfPageFlags();

  /// 整页显示（`duokan-page-fullscreen` 及其跨页变体）。
  final bool fullScreen;

  /// 整页图窗口内适配、上下居中（`duokan-page-fitwindow`）。
  final bool fitWindow;

  /// 跨页左页（`page-spread-left` / `duokan-page-fullscreen-spread-left`）。
  final bool spreadLeft;

  /// 跨页右页（`page-spread-right` / `duokan-page-fullscreen-spread-right`）。
  final bool spreadRight;

  /// 是否走整页图路径（全屏或窗口适配）。
  bool get isFullPage => fullScreen || fitWindow;

  @override
  String toString() =>
      'OpfPageFlags(fullScreen: $fullScreen, fitWindow: $fitWindow, '
      'spreadLeft: $spreadLeft, spreadRight: $spreadRight)';
}

/// 行内级联的实际父样式与内容区，正文设置覆盖后供所有行内载荷共用。
typedef _InlineStyleContext = ({
  List<SelectorElement> ancestors,
  ComputedStyle style,
  double width,
  String? readerFontFamily,
});

/// 作者样式表组合的身份键。
///
/// 加载器会给每章包装新的 [CssStylesheet] 外壳，但外链 CSS 的规则与字体
/// 列表仍复用同一解析结果；按键内数据身份比较可跨章命中共用缓存。
class _CssSheetSetKey {
  _CssSheetSetKey(List<CssStylesheet> sheets, this.fontRevision)
    : rules = List<List<CssRule>>.unmodifiable(
        sheets.map((sheet) => sheet.rules),
      ),
      fontFaces = List<List<CssFontFace>>.unmodifiable(
        sheets.map((sheet) => sheet.fontFaces),
      );

  final List<List<CssRule>> rules;
  final List<List<CssFontFace>> fontFaces;
  final int fontRevision;

  @override
  int get hashCode => Object.hash(
    fontRevision,
    Object.hashAll(rules.map(identityHashCode)),
    Object.hashAll(fontFaces.map(identityHashCode)),
  );

  @override
  bool operator ==(Object other) {
    if (other is! _CssSheetSetKey ||
        fontRevision != other.fontRevision ||
        rules.length != other.rules.length ||
        fontFaces.length != other.fontFaces.length) {
      return false;
    }
    for (var i = 0; i < rules.length; i++) {
      if (!identical(rules[i], other.rules[i]) ||
          !identical(fontFaces[i], other.fontFaces[i])) {
        return false;
      }
    }
    return true;
  }
}

/// 一组作者样式表在章节排版前的派生结果。
class _ChapterCascadePreparation {
  const _ChapterCascadePreparation({
    required this.auxiliaryRules,
    required this.firstLetterRules,
    required this.pseudoRules,
    required this.cascadeRules,
  });

  final List<_AuxiliaryCssRule> auxiliaryRules;
  final List<_AuxiliaryCssRule> firstLetterRules;
  final Map<String, List<_AuxiliaryCssRule>> pseudoRules;
  final CascadeRuleSet cascadeRules;
}

typedef _AuxiliaryCssRule = ({
  SelectorList selectors,
  List<CssDeclaration> declarations,
  String selectorText,
  String? media,
});

/// `<q>` 生成的单个引号，用于同步扩写文本并重映射行内偏移。
class _QuoteInsertion {
  const _QuoteInsertion({
    required this.offset,
    required this.text,
    required this.depth,
    required this.opening,
  });

  final int offset;
  final String text;
  final int depth;
  final bool opening;
}

/// 生成内容的文本与图片占位位置。
class _PseudoContent {
  const _PseudoContent({required this.text, required this.images});

  final String text;
  final List<_PseudoContentImage> images;
}

/// 生成内容中的单张图片；[offset] 指向文本里的 U+FFFC。
class _PseudoContentImage {
  const _PseudoContentImage({required this.offset, required this.url});

  final int offset;
  final String url;
}

/// 伪元素图片在扩写、浮动摘除和切片后的当前块内位置。
class _PseudoImageMark {
  const _PseudoImageMark({
    required this.offset,
    required this.url,
    required this.pseudo,
  });

  final int offset;
  final String url;
  final String pseudo;
}

/// 行内浮动提取结果（W17）：摘出的浮动块 + 剩余文本与偏移重映射。
class _InlineFloatExtraction {
  const _InlineFloatExtraction({
    required this.text,
    required this.marks,
    required this.remapOffset,
    required this.removeStart,
    required this.removeEnd,
    this.block,
    this.inlineBox,
    this.footnote,
  });

  /// 摘掉浮动内容后的段落文本。
  final String text;

  /// 重映射后的行内标记（用于重新生成 runs）。
  final List<InlineMark> marks;

  /// 摘出的浮动块（行内浮动）。
  final PageBlock? block;

  /// 摘出的行内盒子（`display: inline-block`）：交给行排版按行内盒放置。
  final InlineBoxSpec? inlineBox;

  /// 行内盒本身作为注释入口时的弹窗数据。
  final PageFootnote? footnote;

  /// 旧偏移 → 新偏移。
  final int Function(int offset) remapOffset;

  /// 被摘掉的区间（旧坐标，半开）。
  final int removeStart;
  final int removeEnd;

  /// 偏移是否落在被摘掉的区间内。
  bool removed(int offset) => offset >= removeStart && offset < removeEnd;
}
