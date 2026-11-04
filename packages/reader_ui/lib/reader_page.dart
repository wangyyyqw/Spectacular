import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:reader_core/api.dart' hide ComputedStyle;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/paint/paragraph_cache.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'annotations/annotation.dart';
import 'annotations/annotation_editor_sheet.dart';
import 'annotations/annotation_layer.dart';
import 'annotations/decorations.dart';
import 'annotations/note_composer_sheet.dart';
import 'a11y/semantics_layer.dart';
import 'footnote_dialog.dart';
import 'menu/reader_menu_overlay.dart';
import 'panels/margin_editor.dart';
import 'panels/tap_zone_editor.dart';
import 'page_furniture/page_furniture.dart';
import 'theme/reader_margins.dart';
import 'tap_zones.dart';
import 'annotations/relocator.dart';
import 'panels/annotation_panel.dart';
import 'panels/bookmark_panel.dart';
import 'panels/search_panel.dart';
import 'panels/settings_panel.dart';
import 'theme/reader_background.dart';
import 'theme/reader_environment.dart';
import 'selection/selection.dart';
import 'selection/selection_menu.dart';
import 'selection/selection_layer.dart';
import 'panels/toc_panel.dart';
import 'reader_session.dart';
import 'reader_view.dart';
import 'paging/continuous_scroll_view.dart';
import 'paging/page_turn_mode.dart';
import 'paging/page_turn_view.dart';
import 'theme/reader_theme.dart';
import 'loading_skeleton.dart';

/// 最小可运行的阅读页：打开、分页、绘制、翻页与进度恢复。
class ReaderPage extends StatefulWidget {
  /// 创建阅读页。
  const ReaderPage({
    super.key,
    required this.source,
    required this.store,
    required this.bookId,
    this.background = const Color(0xFFFFFFFF),
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    this.bookmarks,
    this.annotations,
    this.onOverridesChanged,
    this.onThemeChanged,
    this.backgroundId = 'none',
    this.inkMode = false,
    this.onBackgroundChanged,
    this.onInkModeChanged,
    this.onSearch,
    this.onSessionReady,
    this.imageCache,
    this.theme,
    this.overrides,
    this.paragraphCache,
    this.showPageFooter = true,
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
  });

  /// 章节页来源。
  final ReaderChapterSource source;

  /// 书签存储（P4-13）；为 null 时菜单不显示书签入口。
  final ReaderBookmarkStore? bookmarks;

  /// 标注存储（P4-17）；为 null 时选区菜单不显示高亮/笔记。
  final ReaderAnnotationStore? annotations;

  /// 排版设置变化（P4-21）：调用方负责持久化。
  final ValueChanged<ReaderOverrides>? onOverridesChanged;

  /// 主题变化（P4-21）：调用方负责持久化。
  final ValueChanged<String>? onThemeChanged;

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

  /// 页面背景。
  final Color background;

  /// 正文区外边距。
  final EdgeInsets padding;

  /// 页脚页码（P8-10 页家具 6 槽的第一槽；槽模板与设置项后续接入）。
  final bool showPageFooter;

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

  /// 会话就绪回调（测试/调试）。
  final ValueChanged<ReaderSession>? onSessionReady;

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
  late final ParagraphCache _paragraphCache =
      widget.paragraphCache ?? ParagraphCache(maxEntries: 256);
  late final bool _ownsParagraphCache = widget.paragraphCache == null;
  late PagePainter _painter = _buildPainter();

  /// 当前排版设置（P4-21：设置面板可改，初始来自 widget.overrides）。
  late ReaderOverrides _overrides;

  /// 当前主题（P4-21：设置面板可切）。
  late ReaderTheme? _theme;

  /// 当前背景（P4-22）：纹理解码结果缓存在这里，换背景不重排。
  late String _backgroundId;
  ui.Image? _backgroundImage;

  /// 墨水屏模式（P4-23）：为 true 时强制纯黑白主题、禁用背景纹理。
  late bool _inkMode;
  late PageTurnMode _pageTurnMode = widget.pageTurnMode;
  final _pageTurnKey = GlobalKey<PageTurnViewState>();
  final _scrollKey = GlobalKey<ContinuousScrollViewState>();

  PageTurnMode get _effectiveTurnMode =>
      _inkMode || MediaQuery.disableAnimationsOf(context)
      ? PageTurnMode.none
      : _pageTurnMode;

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

  /// 调节器草稿：实时参与当前章分页，保存前不写入设置和阅读进度。
  ReaderMargins? _previewMargins;

  /// 已保存的页边距：取消预览时恢复。
  ReaderMargins? _savedMargins;

  /// 从基础 padding 生成调节器值，保证打开调节器时画面不跳。
  ReaderMargins _marginsFromPadding(EdgeInsets padding) {
    return ReaderMargins(
      left: padding.left,
      right: padding.right,
      topOuter: padding.top,
      topInner: widget.showPageFooter ? PageFurniture.headerGap : 0,
      bottomInner: widget.showPageFooter ? PageFurniture.footerGap : 0,
      bottomOuter: padding.bottom,
    );
  }

  /// 当前生效的页边距（未设置时按实际安全区 + padding 推导）。
  ReaderMargins get _activeMargins =>
      _previewMargins ??
      _savedMargins ??
      _marginsFromPadding(_fallbackPadding());

  /// 首次进入阅读页时的默认边距，恢复默认后仍保持原排版。
  ReaderMargins get _defaultMargins =>
      _marginsFromPadding(_fallbackPadding());

  ReaderMargins? get _layoutMargins => _previewMargins ?? _savedMargins;

  /// 菜单是否展开（设计稿沉浸式菜单）。
  bool _menuOpen = false;

  /// 当前打开的抽屉。
  ReaderMenuEntry? _drawer;

  /// 目录抽屉里的二级页签（内容/书签/笔记/搜索）。
  _DrawerTab _drawerTab = _DrawerTab.content;

  /// 已聚焦过的页（P4-28：每页只自动聚焦一次）。
  String? _lastFocusedPageKey;

  /// 新页首块焦点（P4-28）：翻页后把焦点落到第一块，读屏/键盘续读不跳段。
  final FocusNode _semanticsFirstFocus = FocusNode(
    debugLabel: 'reader-first-block',
  );

  /// 搜索命中的临时高亮（P4-26，§29.4：3 秒后消失）。
  ReaderAnnotation? _tempHighlight;
  Timer? _tempHighlightTimer;

  /// 当前阅读环境（P4-23）。
  ReaderEnvironment get _environment =>
      ReaderEnvironment(isEink: _inkMode);

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
      imageLookup: widget.imageCache?.lookup,
      listMarkerImageOf: (block) => block.style?.listStyleImage,
      textColor: theme?.text,
      paragraphCache: _paragraphCache,
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
        headerHeight: PageFurniture.headerHeight,
        footerHeight: PageFurniture.footerHeight,
      );
    }
    final base = _effectivePadding();
    if (!widget.showPageFooter) {
      return base;
    }
    return base + const EdgeInsets.only(
      top: PageFurniture.headerHeight + PageFurniture.headerGap,
      bottom: PageFurniture.footerHeight + PageFurniture.footerGap,
    );
  }

  /// 整页背景图页（封面/扉页）：整页只有一块背景图，四角信息都不画。
  ///
  /// 这类页整页都是图，页眉页脚压上去只会挡图，与多看/阅微一致。
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

  /// 顶部出血页（章首横幅图）：只让位页眉，页脚（时间 + 进度）保留。
  bool _hasTopBleed(PageContent page) =>
      page.slices.any((slice) => slice.block.bleedTop);

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

  /// 全书进度（0..1）：章进度 + 章内页进度。
  double _bookProgressOf(PageContent page) {
    final chapters = widget.source.chapterCount;
    if (chapters <= 0) {
      return 0;
    }
    final pagesInChapter = _session.chapterPageCount;
    final within = pagesInChapter <= 0 ? 0.0 : (page.pageIndex + 1) / pagesInChapter;
    return ((page.spineIndex + within) / chapters).clamp(0.0, 1.0);
  }

  /// 已预取过的页键（spine*100000 + pageIndex），避免重复预取。
  int _prefetchedPageKey = -1;

  /// 图片缓存版本号，解码完成后触发重绘。
  int _imageRevision = 0;

  /// 上一次布局的正文区尺寸（旋转/窗口变化检测，P2-31）。
  Size? _lastContentSize;
  double? _lastContentTopInset;
  bool? _lastContentSizePreview;
  Future<void>? _initialOpen;

  /// 预取页内图片；解码完成后 setState，占位替换为真图。
  ///
  /// [notify] 为 false 时只等待解码，不更新图片版本。翻页快照需要图片已
  /// 就绪，但版本变化会触发 PageTurnView 清空快照并取消进行中的手势。
  Future<void> _prefetchPageImages(
    PageContent page,
    double displayWidth, {
    bool notify = true,
  }) async {
    final cache = widget.imageCache;
    if (cache == null) {
      return;
    }
    final urls = <String>{};
    final visited = <PageBlock>{};

    void addStyle(ComputedStyle? style) {
      final image = style?.backgroundImage;
      if (image != null && image.isNotEmpty) {
        urls.add(image);
      }
    }

    void addBlock(PageBlock block) {
      if (!visited.add(block)) {
        return;
      }
      addStyle(block.style);
      for (final fragment in block.containers) {
        addStyle(fragment.container.style);
      }
      for (final image in block.inlineImages) {
        urls.add(image.url);
      }
      for (final line in block.layout.lines) {
        for (final placement in line.inlineBoxes) {
          final payload = placement.spec.payload;
          if (payload is PageBlock) {
            addBlock(payload);
          }
        }
      }
      // Flex 行和普通表格都以单元格样式承载图片背景，不能只扫外层块样式。
      final cells = block.table?.cells;
      if (cells != null) {
        for (final cell in cells) {
          addStyle(cell.style);
          for (final line in cell.layout.lines) {
            for (final placement in line.inlineBoxes) {
              final payload = placement.spec.payload;
              if (payload is PageBlock) {
                addBlock(payload);
              }
            }
          }
        }
      }
    }

    for (final slice in page.slices) {
      addBlock(slice.block);
    }
    // 整页背景（P9-04）：body 的 background-image 也要预解码。
    if (page.background != null) {
      urls.add(page.background!.imageUrl);
    }
    if (urls.isEmpty) {
      return;
    }
    final before = cache.revision;
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    await cache.prefetch(
      urls,
      displayWidth: displayWidth,
      devicePixelRatio: ratio,
    );
    if (!notify || !mounted || cache.revision == before) {
      return;
    }
    setState(() => _imageRevision = cache.revision);
  }

  /// 翻页快照前准备目标页图片；不触发版本失效，避免取消当前手势。
  Future<void> _prepareTurnPageImages(PageContent page) {
    final width = _lastContentSize?.width ?? 0;
    if (width <= 0) {
      return Future<void>.value();
    }
    return _prefetchPageImages(page, width, notify: false);
  }

  /// 尺寸变化（旋转/窗口缩放）时通知会话重排并恢复位置（P2-31）。
  void _scheduleContentSize(Size pageSize) {
    final padding = _bodyPadding();
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
        _lastContentSizePreview == preview) {
      return;
    }
    _lastContentSize = content;
    _lastContentTopInset = padding.top;
    _lastContentSizePreview = preview;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyContentSize(content, padding.top, preview);
    });
  }

  void _applyContentSize(Size content, double topInset, bool preview) {
    final opening = _initialOpen;
    if (opening == null) {
      _initialOpen = _session.open(
        overrides: _effectiveOverrides(),
        contentWidth: content.width,
        contentHeight: content.height,
        contentTopInset: topInset,
      );
      return;
    }
    unawaited(
      opening.then((_) async {
        if (!mounted) return;
        await _session.applyContentSize(
          width: content.width,
          height: content.height,
          topInset: topInset,
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
    if (_prefetchedPageKey == key) {
      return;
    }
    _prefetchedPageKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prefetchPageImages(page, displayWidth);
      }
    });
  }

  /// 当前页选区（P4-15）；翻页/点菜单时清除。
  ReaderSelection? _selection;

  /// 连续滚动长按命中的页切片；分页模式保持为空。
  PageContent? _selectionPage;

  /// 笔记编辑层打开时隐藏选区菜单，避免菜单悬在遮罩后方。
  bool _hideSelectionMenu = false;

  /// 全书标注（P4-18）：打开时加载，标注变更后刷新。
  List<ReaderAnnotation> _annotations = const <ReaderAnnotation>[];

  /// 可绘制的标注（P4-20：重定位后；失效标注保留数据但不绘制）。
  List<ReaderAnnotation> _resolvedAnnotations = const <ReaderAnnotation>[];

  /// 已重定位的章（换章或重排后重算）。
  int? _relocatedSpineIndex;

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
    unawaited(_loadBackground(_backgroundId));
    // 沉浸模式（P8-10 收尾）：阅读页隐藏状态栏与导航栏，退出时恢复。
    // sticky：边缘下滑可临时唤出系统栏，几秒后自动隐藏。
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      ),
    );
    _session = ReaderSession(
      source: widget.source,
      store: widget.store,
      bookId: widget.bookId,
    );
    widget.onSessionReady?.call(_session);
    unawaited(_reloadAnnotations());
  }

  @override
  void didUpdateWidget(ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageTurnMode != widget.pageTurnMode) {
      _pageTurnMode = widget.pageTurnMode;
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
    if (oldWidget.inkMode != widget.inkMode) {
      _inkMode = widget.inkMode;
      _painter = _buildPainter();
    }
    if (oldWidget.backgroundId != widget.backgroundId) {
      unawaited(_loadBackground(widget.backgroundId));
    }
    if (oldWidget.overrides != widget.overrides &&
        widget.overrides != null) {
      _overrides = widget.overrides!;
    }
    if (oldWidget.theme != widget.theme ||
        oldWidget.background != widget.background ||
        oldWidget.imageCache != widget.imageCache) {
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
          _DrawerTab.annotations => '笔记',
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
      '${page.pageIndex + 1}/${_session.chapterPageCount} 页';

  /// 打开/关闭沉浸式菜单（设计稿 `.screen.menu-open`）。
  void _toggleReaderMenu() {
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

  /// 进度滑杆：按全书百分比跳章。
  Future<void> _seekToProgress(double percent) async {
    final chapters = widget.source.chapterCount;
    if (chapters <= 0) {
      return;
    }
    final target = (percent * chapters).floor().clamp(0, chapters - 1);
    if (target == (_session.progress?.spineIndex ?? 0)) {
      return;
    }
    await _session.jumpToChapter(target);
  }

  /// 日/夜快速切换（设计稿顶部栏的日间夜间按钮）。
  void _toggleDayNight() {
    final current = (_theme ?? ReaderTheme.white).id;
    final dark = current == 'dark' || current == 'black';
    _applyTheme(dark ? 'white' : 'dark');
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

  /// 拖拽产生的页内局部选区 → 全局跨页选区（P4-19）。
  void _applyLocalSelection(ReaderSelection local) {
    final page = _selectionPage ?? _session.page;
    if (page == null || _selection == null) {
      return;
    }
    setState(() {
      _selection = ReaderSelection.spanning(
        start: local.start,
        startPageIndex: page.pageIndex,
        end: local.end,
        endPageIndex: page.pageIndex,
      );
    });
  }

  /// 拖到页边 → 延时 300ms 翻页并扩展选区（§63.5）。
  void _handleSelectionEdgeDrag(bool forward) {
    _selectionEdgeTimer?.cancel();
    _selectionEdgeTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(forward ? _extendSelectionForward() : _extendSelectionBackward());
    });
  }

  Future<void> _extendSelectionForward() async {
    final selection = _selection;
    final page = _session.page;
    if (selection == null || page == null) {
      return;
    }
    final changed = await _session.next();
    if (!changed || !mounted) {
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
    if (selection == null || page == null) {
      return;
    }
    final changed = await _session.previous();
    if (!changed || !mounted) {
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
      '第 ${page.pageIndex + 1} 页，共 $totalPages 页',
      TextDirection.ltr,
    );
  }

  /// 应用搜索结果（P4-26，§29.4）：跳到命中位置并临时高亮 3 秒。
  Future<void> _applySearchResult(SearchPanelResult result) async {
    // 扫描式搜索不给每条命中算 CFI，这里按点击结果现场排版这一章。
    var cfi = result.cfi;
    cfi ??= await widget.onResolveSearchCfi?.call(result);
    if (cfi == null || !mounted) {
      return;
    }
    final resolvedCfi = cfi;
    final offset = cfiCharOffset(resolvedCfi);
    await _session.jumpToCfi(
      resolvedCfi,
      title: result.chapterTitle,
      continuous: _effectiveTurnMode == PageTurnMode.scroll,
    );
    // 表格只能提供精确元素页锚点时，不伪造文本节点的字符高亮区间。
    if (!mounted || offset == null) {
      return;
    }
    final endCfi = cfiWithCharOffset(resolvedCfi, offset + result.matchLength);
    _tempHighlightTimer?.cancel();
    setState(() {
      _tempHighlight = ReaderAnnotation(
        id: 'search-hit',
        type: ReaderAnnotationType.highlight,
        startCfi: resolvedCfi,
        endCfi: endCfi,
        quote: result.context,
        color: 0xFFFFC107,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _relocatedSpineIndex = _session.page?.spineIndex;
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
    if (next.fingerprint == _overrides.fingerprint) {
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
      _painter = _buildPainter();
    });
    unawaited(_session.applyOverrides(_effectiveOverrides()));
    widget.onThemeChanged?.call(themeId);
  }

  /// 加载并应用背景（P4-22）：只解码一次并缓存，换背景不重排。
  Future<void> _loadBackground(String id) async {
    final background = ReaderBackground.byId(id);
    final asset = background.asset;
    if (asset == null) {
      setState(() {
        _backgroundId = background.id;
        _backgroundImage?.dispose();
        _backgroundImage = null;
        _painter = _buildPainter();
      });
      return;
    }
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() {
      _backgroundId = background.id;
      _backgroundImage?.dispose();
      _backgroundImage = frame.image;
      _painter = _buildPainter();
    });
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
  void _applyBackground(String id) {
    unawaited(_loadBackground(id));
    widget.onBackgroundChanged?.call(id);
  }

  /// 恢复默认设置（P4-21）。
  void _resetSettings() {
    final resetMargins = _savedMargins != null;
    _applyOverrides(ReaderSettingsDefaults.overrides);
    _applyTheme(ReaderSettingsDefaults.themeId);
    _applyBackground(ReaderBackground.none.id);
    _applyPageTurnMode(PageTurnMode.cover);
    _applyInkMode(false);
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

  void _applyPageTurnMode(PageTurnMode mode) {
    if (mode == _pageTurnMode) return;
    _pageTurnKey.currentState?.controller.cancel();
    _clearSelection();
    setState(() => _pageTurnMode = mode);
    widget.onPageTurnModeChanged?.call(mode);
    _log('user_page_turn_mode', {'mode': mode.id});
  }

  /// 重新加载全书标注（P4-18）并重定位到当前章（P4-20）。
  Future<void> _reloadAnnotations() async {
    final store = widget.annotations;
    if (store == null) {
      return;
    }
    final items = await store.list();
    if (!mounted) {
      return;
    }
    setState(() => _annotations = items);
    await _relocateAnnotations();
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
    final items = _annotations;
    if (items.isEmpty) {
      setState(() {
        _resolvedAnnotations = const <ReaderAnnotation>[];
        _relocatedSpineIndex = _session.page?.spineIndex;
      });
      return;
    }
    final spine = _session.page?.spineIndex;
    final pages = await _session.chapterPages();
    if (!mounted) {
      return;
    }
    final relocations = AnnotationRelocator.relocate(
      annotations: items,
      pages: pages,
    );
    setState(() {
      _resolvedAnnotations = <ReaderAnnotation>[
        for (final relocation in relocations)
          if (relocation.isResolved) relocation.resolved,
      ];
      _relocatedSpineIndex = spine;
    });
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
      _selectionSpineIndex = page.spineIndex;
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
      _selectionSpineIndex = page.spineIndex;
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

  /// 单击注释引用：命中时打开弹窗并消费本次点击，避免同时翻页。
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
        builder: (context) => ReaderFootnoteDialog(
          footnote: footnote,
          imageCache: widget.imageCache,
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
    final persistent = <ReaderAnnotation>[
      for (final annotation in _resolvedAnnotations)
        if (annotation.id != 'search-hit') annotation,
    ];
    final annotation = AnnotationDecorations.annotationAt(
      page,
      pagePosition,
      persistent,
    );
    if (annotation != null) {
      _clearSelection();
      unawaited(_editAnnotation(annotation));
      return true;
    }
    return _openFootnoteInPage(page, pagePosition);
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
      builder: (context) => ReaderAnnotationEditorSheet(
        annotation: annotation,
        inkMode: _inkMode,
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    await _applyAnnotationEdit(annotation, action);
  }

  Future<void> _applyAnnotationEdit(
    ReaderAnnotation annotation,
    AnnotationEditAction action,
  ) async {
    final store = widget.annotations;
    if (store == null) {
      return;
    }
    final note = action.note?.trim();
    if (note != null && note.isEmpty) {
      return;
    }
    var message = note == null
        ? '已更新高亮'
        : annotation.type == ReaderAnnotationType.highlight
        ? '已添加笔记'
        : '笔记已更新';
    var removed = false;
    var removedNote = false;
    switch (action.type) {
      case AnnotationEditActionType.save:
        await store.update(
          annotation.id,
          type: note != null && annotation.type == ReaderAnnotationType.highlight
              ? ReaderAnnotationType.note
              : null,
          color: action.color,
          style: action.style,
          note: note,
        );
      case AnnotationEditActionType.removeNote:
        await store.update(
          annotation.id,
          type: ReaderAnnotationType.highlight,
          color: action.color,
          style: action.style,
          clearNote: true,
        );
        removedNote = true;
        message = '已删除笔记正文，保留高亮';
      case AnnotationEditActionType.remove:
        await store.remove(annotation.id);
        removed = true;
        message = annotation.type == ReaderAnnotationType.note
            ? '已删除笔记'
            : '已取消高亮';
    }
    if (!mounted) {
      return;
    }
    await _reloadAnnotations();
    if (mounted) {
      if (removed) {
        _showToast(
          message,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => unawaited(_restoreAnnotation(annotation)),
          ),
        );
      } else if (removedNote) {
        _showToast(
          message,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => unawaited(_restoreRemovedNote(annotation)),
          ),
        );
      } else {
        _showToast(message);
      }
    }
  }

  Future<void> _restoreRemovedNote(ReaderAnnotation annotation) async {
    final store = widget.annotations;
    if (store == null) {
      return;
    }
    try {
      await store.update(
        annotation.id,
        type: ReaderAnnotationType.note,
        color: annotation.color,
        style: annotation.style,
        note: annotation.note,
      );
      await _reloadAnnotations();
      if (mounted) {
        _showToast('已恢复笔记');
      }
    } catch (_) {
      if (mounted) {
        _showToast('恢复失败，请重试');
      }
    }
  }

  Future<void> _restoreAnnotation(ReaderAnnotation annotation) async {
    final store = widget.annotations;
    if (store == null) {
      return;
    }
    try {
      final restored = await store.add(
        type: annotation.type,
        startCfi: annotation.startCfi,
        endCfi: annotation.endCfi,
        quote: annotation.quote,
        contextBefore: annotation.contextBefore,
        contextAfter: annotation.contextAfter,
        color: annotation.color,
        style: annotation.style,
        note: annotation.note,
      );
      if (!mounted) {
        return;
      }
      if (restored == null) {
        _showToast('无法撤销：该位置已有标注');
        return;
      }
      await _reloadAnnotations();
      if (mounted) {
        _showToast(
          annotation.type == ReaderAnnotationType.note ? '已恢复笔记' : '已恢复高亮',
        );
      }
    } catch (_) {
      if (mounted) {
        _showToast('恢复失败，请重试');
      }
    }
  }

  /// 选区菜单动作（P4-16）：复制 / 全选 / 取消。
  List<SelectionAction> _selectionActions(
    PageContent page,
    ReaderSelection selection,
  ) => <SelectionAction>[
    if (widget.annotations != null)
      SelectionAction(
        id: 'highlight',
        label: '高亮',
        onTap: () => unawaited(
          _saveAnnotation(page, selection, ReaderAnnotationType.highlight),
        ),
      ),
    if (widget.annotations != null)
      SelectionAction(
        id: 'note',
        label: '笔记',
        onTap: () => unawaited(_addNote(page, selection)),
      ),
    SelectionAction(
      id: 'copy',
      label: '复制',
      onTap: () => unawaited(_copySelection(page, selection)),
    ),
    SelectionAction(id: 'select-all', label: '全选', onTap: () => _selectAll(page)),
    SelectionAction(id: 'dismiss', label: '取消', onTap: _clearSelection),
  ];

  /// 保存高亮/笔记（P4-17）：CFI 区间 + 原文 + 前后文。
  Future<void> _saveAnnotation(
    PageContent page,
    ReaderSelection selection,
    ReaderAnnotationType type, {
    String? note,
  }) async {
    final store = widget.annotations;
    if (store == null) {
      return;
    }
    final cfi = SelectionOps.cfiOf(selection);
    final quote = selection.isMultiPage
        ? SelectionOps.textAcrossPages(await _session.chapterPages(), selection)
        : SelectionOps.textOf(page, selection);
    if (cfi == null || quote.isEmpty) {
      _showToast('当前位置不支持标注');
      return;
    }
    final context = SelectionOps.contextOf(page, selection);
    final created = await store.add(
      type: type,
      startCfi: cfi.start,
      endCfi: cfi.end,
      quote: quote,
      contextBefore: context.before,
      contextAfter: context.after,
      color: type == ReaderAnnotationType.highlight
          ? defaultHighlightColor
          : null,
      note: note,
    );
    if (!mounted) {
      return;
    }
    if (created != null) {
      unawaited(_reloadAnnotations());
    }
    _clearSelection();
    if (created != null) {
      _showToast(
        type == ReaderAnnotationType.note ? '已添加笔记' : '已高亮',
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => unawaited(_removeCreatedAnnotation(created)),
        ),
      );
      return;
    }
    _showToast('该位置已有标注');
  }

  /// 撤销刚创建的标注，避免误触后还要去批注列表删除。
  Future<void> _removeCreatedAnnotation(ReaderAnnotation annotation) async {
    final store = widget.annotations;
    if (store == null) {
      return;
    }
    try {
      await store.remove(annotation.id);
      await _reloadAnnotations();
      if (mounted) {
        _showToast('已撤销');
      }
    } catch (_) {
      if (mounted) {
        _showToast('撤销失败，请重试');
      }
    }
  }

  /// 输入笔记正文后保存（P4-17）。
  Future<void> _addNote(PageContent page, ReaderSelection selection) async {
    final quote = selection.isMultiPage
        ? SelectionOps.textAcrossPages(
            await _session.chapterPages(),
            selection,
          )
        : SelectionOps.textOf(page, selection);
    if (!mounted) {
      return;
    }
    setState(() => _hideSelectionMenu = true);
    try {
      final note = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ReaderNoteComposerSheet(
          quote: quote,
        ),
      );
      if (!mounted || note == null || note.trim().isEmpty) {
        return;
      }
      await _saveAnnotation(
        page,
        selection,
        ReaderAnnotationType.note,
        note: note.trim(),
      );
    } finally {
      if (mounted) {
        setState(() => _hideSelectionMenu = false);
      }
    }
  }

  Future<void> _copySelection(PageContent page, ReaderSelection selection) async {
    final text = selection.isMultiPage
        ? SelectionOps.textAcrossPages(
            await _session.chapterPages(),
            selection,
          )
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
        _selectionPage = null;
        _selectionSpineIndex = null;
        _hideSelectionMenu = false;
      });
    }
  }

  void _showToast(
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 1),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    // 新反馈应替换旧提示，避免撤销条把后续操作结果排队遮挡。
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

  /// 切后台/失去焦点时立即落盘（P4-10）：系统回收不丢最后一次翻页。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pageTurnKey.currentState?.controller.cancel();
      unawaited(_session.flushProgress());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 退出阅读页：恢复系统栏（edge-to-edge），并复位到浅色图标语义。
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    _session.cancelPendingLoads();
    _session.dispose();
    if (_ownsParagraphCache) {
      _paragraphCache.dispose();
    }
    _selectionEdgeTimer?.cancel();
    _tempHighlightTimer?.cancel();
    _semanticsFirstFocus.dispose();
    _backgroundImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        // 背景铺满窗口（P8-10 收尾）：加载骨架/错误态/正文页统一以主题
        // 背景色打底，避免 padding 外区域透出窗口黑底。
        return LayoutBuilder(
          builder: (context, constraints) {
            _scheduleContentSize(Size(constraints.maxWidth, constraints.maxHeight));
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
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final page = _session.page;
    // 翻页后焦点落到新页首块（P4-28）；面板/弹层打开时不抢焦点。
    final pageKey = page == null ? null : '${page.spineIndex}/${page.pageIndex}';
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

    // 换章（拼页/跳转）后重算标注位置；重排后块 CFI 不变，仍会 verified。
    if (page != null &&
        _annotations.isNotEmpty &&
        _relocatedSpineIndex != page.spineIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_relocateAnnotations());
        }
      });
    }

    // 页面不在选区范围内（翻章/跳转）→ 下一帧清除；跨页选区范围内保留。
    // 回调里重新取最新状态：边缘翻页会先翻页再扩展选区，两者不能互相打断。
    if (page != null && _selection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final current = _selection;
        final currentPage = _session.page;
        if (current == null || currentPage == null) {
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
        _schedulePrefetch(page, size.width - bodyPadding.horizontal);
        // 出血页把整页让给图：绘制画布取满屏，正文由 pageInsets 内缩，
        // 出血块才能铺到屏幕边缘。页眉页脚按页类型让位：
        // - 整页背景图页（封面/扉页）：页眉页脚都不画；
        // - 顶部出血页（章首横幅图）：只让位页眉，页脚保留。
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
            if (_selection != null) ...[
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
                      contentPadding: selectionPadding,
                      onChanged: _applyLocalSelection,
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
              progress: _bookProgressOf(page),
              chapterLabel: _chapterLabelOf(page),
              onBack: () {
                Navigator.of(context).maybePop();
              },
              onToggleDayNight: _toggleDayNight,
              nightMode: (_theme ?? ReaderTheme.white).background.computeLuminance() <
                  0.35,
              onPreviousChapter: page.spineIndex <= 0 || _session.jumpLoadingTitle != null
                  ? null : () {
                _closeDrawer();
                unawaited(_session.jumpToChapter(page.spineIndex - 1));
              },
              onNextChapter: page.spineIndex >= widget.source.chapterCount - 1 ||
                  _session.jumpLoadingTitle != null ? null : () {
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
                      currentSpineIndex:
                          _session.progress?.spineIndex ?? 0,
                      currentCfi: _session.currentCfi,
                      bookmarks: widget.bookmarks,
                      annotations: widget.annotations,
                      annotationItems: _annotations,
                      hasCfi: _session.currentCfi != null,
                      overrides: _overrides,
                      themeId: (_theme ?? ReaderTheme.white).id,
                      backgroundId: _backgroundId,
                      inkMode: _inkMode,
                      pageTurnMode: _pageTurnMode,
                      onPageTurnModeChanged: _applyPageTurnMode,
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
                        _closeDrawer();
                        unawaited(_applySearchResult(result));
                      },
                      onTocSelect: (entry) {
                        _closeDrawer();
                        unawaited(
                          _session.jumpToChapter(
                            entry.spineIndex,
                            title: entry.title,
                          ),
                        );
                      },
                      onBookmarkSelect: (bookmark) {
                        _closeDrawer();
                        unawaited(
                          _session.jumpToCfi(
                            bookmark.cfi,
                            title: bookmark.label,
                            continuous:
                                _effectiveTurnMode == PageTurnMode.scroll,
                          ),
                        );
                      },
                      onAddBookmark: () {
                        unawaited(_addBookmark());
                      },
                      onAnnotationSelect: (annotation) {
                        _closeDrawer();
                        unawaited(
                          _session.jumpToCfi(
                            annotation.startCfi,
                            title: annotation.quote,
                            continuous:
                                _effectiveTurnMode == PageTurnMode.scroll,
                          ),
                        );
                      },
                      onAnnotationEdit: (annotation) {
                        unawaited(_editAnnotation(annotation));
                      },
                      onAnnotationDelete: _deleteAnnotations,
                      onAnnotationRecolor: _recolorAnnotations,
                      onOpenMarginEditor: () {
                        _closeDrawer();
                        _toggleReaderMenu();
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

  Widget _buildMarginEditor() => MarginEditor(
    margins: _activeMargins,
    defaults: _defaultMargins,
    onPreview: (margins) => setState(() => _previewMargins = margins),
    showPageFurniture: widget.showPageFooter,
    onCancel: () => setState(() {
      _editingMargins = false;
      _finishingMarginEdit = true;
      _previewMargins = null;
    }),
    onApply: (margins) {
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

  Widget _buildReadingView(Size size) {
    final revision = (
      _painter,
      _imageRevision,
      _resolvedAnnotations,
      _tempHighlight,
      _bodyPadding(),
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
          onPageVisible: (page) =>
              _schedulePrefetch(page, size.width - padding.horizontal),
        ),
      );
    }
    return ReaderView(
      config: ReaderGestureConfig(
        tapZones: _tapZones,
        verticalWriting: _readingRtl,
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
      onDragCancel: () => _pageTurnKey.currentState?.controller.cancel(),
      onLongPressAt: _selectWordAt,
      onDoubleTapAt: _selection == null ? null : _selectWordAt,
      onTripleTapAt: _selection == null ? null : _selectSentenceAt,
      onTapAt: (point) => _pageTurnKey.currentState?.controller.active == true
          ? false
          : _handleTapAt(point),
      child: PageTurnView(
        key: _pageTurnKey,
        session: _session,
        mode: _effectiveTurnMode,
        revision: revision,
        paperBuilder: _buildPaper,
        paperColor: _effectiveTheme?.background ?? widget.background,
        preparePageImages: _prepareTurnPageImages,
        rtl: _readingRtl,
      ),
    );
  }

  Widget _buildPaper(PageContent page, Size size) => ClipRect(
    key: ValueKey('reader-page-${page.spineIndex}-${page.pageIndex}'),
    child: Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _ReaderPageCustomPainter(
            page: page,
            painter: _painter,
            imageRevision: _imageRevision,
            pageInsets: _bodyPadding(),
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
              ),
            ),
          ),
        ..._paperFurniture(page),
      ],
    ),
  );

  Widget _buildScrollPaper(PageContent page, Size size) => ClipRect(
    key: ValueKey('scroll-page-${page.spineIndex}-${page.pageIndex}'),
    child: Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _ReaderPageCustomPainter(
            page: page,
            painter: _painter,
            imageRevision: _imageRevision,
          ),
        ),
        if (_resolvedAnnotations.isNotEmpty || _tempHighlight != null)
          Positioned.fill(
            child: AnnotationLayer(
              page: page,
              annotations: [..._resolvedAnnotations, ?_tempHighlight],
              inkMode: _inkMode,
            ),
          ),
      ],
    ),
  );

  List<Widget> _paperFurniture(PageContent page) {
    final padding = _furniturePadding();
    final full = _isFullPageBackground(page);
    return [
      if (widget.showPageFooter && !full && !_hasTopBleed(page))
        Positioned(
          left: padding.left,
          right: padding.right,
          top: padding.top,
          child: IgnorePointer(
            child: ReaderPageHeader(
              theme: _effectiveTheme,
              title: _chapterTitleOf(page.spineIndex),
              pageLabel:
                  '${page.pageIndex + 1}/${_session.pageCountOf(page.spineIndex)}',
              inkMode: _inkMode,
            ),
          ),
        ),
      if (widget.showPageFooter && !full)
        Positioned(
          left: padding.left,
          right: padding.right,
          bottom: padding.bottom,
          child: IgnorePointer(
            child: ReaderPageFooter(
              theme: _effectiveTheme,
              progress: _bookProgressOf(page),
              inkMode: _inkMode,
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
    required this.imageRevision,
    this.pageInsets = EdgeInsets.zero,
  });

  final PageContent page;
  final PagePainter painter;
  final int imageRevision;

  /// 正文区相对整页的内缩（页边距 + 页眉页脚槽）。
  final EdgeInsets pageInsets;

  @override
  void paint(Canvas canvas, Size size) {
    // 画布是整页；正文由 pageInsets 内缩，出血块由绘制层扩到页边。
    painter.paint(canvas, page, pageSize: size, pageInsets: pageInsets);
  }

  @override
  bool shouldRepaint(_ReaderPageCustomPainter oldDelegate) =>
      oldDelegate.page != page ||
      oldDelegate.imageRevision != imageRevision ||
      oldDelegate.pageInsets != pageInsets ||
      oldDelegate.painter.background != painter.background ||
      oldDelegate.painter.textColor != painter.textColor;
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

  /// 笔记与高亮列表。
  annotations,

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
    required this.hasCfi,
    required this.overrides,
    required this.themeId,
    required this.backgroundId,
    required this.inkMode,
    required this.pageTurnMode,
    required this.onPageTurnModeChanged,
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
  final bool hasCfi;
  final ReaderOverrides overrides;
  final String themeId;
  final String backgroundId;
  final bool inkMode;
  final PageTurnMode pageTurnMode;
  final ValueChanged<PageTurnMode> onPageTurnModeChanged;
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
          onPageTurnModeChanged: widget.onPageTurnModeChanged,
          onOverridesChanged: widget.onOverridesChanged,
          onThemeChanged: widget.onThemeChanged,
          onInkModeChanged: widget.onInkModeChanged,
          onReset: widget.onResetSettings,
          onOpenTapZoneEditor: widget.onOpenTapZoneEditor,
        );
    }
  }

  Widget _buildTocDrawer(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        // 目录抽屉内的二级页签：目录 / 书签 / 笔记 / 搜索。
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
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
                  label: '笔记',
                  selected: widget.tab == _DrawerTab.annotations,
                  onTap: () => widget.onTabChanged(_DrawerTab.annotations),
                ),
              if (widget.onSearch != null)
                _DrawerTabButton(
                  buttonKey: const ValueKey<String>('drawer-tab-search'),
                  label: '搜索',
                  selected: widget.tab == _DrawerTab.search,
                  onTap: () => widget.onTabChanged(_DrawerTab.search),
                ),
              const Spacer(),
              if (widget.tab == _DrawerTab.content && widget.hasCfi)
                TextButton.icon(
                  key: const ValueKey<String>('drawer-add-bookmark'),
                  onPressed: widget.onAddBookmark,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('加书签'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
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
              onSelect: widget.onAnnotationSelect,
              onEdit: widget.onAnnotationEdit,
              onDelete: widget.onAnnotationDelete,
              onRecolor: widget.onAnnotationRecolor,
            ),
            _DrawerTab.search => widget.onSearch == null
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
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
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      key: buttonKey,
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: selected ? scheme.onSurface : scheme.outline,
        textStyle: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      child: label == label
          ? Text(label)
          : Text(label),
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
