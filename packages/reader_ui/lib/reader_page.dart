import 'dart:async';

import 'package:flutter/material.dart';

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:reader_core/api.dart' hide ComputedStyle;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart' show TableCellRender;
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/paint/paragraph_cache.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/layout/line_breaker.dart' show TextLayoutResult;

import 'annotations/annotation.dart';
import 'annotations/annotation_editor_sheet.dart';
import 'annotations/annotation_layer.dart';
import 'annotations/decorations.dart';
import 'annotations/note_composer_sheet.dart';
import 'annotations/mark_settings.dart';
import 'decorations/decoration.dart';
import 'decorations/decoration_editor_sheet.dart';
import 'decorations/decoration_geometry.dart';
import 'decorations/decoration_image_store.dart';
import 'decorations/decoration_image_codec.dart';
import 'decorations/decoration_painter.dart';
import 'decorations/decoration_relocator.dart';
import 'decorations/decoration_rule_engine.dart';
import 'decorations/decoration_rule_page.dart';
import 'decorations/decoration_rules.dart';
import 'a11y/semantics_layer.dart';
import 'footnote_dialog.dart';
import 'gallery/reader_gallery_controls.dart';
import 'image_preview_page.dart';
import 'menu/reader_menu_overlay.dart';
import 'panels/margin_editor.dart';
import 'panels/tap_zone_editor.dart';
import 'page_furniture/page_furniture.dart';
import 'page_furniture/corner_row.dart'
    show ReaderBatteryStatus, readerBatteryStatus;
import 'theme/reader_margins.dart';
import 'tap_zones.dart';
import 'annotations/relocator.dart';
import 'panels/annotation_panel.dart';
import 'panels/bookmark_panel.dart';
import 'panels/search_panel.dart';
import 'panels/settings_panel.dart';
import 'panels/decoration_panel.dart';
import 'panels/mark_settings_sheet.dart';
import 'theme/reader_background.dart';
import 'theme/reader_drawer_style.dart';
import 'page_furniture/corner_info.dart';
import 'theme/reader_environment.dart';
import 'theme/reader_panel_theme.dart';
import 'selection/selection.dart';
import 'selection/selection_menu.dart';
import 'selection/selection_support.dart';
import 'selection/text_range_geometry.dart';
import 'selection/selection_layer.dart';
import 'panels/toc_panel.dart';
import 'reader_session.dart';
import 'reader_view.dart';
import 'paging/continuous_scroll_view.dart';
import 'paging/page_turn_mode.dart';
import 'paging/page_turn_view.dart';
import 'theme/reader_theme.dart';
import 'loading_skeleton.dart';

part 'reader_annotation_controller.dart';
part 'reader_decoration_controller.dart';
part 'reader_decoration_actions.dart';
part 'reader_gallery_controller.dart';
part 'reader_image_assets.dart';

const MethodChannel _readerPlatformChannel = MethodChannel(
  'com.spectacular.reader_mobile/reader',
);

/// 正式引擎命中的文本位置；原文解析与写入由宿主编辑会话负责。
class ReaderEditTarget {
  const ReaderEditTarget({
    required this.spineIndex,
    required this.cfi,
    this.contentRevision,
  });

  final int spineIndex;
  final String cfi;
  final String? contentRevision;
}

/// 最小可运行的阅读页：打开、分页、绘制、翻页与进度恢复。
class ReaderPage extends StatefulWidget {
  /// 创建阅读页。
  const ReaderPage({
    super.key,
    required this.source,
    required this.store,
    required this.bookId,
    this.contentRevision,
    this.background = const Color(0xFFFFFFFF),
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    this.bookmarks,
    this.annotations,
    this.decorations,
    this.decorationRules,
    this.decorationImages,
    this.markSettings = const ReaderMarkSettings(),
    this.onMarkSettingsChanged,
    this.onOverridesChanged,
    this.onThemeChanged,
    this.customTheme,
    this.backgroundImageLoader,
    this.onPickBackgroundImage,
    this.customFonts = const [],
    this.onPickFont,
    this.onLoadFont,
    this.onRenameFont,
    this.onRemoveFont,
    this.backgroundId = 'none',
    this.inkMode = false,
    this.onBackgroundChanged,
    this.onInkModeChanged,
    this.onSearch,
    this.onSessionReady,
    this.onBookEnd,
    this.editMode = false,
    this.onEditTarget,
    this.onOpenEditor,
    this.imageCache,
    this.theme,
    this.overrides,
    this.paragraphCache,
    this.showPageFooter = true,
    this.cornerInfo = ReaderCornerInfo.defaults,
    this.onCornerInfoChanged,
    this.bookTitle = '阅读',
    this.margins,
    this.onMarginsChanged,
    this.tapZones = ReaderTapZones.defaults,
    this.onTapZonesChanged,
    this.onLog,
    this.onResolveSearchCfi,
    this.onSearchStream,
    this.pageTurnMode = PageTurnMode.cover,
    this.onPageTurnModeChanged,
    this.keepScreenOn = false,
    this.onKeepScreenOnChanged,
    this.volumeKeyPaging = false,
    this.onVolumeKeyPagingChanged,
  });

  /// 编辑预览中单击正文直接请求编辑；普通阅读仍保留翻页和脚注语义。
  final bool editMode;
  final ValueChanged<ReaderEditTarget>? onEditTarget;
  final VoidCallback? onOpenEditor;

  /// 章节页来源。
  final ReaderChapterSource source;

  /// 书签存储（P4-13）；为 null 时菜单不显示书签入口。
  final ReaderBookmarkStore? bookmarks;

  /// 阅读划线与想法存储。
  final ReaderAnnotationStore? annotations;

  /// 手工装饰存储，不混入标注列表。
  final ReaderDecorationStore? decorations;

  /// 本书和全局自动装饰规则。
  final ReaderDecorationRuleStore? decorationRules;

  /// 宿主装饰图片存储。
  final ReaderDecorationImageStore? decorationImages;

  /// 划线快捷设置及其持久化回调。
  final ReaderMarkSettings markSettings;
  final ValueChanged<ReaderMarkSettings>? onMarkSettingsChanged;

  /// 排版设置变化（P4-21）：调用方负责持久化。
  final ValueChanged<ReaderOverrides>? onOverridesChanged;

  /// 主题变化（P4-21）：调用方负责持久化。
  final ValueChanged<String>? onThemeChanged;

  /// 上次保存的自定义主题。
  final ReaderTheme? customTheme;

  /// 宿主提供图片数据，UI 不访问文件系统。
  final Future<Uint8List> Function(String id)? backgroundImageLoader;

  /// 宿主选择并复制图片，取消返回 null。
  final Future<String?> Function()? onPickBackgroundImage;

  /// 宿主已保存的字体。
  final List<ReaderFontOption> customFonts;

  /// 宿主导入并注册字体，取消返回 null。
  final Future<ReaderFontOption?> Function()? onPickFont;

  /// 使用已保存字体前，宿主负责注册字体。
  final Future<void> Function(String family)? onLoadFont;
  final Future<ReaderFontOption> Function(String family, String name)?
  onRenameFont;
  final Future<void> Function(String family)? onRemoveFont;

  /// 初始背景 id（P4-22）。
  final String backgroundId;

  /// 墨水屏模式（P4-23）：纯黑白、背景禁用、高亮改下划线。
  final bool inkMode;

  /// 墨水屏开关变化。
  final ValueChanged<bool>? onInkModeChanged;

  /// 搜索回调（P4-26）；为 null 时菜单不显示搜索入口。
  final Future<List<SearchPanelResult>> Function(String query)? onSearch;

  /// 背景变化（P4-22）：调用方负责持久化。
  final ValueChanged<String>? onBackgroundChanged;

  /// 进度存储。
  final ReaderProgressStore store;

  /// 书籍标识。
  final String bookId;

  /// 原 EPUB 文件摘要；当前内容锚点的解释版本。
  final String? contentRevision;

  /// 页面背景。
  final Color background;

  /// 正文区外边距。
  final EdgeInsets padding;

  /// 是否显示页眉页脚。
  final bool showPageFooter;
  final ReaderCornerInfo cornerInfo;
  final ValueChanged<ReaderCornerInfo>? onCornerInfoChanged;

  /// 书名（菜单顶部栏显示）。
  final String bookTitle;

  /// 页边距（P8-10 边距调节器）；为 null 时用 padding + 系统安全区。
  final ReaderMargins? margins;

  /// 页边距变化（调节器「保留」时回调，调用方持久化）。
  final ValueChanged<ReaderMargins>? onMarginsChanged;

  /// 九宫格点击区域配置。
  final ReaderTapZones tapZones;

  /// 九宫格点击区域变化（编辑页「保留」时回调，调用方持久化）。
  final ValueChanged<ReaderTapZones>? onTapZonesChanged;

  /// 诊断日志回调（用户操作与耗时，由 app 层写入 ReaderLog）。
  final void Function(String event, Map<String, Object?> fields)? onLog;

  /// 点开搜索命中时才解析 CFI（搜索阶段不算，避免逐条排版）。
  final Future<String?> Function(SearchPanelResult result)? onResolveSearchCfi;

  /// 流式搜索（逐章推送结果）。
  final Stream<SearchProgress> Function(String query)? onSearchStream;

  /// 翻页方式；独立于排版覆盖，不参与正文布局指纹。
  final PageTurnMode pageTurnMode;
  final ValueChanged<PageTurnMode>? onPageTurnModeChanged;

  /// 阅读时保持屏幕常亮。
  final bool keepScreenOn;

  /// 屏幕常亮开关变化（调用方持久化）。
  final ValueChanged<bool>? onKeepScreenOnChanged;

  /// 用音量键翻页。
  final bool volumeKeyPaging;

  /// 音量键翻页开关变化（调用方持久化）。
  final ValueChanged<bool>? onVolumeKeyPagingChanged;

  /// 会话就绪回调（测试/调试）。
  final ValueChanged<ReaderSession>? onSessionReady;

  final void Function(ReaderSession session, bool rtl)? onBookEnd;

  /// 图片解码缓存（可选）；传入后背景图按需解码并触发重绘。
  final DecodedImageCache? imageCache;

  /// 阅读主题（可选）：背景色与正文色成对定义（P2-23）。
  final ReaderTheme? theme;

  /// 阅读器设置覆盖（可选）：字号/行高/对齐/页边距（P2-22/P2-24）。
  final ReaderOverrides? overrides;

  /// 行段落缓存（可选）：注入后重排会清空旧段落（P2-30）。
  final ParagraphCache? paragraphCache;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  late final ReaderSession _session;
  String? _reportedProgressSaveMessage;
  late final ParagraphCache _paragraphCache =
      widget.paragraphCache ?? ParagraphCache(maxEntries: 128);
  late final bool _ownsParagraphCache = widget.paragraphCache == null;
  late PagePainter _painter = _buildPainter();
  final Map<String, ({int index, String? anchor, int generation})>
  _gallerySelections = {};
  final _galleryPositions = <String, double>{};
  final _galleryRepaint = ValueNotifier(0);

  /// 当前排版设置（P4-21：设置面板可改，初始来自 widget.overrides）。
  late ReaderOverrides _overrides;

  /// 当前主题（P4-21：设置面板可切）。
  late ReaderTheme? _theme;

  /// 当前背景（P4-22）：纹理解码结果缓存在这里，换背景不重排。
  late String _backgroundId;
  ui.Image? _backgroundImage;
  int _backgroundRequest = 0;
  bool _pickingBackgroundImage = false;
  late ReaderTheme? _customTheme = widget.customTheme;
  late List<ReaderFontOption> _customFonts = List.of(widget.customFonts);
  late ReaderCornerInfo _cornerInfo = widget.cornerInfo;

  double get _headerHeight => widget.showPageFooter && _cornerInfo.hasHeader
      ? PageFurniture.headerHeight
      : 0;
  double get _footerHeight => widget.showPageFooter && _cornerInfo.hasFooter
      ? PageFurniture.footerHeight
      : 0;

  /// 墨水屏模式（P4-23）：为 true 时强制纯黑白主题、禁用背景纹理。
  late bool _inkMode;
  late PageTurnMode _pageTurnMode = widget.pageTurnMode;
  final _pageTurnKey = GlobalKey<PageTurnViewState>();
  final _scrollKey = GlobalKey<ContinuousScrollViewState>();

  PageTurnMode get _effectiveTurnMode {
    // 连续滚动是阅读布局，不是翻页动画。墨水屏/减少动画只应关闭动画型
    // 翻页，不能把连续滚动一并降级成无动画分页。
    if (_pageTurnMode == PageTurnMode.scroll) {
      return PageTurnMode.scroll;
    }
    return _inkMode || MediaQuery.disableAnimationsOf(context)
        ? PageTurnMode.none
        : _pageTurnMode;
  }

  bool get _readingRtl {
    final style = _session.page?.slices.firstOrNull?.block.style;
    return style?.values['direction'] == 'rtl' ||
        style?.writingMode == CssWritingMode.verticalRl;
  }

  /// 记录一条诊断日志（无回调时忽略）。
  void _log(String event, [Map<String, Object?> fields = const {}]) {
    widget.onLog?.call(event, fields);
  }

  /// 缓存的安全区高度：只在首帧取一次，系统栏显隐不改变它。
  ///
  /// 菜单是浮层，开关时不能改 padding —— 否则 viewPadding 变化会触发重排。
  double? _cachedSafeTop;
  double? _cachedSafeBottom;

  /// 顶部安全区（缓存值）。
  double get _safeTop =>
      _cachedSafeTop ??= MediaQuery.maybeViewPaddingOf(context)?.top ?? 0;

  /// 底部安全区（缓存值）。
  double get _safeBottom =>
      _cachedSafeBottom ??= MediaQuery.maybeViewPaddingOf(context)?.bottom ?? 0;

  /// 是否在边距调节器里（全屏编辑态，压在菜单之上）。
  bool _editingMargins = false;

  /// 保存或取消的最后一次重排完成前阻止翻章，避免旧分页覆盖导航结果。
  bool _finishingMarginEdit = false;

  /// 是否在九宫格点击区域编辑页。
  bool _editingTapZones = false;

  /// 当前九宫格点击区域配置。
  late ReaderTapZones _tapZones = widget.tapZones;

  /// 调节器正文预览：拖动时合并重排，保存前不写入设置和阅读进度。
  ReaderMargins? _previewMargins;
  ReaderMargins? _pendingMarginPreview;
  Timer? _marginPreviewTimer;
  bool _draggingMargins = false;

  /// 已保存的页边距：取消预览时恢复。
  ReaderMargins? _savedMargins;

  /// 从基础 padding 生成调节器值，保证打开调节器时画面不跳。
  ReaderMargins _marginsFromPadding(EdgeInsets padding) {
    return ReaderMargins(
      left: padding.left,
      right: padding.right,
      topOuter: padding.top,
      topInner: _headerHeight > 0 ? PageFurniture.headerGap : 0,
      bottomInner: _footerHeight > 0 ? PageFurniture.footerGap : 0,
      bottomOuter: padding.bottom,
    );
  }

  /// 当前生效的页边距（未设置时按实际安全区 + padding 推导）。
  ReaderMargins get _activeMargins =>
      _previewMargins ??
      _savedMargins ??
      _marginsFromPadding(_fallbackPadding());

  /// 首次进入阅读页时的默认边距，恢复默认后仍保持原排版。
  ReaderMargins get _defaultMargins => _marginsFromPadding(_fallbackPadding());

  ReaderMargins? get _layoutMargins => _previewMargins ?? _savedMargins;

  /// 菜单是否展开（设计稿沉浸式菜单）。
  bool _menuOpen = false;

  /// 当前打开的抽屉。
  ReaderMenuEntry? _drawer;

  /// 目录抽屉里的二级页签（目录/书签/标注/装饰/搜索）。
  _DrawerTab _drawerTab = _DrawerTab.content;

  /// 是否有浮层压在正文之上：此时系统返回键只关闭浮层，不退出阅读页。
  bool get _hasOverlayOpen =>
      _editingMargins ||
      _editingTapZones ||
      _menuOpen ||
      _drawer != null ||
      _selection != null;

  /// 已聚焦过的页（P4-28：每页只自动聚焦一次）。
  String? _lastFocusedPageKey;

  /// 新页首块焦点（P4-28）：翻页后把焦点落到第一块，读屏/键盘续读不跳段。
  final FocusNode _semanticsFirstFocus = FocusNode(
    debugLabel: 'reader-first-block',
  );

  /// 搜索命中的临时高亮（P4-26，§29.4：3 秒后消失）。
  ReaderAnnotation? _tempHighlight;
  Timer? _tempHighlightTimer;
  int _searchRequest = 0;

  /// 当前阅读环境（P4-23）。
  ReaderEnvironment get _environment => ReaderEnvironment(isEink: _inkMode);

  /// 生效主题（墨水屏强制纯黑白，P4-23）。
  ReaderTheme? get _effectiveTheme {
    final theme = _theme;
    if (theme == null) {
      return null;
    }
    return _environment.resolveTheme(theme);
  }

  PagePainter _buildPainter() {
    final theme = _effectiveTheme;
    return PagePainter(
      background: theme?.background ?? widget.background,
      pageBackgroundImage: _environment.allowsBackgroundImage
          ? _backgroundImage
          : null,
      pageBackgroundImageTint: ReaderBackground.byId(_backgroundId).tint,
      pageBackgroundImageCover: ReaderBackground.byId(_backgroundId).isImage,
      pageBackgroundImageOpacity: ReaderBackground.byId(_backgroundId).isImage
          ? 0.18
          : 0.10,
      imageLookup: widget.imageCache?.lookup,
      listMarkerImageOf: (block) => block.style?.listStyleImage,
      textColor: theme?.text,
      inkMode: _inkMode,
      paragraphCache: _paragraphCache,
      textOverlays: _textOverlays,
      beforeBlockText: _paintDecorationsBeforeText,
      galleryFrameOf: _galleryFrameOf,
      galleryPositionOf: (gallery) => _galleryPositions[gallery.cfi],
    );
  }

  /// 设置与主题合并后的有效覆盖（主题补正文/背景色，设置优先）。
  ReaderOverrides _effectiveOverrides() {
    final base = _overrides;
    final theme = _theme;
    if (theme == null) {
      return base;
    }
    return base.copyWith(
      textColor: base.textColor ?? theme.text,
      backgroundColor: base.backgroundColor ?? theme.background,
    );
  }

  /// 页边距：设置优先，其次 ReaderPage.padding。
  EdgeInsets _fallbackPadding() {
    final edges = _overrides.padding;
    final base = edges == null
        ? widget.padding
        : EdgeInsets.fromLTRB(edges.left, edges.top, edges.right, edges.bottom);
    // 用缓存值而不是实时 MediaQuery —— 菜单开关、系统栏显隐都不该改排版。
    final topInset = _safeTop;
    final bottomInset = _safeBottom;
    if (topInset <= 0 && bottomInset <= 0) {
      return base;
    }
    return base + EdgeInsets.only(top: topInset, bottom: bottomInset);
  }

  EdgeInsets _effectivePadding() {
    // 设置里显式给了页边距（含安全区两段）时直接用它：边距调节器允许把
    // 上下外段调到 0，让正文铺进安全区，所以这里不能再叠加 viewPadding。
    final margins = _layoutMargins;
    if (margins != null) {
      return margins.toPadding();
    }
    return _fallbackPadding();
  }

  /// 页眉页脚外侧 padding：外段从屏幕边界排到页家具，内段不参与。
  EdgeInsets _furniturePadding() {
    final margins = _layoutMargins;
    if (margins != null) {
      return margins.toOuterPadding();
    }
    return _effectivePadding();
  }

  /// 正文区 padding：外段 + 页眉页脚高度 + 内段。
  EdgeInsets _bodyPadding() {
    final margins = _layoutMargins;
    if (margins != null) {
      return margins.toBodyPadding(
        showFurniture: widget.showPageFooter,
        headerHeight: _headerHeight,
        footerHeight: _footerHeight,
      );
    }
    final base = _effectivePadding();
    if (!widget.showPageFooter) {
      return base;
    }
    return base +
        EdgeInsets.only(
          top: _headerHeight > 0 ? _headerHeight + PageFurniture.headerGap : 0,
          bottom: _footerHeight > 0
              ? _footerHeight + PageFurniture.footerGap
              : 0,
        );
  }

  /// 整页背景图页（封面/扉页）：整页只有一块背景图，页脚为图片让位。
  bool _isFullPageBackground(PageContent page) {
    if (page.slices.length != 1) {
      return false;
    }
    final block = page.slices.first.block;
    if (block.layout.text.isNotEmpty || block.inlineImages.isNotEmpty) {
      return false;
    }
    final background = block.style?.values['background-image'];
    return (background != null && background.isNotEmpty) &&
        block.bleedLeft &&
        block.bleedRight;
  }

  /// 章标题：目录里有就用目录名，否则退回「第 N 章」。
  String _chapterTitleOf(int spineIndex) {
    final source = widget.source;
    if (source is TocChapterSource) {
      final title = _tocTitleForSpine(source.toc, spineIndex);
      if (title != null) {
        return title;
      }
    }
    return '第 ${spineIndex + 1} 章';
  }

  /// 指定纸面占全书的比例（0..1），与当前会话所在页无关。
  ///
  /// EPUB 源按同一套章节权重与原文位置计算；普通源或旧数据没有比例时，
  /// 才退回按章/页估算，避免两套口径写回同一个进度字段。
  double _bookProgressOf(PageContent page) {
    final positioned = _session.readingPercentOf(page);
    if (positioned != null) return positioned.clamp(0.0, 1.0);
    final chapters = widget.source.chapterCount;
    if (chapters <= 0) {
      return 0;
    }
    final pagesInChapter = _session.pageCountOf(page.spineIndex);
    final within = pagesInChapter <= 0
        ? 0.0
        : (page.pageIndex + 1) / pagesInChapter;
    return ((page.spineIndex + within) / chapters).clamp(0.0, 1.0);
  }

  /// 已预取过的页键（spine*100000 + pageIndex）。
  ///
  /// 连续滚动会同时构建多页，不能只记当前页，否则下一屏的插图在进入
  /// 可视区时仍未解码，只能看到空框。保留最近若干页，页离开缓存后再次
  /// 构建时仍可补取。
  final Set<int> _prefetchedPageKeys = <int>{};
  static const int _prefetchedPageLimit = 32;
  Object? _imagePage;

  /// 图片缓存版本号，解码完成后触发重绘。
  int _imageRevision = 0;

  /// 上一次布局的正文区尺寸（旋转/窗口变化检测，P2-31）。
  Size? _lastContentSize;
  double? _lastContentTopInset;
  ContentSideInsets? _lastContentSideInsets;
  bool? _lastContentSizePreview;
  Future<void>? _initialOpen;
  bool _approximateNoticeShown = false;

  /// 预取页内图片；解码完成后 setState，占位替换为真图。
  ///
  /// [notify] 为 false 时只等待解码，不更新图片版本。翻页快照需要图片已
  /// 就绪，但版本变化会触发 PageTurnView 清空快照并取消进行中的手势。
  Future<void> _prefetchPageImages(
    PageContent page,
    double displayWidth, {
    bool notify = true,
    bool includeAdjacent = false,
    bool includeGalleryAdjacent = true,
  }) async {
    final cache = widget.imageCache;
    if (cache == null) return;
    final assets = _PageImageAssets(
      _galleryFrameOf,
      includeGalleryAdjacent: includeGalleryAdjacent,
      pageWidth: displayWidth,
    );
    for (final candidate in [
      page,
      if (includeAdjacent) ..._session.adjacentPages,
    ]) {
      assets.addPage(candidate, required: identical(candidate, _session.page));
    }
    if (identical(page, _session.page)) {
      cache.protectedUrls = assets.requiredUrls;
    }
    await _prefetchPageAssets(assets, page, displayWidth, notify: notify);
  }

  Future<void> _prefetchPageAssets(
    _PageImageAssets assets,
    PageContent page,
    double displayWidth, {
    required bool notify,
  }) async {
    final cache = widget.imageCache!;
    if (assets.urls.isEmpty) return;
    final before = cache.revision;
    final presentingSnapshot =
        _pageTurnKey.currentState?.isPresentingSnapshot(page) ?? false;
    final missingVisible = {
      for (final url in assets.requiredUrls)
        if (cache.lookup(url) == null) url,
    };
    await _loadPageAssets(assets, displayWidth);
    if (!notify || !mounted || cache.revision == before) {
      return;
    }
    // 邻页和相邻分帧的解码不改变当前纸面，不能清空已预热的翻页快照。
    if (_effectiveTurnMode != PageTurnMode.scroll &&
        (presentingSnapshot ||
            !identical(page, _session.page) ||
            !missingVisible.any((url) => cache.lookup(url) != null))) {
      return;
    }
    setState(() => _imageRevision = cache.revision);
  }

  Future<void> _loadPageAssets(
    _PageImageAssets assets,
    double displayWidth,
  ) async {
    final cache = widget.imageCache!;
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    for (final url in [
      ...assets.requiredUrls,
      ...assets.urls.difference(assets.requiredUrls),
    ]) {
      await cache.load(
        url,
        displayWidth: assets.displayWidths[url] ?? displayWidth,
        devicePixelRatio: ratio,
      );
    }
  }

  /// 翻页快照前准备目标页图片；不触发版本失效，避免取消当前手势。
  Future<void> _prepareTurnPageImages(PageContent page) {
    final width = _lastContentSize?.width ?? 0;
    if (width <= 0) {
      return Future<void>.value();
    }
    return _prefetchPageImages(
      page,
      width,
      notify: false,
      includeGalleryAdjacent: false,
    );
  }

  /// 尺寸变化（旋转/窗口缩放）时通知会话重排并恢复位置（P2-31）。
  void _scheduleContentSize(Size pageSize) {
    final padding = _bodyPadding();
    final sideInsets = (left: padding.left, right: padding.right);
    final preview = _editingMargins;
    final content = Size(
      pageSize.width - padding.horizontal,
      pageSize.height - padding.vertical,
    );
    if (content.width <= 0 || content.height <= 0) {
      return;
    }
    if (_lastContentSize == content &&
        _lastContentTopInset == padding.top &&
        _lastContentSideInsets == sideInsets &&
        _lastContentSizePreview == preview) {
      return;
    }
    _lastContentSize = content;
    _lastContentTopInset = padding.top;
    _lastContentSideInsets = sideInsets;
    _lastContentSizePreview = preview;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyContentSize(content, padding, preview);
    });
  }

  void _applyContentSize(Size content, EdgeInsets padding, bool preview) {
    final sideInsets = (left: padding.left, right: padding.right);
    final opening = _initialOpen;
    if (opening == null) {
      _initialOpen = _session
          .open(
            overrides: _effectiveOverrides(),
            contentWidth: content.width,
            contentHeight: content.height,
            contentTopInset: padding.top,
            contentSideInsets: sideInsets,
          )
          .then((_) {
            if (mounted &&
                !_approximateNoticeShown &&
                _session.approximateRestoration) {
              _approximateNoticeShown = true;
              _showToast('阅读位置已近似恢复');
            }
          });
      return;
    }
    unawaited(
      opening.then((_) async {
        if (!mounted) return;
        await _session.applyContentSize(
          width: content.width,
          height: content.height,
          topInset: padding.top,
          sideInsets: sideInsets,
          preview: preview,
        );
        if (mounted && !preview && _finishingMarginEdit) {
          setState(() => _finishingMarginEdit = false);
        }
      }),
    );
  }

  void _schedulePrefetch(PageContent page, double displayWidth) {
    final key = page.spineIndex * 100000 + page.pageIndex;
    if (identical(page, _session.page)) {
      final current = (page, _session.readingCfi);
      if (_imagePage != current) {
        _imagePage = current;
        // 回到已访问页或同页 CFI 跳转时，也要恢复当前可见图片的保护集合。
        _prefetchedPageKeys.remove(key);
      }
    }
    if (!_prefetchedPageKeys.add(key)) {
      return;
    }
    if (_prefetchedPageKeys.length > _prefetchedPageLimit) {
      _prefetchedPageKeys.remove(_prefetchedPageKeys.first);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prefetchPageImages(
          page,
          displayWidth,
          includeAdjacent:
              _effectiveTurnMode == PageTurnMode.scroll ||
              _effectiveTurnMode == PageTurnMode.none,
        );
      }
    });
  }

  /// 当前页选区（P4-15）；翻页/点菜单时清除。
  ReaderSelection? _selection;
  int? _selectionLayoutRevision;

  bool get _selectionMatchesLayout =>
      _selectionLayoutRevision == _session.layoutRevision;

  /// 连续滚动长按命中的页片段；分页模式保持为空。
  PageContent? _selectionPage;

  /// 笔记编辑层打开时隐藏选区菜单，避免菜单悬在遮罩后方。
  bool _hideSelectionMenu = false;

  /// 全书标注（P4-18）：打开时加载，标注变更后刷新。
  List<ReaderAnnotation> _annotations = const <ReaderAnnotation>[];

  late ReaderMarkSettings _markSettings = widget.markSettings;
  List<ReaderDecoration> _decorations = const [];
  List<ReaderDecoration> _resolvedDecorations = const [];
  final Map<int, List<ReaderDecoration>> _manualDecorationsByChapter = {};
  final Map<(int, int), Future<bool>> _chapterDecorationPreparations = {};
  final Map<String, Future<void>> _decorationFontLoads = {};
  final Set<String> _loadedDecorationFonts = {};
  Future<bool>? _decorationStoresTask;
  List<ReaderDecorationRuleGroup> _decorationGroups = const [];
  List<ReaderDecorationRule> _decorationRules = const [];
  final _ruleEngine = ReaderDecorationRuleEngine();
  final Map<int, List<ReaderDecorationRuleMatch>> _chapterRuleMatches = {};
  final Map<String, ui.Image> _decorationImages = {};
  final Map<String, ReaderDecorationNineSlice> _decorationNineSlices = {};
  final Set<String> _missingDecorationImages = {};
  final Set<String> _unavailableDecorationFonts = {};
  int _decorationGeneration = 0;
  final Map<int, int> _decorationScheduledChapters = {};
  bool _decorationLoading = false;
  ReaderDecoration? _relocatingDecoration;
  bool _selectionMore = false;
  double _paperContentWidth = 0;

  void _changeReaderState(VoidCallback change) => setState(change);

  ReaderAnnotation? _relocatingAnnotation;
  ReaderBookmark? _relocatingBookmark;
  bool _relocationBusy = false;

  /// 可绘制的标注（P4-20：重定位后；失效标注保留数据但不绘制）。
  List<ReaderAnnotation> _resolvedAnnotations = const <ReaderAnnotation>[];
  final Map<int, List<ReaderAnnotation>> _annotationsByChapter = {};
  final Map<int, int> _annotationScheduledChapters = {};
  int _annotationGeneration = 0;

  /// 选区所属章（跨页选区跨翻页时不清，翻章才清）。
  int? _selectionSpineIndex;

  /// 边缘翻页去抖定时器（§63.5：300ms）。
  Timer? _selectionEdgeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _savedMargins = widget.margins;
    _overrides = widget.overrides ?? ReaderSettingsDefaults.overrides;
    _theme = widget.theme;
    _backgroundId = widget.backgroundId;
    _inkMode = widget.inkMode;
    _readerPlatformChannel.setMethodCallHandler(_handlePlatformCall);
    _syncPlatformSettings();
    unawaited(_loadBackground(_backgroundId));
    // 沉浸模式（P8-10 收尾）：阅读页隐藏状态栏与导航栏，退出时恢复。
    // sticky：边缘下滑可临时唤出系统栏，几秒后自动隐藏。
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    _session = ReaderSession(
      source: widget.source,
      store: widget.store,
      bookId: widget.bookId,
      contentRevision: widget.contentRevision,
      autoFinish: widget.onBookEnd == null,
    );
    _session.addListener(_reportProgressSaveError);
    widget.onSessionReady?.call(_session);
    final source = widget.source;
    if (source is PreparedChapterSource) {
      source.setChapterPreparer(_prepareChapterBeforeLayout);
    }
    unawaited(_reloadAnnotations());
    unawaited(_reloadDecorations());
  }

  @override
  void didUpdateWidget(ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customFonts != widget.customFonts) {
      _customFonts = List.of(widget.customFonts);
    }
    if (oldWidget.cornerInfo != widget.cornerInfo) {
      _cornerInfo = widget.cornerInfo;
    }
    if (oldWidget.pageTurnMode != widget.pageTurnMode) {
      if (oldWidget.pageTurnMode == PageTurnMode.scroll &&
          widget.pageTurnMode != PageTurnMode.scroll) {
        _scrollKey.currentState?.captureLatestPosition();
        unawaited(_flushScrollViewportForModeChange());
      }
      _pageTurnMode = widget.pageTurnMode;
    }
    if (oldWidget.markSettings != widget.markSettings) {
      _markSettings = widget.markSettings;
      _painter = _buildPainter();
    }
    if (oldWidget.decorations != widget.decorations ||
        oldWidget.decorationRules != widget.decorationRules) {
      unawaited(_reloadDecorations());
    }
    if (oldWidget.keepScreenOn != widget.keepScreenOn ||
        oldWidget.volumeKeyPaging != widget.volumeKeyPaging) {
      _syncPlatformSettings();
    }
    if (oldWidget.margins != widget.margins && widget.margins != null) {
      _savedMargins = widget.margins;
    }
    if (oldWidget.tapZones != widget.tapZones) {
      _tapZones = widget.tapZones;
    }
    if (oldWidget.theme != widget.theme) {
      _theme = widget.theme;
    }
    if (oldWidget.customTheme != widget.customTheme) {
      _customTheme = widget.customTheme;
    }
    if (oldWidget.inkMode != widget.inkMode) {
      _inkMode = widget.inkMode;
      _painter = _buildPainter();
    }
    if (oldWidget.backgroundId != widget.backgroundId &&
        widget.backgroundId != _backgroundId) {
      unawaited(_loadBackground(widget.backgroundId));
    }
    if (oldWidget.overrides != widget.overrides && widget.overrides != null) {
      _overrides = widget.overrides!;
    }
    if (oldWidget.theme != widget.theme ||
        oldWidget.background != widget.background ||
        oldWidget.imageCache != widget.imageCache) {
      if (oldWidget.imageCache != widget.imageCache) {
        oldWidget.imageCache?.protectedUrls = const {};
        _prefetchedPageKeys.clear();
        _imagePage = null;
      }
      setState(() => _painter = _buildPainter());
    }
    if (oldWidget.overrides != widget.overrides) {
      // 重排：旧段落缓存全部失效（P2-30）。
      _paragraphCache.clear();
    }
    if (oldWidget.overrides != widget.overrides ||
        oldWidget.theme != widget.theme) {
      unawaited(_session.applyOverrides(_effectiveOverrides()));
    }
  }

  /// 点屏幕中央：阅读菜单（P4-11 目录；P4-13 书签；P4-21 再补主题/排版）。
  ///
  /// 菜单 / 目录 / 书签在同一 sheet 内切换：真机上先 pop 菜单再开新 sheet 会
  /// 被关闭动画吃掉（表现为点了没反应）。
  /// 抽屉标题（设计稿 `.drawer-title`）。
  String _drawerTitleOf(ReaderMenuEntry? entry, _DrawerTab tab) =>
      switch (entry) {
        ReaderMenuEntry.toc => switch (tab) {
          _DrawerTab.content => '目录',
          _DrawerTab.bookmarks => '书签',
          _DrawerTab.annotations => '标注',
          _DrawerTab.decorations => '装饰',
          _DrawerTab.search => '搜索',
        },
        ReaderMenuEntry.theme => '主题',
        ReaderMenuEntry.type => '排版',
        ReaderMenuEntry.settings => '设置',
        null => '',
      };

  /// 滑杆气泡文案：章名 + 章内页。
  String _chapterLabelOf(PageContent page) =>
      '${_chapterTitleOf(page.spineIndex)} · '
      '${_session.pageLabelOf(page)}${_session.isChapterComplete(page.spineIndex) ? ' 页' : ''}';

  /// 打开/关闭沉浸式菜单（设计稿 `.screen.menu-open`）。
  void _toggleReaderMenu() {
    if (widget.editMode) return;
    _pageTurnKey.currentState?.controller.cancel();
    final open = !_menuOpen;
    _log('user_menu', <String, Object?>{'open': open});
    // 不切系统栏模式：菜单是浮层，切 edgeToEdge 会改 viewPadding → 正文重排。
    setState(() {
      _menuOpen = open;
      if (!_menuOpen) {
        _drawer = null;
        _drawerTab = _DrawerTab.content;
      }
    });
  }

  /// 打开某个抽屉面板（底部四入口）。
  void _openDrawer(ReaderMenuEntry entry) {
    _log('user_drawer', <String, Object?>{'panel': entry.name});
    setState(() {
      _drawer = entry;
      _drawerTab = _DrawerTab.content;
    });
  }

  /// 关闭抽屉（保留菜单）。
  void _closeDrawer() {
    setState(() {
      _drawer = null;
      _drawerTab = _DrawerTab.content;
    });
  }

  /// 关闭整个阅读菜单；目录/搜索跳转后应直接回到正文。
  void _dismissReaderMenu() {
    if (!_menuOpen && _drawer == null && _drawerTab == _DrawerTab.content) {
      return;
    }
    setState(() {
      _menuOpen = false;
      _drawer = null;
      _drawerTab = _DrawerTab.content;
    });
  }

  /// 系统返回键：逐层关闭正文之上的浮层，全部关闭后下一次返回退出阅读页。
  void _handleBackPressed() {
    if (_editingMargins) {
      setState(() {
        _clearMarginPreview();
        _editingMargins = false;
        _finishingMarginEdit = true;
        _previewMargins = null;
      });
      return;
    }
    if (_editingTapZones) {
      setState(() => _editingTapZones = false);
      return;
    }
    if (_selection != null) {
      _clearSelection();
      return;
    }
    _dismissReaderMenu();
  }

  /// 菜单里的“返回书架”：这是主动退出，直接出栈，不被返回键拦截逻辑挡住。
  void _exitReader() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  /// 打开九宫格点击区域编辑页。
  void _openTapZoneEditor() {
    _log('user_tap_zones_open');
    setState(() {
      _drawer = null;
      _drawerTab = _DrawerTab.content;
      _menuOpen = false;
      _editingTapZones = true;
    });
  }

  /// 应用九宫格点击区域配置。
  void _applyTapZones(ReaderTapZones zones) {
    _log('user_tap_zones', <String, Object?>{
      for (final zone in ReaderTapZone.values)
        zone.name: zones.actionAt(zone).name,
    });
    widget.onTapZonesChanged?.call(zones);
    setState(() {
      _tapZones = zones;
      _editingTapZones = false;
    });
  }

  /// 进度滑杆：按全书正文字符比例定位到章内 CFI。
  Future<void> _seekToProgress(double percent) async {
    await _session.seekToReadingPercent(
      percent,
      continuous: _effectiveTurnMode == PageTurnMode.scroll,
    );
  }

  /// 日/夜快速切换（设计稿顶部栏的日间夜间按钮）。
  void _toggleDayNight() {
    final dark =
        (_theme ?? ReaderTheme.white).background.computeLuminance() < 0.35;
    _applyTheme(dark ? 'white' : 'black');
  }

  /// 添加当前页书签（P4-13）。
  Future<void> _addBookmark() async {
    final store = widget.bookmarks;
    final cfi = _session.currentCfi;
    if (store == null || cfi == null) {
      _showToast('当前位置不支持书签');
      return;
    }
    final progress = _session.progress;
    final spine = progress?.spineIndex ?? 0;
    final page = progress?.pageIndex ?? 0;
    final chapterTitle = _chapterTitleOf(spine);
    final line = _session.currentLineText;
    final created = await store.add(
      cfi: cfi,
      spineIndex: spine,
      label:
          '$chapterTitle · 第 ${page + 1} 页'
          '${line.isEmpty ? '' : ' · $line'}',
    );
    if (!mounted) {
      return;
    }
    _showToast(created == null ? '该位置已有书签' : '已添加书签');
  }

  /// 拖拽只替换被拖动的一端；跨页范围由选区层保留另一端的页码。
  void _applySelection(ReaderSelection selection) {
    if (_selection == null || !_selectionMatchesLayout) {
      return;
    }
    setState(() => _selection = selection);
  }

  /// 拖到页边 → 延时 300ms 在当前章内翻页并扩展选区（§63.5）。
  void _handleSelectionEdgeDrag(bool forward) {
    _selectionEdgeTimer?.cancel();
    _selectionEdgeTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(
        forward ? _extendSelectionForward() : _extendSelectionBackward(),
      );
    });
  }

  Future<void> _extendSelectionForward() async {
    final selection = _selection;
    final page = _session.page;
    if (selection == null ||
        page == null ||
        (_session.isChapterComplete(page.spineIndex) &&
            page.pageIndex >= _session.chapterPageCount - 1)) {
      return;
    }
    await _session.chapterPages();
    if (!mounted ||
        !identical(selection, _selection) ||
        !identical(page, _session.page) ||
        page.pageIndex >= _session.chapterPageCount - 1) {
      return;
    }
    final changed = await _session.next();
    if (!changed ||
        !mounted ||
        !identical(selection, _selection) ||
        !_selectionMatchesLayout) {
      return;
    }
    final nextPage = _session.page;
    if (nextPage == null) {
      return;
    }
    final boxes = TextHitTester.lineBoxes(nextPage);
    if (boxes.isEmpty) {
      return;
    }
    final last = boxes.last;
    setState(() {
      _selection = ReaderSelection.spanning(
        start: selection.start,
        startPageIndex: selection.startPageIndex,
        end: TextHit(
          lineBox: last,
          charOffset: last.text.length,
          textOffset: last.textOffset + last.text.length,
          atLineStart: false,
          atLineEnd: true,
        ),
        endPageIndex: nextPage.pageIndex,
      );
      _selectionSpineIndex = nextPage.spineIndex;
    });
  }

  Future<void> _extendSelectionBackward() async {
    final selection = _selection;
    final page = _session.page;
    if (selection == null || page == null || page.pageIndex <= 0) {
      return;
    }
    final changed = await _session.previous();
    if (!changed ||
        !mounted ||
        !identical(selection, _selection) ||
        !_selectionMatchesLayout) {
      return;
    }
    final prevPage = _session.page;
    if (prevPage == null) {
      return;
    }
    final boxes = TextHitTester.lineBoxes(prevPage);
    if (boxes.isEmpty) {
      return;
    }
    final first = boxes.first;
    setState(() {
      _selection = ReaderSelection.spanning(
        start: TextHit(
          lineBox: first,
          charOffset: 0,
          textOffset: first.textOffset,
          atLineStart: true,
          atLineEnd: false,
        ),
        startPageIndex: prevPage.pageIndex,
        end: selection.end,
        endPageIndex: selection.endPageIndex,
      );
      _selectionSpineIndex = prevPage.spineIndex;
    });
  }

  /// 复制一段（P4-29 无障碍动作）。
  void _copyBlock(String text) {
    if (text.isEmpty) {
      return;
    }
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    _showToast('已复制本段');
  }

  /// 翻页播报（P4-29，§67.5）：只在无障碍开启时播报，避免干扰普通用户。
  void _announcePageChange(PageContent page, int totalPages) {
    if (!(MediaQuery.maybeAccessibleNavigationOf(context) ?? false)) {
      return;
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      totalPages > 0
          ? '第 ${page.pageIndex + 1} 页，共 $totalPages 页'
          : '第 ${page.pageIndex + 1} 页',
      TextDirection.ltr,
    );
  }

  /// 应用搜索结果（P4-26，§29.4）：跳到命中位置并临时高亮 3 秒。
  Future<void> _applySearchResult(SearchPanelResult result) async {
    final request = ++_searchRequest;
    final generation = _session.generation;
    final navigation = _session.navigationRevision;
    // 扫描式搜索不给每条命中算 CFI，这里按点击结果现场排版这一章。
    var cfi = result.cfi;
    cfi ??= await widget.onResolveSearchCfi?.call(result);
    if (cfi == null ||
        !mounted ||
        request != _searchRequest ||
        generation != _session.generation ||
        navigation != _session.navigationRevision) {
      return;
    }
    final jump = _session.jumpToCfi(
      cfi,
      title: result.chapterTitle,
      continuous: _effectiveTurnMode == PageTurnMode.scroll,
    );
    final jumpNavigation = _session.navigationRevision;
    await jump;
    if (!mounted ||
        request != _searchRequest ||
        jumpNavigation != _session.navigationRevision) {
      return;
    }
    final highlightGeneration = _session.generation;
    final endCfi = await _searchResultEnd(cfi, result);
    if (!mounted ||
        request != _searchRequest ||
        jumpNavigation != _session.navigationRevision ||
        highlightGeneration != _session.generation ||
        endCfi == null) {
      return;
    }
    _highlightSearchResult(cfi, endCfi, result);
  }

  Future<String?> _searchResultEnd(String cfi, SearchPanelResult result) async {
    if (cfiCharOffset(cfi) == null) return null;
    try {
      final source = _session.source;
      if (source is AnchorChapterSource) {
        final chapter = await source.loadAnchorChapter(result.spineIndex);
        final offset = chapter.offsetFor(cfi);
        return offset == null
            ? null
            : chapter.cfiAt(offset + result.matchLength, end: true);
      }
      for (final page in await _session.chapterPages()) {
        for (final slice in page.slices) {
          final block = slice.block;
          final offset = block.offsetForCfi(cfi);
          if (offset != null &&
              offset + result.matchLength <= block.layout.text.length) {
            final end = block.cfiAt(offset + result.matchLength, end: true);
            if (end != cfi) return end;
          }
        }
      }
    } catch (_) {
      // 导航已完成；原文端点补算失败或取消时只跳过临时高亮。
    }
    return null;
  }

  void _highlightSearchResult(
    String resolvedCfi,
    String endCfi,
    SearchPanelResult result,
  ) {
    _tempHighlightTimer?.cancel();
    setState(() {
      _tempHighlight = ReaderAnnotation(
        id: 'search-hit',
        type: ReaderAnnotationType.mark,
        startCfi: resolvedCfi,
        endCfi: endCfi,
        quote: result.context,
        color: 0xFFFFC107,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _resolvedAnnotations = <ReaderAnnotation>[
        ..._resolvedAnnotations,
        _tempHighlight!,
      ];
    });
    _tempHighlightTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _tempHighlight = null;
        _resolvedAnnotations = <ReaderAnnotation>[
          for (final item in _resolvedAnnotations)
            if (item.id != 'search-hit') item,
        ];
      });
    });
  }

  /// 应用排版设置（P4-21）：立即重排 + 通知外部持久化。
  void _applyOverrides(ReaderOverrides next) {
    if (!mounted || next.fingerprint == _overrides.fingerprint) {
      return;
    }
    setState(() => _overrides = next);
    unawaited(_session.applyOverrides(_effectiveOverrides()));
    widget.onOverridesChanged?.call(next);
  }

  /// 切换主题（P4-21）：不重排，只重绘并通知外部持久化。
  void _applyTheme(String themeId) {
    final theme = ReaderTheme.byId(themeId);
    setState(() {
      _theme = theme;
      _customTheme = ReaderTheme.customById(themeId) ?? _customTheme;
      _painter = _buildPainter();
    });
    unawaited(_session.applyOverrides(_effectiveOverrides()));
    widget.onThemeChanged?.call(themeId);
  }

  /// 仅最新加载请求可应用，解码失败保留当前背景。
  Future<bool> _loadBackground(String id) async {
    final request = ++_backgroundRequest;
    final background = ReaderBackground.byId(id);
    ui.Image? image;
    try {
      image = await _decodeBackground(background);
      if (!mounted || request != _backgroundRequest) {
        image?.dispose();
        return false;
      }
      setState(() {
        _backgroundId = background.id;
        _backgroundImage?.dispose();
        _backgroundImage = image;
        _painter = _buildPainter();
      });
      return true;
    } catch (_) {
      image?.dispose();
      if (mounted && request == _backgroundRequest) {
        if (_backgroundImage == null) {
          setState(() {
            _backgroundId = 'none';
            _painter = _buildPainter();
          });
        }
        _showToast('背景图片无法读取，请重新选择');
      }
      return false;
    }
  }

  Future<ui.Image?> _decodeBackground(ReaderBackground background) async {
    Uint8List bytes;
    if (background.isImage) {
      final loader = widget.backgroundImageLoader;
      if (loader == null) throw const FormatException('缺少图片加载器');
      bytes = await loader(background.id);
    } else {
      final asset = background.asset;
      if (asset == null) return null;
      final data = await rootBundle.load(asset);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<void> _pickBackgroundImage() async {
    if (_pickingBackgroundImage || _inkMode) return;
    final pick = widget.onPickBackgroundImage;
    if (pick == null) return;
    setState(() => _pickingBackgroundImage = true);
    final request = _backgroundRequest;
    try {
      final id = await pick();
      if (mounted && id != null && request == _backgroundRequest && !_inkMode) {
        await _applyBackground(id);
      }
    } catch (_) {
      if (mounted) _showToast('无法使用这张图片，请选择有效图片（小于 20MB）');
    } finally {
      if (mounted) setState(() => _pickingBackgroundImage = false);
    }
  }

  Future<ReaderFontOption?> _pickFont() async {
    final font = await widget.onPickFont?.call();
    if (!mounted || font == null) return null;
    setState(() {
      _customFonts = {
        for (final saved in _customFonts) saved.family: saved,
        font.family: font,
      }.values.toList();
    });
    return font;
  }

  void _applyCornerInfo(ReaderCornerInfo info) {
    if (_cornerInfo == info) return;
    setState(() => _cornerInfo = info);
    widget.onCornerInfoChanged?.call(info);
  }

  /// 切换墨水屏模式（P4-23）：纯黑白 + 禁用纹理，只重绘不重排。
  void _applyInkMode(bool enabled) {
    if (enabled == _inkMode) {
      return;
    }
    setState(() {
      _inkMode = enabled;
      _painter = _buildPainter();
    });
    widget.onInkModeChanged?.call(enabled);
  }

  /// 切换背景（P4-22）：纹理只影响绘制层，不触发重排。
  Future<void> _applyBackground(String id) async {
    if (await _loadBackground(id)) widget.onBackgroundChanged?.call(id);
  }

  /// 恢复默认设置（P4-21）。
  void _resetSettings() {
    final resetMargins = _savedMargins != null;
    _applyOverrides(ReaderSettingsDefaults.overrides);
    _applyTheme(ReaderSettingsDefaults.themeId);
    _applyBackground(ReaderBackground.none.id);
    unawaited(_applyPageTurnMode(PageTurnMode.cover));
    _applyInkMode(false);
    _applyMarkSettings(const ReaderMarkSettings());
    _applyCornerInfo(ReaderCornerInfo.defaults);
    if (widget.keepScreenOn) {
      widget.onKeepScreenOnChanged?.call(false);
    }
    if (widget.volumeKeyPaging) {
      widget.onVolumeKeyPagingChanged?.call(false);
    }
    if (_tapZones != ReaderTapZones.defaults) {
      _applyTapZones(ReaderTapZones.defaults);
    }
    if (resetMargins) {
      final margins = _defaultMargins;
      setState(() {
        _previewMargins = null;
        _savedMargins = margins;
      });
      widget.onMarginsChanged?.call(margins);
    }
  }

  Future<void> _applyPageTurnMode(PageTurnMode mode) async {
    if (mode == _pageTurnMode) return;
    if (_effectiveTurnMode == PageTurnMode.scroll) {
      // 滚动容器的 120ms 合并窗口尚未提交时，先取最新视口并等待分页器
      // 落到目标页，避免切到分页模式后显示并保存较早的页号。
      await _flushScrollViewportForModeChange();
      if (!mounted) return;
    }
    _pageTurnKey.currentState?.controller.cancel();
    _clearSelection();
    setState(() => _pageTurnMode = mode);
    widget.onPageTurnModeChanged?.call(mode);
    _log('user_page_turn_mode', {'mode': mode.id});
  }

  /// 切模式前把滚动容器的最新可见位置串行提交并落盘。
  ///
  /// [flushVisiblePosition] 会同步暂存快照并让分页器落到对应页；
  /// [commitStagedViewport] 再补齐窗口销毁前尚未提交的位次；最后显式
  /// [ReaderSession.flushProgress] 不依赖 120ms 合并/保存定时器。
  Future<void> _flushScrollViewportForModeChange() async {
    try {
      await _scrollKey.currentState?.flushVisiblePosition();
      await _session.commitStagedViewport();
      await _session.flushProgress();
    } catch (error) {
      _log('progress_save_error', {'error': '$error'});
    }
  }

  /// 重新加载全书标注（P4-18）并重定位到当前章（P4-20）。
  Future<void> _reloadAnnotations() async {
    final generation = ++_annotationGeneration;
    final store = widget.annotations;
    if (store == null) {
      return;
    }
    final items = await store.list();
    if (!mounted || generation != _annotationGeneration) {
      return;
    }
    setState(() {
      _annotations = items;
      _annotationsByChapter.clear();
      _annotationScheduledChapters.clear();
      _resolvedAnnotations = const [];
    });
    await _relocateAnnotations();
    if (mounted) setState(() => _painter = _buildPainter());
  }

  /// 批量删除标注，完成后只刷新一次阅读页。
  Future<void> _deleteAnnotations(List<ReaderAnnotation> annotations) async {
    final store = widget.annotations;
    if (store == null || annotations.isEmpty) {
      return;
    }
    try {
      for (final annotation in annotations) {
        await store.remove(annotation.id);
      }
    } finally {
      if (mounted) {
        await _reloadAnnotations();
      }
    }
    if (mounted) {
      _showToast('已删除 ${annotations.length} 条标注');
    }
  }

  /// 批量更换标注颜色，完成后只刷新一次阅读页。
  Future<void> _recolorAnnotations(
    List<ReaderAnnotation> annotations,
    int color,
  ) async {
    final store = widget.annotations;
    if (store == null || annotations.isEmpty) {
      return;
    }
    try {
      for (final annotation in annotations) {
        await store.update(annotation.id, color: color);
      }
    } finally {
      if (mounted) {
        await _reloadAnnotations();
      }
    }
    if (mounted) {
      _showToast('已更换 ${annotations.length} 条标注颜色');
    }
  }

  /// 按当前章的分页重算标注位置（§30.4）：CFI 优先，失效按引文兜底。
  Future<void> _relocateAnnotations() async {
    final spine = _session.page?.spineIndex;
    if (spine == null) return;
    await _resolveAnnotationChapter(spine, _annotationGeneration);
  }

  Future<void> _selectBookmark(ReaderBookmark bookmark) async {
    if (!bookmark.needsRelocation) {
      await _session.jumpToCfi(
        bookmark.cfi,
        title: bookmark.label,
        continuous: _effectiveTurnMode == PageTurnMode.scroll,
      );
      return;
    }
    if (widget.bookmarks is! RelocatableBookmarkStore) {
      _showToast('该书签待确认，当前存储不支持重新定位');
      return;
    }
    final accepted = await _showRelocationDialog(
      '重新定位书签',
      bookmark.label,
      bookmark.relocationReason,
    );
    if (!mounted || !accepted) return;
    _clearSelection();
    setState(() {
      _relocatingAnnotation = null;
      _relocatingDecoration = null;
      _relocatingBookmark = bookmark;
    });
  }

  Future<void> _selectAnnotation(ReaderAnnotation annotation) async {
    if (!annotation.needsRelocation) {
      final parsed = EpubCfi.parse(annotation.startCfi);
      final spine = parsed == null ? null : spineIndexOfCfi(parsed);
      if (spine != null && spine >= 0 && spine < widget.source.chapterCount) {
        final pages = await widget.source.loadChapter(spine);
        if (!mounted) return;
        final result = AnnotationRelocator.relocate(
          annotations: [annotation],
          pages: pages,
          contentRevision: widget.contentRevision,
        );
        if (result.isNotEmpty && result.single.isResolved) {
          await _session.jumpToCfi(
            result.single.startCfi,
            title: annotation.quote,
            continuous: _effectiveTurnMode == PageTurnMode.scroll,
          );
          return;
        }
      }
    }
    await _beginAnnotationRelocation(annotation);
  }

  Future<void> _beginAnnotationRelocation(ReaderAnnotation annotation) async {
    if (widget.annotations is! RelocatableAnnotationStore) {
      _showToast('该标注待确认，当前存储不支持重新定位');
      return;
    }
    final original = [
      annotation.quote,
      if (annotation.note != null) annotation.note!,
    ].join('\n\n');
    final accepted = await _showRelocationDialog(
      '重新定位标注',
      original,
      annotation.relocationReason,
    );
    if (!mounted || !accepted) return;
    _clearSelection();
    setState(() {
      _relocatingBookmark = null;
      _relocatingDecoration = null;
      _relocatingAnnotation = annotation;
    });
  }

  Future<bool> _showRelocationDialog(
    String title,
    String original,
    String? reason, {
    String? replacement,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(original),
                if (reason != null) ...[
                  const SizedBox(height: 12),
                  Text(reason),
                ],
                if (replacement != null) ...[
                  const SizedBox(height: 16),
                  const Text('新版位置'),
                  Text(replacement),
                  const SizedBox(height: 12),
                  const Text('原引用、想法及样式将保留。'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(replacement == null ? '重新定位' : '确认关联'),
            ),
          ],
        ),
      ) ??
      false;

  Widget _buildRelocationBar() => SafeArea(
    bottom: false,
    child: Material(
      color: _effectiveTheme?.background ?? widget.background,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _relocatingAnnotation != null || _relocatingDecoration != null
                    ? '长按选择新版文字，点击“关联此处”'
                    : '翻到新版位置后，点击“使用当前位置”',
              ),
            ),
            if (_relocatingBookmark != null)
              TextButton(
                onPressed: _relocationBusy
                    ? null
                    : () => unawaited(_relocateSelectedBookmark()),
                child: const Text('使用当前位置'),
              ),
            TextButton(
              onPressed: _relocationBusy ? null : _cancelRelocation,
              child: const Text('取消定位'),
            ),
          ],
        ),
      ),
    ),
  );

  void _cancelRelocation() {
    _clearSelection();
    setState(() {
      _relocatingAnnotation = null;
      _relocatingBookmark = null;
      _relocatingDecoration = null;
    });
  }

  Future<void> _relocateSelectedBookmark() async {
    final bookmark = _relocatingBookmark;
    final store = widget.bookmarks;
    final cfi = _session.currentCfi;
    if (_relocationBusy ||
        bookmark == null ||
        cfi == null ||
        store is! RelocatableBookmarkStore) {
      return;
    }
    final accepted = await _showRelocationDialog(
      '确认关联书签',
      bookmark.label,
      null,
      replacement: _session.currentLineText,
    );
    if (!mounted || !accepted || _relocatingBookmark != bookmark) return;
    await _saveRelocation(
      () => (store as RelocatableBookmarkStore).relocate(bookmark.id, cfi: cfi),
      '书签已重新定位',
    );
  }

  Future<void> _relocateSelectedAnnotation(
    PageContent page,
    ReaderSelection selection,
  ) async {
    final annotation = _relocatingAnnotation;
    final store = widget.annotations;
    if (_relocationBusy ||
        annotation == null ||
        store is! RelocatableAnnotationStore) {
      return;
    }
    final supported = await _supportedSelection(page, selection);
    if (!mounted || supported == null) return;
    final accepted = await _showRelocationDialog(
      '确认关联标注',
      annotation.quote,
      null,
      replacement: supported.quote,
    );
    if (!mounted || !accepted || _relocatingAnnotation != annotation) return;
    await _saveRelocation(
      () => (store as RelocatableAnnotationStore).relocate(
        annotation.id,
        startCfi: supported.startCfi,
        endCfi: supported.endCfi,
      ),
      '标注已重新定位',
      annotations: true,
    );
  }

  Future<void> _saveRelocation(
    Future<void> Function() save,
    String success, {
    bool annotations = false,
  }) async {
    setState(() => _relocationBusy = true);
    try {
      await save();
      if (mounted && annotations) await _reloadAnnotations();
      if (mounted) {
        _cancelRelocation();
        _showToast(success);
      }
    } catch (_) {
      if (mounted) _showToast('重新定位失败，请重试');
    } finally {
      if (mounted) setState(() => _relocationBusy = false);
    }
  }

  /// 长按 → 选词（P4-15，§63.2：长按先试词，失败退到连续同类字符段）。
  void _selectWordAt(Offset localPosition) {
    final target = _pageHitAt(localPosition);
    if (target == null) {
      return;
    }
    final page = target.page;
    final hit = TextHitTester.hitTest(page, target.localPosition);
    if (hit == null || hit.lineBox.text.trim().isEmpty) {
      _clearSelection();
      return;
    }
    setState(() {
      _selectionPage = _effectiveTurnMode == PageTurnMode.scroll ? page : null;
      _selection = SelectionOps.wordAt(page, hit);
      _selectionLayoutRevision = _session.layoutRevision;
      _selectionSpineIndex = page.spineIndex;
      _selectionMore = false;
    });
  }

  /// 三击 → 选句（P4-16）。
  void _selectSentenceAt(Offset localPosition) {
    final target = _pageHitAt(localPosition);
    if (target == null) {
      return;
    }
    final page = target.page;
    final hit = TextHitTester.hitTest(page, target.localPosition);
    if (hit == null || hit.lineBox.text.trim().isEmpty) {
      _clearSelection();
      return;
    }
    setState(() {
      _selectionPage = _effectiveTurnMode == PageTurnMode.scroll ? page : null;
      _selection = SelectionOps.sentenceAt(page, hit);
      _selectionLayoutRevision = _session.layoutRevision;
      _selectionSpineIndex = page.spineIndex;
      _selectionMore = false;
    });
  }

  ({PageContent page, Offset localPosition})? _pageHitAt(Offset localPosition) {
    if (_effectiveTurnMode == PageTurnMode.scroll) {
      final hit = _scrollKey.currentState?.pageAt(localPosition);
      if (hit == null) {
        return null;
      }
      return (page: hit.page, localPosition: hit.localPosition);
    }
    final page = _session.page;
    if (page == null) {
      return null;
    }
    final padding = _bodyPadding();
    return (
      page: page,
      localPosition: localPosition - Offset(padding.left, padding.top),
    );
  }

  bool _openFootnoteInPage(PageContent page, Offset pagePosition) {
    final footnote = TextHitTester.footnoteAt(page, pagePosition);
    if (footnote == null) {
      return false;
    }
    _clearSelection();
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ReaderPanelTheme(
          theme: _effectiveTheme ?? ReaderTheme.white,
          child: ReaderFootnoteDialog(
            footnote: footnote,
            imageCache: widget.imageCache,
          ),
        ),
      ),
    );
    return true;
  }

  /// 单击正文：优先编辑命中的高亮/笔记，其次打开脚注或尾注。
  bool _handleTapAt(Offset localPosition) {
    final page = _session.page;
    if (page == null) {
      return false;
    }
    final padding = _bodyPadding();
    return _handleTapInPage(
      page,
      localPosition - Offset(padding.left, padding.top),
    );
  }

  bool _handleTapInPage(PageContent page, Offset pagePosition) {
    if (widget.editMode && _editImageAt(page, pagePosition)) return true;
    if (widget.editMode && _editTextAt(page, pagePosition)) return true;
    if (_handleGalleryTap(page, pagePosition)) return true;
    final persistent = <ReaderAnnotation>[
      for (final annotation in _resolvedAnnotations)
        if (annotation.id != 'search-hit') annotation,
    ];
    final annotation = AnnotationDecorations.annotationAt(
      page,
      pagePosition,
      persistent,
      contentWidth: _paperContentWidth,
    );
    if (annotation != null) {
      _clearSelection();
      unawaited(_editAnnotation(annotation));
      return true;
    }
    final decoration = ReaderDecorationGeometry.decorationAt(
      page,
      pagePosition,
      _resolvedDecorations,
    );
    if (decoration != null) {
      _clearSelection();
      unawaited(_editDecoration(decoration));
      return true;
    }
    if (pagePosition.dx >= 0 &&
        pagePosition.dx <= _paperContentWidth &&
        _openFootnoteInPage(page, pagePosition)) {
      return true;
    }
    // 有选区时点击正文只取消选中：既不翻页，也不打开阅读菜单。
    if (_selection != null) {
      _clearSelection();
      return true;
    }
    return false;
  }

  bool _editImageAt(PageContent page, Offset position) {
    if (widget.onEditTarget == null) return false;
    for (final region in galleryRegionsOf(page)) {
      if (region.rect.contains(position)) {
        final gallery = region.gallery;
        _requestTextEdit(
          page.spineIndex,
          gallery.frames[_galleryFrameOf(gallery)].cfi,
        );
        return true;
      }
    }
    var flowY = page.topPadding;
    for (final slice in page.slices) {
      final top = slice.overlay ? slice.absoluteTop ?? flowY : flowY;
      if (!slice.overlay) flowY += slice.height;
      final block = slice.block;
      final style = block.style;
      if (!block.isReplaced ||
          style == null ||
          block.startCfi == null ||
          style.visibility != CssVisibility.visible ||
          block.effectiveOpacity <= 0) {
        continue;
      }
      final model = BoxModel.fromStyle(
        style,
        containingWidth: _paperContentWidth,
      );
      final bounds = Rect.fromLTWH(
        (slice.overlay ? slice.leftInset : 0) +
            style.margin.left +
            block.leftInset,
        top + slice.leadingExtent,
        model.resolveContentWidth(_paperContentWidth),
        (slice.height - slice.leadingExtent - slice.trailingExtent).clamp(
          0,
          double.infinity,
        ),
      );
      if (bounds.contains(position)) {
        _requestTextEdit(page.spineIndex, block.cfiAt(0) ?? block.startCfi!);
        return true;
      }
    }
    return false;
  }

  bool _editTextAt(PageContent page, Offset position) {
    if (widget.onEditTarget == null) return false;
    final hit = TextHitTester.hitTest(page, position);
    if (hit == null ||
        (!hit.lineBox.rect.inflate(3).contains(position) &&
            !_insideEditableLineGap(page, hit.lineBox, position))) {
      return false;
    }
    final cfi = hit.lineBox.slice.block.cfiAt(
      hit.lineBox.blockTextOffset + hit.charOffset,
    );
    if (cfi == null) return false;
    _requestTextEdit(page.spineIndex, cfi);
    return true;
  }

  bool _insideEditableLineGap(
    PageContent page,
    PageLineBox target,
    Offset position,
  ) {
    if (target.isVertical || target.slice.block.multicol != null) return false;
    final lines = TextHitTester.lineBoxes(page);
    for (var index = 1; index < lines.length; index++) {
      final previous = lines[index - 1];
      final next = lines[index];
      if (previous.sliceIndex != target.sliceIndex ||
          next.sliceIndex != target.sliceIndex ||
          previous.lineIndex + 1 != next.lineIndex ||
          previous.text.trim().isEmpty ||
          next.text.trim().isEmpty) {
        continue;
      }
      // 只补同段相邻行中心线之间的空白，不包含段间距或段尾下方。
      final bounds = previous.rect.expandToInclude(next.rect);
      if (Rect.fromLTRB(
        bounds.left,
        previous.rect.center.dy,
        bounds.right,
        next.rect.center.dy,
      ).contains(position)) {
        return true;
      }
    }
    return false;
  }

  void _requestTextEdit(int spineIndex, String cfi) {
    // 排版块可合并多个行内文本节点；编辑定位只传节点路径，不能把
    // 块内累加字符偏移当作原始 XML 文本节点内的偏移。
    final parsed = EpubCfi.parse(cfi);
    if (parsed != null && !parsed.isRange && parsed.segments.isNotEmpty) {
      final segments = [...parsed.segments];
      final last = segments.removeLast();
      segments.add(CfiSegment(last.steps, side: last.side));
      cfi = EpubCfi(segments).serialize();
    }
    _clearSelection();
    widget.onEditTarget?.call(
      ReaderEditTarget(
        spineIndex: spineIndex,
        cfi: cfi,
        contentRevision: widget.contentRevision,
      ),
    );
  }

  /// 打开高亮编辑弹层：组合调整颜色、样式、笔记或删除标注。
  Future<void> _editAnnotation(ReaderAnnotation annotation) async {
    if (widget.annotations == null) {
      return;
    }
    final action = await showModalBottomSheet<AnnotationEditAction>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReaderPanelTheme(
        theme: _effectiveTheme ?? ReaderTheme.white,
        child: ReaderAnnotationEditorSheet(
          annotation: annotation,
          inkMode: _inkMode,
          markSettings: _markSettings,
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    await _applyAnnotationEdit(annotation, action);
  }

  Future<void> _copySelection(
    PageContent page,
    ReaderSelection selection,
  ) async {
    final text = selection.isMultiPage
        ? SelectionOps.textAcrossPages(await _session.chapterPages(), selection)
        : SelectionOps.textOf(page, selection);
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    _clearSelection();
    _showToast('已复制');
  }

  void _selectAll(PageContent page) {
    final boxes = TextHitTester.lineBoxes(page);
    if (boxes.isEmpty) {
      return;
    }
    final first = boxes.first;
    final last = boxes.last;
    setState(() {
      _selectionSpineIndex = page.spineIndex;
      _selectionLayoutRevision = _session.layoutRevision;
      _selection = ReaderSelection.normalized(
        TextHit(
          lineBox: first,
          charOffset: 0,
          textOffset: first.textOffset,
          atLineStart: true,
          atLineEnd: false,
        ),
        TextHit(
          lineBox: last,
          charOffset: last.text.length,
          textOffset: last.textOffset + last.text.length,
          atLineStart: false,
          atLineEnd: true,
        ),
        pageIndex: page.pageIndex,
      );
    });
  }

  void _clearSelection() {
    _selectionEdgeTimer?.cancel();
    _selectionEdgeTimer = null;
    if (_selection != null) {
      setState(() {
        _selection = null;
        _selectionLayoutRevision = null;
        _selectionPage = null;
        _selectionSpineIndex = null;
        _hideSelectionMenu = false;
        _selectionMore = false;
      });
    }
  }

  void _showToast(
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 2),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.clearSnackBars();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: action,
        persist: false,
      ),
    );
  }

  void _reportProgressSaveError() {
    final error = _session.progressSaveError;
    if (error == null) {
      _reportedProgressSaveMessage = null;
      return;
    }
    final message = error is ReaderProgressSaveException
        ? error.message
        : '本次位置未保存，保留上次保存位置，请稍后重试';
    if (_reportedProgressSaveMessage == message) return;
    _reportedProgressSaveMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _session.progressSaveError == null ||
          _reportedProgressSaveMessage != message) {
        return;
      }
      _showToast(message);
    });
  }

  /// 切后台/失去焦点时立即落盘（P4-10）：系统回收不丢最后一次翻页。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pageTurnKey.currentState?.resumeWarmup();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _pageTurnKey.currentState?.releaseCachedBitmaps();
      unawaited(_flushReadingProgress());
    }
  }

  Future<void> _flushReadingProgress() async {
    if (_effectiveTurnMode == PageTurnMode.scroll) {
      _scrollKey.currentState?.captureLatestPosition();
      await _scrollKey.currentState?.flushVisiblePosition();
    }
    try {
      await _session.flushProgress();
    } on ReaderProgressSaveException {
      // 会话已通知保存失败；生命周期回调不能再次抛出预期的存储拒绝。
    }
  }

  @override
  void dispose() {
    _marginPreviewTimer?.cancel();
    _readerPlatformChannel.setMethodCallHandler(null);
    unawaited(_invokePlatformFlag('setKeepScreenOn', false));
    unawaited(_invokePlatformFlag('setVolumeKeyPaging', false));
    WidgetsBinding.instance.removeObserver(this);
    // 退出阅读页：恢复系统栏（edge-to-edge），并复位到浅色图标语义。
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    _scrollKey.currentState?.captureLatestPosition();
    _session.removeListener(_reportProgressSaveError);
    // 先同步取得最新视口并启动最后一次保存，再取消在途排版；这样即使
    // 本轮排版被丢弃，退出保存仍读到旧的可见位置而不是已失效的页号。
    _session.flushProgress().ignore();
    _session.cancelPendingLoads();
    _session.dispose();
    _galleryRepaint.dispose();
    final source = widget.source;
    if (source is PreparedChapterSource) source.setChapterPreparer(null);
    if (_ownsParagraphCache) {
      _paragraphCache.dispose();
    }
    _selectionEdgeTimer?.cancel();
    _tempHighlightTimer?.cancel();
    _semanticsFirstFocus.dispose();
    _backgroundRequest++;
    _backgroundImage?.dispose();
    widget.imageCache?.protectedUrls = const {};
    _decorationGeneration++;
    _annotationGeneration++;
    _ruleEngine.dispose();
    for (final image in _decorationImages.values) {
      image.dispose();
    }
    _decorationImages.clear();
    _decorationNineSlices.clear();
    _chapterDecorationPreparations.clear();
    _decorationFontLoads.clear();
    _loadedDecorationFonts.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasOverlayOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBackPressed();
      },
      child: AnimatedBuilder(
        animation: _session,
        builder: (context, _) {
          // 背景铺满窗口（P8-10 收尾）：加载骨架/错误态/正文页统一以主题
          // 背景色打底，避免 padding 外区域透出窗口黑底。
          return LayoutBuilder(
            builder: (context, constraints) {
              _scheduleContentSize(
                Size(constraints.maxWidth, constraints.maxHeight),
              );
              return ColoredBox(
                color: _effectiveTheme?.background ?? widget.background,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _buildBody(context),
                    ),
                    // 编辑器不随章内页码切换重建，重排期间同一次拖动可以继续。
                    if (_editingMargins || _finishingMarginEdit)
                      const ModalBarrier(
                        key: ValueKey<String>('margin-pagination-barrier'),
                        dismissible: false,
                      ),
                    if (_editingMargins)
                      Positioned.fill(child: _buildMarginEditor()),
                    if (_relocatingAnnotation != null ||
                        _relocatingDecoration != null ||
                        _relocatingBookmark != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _buildRelocationBar(),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final page = _session.page;
    if (page != null) _scheduleDecorationChapter(page);
    if (page != null) _scheduleAnnotationChapter(page);
    // 翻页后焦点落到新页首块（P4-28）；面板/弹层打开时不抢焦点。
    final pageKey = page == null
        ? null
        : '${page.spineIndex}/${page.pageIndex}';
    if (pageKey != null && _lastFocusedPageKey != pageKey) {
      _lastFocusedPageKey = pageKey;
      final focusedPage = page;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || focusedPage == null) {
          return;
        }
        final route = ModalRoute.of(context);
        if (route != null && route.isCurrent == false) {
          return;
        }
        if (_semanticsFirstFocus.canRequestFocus) {
          _semanticsFirstFocus.requestFocus();
        }
        _announcePageChange(focusedPage, _session.chapterPageCount);
      });
    }

    // 新分页快照或页面离开选区范围时，下一帧清除旧选区。
    // 回调里重新取最新状态：边缘翻页会先翻页再扩展选区，两者不能互相打断。
    if (_selection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final current = _selection;
        final currentPage = _session.page;
        if (current == null) {
          return;
        }
        if (!_selectionMatchesLayout) {
          _clearSelection();
          return;
        }
        if (currentPage == null) {
          return;
        }
        if (_effectiveTurnMode == PageTurnMode.scroll) {
          final selectedPage = _selectionPage;
          if (selectedPage == null ||
              _scrollKey.currentState?.pageTopOnScreen(selectedPage) == null) {
            _clearSelection();
          }
          return;
        }
        final sameSpine =
            _selectionSpineIndex == null ||
            _selectionSpineIndex == currentPage.spineIndex;
        final inRange =
            currentPage.pageIndex >= current.startPageIndex &&
            currentPage.pageIndex <= current.endPageIndex;
        if (!sameSpine || !inRange) {
          _clearSelection();
        }
      });
    }
    if (page == null) {
      final error = _session.error;
      if (error != null) {
        return Center(
          key: const ValueKey<String>('reader-error'),
          child: Text('打开失败：$error'),
        );
      }
      if (_session.loading || _initialOpen == null) {
        return ReaderLoadingSkeleton(
          progress: _session.bookProgress > 0 ? _session.bookProgress : null,
          title: widget.bookTitle,
        );
      }
      return const Center(
        key: ValueKey<String>('reader-empty'),
        child: Text('无内容'),
      );
    }
    return LayoutBuilder(
      key: const ValueKey<String>('reader-content'),
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final bodyPadding = _bodyPadding();
        _paperContentWidth = size.width - bodyPadding.horizontal;
        _schedulePrefetch(page, size.width - bodyPadding.horizontal);
        // 出血页把整页让给图：绘制画布取满屏，正文由 pageInsets 内缩，
        // 出血块才能铺到屏幕边缘。页眉页脚按页类型让位：
        // - 整页背景图页（封面/扉页）：页眉页脚都不画；
        // - 章首页或顶部出血页（章首横幅图）：隐藏页眉，页脚保留。
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildReadingView(size),
            // 正文语义层（P4-27）：读屏用，不接收指针事件。
            Positioned.fill(
              child: Padding(
                padding: bodyPadding,
                child: ReaderSemanticsLayer(
                  page: page,
                  pageWidth: size.width - bodyPadding.horizontal,
                  firstNodeFocus: _semanticsFirstFocus,
                  onNextPage: () => _requestPageTurn(true),
                  onPreviousPage: () => _requestPageTurn(false),
                  onCopyBlock: _copyBlock,
                ),
              ),
            ),
            // 选区层（P4-15）：高亮 + 起止手柄；只有手柄热区接收手势。
            if (_selection != null && _selectionMatchesLayout) ...[
              Builder(
                builder: (context) {
                  final selectionPage =
                      _effectiveTurnMode == PageTurnMode.scroll
                      ? _selectionPage ?? page
                      : page;
                  final selectionTop = _effectiveTurnMode == PageTurnMode.scroll
                      ? _scrollKey.currentState?.pageTopOnScreen(
                              selectionPage,
                            ) ??
                            bodyPadding.top
                      : bodyPadding.top;
                  final selectionPadding = bodyPadding.copyWith(
                    top: selectionTop,
                  );
                  return Positioned.fill(
                    child: SelectionLayer(
                      page: selectionPage,
                      pageIndex: selectionPage.pageIndex,
                      selection: _selection!,
                      inkMode: _inkMode,
                      contentPadding: selectionPadding,
                      onChanged: _applySelection,
                      onEdgeDrag: _effectiveTurnMode == PageTurnMode.scroll
                          ? null
                          : _handleSelectionEdgeDrag,
                    ),
                  );
                },
              ),
              // 选区菜单（P4-16）：贴在选区上方，不遮挡选区。
              if (!_hideSelectionMenu)
                SelectionMenu(
                  actions: _selectionActions(
                    _effectiveTurnMode == PageTurnMode.scroll
                        ? _selectionPage ?? page
                        : page,
                    _selection!,
                  ),
                  anchor:
                      SelectionOps.boundsOf(
                        _effectiveTurnMode == PageTurnMode.scroll
                            ? _selectionPage ?? page
                            : page,
                        _selection!,
                      ).shift(
                        Offset(
                          bodyPadding.left,
                          _effectiveTurnMode == PageTurnMode.scroll
                              ? _scrollKey.currentState?.pageTopOnScreen(
                                      _selectionPage ?? page,
                                    ) ??
                                    bodyPadding.top
                              : bodyPadding.top,
                        ),
                      ),
                  bounds: size,
                ),
            ],
            // 翻页/重排时保留旧页，只在顶部显示细进度条（P2-27）。
            if (_session.loading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _session.bookProgress > 0
                      ? _session.bookProgress
                      : null,
                ),
              ),
            // 菜单外的点击只收起菜单，不能穿透到正文的翻页手势。
            if (_menuOpen)
              ModalBarrier(
                onDismiss: _toggleReaderMenu,
                semanticsLabel: '关闭阅读菜单',
              ),
            // 沉浸式菜单（设计稿 .menu-top / .menu-bottom / .drawer）。
            ReaderMenuOverlay(
              open: _menuOpen,
              theme: _effectiveTheme,
              bookTitle: widget.bookTitle,
              progress: _session.readingPercent ?? _bookProgressOf(page),
              chapterLabel: _chapterLabelOf(page),
              onBack: _exitReader,
              onEdit: widget.onOpenEditor,
              onToggleDayNight: _toggleDayNight,
              nightMode:
                  (_theme ?? ReaderTheme.white).background.computeLuminance() <
                  0.35,
              inkMode: _inkMode,
              onPreviousChapter:
                  page.spineIndex <= 0 || _session.jumpLoadingTitle != null
                  ? null
                  : () {
                      _closeDrawer();
                      unawaited(
                        _session.jumpToChapter(
                          page.spineIndex - 1,
                          emptyDirection: -1,
                        ),
                      );
                    },
              onNextChapter:
                  page.spineIndex >= widget.source.chapterCount - 1 ||
                      _session.jumpLoadingTitle != null
                  ? null
                  : () {
                      _closeDrawer();
                      unawaited(_session.jumpToChapter(page.spineIndex + 1));
                    },
              onSeek: (value) {
                _closeDrawer();
                unawaited(_seekToProgress(value));
              },
              onEntry: _openDrawer,
              drawerTitle: _drawerTitleOf(_drawer, _drawerTab),
              drawerChild: _drawer == null
                  ? null
                  : _ReaderDrawerContent(
                      entry: _drawer!,
                      tab: _drawerTab,
                      onTabChanged: (tab) => setState(() => _drawerTab = tab),
                      entries: _session.toc,
                      currentSpineIndex: _session.progress?.spineIndex ?? 0,
                      currentCfi: _session.currentCfi,
                      bookmarks: widget.bookmarks,
                      annotations: widget.annotations,
                      annotationItems: _annotations,
                      decorations: widget.decorations,
                      decorationItems: _decorations,
                      decorationRuleCount: _decorationRules.length,
                      decorationRulesEnabled: _hasEnabledDecorationRules,
                      markSettings: _markSettings,
                      hasCfi: _session.currentCfi != null,
                      overrides: _overrides,
                      themeId: (_theme ?? ReaderTheme.white).id,
                      customTheme: _customTheme,
                      customFonts: _customFonts,
                      onPickFont: widget.onPickFont == null ? null : _pickFont,
                      onLoadFont: widget.onLoadFont,
                      onRenameFont: widget.onRenameFont,
                      onRemoveFont: widget.onRemoveFont,
                      cornerInfo: _cornerInfo,
                      onCornerInfoChanged: _applyCornerInfo,
                      onPickBackgroundImage:
                          widget.onPickBackgroundImage == null
                          ? null
                          : _pickBackgroundImage,
                      backgroundImageLoader: widget.backgroundImageLoader,
                      pickingBackgroundImage: _pickingBackgroundImage,
                      backgroundId: _backgroundId,
                      inkMode: _inkMode,
                      pageTurnMode: _pageTurnMode,
                      tapZones: _tapZones,
                      keepScreenOn: widget.keepScreenOn,
                      volumeKeyPaging: widget.volumeKeyPaging,
                      onPageTurnModeChanged: (mode) {
                        unawaited(_applyPageTurnMode(mode));
                      },
                      onTapZonesChanged: _applyTapZones,
                      onKeepScreenOnChanged: widget.onKeepScreenOnChanged,
                      onVolumeKeyPagingChanged: widget.onVolumeKeyPagingChanged,
                      onOverridesChanged: _applyOverrides,
                      onThemeChanged: _applyTheme,
                      onBackgroundChanged: widget.onBackgroundChanged == null
                          ? null
                          : _applyBackground,
                      onInkModeChanged: _applyInkMode,
                      onResetSettings: _resetSettings,
                      onSearch: widget.onSearch,
                      onSearchStream: widget.onSearchStream,
                      onSearchSelect: (result) {
                        _dismissReaderMenu();
                        unawaited(_applySearchResult(result));
                      },
                      onTocSelect: (entry) {
                        _dismissReaderMenu();
                        unawaited(
                          _session.jumpToTocEntry(
                            entry,
                            continuous:
                                _effectiveTurnMode == PageTurnMode.scroll,
                          ),
                        );
                      },
                      onBookmarkSelect: (bookmark) {
                        _dismissReaderMenu();
                        unawaited(_selectBookmark(bookmark));
                      },
                      onAddBookmark: () {
                        unawaited(_addBookmark());
                      },
                      onAnnotationSelect: (annotation) {
                        _dismissReaderMenu();
                        unawaited(_selectAnnotation(annotation));
                      },
                      onAnnotationEdit: (annotation) {
                        unawaited(_editAnnotation(annotation));
                      },
                      onAnnotationDelete: _deleteAnnotations,
                      onAnnotationRecolor: _recolorAnnotations,
                      onDecorationSelect: (decoration) {
                        _dismissReaderMenu();
                        unawaited(_selectDecoration(decoration));
                      },
                      onDecorationEdit: (decoration) =>
                          unawaited(_editDecoration(decoration)),
                      onDecorationRemove: (decoration) =>
                          unawaited(_removeDecoration(decoration)),
                      onDecorationRules: () =>
                          unawaited(_openDecorationRules()),
                      onOpenMarkSettings: () => unawaited(_openMarkSettings()),
                      onOpenMarginEditor: () {
                        _dismissReaderMenu();
                        setState(() {
                          _editingMargins = true;
                          _previewMargins = null;
                        });
                      },
                      onOpenTapZoneEditor: _openTapZoneEditor,
                    ),
              onCloseDrawer: _closeDrawer,
              safeTop: _safeTop,
              safeBottom: _safeBottom,
            ),
            // 九宫格点击区域编辑页：每个格子循环切换点击动作。
            if (_editingTapZones)
              Positioned.fill(
                child: TapZoneEditor(
                  zones: _tapZones,
                  foreground:
                      _effectiveTheme?.text ??
                      Theme.of(context).colorScheme.onSurface,
                  background: _effectiveTheme?.background ?? widget.background,
                  onCancel: () => setState(() {
                    _editingTapZones = false;
                  }),
                  onApply: _applyTapZones,
                ),
              ),
            // 跳章浮层（P4-12，§27.2）：目标章名 + 不确定进度，完成后淡出。
            _JumpLoadingOverlay(title: _session.jumpLoadingTitle),
          ],
        );
      },
    );
  }

  void _previewMarginChange(ReaderMargins margins) {
    if (!_editingMargins) return;
    _pendingMarginPreview = margins;
    if (!_draggingMargins) {
      _flushMarginPreview();
      return;
    }
    // 按钮与留白由编辑器即时绘制，正文重排按短间隔取最新草稿。
    _marginPreviewTimer ??= Timer(
      const Duration(milliseconds: 80),
      _flushMarginPreview,
    );
  }

  void _flushMarginPreview() {
    _marginPreviewTimer?.cancel();
    _marginPreviewTimer = null;
    final margins = _pendingMarginPreview;
    _pendingMarginPreview = null;
    if (!mounted || !_editingMargins || margins == null) return;
    setState(() => _previewMargins = margins);
  }

  void _marginDragChanged(bool dragging) {
    _draggingMargins = dragging;
    if (!dragging) _flushMarginPreview();
  }

  void _clearMarginPreview() {
    _marginPreviewTimer?.cancel();
    _marginPreviewTimer = null;
    _pendingMarginPreview = null;
    _draggingMargins = false;
  }

  Widget _buildMarginEditor() => MarginEditor(
    margins: _activeMargins,
    defaults: _defaultMargins,
    onPreview: _previewMarginChange,
    onDragChanged: _marginDragChanged,
    showPageFurniture: widget.showPageFooter,
    headerHeight: _headerHeight,
    footerHeight: _footerHeight,
    onCancel: () => setState(() {
      _clearMarginPreview();
      _editingMargins = false;
      _finishingMarginEdit = true;
      _previewMargins = null;
    }),
    onApply: (margins) {
      _clearMarginPreview();
      _log('user_margins', <String, Object?>{
        'left': margins.left,
        'right': margins.right,
        'top_outer': margins.topOuter,
        'top_inner': margins.topInner,
        'bottom_inner': margins.bottomInner,
        'bottom_outer': margins.bottomOuter,
      });
      widget.onMarginsChanged?.call(margins);
      setState(() {
        _savedMargins = margins;
        _editingMargins = false;
        _finishingMarginEdit = true;
        _previewMargins = null;
      });
    },
  );

  void _requestPageTurn(bool next) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _searchRequest += 1;
    _clearSelection();
    _log('user_page', {
      'dir': next ? 'next' : 'prev',
      'mode': _pageTurnMode.id,
    });
    if (_effectiveTurnMode == PageTurnMode.scroll) {
      unawaited(_scrollKey.currentState?.scrollPage(next) ?? Future.value());
      return;
    }
    _pageTurnKey.currentState?.controller.request(next);
  }

  void _openBookEnd() {
    if (!_hasOverlayOpen && ModalRoute.of(context)?.isCurrent != false) {
      widget.onBookEnd?.call(_session, _readingRtl);
    }
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    if (call.method != 'volumeKeyPage' || !widget.volumeKeyPaging) {
      return;
    }
    switch (call.arguments) {
      case 'next':
        _requestPageTurn(true);
      case 'previous':
        _requestPageTurn(false);
    }
  }

  void _syncPlatformSettings() {
    unawaited(_invokePlatformFlag('setKeepScreenOn', widget.keepScreenOn));
    unawaited(
      _invokePlatformFlag('setVolumeKeyPaging', widget.volumeKeyPaging),
    );
  }

  Future<void> _invokePlatformFlag(String method, bool enabled) async {
    try {
      await _readerPlatformChannel.invokeMethod<void>(method, enabled);
    } on MissingPluginException {
      // 桌面/测试环境没有 Android 通道，设置仍保留在 Flutter 状态中。
    } on PlatformException {
      // 平台侧不可用时不影响阅读。
    }
  }

  Widget _buildReadingView(Size size) {
    final page = _session.page;
    if (page != null) _syncGalleryFrames(page);
    final revision = (
      _painter,
      _imageRevision,
      _resolvedAnnotations,
      _tempHighlight,
      _bodyPadding(),
      _cornerInfo,
    );
    if (_effectiveTurnMode == PageTurnMode.scroll) {
      final padding = _bodyPadding();
      return ReaderView(
        config: ReaderGestureConfig(
          tapZones: _tapZones,
          verticalWriting: _readingRtl,
        ),
        continuousScroll: true,
        onPrevious: () => _requestPageTurn(false),
        onNext: () => _requestPageTurn(true),
        onToggleToolbar: () {
          _clearSelection();
          _toggleReaderMenu();
        },
        onLongPressAt: _selectWordAt,
        onDoubleTapAt: _selection == null ? null : _selectWordAt,
        onTripleTapAt: _selection == null ? null : _selectSentenceAt,
        onTapAt: (point) =>
            _scrollKey.currentState?.handleTapAt(point) ?? false,
        child: ContinuousScrollView(
          key: _scrollKey,
          session: _session,
          revision: revision,
          padding: padding,
          paperBuilder: _buildScrollPaper,
          onTapAtPage: _handleTapInPage,
          onUserScroll: _clearSelection,
          onBookEnd: widget.onBookEnd == null ? null : _openBookEnd,
          onPageVisible: (page) =>
              _schedulePrefetch(page, size.width - padding.horizontal),
        ),
      );
    }
    return ReaderView(
      config: ReaderGestureConfig(
        tapZones: _tapZones,
        verticalWriting: _readingRtl,
        minimumFlingVelocity: _effectiveTurnMode == PageTurnMode.simulation3d
            ? 20
            : null,
      ),
      onPrevious: () => _requestPageTurn(false),
      onNext: () => _requestPageTurn(true),
      onToggleToolbar: () {
        _clearSelection();
        _toggleReaderMenu();
      },
      onPointerDown: (point) =>
          _pageTurnKey.currentState?.controller.pointerDown(point),
      onDragStart: (details) {
        _clearSelection();
        _pageTurnKey.currentState?.controller.beginDrag(details);
      },
      onDragUpdate: (details) =>
          _pageTurnKey.currentState?.controller.updateDrag(details),
      onDragEnd: (details) =>
          _pageTurnKey.currentState?.controller.endDrag(details),
      onDragCancel: () => _pageTurnKey.currentState?.controller.cancelDrag(),
      onLongPressAt: _selectWordAt,
      onDoubleTapAt: _selection == null ? null : _selectWordAt,
      onTripleTapAt: _selection == null ? null : _selectSentenceAt,
      onTapAt: (point) => _pageTurnKey.currentState?.controller.active == true
          ? false
          : _handleTapAt(point),
      child: ValueListenableBuilder<ReaderBatteryStatus>(
        valueListenable: readerBatteryStatus,
        builder: (context, battery, _) => PageTurnView(
          key: _pageTurnKey,
          session: _session,
          mode: _effectiveTurnMode,
          revision: (revision, battery),
          paperBuilder: _buildPaper,
          paperColor: _effectiveTheme?.background ?? widget.background,
          paintBackground: _painter.pageBackgroundImage == null
              ? null
              : _paintTurnBackground,
          preparePageImages: _prepareTurnPageImages,
          onBookEnd: widget.onBookEnd == null ? null : _openBookEnd,
          preload: !_editingMargins && !_finishingMarginEdit,
          rtl: _readingRtl,
        ),
      ),
    );
  }

  void _paintTurnBackground(Canvas canvas, Size size) => _painter
      .paintBackground(canvas, pageSize: size, pageInsets: _bodyPadding());

  Widget _buildPaper(PageContent page, Size size) => ClipRect(
    key: ValueKey('reader-page-${page.spineIndex}-${page.pageIndex}'),
    child: Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _ReaderPageCustomPainter(
            page: page,
            painter: _painter,
            paintHighlights: _paintDecorationHighlights,
            imageRevision: _imageRevision,
            pageInsets: _bodyPadding(),
            repaint: _galleryRepaint,
          ),
        ),
        if (_resolvedAnnotations.isNotEmpty || _tempHighlight != null)
          Positioned.fill(
            child: Padding(
              padding: _bodyPadding(),
              child: AnnotationLayer(
                page: page,
                annotations: [..._resolvedAnnotations, ?_tempHighlight],
                inkMode: _inkMode,
                settings: _markSettings,
                backgroundsBehindText: true,
              ),
            ),
          ),
        ..._paperFurniture(page),
        ..._galleryLayers(page, padding: _bodyPadding()),
      ],
    ),
  );

  Widget _buildScrollPaper(PageContent page, Size size) {
    _schedulePrefetch(page, size.width);
    _scheduleDecorationChapter(page);
    _scheduleAnnotationChapter(page);
    return Stack(
      key: ValueKey('scroll-page-${page.spineIndex}-${page.pageIndex}'),
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        ClipRect(
          child: CustomPaint(
            painter: _ReaderPageCustomPainter(
              page: page,
              painter: _painter,
              paintHighlights: _paintDecorationHighlights,
              imageRevision: _imageRevision,
              repaint: _galleryRepaint,
            ),
          ),
        ),
        if (_resolvedAnnotations.isNotEmpty || _tempHighlight != null)
          Positioned.fill(
            child: AnnotationLayer(
              page: page,
              annotations: [..._resolvedAnnotations, ?_tempHighlight],
              inkMode: _inkMode,
              settings: _markSettings,
              backgroundsBehindText: true,
            ),
          ),
        ..._galleryLayers(page),
      ],
    );
  }

  List<Widget> _paperFurniture(PageContent page) {
    final padding = _furniturePadding();
    final full = _isFullPageBackground(page);
    final data = ReaderCornerData(
      bookTitle: widget.bookTitle,
      chapterTitle: _chapterTitleOf(page.spineIndex),
      pageLabel: _session.pageLabelOf(page),
      progress: _bookProgressOf(page),
    );
    return [
      // 页眉只在章节第一页自动隐藏，续页含出血或背景图也保留。
      if (widget.showPageFooter && _cornerInfo.hasHeader && page.pageIndex > 0)
        Positioned(
          left: padding.left,
          right: padding.right,
          top: padding.top,
          child: IgnorePointer(
            child: ReaderPageHeader(
              theme: _effectiveTheme,
              title: _chapterTitleOf(page.spineIndex),
              pageLabel: _session.pageLabelOf(page),
              inkMode: _inkMode,
              info: _cornerInfo,
              data: data,
            ),
          ),
        ),
      if (widget.showPageFooter && _cornerInfo.hasFooter && !full)
        Positioned(
          left: padding.left,
          right: padding.right,
          bottom: padding.bottom,
          child: IgnorePointer(
            child: ReaderPageFooter(
              theme: _effectiveTheme,
              progress: data.progress,
              inkMode: _inkMode,
              info: _cornerInfo,
              data: data,
            ),
          ),
        ),
    ];
  }
}

class _ReaderPageCustomPainter extends CustomPainter {
  const _ReaderPageCustomPainter({
    required this.page,
    required this.painter,
    required this.paintHighlights,
    required this.imageRevision,
    this.pageInsets = EdgeInsets.zero,
    super.repaint,
  });

  final PageContent page;
  final PagePainter painter;
  final void Function(Canvas, PageContent) paintHighlights;
  final int imageRevision;

  /// 正文区相对整页的内缩（页边距 + 页眉页脚槽）。
  final EdgeInsets pageInsets;

  @override
  void paint(Canvas canvas, Size size) {
    // 画布是整页；正文由 pageInsets 内缩，出血块由绘制层扩到页边。
    painter.paint(canvas, page, pageSize: size, pageInsets: pageInsets);
    canvas.save();
    canvas.translate(pageInsets.left, pageInsets.top);
    paintHighlights(canvas, page);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ReaderPageCustomPainter oldDelegate) =>
      oldDelegate.page != page ||
      oldDelegate.imageRevision != imageRevision ||
      oldDelegate.pageInsets != pageInsets ||
      // 绘制配置包含纹理、图片及墨水屏模式，更新时必须重绘当前纸面。
      oldDelegate.painter != painter;
}

/// 目录中与指定 spine 对应的标题；无精确项时沿用最近的前置章节。
String? _tocTitleForSpine(List<TocEntry> entries, int spineIndex) {
  TocEntry? exact;
  TocEntry? nearest;
  void visit(List<TocEntry> rows) {
    for (final entry in rows) {
      final title = entry.title.trim();
      if (title.isNotEmpty) {
        if (entry.spineIndex == spineIndex) {
          exact ??= entry;
        } else if (entry.spineIndex < spineIndex &&
            (nearest == null || entry.spineIndex > nearest!.spineIndex)) {
          nearest = entry;
        }
      }
      visit(entry.children);
    }
  }

  visit(entries);
  return exact?.title.trim() ?? nearest?.title.trim();
}

/// 阅读菜单 sheet（P4-11/P4-13）：菜单 / 目录 / 书签 / 笔记在同一 sheet
/// 内切换，避免真机上「关掉 sheet 立刻开新 sheet」被关闭动画吞掉。
///
/// 返回：选中的 [TocEntry] / [ReaderBookmark] / `'add-bookmark'`（null = 关闭）。
/// 目录抽屉里的二级页签。
enum _DrawerTab {
  /// 目录内容。
  content,

  /// 书签列表。
  bookmarks,

  /// 划线与想法列表。
  annotations,

  /// 手工装饰与自动规则入口。
  decorations,

  /// 搜索。
  search,
}

/// 抽屉内容分发器：目录/主题/排版/设置四个面板 + 目录内的书签、笔记与搜索页签。
///
/// 参数较多是因为它同时是四类面板的适配层（各面板回调不同），拆分收益不大。
class _ReaderDrawerContent extends StatefulWidget {
  const _ReaderDrawerContent({
    required this.entry,
    required this.tab,
    required this.onTabChanged,
    required this.entries,
    required this.currentSpineIndex,
    required this.currentCfi,
    required this.bookmarks,
    required this.annotations,
    required this.annotationItems,
    required this.decorations,
    required this.decorationItems,
    required this.decorationRuleCount,
    required this.decorationRulesEnabled,
    required this.markSettings,
    required this.hasCfi,
    required this.overrides,
    required this.themeId,
    required this.customTheme,
    required this.customFonts,
    required this.onPickFont,
    required this.onLoadFont,
    required this.onRenameFont,
    required this.onRemoveFont,
    required this.cornerInfo,
    required this.onCornerInfoChanged,
    required this.onPickBackgroundImage,
    required this.backgroundImageLoader,
    required this.pickingBackgroundImage,
    required this.backgroundId,
    required this.inkMode,
    required this.pageTurnMode,
    required this.tapZones,
    required this.keepScreenOn,
    required this.volumeKeyPaging,
    required this.onPageTurnModeChanged,
    required this.onTapZonesChanged,
    required this.onKeepScreenOnChanged,
    required this.onVolumeKeyPagingChanged,
    required this.onOverridesChanged,
    required this.onThemeChanged,
    required this.onBackgroundChanged,
    required this.onInkModeChanged,
    required this.onResetSettings,
    required this.onSearch,
    required this.onSearchStream,
    required this.onSearchSelect,
    required this.onTocSelect,
    required this.onBookmarkSelect,
    required this.onAddBookmark,
    required this.onAnnotationSelect,
    required this.onAnnotationEdit,
    required this.onAnnotationDelete,
    required this.onAnnotationRecolor,
    required this.onDecorationSelect,
    required this.onDecorationEdit,
    required this.onDecorationRemove,
    required this.onDecorationRules,
    required this.onOpenMarkSettings,
    required this.onOpenMarginEditor,
    required this.onOpenTapZoneEditor,
  });

  final ReaderMenuEntry entry;
  final _DrawerTab tab;
  final ValueChanged<_DrawerTab> onTabChanged;
  final List<TocEntry> entries;
  final int currentSpineIndex;
  final String? currentCfi;
  final ReaderBookmarkStore? bookmarks;
  final ReaderAnnotationStore? annotations;
  final List<ReaderAnnotation> annotationItems;
  final ReaderDecorationStore? decorations;
  final List<ReaderDecoration> decorationItems;
  final int decorationRuleCount;
  final bool decorationRulesEnabled;
  final ReaderMarkSettings markSettings;
  final bool hasCfi;
  final ReaderOverrides overrides;
  final String themeId;
  final ReaderTheme? customTheme;
  final List<ReaderFontOption> customFonts;
  final Future<ReaderFontOption?> Function()? onPickFont;
  final Future<void> Function(String family)? onLoadFont;
  final Future<ReaderFontOption> Function(String family, String name)?
  onRenameFont;
  final Future<void> Function(String family)? onRemoveFont;
  final ReaderCornerInfo cornerInfo;
  final ValueChanged<ReaderCornerInfo> onCornerInfoChanged;
  final VoidCallback? onPickBackgroundImage;
  final Future<Uint8List> Function(String id)? backgroundImageLoader;
  final bool pickingBackgroundImage;
  final String backgroundId;
  final bool inkMode;
  final PageTurnMode pageTurnMode;
  final ReaderTapZones tapZones;
  final bool keepScreenOn;
  final bool volumeKeyPaging;
  final ValueChanged<PageTurnMode> onPageTurnModeChanged;
  final ValueChanged<ReaderTapZones> onTapZonesChanged;
  final ValueChanged<bool>? onKeepScreenOnChanged;
  final ValueChanged<bool>? onVolumeKeyPagingChanged;
  final ValueChanged<ReaderOverrides> onOverridesChanged;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<String>? onBackgroundChanged;
  final ValueChanged<bool>? onInkModeChanged;
  final VoidCallback onResetSettings;
  final Future<List<SearchPanelResult>> Function(String query)? onSearch;
  final Stream<SearchProgress> Function(String query)? onSearchStream;
  final ValueChanged<SearchPanelResult> onSearchSelect;
  final ValueChanged<TocEntry> onTocSelect;
  final ValueChanged<ReaderBookmark> onBookmarkSelect;
  final VoidCallback onAddBookmark;
  final ValueChanged<ReaderAnnotation> onAnnotationSelect;
  final ValueChanged<ReaderAnnotation> onAnnotationEdit;
  final Future<void> Function(List<ReaderAnnotation>) onAnnotationDelete;
  final Future<void> Function(List<ReaderAnnotation>, int) onAnnotationRecolor;
  final ValueChanged<ReaderDecoration> onDecorationSelect;
  final ValueChanged<ReaderDecoration> onDecorationEdit;
  final ValueChanged<ReaderDecoration> onDecorationRemove;
  final VoidCallback onDecorationRules;
  final VoidCallback onOpenMarkSettings;
  final VoidCallback onOpenMarginEditor;
  final VoidCallback onOpenTapZoneEditor;

  @override
  State<_ReaderDrawerContent> createState() => _ReaderDrawerContentState();
}

class _ReaderDrawerContentState extends State<_ReaderDrawerContent> {
  Future<List<ReaderBookmark>>? _bookmarksFuture;

  @override
  void initState() {
    super.initState();
    _reloadBookmarks();
  }

  void _reloadBookmarks() {
    _bookmarksFuture =
        widget.bookmarks?.list() ??
        Future<List<ReaderBookmark>>.value(const <ReaderBookmark>[]);
  }

  String? _annotationChapterTitle(ReaderAnnotation annotation) {
    final cfi = EpubCfi.parse(annotation.startCfi);
    final spine = cfi == null ? null : spineIndexOfCfi(cfi);
    if (spine == null) {
      return null;
    }
    return _tocTitleForSpine(widget.entries, spine);
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.entry) {
      case ReaderMenuEntry.toc:
        return _buildTocDrawer(context);
      case ReaderMenuEntry.theme:
        return SettingsPanel(
          section: SettingsSection.theme,
          overrides: widget.overrides,
          themeId: widget.themeId,
          customTheme: widget.customTheme,
          onPickBackgroundImage: widget.onPickBackgroundImage,
          backgroundImageLoader: widget.backgroundImageLoader,
          pickingBackgroundImage: widget.pickingBackgroundImage,
          backgroundId: widget.backgroundId,
          inkMode: widget.inkMode,
          onOverridesChanged: widget.onOverridesChanged,
          onThemeChanged: widget.onThemeChanged,
          onBackgroundChanged: widget.onBackgroundChanged,
          onInkModeChanged: widget.onInkModeChanged,
          onReset: widget.onResetSettings,
        );
      case ReaderMenuEntry.type:
        return SettingsPanel(
          section: SettingsSection.type,
          overrides: widget.overrides,
          customFonts: widget.customFonts,
          onPickFont: widget.onPickFont,
          onLoadFont: widget.onLoadFont,
          onRenameFont: widget.onRenameFont,
          onRemoveFont: widget.onRemoveFont,
          themeId: widget.themeId,
          onOverridesChanged: widget.onOverridesChanged,
          onThemeChanged: widget.onThemeChanged,
          onOpenMarginEditor: widget.onOpenMarginEditor,
        );
      case ReaderMenuEntry.settings:
        return SettingsPanel(
          section: SettingsSection.settings,
          overrides: widget.overrides,
          themeId: widget.themeId,
          inkMode: widget.inkMode,
          pageTurnMode: widget.pageTurnMode,
          tapZones: widget.tapZones,
          keepScreenOn: widget.keepScreenOn,
          volumeKeyPaging: widget.volumeKeyPaging,
          cornerInfo: widget.cornerInfo,
          onCornerInfoChanged: widget.onCornerInfoChanged,
          onPageTurnModeChanged: widget.onPageTurnModeChanged,
          onTapZonesChanged: widget.onTapZonesChanged,
          onKeepScreenOnChanged: widget.onKeepScreenOnChanged,
          onVolumeKeyPagingChanged: widget.onVolumeKeyPagingChanged,
          onOverridesChanged: widget.onOverridesChanged,
          onThemeChanged: widget.onThemeChanged,
          onInkModeChanged: widget.onInkModeChanged,
          onReset: widget.onResetSettings,
          onOpenTapZoneEditor: widget.onOpenTapZoneEditor,
          onOpenMarkSettings: widget.onOpenMarkSettings,
          markSettings: widget.markSettings,
        );
    }
  }

  Widget _buildTocDrawer(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ReaderDrawerStyle.dividerOf(theme)),
            ),
          ),
          child: Row(
            children: <Widget>[
              _DrawerTabButton(
                buttonKey: const ValueKey<String>('drawer-tab-toc'),
                label: '目录',
                selected: widget.tab == _DrawerTab.content,
                onTap: () => widget.onTabChanged(_DrawerTab.content),
              ),
              if (widget.bookmarks != null)
                _DrawerTabButton(
                  buttonKey: const ValueKey<String>('drawer-tab-bookmarks'),
                  label: '书签',
                  selected: widget.tab == _DrawerTab.bookmarks,
                  onTap: () {
                    _reloadBookmarks();
                    widget.onTabChanged(_DrawerTab.bookmarks);
                  },
                ),
              if (widget.annotations != null)
                _DrawerTabButton(
                  buttonKey: const ValueKey<String>('drawer-tab-annotations'),
                  label: '标注',
                  selected: widget.tab == _DrawerTab.annotations,
                  onTap: () => widget.onTabChanged(_DrawerTab.annotations),
                ),
              if (widget.decorations != null)
                _DrawerTabButton(
                  buttonKey: const ValueKey<String>('drawer-tab-decorations'),
                  label: '装饰',
                  selected: widget.tab == _DrawerTab.decorations,
                  onTap: () => widget.onTabChanged(_DrawerTab.decorations),
                ),
              if (widget.onSearch != null)
                _DrawerTabButton(
                  buttonKey: const ValueKey<String>('drawer-tab-search'),
                  label: '搜索',
                  selected: widget.tab == _DrawerTab.search,
                  onTap: () => widget.onTabChanged(_DrawerTab.search),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (widget.tab) {
            _DrawerTab.content => TocPanel(
              entries: widget.entries,
              currentSpineIndex: widget.currentSpineIndex,
              currentCfi: widget.currentCfi,
              onSelect: widget.onTocSelect,
            ),
            _DrawerTab.bookmarks => FutureBuilder<List<ReaderBookmark>>(
              future: _bookmarksFuture,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const <ReaderBookmark>[];
                return BookmarkPanel(
                  bookmarks: items,
                  onAdd: widget.hasCfi ? widget.onAddBookmark : null,
                  onSelect: widget.onBookmarkSelect,
                  onDelete: (bookmark) async {
                    await widget.bookmarks?.remove(bookmark.id);
                    if (mounted) {
                      setState(_reloadBookmarks);
                    }
                  },
                );
              },
            ),
            _DrawerTab.annotations => AnnotationPanel(
              annotations: widget.annotationItems,
              chapterTitleOf: _annotationChapterTitle,
              inkMode: widget.inkMode,
              onSelect: widget.onAnnotationSelect,
              onEdit: widget.onAnnotationEdit,
              onDelete: widget.onAnnotationDelete,
              onRecolor: widget.onAnnotationRecolor,
            ),
            _DrawerTab.decorations => ReaderDecorationPanel(
              decorations: widget.decorationItems,
              toc: widget.entries,
              onSelect: widget.onDecorationSelect,
              onEdit: widget.onDecorationEdit,
              onRemove: widget.onDecorationRemove,
              onRules: widget.onDecorationRules,
              ruleCount: widget.decorationRuleCount,
              rulesEnabled: widget.decorationRulesEnabled,
            ),
            _DrawerTab.search =>
              widget.onSearch == null
                  ? const SizedBox.shrink()
                  : SearchPanel(
                      onSearch: widget.onSearch!,
                      onSearchStream: widget.onSearchStream,
                      onSelect: widget.onSearchSelect,
                    ),
          },
        ),
        if (widget.tab == _DrawerTab.search &&
            MediaQuery.maybeViewInsetsOf(context)?.bottom == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '输入关键词后点结果跳转',
              style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
          ),
      ],
    );
  }
}

/// 抽屉内的页签按钮（下划线指示当前页签）。
class _DrawerTabButton extends StatelessWidget {
  const _DrawerTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.buttonKey,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final activeColor = dark
        ? theme.colorScheme.onSurface
        : const Color(0xFF333333);
    final inactiveColor = dark
        ? theme.colorScheme.outline
        : const Color(0xFF999999);
    return Expanded(
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? activeColor : inactiveColor,
                ),
              ),
              if (selected)
                Positioned(
                  bottom: 0,
                  child: SizedBox(
                    width: 16,
                    height: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: activeColor,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 跳章浮层（P4-12，§27.2）：目标章名 + 不确定进度转圈，完成后淡出。
class _JumpLoadingOverlay extends StatelessWidget {
  const _JumpLoadingOverlay({required this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = title != null;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: visible
            ? ColoredBox(
                key: const ValueKey<String>('reader-jump-loading'),
                color: theme.colorScheme.surface.withValues(alpha: 0.92),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          '正在打开 $title',
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
