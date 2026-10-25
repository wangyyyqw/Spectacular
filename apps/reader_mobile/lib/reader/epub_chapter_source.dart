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
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
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
  List<CssStylesheet> _chapterStylesheets(int spineIndex) {    return _chapterSheetCache.putIfAbsent(spineIndex, () {
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
  };
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
        final batchWidth = narrowed
            ? math.max(24.0, width - occupiedLeft - occupiedRight - gap * 2)
            : width;
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
        final ancestorTag = chain[i].tag;
        if (ancestorTag == 'ul' || ancestorTag == 'ol' ||
            ancestorTag == 'li') {
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
          runs.add(StyledRun(start: start, end: end, style: resolved));
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

    void collectImageBlock(BlockNode node) {
      // src 键名兼容 SVG <image xlink:href> 折叠链。
      final src = node.attributes['src'] ?? node.attributes['xlink:href'];
      if (src == null || src.isEmpty) {
        return;
      }
      final url =
          this.document.resources.resolve(src, baseDir: chapterBase) ?? src;
      var size = _resolveImageDisplaySize(
        node.attributes,
        imageSizes[url],
        contentWidth,
        contentHeight,
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
    void collectTable(BlockNode tableNode) {
      const cellPad = 3.0;
      final rows = <List<BlockNode>>[];
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

      // 列声明宽：首行 td/th 的 width 属性（px）近似列声明。
      final columnSpecified = <double?>[];
      for (final cell in rows.first) {
        final raw = cell.attributes['width'];
        final value = raw == null ? null : double.tryParse(raw.trim());
        columnSpecified.add(value);
      }
      final tableWidthRaw = tableNode.attributes['width'];
      double? tableWidthPx;
      double? tableWidthPercent;
      if (tableWidthRaw != null) {
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

      // 每格：样式、全宽自然测量、按宽测高闭包。
      final cellStyles = <List<ComputedStyle>>[];
      final specs = <List<TableCellSpec>>[];
      final cellTexts = <List<String>>[];
      for (final row in rows) {
        final styles = <ComputedStyle>[];
        final rowSpecs = <TableCellSpec>[];
        final texts = <String>[];
        for (final cell in row) {
          final cellStyle = styleFor(
            cell.tag,
            attributes: cell.attributes,
          );
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
            return widest + cellPad * 2;
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
                          maxWidth: math.max(8.0, width - cellPad * 2),
                        )
                        .height +
                    cellPad * 2;
              },
            ),
          );
        }
        cellStyles.add(styles);
        cellTexts.add(texts);
        specs.add(rowSpecs);
      }

      final measured = TableGridMeasurer.measureGrid(
        rows: specs,
        columnSpecified: columnSpecified,
        tableWidthPx: tableWidthPx,
        tableWidthPercent: tableWidthPercent,
        containerWidth: contentWidth,
      );
      final grid = TableGridLayout(
        rows: specs,
        columnWidths: measured.columnWidths,
        rowHeights: measured.rowHeights,
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
                  maxWidth: math.max(8.0, rect.rect.width - cellPad * 2),
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
        rowHeights: measured.rowHeights,
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
          PageBlock(
            layout: TextLayoutResult(
              text: '',
              lines: [
                LineBox(
                  start: 0,
                  end: 0,
                  top: 0,
                  height: sliceHeight,
                  baseline: sliceHeight,
                  width: measured.tableWidth,
                ),
              ],
              width: measured.tableWidth,
              height: sliceHeight,
              maxWidth: measured.tableWidth,
              runs: const <StyledRun>[],
            ),
            style: styleFor('table', attributes: tableNode.attributes),
            table: TableRenderSpec(
              cells: cells,
              columnXs: gridColumnXs,
              rowYs: [
                for (var r = slice.firstRow; r <= slice.lastRow; r++)
                  gridRowYs[r] - sliceTop,
                if (slice.clippedRowHeight > 0)
                  slice.clippedRowHeight,
              ],
              tableWidth: measured.tableWidth,
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
        final blockStyle = styleForChain(
          ancestors,
          quoteDepth: quoteDepth,
          firstInContainer: firstInContainer,
          lastInContainer: lastInContainer,
        );
        // 列表标记（P3-23）：li 项按所在列表类型与序号赋标记文本。
        String? marker;
        if (ancestors.isNotEmpty && ancestors.last.tag == 'li' &&
            list != null) {
          marker = list.nextMarker();
        }
        // 行内样式区间（P8-02）：聚合标记链 → 引擎级联 → StyledRun 混排；
        // ::first-letter（P8-09）：命中规则时首字符放大 run 追加。
        var runs = node is TextContentNode
            ? resolveInlineRuns(node.inlineMarks)
            : const <StyledRun>[];
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
          maxWidth: contentWidth,
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
              // P8-05：块级上下边距（含负值）进分页几何——UA/作者的
              // margin-top/bottom 首次生效；相邻段 margin 折叠暂不做
              //（记录为 flat 近似）。
              spaceBefore: blockStyle.margin.top,
              spaceAfter: blockStyle.margin.bottom,
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
          collectImageBlock(node);
          return;
        }
        // 表格块（flat 管线接入）：格布局测量 + 行边界切分 + 渲染载荷。
        if (node.tag == 'table') {
          collectTable(node);
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

    // 浮动章（flat 管线接入）：含浮动块的章节走浮动感知手动分页
    //（引擎 FloatOccupancy 区间模型），不进 Paginator 与页索引重放。
    if (blocks.any((b) => b.floatSide != null)) {
      final floated = _paginateWithFloats(blocks, spineIndex);
      _pageCache[paginationKey] = floated;
      return floated;
    }

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
