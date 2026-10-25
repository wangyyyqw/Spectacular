import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:reader_core/epub/importer.dart';

import '../library/library_store.dart';
import '../reader/epub_reader_page.dart';
import 'book_detail_sheet.dart';
import '../storage/file_progress_store.dart';
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
  final FileReaderProgressStore progressStore;

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

  List<BookEntry>? _books;
  late final ImportQueue _queue;
  final List<ImportJob> _batch = <ImportJob>[];
  int _reportedJobs = 0;
  String? _error;
  BookSortOrder _sort = BookSortOrder.recent;
  bool _grid = true;

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_reload);
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

  /// 按当前排序方式排序（list() 默认最近阅读优先）。
  List<BookEntry> _sorted(List<BookEntry> books) {
    final sorted = List<BookEntry>.of(books);
    switch (_sort) {
      case BookSortOrder.recent:
        break;
      case BookSortOrder.added:
        sorted.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case BookSortOrder.title:
        sorted.sort((a, b) => a.title.compareTo(b.title));
    }
    return sorted;
  }

  @override
  void dispose() {
    widget.library.removeListener(_reload);
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

  void _reload() {
    widget.library.list().then((books) {
      if (mounted) {
        setState(() {
          _books = books;
        });
      }
    });
  }

  /// 多选 EPUB 入队（P4-03）：后台串行导入，UI 不阻塞。
  Future<void> _import() async {
    final paths = await widget.pickEpubFiles();
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

  Future<void> _open(BookEntry entry) async {
    final bytes = await widget.library.readBytes(entry);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EpubReaderPage(
          bytes: bytes,
          bookId: entry.id,
          store: widget.progressStore,
        ),
      ),
    );
    await widget.library.touchLastRead(entry.id);
  }

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

  @override
  Widget build(BuildContext context) {
    final books = _books;
    final busy = _queue.isBusy;
    final ordered = books == null ? null : _sorted(books);
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: <Widget>[
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : _import,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(busy ? '导入中…' : '导入 EPUB'),
      ),
      body: Column(
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
          Expanded(
            child: _error != null
                ? _ErrorPane(message: _error!, onRetry: _import)
                : books == null
                ? const Center(child: CircularProgressIndicator())
                : books.isEmpty
                ? const _EmptyPane()
                : RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: _grid
                        ? GridView.builder(
                            key: const ValueKey<String>('bookshelf-grid'),
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.62,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                            ),
                            itemCount: ordered!.length,
                            itemBuilder: (context, index) => _BookCard(
                              entry: ordered[index],
                              onOpen: _open,
                              onLongPress: _openBookDetail,
                            ),
                          )
                        : ListView.builder(
                            key: const ValueKey<String>('bookshelf-list'),
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                            itemCount: ordered!.length,
                            itemBuilder: (context, index) => _BookRow(
                              entry: ordered[index],
                              onOpen: _open,
                              onLongPress: _openBookDetail,
                            ),
                          ),
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

/// 列表视图的一行（P4-08）：封面缩略 + 标题/作者 + 状态。
class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.entry,
    required this.onOpen,
    required this.onLongPress,
  });

  final BookEntry entry;
  final Future<void> Function(BookEntry) onOpen;
  final Future<void> Function(BookEntry) onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: 48,
      height: 68,
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
    final cover = entry.coverPath == null
        ? placeholder
        : ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(entry.coverPath!),
              width: 48,
              height: 68,
              fit: BoxFit.cover,
              cacheWidth: 144,
              errorBuilder: (_, _, _) => placeholder,
            ),
          );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: cover,
      title: Text(
        entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        [
          entry.author.isEmpty ? '未知作者' : entry.author,
          if (entry.spineCount != null) '${entry.spineCount} 章',
          if (entry.status == BookReadingStatus.reading) '在读',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      trailing: entry.readabilityLevel >= 2
          ? Icon(
              Icons.report_problem_outlined,
              color: theme.colorScheme.error,
              size: 18,
            )
          : null,
      onTap: () => onOpen(entry),
      onLongPress: () => onLongPress(entry),
    );
  }
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
    required this.onOpen,
    required this.onLongPress,
  });

  final BookEntry entry;
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
    final cover = ClipRRect(
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
            const Align(
              alignment: Alignment.bottomLeft,
              child: _ReadingBadge(),
            ),
        ],
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onOpen(entry),
      onLongPress: () => onLongPress(entry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cover),
          const SizedBox(height: 6),
          Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            entry.author.isEmpty ? '未知作者' : entry.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// 「在读」角标（P4-04：状态随进度自动更新）。
class _ReadingBadge extends StatelessWidget {
  const _ReadingBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey<String>('book-reading-badge'),
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '在读',
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
