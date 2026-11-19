import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/library_store.dart';
import '../storage/startup_storage.dart';
import 'bookshelf_page.dart';
import 'profile_page.dart';
import 'reviews_page.dart';
import 'stats_page.dart';

const _railBreakpoint = 840.0;

/// 首页应用壳：宽窗使用侧栏，窄窗保留底栏。
class HomeShell extends StatefulWidget {
  /// 创建壳。
  const HomeShell({
    super.key,
    required this.library,
    required this.progressStore,
    this.storageRecovery,
    this.onThemeModeChanged,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 进度存储。
  final ReaderProgressStore progressStore;

  /// 数据库不可用时的恢复入口；正常页面与测试可省略。
  final StartupStorage? storageRecovery;

  /// 切换并保存应用界面主题。
  final Future<void> Function(ThemeMode)? onThemeModeChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _bookshelfRefreshToken = 0;
  int _statsRefreshToken = 0;
  bool _exportingDiagnostics = false;

  Future<void> _retryStorage() async {
    if (_exportingDiagnostics) return;
    final restored = await widget.storageRecovery!.retry();
    if (mounted && !restored) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地数据库仍不可用，请稍后重试')),
      );
    }
  }

  Future<void> _exportDiagnostics() async {
    if (_exportingDiagnostics || widget.storageRecovery!.isOpening) return;
    setState(() => _exportingDiagnostics = true);
    final exported = await widget.storageRecovery!.exportDiagnostics();
    if (!mounted) return;
    setState(() => _exportingDiagnostics = false);
    if (!exported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('诊断导出失败，请稍后重试')),
      );
    }
  }

  void _selectDestination(int index) {
    setState(() {
      _index = index;
      if (index == 0) {
        _bookshelfRefreshToken += 1;
      } else if (index == 1) {
        _statsRefreshToken += 1;
      }
    });
  }

  Widget _buildBody() {
    final content = IndexedStack(
      index: _index,
      children: [
        BookshelfPage(
          library: widget.library,
          progressStore: widget.progressStore,
          refreshToken: _bookshelfRefreshToken,
          active: _index == 0,
          allowImport: widget.storageRecovery == null,
        ),
        StatsPage(
          library: widget.library,
          progressStore: widget.progressStore,
          refreshToken: _statsRefreshToken,
          active: _index == 1,
        ),
        ReviewsPage(library: widget.library, active: _index == 2),
        ProfilePage(
          library: widget.library,
          onThemeModeChanged: widget.onThemeModeChanged,
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
      Text(
        '本地数据库不可用，当前为临时模式',
        style: theme.textTheme.titleSmall,
      ),
      const SizedBox(height: 4),
      const Text(
        '持久化不可用，原书库与阅读记录暂时无法读取。原有文件已保留，恢复前已暂停导入。',
      ),
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
    return [
      for (final (label, glyph) in const [
        ('书架', AppGlyph.bookshelf),
        ('统计', AppGlyph.stats),
        ('书评', AppGlyph.review),
        ('我的', AppGlyph.profile),
      ])
        BottomNavigationBarItem(
          label: label,
          icon: AppIcon(glyph, size: 24, color: unselectedColor),
          activeIcon: AppIcon(
            glyph,
            size: 24,
            color: selectedColor,
            filled: true,
            cutoutColor: navigationBackground,
          ),
        ),
    ];
  }

  Widget _buildRail(ThemeData theme, List<BottomNavigationBarItem> items) {
    return NavigationRail(
      extended: true,
      scrollable: true,
      minWidth: 56,
      minExtendedWidth: 160,
      backgroundColor:
          theme.bottomNavigationBarTheme.backgroundColor ?? theme.canvasColor,
      useIndicator: false,
      unselectedIconTheme: const IconThemeData(opacity: 1),
      selectedLabelTextStyle: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      selectedIndex: _index,
      onDestinationSelected: _selectDestination,
      destinations: [
        for (final item in items)
          NavigationRailDestination(
            icon: item.icon,
            selectedIcon: item.activeIcon,
            label: Text(item.label!),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _navigationItems(theme);
    final pages = Expanded(child: _buildBody());
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= _railBreakpoint;
        return Scaffold(
          body: Row(
            children: [
              if (useRail) ...[
                _buildRail(theme, items),
                VerticalDivider(width: 1, color: theme.dividerColor),
              ],
              pages,
            ],
          ),
          bottomNavigationBar: useRail
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: theme.dividerColor)),
                  ),
                  child: BottomNavigationBar(
                    currentIndex: _index,
                    onTap: _selectDestination,
                    items: items,
                  ),
                ),
        );
      },
    );
  }
}
