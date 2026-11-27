import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_ink.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import '../book_source/online_book_controller.dart';
import '../editing/epub_file_editor_page.dart';
import '../library/library_store.dart';
import '../rea_micro/rea_micro_controller.dart';
import '../rea_micro/rea_micro_models.dart';
import '../reader/book_opener.dart';
import '../reader/reader_font_store.dart';
import '../storage/startup_storage.dart';
import '../theme/app_theme.dart';
import 'bookshelf_page.dart';
import 'discover_page.dart';
import 'desktop_layout.dart';
import 'desktop_shortcuts_dialog.dart';
import 'profile_page.dart';
import 'reviews_page.dart';
import 'stats_page.dart';
import 'welcome_announcement.dart';
import 'navigation_settings.dart';
import '../diagnostics/reader_log.dart';
import '../sync/sync_controller.dart';

/// 首页应用壳：桌面平台使用侧栏，移动平台使用底栏。
class HomeShell extends StatefulWidget {
  /// 创建壳。
  const HomeShell({
    super.key,
    required this.library,
    required this.progressStore,
    this.storageRecovery,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.uiStyle = AppUiStyle.classic,
    this.onUiStyleChanged,
    this.appFontFamily = AppFonts.defaultFamily,
    this.appFontStore,
    this.onAppFontFamilyChanged,
    this.showWelcomeAnnouncement = false,
    this.onBookshelfReady,
    this.onSyncPreferences,
    this.windowTopInset = 0,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 进度存储。
  final ReaderProgressStore progressStore;

  /// 数据库不可用时的恢复入口；正常页面与测试可省略。
  final StartupStorage? storageRecovery;

  /// 已保存的界面主题选择，独立于当前实际亮度。
  final ThemeMode themeMode;

  /// 切换并保存应用界面主题。
  final Future<void> Function(ThemeMode)? onThemeModeChanged;

  /// 当前应用控件风格。
  final AppUiStyle uiStyle;

  /// 保存并应用应用控件风格。
  final Future<void> Function(AppUiStyle)? onUiStyleChanged;

  /// 当前应用字体。
  final String appFontFamily;

  /// 应用字体存储。
  final ReaderFontStore? appFontStore;

  /// 切换并保存应用字体。
  final Future<void> Function(String family)? onAppFontFamilyChanged;

  /// 正式应用启动启用公告；独立组件测试可直接构造壳。
  final bool showWelcomeAnnouncement;

  /// 书架前 12 本封面就绪后通知开屏退场。
  final VoidCallback? onBookshelfReady;
  final VoidCallback? onSyncPreferences;

  /// macOS 系统标题栏的高度，侧边栏背景需要延伸覆盖该区域。
  final double windowTopInset;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  /// 收起宽度需容纳 macOS 红绿灯，并让左右留白接近。
  static const double _collapsedRailWidth = 84;
  static const double _expandedRailWidth = 160;

  late SyncController _sync;
  int _syncRevision = 0;
  int _index = 0;
  int _bookshelfRefreshToken = 0;
  int _statsRefreshToken = 0;
  bool _exportingDiagnostics = false;
  late final ReaMicroController _reaMicro;
  late final OnlineBookController _onlineBooks;
  late final ReaderProgressStore _progressStore;
  late final BookOpener _bookOpener;
  late final NavigationSettings _navigation;
  int _discoveryRevision = 0;
  bool _promptingDiscovery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reaMicro = ReaMicroController(
      library: widget.library,
      progressStore: widget.progressStore,
    );
    _onlineBooks = OnlineBookController(library: widget.library);
    _navigation = NavigationSettings(widget.library, _reaMicro)
      ..addListener(_navigationChanged);
    _onlineBooks.addListener(_sourcesChanged);
    unawaited(_navigation.initialize());
    _progressStore = _reaMicro.trackedProgressStore ?? widget.progressStore;
    _bookOpener = BookOpener(
      library: widget.library,
      progressStore: _progressStore,
      onlineBooks: _onlineBooks,
      onReadingFinished: _onReadingFinished,
      loadTtsVoices: _loadTtsVoices,
      loadFinishedReview: _reaMicro.loadFinishedReview,
      saveFinishedReview: _reaMicro.saveFinishedReview,
    );
    if (widget.showWelcomeAnnouncement) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          runWelcomeFlow(
            context: context,
            library: widget.library,
            controller: _reaMicro,
          ),
        );
      });
    } else {
      unawaited(_reaMicro.initialize());
    }
    unawaited(_onlineBooks.initialize());
    _startSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync.removeListener(_onSyncChanged);
    _sync.dispose();
    _reaMicro.dispose();
    _navigation.removeListener(_navigationChanged);
    _navigation.dispose();
    _onlineBooks.removeListener(_sourcesChanged);
    _onlineBooks.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reaMicro.handleAppResumed();
      _sync.resumed();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _sync.paused();
    }
  }

  void _onReadingFinished() => _reaMicro.scheduleReadingSync();

  List<int> get _visibleIndices => [
    for (var index = 0; index < 4; index++)
      if (_navigation.visible(HomeDestination.values[index])) index,
    if (_desktop) 4,
    _desktop ? 5 : 4,
  ];

  void _navigationChanged() {
    if (!mounted) return;
    setState(() {
      if (!_visibleIndices.contains(_index)) {
        final old = _index;
        _index = 0;
        if (_pages.isNotEmpty) {
          _pages[old] = _buildPage(old);
          _pages[0] = _buildPage(0);
        }
      }
    });
  }

  void _sourcesChanged() {
    final revision = _onlineBooks.discoveryImportRevision;
    if (_discoveryRevision == revision) return;
    _discoveryRevision = revision;
    if (_navigation.selected(HomeDestination.discover) ||
        _navigation.discoveryPromptHandled ||
        _promptingDiscovery) {
      return;
    }
    _promptingDiscovery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final enable = await showReaderDialog<bool>(
        context: context,
        builder: (context) => ReaderFrostedAlertDialog(
          title: const Text('启用发现'),
          content: const Text('检测到已添加支持发现页面的源，是否启用发现页面。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('禁用发现'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('启用发现'),
            ),
          ],
        ),
      );
      if (!mounted || enable == null) {
        _promptingDiscovery = false;
        return;
      }
      await _navigation.markDiscoveryPromptHandled();
      if (enable) await _navigation.setVisible(HomeDestination.discover, true);
      _promptingDiscovery = false;
    });
  }

  Future<List<ReaMicroTtsVoice>> _loadTtsVoices() async {
    try {
      return (await _reaMicro.fetchTtsCatalog()).voices;
    } catch (_) {
      return const [];
    }
  }

  bool _desktop = false;
  bool? _railCollapsed;
  List<Widget> _pages = [];
  MediaQueryData? _homeMedia;
  bool _restoringSystemPadding = false;

  void _startSync() {
    _sync = SyncController(widget.library)..addListener(_onSyncChanged);
    unawaited(_sync.initialize());
  }

  void _onSyncChanged() {
    if (!mounted || _syncRevision == _sync.dataRevision) return;
    _syncRevision = _sync.dataRevision;
    setState(() {
      _bookshelfRefreshToken++;
      _statsRefreshToken++;
      if (_pages.isNotEmpty) {
        _pages = List.generate(_desktop ? 6 : 5, _buildPage);
      }
    });
    if (_sync.profile?.preferences == true) widget.onSyncPreferences?.call();
  }

  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library != widget.library) {
      _sync.removeListener(_onSyncChanged);
      _sync.dispose();
      _syncRevision = 0;
      _startSync();
    }
    if (oldWidget.library != widget.library ||
        oldWidget.progressStore != widget.progressStore ||
        oldWidget.storageRecovery != widget.storageRecovery ||
        oldWidget.themeMode != widget.themeMode ||
        oldWidget.onThemeModeChanged != widget.onThemeModeChanged ||
        oldWidget.uiStyle != widget.uiStyle ||
        oldWidget.onUiStyleChanged != widget.onUiStyleChanged ||
        oldWidget.appFontFamily != widget.appFontFamily ||
        oldWidget.appFontStore != widget.appFontStore ||
        oldWidget.onAppFontFamilyChanged != widget.onAppFontFamilyChanged ||
        oldWidget.onBookshelfReady != widget.onBookshelfReady) {
      _pages = [];
    }
  }

  Future<void> _retryStorage() async {
    if (_exportingDiagnostics) return;
    final restored = await widget.storageRecovery!.retry();
    if (mounted && !restored) recordAppEvent('storage_retry_failed');
  }

  Future<void> _exportDiagnostics() async {
    if (_exportingDiagnostics || widget.storageRecovery!.isOpening) return;
    setState(() => _exportingDiagnostics = true);
    final exported = await widget.storageRecovery!.exportDiagnostics();
    if (!mounted) return;
    setState(() => _exportingDiagnostics = false);
    if (!exported) recordAppEvent('storage_diagnostics_export_failed');
  }

  void _selectDestination(int index) {
    if (index == _index) return;
    setState(() {
      final previous = _index;
      _index = index;
      if (index == 0) {
        _bookshelfRefreshToken += 1;
      } else if (index == 2) {
        _statsRefreshToken += 1;
      }
      // 只更新切入与切出页；其余隐藏页复用，避免重新筛书和汇总统计。
      _pages[previous] = _buildPage(previous);
      _pages[index] = _buildPage(index);
    });
  }

  Widget _buildPage(int index) => switch (index) {
    0 => BookshelfPage(
      library: widget.library,
      progressStore: _progressStore,
      refreshToken: _bookshelfRefreshToken,
      active: _index == 0,
      allowImport: widget.storageRecovery == null,
      onReadingFinished: _onReadingFinished,
      reaMicro: _reaMicro,
      onlineBooks: _onlineBooks,
      bookOpener: _bookOpener,
      onInitialCoversReady: widget.onBookshelfReady,
    ),
    1 => DiscoverPage(
      controller: _onlineBooks,
      onRead: _bookOpener.openOnline,
      active: _index == 1,
    ),
    2 => StatsPage(
      bookOpener: _bookOpener,
      library: widget.library,
      progressStore: _progressStore,
      refreshToken: _statsRefreshToken,
      active: _index == 2,
      onReadingFinished: _onReadingFinished,
      reaMicro: _reaMicro,
    ),
    3 => ReviewsPage(
      library: widget.library,
      active: _index == 3,
      reaMicro: _reaMicro,
    ),
    4 when _desktop => EpubFileEditorPage(active: _index == 4),
    _ => ProfilePage(
      library: widget.library,
      reaMicro: _reaMicro,
      onlineBooks: _onlineBooks,
      onReadOnline: _bookOpener.openOnline,
      themeMode: widget.themeMode,
      onThemeModeChanged: widget.onThemeModeChanged,
      uiStyle: widget.uiStyle,
      onUiStyleChanged: widget.onUiStyleChanged,
      appFontFamily: widget.appFontFamily,
      appFontStore: widget.appFontStore,
      onAppFontFamilyChanged: widget.onAppFontFamilyChanged,
      navigationSettings: _navigation,
      sync: _sync,
    ),
  };

  Widget _buildBody(bool desktop) {
    if (_pages.isEmpty || _desktop != desktop) {
      _desktop = desktop;
      _pages = List.generate(desktop ? 6 : 5, _buildPage);
    }
    final content = IndexedStack(
      index: _index,
      children: [
        for (final (index, page) in _pages.indexed)
          TickerMode(
            enabled: index == _index,
            child: ExcludeFocus(
              excluding: index != _index,
              child: RepaintBoundary(child: page),
            ),
          ),
      ],
    );
    final recovery = widget.storageRecovery;
    if (recovery == null) return content;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildStorageBanner(recovery),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildStorageBanner(StartupStorage recovery) {
    final theme = Theme.of(context);
    final busy = recovery.isOpening || _exportingDiagnostics;
    return MaterialBanner(
      key: const ValueKey<String>('temporary-storage-banner'),
      backgroundColor: theme.colorScheme.errorContainer,
      leading: AppIcon(AppGlyph.warning, color: theme.colorScheme.error),
      forceActionsBelow: true,
      content: _buildStorageMessage(theme),
      actions: [
        TextButton(
          key: const ValueKey<String>('storage-retry'),
          onPressed: busy ? null : _retryStorage,
          child: Text(recovery.isOpening ? '正在重试…' : '重试'),
        ),
        TextButton(
          key: const ValueKey<String>('storage-export-diagnostics'),
          onPressed: busy ? null : _exportDiagnostics,
          child: Text(_exportingDiagnostics ? '正在导出…' : '导出诊断'),
        ),
      ],
    );
  }

  Widget _buildStorageMessage(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('本地数据库不可用，当前为临时模式', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      const Text('持久化不可用，原书库与阅读记录暂时无法读取。原有文件已保留，恢复前已暂停导入。'),
    ],
  );

  List<BottomNavigationBarItem> _navigationItems(ThemeData theme) {
    final navigationTheme = theme.bottomNavigationBarTheme;
    final unselectedColor =
        navigationTheme.unselectedItemColor ??
        theme.colorScheme.onSurfaceVariant;
    final selectedColor = theme.useMaterial3
        ? theme.colorScheme.onSecondaryContainer
        : navigationTheme.selectedItemColor ?? theme.colorScheme.onSurface;
    final navigationBackground =
        navigationTheme.backgroundColor ?? theme.canvasColor;
    final iconOffset = Offset(0, usesDesktopLayout(context) ? 0 : 2);
    final definitions = [
      ('书架', AppGlyph.bookshelf),
      ('发现', AppGlyph.discover),
      ('统计', AppGlyph.stats),
      ('笔记', AppGlyph.review),
      if (usesDesktopLayout(context)) ('编辑', AppGlyph.edit),
      ('我的', AppGlyph.profile),
    ];
    return [
      for (final index in _visibleIndices)
        BottomNavigationBarItem(
          label: definitions[index].$1,
          icon: Transform.translate(
            offset: iconOffset,
            child: AppIcon(
              definitions[index].$2,
              size: 24,
              color: unselectedColor,
            ),
          ),
          activeIcon: Transform.translate(
            offset: iconOffset,
            child: AppIcon(
              definitions[index].$2,
              size: 24,
              color: selectedColor,
              filled: true,
              cutoutColor: theme.useMaterial3
                  ? theme.colorScheme.secondaryContainer
                  : navigationBackground,
            ),
          ),
        ),
    ];
  }

  Widget _buildRail(
    ThemeData theme,
    List<BottomNavigationBarItem> items,
    bool collapsed,
    bool canExpand,
  ) {
    final colors = theme.colorScheme;
    final background =
        theme.bottomNavigationBarTheme.backgroundColor ?? theme.canvasColor;
    return AnimatedContainer(
      key: const ValueKey('home-sidebar'),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: collapsed ? _collapsedRailWidth : _expandedRailWidth,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(widget.windowTopInset > 0 ? 0 : 14),
          bottomRight: const Radius.circular(14),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: .12),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: NavigationRail(
              extended: !collapsed,
              scrollable: true,
              minWidth: 56,
              minExtendedWidth: 160,
              backgroundColor: Colors.transparent,
              useIndicator: theme.useMaterial3,
              indicatorColor: colors.secondaryContainer,
              unselectedIconTheme: const IconThemeData(opacity: 1),
              selectedLabelTextStyle: theme.textTheme.titleSmall?.copyWith(
                color: theme.useMaterial3
                    ? colors.onSurface
                    : colors.primary,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelTextStyle: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
              selectedIndex: _visibleIndices.indexOf(_index),
              onDestinationSelected: (index) =>
                  _selectDestination(_visibleIndices[index]),
              destinations: [
                for (final item in items)
                  NavigationRailDestination(
                    icon: Tooltip(message: item.label!, child: item.icon),
                    selectedIcon: Tooltip(
                      message: item.label!,
                      child: item.activeIcon,
                    ),
                    label: Text(item.label!),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Align(
            alignment: AlignmentDirectional.bottomStart,
            child: Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? 8 : 12, 4, 8, 4),
              child: IconButton(
                tooltip: '桌面快捷键（F1）',
                onPressed: () =>
                    showDesktopShortcuts(context, destinations: items),
                icon: const AppIcon(AppGlyph.info, size: 18),
              ),
            ),
          ),
          if (canExpand) ...[
            Align(
              alignment: AlignmentDirectional.bottomStart,
              child: Padding(
                padding: EdgeInsets.fromLTRB(collapsed ? 8 : 12, 4, 8, 8),
                child: IconButton(
                  tooltip: collapsed ? '展开侧边栏' : '收起侧边栏',
                  onPressed: () => setState(() => _railCollapsed = !collapsed),
                  icon: AnimatedRotation(
                    turns: collapsed ? .5 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: const AppIcon(AppGlyph.chevronLeft, size: 18),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 阅读页隐藏系统栏时保留首页安全区，返回后不随系统栏恢复动画挪动布局。
  MediaQueryData _homeLayoutMedia() {
    final media = MediaQuery.of(context);
    final previous = _homeMedia;
    if (previous == null || previous.size != media.size) {
      _restoringSystemPadding = false;
      return _homeMedia = media;
    }
    if (ModalRoute.isCurrentOf(context) == false) {
      _restoringSystemPadding = true;
    }
    final padding = previous.viewPadding;
    final pending =
        _restoringSystemPadding &&
        (media.viewPadding.top < padding.top ||
            media.viewPadding.bottom < padding.bottom);
    if (!pending) {
      _restoringSystemPadding = false;
      return _homeMedia = media;
    }
    return media.copyWith(
      viewPadding: media.viewPadding.copyWith(
        top: padding.top,
        bottom: padding.bottom,
      ),
      padding: media.padding.copyWith(
        top: math.max(0, padding.top - media.viewInsets.top),
        bottom: math.max(0, padding.bottom - media.viewInsets.bottom),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => _layout(context, bounds.maxWidth),
  );

  Widget _layout(BuildContext context, double width) {
    final theme = Theme.of(context);
    final useRail = usesDesktopLayout(context);
    // 窄窗优先让出正文空间；回到宽窗恢复用户手动选择或默认展开。
    final collapsed = width < 600 || (_railCollapsed ?? width < 1000);
    final pages = Expanded(child: _buildBody(useRail));
    final items = _navigationItems(theme);
    final scaffold = MediaQuery(
      data: _homeLayoutMedia(),
      child: Scaffold(
        body: Row(
          children: [
            if (useRail) _buildRail(theme, items, collapsed, width >= 600),
            pages,
          ],
        ),
        bottomNavigationBar: useRail
            ? null
            : theme.useMaterial3
            ? NavigationBar(
                selectedIndex: _visibleIndices.indexOf(_index),
                onDestinationSelected: (index) =>
                    _selectDestination(_visibleIndices[index]),
                destinations: [
                  for (final item in items)
                    NavigationDestination(
                      icon: item.icon,
                      selectedIcon: item.activeIcon,
                      label: item.label!,
                    ),
                ],
              )
            : Material(
                color: theme.colorScheme.surface,
                elevation: 2,
                shadowColor: theme.colorScheme.shadow.withValues(alpha: .12),
                child: Theme(
                  // 底栏四个入口不显示点击高亮与水波。
                  data: quietInk(theme),
                  child: BottomNavigationBar(
                    backgroundColor: theme.colorScheme.surface,
                    elevation: 0,
                    currentIndex: _visibleIndices.indexOf(_index),
                    onTap: (index) =>
                        _selectDestination(_visibleIndices[index]),
                    items: items,
                  ),
                ),
              ),
      ),
    );
    if (!useRail) return scaffold;
    final railBackground =
        theme.bottomNavigationBarTheme.backgroundColor ?? theme.canvasColor;
    final sidebarWidth = collapsed ? _collapsedRailWidth : _expandedRailWidth;
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        scaffold,
        if (widget.windowTopInset > 0)
          AnimatedPositioned(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            left: 0,
            top: -widget.windowTopInset,
            width: sidebarWidth,
            height: widget.windowTopInset,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: railBackground,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(14),
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(alpha: .12),
                    blurRadius: 10,
                    offset: const Offset(2, 0),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    final macOS = theme.platform == TargetPlatform.macOS;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.f1,
          includeRepeats: false,
        ): () {
          if (ModalRoute.isCurrentOf(context) != false) {
            unawaited(showDesktopShortcuts(context, destinations: items));
          }
        },
        for (final (index, key) in const [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.digit6,
        ].indexed)
          SingleActivator(
            key,
            meta: macOS,
            control: !macOS,
            includeRepeats: false,
          ): () {
            if (ModalRoute.isCurrentOf(context) != false) {
              if (index < _visibleIndices.length) {
                _selectDestination(_visibleIndices[index]);
              }
            }
          },
      },
      child: Focus(autofocus: true, child: content),
    );
  }
}
