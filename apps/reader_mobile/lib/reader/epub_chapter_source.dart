import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:reader_core/api.dart' hide ComputedStyle, Paginator;
import 'package:reader_core/css/computed_style.dart';
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
import 'package:reader_ui/reader_session.dart';

import 'bounded_cache.dart';
import 'epub/chapter_positions.dart';
import 'epub/book_resources.dart';
import 'epub/book_fonts.dart';
import 'epub/chapter_styles.dart';
import 'epub/chapter_style_key.dart';
import 'epub/chapter_structure.dart';
import 'epub/container_blocks.dart';
import 'epub/chapter_layout_job.dart';
import 'epub/chapter_preparation_job.dart';
import 'epub/chapter_layout_cache.dart';
import 'epub/chapter_layout_pipeline.dart';
import 'epub/chapter_block_walker.dart';
import 'epub/chapter_text_overlays.dart';
import 'epub/chapter_page_flags.dart';
import 'epub/book_page_counter.dart';
import 'epub/full_page_layout.dart';

export 'epub/chapter_page_flags.dart';

/// 从 EPUB 文档读取章节并提供分页结果。
class EpubChapterSource
    implements
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
        PageCountingChapterSource,
        SpineLayoutDependencyChapterSource,
        ReaderTextOverlaySource {
  EpubChapterSource._({
    required EpubDocumentImpl document,
    required this.baseContentWidth,
    required this.baseContentHeight,
    required this.baseStyle,
    required this.trimTextEdges,
    String? contentVersion,
  }) : _resources = BookResources(document),
       _contentVersion = contentVersion?.trim().isNotEmpty == true
           ? contentVersion!
           : '会话:${++_sessionSequence}';

  static int _sessionSequence = 0;
  String _contentVersion;

  /// 打开 EPUB 并创建来源。
  static Future<EpubChapterSource> open(
    Uint8List bytes, {
    double contentWidth = 320,
    double contentHeight = 480,
    ComputedStyle? style,
    bool verifyCrc = true,
    bool trimTextEdges = true,
    String? contentVersion,
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
  }) async {
    line_breaker.LineBreaker.preserveFractionalLineHeight = true;
    final result = await openEpubFile(file, verifyCrc: verifyCrc);
    return _fromOpenResult(
      result,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      style: style,
      trimTextEdges: trimTextEdges,
      contentVersion: contentVersion,
    );
  }

  static EpubChapterSource _fromOpenResult(
    EpubOpenResult result, {
    required double contentWidth,
    required double contentHeight,
    required ComputedStyle? style,
    required bool trimTextEdges,
    String? contentVersion,
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
    );
  }

  /// 已打开文档。
  final BookResources _resources;
  EpubDocumentImpl get document => _resources.document;

  /// 旧书摘要在首次排版前绑定；已完成纯布局按实际内容版本复用。
  void setContentVersion(String version) {
    if (_closed || version.trim().isEmpty || version == _contentVersion) return;
    _contentVersion = version;
    _layoutGeneration += 1;
    cancelPendingLayouts();
    _syncPageCountLayout();
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
  BookPageCountStore? _pageCountStore;
  BookPageCounter? _pageCounter;
  int? _currentReadingSpine;
  bool _pageCountingRequested = false;
  late final ChapterLayoutScheduler _scheduler = ChapterLayoutScheduler(
    run: _runLayout,
    isCurrent: _isCurrentSnapshot,
    onFinished: _releaseLayoutInput,
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

  /// 兼容同步原文入口；生产打开、跳转和装饰核验先准备目标章。
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
      '|page=$baseContentHeight|top=$_contentTopInset|trim=$trimTextEdges'
      '|spacing=$textSpacingRevision|index=${PageIndex.currentSchemaVersion}'
      '|${_overrides.fingerprint}';

  String get _preparationKey =>
      '$_configurationKey|generation=$_layoutGeneration';

  String get _bookLayoutKey {
    final fonts = _fonts.freeze();
    final families = {
      ...baseStyle.fontFamilies,
      ?_overrides.fontFamily,
      ..._bookTypographyFamilies,
    };
    final typography =
        _bookTypographyFingerprint ?? _chapterOverlays.typographyFingerprint;
    return '$_configurationKey|book=$typography'
        '|font=${fonts.userFontDependency(families)}'
        '|user-fonts=${fonts.userFontEnvironmentDependency}';
  }

  String _paginationKey(int spine, String dependency) =>
      '$_configurationKey|spine=$spine|font=$dependency'
      '|text=${_chapterOverlays.forSpine(spine).typographyFingerprint}';

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

  /// 容器级浮动分组号的起点（W12）：普通块组的 groupId 从 1 起，
  /// 容器浮动组用 [floatGroupBase] + 序号，分页时按组整体占位。

  ComputedStyle? _resolvedBaseStyle;

  /// 文本块样式：同一环境复用书籍样式叠加阅读器覆盖的结果。
  ComputedStyle get style => _resolvedBaseStyle ??= _applyCustomFont(
    _overrides.apply(baseStyle, containingWidth: contentWidth),
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
    if (_bookTypographyFingerprint == null) _syncPageCountLayout();
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
    _syncPageCountLayout();
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
  }) async {
    final previous = (
      width: contentWidth,
      height: contentHeight,
      top: _contentTopInset,
    );
    _viewportContentWidth = math.max(80.0, width);
    _viewportContentHeight = math.max(120.0, height);
    _viewportContentTopInset = math.max(0.0, topInset);
    final next = (
      width: contentWidth,
      height: contentHeight,
      top: _contentTopInset,
    );
    if (previous == next) return false;
    _layoutGeneration += 1;
    _resolvedBaseStyle = null;
    _logInvalidation('viewportSizeChanged', '$previous', '$next');
    cancelPendingLayouts();
    if (previous.width != next.width) _clearViewportStructure();
    _syncPageCountLayout();
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

  /// 注入元数据索引，供缺失元数据与兼容降级回归使用。
  void bindProgressIndex(BookProgressIndex index) =>
      _positions.bindProgressIndex(index);

  @override
  bool isChapterMissing(int spineIndex) => _positions.isMissing(spineIndex);

  @override
  Future<AnchorChapter> loadAnchorChapter(int spineIndex) =>
      scheduleAnchorChapter(spineIndex).result;

  @override
  ReaderPreparationHandle<AnchorChapter> scheduleAnchorChapter(
    int spineIndex,
  ) => mapPreparation(_structures.schedule(spineIndex, contentWidth), (
    structure,
  ) {
    if (_closed) throw const ChapterLoadCancelled();
    return structure.anchor;
  });

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
  ]);

  /// 关闭在途任务和书籍资源；近期缓存只保留不含资源句柄的纯布局。
  void close() {
    if (_closed) return;
    _closed = true;
    _layoutGeneration += 1;
    cancelPendingLayouts();
    _scheduler.close();
    _pageCounter?.close();
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
    final spreadLeft =
        has('page-spread-left') || has('duokan-page-fullscreen-spread-left');
    final spreadRight =
        has('page-spread-right') || has('duokan-page-fullscreen-spread-right');
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
      _structures.synchronously(spineIndex, contentWidth).fullBleed;

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
    _syncPageCountLayout();
  }

  @override
  void setBookTypographyFamilies(Set<String> families) {
    final next = Set<String>.unmodifiable(families);
    if (_bookTypographyFamilies.length == next.length &&
        _bookTypographyFamilies.containsAll(next)) {
      return;
    }
    _bookTypographyFamilies = next;
    _syncPageCountLayout();
  }

  @override
  void setBookTypographyFontAvailability(String family, bool available) {
    if (_fonts.setUserFontAvailability(family, available)) {
      _syncPageCountLayout();
    }
  }

  @override
  ChapterLoadHandle scheduleChapter(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
    bool retainResult = true,
  }) {
    if (!_closed && isChapterMissing(spineIndex)) return _emptyChapterHandle();
    _syncPageCountLayout();
    final key = _preparationKey;
    final preparation = _structures.schedule(
      spineIndex,
      contentWidth,
      priority: priority,
    );
    final handle = PreparingChapterHandle(
      (cancelled) => _prepareAndSchedule(
        spineIndex,
        key,
        cancelled,
        preparation,
        (priority: priority, retain: retainResult),
      ),
      onCancel: preparation.cancel,
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
    ({ChapterLayoutPriority priority, bool retain}) request,
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
      await _prepareChapterDecoration(spine, preparationKey);
      check();
      final snapshot = await _prepareLayoutSnapshot(spine, structure, check);
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
        priority: request.priority,
        retainResult: request.retain,
      );
    } on EpubException catch (error) {
      if (error.code != 'E_SPINE_MISSING') rethrow;
      _positions.markMissing(spine);
      return _emptyChapterHandle();
    } finally {
      preparation.cancel();
    }
  }

  Future<LayoutSnapshot> _prepareLayoutSnapshot(
    int spine,
    ChapterStructure structure,
    void Function() check,
  ) async {
    final faces = _styles.usedBookFonts(
      structure.sheets,
      structure.selectors,
      _overrides,
      contentWidth,
    );
    await _fonts.ensure(faces);
    check();
    return _freezeLayout(spine, {
      ...baseStyle.fontFamilies,
      ...style.fontFamilies,
      ...structure.fontFamilies,
      ?_overrides.fontFamily,
      ..._chapterOverlays.familiesFor(spine),
      for (final face in faces) face.family.toLowerCase(),
    });
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

  LayoutSnapshot _freezeLayout(int spine, Set<String> families) {
    final fonts = _fonts.freeze();
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
      baseStyle: baseStyle,
      overrides: _overrides,
      textOverlays: _chapterOverlays.forSpine(spine),
      fontDependency: dependency,
      fonts: fonts,
      fontFamilies: Set.unmodifiable(families),
      trimTextEdges: trimTextEdges,
    );
  }

  PreparedChapterLayout _prepareLayoutInput(
    LayoutSnapshot snapshot,
    ChapterStructure structure,
    List<CssStylesheet> sheets,
  ) {
    final imageAnalysis =
        FullPageChapterLayout.isFixedLike(document.extensionConfig.layout)
        ? structure.fixedFullBleed
        : structure.fullBleed;
    return PreparedChapterLayout(
      snapshot: snapshot,
      document: structure.document,
      selectors: structure.selectors,
      styles: _styles.prepare(sheets),
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
      snapshot.overrideFingerprint == _overrideFingerprint &&
      snapshot.typographyFingerprint ==
          _chapterOverlays
              .forSpine(snapshot.spineIndex)
              .typographyFingerprint &&
      _snapshotFontsCurrent(snapshot);

  bool _snapshotFontsCurrent(LayoutSnapshot snapshot) {
    final fonts = _fonts.freeze();
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
    final input = _layoutInputs[snapshot.key]!;
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
    final result = await _pipeline.run(input, budget, cached: cached);
    budget.check();
    if (result.indexDiagnostic case final diagnostic?) {
      _logInvalidation(diagnostic, snapshot.key, snapshot.key);
    }
    if (result.warning case final warning?) {
      _layoutWarnings.putIfAbsent(snapshot.spineIndex, () => warning);
    }
    _commitLayout(snapshot, budget, result.layout, retainResult());
    _traceLayout(ReaderTraceName.chapterLayout, watch);
    return result.layout.pages;
  }

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
      _lastSnapshots[snapshot.spineIndex] = snapshot;
    }
    if (budget.priority != ChapterLayoutPriority.pageCount) {
      _ensurePageCounter().recordChapter(
        _bookLayoutKey,
        snapshot.spineIndex,
        layout.pages.length,
      );
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

  /// 存储在首屏前绑定；订阅器和进行中的计页状态保持同一所有者。
  void setPageCountStore(BookPageCountStore store) {
    _pageCountStore = store;
    final counter = _pageCounter;
    if (counter != null) unawaited(counter.bindStore(store));
  }

  Future<void> flushPageCounts() async => _pageCounter?.flush();

  BookPageCounter _ensurePageCounter() {
    final existing = _pageCounter;
    if (existing != null) return existing;
    final counter = _pageCounter = BookPageCounter(
      chapterCount: chapterCount,
      isMissing: isChapterMissing,
      store: _pageCountStore,
      schedule: (spine) => scheduleChapter(
        spine,
        priority: ChapterLayoutPriority.pageCount,
        retainResult: false,
      ),
    );
    unawaited(counter.useLayout(_bookLayoutKey));
    counter.setActive(_pageCountingRequested && _currentReadingSpine != null);
    return counter;
  }

  void _syncPageCountLayout() {
    final counter = _pageCounter;
    if (counter != null && !_closed) {
      final next = _bookLayoutKey;
      unawaited(counter.useLayout(next));
      _recordValidCachedCounts(counter, next);
    }
  }

  void _recordValidCachedCounts(BookPageCounter counter, String layoutKey) {
    for (final layout in _completed.entries) {
      final snapshot = _lastSnapshots[layout.spineIndex];
      if (snapshot == null ||
          snapshot.key != layout.key ||
          !_isCurrentSnapshot(snapshot) ||
          _completed.requiresReplay(layout.key)) {
        continue;
      }
      counter.recordChapter(layoutKey, layout.spineIndex, layout.pages.length);
    }
  }

  @override
  ValueListenable<BookPageCountState> get pageCountState =>
      _ensurePageCounter().state;

  @override
  void setPageCountingActive(bool active) {
    _pageCountingRequested = active;
    _ensurePageCounter().setActive(active && _currentReadingSpine != null);
  }

  @override
  void setCurrentReadingChapter(int spineIndex) {
    _currentReadingSpine = spineIndex;
    final snapshot = _lastSnapshots[spineIndex];
    if (snapshot != null) _completed.setCurrent(snapshot.key);
    _ensurePageCounter().setActive(_pageCountingRequested);
  }

  ChapterLoadHandle _emptyChapterHandle() => _EmptyChapterHandle();
}

class _EmptyChapterHandle implements ChapterLoadHandle {
  @override
  Future<List<PageContent>> get result => Future.value(const []);
  @override
  void cancel() {}
}
