import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import '../book_source/online_book_controller.dart';
import '../book_source/online_book_detail_page.dart';
import '../book_source/online_source_page.dart';
import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';
import '../rea_micro/rea_micro_controller.dart';
import '../rea_micro/rea_micro_page.dart';
import '../ye_she/ye_she_page.dart';
import 'bookshelf_sort.dart';

/// 我的页：外观、书架设置、版本信息、诊断日志导出。
class ProfilePage extends StatefulWidget {
  /// 创建页面。
  const ProfilePage({
    super.key,
    required this.library,
    this.reaMicro,
    this.onlineBooks,
    this.onReadOnline,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
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

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  PackageInfo? _packageInfo;
  bool _exporting = false;
  bool _savingTheme = false;
  BookSortOrder _shelfSort = BookSortOrder.recent;

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
    _loadShelfSort();
  }

  Future<void> _loadShelfSort() async {
    final value = await widget.library.getSetting(bookshelfSortKey);
    if (mounted) {
      setState(() => _shelfSort = BookSortOrder.fromValue(value));
    }
  }

  Future<void> _chooseShelfSort() async {
    final selected = await showDialog<BookSortOrder>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
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
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: const Text('界面主题'),
        content: RadioGroup<ThemeMode>(
          groupValue: current,
          onChanged: (mode) => Navigator.of(context).pop(mode),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile(value: ThemeMode.system, title: Text('跟随系统')),
              RadioListTile(value: ThemeMode.light, title: Text('日间模式')),
              RadioListTile(value: ThemeMode.dark, title: Text('夜间模式')),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null || selected == current) return;
    setState(() => _savingTheme = true);
    try {
      await widget.onThemeModeChanged!(selected);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('界面主题保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _savingTheme = false);
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
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
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('日志已清理')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('清理失败：$error')));
      }
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
      final path = await log.exportFile();
      await log.share();
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('日志已导出：${path ?? '分享面板已打开'}')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('日志导出失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          _identity(context),
          const SizedBox(height: 28),
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
            if (widget.onlineBooks != null)
              _OnlineSourceEntry(
                controller: widget.onlineBooks!,
                onRead: widget.onReadOnline,
              ),
          ]),
          if (widget.reaMicro != null) ...[
            const SizedBox(height: 24),
            _section(context, '账号与同步', [
              _ReaMicroEntry(controller: widget.reaMicro!),
              _YeSheEntry(controller: widget.reaMicro!),
            ]),
          ],
          const SizedBox(height: 24),
          _section(context, '帮助与诊断', [
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
    ]);
  }

  Widget _identity(BuildContext context) {
    final info = _packageInfo;
    return Row(
      children: [
        const AppIcon(AppGlyph.menuBook, size: 36),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spectacular Reader',
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
        Card(
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
        subtitle: Text(controller.signedIn ? '文房、游艺与见闻' : '登录阅微后进入文房、游艺与见闻'),
        trailing: const AppIcon(AppGlyph.chevronRight),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (context) =>
                YeShePage(tokenProvider: () => controller.token),
          ),
        ),
      ),
    );
  }
}

class _ReaMicroEntry extends StatelessWidget {
  const _ReaMicroEntry({required this.controller});

  final ReaMicroController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final user = controller.user;
        final subtitle = !controller.signedIn
            ? '登录阅微账号，查看并同步阅读时长'
            : user == null
            ? '已登录，正在读取账号信息'
            : '${user.nickName} · '
                  '${controller.links.isEmpty ? '尚未关联书籍' : '已关联 ${controller.links.length} 本'}';
        return ListTile(
          key: const ValueKey<String>('reamicro-entry'),
          leading: const AppIcon(AppGlyph.autoStories),
          title: const Text('阅微同步'),
          subtitle: Text(
            controller.error ?? subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const AppIcon(AppGlyph.chevronRight),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (context) => ReaMicroPage(controller: controller),
            ),
          ),
        );
      },
    );
  }
}
