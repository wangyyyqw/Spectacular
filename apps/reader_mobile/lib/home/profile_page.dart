import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';
import 'bookshelf_sort.dart';

/// 我的页：书架设置、应用/引擎信息、诊断日志导出。
class ProfilePage extends StatefulWidget {
  /// 创建页面。
  const ProfilePage({super.key, required this.library});

  /// 书架存储。
  final LibraryStore library;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  PackageInfo? _packageInfo;
  bool _exporting = false;
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
      builder: (context) => AlertDialog(
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

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
          _section(context, '阅读', [
            ListTile(
              key: const ValueKey<String>('bookshelf-sort-setting'),
              leading: const AppIcon(AppGlyph.sort),
              title: const Text('书架排序'),
              subtitle: Text(_shelfSort.label),
              trailing: const AppIcon(AppGlyph.chevronRight),
              onTap: _chooseShelfSort,
            ),
          ]),
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
