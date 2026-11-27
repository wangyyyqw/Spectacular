import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';

import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';
import 'bookshelf_sort.dart';

enum _ShelfOption {
  gridTitles(bookshelfGridShowTitlesKey, 'grid-title', '宫格书架显示书名', true),
  dividers(bookshelfListDividersKey, 'list-divider', '列表书架显示分割线', true),
  newestFirst(bookshelfNewestFirstKey, 'newest-first', '新导入图书放到最上面', false),
  updateFirst(
    bookshelfAutoUpdateFirstKey,
    'auto-update-first',
    '在线图书更新后自动上浮',
    false,
  ),
  checkUpdates(
    bookshelfAutoCheckUpdatesKey,
    'auto-check-updates',
    '在线图书自动检查更新',
    false,
  ),
  skipFinished(
    bookshelfSkipFinishedUpdatesKey,
    'skip-finished-updates',
    '完结或读完图书跳过检查更新',
    true,
  ),
  allAsGroup(bookshelfAllAsGroupKey, 'all-as-group', '全部书架视为分组', false);

  const _ShelfOption(this.storageKey, this.id, this.title, this.defaultValue);

  final String storageKey;
  final String id;
  final String title;
  final bool defaultValue;
}

class BookshelfSettingsPage extends StatefulWidget {
  const BookshelfSettingsPage({super.key, required this.library});
  final LibraryStore library;

  @override
  State<BookshelfSettingsPage> createState() => _BookshelfSettingsPageState();
}

class _BookshelfSettingsPageState extends State<BookshelfSettingsPage> {
  Map<_ShelfOption, bool> _values = {};
  final _saving = <_ShelfOption>{};
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = <_ShelfOption, bool>{};
      for (final option in _ShelfOption.values) {
        var stored = await widget.library.getSetting(option.storageKey);
        if (stored == null && option == _ShelfOption.gridTitles) {
          stored = await widget.library.getSetting(bookshelfShowTitlesKey);
        }
        values[option] = option.defaultValue
            ? stored != 'false'
            : stored == 'true';
      }
      if (mounted) setState(() => _values = values);
    } catch (error, stackTrace) {
      recordAppError(
        'bookshelf_settings_load_failed',
        error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _set(_ShelfOption option, bool value) async {
    final oldValue = _values[option]!;
    setState(() {
      _saving.add(option);
      _values[option] = value;
    });
    try {
      await widget.library.setSetting(option.storageKey, value.toString());
    } catch (error, stackTrace) {
      recordAppError(
        'bookshelf_setting_save_failed',
        error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _values[option] = oldValue);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    } finally {
      if (mounted) setState(() => _saving.remove(option));
    }
  }

  @override
  Widget build(BuildContext context) => ReaderSettingsScaffold(
    title: const Text('书架管理'),
    children: [
      if (_values.isNotEmpty)
        ReaderSectionGroup(
          title: '书架选项',
          children: [
            for (final option in _ShelfOption.values)
              ReaderSwitchListTile(
                key: ValueKey('bookshelf-${option.id}-setting'),
                title: Text(option.title),
                value: _values[option]!,
                onChanged: _saving.contains(option)
                    ? null
                    : (value) => _set(option, value),
              ),
          ],
        )
      else if (_loadFailed)
        ReaderInlineNotice(
          message: '书架设置读取失败',
          isError: true,
          trailing: TextButton(
            onPressed: () {
              setState(() => _loadFailed = false);
              _load();
            },
            child: const Text('重试'),
          ),
        )
      else
        const Center(child: CircularProgressIndicator()),
    ],
  );
}
