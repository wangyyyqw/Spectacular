import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/library_store.dart';
import '../rea_micro/rea_micro_controller.dart';
import '../storage/startup_storage.dart';
import 'bookshelf_page.dart';
import 'profile_page.dart';
import 'reviews_page.dart';
import 'stats_page.dart';

/// 四底栏应用壳：书架 / 统计 / 书评 / 我的。
class HomeShell extends StatefulWidget {
  /// 创建壳。
  const HomeShell({
    super.key,
    required this.library,
    required this.progressStore,
    this.storageRecovery,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 进度存储。
  final ReaderProgressStore progressStore;

  /// 数据库不可用时的恢复入口；正常页面与测试可省略。
  final StartupStorage? storageRecovery;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  int _bookshelfRefreshToken = 0;
  int _statsRefreshToken = 0;
  bool _exportingDiagnostics = false;
  late final ReaMicroController _reaMicro;
  late final ReaderProgressStore _progressStore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reaMicro = ReaMicroController(
      library: widget.library,
      progressStore: widget.progressStore,
    );
    _progressStore = _reaMicro.trackedProgressStore ?? widget.progressStore;
    unawaited(_reaMicro.initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reaMicro.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reaMicro.scheduleReadingSync();
    }
  }

  void _onReadingFinished() => _reaMicro.scheduleReadingSync();

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

  Widget _buildBody(List<Widget> pages) {
    final content = IndexedStack(index: _index, children: pages);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navigationTheme = theme.bottomNavigationBarTheme;
    final unselectedColor =
        navigationTheme.unselectedItemColor ??
        theme.colorScheme.onSurfaceVariant;
    final selectedColor =
        navigationTheme.selectedItemColor ?? theme.colorScheme.onSurface;
    final navigationBackground =
        navigationTheme.backgroundColor ?? theme.canvasColor;
    final pages = <Widget>[
      BookshelfPage(
        library: widget.library,
        progressStore: _progressStore,
        refreshToken: _bookshelfRefreshToken,
        allowImport: widget.storageRecovery == null,
        onReadingFinished: _onReadingFinished,
      ),
      StatsPage(
        library: widget.library,
        progressStore: _progressStore,
        refreshToken: _statsRefreshToken,
        active: _index == 1,
        onReadingFinished: _onReadingFinished,
      ),
      ReviewsPage(library: widget.library, active: _index == 2),
      ProfilePage(library: widget.library, reaMicro: _reaMicro),
    ];
    return Scaffold(
      body: _buildBody(pages),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (value) {
            setState(() {
              _index = value;
              if (value == 0) {
                _bookshelfRefreshToken += 1;
              } else if (value == 1) {
                _statsRefreshToken += 1;
              }
            });
          },
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: AppIcon(
                AppGlyph.bookshelf,
                size: 24,
                color: unselectedColor,
              ),
              activeIcon: AppIcon(
                AppGlyph.bookshelf,
                size: 24,
                color: selectedColor,
                filled: true,
                cutoutColor: navigationBackground,
              ),
              label: '书架',
            ),
            BottomNavigationBarItem(
              icon: AppIcon(AppGlyph.stats, size: 24, color: unselectedColor),
              activeIcon: AppIcon(
                AppGlyph.stats,
                size: 24,
                color: selectedColor,
                filled: true,
              ),
              label: '统计',
            ),
            BottomNavigationBarItem(
              icon: AppIcon(AppGlyph.review, size: 24, color: unselectedColor),
              activeIcon: AppIcon(
                AppGlyph.review,
                size: 24,
                color: selectedColor,
                filled: true,
                cutoutColor: navigationBackground,
              ),
              label: '书评',
            ),
            BottomNavigationBarItem(
              icon: AppIcon(AppGlyph.profile, size: 24, color: unselectedColor),
              activeIcon: AppIcon(
                AppGlyph.profile,
                size: 24,
                color: selectedColor,
                filled: true,
                cutoutColor: navigationBackground,
              ),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
