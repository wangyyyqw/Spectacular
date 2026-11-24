import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../book_source/online_book_controller.dart';
import '../dictionary/dictionary_store.dart';
import '../dictionary/dictionary_settings_page.dart';
import '../book_source/online_book_detail_page.dart';
import '../book_source/online_source_page.dart';
import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';
import '../reader/reader_font_store.dart';
import '../reader/reader_settings.dart';
import 'about_page.dart';
import '../theme/app_theme.dart';
import '../theme/theme_color_settings.dart';
import 'app_font_picker.dart';
import 'bookshelf_sort.dart';
import 'navigation_settings.dart';
import 'navigation_settings_page.dart';
import 'theme_color_settings_page.dart';

/// 应用设置：外观、阅读、帮助与诊断和关于。
class AppSettingsPage extends StatefulWidget {
  /// 创建页面。
  const AppSettingsPage({
    super.key,
    required this.library,
    this.onlineBooks,
    this.onReadOnline,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.appFontFamily = AppFonts.defaultFamily,
    this.appFontStore,
    this.onAppFontFamilyChanged,
    this.navigationSettings,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 在线书源；测试或未接入时不显示入口。
  final OnlineBookController? onlineBooks;
  final OnlineBookReadCallback? onReadOnline;

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
  final NavigationSettings? navigationSettings;

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  bool _exporting = false;
  bool _savingTheme = false;
  late ThemeMode _themeMode;
  late String _appFontFamily;
  BookSortOrder _shelfSort = BookSortOrder.recent;
  bool _showShelfTitles = true;
  bool _inkMode = false;
  List<ReaderFontEntry> _appFonts = const [];

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
    _appFontFamily = widget.appFontFamily;
    _loadShelfPreferences();
    _loadAppFonts();
  }

  @override
  void didUpdateWidget(covariant AppSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeMode != widget.themeMode) {
      _themeMode = widget.themeMode;
    }
    if (oldWidget.appFontFamily != widget.appFontFamily) {
      _appFontFamily = widget.appFontFamily;
    }
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
    final value = await widget.library.getSetting(bookshelfSortKey);
    final showTitles = await widget.library.getSetting(bookshelfShowTitlesKey);
    final inkMode = await widget.library.getSetting(
      ReaderSettingsStore.keyInkMode,
    );
    if (mounted) {
      setState(() {
        _shelfSort = BookSortOrder.fromValue(value);
        _showShelfTitles = showTitles != 'false';
        _inkMode = inkMode == 'true';
      });
    }
  }

  Future<void> _toggleShelfTitles(bool value) async {
    setState(() => _showShelfTitles = value);
    await widget.library.setSetting(bookshelfShowTitlesKey, value.toString());
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
      if (mounted) setState(() => _themeMode = selected);
    } catch (error, stackTrace) {
      recordAppError('theme_save_failed', error, stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _savingTheme = false);
    }
  }

  String get _appFontLabel {
    if (_appFontFamily == AppFonts.defaultFamily) return '思源宋体';
    return _appFonts
            .where((font) => font.family == _appFontFamily)
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
        selectedFamily: _appFontFamily,
        onSelect: _setAppFont,
        onImport: _importAppFont,
        onRemove: _removeAppFont,
      ),
    );
  }

  Future<void> _setAppFont(String family) async {
    await widget.onAppFontFamilyChanged!(family);
    if (mounted) setState(() => _appFontFamily = family);
  }

  Future<ReaderFontEntry?> _importAppFont() async {
    final font = await widget.appFontStore!.pick();
    if (font != null) await _loadAppFonts();
    return font;
  }

  Future<void> _removeAppFont(String family) async {
    await widget.appFontStore!.remove(family);
    if (_appFontFamily == family) {
      await _setAppFont(AppFonts.defaultFamily);
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
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _appearance(context),
              const SizedBox(height: 24),
              _section(context, '阅读', [
                ListTile(
                  key: const ValueKey('dictionary-settings-entry'),
                  leading: const AppIcon(AppGlyph.bookshelf),
                  title: const Text('词典设置'),
                  subtitle: const Text('释义服务、模型与查询预设'),
                  trailing: const AppIcon(AppGlyph.chevronRight),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => DictionarySettingsPage(
                        store: DictionaryStore(widget.library),
                      ),
                    ),
                  ),
                ),
                ListTile(
                  key: const ValueKey<String>('bookshelf-sort-setting'),
                  leading: const AppIcon(AppGlyph.sort),
                  title: const Text('书架排序'),
                  subtitle: Text(_shelfSort.label),
                  trailing: const AppIcon(AppGlyph.chevronRight),
                  onTap: _chooseShelfSort,
                ),
                ReaderSwitchListTile(
                  key: const ValueKey<String>('bookshelf-title-setting'),
                  secondary: const AppIcon(AppGlyph.textFields),
                  title: const Text('显示书名'),
                  subtitle: const Text('关闭后书架只显示封面'),
                  value: _showShelfTitles,
                  onChanged: _toggleShelfTitles,
                ),
                if (widget.onlineBooks != null)
                  _OnlineSourceEntry(
                    controller: widget.onlineBooks!,
                    onRead: widget.onReadOnline,
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
              _section(context, '应用信息', [
                ListTile(
                  key: const ValueKey('about-entry'),
                  title: const Text('关于'),
                  trailing: const AppIcon(AppGlyph.chevronRight),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const AboutPage()),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appearance(BuildContext context) {
    final mode = AppThemeScope.maybeOf(context)?.mode ?? _themeMode;
    return _section(context, '外观', [
      ReaderSwitchListTile(
        key: const ValueKey('appearance-ink-mode'),
        secondary: const AppIcon(AppGlyph.lightMode),
        title: const Text('墨水屏模式'),
        value: _inkMode,
        onChanged: (value) async {
          await widget.library.setSetting(
            ReaderSettingsStore.keyInkMode,
            '$value',
          );
          if (mounted) setState(() => _inkMode = value);
        },
      ),
      ListTile(
        key: const ValueKey('theme-color-settings-entry'),
        leading: const AppIcon(AppGlyph.palette),
        title: const Text('主题取色'),
        trailing: const AppIcon(AppGlyph.chevronRight),
        onTap: () async {
          final shared = ThemeColorScope.maybeOf(context);
          final settings = shared ?? ThemeColorSettings(widget.library);
          if (shared == null) await settings.initialize();
          if (!context.mounted) {
            if (shared == null) settings.dispose();
            return;
          }
          try {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ThemeColorSettingsPage(settings: settings),
              ),
            );
          } finally {
            if (shared == null) settings.dispose();
          }
        },
      ),
      if (widget.onThemeModeChanged != null)
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
      if (widget.navigationSettings != null)
        ListTile(
          key: const ValueKey('navigation-settings-entry'),
          leading: const AppIcon(AppGlyph.menuBook),
          title: const Text('底栏设置'),
          trailing: const AppIcon(AppGlyph.chevronRight),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) =>
                  NavigationSettingsPage(settings: widget.navigationSettings!),
            ),
          ),
        ),
    ]);
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
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

class _OnlineSourceEntry extends StatelessWidget {
  const _OnlineSourceEntry({required this.controller, this.onRead});

  final OnlineBookController controller;
  final OnlineBookReadCallback? onRead;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final subtitle = controller.error != null
            ? controller.error!
            : controller.enabledCount == 0
            ? '导入 Legado/阅读 JSON 书源，搜索并下载书籍'
            : '已启用 ${controller.enabledCount} / ${controller.sources.length} 个书源';
        return ListTile(
          key: const ValueKey<String>('online-source-entry'),
          leading: const AppIcon(AppGlyph.link),
          title: const Text('在线书源'),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const AppIcon(AppGlyph.chevronRight),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (context) =>
                  OnlineSourcePage(controller: controller, onRead: onRead),
            ),
          ),
        );
      },
    );
  }
}
