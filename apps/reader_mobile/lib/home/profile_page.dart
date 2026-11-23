import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';
import '../reader/reader_font_store.dart';
import '../theme/app_theme.dart';
import 'app_font_picker.dart';
import 'bookshelf_sort.dart';

/// 我的页：外观、书架设置、版本信息、诊断日志导出。
class ProfilePage extends StatefulWidget {
  /// 创建页面。
  const ProfilePage({
    super.key,
    required this.library,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.appFontFamily = AppFonts.defaultFamily,
    this.appFontStore,
    this.onAppFontFamilyChanged,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 已保存的界面主题选择。
  final ThemeMode themeMode;

  /// 切换并保存应用界面主题。
  final Future<void> Function(ThemeMode)? onThemeModeChanged;

  /// 当前应用字体。
  final String appFontFamily;

  /// 应用字体存储；为空时不显示应用字体入口。
  final ReaderFontStore? appFontStore;

  /// 切换并保存应用字体。
  final Future<void> Function(String family)? onAppFontFamilyChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  PackageInfo? _packageInfo;
  bool _exporting = false;
  bool _savingTheme = false;
  BookSortOrder _shelfSort = BookSortOrder.recent;
  bool _showShelfTitles = true;
  List<ReaderFontEntry> _appFonts = const [];

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform()
        .then((info) {
          if (mounted) {
            setState(() => _packageInfo = info);
          }
        })
        .catchError((_) {});
    _loadShelfPreferences();
    _loadAppFonts();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appFontStore != widget.appFontStore) {
      _loadAppFonts();
    }
  }

  Future<void> _loadAppFonts() async {
    final store = widget.appFontStore;
    if (store == null) {
      _appFonts = const [];
      return;
    }
    try {
      final fonts = await store.list();
      if (mounted) setState(() => _appFonts = fonts);
    } catch (error, stackTrace) {
      recordAppError('app_font_list_failed', error, stackTrace: stackTrace);
    }
  }

  Future<void> _loadShelfPreferences() async {
    final sort = await widget.library.getSetting(bookshelfSortKey);
    final showTitles = await widget.library.getSetting(bookshelfShowTitlesKey);
    if (mounted) {
      setState(() {
        _shelfSort = BookSortOrder.fromValue(sort);
        _showShelfTitles = showTitles != 'false';
      });
    }
  }

  Future<void> _chooseShelfSort() async {
    final selected = await showReaderDrawer<BookSortOrder>(
      context: context,
      builder: (context) => ReaderSheetForm(
        title: const Text('书架排序'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final order in BookSortOrder.values)
              ListTile(
                key: ValueKey<String>('bookshelf-sort-${order.value}'),
                contentPadding: EdgeInsets.zero,
                leading: AppIcon(
                  order == _shelfSort
                      ? AppGlyph.radioChecked
                      : AppGlyph.radioUnchecked,
                ),
                title: Text(order.label),
                selected: order == _shelfSort,
                selectedColor: Theme.of(context).colorScheme.onSurface,
                onTap: () => Navigator.of(context).pop(order),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() => _shelfSort = selected);
    await widget.library.setSetting(bookshelfSortKey, selected.value);
  }

  Future<void> _toggleShelfTitles(bool value) async {
    setState(() => _showShelfTitles = value);
    await widget.library.setSetting(bookshelfShowTitlesKey, '$value');
  }

  Future<void> _chooseTheme(ThemeMode current) async {
    final selected = await showReaderDrawer<ThemeMode>(
      context: context,
      builder: (context) => ReaderSheetForm(
        title: const Text('界面主题'),
        content: RadioGroup<ThemeMode>(
          groupValue: current,
          onChanged: (mode) => Navigator.of(context).pop(mode),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in ThemeMode.values)
                RadioListTile(
                  value: mode,
                  activeColor: Theme.of(context).colorScheme.onSurface,
                  contentPadding: EdgeInsets.zero,
                  title: Text(switch (mode) {
                    ThemeMode.system => '跟随系统',
                    ThemeMode.light => '日间模式',
                    ThemeMode.dark => '夜间模式',
                  }),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null || selected == current) return;
    setState(() => _savingTheme = true);
    try {
      await widget.onThemeModeChanged!(selected);
    } catch (error, stackTrace) {
      recordAppError('theme_save_failed', error, stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _savingTheme = false);
    }
  }

  String get _appFontLabel {
    if (widget.appFontFamily == AppFonts.defaultFamily) return '思源宋体';
    return _appFonts
            .where((font) => font.family == widget.appFontFamily)
            .firstOrNull
            ?.displayName ??
        '自定义字体';
  }

  Future<void> _chooseAppFont() async {
    final store = widget.appFontStore;
    final onChanged = widget.onAppFontFamilyChanged;
    if (store == null || onChanged == null) return;
    await showReaderDrawer<void>(
      context: context,
      builder: (_) => AppFontPickerSheet(
        fonts: _appFonts,
        selectedFamily: widget.appFontFamily,
        onSelect: onChanged,
        onImport: _importAppFont,
        onRemove: _removeAppFont,
      ),
    );
  }

  Future<ReaderFontEntry?> _importAppFont() async {
    final font = await widget.appFontStore!.pick();
    if (font != null) await _loadAppFonts();
    return font;
  }

  Future<void> _removeAppFont(String family) async {
    await widget.appFontStore!.remove(family);
    if (widget.appFontFamily == family) {
      await widget.onAppFontFamilyChanged!(AppFonts.defaultFamily);
    }
    await _loadAppFonts();
  }

  Future<void> _clearLogs() async {
    final confirmed = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: const Text('清理日志'),
        content: const Text('将删除本机保存的全部诊断日志（含历史会话），确定吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey<String>('logs-clear-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ReaderLog.instance.clear();
    } catch (error, stackTrace) {
      recordAppError('log_clear_failed', error, stackTrace: stackTrace);
    }
  }

  Future<void> _exportLogs() async {
    if (_exporting) {
      return;
    }
    setState(() => _exporting = true);
    final log = ReaderLog.instance;
    try {
      await log.log('export_logs');
      await log.exportFile();
      await log.share();
    } catch (error, stackTrace) {
      recordAppError('log_export_failed', error, stackTrace: stackTrace);
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _viewLogs() async {
    final text = await ReaderLog.instance.exportText();
    if (!mounted) return;
    await showReaderDrawer<void>(
      context: context,
      builder: (context) => ReaderSheetForm(
        title: const Text('诊断日志'),
        content: SelectableText(text.isEmpty ? '暂无日志' : text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _identity(context),
              const SizedBox(height: 24),
              if (widget.onThemeModeChanged != null) ...[
                _appearance(context),
                const SizedBox(height: 24),
              ],
              _section(context, '阅读', [
                ListTile(
                  key: const ValueKey<String>('bookshelf-sort-setting'),
                  leading: const AppIcon(AppGlyph.sort),
                  title: const Text('书架排序'),
                  subtitle: Text(_shelfSort.label),
                  trailing: const AppIcon(AppGlyph.chevronRight),
                  onTap: _chooseShelfSort,
                ),
                SwitchListTile(
                  key: const ValueKey<String>('bookshelf-title-setting'),
                  secondary: const AppIcon(AppGlyph.textFields),
                  title: const Text('显示书名'),
                  subtitle: const Text('关闭后书架只显示封面'),
                  value: _showShelfTitles,
                  onChanged: _toggleShelfTitles,
                ),
              ]),
              const SizedBox(height: 24),
              _section(context, '帮助与诊断', [
                ListTile(
                  leading: const AppIcon(AppGlyph.listBulleted),
                  title: const Text('查看诊断日志'),
                  subtitle: const Text('查看应用错误和运行记录'),
                  onTap: _viewLogs,
                ),
                ListTile(
                  leading: _exporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const AppIcon(AppGlyph.share),
                  title: const Text('导出诊断日志'),
                  subtitle: const Text('遇到阅读问题时，可随反馈附上'),
                  onTap: _exporting ? null : _exportLogs,
                ),
                ListTile(
                  key: const ValueKey<String>('logs-clear'),
                  leading: const AppIcon(AppGlyph.deleteSweep),
                  title: const Text('清理日志'),
                  subtitle: const Text('删除本机保存的全部诊断日志'),
                  onTap: _exporting ? null : _clearLogs,
                ),
              ]),
              const SizedBox(height: 24),
              Text('关于', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 10),
              Text(
                '本地 EPUB 阅读。书籍、阅读进度与笔记保存在设备上。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appearance(BuildContext context) {
    final mode = widget.themeMode;
    return _section(context, '外观', [
      ListTile(
        leading: const AppIcon(AppGlyph.palette),
        title: const Text('界面主题'),
        subtitle: Text(switch (mode) {
          ThemeMode.system => '跟随系统',
          ThemeMode.light => '日间模式',
          ThemeMode.dark => '夜间模式',
        }),
        trailing: const AppIcon(AppGlyph.chevronRight),
        onTap: _savingTheme ? null : () => _chooseTheme(mode),
      ),
      if (widget.appFontStore != null && widget.onAppFontFamilyChanged != null)
        ListTile(
          key: const ValueKey('app-font-setting'),
          leading: const AppIcon(AppGlyph.textFields),
          title: const Text('应用字体'),
          subtitle: Text(_appFontLabel),
          trailing: const AppIcon(AppGlyph.chevronRight),
          onTap: _chooseAppFont,
        ),
    ]);
  }

  Widget _identity(BuildContext context) {
    final info = _packageInfo;
    return Row(
      children: [
        Image.asset(
          'assets/branding/app_icon.png',
          width: 36,
          height: 36,
          cacheWidth: (36 * MediaQuery.devicePixelRatioOf(context)).round(),
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '墨屿',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                info == null
                    ? '正在读取版本…'
                    : '版本 ${info.version} · ${info.buildNumber}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 10),
        Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(4),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < rows.length; index++) ...[
                if (index > 0)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                rows[index],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
