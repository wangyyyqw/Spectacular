import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/reader_session.dart';

import 'package:reader_core/epub/importer.dart';
import 'package:reader_core/position/locator.dart';

import '../library/library_store.dart';
import '../reader/book_opener.dart';
import 'book_detail_page.dart';
import 'book_detail_sheet.dart';
import 'bookshelf_sort.dart';
import '../storage/import_queue.dart';

/// 书架条目与已保存的当前正文比例；旧记录才按字符权重估算。
typedef _ShelfItem = ({BookEntry entry, int? percentInt, bool finished});

const _shelfColumns = 3;
const _shelfGridPadding = 16.0;
const _shelfGridSpacing = 16.0;
const _shelfCoverAspectRatio = 3 / 4;
const _shelfTitleGap = 6.0;
const _shelfTitleHeight = 20.0;
const _shelfMetaHeight = 18.0;

/// 书架页：书籍网格/列表、EPUB 导入、点击进入阅读、长按看详情。
class BookshelfPage extends StatefulWidget {
  /// 创建页面。
  const BookshelfPage({
    super.key,
    required this.library,
    required this.progressStore,
    this.refreshToken = 0,
    this.pickEpubFiles = _pickWithFilePicker,
    this.readFile = _readFile,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 阅读进度存储（进阅读页用）。
  final ReaderProgressStore progressStore;

  /// 外部切换页面时递增，用于重新读取排序设置。
  final int refreshToken;

  /// 选文件入口（默认 file_picker 多选；测试注入）。
  final Future<List<String>> Function() pickEpubFiles;

  /// 读取文件字节（默认 dart:io；测试注入以便在 FakeAsync 中同步返回）。
  final Future<Uint8List> Function(String path) readFile;

  static Future<Uint8List> _readFile(String path) => File(path).readAsBytes();

  static Future<List<String>> _pickWithFilePicker() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['epub'],
    );
    return <String>[
      for (final file in files)
        if (file.path != null) file.path!,
    ];
  }

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  static const _viewKey = 'bookshelf.grid';

  List<_ShelfItem>? _items;

  late final BookOpener _bookOpener;
  late final ImportQueue _queue;
  final List<ImportJob> _batch = <ImportJob>[];
  int _reportedJobs = 0;
  String? _error;
  BookSortOrder _sort = BookSortOrder.recent;
  List<ShelfGroup> _groups = const <ShelfGroup>[];
  Map<String, String> _bookGroups = const <String, String>{};
  String? _activeGroupId;
  bool _grid = true;
  bool _searching = false;
  bool _selectionMode = false;
  bool _removing = false;
  String _query = '';
  final Set<String> _selectedIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  Future<void>? _reloadTask;
  bool _reloadRequested = false;

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_reload);
    _bookOpener = BookOpener(
      library: widget.library,
      progressStore: widget.progressStore,
    );
    _queue = ImportQueue(widget.library, readFile: widget.readFile)
      ..addListener(_onQueueChanged);
    _reload();
    _loadPreferences();
  }

  @override
  void didUpdateWidget(BookshelfPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadPreferences();
    }
  }

  /// 读持久化的排序与视图模式（settings 表）。
  Future<void> _loadPreferences() async {
    final sort = await widget.library.getSetting(bookshelfSortKey);
    final grid = await widget.library.getSetting(_viewKey);
    if (!mounted) {
      return;
    }
    setState(() {
      _sort = BookSortOrder.fromValue(sort);
      _grid = grid != 'false';
    });
  }

  Future<void> _toggleView() async {
    final grid = !_grid;
    setState(() => _grid = grid);
    await widget.library.setSetting(_viewKey, '$grid');
  }

  ShelfGroup? get _activeGroup {
    for (final group in _groups) {
      if (group.id == _activeGroupId) {
        return group;
      }
    }
    return null;
  }

  void _toggleGroup(String id) {
    setState(() {
      _activeGroupId = _activeGroupId == id ? null : id;
    });
  }

  int _groupBookCount(ShelfGroup group) => (_items ?? const <_ShelfItem>[])
      .where((item) => _bookGroups[item.entry.id] == group.id)
      .length;

  Future<void> _createGroup({
    Set<String> initialBookIds = const <String>{},
  }) async {
    final draft = await showDialog<({String name, Set<String> bookIds})>(
      context: context,
      builder: (_) => _NewGroupDialog(
        items: _items ?? const <_ShelfItem>[],
        groups: _groups,
        assignments: _bookGroups,
        initialBookIds: initialBookIds,
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      final group = await widget.library.createGroup(draft.name);
      if (draft.bookIds.isNotEmpty) {
        await widget.library.setBooksGroup(draft.bookIds, groupId: group.id);
      }
      await _reload();
      if (mounted) {
        setState(() {
          _activeGroupId = group.id;
          _query = '';
          _selectionMode = false;
          _selectedIds.clear();
        });
      }
    } on LibraryImportException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<String?> _promptGroupName({
    required String title,
    String initial = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _GroupNameDialog(title: title, initial: initial),
    );
  }

  Future<void> _manageGroup(ShelfGroup group) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(group.name),
              subtitle: Text('${_groupBookCount(group)} 本书'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名分组'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除分组',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: const Text('书籍会保留在书架中'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == 'rename') {
      final name = await _promptGroupName(title: '重命名分组', initial: group.name);
      if (name == null) {
        return;
      }
      try {
        await widget.library.renameGroup(group.id, name);
      } on LibraryImportException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('删除分组「${group.name}」？'),
          content: const Text('书籍会保留在书架中，只删除分组。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await widget.library.deleteGroup(group.id);
        if (mounted && _activeGroupId == group.id) {
          setState(() => _activeGroupId = null);
        }
      }
    }
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
    if (!_searching) {
      FocusScope.of(context).unfocus();
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _resetFilters() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = false;
      _query = '';
      _activeGroupId = null;
    });
  }

  void _startSelection(BookEntry entry) {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _selectionMode = true;
      _searching = false;
      _query = '';
      _activeGroupId = null;
      _selectedIds
        ..clear()
        ..add(entry.id);
    });
  }

  void _exitSelectionMode() {
    if (_removing) {
      return;
    }
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    if (_removing) {
      return;
    }
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  bool _allSelected(List<_ShelfItem>? items) {
    final entries = items ?? const <_ShelfItem>[];
    return entries.isNotEmpty &&
        entries.every((item) => _selectedIds.contains(item.entry.id));
  }

  void _toggleSelectAll(List<_ShelfItem>? items) {
    if (_removing) {
      return;
    }
    final entries = items ?? const <_ShelfItem>[];
    final allSelected = _allSelected(entries);
    setState(() {
      _selectedIds.clear();
      if (!allSelected) {
        _selectedIds.addAll(entries.map((item) => item.entry.id));
      }
    });
  }

  /// 按当前排序方式排序（list() 默认最近阅读优先）。
  List<_ShelfItem> _sorted(List<_ShelfItem> items) {
    final sorted = List<_ShelfItem>.of(items);
    switch (_sort) {
      case BookSortOrder.recent:
        break;
      case BookSortOrder.added:
        sorted.sort((a, b) => b.entry.addedAt.compareTo(a.entry.addedAt));
      case BookSortOrder.title:
        sorted.sort((a, b) => a.entry.title.compareTo(b.entry.title));
    }
    return sorted;
  }

  /// 先按关键词与当前分组过滤，再沿用书架排序。
  List<_ShelfItem> _visible(List<_ShelfItem> items) {
    final query = _query.trim().toLowerCase();
    final filtered = items.where((item) {
      final groupId = _activeGroupId;
      if (groupId != null && _bookGroups[item.entry.id] != groupId) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return item.entry.title.toLowerCase().contains(query) ||
          item.entry.author.toLowerCase().contains(query);
    });
    return _sorted(filtered.toList());
  }

  @override
  void dispose() {
    widget.library.removeListener(_reload);
    _searchController.dispose();
    _queue
      ..removeListener(_onQueueChanged)
      ..dispose();
    super.dispose();
  }

  /// 队列变化：刷新进度；一批任务全部结束时汇总提示。
  void _onQueueChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    if (!_queue.isIdle || _batch.length == _reportedJobs) {
      return;
    }
    _reportedJobs = _batch.length;
    _showImportSummary();
  }

  void _showImportSummary() {
    final succeeded = _batch
        .where((job) => job.status == ImportStatus.succeeded)
        .length;
    ImportJob? failed;
    for (final job in _batch) {
      if (job.status == ImportStatus.failed) {
        failed = job;
        break;
      }
    }
    final cancelled = _batch
        .where((job) => job.status == ImportStatus.cancelled)
        .length;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (succeeded > 0) {
      final outcomes = _batch
          .where((job) => job.status == ImportStatus.succeeded)
          .map((job) => job.entry!.importOutcome)
          .toList();
      final added = outcomes
          .where((value) => value == BookImportOutcome.added)
          .length;
      final updated = outcomes
          .where((value) => value == BookImportOutcome.updated)
          .length;
      final unchanged = outcomes
          .where((value) => value == BookImportOutcome.unchanged)
          .length;
      final message = succeeded == 1
          ? switch (outcomes.single) {
              BookImportOutcome.added => '已导入 1 本书',
              BookImportOutcome.updated => '书籍已更新',
              BookImportOutcome.unchanged => '书籍内容未变化',
            }
          : [
              if (added > 0) '新增 $added 本',
              if (updated > 0) '更新 $updated 本',
              if (unchanged > 0) '$unchanged 本内容未变化',
            ].join('，');
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
    if (failed != null) {
      _showImportFailure(failed, messenger);
    } else if (succeeded == 0 && cancelled > 0) {
      messenger?.showSnackBar(const SnackBar(content: Text('已取消导入')));
    }
  }

  void _showImportFailure(ImportJob failed, ScaffoldMessengerState? messenger) {
    final friendly = EpubRejectionMessages.forCode(
      failed.errorCode,
      failed.error ?? '',
    );
    final message = '${friendly.title}。${friendly.suggestion}';
    if (failed.errorCode == 'E_DUPLICATE' ||
        failed.updateBookId != null ||
        failed.errorCode == 'E_REVISION_CONFLICT' ||
        failed.errorCode == 'E_STALE_REVISION') {
      // 重复导入不影响现有书架，用户可以直接打开原书。
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    } else {
      setState(() => _error = message);
    }
  }

  Future<void> _reload() {
    _reloadRequested = true;
    return _reloadTask ??= _drainReloads();
  }

  Future<void> _drainReloads() async {
    try {
      while (mounted && _reloadRequested) {
        _reloadRequested = false;
        await _reloadOnce();
      }
    } finally {
      _reloadTask = null;
    }
  }

  Future<void> _reloadOnce() async {
    // 四份数据互不依赖；并发读取后仍只对本轮完整快照调用一次 setState。
    final (books, groups, bookGroups, progress) = await (
      widget.library.list(),
      widget.library.listGroups(),
      widget.library.groupAssignments(),
      widget.progressStore.snapshot(),
    ).wait;
    final weights = await widget.library.progressWeightsForBooks(<String>[
      for (final book in books)
        if (progress.containsKey(book.id)) book.id,
    ]);
    final items = <_ShelfItem>[];
    for (final book in books) {
      int? percent;
      final current = progress[book.id];
      if (current != null) {
        percent = current.readingPercent == null
            ? _fallbackPercent(weights[book.id], current)
            : (current.readingPercent! * 100).round().clamp(0, 100);
      }
      items.add((
        entry: book,
        percentInt: percent,
        finished: current?.finished ?? false,
      ));
    }
    if (mounted) {
      final validIds = <String>{for (final item in items) item.entry.id};
      setState(() {
        _items = items;
        _groups = groups;
        _bookGroups = bookGroups;
        if (_activeGroupId != null &&
            !groups.any((group) => group.id == _activeGroupId)) {
          _activeGroupId = null;
        }
        _selectedIds.removeWhere((id) => !validIds.contains(id));
        if (items.isEmpty) {
          _selectionMode = false;
        }
      });
    }
  }

  int? _fallbackPercent(ProgressWeights? weights, ReaderProgress progress) {
    if (weights == null || weights.total <= 0) return null;
    return weights.percentInt(progress.spineIndex);
  }

  /// 多选 EPUB 入队（P4-03）：后台串行导入，UI 不阻塞。
  Future<void> _import() async {
    // ignore: avoid_print
    print('[import] 开始选择文件');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在打开文件选择器…'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    List<String> paths;
    try {
      paths = await widget.pickEpubFiles();
    } catch (error) {
      // ignore: avoid_print
      print('[import] 选择文件失败：$error');
      if (mounted) {
        setState(() => _error = '选择文件失败：$error');
      }
      return;
    }
    // ignore: avoid_print
    print('[import] 选中 ${paths.length} 个文件');
    if (paths.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _error = null;
      _batch.clear();
      _reportedJobs = 0;
    });
    for (final path in paths) {
      try {
        _batch.add(
          _queue.enqueuePath(
            path,
            fallbackTitle: path.split(Platform.pathSeparator).last,
          ),
        );
      } catch (error) {
        if (mounted) {
          setState(() => _error = '读取文件失败：$error');
        }
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _open(BookEntry entry) => _bookOpener.open(context, entry);

  /// 长按卡片：快捷详情面板；可继续进入完整详情页或删除。
  Future<void> _openBookDetail(BookEntry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BookDetailSheet(entry: entry, library: widget.library),
    );
    if (!mounted) {
      return;
    }
    if (action == 'detail') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => BookDetailPage(
            entry: entry,
            library: widget.library,
            progressStore: widget.progressStore,
          ),
        ),
      );
      if (mounted) {
        await _reload();
      }
    } else if (action == 'delete') {
      await _confirmRemove(entry);
    } else if (action == 'update') {
      await _pickBookUpdate(entry);
    } else if (action == 'create-group') {
      await _createGroup(initialBookIds: <String>{entry.id});
    } else if (action == 'multi-select') {
      _startSelection(entry);
    }
  }

  Future<void> _pickBookUpdate(BookEntry entry) async {
    try {
      final paths = await widget.pickEpubFiles();
      if (!mounted || paths.isEmpty) return;
      if (paths.length != 1) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('更新时请选择一本 EPUB')));
        return;
      }
      setState(() {
        _batch.clear();
        _reportedJobs = 0;
        _error = null;
      });
      _batch.add(_queue.enqueuePath(paths.single, updateBookId: entry.id));
      setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法更新：$error')));
      }
    }
  }

  Future<void> _confirmRemove(BookEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除《${entry.title}》'),
        content: const Text('将删除书籍文件；阅读进度、书签、笔记和高亮会保留，重新导入同一本书后恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.library.remove(entry.id);
    }
  }

  List<BookEntry> _selectedEntries() => <BookEntry>[
    for (final item in _items ?? const <_ShelfItem>[])
      if (_selectedIds.contains(item.entry.id)) item.entry,
  ];

  Future<void> _confirmBatchRemove() async {
    final entries = _selectedEntries();
    if (entries.isEmpty || _removing) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除选中的 ${entries.length} 本书？'),
        content: const Text('将删除书籍文件；阅读进度、书签、笔记和高亮会保留，重新导入后恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _removeSelected(entries);
    }
  }

  Future<void> _moveSelectedToGroup() async {
    final entries = _selectedEntries();
    if (entries.isEmpty) {
      return;
    }
    final target = await showModalBottomSheet<({String? groupId})>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '将 ${entries.length} 本书移入分组',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            ListTile(
              key: const ValueKey<String>('bookshelf-group-pick-none'),
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('移出分组'),
              onTap: () => Navigator.of(context).pop((groupId: null)),
            ),
            for (final group in _groups)
              ListTile(
                key: ValueKey<String>('bookshelf-group-pick-${group.id}'),
                leading: const Icon(Icons.folder_outlined),
                title: Text(group.name),
                onTap: () => Navigator.of(context).pop((groupId: group.id)),
              ),
          ],
        ),
      ),
    );
    if (!mounted || target == null) {
      return;
    }
    final groupId = target.groupId;
    final ids = <String>[for (final entry in entries) entry.id];
    try {
      String message;
      if (groupId == null) {
        await widget.library.setBooksGroup(ids);
        message = '已移出分组';
      } else {
        final group = _groups.firstWhere((group) => group.id == groupId);
        await widget.library.setBooksGroup(ids, groupId: group.id);
        message = '已移入「${group.name}」';
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on LibraryImportException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _removeSelected(List<BookEntry> entries) async {
    setState(() => _removing = true);
    var removed = 0;
    final failedIds = <String>[];
    for (final entry in entries) {
      try {
        await widget.library.remove(entry.id);
        removed++;
      } catch (_) {
        failedIds.add(entry.id);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _removing = false;
      _selectedIds
        ..clear()
        ..addAll(failedIds);
      if (failedIds.isEmpty) {
        _selectionMode = false;
      }
    });
    final message = switch ((removed, failedIds.length)) {
      (0, _) => '删除失败，请稍后重试',
      (_, 0) => '已删除 $removed 本书',
      (final done, final failed) => '已删除 $done 本，$failed 本删除失败',
    };
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final busy = _queue.isBusy;
    final visible = items == null ? null : _visible(items);
    return Scaffold(
      appBar: _buildAppBar(items, busy),
      bottomNavigationBar: _selectionMode ? _buildSelectionBar() : null,
      body: _buildBody(items, visible, busy),
    );
  }

  PreferredSizeWidget _buildAppBar(List<_ShelfItem>? items, bool busy) {
    if (_selectionMode) {
      return AppBar(
        leading: IconButton(
          tooltip: '退出多选',
          onPressed: _removing ? null : _exitSelectionMode,
          icon: const Icon(Icons.close),
        ),
        title: Text(
          _selectedIds.isEmpty ? '多选' : '已选 ${_selectedIds.length} 本',
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('bookshelf-select-all'),
            onPressed: _removing ? null : () => _toggleSelectAll(items),
            child: Text(_allSelected(items) ? '取消全选' : '全选'),
          ),
        ],
      );
    }
    return AppBar(
      title: _searching
          ? TextField(
              key: const ValueKey<String>('bookshelf-search-field'),
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索书名或作者',
                border: InputBorder.none,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (value) => setState(() => _query = value),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    _activeGroup?.name ?? '书架',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (items != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '${_activeGroup == null ? items.length : _groupBookCount(_activeGroup!)} 本',
                    key: const ValueKey<String>('bookshelf-count'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
      actions: _searching
          ? <Widget>[
              IconButton(
                tooltip: '关闭搜索',
                onPressed: _toggleSearch,
                icon: const Icon(Icons.close),
              ),
            ]
          : <Widget>[
              if (_activeGroupId != null)
                PopupMenuButton<String>(
                  key: const ValueKey<String>('bookshelf-group-options'),
                  tooltip: '分组选项',
                  icon: const Icon(Icons.filter_alt_outlined),
                  onSelected: (action) {
                    if (action == 'exit') {
                      setState(() => _activeGroupId = null);
                      return;
                    }
                    final group = _activeGroup;
                    if (group != null) {
                      _manageGroup(group);
                    }
                  },
                  itemBuilder: (_) => const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(value: 'exit', child: Text('退出分组')),
                    PopupMenuItem<String>(
                      value: 'manage',
                      child: Text('管理当前分组'),
                    ),
                  ],
                ),
              IconButton(
                tooltip: '搜索书架',
                onPressed: _toggleSearch,
                icon: const Icon(Icons.search),
              ),
              IconButton(
                key: const ValueKey<String>('bookshelf-import'),
                tooltip: busy ? '导入中…' : '导入 EPUB',
                onPressed: busy ? null : _import,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_upload_outlined),
              ),
              IconButton(
                tooltip: _grid ? '列表视图' : '网格视图',
                onPressed: _toggleView,
                icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view),
              ),
            ],
    );
  }

  Widget _buildBody(
    List<_ShelfItem>? items,
    List<_ShelfItem>? visible,
    bool busy,
  ) {
    return Column(
      children: [
        if (busy)
          _ImportBanner(
            queue: _queue,
            onCancel: () {
              final job = _queue.activeJob;
              if (job != null) {
                _queue.cancel(job.id);
              }
            },
          ),
        if (!_selectionMode &&
            _error == null &&
            items != null &&
            items.isNotEmpty &&
            _groups.isNotEmpty)
          _ShelfGroupBar(
            items: items,
            groups: _groups,
            assignments: _bookGroups,
            activeGroupId: _activeGroupId,
            onToggle: _toggleGroup,
            onShowAll: () => setState(() => _activeGroupId = null),
            onManage: _manageGroup,
          ),
        Expanded(child: _buildLibraryBody(items, visible)),
      ],
    );
  }

  Widget _buildLibraryBody(List<_ShelfItem>? items, List<_ShelfItem>? visible) {
    if (_error != null) {
      return _ErrorPane(message: _error!, onRetry: _import);
    }
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return const _EmptyPane();
    }
    final books = visible!;
    if (books.isEmpty) {
      return _NoMatchesPane(
        query: _query.trim(),
        groupName: _query.trim().isEmpty ? _activeGroup?.name : null,
        onReset: _resetFilters,
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: _grid ? _buildBookGrid(books) : _buildBookList(books),
    );
  }

  Widget _buildBookGrid(List<_ShelfItem> books) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth =
            (constraints.maxWidth -
                _shelfGridPadding * 2 -
                _shelfGridSpacing * (_shelfColumns - 1)) /
            _shelfColumns;
        final titleHeight = MediaQuery.textScalerOf(context)
            .scale(_shelfTitleHeight);
        final metaHeight = MediaQuery.textScalerOf(context)
            .scale(_shelfMetaHeight);
        return GridView.builder(
          key: const ValueKey<String>('bookshelf-grid'),
          padding: EdgeInsets.fromLTRB(
            _shelfGridPadding,
            12,
            _shelfGridPadding,
            _selectionMode ? 160 : 96,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _shelfColumns,
            mainAxisExtent:
                cardWidth / _shelfCoverAspectRatio +
                _shelfTitleGap +
                titleHeight +
                metaHeight,
            mainAxisSpacing: 20,
            crossAxisSpacing: _shelfGridSpacing,
          ),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final item = books[index];
            return _BookCard(
              entry: item.entry,
              percentInt: item.percentInt,
              finished: item.finished,
              selectionMode: _selectionMode,
              selected: _selectedIds.contains(item.entry.id),
              onSelect: () => _toggleSelected(item.entry.id),
              onOpen: _open,
              onLongPress: _openBookDetail,
            );
          },
        );
      },
    );
  }

  Widget _buildBookList(List<_ShelfItem> books) {
    return ListView.separated(
      key: const ValueKey<String>('bookshelf-list'),
      padding: EdgeInsets.fromLTRB(16, 8, 16, _selectionMode ? 160 : 96),
      itemCount: books.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = books[index];
        return _BookRow(
          entry: item.entry,
          percentInt: item.percentInt,
          finished: item.finished,
          selectionMode: _selectionMode,
          selected: _selectedIds.contains(item.entry.id),
          onSelect: () => _toggleSelected(item.entry.id),
          onOpen: _open,
          onLongPress: _openBookDetail,
        );
      },
    );
  }

  Widget _buildSelectionBar() {
    final theme = Theme.of(context);
    final count = _selectedIds.length;
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                count == 0 ? '请选择书籍' : '分组或删除',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey<String>(
                        'bookshelf-batch-create-group',
                      ),
                      onPressed: count == 0 || _removing
                          ? null
                          : () => _createGroup(
                              initialBookIds: Set<String>.of(_selectedIds),
                            ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      label: const Text('新建分组'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey<String>('bookshelf-batch-group'),
                      onPressed: count == 0 || _removing
                          ? null
                          : _moveSelectedToGroup,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.folder_outlined, size: 18),
                      label: const Text('分组'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey<String>('bookshelf-batch-delete'),
                      onPressed: count == 0 || _removing
                          ? null
                          : _confirmBatchRemove,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: _removing
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onError,
                              ),
                            )
                          : const Icon(Icons.delete_outline, size: 18),
                      label: Text(_removing ? '删除中' : '删除'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) {
      Navigator.of(context).pop(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey<String>('bookshelf-group-name-field'),
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: '分组名称',
          hintText: '例如：小说、待读',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey<String>('bookshelf-group-name-confirm'),
          onPressed: _controller.text.trim().isEmpty ? null : _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _NewGroupDialog extends StatefulWidget {
  const _NewGroupDialog({
    required this.items,
    required this.groups,
    required this.assignments,
    required this.initialBookIds,
  });

  final List<_ShelfItem> items;
  final List<ShelfGroup> groups;
  final Map<String, String> assignments;
  final Set<String> initialBookIds;

  @override
  State<_NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends State<_NewGroupDialog> {
  final TextEditingController _controller = TextEditingController();
  late final Set<String> _selected = Set<String>.of(widget.initialBookIds);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _groupName(String? groupId) {
    if (groupId == null) {
      return null;
    }
    for (final group in widget.groups) {
      if (group.id == groupId) {
        return group.name;
      }
    }
    return null;
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.of(context).pop((name: name, bookIds: Set<String>.of(_selected)));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('新建分组'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              key: const ValueKey<String>('bookshelf-group-create-name'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '分组名称',
                hintText: '例如：小说、待读',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Text('选择书籍', style: textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '可稍后通过多选调整',
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: widget.items.isEmpty
                  ? const Center(child: Text('书架还没有书'))
                  : ListView.builder(
                      itemCount: widget.items.length,
                      itemBuilder: (context, index) {
                        final item = widget.items[index];
                        final currentGroup = _groupName(
                          widget.assignments[item.entry.id],
                        );
                        return CheckboxListTile(
                          key: ValueKey<String>(
                            'bookshelf-group-book-${item.entry.id}',
                          ),
                          value: _selected.contains(item.entry.id),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            item.entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: currentGroup == null
                              ? null
                              : Text('当前在「$currentGroup」'),
                          onChanged: (selected) {
                            setState(() {
                              if (selected ?? false) {
                                _selected.add(item.entry.id);
                              } else {
                                _selected.remove(item.entry.id);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey<String>('bookshelf-group-create-confirm'),
          onPressed: _controller.text.trim().isEmpty ? null : _submit,
          child: const Text('创建'),
        ),
      ],
    );
  }
}

class _ShelfGroupBar extends StatelessWidget {
  const _ShelfGroupBar({
    required this.items,
    required this.groups,
    required this.assignments,
    required this.activeGroupId,
    required this.onToggle,
    required this.onShowAll,
    required this.onManage,
  });

  final List<_ShelfItem> items;
  final List<ShelfGroup> groups;
  final Map<String, String> assignments;
  final String? activeGroupId;
  final ValueChanged<String> onToggle;
  final VoidCallback onShowAll;
  final ValueChanged<ShelfGroup> onManage;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final item in items) {
      final groupId = assignments[item.entry.id];
      if (groupId != null) {
        counts[groupId] = (counts[groupId] ?? 0) + 1;
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: <Widget>[
          _ShelfGroupTab(
            key: const ValueKey<String>('bookshelf-group-all'),
            label: '全部 ${items.length}',
            selected: activeGroupId == null,
            onTap: onShowAll,
          ),
          for (final group in groups)
            _ShelfGroupTab(
              key: ValueKey<String>('bookshelf-group-${group.id}'),
              label: '${group.name} ${counts[group.id] ?? 0}',
              selected: group.id == activeGroupId,
              onTap: () => onToggle(group.id),
              onLongPress: () => onManage(group),
            ),
        ],
      ),
    );
  }
}

/// 分组采用文字页签，让书封面成为书架的视觉重点。
class _ShelfGroupTab extends StatelessWidget {
  const _ShelfGroupTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.only(right: 20),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
              ),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: selected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// 导入进度条：当前任务名 + 进度 + 取消（P4-03）。
class _ImportBanner extends StatelessWidget {
  const _ImportBanner({required this.queue, required this.onCancel});

  final ImportQueue queue;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final job = queue.activeJob;
    final theme = Theme.of(context);
    final label = job == null
        ? '等待导入（排队 ${queue.pendingCount} 本）'
        : '正在导入：${job.fallbackTitle ?? '书籍'}'
              '${queue.pendingCount > 0 ? '（排队 ${queue.pendingCount} 本）' : ''}';
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: job?.progress),
                ],
              ),
            ),
            TextButton(onPressed: onCancel, child: const Text('取消')),
          ],
        ),
      ),
    );
  }
}

/// 列表视图的一行（P4-08）：封面缩略 + 书名。
class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.entry,
    required this.percentInt,
    required this.finished,
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onLongPress,
  });

  final BookEntry entry;
  final int? percentInt;
  final bool finished;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;
  final Future<void> Function(BookEntry) onOpen;
  final Future<void> Function(BookEntry) onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      alignment: Alignment.center,
      child: Text(
        entry.title.isEmpty ? '书' : entry.title.characters.first,
        style: theme.textTheme.titleMedium,
      ),
    );
    final cover = Hero(
      tag: bookCoverHeroTag(entry.id),
      transitionOnUserGestures: true,
      child: SizedBox(
        key: const ValueKey<String>('book-row-cover'),
        width: 48,
        height: 64,
        child: entry.coverPath == null
            ? placeholder
            : ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(entry.coverPath!),
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  cacheWidth: 126,
                  errorBuilder: (_, _, _) => placeholder,
                ),
              ),
      ),
    );
    final trailing = <Widget>[
      if (entry.readabilityLevel >= 2)
        Icon(
          Icons.report_problem_outlined,
          color: theme.colorScheme.error,
          size: 18,
        ),
      if (selectionMode)
        Checkbox(
          key: ValueKey<String>('book-row-check-${entry.id}'),
          value: selected,
          onChanged: (_) => onSelect(),
          visualDensity: VisualDensity.compact,
        ),
    ];
    return Semantics(
      selected: selectionMode && selected,
      child: InkWell(
        key: ValueKey<String>('book-row-${entry.id}'),
        onTap: () {
          if (selectionMode) {
            onSelect();
          } else {
            onOpen(entry);
          }
        },
        onLongPress: () {
          if (selectionMode) {
            onSelect();
          } else {
            onLongPress(entry);
          }
        },
        child: Ink(
          color: selectionMode && selected
              ? theme.colorScheme.surfaceContainerLow
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              cover,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.title,
                      key: ValueKey<String>('book-row-title-${entry.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _shelfMetaLabel(entry, percentInt, finished),
                      key: ValueKey<String>('book-row-meta-${entry.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8),
                ...trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _shelfMetaLabel(BookEntry entry, int? percentInt, bool finished) {
  final author = entry.author.trim().isEmpty ? '未知作者' : entry.author.trim();
  final status = switch (finished ? BookReadingStatus.finished : entry.status) {
    BookReadingStatus.unread => '未开始',
    BookReadingStatus.reading => percentInt == null ? '在读' : '在读 $percentInt%',
    BookReadingStatus.finished => '已读完',
  };
  return '$status · $author';
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text('书架还是空的', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('点击右上角导入按钮添加第一本书', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _NoMatchesPane extends StatelessWidget {
  const _NoMatchesPane({
    required this.query,
    required this.onReset,
    this.groupName,
  });

  final String query;
  final VoidCallback onReset;
  final String? groupName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              query.isNotEmpty
                  ? '没有找到相关书籍'
                  : groupName == null
                  ? '没有符合筛选条件的书'
                  : '这个分组还没有书',
              style: theme.textTheme.titleMedium,
            ),
            if (query.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '没有书名或作者包含“$query”',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ] else if (groupName != null) ...[
              const SizedBox(height: 4),
              Text(
                '长按书籍选择多选，再移入「$groupName」',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: Text(groupName == null ? '清除筛选' : '查看全部书籍'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.entry,
    required this.percentInt,
    required this.finished,
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onLongPress,
  });

  final BookEntry entry;
  final int? percentInt;
  final bool finished;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;
  final Future<void> Function(BookEntry) onOpen;
  final Future<void> Function(BookEntry) onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          Center(
            child: Text(
              _coverGlyph(entry.title),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          // L2/L3 结构异常角标（P3-27，§55.2：必须让用户知道书被修复过）。
          if (entry.readabilityLevel >= 2)
            Positioned(
              top: 0,
              right: 0,
              child: Tooltip(
                message: entry.readabilityLevel >= 3
                    ? '结构异常：进度与目录可能不可靠'
                    : '部分内容降级：目录或资源缺失',
                child: Container(
                  key: const ValueKey<String>('book-damaged-badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.readabilityLevel >= 3 ? '结构异常' : '部分降级',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    // 封面（§37.3）：缓存文件优先，缺失/解码失败退回书名首字占位。
    final cover = Hero(
      tag: bookCoverHeroTag(entry.id),
      transitionOnUserGestures: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (entry.coverPath == null)
              placeholder
            else
              Image.file(
                File(entry.coverPath!),
                fit: BoxFit.cover,
                cacheWidth: 320,
                errorBuilder: (_, _, _) => placeholder,
              ),
            if (selectionMode)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    color: selected
                        ? theme.colorScheme.primary.withAlpha(36)
                        : Colors.transparent,
                  ),
                ),
              ),
            if (selectionMode)
              Positioned(
                top: 6,
                left: 6,
                child: _BookSelectionMark(
                  key: ValueKey<String>('book-selected-${entry.id}'),
                  selected: selected,
                ),
              ),
          ],
        ),
      ),
    );
    return InkWell(
      key: ValueKey<String>('book-card-${entry.id}'),
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        if (selectionMode) {
          onSelect();
        } else {
          onOpen(entry);
        }
      },
      onLongPress: () {
        if (selectionMode) {
          onSelect();
        } else {
          onLongPress(entry);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            key: const ValueKey<String>('book-card-cover'),
            aspectRatio: _shelfCoverAspectRatio,
            child: cover,
          ),
          const SizedBox(height: _shelfTitleGap),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(_shelfTitleHeight),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                entry.title,
                key: ValueKey<String>('book-card-title-${entry.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selectionMode && selected
                      ? theme.colorScheme.primary
                      : null,
                ),
              ),
            ),
          ),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(_shelfMetaHeight),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _shelfMetaLabel(entry, percentInt, finished),
                key: ValueKey<String>('book-card-meta-${entry.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookSelectionMark extends StatelessWidget {
  const _BookSelectionMark({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      label: selected ? '已选择' : '未选择',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surface.withAlpha(232),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 18, color: theme.colorScheme.onPrimary)
            : null,
      ),
    );
  }
}

/// 封面占位字形：标题首字符，空标题回退「书」。
String _coverGlyph(String title) {
  final chars = title.characters;
  return chars.isEmpty ? '书' : chars.first.toString();
}
