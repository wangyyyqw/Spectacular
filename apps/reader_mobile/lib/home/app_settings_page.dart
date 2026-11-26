import 'dart:async';

import 'package:flutter/material.dart';

import '../sync/sync_controller.dart';
import '../sync/sync_page.dart';

import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';

import '../book_source/online_book_controller.dart';
import '../dictionary/dictionary_store.dart';
import '../dictionary/dictionary_settings_page.dart';
import '../book_source/online_book_detail_page.dart';
import '../book_source/online_source_page.dart';
import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';
import '../reader/reader_font_store.dart';
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
    this.uiStyle = AppUiStyle.classic,
    this.onUiStyleChanged,
    this.appFontFamily = AppFonts.defaultFamily,
    this.appFontStore,
    this.onAppFontFamilyChanged,
    this.navigationSettings,
    this.sync,
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

  /// 当前应用控件风格。
  final AppUiStyle uiStyle;

  /// 切换并保存应用控件风格。
  final Future<void> Function(AppUiStyle)? onUiStyleChanged;

  /// 当前应用字体。
  final String appFontFamily;

  /// 应用字体存储；为空时不显示应用字体入口。
  final ReaderFontStore? appFontStore;

  /// 切换并保存应用字体。
  final Future<void> Function(String family)? onAppFontFamilyChanged;
  final NavigationSettings? navigationSettings;
  final SyncController? sync;

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  bool _exporting = false;
  bool _savingTheme = false;
  bool _savingUiStyle = false;
  late ThemeMode _themeMode;
  late AppUiStyle _uiStyle;
  late String _appFontFamily;
  bool _gridShowTitles = true;
  bool _listDividers = true;
  bool _newestFirst = false;
  bool _autoUpdateFirst = false;
  bool _autoCheckUpdates = false;
  bool _skipFinishedUpdates = true;
  bool _allAsGroup = false;
  List<ReaderFontEntry> _appFonts = const [];

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
    _uiStyle = widget.uiStyle;
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
    if (oldWidget.uiStyle != widget.uiStyle) {
      _uiStyle = widget.uiStyle;
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
    final oldShowTitles = await widget.library.getSetting(
      bookshelfShowTitlesKey,
    );
    final gridShowTitles = await widget.library.getSetting(
      bookshelfGridShowTitlesKey,
    );
    final listDividers = await widget.library.getSetting(
      bookshelfListDividersKey,
    );
    final newestFirst = await widget.library.getSetting(
      bookshelfNewestFirstKey,
    );
    final autoUpdateFirst = await widget.library.getSetting(
      bookshelfAutoUpdateFirstKey,
    );
    final autoCheckUpdates = await widget.library.getSetting(
      bookshelfAutoCheckUpdatesKey,
    );
    final skipFinishedUpdates = await widget.library.getSetting(
      bookshelfSkipFinishedUpdatesKey,
    );
    final allAsGroup = await widget.library.getSetting(bookshelfAllAsGroupKey);
    if (mounted) {
      setState(() {
        _gridShowTitles = gridShowTitles == null
            ? oldShowTitles != 'false'
            : gridShowTitles != 'false';
        _listDividers = listDividers != 'false';
        _newestFirst = newestFirst == 'true';
        _autoUpdateFirst = autoUpdateFirst == 'true';
        _autoCheckUpdates = autoCheckUpdates == 'true';
        _skipFinishedUpdates = skipFinishedUpdates != 'false';
        _allAsGroup = allAsGroup == 'true';
      });
    }
  }

  Future<bool> _toggleShelfSetting(String key, bool value) async {
    // 先更新抽屉内状态，让开关立即反馈；持久化失败时回滚并记录错误。
    setState(() {
      if (key == bookshelfGridShowTitlesKey) _gridShowTitles = value;
      if (key == bookshelfListDividersKey) _listDividers = value;
      if (key == bookshelfNewestFirstKey) _newestFirst = value;
      if (key == bookshelfAutoUpdateFirstKey) _autoUpdateFirst = value;
      if (key == bookshelfAutoCheckUpdatesKey) _autoCheckUpdates = value;
      if (key == bookshelfSkipFinishedUpdatesKey) _skipFinishedUpdates = value;
      if (key == bookshelfAllAsGroupKey) _allAsGroup = value;
    });
    try {
      await widget.library.setSetting(key, value.toString());
      return true;
    } catch (error, stackTrace) {
      recordAppError(
        'bookshelf_setting_save_failed',
        error,
        stackTrace: stackTrace,
      );
      if (!mounted) return false;
      setState(() {
        if (key == bookshelfGridShowTitlesKey) _gridShowTitles = !value;
        if (key == bookshelfListDividersKey) _listDividers = !value;
        if (key == bookshelfNewestFirstKey) _newestFirst = !value;
        if (key == bookshelfAutoUpdateFirstKey) _autoUpdateFirst = !value;
        if (key == bookshelfAutoCheckUpdatesKey) _autoCheckUpdates = !value;
        if (key == bookshelfSkipFinishedUpdatesKey) {
          _skipFinishedUpdates = !value;
        }
        if (key == bookshelfAllAsGroupKey) _allAsGroup = !value;
      });
      return false;
    }
  }

  Future<void> _openShelfManagement() {
    var gridShowTitles = _gridShowTitles;
    var listDividers = _listDividers;
    var newestFirst = _newestFirst;
    var autoUpdateFirst = _autoUpdateFirst;
    var autoCheckUpdates = _autoCheckUpdates;
    var skipFinishedUpdates = _skipFinishedUpdates;
    var allAsGroup = _allAsGroup;

    return showReaderDrawer<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDrawerState) {
          Future<void> change(String key, bool value) async {
            setDrawerState(() {
              if (key == bookshelfGridShowTitlesKey) gridShowTitles = value;
              if (key == bookshelfListDividersKey) listDividers = value;
              if (key == bookshelfNewestFirstKey) newestFirst = value;
              if (key == bookshelfAutoUpdateFirstKey) autoUpdateFirst = value;
              if (key == bookshelfAutoCheckUpdatesKey) {
                autoCheckUpdates = value;
              }
              if (key == bookshelfSkipFinishedUpdatesKey) {
                skipFinishedUpdates = value;
              }
              if (key == bookshelfAllAsGroupKey) allAsGroup = value;
            });
            final saved = key == bookshelfAllAsGroupKey
                ? await _setAllAsGroup(value)
                : await _toggleShelfSetting(key, value);
            if (!saved && context.mounted) {
              setDrawerState(() {
                if (key == bookshelfGridShowTitlesKey) {
                  gridShowTitles = !value;
                }
                if (key == bookshelfListDividersKey) listDividers = !value;
                if (key == bookshelfNewestFirstKey) newestFirst = !value;
                if (key == bookshelfAutoUpdateFirstKey) {
                  autoUpdateFirst = !value;
                }
                if (key == bookshelfAutoCheckUpdatesKey) {
                  autoCheckUpdates = !value;
                }
                if (key == bookshelfSkipFinishedUpdatesKey) {
                  skipFinishedUpdates = !value;
                }
                if (key == bookshelfAllAsGroupKey) allAsGroup = !value;
              });
            }
          }

          return ReaderSheetForm(
            title: const Text('书架管理'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReaderSwitchListTile(
                  key: const ValueKey('bookshelf-grid-title-setting'),
                  title: const Text('宫格书架显示书名'),
                  value: gridShowTitles,
                  onChanged: (value) =>
                      change(bookshelfGridShowTitlesKey, value),
                ),
                ReaderSwitchListTile(
                  key: const ValueKey('bookshelf-list-divider-setting'),
                  title: const Text('列表书架显示分割线'),
                  value: listDividers,
                  onChanged: (value) => change(bookshelfListDividersKey, value),
                ),
                ReaderSwitchListTile(
                  key: const ValueKey('bookshelf-newest-first-setting'),
                  title: const Text('新导入图书放到最上面'),
                  value: newestFirst,
                  onChanged: (value) => change(bookshelfNewestFirstKey, value),
                ),
                ReaderSwitchListTile(
                  key: const ValueKey('bookshelf-auto-update-first-setting'),
                  title: const Text('在线图书更新后自动上浮'),
                  value: autoUpdateFirst,
                  onChanged: (value) =>
                      change(bookshelfAutoUpdateFirstKey, value),
                ),
                ReaderSwitchListTile(
                  key: const ValueKey('bookshelf-auto-check-updates-setting'),
                  title: const Text('在线图书自动检查更新'),
                  value: autoCheckUpdates,
                  onChanged: (value) =>
                      change(bookshelfAutoCheckUpdatesKey, value),
                ),
                ReaderSwitchListTile(
                  key: const ValueKey(
                    'bookshelf-skip-finished-updates-setting',
                  ),
                  title: const Text('完结或读完图书跳过检查更新'),
                  value: skipFinishedUpdates,
                  onChanged: (value) =>
                      change(bookshelfSkipFinishedUpdatesKey, value),
                ),
                ReaderSwitchListTile(
                  key: const ValueKey('bookshelf-all-as-group-setting'),
                  title: const Text('全部书架视为分组'),
                  value: allAsGroup,
                  onChanged: (value) => change(bookshelfAllAsGroupKey, value),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<bool> _setAllAsGroup(bool value) async {
    try {
      if (value) {
        await widget.library.setSetting(bookshelfDefaultGroupNameKey, '默认');
      }
      return await _toggleShelfSetting(bookshelfAllAsGroupKey, value);
    } catch (error, stackTrace) {
      recordAppError(
        'bookshelf_group_setting_save_failed',
        error,
        stackTrace: stackTrace,
      );
      return false;
    }
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
                RadioListTile<ThemeMode>(
                  value: mode,
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

  Future<void> _chooseUiStyle(AppUiStyle current) async {
    final selected = await showReaderDrawer<AppUiStyle>(
      context: context,
      builder: (context) => ReaderSheetForm(
        title: const Text('界面样式'),
        content: RadioGroup<AppUiStyle>(
          groupValue: current,
          onChanged: (style) => Navigator.of(context).pop(style),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in AppUiStyle.values)
                RadioListTile<AppUiStyle>(
                  value: style,
                  contentPadding: EdgeInsets.zero,
                  title: Text(switch (style) {
                    AppUiStyle.classic => '经典',
                    AppUiStyle.material3 => 'Material 3',
                  }),
                  subtitle: Text(switch (style) {
                    AppUiStyle.classic => '克制精炼的工具风，平面细描边与小圆角',
                    AppUiStyle.material3 => 'Material 3 规范控件、大圆角与柔和色调容器',
                  }),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null || selected == current) return;
    final onChanged =
        AppThemeScope.maybeOf(context)?.onUiStyleChanged ??
        widget.onUiStyleChanged;
    if (onChanged == null) return;
    setState(() => _savingUiStyle = true);
    try {
      await onChanged(selected);
      if (mounted) setState(() => _uiStyle = selected);
    } catch (error, stackTrace) {
      recordAppError('ui_style_save_failed', error, stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _savingUiStyle = false);
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
    final confirmed = await showReaderConfirmDialog(
      context: context,
      title: '清理日志',
      message: '将删除本机保存的全部诊断日志（含历史会话），确定吗？',
      confirmLabel: '清理',
      destructive: true,
      confirmKey: const ValueKey<String>('logs-clear-confirm'),
    );
    if (!confirmed) {
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
    return ReaderSettingsScaffold(
      title: const Text('设置'),
      children: [
        if (widget.sync != null) ...[
          ReaderSectionGroup(
            title: '数据',
            children: [
              ListTile(
                key: const ValueKey('multi-device-sync-entry'),
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('多设备同步'),
                subtitle: const Text('WebDAV / S3 · 完整阅读数据与可选加密'),
                trailing: const AppIcon(AppGlyph.chevronRight),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => SyncPage(controller: widget.sync!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ReaderUiTokens.spacingXl),
        ],
        _appearance(context),
        const SizedBox(height: ReaderUiTokens.spacingXl),
        ReaderSectionGroup(
          title: '阅读',
          children: [
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
            if (widget.onlineBooks != null)
              _OnlineSourceEntry(
                controller: widget.onlineBooks!,
                onRead: widget.onReadOnline,
              ),
          ],
        ),
        const SizedBox(height: ReaderUiTokens.spacingXl),
        ReaderSectionGroup(
          title: '帮助与诊断',
          children: [
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
          ],
        ),
        const SizedBox(height: ReaderUiTokens.spacingXl),
        ReaderSectionGroup(
          title: '应用信息',
          children: [
            ListTile(
              key: const ValueKey('about-entry'),
              title: const Text('关于'),
              trailing: const AppIcon(AppGlyph.chevronRight),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _appearance(BuildContext context) {
    final mode = AppThemeScope.maybeOf(context)?.mode ?? _themeMode;
    final uiStyle = AppThemeScope.maybeOf(context)?.uiStyle ?? _uiStyle;
    return ReaderSectionGroup(
      title: '外观',
      children: [
        ListTile(
          key: const ValueKey('bookshelf-management-entry'),
          leading: const AppIcon(AppGlyph.bookshelf),
          title: const Text('书架管理'),
          subtitle: const Text('书架显示、排序、更新和分组'),
          trailing: const AppIcon(AppGlyph.chevronRight),
          onTap: _openShelfManagement,
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
        if ((AppThemeScope.maybeOf(context)?.onUiStyleChanged ??
                widget.onUiStyleChanged) !=
            null)
          ListTile(
            key: const ValueKey('app-ui-style-setting'),
            leading: const AppIcon(AppGlyph.palette),
            title: const Text('界面样式'),
            subtitle: Text(switch (uiStyle) {
              AppUiStyle.classic => '经典',
              AppUiStyle.material3 => 'Material 3',
            }),
            trailing: const AppIcon(AppGlyph.chevronRight),
            onTap: _savingUiStyle ? null : () => _chooseUiStyle(uiStyle),
          ),
        if (widget.appFontStore != null &&
            widget.onAppFontFamilyChanged != null)
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
            MaterialPageRoute(
              builder: (context) =>
                  OnlineSourcePage(controller: controller, onRead: onRead),
            ),
          ),
        );
      },
    );
  }
}
