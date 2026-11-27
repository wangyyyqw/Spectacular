import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_common_widgets.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_ink.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../diagnostics/reader_log.dart';
import '../dictionary/dictionary_store.dart';
import '../dictionary/dictionary_settings_page.dart';
import '../library/library_store.dart';
import '../reader/reader_font_store.dart';
import '../theme/app_theme.dart';
import 'app_font_picker.dart';
import 'bookshelf_sort.dart';
import 'theme_preset_picker.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_page.dart';

/// 我的页：外观、书架设置、版本信息、诊断日志导出。
class ProfilePage extends StatefulWidget {
  /// 创建页面。
  const ProfilePage({
    super.key,
    required this.library,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.themePreset = AppThemePreset.clearBlue,
    this.onThemePresetChanged,
    this.appFontFamily = AppFonts.defaultFamily,
    this.appFontStore,
    this.onAppFontFamilyChanged,
    this.sync,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 已保存的界面主题选择。
  final ThemeMode themeMode;

  /// 切换并保存应用界面主题。
  final Future<void> Function(ThemeMode)? onThemeModeChanged;

  /// 已保存的软件配色方案。
  final AppThemePreset themePreset;

  /// 切换并保存软件配色方案。
  final Future<void> Function(AppThemePreset)? onThemePresetChanged;

  /// 当前应用字体。
  final String appFontFamily;

  /// 应用字体存储；为空时不显示应用字体入口。
  final ReaderFontStore? appFontStore;
  final SyncController? sync;

  /// 切换并保存应用字体。
  final Future<void> Function(String family)? onAppFontFamilyChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  PackageInfo? _packageInfo;
  bool _exporting = false;
  bool _savingTheme = false;
  bool _savingPreset = false;
  BookSortOrder _shelfSort = BookSortOrder.recent;
  bool _newBooksFirst = true;
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
    final newBooksFirst = await widget.library.getSetting(
      bookshelfNewBooksFirstKey,
    );
    final showTitles = await widget.library.getSetting(bookshelfShowTitlesKey);
    if (mounted) {
      setState(() {
        _shelfSort = BookSortOrder.fromValue(sort);
        _newBooksFirst = newBooksFirst != 'false';
        _showShelfTitles = showTitles != 'false';
      });
    }
  }

  Future<void> _chooseShelfSort() async {
    final selected = await showReaderDrawer<BookSortOrder>(
      context: context,
      builder: (context) => ReaderSheetForm(
        title: const Text('书架排序'),
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final order in BookSortOrder.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: ReaderOptionTile(
                  tileKey: ValueKey<String>('bookshelf-sort-${order.value}'),
                  title: order.label,
                  selected: order == _shelfSort,
                  onTap: () => Navigator.of(context).pop(order),
                ),
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

  Future<void> _toggleNewBooksFirst(bool value) async {
    setState(() => _newBooksFirst = value);
    await widget.library.setSetting(bookshelfNewBooksFirstKey, '$value');
  }

  Future<void> _chooseTheme(ThemeMode current) async {
    final selected = await showReaderDrawer<ThemeMode>(
      context: context,
      builder: (context) => ReaderSheetForm(
        title: const Text('界面主题'),
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: ReaderOptionTile(
                  title: switch (mode) {
                    ThemeMode.system => '跟随系统',
                    ThemeMode.light => '日间模式',
                    ThemeMode.dark => '夜间模式',
                  },
                  subtitle: switch (mode) {
                    ThemeMode.system => '随系统明暗外观自动切换',
                    ThemeMode.light => '始终使用浅色界面',
                    ThemeMode.dark => '始终使用深色界面',
                  },
                  selected: mode == current,
                  onTap: () => Navigator.of(context).pop(mode),
                ),
              ),
          ],
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

  Future<void> _chooseThemePreset(AppThemePreset current) async {
    final selected = await showReaderDrawer<AppThemePreset>(
      context: context,
      builder: (context) => ThemePresetPickerSheet(
        selected: current,
        onSelect: (preset) => Navigator.of(context).pop(preset),
      ),
    );
    if (!mounted || selected == null || selected.id == current.id) return;
    setState(() => _savingPreset = true);
    try {
      await widget.onThemePresetChanged!(selected);
    } catch (error, stackTrace) {
      recordAppError('theme_preset_save_failed', error, stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _savingPreset = false);
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
    final confirmed = await showReaderConfirmDialog(
      context: context,
      title: '清理日志',
      message: '将删除本机保存的全部诊断日志（含历史会话），确定吗？',
      confirmLabel: '清理',
      confirmKey: const ValueKey<String>('logs-clear-confirm'),
      destructive: true,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: Theme(
        data: quietInk(theme),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _identity(context),
                const SizedBox(height: 20),
                if (widget.sync != null) ...[
                  _section(context, '数据', [
                    _settingTile(
                      context,
                      key: const ValueKey('multi-device-sync-entry'),
                      glyph: AppGlyph.cloudSync,
                      accentIcon: true,
                      title: '多设备同步',
                      subtitle: 'WebDAV / S3 · 完整阅读数据与可选加密',
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => SyncPage(controller: widget.sync!),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                ],
                if (widget.onThemeModeChanged != null ||
                    widget.onThemePresetChanged != null ||
                    (widget.appFontStore != null &&
                        widget.onAppFontFamilyChanged != null)) ...[
                  _appearance(context),
                  const SizedBox(height: 18),
                ],
                _section(context, '阅读', [
                  _settingTile(
                    context,
                    key: const ValueKey('dictionary-settings-entry'),
                    glyph: AppGlyph.bookshelf,
                    title: '词典设置',
                    subtitle: '释义服务、模型与查询预设',
                    onTap: () => showReaderBottomSheet<void>(
                      context: context,
                      useSafeArea: true,
                      isScrollControlled: true,
                      builder: (_) => DictionarySettingsPage(
                        store: DictionaryStore(widget.library),
                      ),
                    ),
                  ),
                  _settingTile(
                    context,
                    key: const ValueKey<String>('bookshelf-sort-setting'),
                    glyph: AppGlyph.sort,
                    title: '书架排序',
                    subtitle: _shelfSort.label,
                    onTap: _chooseShelfSort,
                  ),
                  SwitchListTile(
                    key: const ValueKey('bookshelf-new-books-first-setting'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    secondary: _iconBadge(context, AppGlyph.sort),
                    title: const Text('新书排在最前'),
                    subtitle: Text(
                      _shelfSort == BookSortOrder.title
                          ? '按书名排序时不调整新书位置'
                          : '关闭后新导入书籍排在最后，置顶书籍优先',
                    ),
                    value: _newBooksFirst,
                    onChanged: _shelfSort == BookSortOrder.title
                        ? null
                        : _toggleNewBooksFirst,
                  ),
                  SwitchListTile(
                    key: const ValueKey<String>('bookshelf-title-setting'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    secondary: _iconBadge(context, AppGlyph.textFields),
                    title: const Text('显示书名'),
                    subtitle: const Text('关闭后宫格书架只显示封面'),
                    value: _showShelfTitles,
                    onChanged: _toggleShelfTitles,
                  ),
                ]),
                const SizedBox(height: 18),
                _section(context, '帮助与诊断', [
                  _settingTile(
                    context,
                    glyph: AppGlyph.listBulleted,
                    title: '查看诊断日志',
                    subtitle: '查看应用错误和运行记录',
                    onTap: _viewLogs,
                  ),
                  _settingTile(
                    context,
                    glyph: AppGlyph.share,
                    loading: _exporting,
                    title: '导出诊断日志',
                    subtitle: '遇到阅读问题时，可随反馈附上',
                    onTap: _exporting ? null : _exportLogs,
                  ),
                  _settingTile(
                    context,
                    key: const ValueKey<String>('logs-clear'),
                    glyph: AppGlyph.deleteSweep,
                    destructive: true,
                    title: '清理日志',
                    subtitle: '删除本机保存的全部诊断日志',
                    onTap: _exporting ? null : _clearLogs,
                  ),
                ]),
                const SizedBox(height: 18),
                ReaderSectionCard(
                  title: '关于',
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _iconBadge(context, AppGlyph.info),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '本地 EPUB 阅读。书籍、阅读进度与笔记保存在设备上。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.55,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _appearance(BuildContext context) {
    final mode = widget.themeMode;
    final preset = widget.themePreset;
    final brightness = Theme.of(context).brightness;
    final preview = preset.previewFor(brightness);
    final scheme = Theme.of(context).colorScheme;
    return _section(context, '外观', [
      if (widget.onThemeModeChanged != null)
        _settingTile(
          context,
          glyph: AppGlyph.palette,
          title: '界面主题',
          subtitle: switch (mode) {
            ThemeMode.system => '跟随系统',
            ThemeMode.light => '日间模式',
            ThemeMode.dark => '夜间模式',
          },
          onTap: _savingTheme ? null : () => _chooseTheme(mode),
        ),
      if (widget.onThemePresetChanged != null)
        _settingTile(
          context,
          key: const ValueKey('theme-preset-setting'),
          glyph: AppGlyph.formatPaint,
          title: '配色方案',
          subtitle: preset.name,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _presetPreviewDots(
                canvas: preview.canvas,
                surface: preview.surface,
                accent: preview.accent,
                border: scheme.outlineVariant,
              ),
              const SizedBox(width: 8),
              AppIcon(AppGlyph.chevronRight, size: 18, color: scheme.outline),
            ],
          ),
          onTap: _savingPreset ? null : () => _chooseThemePreset(preset),
        ),
      if (widget.appFontStore != null && widget.onAppFontFamilyChanged != null)
        _settingTile(
          context,
          key: const ValueKey('app-font-setting'),
          glyph: AppGlyph.textFields,
          title: '应用字体',
          subtitle: _appFontLabel,
          onTap: _chooseAppFont,
        ),
    ]);
  }

  Widget _presetPreviewDots({
    required Color canvas,
    required Color surface,
    required Color accent,
    required Color border,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color: canvas,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: surface,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: .8),
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
      ],
    ),
  );

  Widget _settingTile(
    BuildContext context, {
    Key? key,
    required AppGlyph glyph,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    bool accentIcon = false,
    bool destructive = false,
    bool loading = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: key,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      minLeadingWidth: 36,
      horizontalTitleGap: 12,
      leading: loading
          ? Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _iconBadge(
              context,
              glyph,
              accent: accentIcon,
              destructive: destructive,
            ),
      title: Text(
        title,
        style: destructive
            ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.error,
              )
            : null,
      ),
      subtitle: Text(subtitle),
      trailing:
          trailing ??
          AppIcon(AppGlyph.chevronRight, size: 18, color: scheme.outline),
      onTap: onTap,
    );
  }

  Widget _iconBadge(
    BuildContext context,
    AppGlyph glyph, {
    bool accent = false,
    bool destructive = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final background = destructive
        ? scheme.errorContainer
        : accent
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    final iconColor = destructive
        ? scheme.error
        : accent
        ? scheme.primary
        : scheme.onSurfaceVariant;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: destructive
              ? scheme.error.withValues(alpha: .18)
              : accent
              ? scheme.primary.withValues(alpha: .16)
              : scheme.outlineVariant.withValues(alpha: .75),
        ),
      ),
      child: AppIcon(glyph, size: 18, color: iconColor),
    );
  }

  Widget _identity(BuildContext context) {
    final info = _packageInfo;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    return ReaderSectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: isLight
                  ? [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: .08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.asset(
                'assets/branding/app_icon.png',
                width: 52,
                height: 52,
                cacheWidth: (52 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                excludeFromSemantics: true,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '墨屿',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        widget.themePreset.name,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  info == null
                      ? '正在读取版本…'
                      : '版本 ${info.version} · ${info.buildNumber}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) =>
      ReaderSectionCard(
        title: title,
        dividerIndent: 62,
        dividerEndIndent: 14,
        children: rows,
      );
}
