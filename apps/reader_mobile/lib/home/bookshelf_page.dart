import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/reader_session.dart';

import 'package:reader_core/epub/importer.dart';

import '../library/library_store.dart';
import '../reader/book_opener.dart';
import 'book_detail_sheet.dart';
import '../storage/import_queue.dart';

/// 书架排序方式（P4-08）。
enum BookSortOrder {
  /// 最近阅读优先（默认）。
  recent('最近阅读', 'recent'),

  /// 导入时间倒序。
  added('导入时间', 'added'),

  /// 书名升序。
  title('书名', 'title');

  const BookSortOrder(this.label, this.value);

  /// 菜单文案。
  final String label;

  /// 持久化值。
  final String value;

  /// 按持久化值还原，未知值回退最近阅读。
  static BookSortOrder fromValue(String? value) {
    for (final order in values) {
      if (order.value == value) {
        return order;
      }
    }
    return recent;
  }
}

/// 书架条目 + 进度（P4-09：百分比由字符权重表算，章级粒度）。
typedef _ShelfItem = ({BookEntry entry, int? percentInt});

/// 书架阅读状态筛选。
enum _ShelfStatusFilter {
  all('全部'),
  unread('未读'),
  reading('在读');

  const _ShelfStatusFilter(this.label);

  final String label;

  bool matches(BookReadingStatus status) => switch (this) {
    all => true,
    unread => status == BookReadingStatus.unread,
    reading => status == BookReadingStatus.reading,
  };
}

const _shelfColumns = 3;
const _shelfGridPadding = 16.0;
const _shelfGridSpacing = 12.0;
const _shelfCoverAspectRatio = 3 / 4;
const _shelfTitleGap = 6.0;
const _shelfTitleHeight = 20.0;

/// 书架页：书籍网格/列表、EPUB 导入、点击进入阅读、长按看详情。
class BookshelfPage extends StatefulWidget {
  /// 创建页面。
  const BookshelfPage({
    super.key,
    required this.library,
    required this.progressStore,
    this.pickEpubFiles = _pickWithFilePicker,
    this.readFile = _readFile,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 阅读进度存储（进阅读页用）。
  final ReaderProgressStore progressStore;

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

  static const _sortKey = 'bookshelf.sort';
  static const _viewKey = 'bookshelf.grid';

  List<_ShelfItem>? _items;

  late final BookOpener _bookOpener;
  late final ImportQueue _queue;
  final List<ImportJob> _batch = <ImportJob>[];
  int _reportedJobs = 0;
  String? _error;
  BookSortOrder _sort = BookSortOrder.recent;
  _ShelfStatusFilter _filter = _ShelfStatusFilter.all;
  bool _grid = true;
  bool _searching = false;
  bool _selectionMode = false;
  bool _removing = false;
  String _query = '';
  final Set<String> _selectedIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_reload);
    _bookOpener = BookOpener(
      library: widget.library,
      progressStore: widget.progressStore,
    );
    _queue = ImportQueue(widget.library)..addListener(_onQueueChanged);
    _reload();
    _loadPreferences();
  }

  /// 读持久化的排序与视图模式（settings 表）。
  Future<void> _loadPreferences() async {
    final sort = await widget.library.getSetting(_sortKey);
    final grid = await widget.library.getSetting(_viewKey);
    if (!mounted) {
      return;
    }
    setState(() {
      _sort = BookSortOrder.fromValue(sort);
      _grid = grid != 'false';
    });
  }

  Future<void> _setSort(BookSortOrder order) async {
    setState(() => _sort = order);
    await widget.library.setSetting(_sortKey, order.value);
  }

  Future<void> _toggleView() async {
    final grid = !_grid;
    setState(() => _grid = grid);
    await widget.library.setSetting(_viewKey, '$grid');
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
      _filter = _ShelfStatusFilter.all;
    });
  }

  void _enterSelectionMode() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _selectionMode = true;
      _searching = false;
      _query = '';
      _filter = _ShelfStatusFilter.all;
      _selectedIds.clear();
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

  /// 先按关键词与阅读状态过滤，再沿用书架排序。
  List<_ShelfItem> _visible(List<_ShelfItem> items) {
    final query = _query.trim().toLowerCase();
    final filtered = items.where((item) {
      if (!_filter.matches(item.entry.status)) {
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
      messenger?.showSnackBar(SnackBar(content: Text('已导入 $succeeded 本书')));
    }
    if (failed != null) {
      // P3-27：拒绝文案由码表驱动，给原因与建议，不暴露堆栈。
      final friendly = EpubRejectionMessages.forCode(
        failed.errorCode,
        failed.error ?? '',
      );
      setState(() => _error = '${friendly.title}。${friendly.suggestion}');
    } else if (succeeded == 0 && cancelled > 0) {
      messenger?.showSnackBar(const SnackBar(content: Text('已取消导入')));
    }
  }

  Future<void> _reload() async {
    // 递增 token：并发刷新时只让最后一次生效，避免旧结果覆盖新状态。
    final token = ++_reloadToken;
    final books = await widget.library.list();
    final items = <_ShelfItem>[];
    for (final book in books) {
      int? percent;
      final progress = await widget.progressStore.load(book.id);
      if (progress != null) {
        final weights = await widget.library.progressWeights(book.id);
        if (weights.total > 0) {
          percent = weights.percentInt(progress.spineIndex);
        }
      }
      items.add((entry: book, percentInt: percent));
    }
    if (mounted && token == _reloadToken) {
      final validIds = <String>{for (final item in items) item.entry.id};
      setState(() {
        _items = items;
        _selectedIds.removeWhere((id) => !validIds.contains(id));
        if (items.isEmpty) {
          _selectionMode = false;
        }
      });
    }
  }

  /// 多选 EPUB 入队（P4-03）：后台串行导入，UI 不阻塞。
  Future<void> _import() async {
    // ignore: avoid_print
    print('[import] 开始选择文件');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在打开文件选择器…'), duration: Duration(seconds: 2)),
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
        final bytes = await widget.readFile(path);
        // 大文件（>20MB）导入要十几秒：先给出预期，避免以为卡死。
        final megabytes = bytes.length / (1024 * 1024);
        if (megabytes >= 20 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '正在导入大文件（${megabytes.toStringAsFixed(0)}MB），请稍候…',
              ),
            ),
          );
        }
        _batch.add(
          _queue.enqueue(
            bytes,
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

  /// 长按卡片：书籍详情 + 导入报告（P4-06），详情里可删除。
  Future<void> _openBookDetail(BookEntry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BookDetailSheet(entry: entry, library: widget.library),
    );
    if (action == 'delete' && mounted) {
      await _confirmRemove(entry);
    }
  }

  Future<void> _confirmRemove(BookEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除《${entry.title}》'),
        content: const Text('将删除书籍文件与阅读进度，且不可恢复。'),
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
      await widget.progressStore.clear(entry.id);
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
        content: const Text('将永久删除书籍文件、阅读进度、书签、笔记和高亮，且不可恢复。'),
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

  Future<void> _removeSelected(List<BookEntry> entries) async {
    setState(() => _removing = true);
    var removed = 0;
    final failedIds = <String>[];
    for (final entry in entries) {
      try {
        await widget.progressStore.clear(entry.id);
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
      floatingActionButton: _selectionMode ? null : _buildImportButton(busy),
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
          _selectedIds.isEmpty ? '批量管理' : '已选 ${_selectedIds.length} 本',
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
          : const Text('书架'),
      actions: _searching
          ? <Widget>[
              IconButton(
                tooltip: '关闭搜索',
                onPressed: _toggleSearch,
                icon: const Icon(Icons.close),
              ),
            ]
          : <Widget>[
              IconButton(
                tooltip: '搜索书架',
                onPressed: _toggleSearch,
                icon: const Icon(Icons.search),
              ),
              if (items != null && items.isNotEmpty)
                IconButton(
                  tooltip: '批量管理',
                  onPressed: busy ? null : _enterSelectionMode,
                  icon: const Icon(Icons.checklist),
                ),
              PopupMenuButton<BookSortOrder>(
                tooltip: '排序',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: _setSort,
                itemBuilder: (_) => <PopupMenuEntry<BookSortOrder>>[
                  for (final order in BookSortOrder.values)
                    PopupMenuItem<BookSortOrder>(
                      value: order,
                      child: Text(order.label),
                    ),
                ],
              ),
              IconButton(
                tooltip: _grid ? '列表视图' : '网格视图',
                onPressed: _toggleView,
                icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view),
              ),
            ],
    );
  }

  Widget _buildImportButton(bool busy) {
    return FloatingActionButton.extended(
      onPressed: busy ? null : _import,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add),
      label: Text(busy ? '导入中…' : '导入 EPUB'),
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
            items.isNotEmpty)
          _ShelfFilterBar(
            items: items,
            selected: _filter,
            onSelected: (filter) => setState(() => _filter = filter),
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
      return _NoMatchesPane(query: _query.trim(), onReset: _resetFilters);
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
                titleHeight,
            mainAxisSpacing: _shelfGridSpacing,
            crossAxisSpacing: _shelfGridSpacing,
          ),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final item = books[index];
            return _BookCard(
              entry: item.entry,
              percentInt: item.percentInt,
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
    return ListView.builder(
      key: const ValueKey<String>('bookshelf-list'),
      padding: EdgeInsets.fromLTRB(12, 8, 12, _selectionMode ? 160 : 96),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final item = books[index];
        return _BookRow(
          entry: item.entry,
          percentInt: item.percentInt,
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
      color: theme.colorScheme.surfaceContainer,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                count == 0 ? '请选择要删除的书籍' : '删除后不可恢复',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton.icon(
              key: const ValueKey<String>('bookshelf-batch-delete'),
              onPressed: count == 0 || _removing ? null : _confirmBatchRemove,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
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
                  : const Icon(Icons.delete_outline),
              label: Text(_removing ? '正在删除…' : '删除'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShelfFilterBar extends StatelessWidget {
  const _ShelfFilterBar({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<_ShelfItem> items;
  final _ShelfStatusFilter selected;
  final ValueChanged<_ShelfStatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: <Widget>[
          for (final filter in _ShelfStatusFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey<String>('bookshelf-filter-${filter.name}'),
                label: Text(
                  '${filter.label} '
                  '${items.where((item) => filter.matches(item.entry.status)).length}',
                ),
                selected: filter == selected,
                showCheckmark: false,
                onSelected: (_) => onSelected(filter),
              ),
            ),
        ],
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
      color: theme.colorScheme.surfaceContainerHighest,
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
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onLongPress,
  });

  final BookEntry entry;
  final int? percentInt;
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
        color: HSLColor.fromAHSL(
          1,
          entry.coverHue.toDouble(),
          0.42,
          0.38,
        ).toColor(),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        entry.title.isEmpty ? '书' : entry.title.characters.first,
        style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
      ),
    );
    final cover = Hero(
      tag: bookCoverHeroTag(entry.id),
      transitionOnUserGestures: true,
      child: SizedBox(
        key: const ValueKey<String>('book-row-cover'),
        width: 42,
        height: 56,
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
    return ListTile(
      key: ValueKey<String>('book-row-${entry.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: cover,
      title: Text(
        entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        _shelfMetaLabel(entry, percentInt),
        key: ValueKey<String>('book-row-meta-${entry.id}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: trailing.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: trailing),
      selected: selectionMode && selected,
      selectedTileColor: theme.colorScheme.primary.withAlpha(18),
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
    );
  }
}

String _shelfMetaLabel(BookEntry entry, int? percentInt) {
  final author = entry.author.trim().isEmpty ? '未知作者' : entry.author.trim();
  final status = switch (entry.status) {
    BookReadingStatus.unread => '未开始',
    BookReadingStatus.reading => percentInt == null ? '在读' : '在读 $percentInt%',
    BookReadingStatus.finished => '已读完',
  };
  return '$author · $status';
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
          Text(
            '点击右下角「导入 EPUB」添加第一本书',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NoMatchesPane extends StatelessWidget {
  const _NoMatchesPane({required this.query, required this.onReset});

  final String query;
  final VoidCallback onReset;

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
              query.isEmpty ? '没有符合筛选条件的书' : '没有找到相关书籍',
              style: theme.textTheme.titleMedium,
            ),
            if (query.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '没有书名或作者包含“$query”',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('清除筛选'),
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
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onLongPress,
  });

  final BookEntry entry;
  final int? percentInt;
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
        color: HSLColor.fromAHSL(
          1,
          entry.coverHue.toDouble(),
          0.42,
          0.38,
        ).toColor(),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _coverGlyph(entry.title),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
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
                    borderRadius: BorderRadius.circular(6),
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
        borderRadius: BorderRadius.circular(8),
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
            if (entry.status == BookReadingStatus.reading)
              Align(
                alignment: Alignment.bottomLeft,
                child: _ReadingBadge(percentInt: percentInt),
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
      borderRadius: BorderRadius.circular(8),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selectionMode && selected
                      ? theme.colorScheme.primary
                      : null,
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

/// 「在读」角标（P4-04：状态随进度自动更新）。
class _ReadingBadge extends StatelessWidget {
  const _ReadingBadge({this.percentInt});

  final int? percentInt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = percentInt == null ? '在读' : '在读 $percentInt%';
    return Container(
      key: const ValueKey<String>('book-reading-badge'),
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}

/// 封面占位字形：标题首字符，空标题回退「书」。
String _coverGlyph(String title) {
  final chars = title.characters;
  return chars.isEmpty ? '书' : chars.first.toString();
}
