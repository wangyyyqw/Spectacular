import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

import '../book_source/online_book_controller.dart';
import '../book_source/online_book_detail_page.dart';
import '../library/library_store.dart';
import '../rea_micro/rea_micro_controller.dart';
import '../rea_micro/rea_micro_lan_page.dart';
import '../rea_micro/rea_micro_page.dart';
import '../rea_micro/rea_micro_s3_page.dart';
import '../ye_she/community_page.dart';
import '../ye_she/ye_she_page.dart';
import '../reader/reader_font_store.dart';
import '../theme/app_theme.dart';
import 'reading_insights.dart';
import 'app_settings_page.dart';
import 'navigation_settings.dart';
import 'reading_heatmap.dart';

/// 我的页展示阅微账号、社区与设置入口。
class ProfilePage extends StatelessWidget {
  /// 创建页面。
  const ProfilePage({
    super.key,
    required this.library,
    this.reaMicro,
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

  /// 阅微登录与同步状态；测试或未接入时不显示入口。
  final ReaMicroController? reaMicro;

  /// 在线书源；测试或未接入时不显示入口。
  final OnlineBookController? onlineBooks;
  final OnlineBookReadCallback? onReadOnline;

  /// 已保存的界面主题选择。
  final ThemeMode themeMode;

  /// 切换并保存应用界面主题。
  final Future<void> Function(ThemeMode)? onThemeModeChanged;

  /// 当前应用控件风格。
  final AppUiStyle uiStyle;

  /// 保存并应用应用控件风格。
  final Future<void> Function(AppUiStyle)? onUiStyleChanged;

  /// 当前应用字体。
  final String appFontFamily;

  /// 应用字体存储；为空时不显示应用字体入口。
  final ReaderFontStore? appFontStore;

  /// 切换并保存应用字体。
  final Future<void> Function(String family)? onAppFontFamilyChanged;
  final NavigationSettings? navigationSettings;

  Future<void> _openAccount(BuildContext context) async {
    final controller = reaMicro;
    if (controller == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ReaMicroPage(controller: controller)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            InkWell(
              key: const ValueKey('profile-account-entry'),
              borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
              onTap: reaMicro == null ? null : () => _openAccount(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _identity(context),
              ),
            ),
            if (reaMicro != null) ReadingHeatmap(controller: reaMicro!),
            const SizedBox(height: 24),
            ReaderSectionGroup(
              children: [
                if (reaMicro != null) ...[
                  _YeSheEntry(controller: reaMicro!),
                  _CommunityEntry(controller: reaMicro!),
                  ListTile(
                    key: const ValueKey('profile-lan-entry'),
                    leading: const Icon(Icons.sync_alt),
                    title: const Text('互联'),
                    trailing: const AppIcon(AppGlyph.chevronRight),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => ReaMicroLanPage(controller: reaMicro!),
                      ),
                    ),
                  ),
                  ListTile(
                    key: const ValueKey('profile-sync-entry'),
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: const Text('同步'),
                    trailing: const AppIcon(AppGlyph.chevronRight),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => ReaMicroS3Page(controller: reaMicro!),
                      ),
                    ),
                  ),
                ],
                ListTile(
                  key: const ValueKey('profile-settings-entry'),
                  leading: const AppIcon(AppGlyph.settings),
                  title: const Text('设置'),
                  trailing: const AppIcon(AppGlyph.chevronRight),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => AppSettingsPage(
                        library: library,
                        onlineBooks: onlineBooks,
                        onReadOnline: onReadOnline,
                        themeMode: themeMode,
                        onThemeModeChanged: onThemeModeChanged,
                        uiStyle: uiStyle,
                        onUiStyleChanged: onUiStyleChanged,
                        appFontFamily: appFontFamily,
                        appFontStore: appFontStore,
                        onAppFontFamilyChanged: onAppFontFamilyChanged,
                        navigationSettings: navigationSettings,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  Widget _identity(BuildContext context) {
    final controller = reaMicro;
    if (controller != null) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _accountIdentity(context, controller),
      );
    }
    return _accountIdentity(context, null);
  }

  Widget _accountIdentity(
    BuildContext context,
    ReaMicroController? controller,
  ) {
    final user = controller?.signedIn == true ? controller?.user : null;
    final scheme = Theme.of(context).colorScheme;
    final avatar = user?.avatar.trim() ?? '';
    final totalSeconds =
        controller?.cloudStats?.overview.totalDurationSeconds ??
        user?.totalReadTimeSeconds ??
        0;
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: const Center(child: AppIcon(AppGlyph.profile)),
    );
    return Row(
      children: [
        ClipOval(
          child: SizedBox.square(
            dimension: 60,
            child: user == null
                ? Image.asset('assets/branding/app_icon.png', fit: BoxFit.cover)
                : avatar.isEmpty
                ? fallback
                : Image.network(
                    avatar,
                    fit: BoxFit.cover,
                    cacheWidth: (60 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    errorBuilder: (_, _, _) => fallback,
                  ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.nickName ?? '登录阅微',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                user == null
                    ? '登录后查看阅读时长与阅微 ID'
                    : '累计阅读 ${formatReadingDuration(Duration(seconds: totalSeconds))}'
                          '\n阅微 ID：${user.id}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _YeSheEntry extends StatelessWidget {
  const _YeSheEntry({required this.controller});

  final ReaMicroController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) => ListTile(
        key: const ValueKey<String>('ye-she-entry'),
        leading: const AppIcon(AppGlyph.autoStories),
        title: const Text('野社'),
        trailing: const AppIcon(AppGlyph.chevronRight),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (context) => YeShePage(
              account: controller,
              tokenProvider: () => controller.token,
              currentUserName: controller.user?.nickName ?? '',
              currentUserId: controller.user?.id ?? 0,
              currentUserAvatar: controller.user?.avatar ?? '',
              currentUserTitle: controller.user?.userTitle ?? '',
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityEntry extends StatelessWidget {
  const _CommunityEntry({required this.controller});

  final ReaMicroController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) => ListTile(
        key: const ValueKey<String>('community-entry'),
        leading: const AppIcon(AppGlyph.highlighter),
        title: const Text('社区'),
        trailing: const AppIcon(AppGlyph.chevronRight),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (context) => CommunityPage(
              account: controller,
              tokenProvider: () => controller.token,
              currentUserName: controller.user?.nickName ?? '',
              currentUserAvatar: controller.user?.avatar ?? '',
            ),
          ),
        ),
      ),
    );
  }
}
