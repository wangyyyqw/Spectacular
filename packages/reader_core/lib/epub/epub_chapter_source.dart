import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:reader_core/api.dart' hide ComputedStyle, Paginator;
import 'package:reader_core/cache/chapter_pagination_store.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/epub_exception.dart';
import 'package:reader_core/layout/line_breaker.dart';
// api.dart 也导出了同名的 `LineBreaker` 接口，这里给具体实现加前缀，
// 以便打开小数行高开关（见 [EpubChapterSource.open]）。
import 'package:reader_core/layout/line_breaker.dart' as line_breaker;
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/perf/trace.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/parser/full_bleed.dart';
import 'package:reader_core/position/location_anchor.dart';

import '../util/bounded_cache.dart';
import 'archive_reader.dart';
import 'opf.dart';
import 'resource_index.dart';
import 'chapter/chapter_positions.dart';
import 'chapter/book_resources.dart';
import 'chapter/book_fonts.dart';
import 'chapter/chapter_styles.dart';
import 'chapter/chapter_style_key.dart';
import 'chapter/chapter_structure.dart';
import 'chapter/chapter_preview_cache.dart';
import 'chapter/container_blocks.dart';
import 'chapter/chapter_layout_job.dart';
import 'chapter/chapter_preparation_job.dart';
import 'chapter/chapter_layout_cache.dart';
import 'chapter/chapter_pagination_cache.dart';
import 'chapter/chapter_layout_pipeline.dart';
import 'chapter/chapter_block_walker.dart';
import 'chapter/chapter_text_overlays.dart';
import 'chapter/chapter_page_flags.dart';
import 'chapter/full_page_layout.dart';

export 'chapter/chapter_page_flags.dart';

/// 从 EPUB 文档读取章节并提供分页结果。
class EpubChapterSource
    implements
        ReaderPublicationSource,
        RestylableChapterSource,
        ResizableChapterSource,
        TocChapterSource,
        MissingChapterSource,
        AsyncPositionedChapterSource,
        ScheduledPositionedChapterSource,
        ScheduledAnchorChapterSource,
        PreparedChapterSource,
        BookTypographyFontSource,
        ScheduledChapterSource,
        ProgressiveChapterSource,
        BackgroundLayoutChapterSource,
        CurrentReadingChapterSource,
        SpineLayoutDependencyChapterSource,
        ReaderTextOverlaySource {
  EpubChapterSource._({
    required EpubDocumentImpl document,
    required this.baseContentWidth,
    required this.baseContentHeight,
    required this.baseStyle,
    required this.trimTextEdges,
    String? contentVersion,
    ChapterPreviewCache<ChapterStructure>? previewCache,
    Map<String, String> resourceVersions = const {},
    Future<Directory> Function()? networkImageCacheDirectoryProvider,
    ChapterPaginationStore? paginationStore,
    Future<String> Function(int)? loadChapterXhtml,
    Future<Uint8List?> Function(String)? loadNetworkImage,
  }) : _paginationCache = ChapterPaginationCache(paginationStore),
       _hasStableContentVersion = contentVersion?.trim().isNotEmpty == true,
       _resources = BookResources(
         document,
         trackDependencies: previewCache != null,
         networkImageCacheDirectoryProvider: networkImageCacheDirectoryProvider,
         loadChapterXhtml: loadChapterXhtml,
         loadNetworkImage: loadNetworkImage,
       ),
       _previewCache = previewCache,
       _resourceVersions = Map.unmodifiable(resourceVersions),
       _contentVersion = contentVersion?.trim().isNotEmpty == true
           ? contentVersion!
           : '会话:${++_sessionSequence}';

  static int _sessionSequence = 0;
  String _contentVersion;
  bool _hasStableContentVersion;
  final ChapterPaginationCache _paginationCache;
  final ChapterPreviewCache<ChapterStructure>? _previewCache;
  final Map<String, String> _resourceVersions;

  /// 目录已知、正文按需获取的重排文档，复用 EPUB 的解析、布局和锚点。
  factory EpubChapterSource.fromChapterLoader({
    required BookMeta meta,
    required List<String> chapterTitles,
    List<String> chapterVolumes = const [],
    required Future<String> Function(int spineIndex) loadChapterXhtml,
    Map<String, Uint8List> resources = const {},
    Future<Uint8List?> Function(String url)? loadNetworkImage,
  }) {
    line_breaker.LineBreaker.preserveFractionalLineHeight = true;
    final archive = EpubArchive.fromResources(resources);
    const opfPath = 'content.opf';
    final package = OpfPackage(
      meta: meta,
      manifest: const [],
      spine: List.unmodifiable([
        for (var index = 0; index < chapterTitles.length; index++)
          SpineItem(
            index: index,
            href: 'text/chapter_$index.xhtml',
            mediaType: 'application/xhtml+xml',
          ),
      ]),
      version: '3.0',
      warnings: const [],
    );
    final document = EpubDocumentImpl(
      archive: archive,
      package: package,
      resources: ResourceIndex.build(
        archive: archive,
        manifest: package.manifest,
        opfPath: opfPath,
      ),
      opfPath: opfPath,
      toc: _onlineToc(chapterTitles, chapterVolumes),
      tocSource: '在线目录',
      report: const ImportReport(ok: true),
    );
    return _fromOpenResult(
      EpubOpenResult(document: document, report: document.report),
      contentWidth: 320,
      contentHeight: 480,
      style: null,
      trimTextEdges: true,
      loadChapterXhtml: loadChapterXhtml,
      loadNetworkImage: loadNetworkImage,
    );
  }

  static List<TocEntry> _onlineToc(List<String> titles, List<String> volumes) {
    final result = <TocEntry>[];
    var index = 0;
    while (index < titles.length) {
      final volume = index < volumes.length ? volumes[index].trim() : '';
      if (volume.isEmpty) {
        result.add(TocEntry(title: titles[index], spineIndex: index));
        index++;
        continue;
      }
      final start = index;
      final children = <TocEntry>[];
      while (index < titles.length &&
          index < volumes.length &&
          volumes[index].trim() == volume) {
        children.add(TocEntry(title: titles[index], spineIndex: index));
        index++;
      }
      result.add(
        TocEntry(title: volume, spineIndex: start, children: children),
      );
    }
    return result;
  }

  /// 打开 EPUB 并创建来源。
  static Future<EpubChapterSource> open(
    Uint8List bytes, {
    double contentWidth = 320,
    double contentHeight = 480,
    ComputedStyle? style,
    bool verifyCrc = true,
    bool trimTextEdges = true,
    String? contentVersion,
    Future<Directory> Function()? networkImageCacheDirectoryProvider,
    ChapterPaginationStore? paginationStore,
  }) async {
    // 小数行高（T1 实验开关）：Skia 会把行盒高取整成整数，CSS 的
    // `line-height: 1.7` × 15px = 25.5 会变成 26，列表/表格行位置逐行
    // 累积偏移（31-list-nested 14 项、12-table 残余都是它）。
    line_breaker.LineBreaker.preserveFractionalLineHeight = true;
    final result = await openEpub(bytes, verifyCrc: verifyCrc);
    return _fromOpenResult(
      result,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      style: style,
      trimTextEdges: trimTextEdges,
      contentVersion: contentVersion,
      networkImageCacheDirectoryProvider: networkImageCacheDirectoryProvider,
      paginationStore: paginationStore,
    );
  }

  /// 从文件打开 EPUB：中央目录之外的内容按需读取。
  ///
  /// 阅读页使用这个入口，避免把整本书（100MB+）读进 Dart 堆。
  static Future<EpubChapterSource> openFile(
    File file, {
    double contentWidth = 320,
    double contentHeight = 480,
    ComputedStyle? style,
    bool verifyCrc = false,
    bool trimTextEdges = true,
    String? contentVersion,
    Map<String, Uint8List?> resourceOverrides = const {},
    ChapterPreviewCache<ChapterStructure>? previewCache,
    Map<String, String> resourceVersions = const {},
    Future<Directory> Function()? networkImageCacheDirectoryProvider,
    ChapterPaginationStore? paginationStore,
  }) async {
    line_breaker.LineBreaker.preserveFractionalLineHeight = true;
    final result = await openEpubFile(
      file,
      verifyCrc: verifyCrc,
      resourceOverrides: resourceOverrides,
    );
    return _fromOpenResult(
      result,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      style: style,
      trimTextEdges: trimTextEdges,
      contentVersion: contentVersion,
      previewCache: previewCache,
      resourceVersions: resourceVersions,
      networkImageCacheDirectoryProvider: networkImageCacheDirectoryProvider,
      paginationStore: paginationStore,
    );
  }

  static EpubChapterSource _fromOpenResult(
    EpubOpenResult result, {
    required double contentWidth,
    required double contentHeight,
    required ComputedStyle? style,
    required bool trimTextEdges,
    String? contentVersion,
    ChapterPreviewCache<ChapterStructure>? previewCache,
    Map<String, String> resourceVersions = const {},
    Future<Directory> Function()? networkImageCacheDirectoryProvider,
    ChapterPaginationStore? paginationStore,
    Future<String> Function(int)? loadChapterXhtml,
    Future<Uint8List?> Function(String)? loadNetworkImage,
  }) {
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
      contentVersion: contentVersion,
      previewCache: previewCache,
      resourceVersions: resourceVersions,
      networkImageCacheDirectoryProvider: networkImageCacheDirectoryProvider,
      paginationStore: paginationStore,
      loadChapterXhtml: loadChapterXhtml,
      loadNetworkImage: loadNetworkImage,
    );
  }

  /// 已打开文档。
  final BookResources _resources;
  EpubDocumentImpl get document => _resources.document;

  @override
  ReaderFormat get format => ReaderFormat.epub;

  @override
  ReaderContentLayout get layout => document.extensionConfig.isFixedLike
      ? ReaderContentLayout.fixedPages
      : ReaderContentLayout.reflowable;

  /// 包内、内嵌与网络图片共用读取入口；关闭后不再发布旧资源。
  Future<Uint8List?> readImageBytes(String url) => _resources.readImage(url);

  /// 首次排版前绑定导入摘要；完成布局按实际内容版本复用。
  void setContentVersion(String version) {
    if (_closed || version.trim().isEmpty) return;
    _hasStableContentVersion = true;
    if (version == _contentVersion) return;
    _contentVersion = version;
    _layoutGeneration += 1;
    cancelPendingLayouts();
  }

  /// 目录（P4-11）：每项自带目标 spine 序号。
  @override
  List<TocEntry> get toc => _positions.toc;

  /// 原始正文区宽（未扣设置页边距）。
  final double baseContentWidth;

  /// 原始正文区高。
  final double baseContentHeight;

  /// 书籍基础样式。
  final ComputedStyle baseStyle;
  late final String _baseStyleKey = chapterBaseStyleKey(baseStyle);

  /// 是否回收页首/页尾的行高留白。
  ///
  /// 阅读模式默认开启；CSS 属性对照需要完整行盒时显式关闭。
  final bool trimTextEdges;

  ReaderOverrides _overrides = const ReaderOverrides();
  String _overrideFingerprint = const ReaderOverrides().fingerprint;

  ChapterTextOverlays _chapterOverlays = ChapterTextOverlays(const []);

  /// 阅读页传入的正文区尺寸（旋转/窗口变化后由 ReaderSession 设置）。
  double? _viewportContentWidth;
  double? _viewportContentHeight;
  double? _viewportContentTopInset;
  ContentSideInsets? _viewportSideInsets;

  /// 段落布局缓存（P2-26）：同一文本+样式的重复测量直接复用。
  final TextLayoutCache _layoutCache = TextLayoutCache(
    maxEntries: textLayoutCacheLimit,
  );

  /// 表格最小内容宽只依赖样式与文本片段；缓存单字/词段宽度，避免同一
  /// 章节的多张表格反复创建 TextPainter。
  final BoundedCache<String, double> _textWidthCache = BoundedCache(2048);

  late final ChapterStructureStore _structures = ChapterStructureStore(
    _resources,
    _styles,
    baseStyle,
    previewCache: _previewCache,
    resourceVersions: _resourceVersions,
  );

  late final ChapterPositions _positions = ChapterPositions(
    _resources,
    _structures,
  );

  /// 保留原门面的块重排测试入口。
  static TextLayoutResult withLayoutWidth(
    TextLayoutResult source, {
    double? width,
    double? maxWidth,
  }) => pageBlockWithLayoutWidth(source, width: width, maxWidth: maxWidth);

  static const int pageCacheChapterLimit = ChapterLayoutCache.maxEntries;
  static const int textLayoutCacheLimit = 4096;
  static const int blockCacheChapterLimit = pageCacheChapterLimit;
  static const int documentCacheChapterLimit = 3;
  static const int chapterIndexCacheLimit = 3;
  static const int cssSheetCacheLimit = 32;
  static const int imageIntrinsicCacheLimit = 512;
  static const int imageHeaderProbeBytes = 256 * 1024;
  static const int floatGroupBase = ChapterBlockWalker.floatGroupBase;

  final ChapterLayoutCache _completed = ChapterLayoutCache.recent;
  final Map<String, PreparedChapterLayout> _layoutInputs = {};
  final BoundedCache<int, LayoutSnapshot> _lastSnapshots = BoundedCache(3);
  final BoundedCache<String, Future<void>> _preparerTasks = BoundedCache(3);
  final Set<ChapterLoadHandle> _waitingLayouts = {};
  Future<void> Function(int)? _chapterPreparer;
  String? _bookTypographyFingerprint;
  Set<String> _bookTypographyFamilies = const {};
  int _preparerEpoch = 0;
  int _blockCacheHits = 0;
  int _chapterLayoutCount = 0;
  int _storedIndexReplays = 0;
  late final ChapterLayoutScheduler _scheduler = ChapterLayoutScheduler(
    run: _runLayout,
    isCurrent: _isCurrentSnapshot,
    onFinished: _releaseLayoutInput,
    onPageCount: _rememberPageCount,
  );
  late final ChapterLayoutPipeline _pipeline = ChapterLayoutPipeline(
    _resources,
    _layoutCache,
    _textWidthCache,
  );

  /// styles 层块缓存命中次数（测试/诊断用）。
  int get blockCacheHits => _blockCacheHits;

  /// 章节结构缓存命中次数（测试/诊断用）。
  int get displayDocumentCacheHits => _structures.hits;

  /// 实际原文准备次数，验证开书只准备目标章。
  int get anchorPreparationCount => _structures.preparations;

  /// 同步读取已准备的原文；调用前等待目标章的准备任务。
  AnchorChapter anchorChapter(int spineIndex) =>
      _positions.anchorChapter(spineIndex, contentWidth);

  /// 页、块和索引共享同一所有者；报告只列出本来源仍可访问的条目。
  String get cacheReport {
    final entries = _closed
        ? <CompletedChapterLayout>[]
        : _completed.entries
              .where((entry) => entry.key.startsWith(_cacheScope))
              .toList();
    final pages = entries
        .where((entry) => !_completed.requiresReplay(entry.key))
        .length;
    return '页缓存 $pages/$pageCacheChapterLimit 章；'
        '块缓存 ${entries.length}/$blockCacheChapterLimit 章；'
        '完成布局 ${_completed.estimatedBytes}/${ChapterLayoutCache.maxBytes} 字节；'
        '持久分页命中 ${_paginationCache.hits} 次，缓存异常 ${_paginationCache.failures} 次；'
        '持久页索引回放 $_storedIndexReplays 次；'
        '文档缓存 ${_structures.length}/$documentCacheChapterLimit 章；'
        '${_styles.cacheReport}；'
        '满屏索引 ${_structures.length}/$chapterIndexCacheLimit 章；'
        '脚注索引 ${_resources.footnoteCacheCount}/$chapterIndexCacheLimit 章；'
        '字体 face ${_fonts.faceCount} 个/${_fonts.engineFamilies.length} 族；'
        '段落布局 ${_layoutCache.length}/$textLayoutCacheLimit 条；'
        '文本宽度 ${_textWidthCache.length}/2048 条；'
        '图片索引 ${_resources.imageCacheCount}/$imageIntrinsicCacheLimit 个；'
        '纯文本缓存 ${_positions.plainTextCacheCount}/$chapterIndexCacheLimit 章';
  }

  String get _cacheScope => '${jsonEncode(_contentVersion)}|';

  String get _configurationKey =>
      '$_cacheScope'
      'base=$_baseStyleKey|${contentWidth}x$contentHeight'
      '|page=$baseContentHeight|top=$_contentTopInset|trim=$trimTextEdges|edges=3'
      '|sides=${_contentSideInsets.left},${_contentSideInsets.right}'
      '|spacing=$textSpacingRevision|index=${PageIndex.currentSchemaVersion}'
      '|platform=${Platform.operatingSystem}:${Platform.operatingSystemVersion}'
      '|${_overrides.fingerprint}';

  String get _preparationKey =>
      '$_configurationKey|generation=$_layoutGeneration';

  String _paginationKey(int spine, String dependency) =>
      '$_configurationKey|spine=$spine|font=$dependency'
      '|text=${_chapterOverlays.forSpine(spine).typographyFingerprint}'
      '${_previewCache == null ? '' : '|resources=${_structures.prepared(spine, contentWidth).resourceDependency}'}';

  /// 失效与续排日志（P7-27）：同时记录失效前后的缓存键，
  /// 便于定位设置、视口或页索引变化。
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

  /// 索引回放仍使用同一条目的块树，不额外保存第二套完整布局。
  void clearPaginationCache() =>
      _completed.markForReplay((entry) => entry.key.startsWith(_cacheScope));

  /// 系统内存压力时释放非当前完成结果，当前可见正文继续保留。
  void clearNonCurrentLayouts() {
    _completed.clearNonCurrent();
    _layoutCache.clear();
    _textWidthCache.clear();
  }

  void injectPageIndexForTest(int spineIndex, Uint8List bytes) {
    final snapshot = _lastSnapshots[spineIndex];
    if (snapshot != null) _completed.injectPageIndex(snapshot.key, bytes);
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

  ContentSideInsets get _contentSideInsets =>
      _viewportSideInsets ??
      (
        left: _overrides.padding?.left ?? 0,
        right: _overrides.padding?.right ?? 0,
      );

  /// 容器级浮动分组号的起点（W12）：普通块组的 groupId 从 1 起，
  /// 容器浮动组用 [floatGroupBase] + 序号，分页时按组整体占位。

  ComputedStyle? _resolvedBaseStyle;

  /// 作者级联基准：同一环境复用，阅读字号由正文构块阶段另行覆盖。
  ///
  /// 这里保留书籍字号以解算作者的 em 几何；尺寸变化后重算仍可能返回同一
  /// 基准实例，实际测量与分页是否复用由冻结快照的完整布局键决定。
  ComputedStyle get style => _resolvedBaseStyle ??= _applyCustomFont(
    _overrides.applyCascadeBase(baseStyle, containingWidth: contentWidth),
  );

  /// 字体策略只改字族，标题、表格与行内元素继续保留作者的字号与盒样式。
  ComputedStyle _applyCustomFont(ComputedStyle computed) =>
      _fonts.freeze().applyCustomFont(computed, _overrides);

  @override
  Future<bool> applyTextOverlays(List<ReaderTextOverlay> overlays) async {
    final next = ChapterTextOverlays(overlays);
    final previous = _chapterOverlays.typographyFingerprint;
    _chapterOverlays = next;
    if (previous == next.typographyFingerprint) return false;
    _logInvalidation(
      'textTypographyChanged',
      previous,
      next.typographyFingerprint,
    );
    _scheduler.cancelWhere((snapshot) => !_isCurrentSnapshot(snapshot));
    return true;
  }

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    final previous = _overrides;
    final width = contentWidth;
    _overrides = overrides;
    _overrideFingerprint = overrides.fingerprint;
    _resolvedBaseStyle = null;
    if (previous.fingerprint == overrides.fingerprint) return;
    _layoutGeneration += 1;
    _logInvalidation(
      _isFontOnlyChange(previous, overrides)
          ? 'fontFamilyChanged'
          : 'configChanged',
      previous.fingerprint,
      overrides.fingerprint,
    );
    cancelPendingLayouts();
    if (width != contentWidth) _clearViewportStructure();
  }

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
    ContentSideInsets? sideInsets,
  }) async {
    final previous = (
      width: contentWidth,
      height: contentHeight,
      top: _contentTopInset,
      sides: _contentSideInsets,
    );
    _viewportContentWidth = math.max(80.0, width);
    _viewportContentHeight = math.max(120.0, height);
    _viewportContentTopInset = math.max(0.0, topInset);
    _viewportSideInsets = sideInsets == null
        ? null
        : (
            left: math.max(0.0, sideInsets.left),
            right: math.max(0.0, sideInsets.right),
          );
    final next = (
      width: contentWidth,
      height: contentHeight,
      top: _contentTopInset,
      sides: _contentSideInsets,
    );
    if (previous == next) return false;
    _layoutGeneration += 1;
    _resolvedBaseStyle = null;
    _logInvalidation('viewportSizeChanged', '$previous', '$next');
    cancelPendingLayouts();
    if (previous.width != next.width) _clearViewportStructure();
    return true;
  }

  /// 埋点用的书籍标识（P4-31）；由打开方按需设置。
  String? bookIdForTrace;

  @override
  int get chapterCount => document.spine.length;

  @override
  String get layoutDependency =>
      'base=$_baseStyleKey;'
      'fonts=${_fonts.freeze().dependency({...baseStyle.fontFamilies, ?_overrides.fontFamily})}';

  @override
  String layoutDependencyForSpine(int spineIndex) {
    final snapshot = _lastSnapshots[spineIndex];
    return snapshot == null
        ? layoutDependency
        : 'base=$_baseStyleKey;fonts=${snapshot.fontDependency}';
  }

  /// 全书只持有条目权重；原文索引按目标章准备。
  BookProgressIndex get progressIndex => _positions.progressIndex;

  /// 注入元数据索引，供缺失元数据的估算回归使用。
  void bindProgressIndex(BookProgressIndex index) =>
      _positions.bindProgressIndex(index);

  @override
  bool isChapterMissing(int spineIndex) => _positions.isMissing(spineIndex);

  @override
  Future<AnchorChapter> loadAnchorChapter(int spineIndex) =>
      scheduleAnchorChapter(spineIndex).result;

  @override
  ReaderPreparationHandle<AnchorChapter> scheduleAnchorChapter(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
  }) => mapPreparation(
    _structures.schedule(spineIndex, contentWidth, priority: priority),
    (structure) {
      if (_closed) throw const ChapterLoadCancelled();
      return structure.anchor;
    },
  );

  @override
  double? readingPercentForCfi(String? cfi) =>
      _positions.readingPercentForCfi(cfi, contentWidth);

  /// 图片章的无文本锚点必须对应真实可定位元素。
  bool isValidElementCfi(String cfi) =>
      _positions.isValidElementCfi(cfi, contentWidth);

  @override
  String? cfiForReadingPercent(double percent) =>
      _positions.cfiForReadingPercent(percent, contentWidth);

  @override
  Future<String?> prepareCfiForReadingPercent(double percent) =>
      scheduleCfiForReadingPercent(percent).result;

  @override
  ReaderPreparationHandle<String?> scheduleCfiForReadingPercent(
    double percent,
  ) {
    if (_closed) return cancelledPreparation();
    final location = progressIndex.locate(percent);
    if (location == null) return completedPreparation(null);
    final width = contentWidth;
    return mapPreparation(_structures.schedule(location.spineIndex, width), (
      _,
    ) {
      if (_closed || width != contentWidth) throw const ChapterLoadCancelled();
      return _positions.cfiForReadingPercent(percent, width);
    });
  }

  @override
  String? cfiForTocEntry(TocEntry entry) =>
      _positions.cfiForTocEntry(entry, contentWidth);

  late final BookFonts _fonts = BookFonts(
    _resources,
    onFontsChanged: _invalidateBookFontLayouts,
  );
  late final ChapterStyles _styles = ChapterStyles(_resources, _fonts);

  bool _closed = false;
  int _layoutGeneration = 0;

  /// 是否已关闭。
  bool get isClosed => _closed;

  /// 退出阅读页前等待已取消的准备任务与 worker 端口实际释放。
  Future<void> get preparationsStopped => Future.wait([
    _structures.preparationsStopped,
    _styles.preparationsStopped,
    _resources.preparationsStopped,
    cacheWritesStopped,
  ]);

  /// 关闭在途任务和书籍资源；近期缓存只保留不含资源句柄的纯布局。
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _layoutGeneration += 1;
    cancelPendingLayouts();
    _scheduler.close();
    _layoutInputs.clear();
    _preparerTasks.clear();
    _lastSnapshots.clear();
    _layoutCache.clear();
    _textWidthCache.clear();
    _structures.close();
    _resolvedBaseStyle = null;
    _positions.close();
    _opfPageFlagsCache = null;
    _styles.close();
    _fonts.close();
    _resources.close();
  }

  void _invalidateBookFontLayouts(Set<String> changedFamilies) {
    _resolvedBaseStyle = null;
    _logInvalidation('fontFacesChanged', 'cached', changedFamilies.join(','));
    _scheduler.cancelWhere((snapshot) => !_isCurrentSnapshot(snapshot));
  }

  /// 搜索纯文本不参与阅读位置换算，命中后必须用原文锚点核验。
  String chapterPlainText(int spineIndex) =>
      _positions.chapterPlainText(spineIndex);

  /// OPF `itemref` 上的多看页属性（按 spine 序缓存）。
  Map<int, OpfPageFlags>? _opfPageFlagsCache;

  /// 章节级固定版/漫画布局诊断；每章只保留首个原因。
  final Map<int, String> _layoutWarnings = <int, String>{};

  /// 某章未走固定版/漫画专用路径的原因；未发生降级时为 null。
  String? layoutWarningFor(int spineIndex) => _layoutWarnings[spineIndex];

  /// 从引擎保留的 spine `properties` 解析多看页属性。
  Map<int, OpfPageFlags> _opfPageFlags() {
    final cached = _opfPageFlagsCache;
    if (cached != null) {
      return cached;
    }
    final flags = <int, OpfPageFlags>{
      for (final item in document.spine)
        item.index: _pageFlagsFromProperties(item.properties),
    };
    _opfPageFlagsCache = flags;
    return flags;
  }

  /// 章节的多看页属性（OPF `itemref`）；未标记返回 [OpfPageFlags.none]。
  OpfPageFlags chapterPageFlags(int spineIndex) =>
      _opfPageFlags()[spineIndex] ?? OpfPageFlags.none;

  static OpfPageFlags _pageFlagsFromProperties(Iterable<String> properties) {
    final tokens = properties.toSet();
    bool has(String name) => tokens.contains(name);
    // 标准 page-spread-* 只指定双页摆放，不触发整页图或图片裁切。
    final spreadLeft = has('duokan-page-fullscreen-spread-left');
    final spreadRight = has('duokan-page-fullscreen-spread-right');
    return OpfPageFlags(
      // 全屏跨页的左右页也是全屏页。
      fullScreen: has('duokan-page-fullscreen') || spreadLeft || spreadRight,
      fitWindow: has('duokan-page-fitwindow'),
      spreadLeft: spreadLeft,
      spreadRight: spreadRight,
    );
  }

  /// 满屏判定与原文结构共用纯数据准备结果。
  FullBleedChapter fullBleedAnalysis(int spineIndex) =>
      _structures.prepared(spineIndex, contentWidth).fullBleed;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) =>
      scheduleChapter(spineIndex).result;

  /// 实际整章构块次数，不把纯页面缓存命中计入。
  int get chapterLayoutCount => _chapterLayoutCount;

  @override
  void setChapterPreparer(Future<void> Function(int)? preparer) {
    if (identical(_chapterPreparer, preparer)) return;
    _chapterPreparer = preparer;
    _preparerEpoch += 1;
    _preparerTasks.clear();
  }

  @override
  void setBookTypographyFingerprint(String fingerprint) {
    if (_bookTypographyFingerprint == fingerprint) return;
    _bookTypographyFingerprint = fingerprint;
    _preparerEpoch += 1;
    _preparerTasks.clear();
  }

  @override
  void setBookTypographyFamilies(Set<String> families) {
    final next = Set<String>.unmodifiable(families);
    if (_bookTypographyFamilies.length == next.length &&
        _bookTypographyFamilies.containsAll(next)) {
      return;
    }
    _bookTypographyFamilies = next;
  }

  @override
  void setBookTypographyFontAvailability(String family, bool available) {
    _fonts.setUserFontAvailability(family, available);
  }

  @override
  ChapterLoadHandle scheduleChapter(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
    bool retainResult = true,
  }) => _scheduleChapter(spineIndex, priority, retainResult, false);

  @override
  ProgressiveChapterLoadHandle scheduleProgressiveChapter(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
    bool retainResult = true,
  }) => _scheduleChapter(spineIndex, priority, retainResult, true);

  ProgressiveChapterLoadHandle _scheduleChapter(
    int spineIndex,
    ChapterLayoutPriority priority,
    bool retainResult,
    bool progressive,
  ) {
    if (!_closed && isChapterMissing(spineIndex)) return _emptyChapterHandle();
    final key = _preparationKey;
    final preparation = _structures.schedule(
      spineIndex,
      contentWidth,
      priority: priority,
    );
    final budget = LayoutBudget(
      priority: priority,
      isCurrent: () => !_closed && key == _preparationKey,
      waitForBackground: () => _scheduler.backgroundResumeSignal,
    );
    final handle = PreparingChapterHandle(
      (cancelled) => _prepareAndSchedule(
        spineIndex,
        key,
        cancelled,
        preparation,
        (budget: budget, retain: retainResult, progressive: progressive),
      ),
      onCancel: () {
        budget.cancel();
        preparation.cancel();
      },
      onPriorityChanged: (next) {
        budget.priority = next;
        preparation.promote(next);
      },
      priority: priority,
    );
    _waitingLayouts.add(handle);
    unawaited(
      handle.result.then<void>(
        (_) => _waitingLayouts.remove(handle),
        onError: (Object _, StackTrace _) => _waitingLayouts.remove(handle),
      ),
    );
    return handle;
  }

  Future<ChapterLoadHandle> _prepareAndSchedule(
    int spine,
    String preparationKey,
    bool Function() cancelled,
    ChapterPreparationHandle<ChapterStructure> preparation,
    ({LayoutBudget budget, bool retain, bool progressive}) request,
  ) async {
    void check() {
      if (_closed || cancelled() || preparationKey != _preparationKey) {
        throw const ChapterLoadCancelled();
      }
    }

    try {
      check();
      final structure = await preparation.result;
      check();
      return await _schedulePreparedLayout(
        spine,
        preparationKey,
        structure,
        check,
        request,
      );
    } on EpubException catch (error) {
      if (error.code != 'E_SPINE_MISSING') rethrow;
      _positions.markMissing(spine);
      return _emptyChapterHandle();
    } finally {
      preparation.cancel();
    }
  }

  Future<ChapterLoadHandle> _schedulePreparedLayout(
    int spine,
    String preparationKey,
    ChapterStructure structure,
    void Function() check,
    ({LayoutBudget budget, bool retain, bool progressive}) request,
  ) async {
    final budget = request.budget;
    // 原文可在 isolate 中继续准备，主线程阶段必须先等待空闲或前台接管。
    await budget.checkpoint(
      force: budget.priority == ChapterLayoutPriority.background,
    );
    await _prepareChapterDecoration(spine, preparationKey);
    check();
    await budget.checkpoint(
      force: budget.priority == ChapterLayoutPriority.background,
    );
    final snapshot = await _prepareLayoutSnapshot(spine, structure, check);
    await budget.checkpoint(
      force: budget.priority == ChapterLayoutPriority.background,
    );
    if (!_scheduler.contains(snapshot.key)) {
      _layoutInputs[snapshot.key] = _prepareLayoutInput(
        snapshot,
        structure,
        structure.sheets,
      );
    }
    check();
    return _scheduler.schedule(
      snapshot,
      priority: budget.priority,
      retainResult: request.retain,
      progressive: request.progressive,
    );
  }

  Future<LayoutSnapshot> _prepareLayoutSnapshot(
    int spine,
    ChapterStructure structure,
    void Function() check,
  ) async {
    final faces = structure.usedBookFonts(_overrides);
    await _fonts.ensure(faces);
    check();
    return _freezeLayout(spine, {
      ...baseStyle.fontFamilies,
      ...style.fontFamilies,
      ...structure.fontFamilies,
      ?_overrides.fontFamily,
      ..._chapterOverlays.familiesFor(spine),
      for (final face in faces) face.family.toLowerCase(),
    }, faces);
  }

  Future<void> _prepareChapterDecoration(int spine, String preparationKey) {
    final preparer = _chapterPreparer;
    if (preparer == null) return Future.value();
    final key = '$spine@$preparationKey:$_preparerEpoch';
    return _preparerTasks.putIfAbsent(
      key,
      () => Future<void>.microtask(() => preparer(spine)),
    );
  }

  LayoutSnapshot _freezeLayout(
    int spine,
    Set<String> families,
    List<CssFontFace> faces,
  ) {
    final fontFaces = List<CssFontFace>.unmodifiable(faces);
    final fonts = _fonts.freezeFor(fontFaces);
    final dependency = fonts.dependency(families);
    return LayoutSnapshot(
      spineIndex: spine,
      key: _paginationKey(spine, dependency),
      contentVersion: _contentVersion,
      generation: _layoutGeneration,
      width: contentWidth,
      height: contentHeight,
      pageHeight: baseContentHeight,
      topInset: _contentTopInset,
      sideInsets: _contentSideInsets,
      baseStyle: baseStyle,
      overrides: _overrides,
      textOverlays: _chapterOverlays.forSpine(spine),
      fontDependency: dependency,
      fonts: fonts,
      fontFamilies: Set.unmodifiable(families),
      fontFaces: fontFaces,
      trimTextEdges: trimTextEdges,
    );
  }

  PreparedChapterLayout _prepareLayoutInput(
    LayoutSnapshot snapshot,
    ChapterStructure structure,
    List<CssStylesheet> sheets,
  ) {
    final imageAnalysis = layout == ReaderContentLayout.fixedPages
        ? structure.fixedFullBleed
        : structure.fullBleed;
    return PreparedChapterLayout(
      snapshot: snapshot,
      document: structure.document,
      selectors: structure.selectors,
      styles: _styles.prepare(sheets, fonts: snapshot.fonts),
      footnotes: structure.footnotes,
      imageAnalysis: imageAnalysis,
      imageCfi: imageAnalysis.singleImageCfi,
      fullPageOptions: FullPageLayoutOptions(
        document.extensionConfig.layout,
        chapterPageFlags(snapshot.spineIndex),
        document.extensionConfig.aspectRatio,
      ),
      traceBook: bookIdForTrace,
    );
  }

  bool _isCurrentSnapshot(LayoutSnapshot snapshot) =>
      !_closed &&
      snapshot.generation == _layoutGeneration &&
      snapshot.contentVersion == _contentVersion &&
      snapshot.width == contentWidth &&
      snapshot.height == contentHeight &&
      snapshot.topInset == _contentTopInset &&
      snapshot.sideInsets == _contentSideInsets &&
      snapshot.overrideFingerprint == _overrideFingerprint &&
      snapshot.typographyFingerprint ==
          _chapterOverlays
              .forSpine(snapshot.spineIndex)
              .typographyFingerprint &&
      _snapshotFontsCurrent(snapshot);

  bool _snapshotFontsCurrent(LayoutSnapshot snapshot) {
    final fonts = _fonts.freezeFor(snapshot.fontFaces);
    return identical(fonts, snapshot.fonts) ||
        snapshot.fontDependency == fonts.dependency(snapshot.fontFamilies);
  }

  void _releaseLayoutInput(LayoutSnapshot snapshot) {
    if (identical(_layoutInputs[snapshot.key]?.snapshot, snapshot)) {
      _layoutInputs.remove(snapshot.key);
    }
  }

  Future<List<PageContent>> _runLayout(
    LayoutSnapshot snapshot,
    LayoutBudget budget,
    bool Function() retainResult,
  ) async {
    budget.check();
    final watch = Stopwatch()..start();
    final cached = _completed.get(snapshot.key, snapshot.fontDependency);
    _traceCache(cached != null && !_completed.requiresReplay(snapshot.key));
    if (cached != null && !_completed.requiresReplay(snapshot.key)) {
      _commitLayout(snapshot, budget, cached, retainResult());
      _traceLayout(ReaderTraceName.pageRenderReuse, watch);
      return cached.pages;
    }
    if (cached != null) _blockCacheHits += 1;
    if (cached == null) _chapterLayoutCount += 1;
    final result = await _rebuildLayout(snapshot, budget, cached);
    _commitLayout(snapshot, budget, result.layout, retainResult());
    _traceLayout(ReaderTraceName.chapterLayout, watch);
    return result.layout.pages;
  }

  Future<ChapterPipelineResult> _rebuildLayout(
    LayoutSnapshot snapshot,
    LayoutBudget budget,
    CompletedChapterLayout? cached,
  ) async {
    final stored = cached == null
        ? await _loadStoredPagination(snapshot, budget)
        : null;
    final result = await _pipeline.run(
      _layoutInputs[snapshot.key]!,
      budget,
      cached: cached,
      pageIndex: stored?.pageIndex,
      onPages: budget.wantsProgressivePages?.call() == true
          ? budget.publishPages
          : null,
    );
    budget.check();
    if (stored?.pageIndex != null &&
        identical(stored!.pageIndex, result.layout.pageIndex)) {
      _storedIndexReplays += 1;
    }
    if (result.indexDiagnostic case final diagnostic?) {
      _logInvalidation(diagnostic, snapshot.key, snapshot.key);
    }
    if (result.warning case final warning?) {
      _layoutWarnings.putIfAbsent(snapshot.spineIndex, () => warning);
    }
    return result;
  }

  Future<ChapterPaginationData?> _loadStoredPagination(
    LayoutSnapshot snapshot,
    LayoutBudget budget,
  ) async {
    if (!_hasStableContentVersion) return null;
    final stored = await _paginationCache.read(snapshot.key);
    budget.check();
    if (stored != null) budget.publishPageCount?.call(stored.pageCount);
    return stored;
  }

  void _rememberPageCount(LayoutSnapshot snapshot, int count) {
    if (_hasStableContentVersion && _isCurrentSnapshot(snapshot)) {
      _paginationCache.rememberCount(snapshot.key, count);
    }
  }

  /// 关闭后已确定结果的文件写入仍可完成，不等待剩余章节排版。
  Future<void> get cacheWritesStopped => _paginationCache.writesStopped;

  void _commitLayout(
    LayoutSnapshot snapshot,
    LayoutBudget budget,
    CompletedChapterLayout layout,
    bool retain,
  ) {
    budget.check();
    if (retain) {
      if (budget.priority == ChapterLayoutPriority.reading) {
        _completed.setCurrent(snapshot.key);
      }
      _completed.put(layout);
      if (_hasStableContentVersion) _paginationCache.rememberLayout(layout);
      _lastSnapshots[snapshot.spineIndex] = snapshot;
    }
  }

  void _traceCache(bool hit) {
    if (!readerTraceEnabled) return;
    ReaderTrace.instance.count(
      hit ? ReaderTraceCounter.pageCacheHit : ReaderTraceCounter.pageCacheMiss,
      bookId: bookIdForTrace,
    );
  }

  void _traceLayout(ReaderTraceName name, Stopwatch watch) {
    if (!readerTraceEnabled) return;
    ReaderTrace.instance.record(
      name,
      watch.elapsedMicroseconds,
      bookId: bookIdForTrace,
    );
  }

  @override
  void cancelPendingLayouts() {
    for (final handle in _waitingLayouts.toList()) {
      handle.cancel();
    }
    _scheduler.cancelWhere((_) => true);
  }

  void _clearViewportStructure() {
    _structures.clear();
    _positions.clearCoordinates();
  }

  @override
  void setCurrentReadingChapter(int spineIndex) {
    _structures.setCurrentReadingChapter(spineIndex, contentWidth);
    final snapshot = _lastSnapshots[spineIndex];
    if (snapshot != null) _completed.setCurrent(snapshot.key);
  }

  @override
  void setBackgroundLayoutPaused(bool paused) =>
      _scheduler.setBackgroundPaused(paused);

  ProgressiveChapterLoadHandle _emptyChapterHandle() => _EmptyChapterHandle();
}

class _EmptyChapterHandle implements ProgressiveChapterLoadHandle {
  @override
  Future<List<PageContent>> get result => Future.value(const []);
  @override
  Future<List<PageContent>> get firstPages => result;
  @override
  List<PageContent> get availablePages => const [];
  @override
  Stream<List<PageContent>> get updates => const Stream.empty();
  @override
  Stream<int> get pageCountUpdates => const Stream.empty();
  @override
  bool get isComplete => true;
  @override
  int get pageCount => 0;
  @override
  ChapterLayoutPriority get priority => ChapterLayoutPriority.background;
  @override
  void setPriority(ChapterLayoutPriority priority) {}
  @override
  void cancel() {}
}
