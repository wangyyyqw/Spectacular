import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:reader_core/api.dart' hide ComputedStyle, Paginator;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/css/ua_stylesheet.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/full_bleed.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_core/paint/image_size.dart';
import 'package:reader_ui/reader_session.dart';

/// 从 EPUB 文档读取章节并提供分页结果。
class EpubChapterSource
    implements RestylableChapterSource, ResizableChapterSource {
  EpubChapterSource._({
    required this.document,
    required this.baseContentWidth,
    required this.baseContentHeight,
    required this.baseStyle,
  });

  /// 打开 EPUB 并创建来源。
  static Future<EpubChapterSource> open(
    Uint8List bytes, {
    double contentWidth = 320,
    double contentHeight = 480,
    ComputedStyle? style,
  }) async {
    final result = await openEpub(bytes);
    final document = result.document;
    if (document == null) {
      throw StateError(result.report.message ?? '打开 EPUB 失败');
    }
    return EpubChapterSource._(
      document: document,
      baseContentWidth: contentWidth,
      baseContentHeight: contentHeight,
      baseStyle:
          style ??
          ComputedStyle(const <String, String>{
            'font-size': '16px',
            'line-height': '1.5',
            'font-family': 'serif',
          }),
    );
  }

  /// 已打开文档。
  final EpubDocumentImpl document;

  /// 原始正文区宽（未扣设置页边距）。
  final double baseContentWidth;

  /// 原始正文区高。
  final double baseContentHeight;

  /// 书籍基础样式。
  final ComputedStyle baseStyle;

  ReaderOverrides _overrides = const ReaderOverrides();

  /// 阅读页传入的正文区尺寸（旋转/窗口变化后由 ReaderSession 设置）。
  double? _viewportContentWidth;
  double? _viewportContentHeight;

  /// 段落布局缓存（P2-26）：同一文本+样式的重复测量直接复用。
  final TextLayoutCache _layoutCache = TextLayoutCache();

  /// 排版缓存三层（P7-23；对照 Reeden document/styles/pagination，
  /// 550 号 §0）：
  /// - document：聚合后的章节文本（解析+聚合结果），键=spineIndex；
  /// - styles：块级样式由 [styleFor] 按（基准+覆盖）即时派生，缓存键
  ///   只含影响该层的最小变量集（字号/行高/对齐/边距/几何）；
  /// - pagination：页缓存与页索引，键=spineIndex+排版指纹（几何+设置
  ///   排版字段）。主题颜色不进任何键 → 切主题零重排。
  final Map<int, BlockDocument> _documentCache = <int, BlockDocument>{};
  final Map<String, List<PageContent>> _pageCache = <String, List<PageContent>>{};
  final Map<String, Uint8List> _pageIndexCache = <String, Uint8List>{};

  /// 排版层指纹（P7-23）：几何 + 设置的排版字段；颜色不参与（绘制层
  /// 即时生效，不失效任何缓存）。
  String _paginationKey(int spineIndex) =>
      '$spineIndex@${contentWidth.toString()}x${contentHeight.toString()}'
      '|${_overrides.fingerprint}';

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

  /// 仅清空页缓存（保留页索引）：供冷启动重放路径测试与 P7-27 续排
  /// 使用——页索引仍在时 loadChapter 直接按边界出页。
  void clearPaginationCache() {
    _pageCache.clear();
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

  /// 构建满屏图页：整页单块 + 背景图 cover（复用 P2-13 背景管线与
  /// PagePainter.imageLookup），边距归零（用未扣设置页边距的基准尺寸）。
  /// 解码由 ReaderPage 的 imageCache 异步完成，revision 触发重绘。
  List<PageContent> _buildFullBleedPages(
    int spineIndex,
    String imageSrc,
    String paginationKey,
  ) {
    final width = math.max(80.0, baseContentWidth);
    final height = math.max(120.0, baseContentHeight);
    final item = document.spine[spineIndex];
    final chapterBase = p.posix.dirname(
      document.resources.resolve(item.href, baseDir: p.posix.dirname(
        document.opfPath,
      )) ??
          item.href,
    );
    final imageUrl = document.resources
            .resolve(imageSrc, baseDir: chapterBase) ??
        imageSrc;
    final blockStyle = ComputedStyle(<String, String>{
      ...baseStyle.values,
      'background-image': 'url($imageUrl)',
      'background-size': 'cover',
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
    final pages = Paginator(pageHeight: height)
        .measureChapter(
          blocks: [
            PageBlock(layout: layout, style: blockStyle),
          ],
          spineIndex: spineIndex,
        )
        .pages;
    _pageIndexCache[paginationKey] = PageIndex.from(
      ChapterPagination(
        spineIndex: spineIndex,
        pages: pages,
        pageHeight: height,
        totalHeight: 0,
      ),
      [
        PageBlock(layout: layout, style: blockStyle),
      ],
    ).encode();
    return pages;
  }

  /// 文本块样式：书籍样式叠加阅读器覆盖。
  ComputedStyle get style =>
      _overrides.apply(baseStyle, containingWidth: contentWidth);

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    final previous = _overrides;
    _overrides = overrides;
    // 失效矩阵（P7-23）：只有排版字段（字号/行高/对齐/边距）变化才
    // 失效 pagination 层与段落缓存；颜色变化零重排（绘制层即时生效）。
    if (previous.fingerprint != overrides.fingerprint) {
      _logInvalidation(
        'configChanged',
        previous.fingerprint,
        overrides.fingerprint,
      );
      _layoutCache.clear();
      _pageCache.clear();
      _pageIndexCache.clear();
    }
  }

  @override
  Future<bool> applyContentSize({
    required double width,
    required double height,
  }) async {
    final nextWidth = math.max(80.0, width);
    final nextHeight = math.max(120.0, height);
    final previousWidth = contentWidth;
    final previousHeight = contentHeight;
    _viewportContentWidth = nextWidth;
    _viewportContentHeight = nextHeight;
    if (previousWidth == nextWidth && previousHeight == nextHeight) {
      return false;
    }
    // 尺寸变化等同重排：几何进排版键（P7-23 矩阵「几何全失效」）。
    _logInvalidation(
      'viewportSizeChanged',
      '${previousWidth.toString()}x${previousHeight.toString()}',
      '${nextWidth.toString()}x${nextHeight.toString()}',
    );
    _layoutCache.clear();
    _pageCache.clear();
    _pageIndexCache.clear();
    return true;
  }

  @override
  int get chapterCount => document.spine.length;

  /// 满屏判定缓存（P3-10）：spineIndex → 分析结果；聚合文本含 U+FFFC
  /// 才做深度分析，普通文字章零开销。
  final Map<int, FullBleedChapter> _fullBleedCache = <int, FullBleedChapter>{};

  /// 图片原始尺寸缓存（按解析后 URL，跨章复用）；读取失败记 miss 防
  /// 重复解压。
  final Map<String, ImageIntrinsicSize> _imageIntrinsicCache =
      <String, ImageIntrinsicSize>{};
  final Set<String> _imageIntrinsicMiss = <String>{};

  /// 作者样式表缓存：CSS 文件 URL → 解析结果（跨章共享）；章节 → 该章
  /// link 的样式表序列（文档顺序，级联后声明覆盖先声明）。
  final Map<String, CssStylesheet> _cssSheetCache = <String, CssStylesheet>{};
  final Map<int, List<CssStylesheet>> _chapterSheetCache =
      <int, List<CssStylesheet>>{};

  /// 章节作者样式表（真实书适配）：提取章节 `<link rel=stylesheet>`
  /// 与 `<style>`，按文档顺序解析；CSS 文件字节按 URL 缓存。
  List<CssStylesheet> _chapterStylesheets(int spineIndex) {
    return _chapterSheetCache.putIfAbsent(spineIndex, () {
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
      final inline = CssParser.extractFromXhtml(
        utf8.decode(xhtmlBytes, allowMalformed: true),
      );
      final chapterBase = p.posix.dirname(xhtmlPath);
      final sheets = <CssStylesheet>[];
      for (final href in inline.links) {
        final url =
            document.resources.resolve(href, baseDir: chapterBase) ??
                href;
        sheets.add(
          _cssSheetCache.putIfAbsent(url, () {
            final bytes = document.archive.readBytes(url);
            if (bytes == null) {
              return const CssStylesheet(
                rules: [],
                imports: [],
                warnings: [],
              );
            }
            return CssParser.parse(
              utf8.decode(bytes, allowMalformed: true),
            );
          }),
        );
      }
      if (inline.css.isNotEmpty) {
        sheets.add(CssParser.parse(inline.css));
      }
      return sheets;
    });
  }

  /// 匹配作者声明：仅支持单复合选择器（`p`、`p.cls`、`.cls`），后代/
  /// 子/伪类选择器与 `@media` 内规则跳过；保持文档顺序，后声明覆盖
  /// 先声明（CSS 级联的同优先级语义）。
  static Map<String, String> _authorDeclarations(
    List<CssStylesheet> sheets,
    String tag,
    String? classes,
  ) {
    final merged = <String, String>{};
    final classSet = (classes ?? '')
        .split(RegExp(r'\s+'))
        .where((c) => c.isNotEmpty)
        .toSet();
    for (final sheet in sheets) {
      for (final rule in sheet.rules) {
        if (rule.media != null) {
          continue;
        }
        for (final raw in rule.selector.split(',')) {
          final selector = raw.trim();
          if (selector.isEmpty ||
              selector.contains(' ') ||
              selector.contains('>') ||
              selector.contains(':')) {
            continue;
          }
          final dot = selector.indexOf('.');
          final selectorTag = dot < 0 ? selector : selector.substring(0, dot);
          final selectorClasses = dot < 0
              ? const <String>{}
              : selector
                  .substring(dot + 1)
                  .split('.')
                  .where((c) => c.isNotEmpty)
                  .toSet();
          if (selectorTag.isNotEmpty && selectorTag != tag) {
            continue;
          }
          if (selectorClasses.isNotEmpty &&
              !selectorClasses.every(classSet.contains)) {
            continue;
          }
          for (final declaration in rule.declarations) {
            merged[declaration.property] = declaration.value;
          }
        }
      }
    }
    return merged;
  }

  /// 图片显示尺寸：width/height 属性（% 或 px）优先，缺边按原始宽高比
  /// 补齐；CSS class 尺寸（textiE1 的 width:100%）flat 管线暂不解析，
  /// 无属性时按全宽近似。高超出页高时钳制（contain 绘制不变形）。
  (double, double) _resolveImageDisplaySize(
    Map<String, String> attributes,
    ImageIntrinsicSize? intrinsic,
    double maxWidth,
    double maxHeight,
  ) {
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

    var width = parseLength(attributes['width'], maxWidth);
    var height = parseLength(attributes['height'], maxHeight);
    if (width != null && width > maxWidth) {
      width = maxWidth;
    }
    if (height != null && height > maxHeight) {
      height = maxHeight;
    }
    if (width == null && height == null) {
      if (intrinsic == null) {
        return (maxWidth, maxHeight * 0.6);
      }
      width = maxWidth;
    }
    if (width != null && height == null && intrinsic != null) {
      height = width * intrinsic.height / intrinsic.width;
    } else if (height != null && width == null && intrinsic != null) {
      width = height * intrinsic.width / intrinsic.height;
    }
    width ??= maxWidth;
    height ??= width * 0.75;
    if (height > maxHeight) {
      height = maxHeight;
    }
    return (width, height);
  }

  /// 章节是否走满屏路径（单图无正文无宽高属性，§8.6）。
  FullBleedChapter fullBleedAnalysis(int spineIndex) {
    return _fullBleedCache.putIfAbsent(spineIndex, () {
      final aggregated = _documentCache.putIfAbsent(
        spineIndex,
        () => document.aggregateText(
          spineIndex,
          whiteSpace: style.whiteSpace,
        ),
      );
      // 纯图块折叠后 img 块不再产生 \uFFFC 占位文本，需同时扫描聚合树。
      if (!aggregated.plainText.contains('\uFFFC') &&
          !_treeHasImageBlock(aggregated.root)) {
        return const FullBleedChapter(
          imageCount: 0,
          hasVisibleText: true,
          singleImageSrc: null,
          singleImageHasDimensions: false,
        );
      }
      return analyzeFullBleed(document.parseBlocks(spineIndex));
    });
  }

  /// 聚合树中是否存在折叠出的 img 块。
  static bool _treeHasImageBlock(BlockNode node) {
    if (node.tag == 'img') {
      return true;
    }
    for (final child in node.children) {
      if (child is BlockNode && _treeHasImageBlock(child)) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final paginationKey = _paginationKey(spineIndex);
    final cachedPages = _pageCache[paginationKey];
    if (cachedPages != null) {
      return cachedPages;
    }
    // 满屏图页（P3-10，§8.6）：单图无正文无宽高属性 → 整页单块、
    // 边距归零、背景图 cover。先于普通聚合判定。
    final fullBleed = fullBleedAnalysis(spineIndex);
    if (fullBleed.isFullBleed) {
      final pages = _buildFullBleedPages(
        spineIndex,
        fullBleed.singleImageSrc!,
        paginationKey,
      );
      _pageCache[paginationKey] = pages;
      return pages;
    }
    // document 层（P7-23）：聚合结果按章缓存。
    final document = _documentCache.putIfAbsent(
      spineIndex,
      () => this.document.aggregateText(
        spineIndex,
        whiteSpace: style.whiteSpace,
      ),
    );
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
              this.document.resources.resolve(src, baseDir: chapterBase) ??
                  src;
          if (!imageSizes.containsKey(url)) {
            var size = _imageIntrinsicCache[url];
            if (size == null && !_imageIntrinsicMiss.contains(url)) {
              final bytes = this.document.archive.readBytes(url);
              size = bytes == null
                  ? null
                  : ImageSizeParser.readImageSize(bytes);
              if (size == null) {
                _imageIntrinsicMiss.add(url);
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

    gatherImageSrcs(document.root);
    final blocks = <PageBlock>[];

    void collectImageBlock(BlockNode node) {
      // src 键名兼容 SVG <image xlink:href> 折叠链。
      final src = node.attributes['src'] ?? node.attributes['xlink:href'];
      if (src == null || src.isEmpty) {
        return;
      }
      final url =
          this.document.resources.resolve(src, baseDir: chapterBase) ?? src;
      final size = _resolveImageDisplaySize(
        node.attributes,
        imageSizes[url],
        contentWidth,
        contentHeight,
      );
      final blockStyle = ComputedStyle(<String, String>{
        ...baseStyle.values,
        'background-image': 'url($url)',
        'background-size': 'contain',
        'background-position': 'center center',
        'background-repeat': 'no-repeat',
      });
      // 空行盒块：无 runs（不画字），块盒即图片显示区，背景按 contain
      // 居中绘制（块高按原图比例换算时恰好铺满，不变形）。
      final layout = TextLayoutResult(
        text: '',
        lines: [
          LineBox(
            start: 0,
            end: 0,
            top: 0,
            height: size.$2,
            baseline: size.$2,
            width: contentWidth,
          ),
        ],
        width: contentWidth,
        height: size.$2,
        maxWidth: contentWidth,
        runs: const <StyledRun>[],
      );
      blocks.add(PageBlock(layout: layout, style: blockStyle));
    }

    // 块级样式（P7-03 + 真实书适配）：UA 标签默认 + 作者 CSS（标签/
    // class 规则，级联后声明覆盖先声明）叠加；em 相对阅读器基准字号
    // 解算；同（标签, class, 引用深度）只构造一次。
    final sheets = _chapterStylesheets(spineIndex);
    final uaStyles = <String, ComputedStyle>{};
    var figureSeq = 0;
    ComputedStyle styleFor(
      String tag, {
      Map<String, String>? attributes,
      int quoteDepth = 0,
    }) {
      final classes = attributes?['class'];
      final key = '$tag|$classes|$quoteDepth';
      final cached = uaStyles[key];
      if (cached != null) {
        return cached;
      }
      final declarations = <String, String>{
        ...UaBlockDefaults.declarationsFor(tag),
        ..._authorDeclarations(sheets, tag, classes),
      };
      if (declarations.isEmpty && quoteDepth == 0) {
        return uaStyles[key] = style;
      }
      if (quoteDepth == 0) {
        return uaStyles[key] = ComputedStyle(
          declarations,
          parent: style,
          explicitProperties: declarations.keys.toSet(),
          containingWidth: contentWidth,
          rootFontSize: style.fontSize,
        );
      }
      // 引用容器（M2）：flat 管线无 blockquote 盒子，容器的左右边距
      // 按嵌套深度叠加到子块声明上（WHATWG 15.3.3 一层 40px）。
      final fallback = declarations.isEmpty
          ? style
          : ComputedStyle(
              declarations,
              parent: style,
              explicitProperties: declarations.keys.toSet(),
              containingWidth: contentWidth,
              rootFontSize: style.fontSize,
            );
      final extra = 40.0 * quoteDepth;
      final quoteDeclarations = <String, String>{
        ...declarations,
        'margin-left': '${fallback.margin.left + extra}px',
        'margin-right': '${fallback.margin.right + extra}px',
      };
      return uaStyles[key] = ComputedStyle(
        quoteDeclarations,
        parent: style,
        explicitProperties: quoteDeclarations.keys.toSet(),
        containingWidth: contentWidth,
        rootFontSize: style.fontSize,
      );
    }

    void collect(
      EpubNode node,
      String blockTag, {
      Map<String, String>? attributes,
      int groupId = 0,
      _ListContext? list,
      int quoteDepth = 0,
    }) {
      if (node is TextBlockNode) {
        final cfi = node is TextContentNode ? node.cfi.serialize() : null;
        final text = node.text;
        if (text.trim().isEmpty) {
          return;
        }
        final blockStyle = styleFor(
          blockTag,
          attributes: attributes,
          quoteDepth: quoteDepth,
        );
        // 列表标记（P3-23）：li 项按所在列表类型与序号赋标记文本。
        String? marker;
        if (blockTag == 'li' && list != null) {
          marker = list.nextMarker();
        }
        final layout = _layoutCache.layout(
          text: text,
          style: blockStyle,
          maxWidth: contentWidth,
        );
        if (layout.lineCount > 0) {
          blocks.add(
            PageBlock.styled(
              layout: layout,
              style: blockStyle,
              containingWidth: contentWidth,
              startCfi: cfi,
              groupId: groupId,
              listMarker: marker,
            ),
          );
        }
      } else if (node is BlockNode) {
        // 折叠出的纯图块（真实书适配）：构造背景图块（contain 居中），
        // 块高按属性尺寸/原始宽高比换算。
        if (node.tag == 'img' && node.children.isEmpty) {
          collectImageBlock(node);
          return;
        }
        // 整组不可切（P7-26）：figure（图+题注）内的块标记同组。
        var childGroup = groupId;
        if (node.tag == 'figure') {
          figureSeq += 1;
          childGroup = figureSeq;
        }
        // 列表上下文（P3-23）：ul/ol 开新层，li 沿用所在列表。
        _ListContext? childList = list;
        if (node.tag == 'ul' || node.tag == 'ol') {
          childList = _ListContext(node.tag, (list?.depth ?? -1) + 1);
        } else if (node.tag == 'li' && list != null) {
          childList = list;
        }
        // 引用深度（M2）：blockquote 每层 +1，容器左右边距叠加到子块。
        final childQuoteDepth =
            node.tag == 'blockquote' ? quoteDepth + 1 : quoteDepth;
        // 作者 CSS（真实书适配）：块自身属性（class/style）供样式匹配。
        for (final child in node.children) {
          collect(
            child,
            node.tag,
            attributes: node.attributes,
            groupId: childGroup,
            list: childList,
            quoteDepth: childQuoteDepth,
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
          );
        }
      }
    }

    collect(document.root, 'body', attributes: document.root.attributes);
    // pagination 层（P7-23）：先试页索引重放（P7-22），跳过分页状态
    // 机；索引缺失/损坏/schema 不匹配时静默重排并回写索引。
    final cachedIndexBytes = _pageIndexCache[paginationKey];
    if (cachedIndexBytes != null) {
      final index = PageIndex.decode(cachedIndexBytes);
      if (index != null) {
        final replayed = PageIndex.apply(index, blocks, spineIndex: spineIndex);
        if (replayed != null) {
          _pageCache[paginationKey] = replayed;
          return replayed;
        }
        _logInvalidation('indexSchemaMismatch', paginationKey, paginationKey);
      } else {
        _logInvalidation('indexCorrupted', paginationKey, paginationKey);
      }
      _pageIndexCache.remove(paginationKey);
    }
    final pages = Paginator(pageHeight: contentHeight)
        .measureChapter(blocks: blocks, spineIndex: spineIndex)
        .pages;
    _pageCache[paginationKey] = pages;
    _pageIndexCache[paginationKey] = PageIndex.from(
      ChapterPagination(
        spineIndex: spineIndex,
        pages: pages,
        pageHeight: contentHeight,
        totalHeight: 0,
      ),
      blocks,
    ).encode();
    return pages;
  }
}

/// 列表上下文（P3-23）：类型 + 嵌套深度 + ol 序号计数。
class _ListContext {
  _ListContext(this.type, this.depth);

  /// 'ul' 或 'ol'。
  final String type;

  /// 嵌套深度（0 起）。
  final int depth;

  int _olCounter = 0;

  /// 当前项的标记文本；ol 递增序号，ul 按深度取 disc→circle→square
  ///（Reeden 630 §0-#4 嵌套类型轮换）。
  String nextMarker() {
    if (type == 'ol') {
      _olCounter += 1;
      return '$_olCounter.';
    }
    const bullets = <String>['•', '○', '▪'];
    return bullets[depth.clamp(0, 2)];
  }
}
