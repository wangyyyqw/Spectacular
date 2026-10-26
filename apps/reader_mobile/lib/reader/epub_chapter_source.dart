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
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/line_breaker.dart';
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
    final result = await openEpub(bytes, verifyCrc: verifyCrc);
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

  /// 块级左右水平内缩总量：外边距 + 内边距 + 边框。
  ///
  /// flat 管线把块级水平内缩折算进绘制左偏移（PagePainter 取
  /// `slice.leftInset + style.margin.left`），排版宽度必须同步扣掉同一
  /// 份内缩——否则带 margin/padding 的段落整体右移、压出正文区右缘被
  /// 裁切（真机：作者 CSS `body`/`p` 各 1% 外边距 → 正文右偏且缺右缘
  /// 字）。
  double _horizontalInsetsOf(ComputedStyle style) =>
      style.margin.horizontal +
      style.padding.horizontal +
      style.borders.left.width +
      style.borders.right.width;

  /// 文本块的排版宽度：正文区宽扣除块级左右水平内缩。
  double _textWidthFor(ComputedStyle style) =>
      math.max(24.0, contentWidth - _horizontalInsetsOf(style));

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
    'background-color', 'border-left', 'border-right',
    'padding-left', 'padding-right', 'margin-left', 'margin-right',
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
      occupancy.clear();
    }

    for (final block in blocks) {
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
        final w = block.layout.width;
        final h = block.height;
        if (y > 0 && y + h > height) {
          closePage();
        }
        final x0 = floatSide == FloatSide.left ? 0.0 : width - w;
        occupancy.insert(
          BoxOccupied(
            rect: Rect.fromLTWH(x0, y, w, h),
            baseline: y,
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
            absoluteTop: y,
            leftInset: x0,
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
      // 行批切段：同占位状态的行聚成一批，窄批重测。
      final fullText = block.layout.text;
      var charCursor = 0;
      var leadingLeft = block.leadingExtent;
      while (charCursor < fullText.length) {
        final probe = block.layout.lines.first.height;
        final occupiedLeft = occupancy.occupiedLeftAt(y, y + probe);
        final occupiedRight =
            occupancy.occupiedRightAt(y, y + probe, width);
        final narrowed = occupiedLeft > 0 || occupiedRight > 0;
        // 块级水平内缩同样占宽（见 _textWidthFor）：窄批只减浮动占位。
        final available = math.max(
          24.0,
          width - _horizontalInsetsOf(block.style ?? style),
        );
        final batchWidth = narrowed
            ? math.max(
                24.0,
                available - occupiedLeft - occupiedRight - gap * 2,
              )
            : available;
        final remaining = fullText.substring(charCursor);
        final measured = _layoutCache.layout(
          text: remaining,
          style: block.style ?? style,
          maxWidth: batchWidth,
        );
        // 取行：直到批状态变化（下一行的占位区间不同）或页尽或文本尽。
        var taken = 0;
        var batchHeight = 0.0;
        while (taken < measured.lineCount) {
          final lineH = measured.lines[taken].height;
          if (y + leadingLeft + batchHeight + lineH > height && y > 0) {
            break;
          }
          final nextLeft = occupancy.occupiedLeftAt(
            y + leadingLeft + batchHeight,
            y + leadingLeft + batchHeight + lineH,
          );
          final nextRight = occupancy.occupiedRightAt(
            y + leadingLeft + batchHeight,
            y + leadingLeft + batchHeight + lineH,
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
          // 首行就放不下：收页重试（页首必能放至少一行）。
          closePage();
          leadingLeft = 0;
          continue;
        }
        final segLines = measured.lines.take(taken).toList();
        final segText = remaining.substring(
          0,
          segLines.last.end,
        );
        final segLayout = TextLayoutResult(
          text: segText,
          lines: segLines,
          width: batchWidth,
          height: batchHeight,
          maxWidth: batchWidth,
          runs: const <StyledRun>[],
        );
        final segBlock = PageBlock(
          layout: segLayout,
          style: block.style,
          startCfi: block.startCfi,
          leftInset: narrowed ? occupiedLeft + gap : block.leftInset,
        );
        slices.add(
          PageBlockSlice(
            block: segBlock,
            startLine: 0,
            endLine: taken,
            height: leadingLeft + batchHeight,
            leadingExtent: leadingLeft,
            trailingExtent: taken == measured.lineCount
                ? block.trailingExtent
                : 0,
            leftInset: segBlock.leftInset,
          ),
        );
        y += leadingLeft + batchHeight;
        leadingLeft = 0;
        charCursor += segText.length;
        if (charCursor < fullText.length &&
            y + (block.layout.lines.first.height) > height &&
            y > 0) {
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

    // 块级样式（P8-02 链式级联）：UA（uaRules）+ 作者样式表（私有钩子
    // 契约过滤）+ 内联 style 三源进 Cascade.compute——特异性/!important/
    // @media/继承（18 项继承表）全部由引擎处理；flat 管线只补盒类近似
    // 传导与引用深度。前缀缓存：同容器兄弟块共享祖先计算结果。
    final sheets = _chapterStylesheets(spineIndex);
    await _ensureBookFonts(sheets);
    final cascadeRules = <CascadeRule>[
      ...uaRules(),
      for (var i = 0; i < sheets.length; i++)
        ...CascadeRule.fromStylesheet(
          sheets[i],
          origin: CascadeOrigin.author,
          startOrder: 1000 + i * 10000,
        ),
    ];
    final chainStyleCache = <String, ComputedStyle>{};
    var figureSeq = 0;

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
          inlineDeclarations: _inlineDeclarationsOf(
            chain.last.attributes['style'],
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

    /// 块级样式入口（P8-02）：链式级联结果 + 容器盒类近似传导 +
    /// 引用深度边距叠加。P8-05c：容器的上下边框拼合——首个后代块画
    /// 上边框、末个画下边框（flat 无嵌套盒子的面板整框近似）。
    ComputedStyle styleForChain(
      List<SelectorElement> chain, {
      int quoteDepth = 0,
      bool firstInContainer = false,
      bool lastInContainer = false,
    }) {
      final computed = chainStyle(chain);
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
      if (promoted.isEmpty && extraLeft == 0 && extraRight == 0) {
        return computed;
      }
      final declarations = <String, String>{...promoted, ...computed.values};
      if (extraLeft > 0) {
        declarations['margin-left'] = '${computed.margin.left + extraLeft}px';
      }
      if (extraRight > 0) {
        declarations['margin-right'] = '${computed.margin.right + extraRight}px';
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
      List<SelectorElement> ancestors,
    ) {
      // src 键名兼容 SVG <image xlink:href> 折叠链。
      final src = node.attributes['src'] ?? node.attributes['xlink:href'];
      if (src == null || src.isEmpty) {
        return;
      }
      final url =
          this.document.resources.resolve(src, baseDir: chapterBase) ?? src;
      // 图片自身 CSS（P9-08）：img.xxx { width: 36px; height: auto } 这类
      // 声明的尺寸必须优先于表现属性，否则插图/头像会按整宽绘制。
      final imageStyle = styleForChain(<SelectorElement>[
        ...ancestors,
        _NodeView(node.tag, node.attributes, const <SelectorElement>[]),
      ]);
      var size = _resolveImageDisplaySize(
        node.attributes,
        imageSizes[url],
        contentWidth,
        contentHeight,
        cssWidth: imageStyle.width?.resolve(contentWidth),
        cssHeight: imageStyle.height?.resolve(contentHeight),
      );
      final floatSide = floatSideOf(node.attributes);
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
      final blockWidth = floatSide != null ? size.$1 : contentWidth;
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
        PageBlock(layout: layout, style: blockStyle, floatSide: floatSide),
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

      /// 单元格水平占位：左右内边距 + 左右边框。
      double horizontalInset(ComputedStyle style) =>
          style.padding.left +
          style.padding.right +
          style.borders.left.width +
          style.borders.right.width;

      /// 单元格垂直占位：上下内边距 + 上下边框。
      double verticalInset(ComputedStyle style) =>
          style.padding.top +
          style.padding.bottom +
          style.borders.top.width +
          style.borders.bottom.width;

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
      String cellTextOf(BlockNode cell) {
        final buffer = StringBuffer();
        void walkText(EpubNode node) {
          if (node is TextBlockNode) {
            if (node.text.trim().isNotEmpty) {
              if (buffer.isNotEmpty) {
                buffer.write('\n');
              }
              buffer.write(node.text.trim());
            }
          } else if (node is BlockNode) {
            for (final child in node.children) {
              walkText(child);
            }
          } else if (node is InlineNode) {
            for (final child in node.children) {
              walkText(child);
            }
          }
        }

        walkText(cell);
        return buffer.toString();
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
      for (var i = 0; i < columnElements.length && i < columnCount; i += 1) {
        final column = columnElements[i];
        columnSpecified[i] = declaredLength(
          styleForChain(<SelectorElement>[
            ...tableChain,
            _NodeView(
              column.tag,
              column.attributes,
              const <SelectorElement>[],
            ),
          ]),
          column.attributes,
        );
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
        for (final cell in row) {
          final cellStyle = styleForChain(<SelectorElement>[
            ...tableChain,
            rowView,
            _NodeView(cell.tag, cell.attributes, const <SelectorElement>[]),
          ]);
          final text = cellTextOf(cell);
          final colspan = int.tryParse(
                cell.attributes['colspan']?.trim() ?? '',
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
                        )
                        .height +
                    verticalInset(cellStyle);
              },
            ),
          );
        }
        cellStyles.add(styles);
        cellTexts.add(texts);
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
        }
        firstRowColumn += span;
      }

      final fixedLayout = tableStyle.tableLayout == CssTableLayout.fixed;
      final List<double> columnWidths;
      final List<double> rowHeights;
      final double tableWidthPxFinal;
      if (fixedLayout) {
        // `table-layout: fixed`：声明列保持声明宽，剩余空间平分给未声明列。
        var target = tableWidthPercent != null
            ? contentWidth * tableWidthPercent.clamp(0.0, 1.0)
            : (tableWidthPx ?? contentWidth);
        target = target.clamp(0.0, contentWidth);
        final widths = List<double>.filled(columnCount, 0);
        var specifiedTotal = 0.0;
        var autoColumns = 0;
        for (var c = 0; c < columnCount; c += 1) {
          final specified = columnSpecified[c];
          if (specified != null) {
            widths[c] = specified;
            specifiedTotal += specified;
          } else {
            autoColumns += 1;
          }
        }
        if (autoColumns == 0) {
          if (specifiedTotal > target && specifiedTotal > 0) {
            final scale = target / specifiedTotal;
            for (var c = 0; c < columnCount; c += 1) {
              widths[c] *= scale;
            }
          }
        } else {
          final share = math.max(0.0, target - specifiedTotal) / autoColumns;
          for (var c = 0; c < columnCount; c += 1) {
            if (columnSpecified[c] == null) {
              widths[c] = share;
            }
          }
        }
        columnWidths = widths;
        tableWidthPxFinal = widths.fold(0.0, (sum, width) => sum + width);
        final heights = <double>[];
        for (var r = 0; r < rows.length; r += 1) {
          var rowHeight = 0.0;
          var column = 0;
          for (var i = 0; i < rows[r].length; i += 1) {
            final span =
                int.tryParse(rows[r][i].attributes['colspan']?.trim() ?? '') ??
                    1;
            var cellWidth = 0.0;
            for (var c = column; c < column + span && c < columnCount; c += 1) {
              cellWidth += columnWidths[c];
            }
            column += span;
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
            rowHeight = math.max(rowHeight, height);
          }
          heights.add(rowHeight);
        }
        rowHeights = heights;
      } else {
        final measured = TableGridMeasurer.measureGrid(
          rows: specs,
          columnSpecified: columnSpecified,
          tableWidthPx: tableWidthPx,
          tableWidthPercent: tableWidthPercent,
          containerWidth: contentWidth,
        );
        columnWidths = measured.columnWidths;
        rowHeights = measured.rowHeights;
        tableWidthPxFinal = measured.tableWidth;
      }
      final grid = TableGridLayout(
        rows: specs,
        columnWidths: columnWidths,
        rowHeights: rowHeights,
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
      // 行边界切分（P3-20）：以正文页高为页。
      final slices = TablePaginator.paginateRows(
        rowHeights: rowHeights,
        pageHeight: contentHeight,
      );
      final gridRowYs = grid.rowYs;
      final gridColumnXs = grid.columnXs;
      for (final slice in slices) {
        final sliceTop = gridRowYs[slice.firstRow];
        final sliceHeight = slice.clippedRowHeight > 0
            ? slice.clippedRowHeight
            : slice.drawnHeight;
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
    }) {
      if (node is TextBlockNode) {
        final cfi = node is TextContentNode ? node.cfi.serialize() : null;
        final text = node.text;
        if (text.trim().isEmpty) {
          return;
        }
        // 伪元素生成内容（P8-09）：::before/::after 的 content（字符串/
        // attr()）拼进块首尾（flat 近似：CFI 偏移不含生成文本，记录）。
        final before = _pseudoContent(sheets, ancestors, '::before');
        final after = _pseudoContent(sheets, ancestors, '::after');
        final effectiveText =
            (before == null && after == null) || node is! TextContentNode
            ? text
            : '${before ?? ''}$text${after ?? ''}';
        // 链末位即当前块上下文（P8-02：链式级联含全部祖先）；
        // 首末容器位（P8-05c）供上下边框拼合。
        final tag = ancestors.isEmpty ? 'body' : ancestors.last.tag;
        final isHeading = _headingTags.contains(tag);
        // 阅读器排版覆盖（reader origin 高于 author）：字号/行高/对齐作用
        // 在级联结果之上，否则作者 p{font-size;line-height} 会让设置失效。
        // 标题不参与——标题字号/行高继续跟随书籍样式族。
        var blockStyle = styleForChain(
          ancestors,
          quoteDepth: quoteDepth,
          firstInContainer: firstInContainer,
          lastInContainer: lastInContainer,
        );
        if (!isHeading) {
          blockStyle = overrides.applyTypography(blockStyle);
        }
        // 绝对定位（P9-19）：脱离正常流，top/left 按页内坐标解析；
        // 未声明 top/left 时跟随当前流位置。
        final blockPosition = blockStyle.position;
        final isAbsolute = blockPosition == CssPosition.absolute ||
            blockPosition == CssPosition.fixed;
        final absoluteTop = isAbsolute
            ? blockStyle.top?.resolve(contentHeight)
            : null;
        final absoluteLeft = isAbsolute
            ? blockStyle.left?.resolve(contentWidth)
            : null;
        // 段间距（阅读器设置优先）：只作用于正文段落；标题与列表项保留
        // 书籍自身的间距族。null 时沿用块 margin 并交给相邻折叠。
        final paragraphSpacing = isHeading || tag == 'li'
            ? null
            : overrides.paragraphSpacing;
        // 列表标记（P3-23）：li 项按所在列表类型与序号赋标记文本。
        String? marker;
        if (ancestors.isNotEmpty && ancestors.last.tag == 'li' &&
            list != null) {
          final markerText = list.nextMarker(blockStyle.listStyleType);
          marker = markerText.isEmpty ? null : markerText;
        }
        // 行内样式区间（P8-02）：聚合标记链 → 引擎级联 → StyledRun 混排；
        // ::first-letter（P8-09）：命中规则时首字符放大 run 追加。
        var runs = node is TextContentNode
            ? resolveInlineRuns(node.inlineMarks)
            : const <StyledRun>[];
        // 行内图片（P9-06）：占位符 → 书内图片路径 + 书籍 CSS 尺寸。
        final inlineImages = <InlineImageSpec>[];
        if (node is TextContentNode && node.inlineImages.isNotEmpty) {
          final shift = (before ?? '').length;
          for (final mark in node.inlineImages) {
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
            inlineImages.add(
              InlineImageSpec(
                offset: mark.offset + shift,
                url: url,
                width: imageStyle.width?.resolve(contentWidth),
                height: imageStyle.height?.resolve(contentWidth),
              ),
            );
          }
        }
        final firstLetter = _firstLetterRun(
          sheets,
          ancestors,
          effectiveText,
          blockStyle,
        );
        if (firstLetter != null) {
          runs = [...runs, firstLetter];
        }
        final layout = _layoutCache.layout(
          text: effectiveText,
          style: blockStyle,
          maxWidth: _textWidthFor(blockStyle),
          runs: runs,
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
              // 块级上下边距进分页几何（含负值）：作者/UA margin 生效，
              // 阅读器段距设置优先；相邻段在分页层折叠取大
              //（PageBlock.collapseAdjacentMargins）。
              spaceBefore: paragraphSpacing ?? blockStyle.margin.top,
              spaceAfter: paragraphSpacing ?? blockStyle.margin.bottom,
              // P8-08：注音标注透传渲染层。
              rubies: node is TextContentNode && node.rubies.isNotEmpty
                  ? [
                      for (final ruby in node.rubies)
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
              absolute: isAbsolute,
              absoluteTop: absoluteTop,
              absoluteLeft: absoluteLeft,
            ),
          );
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
          collectImageBlock(node, ancestors);
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
    blocks = PageBlock.collapseAdjacentMargins(blocks);

    // 浮动章（flat 管线接入）：含浮动块的章节走浮动感知手动分页
    //（引擎 FloatOccupancy 区间模型），不进 Paginator 与页索引重放。
    if (blocks.any((b) => b.floatSide != null)) {
      final floated = _paginateWithFloats(blocks, spineIndex);
      _putPageCache(paginationKey, floated);
      return floated;
    }

    // pagination 层（P7-23）：先试页索引重放（P7-22），跳过分页状态
    // 机；索引缺失/损坏/schema 不匹配时静默重排并回写索引。
    final hasAbsoluteBlocks = blocks.any((block) => block.absolute);
    final cachedIndexBytes = hasAbsoluteBlocks
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
    final pages = Paginator(pageHeight: contentHeight)
        .measureChapter(blocks: blocks, spineIndex: spineIndex)
        .pages;
    _putPageCache(paginationKey, pages);
    if (trace != null) {
      trace.record(
        ReaderTraceName.chapterLayout,
        watch!.elapsedMicroseconds,
        bookId: traceBook,
      );
    }
    if (!hasAbsoluteBlocks) {
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
  _ListContext(this.type, this.depth);

  /// 'ul' 或 'ol'。
  final String type;

  /// 嵌套深度（0 起）。
  final int depth;

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
