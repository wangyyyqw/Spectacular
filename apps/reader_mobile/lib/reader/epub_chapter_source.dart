import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, Rect;

import 'package:path/path.dart' as p;
import 'package:reader_core/api.dart' hide ComputedStyle, Paginator;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/book_font_loader.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/css/ua_stylesheet.dart' show UaBlockDefaults, uaRules;
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/css/ua_stylesheet.dart';
import 'package:reader_core/epub/epub_document.dart';
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
import 'package:reader_core/parser/full_bleed.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_core/paint/image_size.dart';
import 'package:reader_core/text/xhtml_text.dart';
import 'package:reader_ui/reader_session.dart';

/// 从 EPUB 文档读取章节并提供分页结果。
class EpubChapterSource
    implements RestylableChapterSource, ResizableChapterSource, TocChapterSource {
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
    bool verifyCrc = true,
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

  /// white-space 原文保留（P9-28）：命中章节的判定结果与两遍保留模式
  /// 聚合的文本节点（键 = 源码起止偏移），见 [_preservedTexts]。
  final Map<int, bool> _preservingWhiteSpaceCache = <int, bool>{};
  final Map<int, Map<String, TextContentNode>> _preservedRawTexts =
      <int, Map<String, TextContentNode>>{};
  final Map<int, Map<String, TextContentNode>> _preservedPreLineTexts =
      <int, Map<String, TextContentNode>>{};

  /// 页缓存（key = paginationKey）：按章 LRU，上限 [pageCacheChapterLimit] 章
  /// （§44.4：只留当前章 ±2）。
  final Map<String, List<PageContent>> _pageCache =
      <String, List<PageContent>>{};

  /// LRU 顺序（最近使用的在末尾）。
  final List<String> _pageCacheOrder = <String>[];

  /// 章级整页背景（P9-04）：body 的 background-image，按章缓存。
  final Map<int, PageBackground> _pageBackgrounds = <int, PageBackground>{};

  /// 页缓存保留的章数上限（当前章 ±2）。
  static const int pageCacheChapterLimit = 5;

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

  /// 缓存报告（P4-32）：页缓存章数与容量。
  String get cacheReport =>
      '页缓存 ${_pageCache.length}/$pageCacheChapterLimit 章';
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
      rule.declarations.any((declaration) => declaration.property == 'margin-left');

  /// 级联后的浮动方向（f）；未浮动返回 null。
  static FloatSide? _floatSideOfStyle(ComputedStyle style) => switch (
    style.cssFloat
  ) {
    CssFloat.left => FloatSide.left,
    CssFloat.right => FloatSide.right,
    CssFloat.none => null,
  };

  /// 浮动文本块：`PageBlock.styled` 不透传 floatSide，这里按同一口径
  /// 直接构造（内缩 = 边框 + 内边距；声明高度走 [BoxModel] 解算）。
  PageBlock _floatedTextBlock({
    required TextLayoutResult layout,
    required ComputedStyle style,
    required FloatSide side,
    required double spaceBefore,
    required double spaceAfter,
    String? startCfi,
    int groupId = 0,
    bool containerSides = false,
    double effectiveOpacity = 1,
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
      declaredContentHeight: model.resolveContentHeight(
        layout.height,
        containingHeight: contentHeight,
      ),
      startCfi: startCfi,
      groupId: groupId,
      containerSides: containerSides,
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
    if (_imageIntrinsicMiss.contains(url)) {
      return null;
    }
    final bytes = document.archive.readBytes(url);
    final size = bytes == null ? null : ImageSizeParser.readImageSize(bytes);
    if (size == null) {
      _imageIntrinsicMiss.add(url);
    } else {
      _imageIntrinsicCache[url] = size;
    }
    return size;
  }

  List<PageContent> _buildFullBleedPages(
    int spineIndex,
    String imageSrc,
    String paginationKey, {
    bool contain = false,
    bool bleed = false,
  }) {
    final width = math.max(80.0, baseContentWidth);
    final height = math.max(120.0, baseContentHeight);
    final imageUrl = _chapterImageUrl(spineIndex, imageSrc);
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
    // 全屏页用出血标记让绘制层横向顶到页面边缘（不看页边距）。
    final block = PageBlock(
      layout: layout,
      style: blockStyle,
      bleedLeft: bleed,
      bleedRight: bleed,
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
    _pageCacheOrder.clear();
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
    _pageCacheOrder.clear();
    _pageIndexCache.clear();
    return true;
  }

  /// 埋点用的书籍标识（P4-31）；由打开方按需设置。
  String? bookIdForTrace;

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

  /// 书内字体（P3-01/02 接入 flat 管线）：@font-face 注册器与引擎族名
  /// 映射；bookId 由 OPF 路径派生（同书同族隔离，多书不串）。
  BookFontLoader? _fontLoader;
  final Set<String> _fontFacesSeen = <String>{};

  /// 书内字族 → 引擎族名（键为小写 CSS 族名）。
  ///
  /// [BookFontLoader] 把 `@font-face` 注册成 `bi_<bookId>_<族>`，TextPainter
  /// 只认这个引擎族名；书名 CSS 里的 `font-family: "mm"` 不改写就等于整条
  /// font-face 链路白建（真书：章号被画成缺字方块）。
  final Map<String, String> _bookFontEngines = <String, String>{};

  String get _bookId => 'bk-${document.opfPath.hashCode}';

  /// 注册章内 `@font-face`（真实书适配）：书内字体按 face 键去重后
  /// 经 BookFontLoader 注册到引擎；字节解析沿用图片的多路径回退
  /// （直读 → OPF 目录 → 各章节目录）。
  Future<void> _ensureBookFonts(List<CssStylesheet> sheets) async {
    final faces = <CssFontFace>[
      for (final sheet in sheets) ...sheet.fontFaces,
    ];
    if (faces.isEmpty) {
      return;
    }
    final loader = _fontLoader ??= BookFontLoader(bookId: _bookId);
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
    await loader.load(pending, resolveBytes: (url) async {
      final direct = document.archive.readBytes(url);
      if (direct != null) {
        return direct;
      }
      final resolved = document.resources.resolve(url);
      if (resolved != null) {
        final bytes = document.archive.readBytes(resolved);
        if (bytes != null) {
          return bytes;
        }
      }
      for (final item in document.spine) {
        final slash = item.href.lastIndexOf('/');
        final baseDir = slash < 0 ? '' : item.href.substring(0, slash);
        final candidate = document.resources.resolve(url, baseDir: baseDir);
        if (candidate == null) {
          continue;
        }
        final bytes = document.archive.readBytes(candidate);
        if (bytes != null) {
          return bytes;
        }
      }
      return null;
    });
    _syncBookFontEngines(loader, faces);
  }

  /// 把已注册成功的族收进「CSS 族名 → 引擎族名」映射。
  ///
  /// 只收注册成功的（[BookFontLoader.engineFamily] 非空）：加载失败的族
  /// 保持原样，让 `font-family` 回退链继续生效。
  void _syncBookFontEngines(BookFontLoader loader, List<CssFontFace> faces) {
    for (final face in faces) {
      final engine = loader.engineFamily(face.family);
      if (engine != null) {
        _bookFontEngines[face.family.toLowerCase()] = engine;
      }
    }
  }

  /// 重写作者样式表里的 `font-family` / `font` 简写：书内字族换成引擎族名。
  ///
  /// 在「声明 → 级联」之间改写（不是算完样式再改）：ComputedStyle 没有
  /// 公开的 withFontFamilies，重建样式会重新解析整份声明并丢失已继承的
  /// 值；改写声明则让级联、继承、行内 run 全部自然拿到引擎族名，成本是
  /// 每章一次 O(规则数) 而不是每块一次。未注册的族原样保留（回退链不变）。
  List<CssStylesheet> _rewriteBookFontSheets(List<CssStylesheet> sheets) {
    if (_bookFontEngines.isEmpty) {
      return sheets;
    }
    final result = <CssStylesheet>[];
    for (final sheet in sheets) {
      var changed = false;
      final rules = <CssRule>[];
      for (final rule in sheet.rules) {
        final declarations = _rewriteBookFontDeclarations(rule.declarations);
        if (identical(declarations, rule.declarations)) {
          rules.add(rule);
          continue;
        }
        changed = true;
        rules.add(
          CssRule(
            selector: rule.selector,
            declarations: declarations,
            media: rule.media,
          ),
        );
      }
      result.add(
        changed
            ? CssStylesheet(
                rules: List.unmodifiable(rules),
                imports: sheet.imports,
                warnings: sheet.warnings,
                fontFaces: sheet.fontFaces,
              )
            : sheet,
      );
    }
    return result;
  }

  /// 逐条改写声明；未命中时返回原列表（调用方用 identical 判重）。
  List<CssDeclaration> _rewriteBookFontDeclarations(
    List<CssDeclaration> declarations,
  ) {
    if (_bookFontEngines.isEmpty) {
      return declarations;
    }
    List<CssDeclaration>? rewritten;
    for (var i = 0; i < declarations.length; i++) {
      final declaration = declarations[i];
      final fontFamily = declaration.property == 'font-family';
      if (!fontFamily && declaration.property != 'font') {
        continue;
      }
      final value = fontFamily
          ? _rewriteFontFamilyList(declaration.value)
          : _rewriteFontShorthand(declaration.value);
      if (value == declaration.value) {
        continue;
      }
      rewritten ??= List<CssDeclaration>.of(declarations);
      rewritten[i] = CssDeclaration(
        property: declaration.property,
        value: value,
        important: declaration.important,
      );
    }
    return rewritten ?? declarations;
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

  /// `font: italic bold 16px/1.5 "mm", serif` → 只替换族列表部分。
  ///
  /// 简写前缀（样式/字重/字号/行高）不含族名，按「最后一组引号串或尾随
  /// 裸族名」定位，命中注册表才替换。
  String _rewriteFontShorthand(String value) {
    var result = value;
    var changed = false;
    // 引号族名：简写里唯一可能出现引号的位置。
    result = result.replaceAllMapped(_quotedFontFamily, (match) {
      final name = _unquoteFontFamily(match.group(1) ?? '');
      final engine = _bookFontEngines[name.toLowerCase()];
      if (engine == null) {
        return match.group(0) ?? '';
      }
      changed = true;
      return '"$engine"';
    });
    if (changed) {
      return result;
    }
    // 裸族名：`font: 12pt mm` 这类尾声。
    final bare = RegExp(r'(?:^|[\s/])([A-Za-z_][\w-]*)$').firstMatch(result);
    if (bare == null) {
      return value;
    }
    final name = bare.group(1)!;
    final engine = _bookFontEngines[name.toLowerCase()];
    if (engine == null) {
      return value;
    }
    return result.replaceRange(
      bare.end - name.length,
      result.length,
      '"$engine"',
    );
  }

  static final RegExp _quotedFontFamily = RegExp(r'''["']([^"']*)["']''');

  static String _unquoteFontFamily(String raw) {
    if (raw.length >= 2 &&
        ((raw.startsWith('"') && raw.endsWith('"')) ||
            (raw.startsWith("'") && raw.endsWith("'")))) {
      return raw.substring(1, raw.length - 1);
    }
    return raw;
  }

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
      final visited = <String>{};

      /// 加载一张样式表并先展开它的 @import（P9-10）：被导入的规则在
      /// 层叠顺序上位于导入方之前，之前完全没加载等于整份样式丢失。
      void loadSheet(String url, {int depth = 0}) {
        if (depth > 8 || !visited.add(url)) {
          return;
        }
        final sheet = _cssSheetCache.putIfAbsent(url, () {
          final bytes = document.archive.readBytes(url);
          if (bytes == null) {
            return const CssStylesheet(rules: [], imports: [], warnings: []);
          }
          return _absolutizeSheet(
            CssParser.parse(utf8.decode(bytes, allowMalformed: true)),
            p.posix.dirname(url),
          );
        });
        for (final imported in sheet.imports) {
          final media = imported.media?.toLowerCase() ?? '';
          if (media.contains('print') || media.contains('speech')) {
            continue;
          }
          final target =
              document.resources.resolve(
                imported.url,
                baseDir: p.posix.dirname(url),
              ) ??
              imported.url;
          loadSheet(target, depth: depth + 1);
        }
        sheets.add(sheet);
      }

      for (final href in inline.links) {
        final url =
            document.resources.resolve(href, baseDir: chapterBase) ?? href;
        loadSheet(url);
      }
      if (inline.css.isNotEmpty) {
        sheets.add(_absolutizeSheet(CssParser.parse(inline.css), chapterBase));
      }
      return sheets;
    });
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
    CssWhiteSpace whiteSpace,
  ) {
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

  /// 取块排版用的文本节点：pre 族块换成保留原文的同一节点，其余块沿用
  /// 聚合器已折叠的文本（行为与改动前完全一致）。
  TextBlockNode _textNodeFor(
    int spineIndex,
    TextBlockNode node,
    CssWhiteSpace whiteSpace,
  ) {
    if (whiteSpace != CssWhiteSpace.pre &&
        whiteSpace != CssWhiteSpace.preWrap &&
        whiteSpace != CssWhiteSpace.preLine) {
      return node;
    }
    if (node is! TextContentNode) {
      return node;
    }
    final texts = _preservedTexts(spineIndex, whiteSpace);
    return texts['${node.start}:${node.end}'] ?? node;
  }

  /// 相对 URL 需要解析的属性（P9-03）：背景图与列表标记图。
  static const _urlProperties = <String>{
    'background-image',
    'background',
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
      if (property.isNotEmpty && value.isNotEmpty && !property.startsWith('-')) {
        result.add(
          CssDeclaration(property: property, value: value, important: important),
        );
      }
    }
    return result;
  }

  /// 伪元素生成内容（P8-09）：作者规则 `X::before/::after { content: … }`
  /// 的主选择器 X 匹配链末元素时返回 content 值——字符串字面量或
  /// attr(name)；计数器/open-quote 等返回 null（记录为不支持）。
  static String? _pseudoContent(
    List<CssStylesheet> sheets,
    List<SelectorElement> ancestors,
    String pseudo,
  ) {
    if (ancestors.isEmpty) {
      return null;
    }
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
          if (parsed.selectors.isEmpty) {
            continue;
          }
          var matched = false;
          for (final complex in parsed.selectors) {
            if (complex.matches(ancestors.last, ancestors.sublist(0, ancestors.length - 1))) {
              matched = true;
              break;
            }
          }
          if (!matched) {
            continue;
          }
          for (final declaration in rule.declarations) {
            if (declaration.property != 'content') {
              continue;
            }
            final value = declaration.value.trim();
            final quote = value.isNotEmpty ? value[0] : '';
            final isQuoted =
                (quote == '"' || quote == "'") &&
                value.length >= 2 &&
                value.endsWith(quote);
            if (isQuoted) {
              return value.substring(1, value.length - 1);
            }
            final attrMatch = RegExp(
              r'^attr\(\s*([a-zA-Z-]+)\s*\)$',
            ).firstMatch(value);
            if (attrMatch != null) {
              return ancestors.last.attributes[attrMatch.group(1)!] ?? '';
            }
            return null;
          }
        }
      }
    }
    return null;
  }

  /// ::first-letter（P8-09）：命中规则的声明合成首字符 run（字号/
  /// 颜色/字重放大），借用行内 run 机制排版（行高随之撑起）。
  StyledRun? _firstLetterRun(
    List<CssStylesheet> sheets,
    List<SelectorElement> ancestors,
    String text,
    ComputedStyle baseStyle,
  ) {
    if (ancestors.isEmpty || text.isEmpty) {
      return null;
    }
    final declarations = <String, String>{};
    for (final sheet in sheets) {
      for (final rule in sheet.rules) {
        for (final raw in rule.selector.split(',')) {
          final selector = raw.trim();
          if (!selector.endsWith('::first-letter')) {
            continue;
          }
          final main = selector.substring(
            0,
            selector.length - '::first-letter'.length,
          );
          if (main.isEmpty) {
            continue;
          }
          final parsed = SelectorParser.parse(main);
          if (parsed.selectors.isEmpty) {
            continue;
          }
          var matched = false;
          for (final complex in parsed.selectors) {
            if (complex.matches(
              ancestors.last,
              ancestors.sublist(0, ancestors.length - 1),
            )) {
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
      }
    }
    if (declarations.isEmpty) {
      return null;
    }
    // 首字符 = 首个非空白字符。
    var start = 0;
    while (start < text.length &&
        _isWhitespace(text.codeUnitAt(start))) {
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
      codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x0A ||
      codeUnit == 0x0D;

  static String _chainKey(List<SelectorElement> chain) {
    final parts = <String>[];
    for (final view in chain) {
      final attrKeys = view.attributes.keys.toList()..sort();
      final attrs = [
        for (final key in attrKeys) '$key=${view.attributes[key]}',
      ].join(';');
      parts.add('${view.tag}|$attrs');
    }
    return parts.join('>');
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
  static const _headingTags = <String>{
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  };
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
  }) {
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

  /// 章节纯文本缓存（轻量提取结果）。
  final Map<int, String> _plainTextCache = <int, String>{};

  /// 章节纯文本：扫描式全文搜索用。
  ///
  /// 走「原始 XHTML → 剥标签」的轻量路径，跳过完整解析与排版（156MB 全书
  /// 约 2 秒 → 数百毫秒）。文本细节与排版结果可能有差异，所以搜索命中后要按
  /// 块级文本重新校验偏移，不能直接拿它算 CFI。
  String chapterPlainText(int spineIndex) {
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
    final doubleQuoted = RegExp(
      '(?:^|\\s)$escaped\\s*=\\s*"([^"]*)"',
    ).firstMatch(tag);
    if (doubleQuoted != null) {
      return doubleQuoted.group(1);
    }
    return RegExp(
      "(?:^|\\s)$escaped\\s*=\\s*'([^']*)'",
    ).firstMatch(tag)?.group(1);
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

  /// 浮动感知分页（flat 管线接入，引擎 FloatOccupancy 区间模型）：
  /// - 浮动图不占流高，按侧登记占位，覆盖切片渲染（overlay/absoluteTop）；
  /// - 文本按「同占位状态」行批切段——窄幅区间重测（行内样式区间不
  ///   映射，记录为已知限制），区间外回全宽；
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

    /// 浮动排布（CSS 2.1 §9.5.1）：同一行还有空位就并排——左浮动贴已有
    /// 左浮动的右缘、右浮动贴已有右浮动的左缘；放不下就落到该侧浮动底边
    /// 另起一行。多列网格（双列目录）靠这条把同宽浮块两两并排。
    ({double top, double x}) placeFloat({
      required double preferredTop,
      required double occupiedWidth,
      required double heightPx,
      required FloatSide side,
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
        final leftUsed = occupancy.occupiedLeftAt(top, top + heightPx);
        final rightUsed = occupancy.occupiedRightAt(
          top,
          top + heightPx,
          width,
        );
        if (leftUsed + rightUsed + occupiedWidth <= width + 0.5) {
          final x = side == FloatSide.left
              ? leftUsed
              : width - rightUsed - occupiedWidth;
          return (top: top, x: math.max(0.0, x));
        }
      }
      // 所有行位都放不下：落到该侧浮动底边另起一行。
      return (
        top: math.max(preferredTop, occupancy.maxBottom(side)),
        x: 0,
      );
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
              ? math.min(first.layout.maxWidth, width)
              : first.layout.width;
          final groupBorderW = math.min(width, groupContentW + groupInsetX);
          final groupMarginLeft = groupStyle?.margin.left ?? 0;
          final groupMarginRight = groupStyle?.margin.right ?? 0;
          final groupLeftSpace = floatSide == FloatSide.left
              ? groupMarginLeft
              : groupMarginLeft;
          final groupRightSpace = groupMarginRight;
          final groupOccupied = math.min(
            width,
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
              : nextFlowLeading[blockIndex];
          if (y > 0 &&
              groupFlowTop +
                      groupMarginTop +
                      groupBorderHeight +
                      groupMarginBottom >
                  height) {
            closePage();
          }
          final groupPlacement = placeFloat(
            preferredTop:
                (hasFlowOnPage
                    ? lastContentBottom + lastBottomMargin
                    : nextFlowLeading[blockIndex]) +
                groupMarginTop,
            occupiedWidth: groupOccupied,
            heightPx: groupBorderHeight + groupMarginBottom,
            side: floatSide,
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
            ? math.min(block.layout.maxWidth, width)
            : block.layout.width;
        final borderW = math.min(width, contentW + insetX);
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
        final occupied = math.min(width, leftSpace + borderW + rightSpace);
        // 静态位置 = 当前流位置（上一个在流块的内容底边 + 它的下外边距；
        // 页首无在流块时用下一个在流块的段前距），再叠加自身 margin-top
        //（浮动的 margin 不参与折叠，原样相加）。
        double flowPosition() => hasFlowOnPage
            ? lastContentBottom + lastBottomMargin
            : nextFlowLeading[blockIndex];
        final preferredTop = flowPosition() + block.spaceBefore;
        if (y > 0 && preferredTop + h > height) {
          closePage();
        }
        final placement = placeFloat(
          preferredTop: hasFlowOnPage
              ? lastContentBottom + lastBottomMargin + block.spaceBefore
              : nextFlowLeading[blockIndex] + block.spaceBefore,
          occupiedWidth: occupied,
          heightPx: h,
          side: floatSide,
        );
        final occupiedX = placement.x;
        final boxX = occupiedX + leftSpace;
        final floatY = placement.top;
        occupancy.insert(
          BoxOccupied(
            rect: Rect.fromLTWH(occupiedX, floatY, occupied, h),
            baseline: floatY,
            side: floatSide,
          ),
        );
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: 0,
            endLine: block.layout.lineCount,
            height: h,
            overlay: true,
            absoluteTop: floatY,
            // 绘制层会在 leftInset 之上再加一次 margin.left，浮动框定位
            // 用的是边框盒左缘，这里先把外边距扣掉（否则右浮动整体右移）。
            leftInset: math.max(0.0, boxX - marginLeft),
          ),
        );
        continue;
      }
      if (block.layout.lineCount == 0) {
        // 空盒块（hr 等）：按普通流处理。
        if (y + block.leadingExtent + block.height > height && y > 0) {
          closePage();
        }
        y += block.leadingExtent + block.height + block.trailingExtent;
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
            style: block.style,
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
      // 表格块/空布局块（浮动章节）：整块原子入流。表格的逐行切分在
      // collectTable 里已完成，这里只按块高占位——否则会被当成空文本块
      // 静默丢掉（浮动章里的表格直接消失），空文本块还会让收页循环空转。
      if (block.table != null || block.layout.text.isEmpty) {
        if (y > 0 && y + block.leadingExtent + block.height > height) {
          closePage();
        }
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: 0,
            endLine: block.layout.lineCount,
            height: block.leadingExtent + block.height + block.trailingExtent,
            leadingExtent: block.leadingExtent,
            trailingExtent: block.trailingExtent,
            leftInset: block.leftInset,
          ),
        );
        noteFlow(
          y + block.leadingExtent + block.height,
          block.style?.margin.bottom ?? block.spaceAfter,
        );
        y += block.leadingExtent + block.height + block.trailingExtent;
        continue;
      }
      // 声明盒高块（height/min-height/overflow 裁剪）：浮动流里按原子块
      // 处理。逐行批切段会按行高重建切片高，把盒内留白/裁剪全丢掉
      //（`.ov{height:40px}` 曾按 3 行 75px 占位）。
      final boxHeight = block.height;
      if ((boxHeight - block.measuredHeight).abs() > 0.5 ||
          block.clipsContent) {
        final available = _textWidthFor(block.style ?? style);
        final occupiedLeft = occupancy.occupiedLeftAt(y, y + boxHeight);
        final occupiedRight = occupancy.occupiedRightAt(
          y,
          y + boxHeight,
          width,
        );
        final narrowed = occupiedLeft > 0 || occupiedRight > 0;
        final batchWidth = narrowed
            ? math.max(24.0, available - occupiedLeft - occupiedRight)
            : available;
        final measured = _layoutCache.layout(
          text: block.layout.text,
          style: block.style ?? style,
          maxWidth: batchWidth,
        );
        // 行数不按盒高裁剪：浏览器 overflow 默认 visible，元素矩形高是
        // 声明盒高、但行矩形照样列出盒外内容（对照口径）。盒高只决定
        // 流内占位高度，绘制裁剪由绘制层按 clipsContent 决定。
        final taken = measured.lineCount;
        final visibleHeight = measured.height;
        if (y > 0 && y + block.leadingExtent + boxHeight > height) {
          closePage();
        }
        if (taken > 0) {
          final segLines = measured.lines.take(taken).toList();
          final segText = block.layout.text.substring(0, segLines.last.end);
          final segLayout = TextLayoutResult(
            text: segText,
            lines: segLines,
            width: batchWidth,
            height: visibleHeight,
            maxWidth: batchWidth,
            runs: const <StyledRun>[],
          );
          final leftInset = narrowed ? occupiedLeft : block.leftInset;
          slices.add(
            PageBlockSlice(
              block: PageBlock(
                layout: segLayout,
                style: block.style,
                startCfi: block.startCfi,
                leftInset: leftInset,
                topInset: block.topInset,
                bottomInset: block.bottomInset,
                declaredContentHeight: boxHeight,
              ),
              startLine: 0,
              endLine: taken,
              height: block.leadingExtent + boxHeight,
              leadingExtent: block.leadingExtent,
              trailingExtent: block.trailingExtent,
              leftInset: leftInset,
            ),
          );
        }
        noteFlow(
          y + block.leadingExtent + boxHeight,
          block.style?.margin.bottom ?? block.spaceAfter,
        );
        y += block.leadingExtent + boxHeight + block.trailingExtent;
        continue;
      }
      // 行批切段（f）：一个源块只产出一个 PageBlock，绕排只改变行的起始
      // x（写进 LineBox.offsetX）。此前按「同占位状态」把段落切成多个块，
      // 块的宽度/行数于是对不上浏览器的「一个 <p> 一个块」。
      final fullText = block.layout.text;
      final available = _textWidthFor(block.style ?? style);
      var charCursor = 0;
      var leadingLeft = block.leadingExtent;
      while (charCursor < fullText.length) {
        final blockLines = <LineBox>[];
        var blockHeight = 0.0;
        while (charCursor < fullText.length) {
          final probe = block.layout.lines.first.height;
          final lineY = y + leadingLeft + blockHeight;
          final occupiedLeft = occupancy.occupiedLeftAt(lineY, lineY + probe);
          final occupiedRight = occupancy.occupiedRightAt(
            lineY,
            lineY + probe,
            width,
          );
          final narrowed = occupiedLeft > 0 || occupiedRight > 0;
          final batchWidth = narrowed
              ? math.max(24.0, available - occupiedLeft - occupiedRight)
              : available;
          final remaining = fullText.substring(charCursor);
          final measured = _layoutCache.layout(
            text: remaining,
            style: block.style ?? style,
            maxWidth: batchWidth,
          );
          // 取行：直到占位状态变化（下一行的区间不同）、页尽或文本尽。
          var taken = 0;
          var batchHeight = 0.0;
          while (taken < measured.lineCount) {
            final lineH = measured.lines[taken].height;
            if (y + leadingLeft + blockHeight + batchHeight + lineH > height) {
              break;
            }
            final nextY = y + leadingLeft + blockHeight + batchHeight;
            final nextLeft = occupancy.occupiedLeftAt(nextY, nextY + lineH);
            final nextRight = occupancy.occupiedRightAt(
              nextY,
              nextY + lineH,
              width,
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
              ),
            );
          }
          blockHeight += batchHeight;
          charCursor += measured.lines[taken - 1].end;
        }
        if (blockLines.isEmpty) {
          // 页首也放不下任何一行：收页重试（此时必然 y > 0）。
          closePage();
          leadingLeft = 0;
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
        );
        final trailing = finished ? block.trailingExtent : 0.0;
        slices.add(
          PageBlockSlice(
            block: PageBlock(
              layout: segLayout,
              style: block.style,
              startCfi: block.startCfi,
              leftInset: block.leftInset,
              topInset: block.topInset,
              bottomInset: block.bottomInset,
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
        leadingLeft = 0;
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
    var pages = await _loadChapterPages(spineIndex);
    final background = _pageBackgrounds[spineIndex];
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

  /// 分页主体：产物不带整页背景，由 [loadChapter] 统一贴上。
  Future<List<PageContent>> _loadChapterPages(int spineIndex) async {
    final trace = readerTraceEnabled ? ReaderTrace.instance : null;
    final traceBook = bookIdForTrace;
    final watch = trace == null ? null : (Stopwatch()..start());
    final paginationKey = _paginationKey(spineIndex);
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
    // 满屏图页（P3-10，§8.6）：单图无正文无宽高属性 → 整页单块、
    // 多看全屏页（OPF `duokan-page-*`）：封面/插图整页铺满，正文样式
    // 不参与——body 的 padding/字号不会把封面裁小。`fitwindow` 用
    // contain 上下居中，其余全屏页 cover 铺满。
    final pageFlags = chapterPageFlags(spineIndex);
    if (pageFlags.isFullPage) {
      final singleImage = fullBleedAnalysis(spineIndex).singleImageSrc;
      if (singleImage != null && singleImage.isNotEmpty) {
        // 铺法（R4 回归修正）：全屏页默认 **contain**（等比完整显示、页内
        // 居中、允许留白）——强上 cover 会把 SVG 封面/插图裁掉（zhushen
        // 封面是 `<image xMidYMid meet>`，像素差 97%）。只有「声明
        // fullscreen 且图片宽高比与页面比差 <2%」这种几乎无损的情形才
        // 用 cover 填满；`duokan-page-fitwindow` 一律 contain。
        final imageUrl = _chapterImageUrl(spineIndex, singleImage);
        final intrinsic = _intrinsicSizeOfUrl(imageUrl);
        final pageRatio = baseContentWidth / math.max(1.0, baseContentHeight);
        final imageRatio = intrinsic == null
            ? pageRatio
            : intrinsic.width / math.max(1.0, intrinsic.height);
        final closeRatio =
            (imageRatio - pageRatio).abs() <= pageRatio * 0.02;
        final useCover =
            pageFlags.fullScreen && !pageFlags.fitWindow && closeRatio;
        final pages = _buildFullBleedPages(
          spineIndex,
          singleImage,
          paginationKey,
          contain: !useCover,
          bleed: true,
        );
        _putPageCache(paginationKey, pages);
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
      _putPageCache(paginationKey, pages);
      if (trace != null) {
        trace.record(
          ReaderTraceName.chapterLayout,
          watch!.elapsedMicroseconds,
          bookId: traceBook,
        );
      }
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
    // 可变：collect 之后按 CSS 相邻兄弟折叠上下边距，再交给分页。
    var blocks = <PageBlock>[];
    // `position: fixed`（W18）：相对页面定位、每页重复——不进流，分页完成
    // 后给每一页追加覆盖切片。
    final fixedBlocks = <PageBlock>[];

    // 块级样式（P8-02 链式级联）：UA（uaRules）+ 作者样式表（私有钩子
    // 契约过滤）+ 内联 style 三源进 Cascade.compute——特异性/!important/
    // @media/继承（18 项继承表）全部由引擎处理；flat 管线只补盒类近似
    // 传导与引用深度。前缀缓存：同容器兄弟块共享祖先计算结果。
    final sheets = _chapterStylesheets(spineIndex);
    await _ensureBookFonts(sheets);
    // 书内 @font-face 的族名改写（P0）：注册后把作者声明里的书内字族换成
    // 引擎族名 `bi_<bookId>_<族>`，改写在级联之前，块样式与行内 run 样式
    // 都自然拿到引擎族名。
    final styledSheets = _rewriteBookFontSheets(sheets);
    final cascadeRules = <CascadeRule>[
      // 列表缩进改由列表容器的级联盒计算（g）：UA 里的近似
      // `li { margin-left: 40px }` 会盖掉作者 `ul { padding-left: 28px }`，
      // 且重复叠加，这里整条跳过（其他 UA 规则照旧）。
      for (final rule in uaRules())
        if (!_isUaListIndentRule(rule.rule)) rule,
      for (var i = 0; i < styledSheets.length; i++)
        ...CascadeRule.fromStylesheet(
          styledSheets[i],
          origin: CascadeOrigin.author,
          startOrder: 1000 + i * 10000,
        ),
    ];
    final chainStyleCache = <String, ComputedStyle>{};
    var figureSeq = 0;
    // P9-25：最近一次 styleForChain 的最近容器是否带可见边框。局部状态，
    // 调用后立刻读取，避免为同一链再跑一次级联。
    var containerBorderedForLastChain = false;
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
      final key = _chainKey(chain);
      return chainStyleCache.putIfAbsent(key, () {
        final parent = chain.length > 1
            ? chainStyle(chain.sublist(0, chain.length - 1))
            : style;
        return Cascade.compute(
          element: chain.last,
          ancestors: chain.sublist(0, chain.length - 1),
          rules: cascadeRules,
          inlineDeclarations: _rewriteBookFontDeclarations(
            _inlineDeclarationsOf(chain.last.attributes['style']),
          ),
          parent: parent,
          rootFontSize: style.fontSize,
          containingWidth: contentWidth,
        );
      });
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
    if (bodyBackground != null) {
      _pageBackgrounds[spineIndex] = bodyBackground;
    } else {
      _pageBackgrounds.remove(spineIndex);
    }

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
      final isSymbol =
          marker == '•' || marker == '○' || marker == '▪';
      final advance = isSymbol
          ? style.fontSize * symbolAdvanceEm
          : _layoutCache
                .layout(
                  text: marker,
                  style: style,
                  maxWidth: contentWidth,
                )
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
      required List<SelectorElement> ancestors,
    }) {
      if (text.isEmpty || marks.isEmpty) {
        return null;
      }
      ComputedStyle styleForInlineMark(InlineMark mark) {
        final views = <SelectorElement>[
          for (final subject in mark.chain.take(mark.chain.length - 1))
            _NodeView(
              subject.tag.toLowerCase(),
              <String, String>{'class': subject.classes.join(' ')},
              const <SelectorElement>[],
            ),
          _NodeView(
            mark.tag.toLowerCase(),
            <String, String>{'class': mark.classes.join(' ')},
            const <SelectorElement>[],
          ),
        ];
        return chainStyle(<SelectorElement>[...ancestors, ...views]);
      }

      for (final mark in marks) {
        if (mark.chain.isEmpty || mark.end <= mark.start) {
          continue;
        }
        // 图片标记（占位符）交给下面的图片分支处理，避免把 U+FFFC 当成
        // 文本浮动块（占位符宽 1em，图片会缩成 16px）。
        final markTag = mark.tag.toLowerCase();
        if (markTag == 'img' || markTag == 'image') {
          continue;
        }
        final inlineStyle = styleForInlineMark(mark);
        final side = _floatSideOfStyle(inlineStyle);
        // `display: inline-block`：盒子交给行排版（T1 的 InlineBoxSpec），
        // 宽高含 padding/border，整块不跨行、放不下换行。
        // 只有声明了宽/高的 inline-block 才当行内盒处理：没有尺寸的行内
        // 块（chip/tag 之类）继续走行内 run 的背景+边框近似绘制（P9-24），
        // 否则会退化成「只画盒不画字」。
        final inlineBlock =
            side == null &&
            inlineStyle.display == CssDisplay.inlineBlock &&
            (inlineStyle.width != null || inlineStyle.height != null);
        if (side == null && !inlineBlock) {
          continue;
        }
        final content = text.substring(mark.start, mark.end).trim();
        if (content.isEmpty) {
          continue;
        }
        final contentWidthLimit = _textWidthFor(inlineStyle);
        var layout = _layoutCache.layout(
          text: content,
          style: inlineStyle,
          maxWidth: contentWidthLimit,
        );
        PageBlock? floatBlock;
        InlineBoxSpec? boxSpec;
        if (inlineBlock) {
          // 行内盒：宽高含 padding/border（CSS inline-block 的盒尺寸），
          // 内容按自身内容宽排版；payload 交给绘制层画盒内内容。
          final model = BoxModel.fromStyle(
            inlineStyle,
            containingWidth: contentWidth,
          );
          final contentHeightValue =
              inlineStyle.height?.resolve(contentHeight) ?? layout.height;
          boxSpec = InlineBoxSpec(
            offset: mark.start,
            width: (inlineStyle.width?.resolve(contentWidth) ?? layout.width) +
                model.padding.horizontal +
                model.borders.left +
                model.borders.right,
            height: contentHeightValue +
                model.padding.vertical +
                model.borders.top +
                model.borders.bottom,
            verticalAlign: inlineBoxAlignOf(inlineStyle.verticalAlign),
            marginTop: inlineStyle.margin.top,
            marginBottom: inlineStyle.margin.bottom,
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
            layout = TextLayoutResult(
              text: layout.text,
              lines: layout.lines,
              width: layout.width,
              height: layout.height,
              maxWidth: layout.width,
              runs: layout.runs,
            );
          }
          floatBlock = _floatedTextBlock(
            layout: layout,
            style: inlineStyle,
            side: side!,
            spaceBefore: inlineStyle.margin.top,
            spaceAfter: inlineStyle.margin.bottom,
          );
        }
        // 从段落文本里摘掉这段内容（连同相邻的一个空格），其余偏移重映射。
        var removeStart = mark.start;
        var removeEnd = mark.end;
        if (removeEnd < text.length && text[removeEnd] == ' ') {
          removeEnd += 1;
        } else if (removeStart > 0 && text[removeStart - 1] == ' ') {
          removeStart -= 1;
        }
        final removed = removeEnd - removeStart;
        final newText = text.substring(0, removeStart) + text.substring(removeEnd);
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
            if (other.end <= removeStart || other.start >= removeEnd)
              InlineMark(
                start: remap(other.start),
                end: remap(other.end),
                tag: other.tag,
                classes: other.classes,
                chain: other.chain,
              ),
        ];
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
                  marginTop: boxSpec.marginTop,
                  marginBottom: boxSpec.marginBottom,
                  baselineOffset: boxSpec.baselineOffset,
                  payload: boxSpec.payload,
                ),
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
        );
        final imageBlockStyle = ComputedStyle(<String, String>{
          ...baseStyle.values,
          'background-image': 'url($url)',
          'background-size': 'contain',
          'background-position': 'center center',
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
        final block = PageBlock(
          layout: layout,
          style: imageBlockStyle,
          floatSide: side,
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
        if (ancestorTag == 'ul' || ancestorTag == 'ol' ||
            ancestorTag == 'li' || ancestorTag == 'body' ||
            ancestorTag == 'html') {
          continue;
        }
        final ancStyle = chainStyle(chain.sublist(0, i + 1));
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
      final declarations = <String, String>{...promoted, ...computed.values};
      if (extraLeft > 0) {
        declarations['margin-left'] = '${computed.margin.left + extraLeft}px';
      }
      if (extraRight > 0) {
        declarations['margin-right'] = '${computed.margin.right + extraRight}px';
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
    List<StyledRun> resolveInlineRuns(List<InlineMark> marks) {
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
        for (final mark in marks) {
          if (mark.start > start || end > mark.end || mark.chain.isEmpty) {
            continue;
          }
          final viewChain = <SelectorElement>[
            for (final subject in mark.chain.take(mark.chain.length - 1))
              _NodeView(
                subject.tag.toLowerCase(),
                <String, String>{'class': subject.classes.join(' ')},
                const <SelectorElement>[],
              ),
            _NodeView(
              mark.tag.toLowerCase(),
              <String, String>{'class': mark.classes.join(' ')},
              const <SelectorElement>[],
            ),
          ];
          final computed = chainStyle(viewChain);
          if (computed.explicitProperties.isEmpty) {
            continue;
          }
          // 内层（后遍历）覆盖外层同名属性。
          resolved = computed;
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

    /// 浮动方向检测（flat 管线接入）：内联 style `float:`、历史 `align`
    /// 属性、作者 CSS class 规则三处来源（P8-02：CSS 规则经引擎级联）。
    FloatSide? floatSideOf(Map<String, String> attributes) {
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
      final view = _NodeView(
        'img',
        <String, String>{
          if (attributes['class'] != null) 'class': attributes['class']!,
        },
        const <SelectorElement>[],
      );
      final imgStyle = chainStyle([view]);
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
      final imageStyle = styleForChain(<SelectorElement>[
        ...foldedChain,
        _NodeView(node.tag, node.attributes, const <SelectorElement>[]),
      ]);
      // 图片块：祖先累计 opacity 同样透传（嵌套容器里的半透明图）。
      final imageOpacity = effectiveOpacityForLastChain;
      // 出血图（P9-22）：显示宽按页面宽（正文宽 + 页边距）计算，
      // 否则横幅只按正文宽缩放，左右留白与多看/阅微不一致。
      final bleed = imageStyle.bleed;
      final pageInsetLeft = _overrides.padding?.left ?? 0;
      final pageInsetRight = _overrides.padding?.right ?? 0;
      final bleedWidth = contentWidth +
          (bleed.left ? pageInsetLeft : 0) +
          (bleed.right ? pageInsetRight : 0);
      var size = _resolveImageDisplaySize(
        node.attributes,
        imageSizes[url],
        bleedWidth,
        contentHeight,
        cssWidth: imageStyle.width?.resolve(bleedWidth),
        cssHeight: imageStyle.height?.resolve(contentHeight),
      );
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
          floatSideOf(node.attributes) ?? containerFloat ?? chainFloat;
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
            width: blockWidth,
          ),
        ],
        width: blockWidth,
        height: size.$2,
        maxWidth: blockWidth,
        runs: const <StyledRun>[],
      );
      blocks.add(
        PageBlock(
          layout: layout,
          style: blockStyle,
          floatSide: floatSide,
          bleedLeft: imageStyle.bleed.left,
          bleedRight: imageStyle.bleed.right,
          effectiveOpacity: imageOpacity,
          groupId: containerFloat != null
              ? containerFloatGroup
              : (chainFloat != null && containerFloatGroup > 0
                    ? containerFloatGroup
                    : 0),
        ),
      );
    }

    /// 表格收集（flat 管线接入）：聚合树 tr/td → 格自然宽/测高闭包 →
    /// 两遍列宽 + 网格 + 行边界切分；每页片产出一个带渲染载荷的块。
    /// 嵌套表/行分组（thead/tbody）按树序展开；caption 暂并入文字流。
    void collectTable(
      BlockNode tableNode,
      List<SelectorElement> ancestors,
    ) {
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
      void walkRows(EpubNode node) {
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
          }
          return;
        }
        if (node.tag == 'td' || node.tag == 'th') {
          return;
        }
        for (final child in node.children) {
          walkRows(child);
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
                maxWidth: contentWidth,
              );
              if (result.lineCount > 0) {
                blocks.add(
                  PageBlock.styled(
                    layout: result,
                    style: cellStyle,
                    containingWidth: contentWidth,
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
            final trimmed = raw.trim();
            if (trimmed.isEmpty) {
              return;
            }
            final leading = raw.length - raw.trimLeft().length;
            if (buffer.isNotEmpty) {
              buffer.write('\n');
            }
            final offset = buffer.length;
            buffer.write(trimmed);
            for (final mark in node.inlineMarks) {
              final start = math.max(0, mark.start - leading);
              final end = math.min(trimmed.length, mark.end - leading);
              if (end <= start) {
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
              ? contentWidth * css.value / 100
              : css.value;
        }
        final raw = attributes['width']?.trim();
        if (raw == null || raw.isEmpty) {
          return null;
        }
        if (raw.endsWith('%')) {
          final percent = double.tryParse(
            raw.substring(0, raw.length - 1),
          );
          return percent == null ? null : contentWidth * percent / 100;
        }
        return double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
      }

      var columnCount = 0;
      for (final row in rows) {
        var count = 0;
        for (final cell in row) {
          count +=
              int.tryParse(cell.attributes['colspan']?.trim() ?? '') ?? 1;
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
        columnSpecified[i] = declaredLength(
          columnStyle,
          column.attributes,
        );
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
      final cellTexts = <List<String>>[];
      final cellRuns = <List<List<StyledRun>>>[];
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
        final row = rows[rowIndex];
        final rowView = _NodeView(
          rowNodes[rowIndex].tag,
          rowNodes[rowIndex].attributes,
          const <SelectorElement>[],
        );
        final styles = <ComputedStyle>[];
        final rowSpecs = <TableCellSpec>[];
        final texts = <String>[];
        final rowRuns = <List<StyledRun>>[];
        for (final cell in row) {
          final cellChain = <SelectorElement>[
            ...tableChain,
            rowView,
            _NodeView(cell.tag, cell.attributes, const <SelectorElement>[]),
          ];
          final cellStyle = styleForChain(cellChain);
          final content = cellContentOf(cell, cellChain);
          final text = content.text;
          final runs = resolveInlineRuns(content.marks);
          rowRuns.add(runs);
          final colspan = int.tryParse(
                cell.attributes['colspan']?.trim() ?? '',
              ) ??
              1;
          // rowspan（a）：跨行格的高度回填与合并矩形都靠它，之前完全
          // 没解析，跨行格按单行高排版。
          final rowspan = int.tryParse(
                cell.attributes['rowspan']?.trim() ?? '',
              ) ??
              1;
          double naturalWidth(double width, ComputedStyle cs) {
            if (text.isEmpty) {
              return 0;
            }
            final measured = _layoutCache.layout(
              text: text,
              style: cs,
              maxWidth: width,
              runs: runs,
            );
            var widest = 0.0;
            for (final line in measured.lines) {
              widest = math.max(widest, line.width);
            }
            return widest + horizontalInset(cs);
          }

          styles.add(cellStyle);
          texts.add(text);
          rowSpecs.add(
            TableCellSpec(
              naturalWidth: naturalWidth(contentWidth, cellStyle),
              colspan: colspan,
              rowspan: rowspan,
              measureHeight: (width) {
                if (text.isEmpty) {
                  return cellStyle.lineHeight * 0.6;
                }
                return _layoutCache
                        .layout(
                          text: text,
                          style: cellStyle,
                          maxWidth: math.max(
                            8.0,
                            width - horizontalInset(cellStyle),
                          ),
                          runs: runs,
                        )
                        .height +
                    verticalInset(cellStyle);
              },
            ),
          );
        }
        cellStyles.add(styles);
        cellTexts.add(texts);
        cellRuns.add(rowRuns);
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
            ? contentWidth * tableWidthPercent.clamp(0.0, 1.0)
            : (tableWidthPx ?? contentWidth);
        target = target.clamp(0.0, contentWidth);
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
          for (var c = insetColumn; c < insetColumn + span && c < columnCount; c += 1) {
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
          final content = (c < columnPercent.length && columnPercent[c] &&
                  contentWidth > 0)
              ? specified * columnSpace / contentWidth
              : specified;
          widths[c] = content + columnInset[c];
          specifiedTotal += widths[c];
        }
        if (autoColumns > 0) {
          final share = math.max(0.0, columnSpace - specifiedTotal) /
              autoColumns;
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
        tableWidthPxFinal = widths.fold(0.0, (sum, width) => sum + width) +
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
            for (var c = column; c < column + colSpan && c < columnCount; c += 1) {
              cellWidth += widths[c];
            }
            column += colSpan;
            if (rowSpan > 1) {
              continue;
            }
            final style = cellStyles[r][i];
            final text = cellTexts[r][i];
            final measuredCell = text.isEmpty
                ? null
                : _layoutCache.layout(
                    text: text,
                    style: style,
                    maxWidth: math.max(
                      8.0,
                      cellWidth - horizontalInset(style),
                    ),
                  );
            final height =
                (measuredCell?.height ?? style.lineHeight * 0.6) +
                verticalInset(style);
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
            final style = cellStyles[r][i];
            final text = cellTexts[r][i];
            final measuredCell = text.isEmpty
                ? null
                : _layoutCache.layout(
                    text: text,
                    style: style,
                    maxWidth: math.max(
                      8.0,
                      cellWidth - horizontalInset(style),
                    ),
                  );
            final height =
                (measuredCell?.height ?? style.lineHeight * 0.6) +
                verticalInset(style);
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
          containerWidth: contentWidth,
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
      // 格终布局（按最终列宽）与渲染格。
      final allCells = <TableCellRender>[];
      for (var r = 0; r < rows.length; r++) {
        for (var c = 0; c < rows[r].length; c++) {
          final rect = grid.cellRectAt(r, c);
          if (rect == null) {
            continue;
          }
          final text = cellTexts[r][c];
          final cellStyle = cellStyles[r][c];
          final layout = text.isEmpty
              ? null
              : _layoutCache.layout(
                  text: text,
                  style: cellStyle,
                  maxWidth: math.max(
                    8.0,
                    rect.rect.width - horizontalInset(cellStyle),
                  ),
                  runs: cellRuns[r][c],
                );
          if (layout == null || layout.lineCount == 0) {
            continue;
          }
          allCells.add(
            TableCellRender(
              row: r,
              rect: rect.rect,
              layout: layout,
              style: cellStyle,
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
      final slices = TablePaginator.paginateRows(
        rowHeights: paddedRowHeights,
        pageHeight: math.max(1.0, contentHeight - spacingY),
      );
      final gridRowYs = grid.rowYs;
      final gridColumnXs = grid.columnXs;
      for (final slice in slices) {
        final sliceTop = gridRowYs[slice.firstRow];
        var sliceHeight = slice.clippedRowHeight > 0
            ? slice.clippedRowHeight
            : slice.drawnHeight;
        // 末段落补上表格底部的最后一份纵向间距。
        if (slice.lastRow >= rowHeights.length) {
          sliceHeight += spacingY;
        }
        final cells = allCells
            .where((cell) =>
                cell.row >= slice.firstRow && cell.row < slice.lastRow)
            .map(
              (cell) => TableCellRender(
                row: cell.row,
                rect: cell.rect.translate(0, -sliceTop),
                layout: cell.layout,
                style: cell.style,
              ),
            )
            .toList();
        blocks.add(
          PageBlock.styled(
            style: tableStyle,
            containingWidth: contentWidth,
            // P9-25：带边框容器内的表格块同样参与背景/边框拼合。
            containerSides: tableInBorderedContainer,
            effectiveOpacity: tableOpacity,
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
                for (var r = slice.firstRow; r <= slice.lastRow; r++)
                  gridRowYs[r] - sliceTop,
                if (slice.clippedRowHeight > 0)
                  slice.clippedRowHeight,
              ],
              tableWidth: tableWidthPxFinal,
            ),
          ),
        );
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
        final isRelative =
            relativeProbe.position == CssPosition.relative;
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
        final textNode = _textNodeFor(spineIndex, node, blockStyle.whiteSpace);
        final text = textNode.text;
        if (text.trim().isEmpty) {
          return;
        }
        // 伪元素生成内容（P8-09）：::before/::after 的 content（字符串/
        // attr()）拼进块首尾（flat 近似：CFI 偏移不含生成文本，记录）。
        final before = _pseudoContent(styledSheets, ancestors, '::before');
        final after = _pseudoContent(styledSheets, ancestors, '::after');
        final effectiveText =
            (before == null && after == null) || textNode is! TextContentNode
            ? text
            : '${before ?? ''}$text${after ?? ''}';
        // 阅读器排版覆盖（reader origin 高于 author）：字号/行高/对齐作用
        // 在级联结果之上，否则作者 p{font-size;line-height} 会让设置失效。
        // 标题不参与——标题字号/行高继续跟随书籍样式族。
        if (!isHeading) {
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
        final paragraphSpacing = isHeading || tag == 'li'
            ? null
            : overrides.paragraphSpacing;
        // 列表标记（P3-23）：每个 li 一项标记，只挂在该项首个文本块上
        //（li 内多段时不能重复编号）。
        String? marker;
        if (isListItem && list.markerPending) {
          list.markerPending = false;
          final markerText = list.nextMarker(blockStyle.listStyleType);
          marker = markerText.isEmpty ? null : markerText;
        }
        // `list-style-position: inside`（g）：标记并入首行，首行让出
        // 「标记宽 + 间隙」；outside 保持整行宽度（标记画在内容框外）。
        // 该属性在 CSS 里继承，li 自己声明时优先，否则取列表容器的值。
        final markerInside = blockStyle.values.containsKey(
          'list-style-position',
        )
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
        final listSpacingBefore =
            isListItem && listFirst ? list.spaceBefore : 0.0;
        final listSpacingAfter = isListItem && listLast ? list.spaceAfter : 0.0;
        // 行内样式区间（P8-02）：聚合标记链 → 引擎级联 → StyledRun 混排；
        // ::first-letter（P8-09）：命中规则时首字符放大 run 追加。
        // 行内元素浮动（W17）：段落首/尾的行内浮动元素（span 标签、
        // img 头像）摘出来单独成块，段落剩余文本按行 offsetX 绕排。
        // 段落自身是浮动块时不做（避免嵌套浮动互相干扰）。
        final paragraphIsFloat =
            _floatSideOfStyle(blockStyle) != null || containerFloat != null;
        final inlineFloats = <PageBlock>[];
        var inlineBoxes = <InlineBoxSpec>[];
        var paragraphText = effectiveText;
        var paragraphMarks = textNode is TextContentNode
            ? textNode.inlineMarks
            : const <InlineMark>[];
        var paragraphImages = textNode is TextContentNode
            ? textNode.inlineImages
            : const <InlineImageMark>[];
        if (!paragraphIsFloat && textNode is TextContentNode) {
          // 一段里可能有多个行内浮动（如职业标签 + 天赋标签），逐个摘出。
          for (var guard = 0; guard < 8; guard += 1) {
            final extracted = extractInlineFloat(
              text: paragraphText,
              marks: paragraphMarks,
              images: paragraphImages,
              ancestors: ancestors,
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
              // 已有 spec 的偏移随文本摘除重映射，再按偏移升序入列。
              final removedBefore = extracted.removeEnd - extracted.removeStart;
              inlineBoxes = <InlineBoxSpec>[
                for (final existing in inlineBoxes)
                  InlineBoxSpec(
                    offset: existing.offset <= extracted.removeStart
                        ? existing.offset
                        : math.max(
                            extracted.removeStart,
                            existing.offset - removedBefore,
                          ),
                    width: existing.width,
                    height: existing.height,
                    verticalAlign: existing.verticalAlign,
                    marginTop: existing.marginTop,
                    marginBottom: existing.marginBottom,
                    baselineOffset: existing.baselineOffset,
                    payload: existing.payload,
                  ),
                box,
              ]..sort((a, b) => a.offset.compareTo(b.offset));
            }
            paragraphText = extracted.text;
            paragraphMarks = extracted.marks;
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
        var runs = resolveInlineRuns(paragraphMarks);
        // 行内图片（P9-06）：占位符 → 书内图片路径 + 书籍 CSS 尺寸。
        final inlineImages = <InlineImageSpec>[];
        if (paragraphImages.isNotEmpty) {
          final shift = (before ?? '').length;
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
            final imageStyle = styleForChain(<SelectorElement>[
              ...ancestors,
              _NodeView(
                mark.node.tag,
                attributesForImage,
                const <SelectorElement>[],
              ),
            ]);
            final rawOffset = mark.offset + shift;
            inlineImages.add(
              InlineImageSpec(
                offset: rawOffset,
                url: url,
                width: imageStyle.width?.resolve(contentWidth),
                height: imageStyle.height?.resolve(contentWidth),
              ),
            );
          }
        }
        final firstLetter = _firstLetterRun(
          styledSheets,
          ancestors,
          paragraphText,
          blockStyle,
        );
        if (firstLetter != null) {
          runs = [...runs, firstLetter];
        }
        // 浮动块（f/W12）：`float` 走级联后的计算样式；容器上的 float
        //（如双列目录 `.dk-toc-item`）经传导带给子块，子块按容器内容宽
        // 排版并整体进同一个浮动盒。
        final ownFloatSide = _floatSideOfStyle(blockStyle);
        final floatSide = ownFloatSide ?? containerFloat;
        // 容器浮动传导来的宽度优先（容器里可能有多个子块）。
        final measureWidth = ownFloatSide == null && containerFloat != null
            ? containerFloatWidth ?? _textWidthFor(measureStyle)
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
              )
            : TextLayoutEngine.layout(
                text: paragraphText,
                style: measureStyle,
                maxWidth: measureWidth,
                runs: runs,
                inlineBoxes: inlineBoxes,
              );
        if (outOfFlowBoxWidth != null) {
          layout = TextLayoutResult(
            text: layout.text,
            lines: layout.lines,
            width: outOfFlowBoxWidth,
            height: layout.height,
            maxWidth: outOfFlowBoxWidth,
            runs: layout.runs,
          );
        }
        // 竖排（W19）：行排版层给出的 `layout.width` 是**列带总宽**
        //（列数 × 列宽），块的内容宽就取它——沿用整页宽
        //（`layout.maxWidth`）会让块盒比浏览器宽一截（35-writing-mode）。
        if (measureStyle.writingMode != CssWritingMode.horizontalTb &&
            layout.width.isFinite &&
            layout.width > 0 &&
            layout.width != layout.maxWidth) {
          layout = TextLayoutResult(
            text: layout.text,
            lines: layout.lines,
            width: layout.width,
            height: layout.height,
            maxWidth: layout.width,
            runs: layout.runs,
          );
        }
        if (inlineFloats.isNotEmpty) {
          // 浮动块排在段落之前：分页时它们先占位，段落行按剩余宽度收窄。
          blocks.addAll(inlineFloats);
        }
        if (layout.lineCount > 0) {
          final incomingShift = pendingRelativeTop;
          pendingRelativeTop = 0;
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
                startCfi: cfi,
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
            startCfi: cfi,
            groupId: groupId,
            listMarker: marker,
              // 块级上下边距进分页几何（含负值）：作者/UA margin 生效，
              // 阅读器段距设置优先；相邻段在分页层折叠取大
              //（PageBlock.collapseAdjacentMargins）。列表项另加容器段距。
              spaceBefore: spaceBefore,
              spaceAfter: spaceAfter,
              // P8-08：注音标注透传渲染层。
              rubies: textNode is TextContentNode && textNode.rubies.isNotEmpty
                  ? [
                      for (final ruby in textNode.rubies)
                        RubyAnnotation(
                          start: ruby.start,
                          end: ruby.end,
                          text: ruby.text,
                        ),
                    ]
                  : null,
              // P9-06：行内图片（U+FFFC 占位）透传给绘制层。
              inlineImages: inlineImages,
              // P9-19：绝对定位块（不占流高，绘制在页内绝对坐标）。
              absolute: isOutOfFlow,
              absoluteTop: absoluteTop,
              absoluteLeft: absoluteLeft,
              // P9-22：多看出血（背景/边框延伸到页面边缘）。
              bleedLeft: blockStyle.bleed.left,
              bleedRight: blockStyle.bleed.right,
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
              groupId: textBlock.groupId,
              listMarker: textBlock.listMarker,
              rubies: textBlock.rubies,
              inlineImages: textBlock.inlineImages,
              absolute: textBlock.absolute,
              absoluteTop: textBlock.absoluteTop,
              absoluteLeft: textBlock.absoluteLeft,
              bleedLeft: textBlock.bleedLeft,
              bleedRight: textBlock.bleedRight,
              containerSides: textBlock.containerSides,
              effectiveOpacity: textBlock.effectiveOpacity,
              declaredContentHeight: textBlock.declaredContentHeight,
            );
            if (relativeTop != 0) {
              pendingRelativeTop += relativeTop;
            }
          }
          if (isFixed) {
            // 固定定位块每页重复，分页后再逐页追加（见 _withFixedOverlays）。
            fixedBlocks.add(textBlock);
          } else {
            blocks.add(textBlock);
          }
        }
      } else if (node is BlockNode) {
        // display:none 容器子树剔除（P8-07，WHATWG 15.3.1 语义）：容器
        // 自身样式为 none 时整棵子树不产出（含 [hidden]/input[type=
        // hidden]/dialog:not([open]) 等经级联命中的形态）。
        if (chainStyle(<SelectorElement>[
          ...ancestors,
          _NodeView(node.tag, node.attributes, const <SelectorElement>[]),
        ]).display == CssDisplay.none) {
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
          collectTable(node, ancestors);
          return;
        }
        // 分隔线 hr：空行块 + 下边框（绘制层 _paintBorders 画线）。
        if (node.tag == 'hr' && node.children.isEmpty) {
          final hrStyle = ComputedStyle(<String, String>{
            ...UaBlockDefaults.declarationsFor('hr'),
            'border-bottom': '1px solid #B0B0B0',
          }, parent: style, explicitProperties: <String>{
            ...UaBlockDefaults.declarationsFor('hr').keys,
            'border-bottom',
          }, rootFontSize: style.fontSize);
          blocks.add(
            PageBlock.styled(
              layout: TextLayoutResult(
                text: '',
                lines: [
                  LineBox(
                    start: 0,
                    end: 0,
                    top: 0,
                    height: 1,
                    baseline: 1,
                    width: contentWidth,
                  ),
                ],
                width: contentWidth,
                height: 1,
                maxWidth: contentWidth,
                runs: const <StyledRun>[],
              ),
              style: hrStyle,
              containingWidth: contentWidth,
            ),
          );
          return;
        }
        // 整组不可切（P7-26）：figure（图+题注）内的块标记同组。
        var childGroup = groupId;
        if (node.tag == 'figure') {
          figureSeq += 1;
          childGroup = figureSeq;
        }
        // 引用深度（M2）：blockquote 每层 +1，容器左右边距叠加到子块。
        final childQuoteDepth =
            node.tag == 'blockquote' ? quoteDepth + 1 : quoteDepth;
        // 祖先链（P8-02）：块级元素入链（含兄弟池视图），选择器匹配用。
        final childViews = <SelectorElement>[
          for (final child in node.children)
            if (child is BlockNode)
              _NodeView(child.tag, child.attributes, const <SelectorElement>[])
            else if (child is InlineNode)
              _NodeView(child.tag, child.attributes, const <SelectorElement>[]),
        ];
        final selfView = _NodeView(node.tag, node.attributes, childViews);
        final childAncestors = <SelectorElement>[...ancestors, selfView];
        // 容器级浮动传导（W12）：flat 管线把容器拆成子块后，容器上的
        // `float`/`width` 会整条丢掉（双列目录 `.dk-toc-item{float:left;
        // width:48%}` 因此排成单列）。这里把容器浮动按「传导白名单」的
        // 思路带给子块：子块整体当作一个浮动盒（同一 groupId 分组）。
        var childContainerFloat = containerFloat;
        var childContainerFloatWidth = containerFloatWidth;
        var childContainerFloatGroup = containerFloatGroup;
        final selfStyle = chainStyle(childAncestors);
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
                containerStyle.listStylePosition ==
                CssListStylePosition.inside,
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
          collect(
            child,
            node.tag,
            attributes: node.attributes,
            groupId: childGroup,
            list: childList,
            quoteDepth: childQuoteDepth,
            ancestors: childAncestors,
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
        _NodeView(
          'body',
          document.root.attributes,
          const <SelectorElement>[],
        ),
      ],
    );

    // 相邻块上下外边距折叠（CSS 2.1 §8.3.1）：段距取 max，而不是两段
    // margin 相加。分页器、浮动分页与页索引重放共用这批块对象，
    // PageIndex.from 按块身份记录块序号，必须先折叠再分页。
    blocks = _collapseMarginsIgnoringFloats(blocks);

    // 浮动章（flat 管线接入）：含浮动块的章节走浮动感知手动分页
    //（引擎 FloatOccupancy 区间模型），不进 Paginator 与页索引重放。
    if (blocks.any((b) => b.floatSide != null)) {
      final floated = _withFixedOverlays(
        _paginateWithFloats(blocks, spineIndex),
        fixedBlocks,
      );
      _putPageCache(paginationKey, floated);
      return floated;
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
        final replayed = PageIndex.apply(index, blocks, spineIndex: spineIndex);
        if (replayed != null) {
          _putPageCache(paginationKey, replayed);
          return replayed;
        }
        _logInvalidation('indexSchemaMismatch', paginationKey, paginationKey);
      } else {
        _logInvalidation('indexCorrupted', paginationKey, paginationKey);
      }
      _pageIndexCache.remove(paginationKey);
    }
    final pages = _withFixedOverlays(
      Paginator(pageHeight: contentHeight, pageWidth: contentWidth)
          .measureChapter(blocks: blocks, spineIndex: spineIndex)
          .pages,
      fixedBlocks,
    );
    _putPageCache(paginationKey, pages);
    if (trace != null) {
      trace.record(
        ReaderTraceName.chapterLayout,
        watch!.elapsedMicroseconds,
        bookId: traceBook,
      );
    }
    if (!skipPageIndex) {
      _pageIndexCache[paginationKey] = PageIndex.from(
        ChapterPagination(
          spineIndex: spineIndex,
          pages: pages,
          pageHeight: contentHeight,
          totalHeight: 0,
        ),
        blocks,
      ).encode();
    }
    return pages;
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
      (1000, 'M'), (900, 'CM'), (500, 'D'), (400, 'CD'),
      (100, 'C'), (90, 'XC'), (50, 'L'), (40, 'XL'),
      (10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I'),
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
  const _NodeView(this.tag, this.attributes, this.childElements);

  @override
  final String tag;

  @override
  final Map<String, String> attributes;

  @override
  final List<SelectorElement> childElements;
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
  });

  /// 摘掉浮动内容后的段落文本。
  final String text;

  /// 重映射后的行内标记（用于重新生成 runs）。
  final List<InlineMark> marks;

  /// 摘出的浮动块（行内浮动）。
  final PageBlock? block;

  /// 摘出的行内盒子（`display: inline-block`）：交给行排版按行内盒放置。
  final InlineBoxSpec? inlineBox;

  /// 旧偏移 → 新偏移。
  final int Function(int offset) remapOffset;

  /// 被摘掉的区间（旧坐标，半开）。
  final int removeStart;
  final int removeEnd;

  /// 偏移是否落在被摘掉的区间内。
  bool removed(int offset) => offset >= removeStart && offset < removeEnd;
}
