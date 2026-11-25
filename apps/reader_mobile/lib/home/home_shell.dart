import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_ink.dart';

import '../editing/epub_file_editor_page.dart';
import '../library/library_store.dart';
import '../reader/reader_font_store.dart';
import '../storage/startup_storage.dart';
import '../theme/app_theme.dart';
import 'bookshelf_page.dart';
import 'desktop_layout.dart';
import 'profile_page.dart';
import 'reviews_page.dart';
import 'stats_page.dart';
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
    this.appFontFamily = AppFonts.defaultFamily,
    this.appFontStore,
    this.onAppFontFamilyChanged,
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

  /// 当前应用字体。
  final String appFontFamily;

  /// 应用字体存储。
  final ReaderFontStore? appFontStore;

  /// 切换并保存应用字体。
  final Future<void> Function(String family)? onAppFontFamilyChanged;

  /// 书架前 12 本封面就绪后通知开屏退场。
  final VoidCallback? onBookshelfReady;
  final VoidCallback? onSyncPreferences;

  /// macOS 标题栏红绿灯区域的顶部高度；侧边栏背景需要补到该区域。
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
  bool _desktop = false;
  bool _railCollapsed = false;
  List<Widget> _pages = [];
  MediaQueryData? _homeMedia;
  bool _restoringSystemPadding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startSync();
  }

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
        _pages = List.generate(_desktop ? 5 : 4, _buildPage);
      }
    });
    if (_sync.profile?.preferences == true) widget.onSyncPreferences?.call();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync.resumed();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _sync.paused();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync.removeListener(_onSyncChanged);
    _sync.dispose();
    super.dispose();
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
      } else if (index == 1) {
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
      progressStore: widget.progressStore,
      refreshToken: _bookshelfRefreshToken,
      active: _index == 0,
      allowImport: widget.storageRecovery == null,
      onInitialCoversReady: widget.onBookshelfReady,
    ),
    1 => StatsPage(
      library: widget.library,
      progressStore: widget.progressStore,
      refreshToken: _statsRefreshToken,
      active: _index == 1,
    ),
    2 => ReviewsPage(library: widget.library, active: _index == 2),
    3 when _desktop => EpubFileEditorPage(active: _index == 3),
    _ => ProfilePage(
      library: widget.library,
      themeMode: widget.themeMode,
      onThemeModeChanged: widget.onThemeModeChanged,
      appFontFamily: widget.appFontFamily,
      appFontStore: widget.appFontStore,
      onAppFontFamilyChanged: widget.onAppFontFamilyChanged,
      sync: _sync,
    ),
  };

  Widget _buildBody(bool desktop) {
    if (_pages.isEmpty || _desktop != desktop) {
      _desktop = desktop;
      _pages = List.generate(desktop ? 5 : 4, _buildPage);
    }
    final content = IndexedStack(
      index: _index,
      children: [
        for (final (index, page) in _pages.indexed)
          TickerMode(
            enabled: index == _index,
            child: ExcludeFocus(excluding: index != _index, child: page),
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
    final selectedColor =
        navigationTheme.selectedItemColor ?? theme.colorScheme.onSurface;
    final navigationBackground =
        navigationTheme.backgroundColor ?? theme.canvasColor;
    final iconOffset = Offset(0, usesDesktopLayout(context) ? 0 : 2);
    return [
      for (final (label, glyph) in [
        ('书架', AppGlyph.bookshelf),
        ('统计', AppGlyph.stats),
        ('笔记', AppGlyph.review),
        if (usesDesktopLayout(context)) ('编辑', AppGlyph.edit),
        ('我的', AppGlyph.profile),
      ])
        BottomNavigationBarItem(
          label: label,
          icon: Transform.translate(
            offset: iconOffset,
            child: AppIcon(glyph, size: 24, color: unselectedColor),
          ),
          activeIcon: Transform.translate(
            offset: iconOffset,
            child: AppIcon(
              glyph,
              size: 24,
              color: selectedColor,
              filled: true,
              cutoutColor: navigationBackground,
            ),
          ),
        ),
    ];
  }

  Widget _buildRail(ThemeData theme, List<BottomNavigationBarItem> items) {
    final colors = theme.colorScheme;
    final background =
        theme.bottomNavigationBarTheme.backgroundColor ?? theme.canvasColor;
    return AnimatedContainer(
      key: const ValueKey('home-sidebar'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: _railCollapsed ? _collapsedRailWidth : _expandedRailWidth,
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
              extended: !_railCollapsed,
              scrollable: true,
              minWidth: 56,
              minExtendedWidth: 160,
              backgroundColor: Colors.transparent,
              useIndicator: false,
              unselectedIconTheme: const IconThemeData(opacity: 1),
              selectedLabelTextStyle: theme.textTheme.titleSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelTextStyle: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
              selectedIndex: _index,
              onDestinationSelected: _selectDestination,
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
              padding: EdgeInsets.fromLTRB(_railCollapsed ? 8 : 12, 4, 8, 8),
              child: IconButton(
                tooltip: _railCollapsed ? '展开侧边栏' : '收起侧边栏',
                onPressed: () =>
                    setState(() => _railCollapsed = !_railCollapsed),
                icon: AnimatedRotation(
                  turns: _railCollapsed ? .5 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: const AppIcon(AppGlyph.chevronLeft, size: 18),
                ),
              ),
            ),
          ),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _navigationItems(theme);
    final useRail = usesDesktopLayout(context);
    final pages = Expanded(child: _buildBody(useRail));
    final scaffold = MediaQuery(
      data: _homeLayoutMedia(),
      child: Scaffold(
        body: Row(children: [if (useRail) _buildRail(theme, items), pages]),
        bottomNavigationBar: useRail
            ? null
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
                    currentIndex: _index,
                    onTap: _selectDestination,
                    items: items,
                  ),
                ),
              ),
      ),
    );
    if (!useRail) return scaffold;
    final railBackground =
        theme.bottomNavigationBarTheme.backgroundColor ?? theme.canvasColor;
    final sidebarWidth = _railCollapsed
        ? _collapsedRailWidth
        : _expandedRailWidth;
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        scaffold,
        if (widget.windowTopInset > 0)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
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
        for (final (index, key) in const [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit5,
        ].indexed)
          SingleActivator(
            key,
            meta: macOS,
            control: !macOS,
            includeRepeats: false,
          ): () {
            if (ModalRoute.isCurrentOf(context) != false) {
              _selectDestination(index);
            }
          },
      },
      child: Focus(autofocus: true, child: content),
    );
  }
}
