import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_ui/reader_ui.dart';

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
                leading: Icon(
                  order == _shelfSort
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
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
    final info = _packageInfo;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    child: Icon(
                      Icons.menu_book,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Spectacular Reader',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        info == null
                            ? '正在读取版本…'
                            : '${info.version} (${info.buildNumber})',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              key: const ValueKey<String>('bookshelf-sort-setting'),
              leading: const Icon(Icons.sort),
              title: const Text('书架排序'),
              subtitle: Text(_shelfSort.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: _chooseShelfSort,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.memory),
                  title: const Text('排版引擎'),
                  subtitle: Text(
                    'reader_core（$readerCorePackageName）· reader_ui'
                    '（$readerUiPackageName）\n'
                    '自研排版引擎，正文渲染不使用 WebView',
                  ),
                ),
                ListTile(
                  leading: _exporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share),
                  title: const Text('导出诊断日志'),
                  subtitle: const Text('包含历史会话；排查真机问题时随反馈附上'),
                  onTap: _exporting ? null : _exportLogs,
                ),
                ListTile(
                  key: const ValueKey<String>('logs-clear'),
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('清理日志'),
                  subtitle: const Text('删除本机保存的全部诊断日志'),
                  onTap: _exporting ? null : _clearLogs,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('开放中的能力', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    '字体与图片（P3）、书库云同步、划线笔记（P4）、'
                    '竖排与注音（P5）、朗读（P6）将随里程碑开放。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
