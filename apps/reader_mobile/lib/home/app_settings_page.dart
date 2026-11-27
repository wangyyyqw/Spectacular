import 'dart:async';

import 'package:flutter/material.dart';

import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';

import '../book_source/online_book_controller.dart';
import '../dictionary/dictionary_store.dart';
import '../dictionary/dictionary_settings_page.dart';
import '../book_source/online_book_detail_page.dart';
import '../book_source/online_source_page.dart';
import '../diagnostics/reader_log.dart';
import '../diagnostics/reader_log_page.dart';
import '../library/library_store.dart';
import '../reader/reader_font_store.dart';
import 'about_page.dart';
import '../theme/app_theme.dart';
import '../theme/theme_color_settings.dart';
import 'app_font_settings_page.dart';
import 'bookshelf_settings_page.dart';
import 'navigation_settings.dart';
import 'navigation_settings_page.dart';
import 'settings_choice_tile.dart';
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

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  late ThemeMode _themeMode;
  late AppUiStyle _uiStyle;
  late String _appFontFamily;
  List<ReaderFontEntry> _appFonts = const [];

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
    _uiStyle = widget.uiStyle;
    _appFontFamily = widget.appFontFamily;
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AppFontSettingsPage(
          fonts: _appFonts,
          selectedFamily: _appFontFamily,
          loadFont: store.load,
          onSelect: _setAppFont,
          onImport: _importAppFont,
          onRemove: _removeAppFont,
        ),
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

  @override
  Widget build(BuildContext context) {
    return ReaderSettingsScaffold(
      title: const Text('设置'),
      children: [
        _appearance(context),
        const SizedBox(height: ReaderUiTokens.spacingXl),
        ReaderSectionGroup(
          title: '阅读',
          children: [
            ListTile(
              key: const ValueKey('dictionary-settings-entry'),
              leading: const AppIcon(AppGlyph.bookshelf),
              title: const Text('词典设置'),
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
              title: const Text('查看日志'),
              trailing: const AppIcon(AppGlyph.chevronRight),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const ReaderLogPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: ReaderUiTokens.spacingXl),
        ReaderSectionGroup(
          title: '应用信息',
          children: [
            ListTile(
              key: const ValueKey('about-entry'),
              leading: const AppIcon(AppGlyph.info),
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
    return ReaderSectionGroup(
      title: '外观',
      children: [
        ListTile(
          key: const ValueKey('bookshelf-management-entry'),
          leading: const AppIcon(AppGlyph.bookshelf),
          title: const Text('书架管理'),
          trailing: const AppIcon(AppGlyph.chevronRight),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => BookshelfSettingsPage(library: widget.library),
            ),
          ),
        ),
        ListTile(
          key: const ValueKey('theme-color-settings-entry'),
          leading: const AppIcon(AppGlyph.palette),
          title: const Text('主题外观'),
          trailing: const AppIcon(AppGlyph.chevronRight),
          onTap: () async {
            final shared = ThemeColorScope.maybeOf(context);
            final settings = shared ?? ThemeColorSettings(widget.library);
            if (shared == null) {
              unawaited(settings.initialize().catchError((Object error, StackTrace stackTrace) {
                recordAppError('theme_color_init_failed', error, stackTrace: stackTrace);
              }));
            }
            try {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ThemeColorSettingsPage(
                    settings: settings,
                    themeMode: _themeMode,
                    uiStyle: _uiStyle,
                    onModeChanged: widget.onThemeModeChanged == null
                        ? null
                        : (mode) async {
                            await widget.onThemeModeChanged!(mode);
                            _themeMode = mode;
                          },
                    onStyleChanged: widget.onUiStyleChanged == null
                        ? null
                        : (style) async {
                            await widget.onUiStyleChanged!(style);
                            _uiStyle = style;
                          },
                  ),
                ),
              );
            } finally {
              if (shared == null) settings.dispose();
            }
          },
        ),
        if (widget.appFontStore != null &&
            widget.onAppFontFamilyChanged != null)
          ListTile(
            key: const ValueKey('app-font-setting'),
            leading: const AppIcon(AppGlyph.textFields),
            title: const Text('应用字体'),
            trailing: SettingsTrailingValue(_appFontLabel),
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
                builder: (_) => NavigationSettingsPage(
                  settings: widget.navigationSettings!,
                ),
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
    return ListTile(
      key: const ValueKey<String>('online-source-entry'),
      leading: const AppIcon(AppGlyph.link),
      title: const Text('在线书源'),
      trailing: const AppIcon(AppGlyph.chevronRight),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) =>
              OnlineSourcePage(controller: controller, onRead: onRead),
        ),
      ),
    );
  }
}
