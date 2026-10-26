import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/panels/search_panel.dart';
import 'package:reader_ui/reader_session.dart';

import 'package:reader_core/epub/importer.dart';

import '../library/library_store.dart';
import '../reader/epub_chapter_source.dart';
import '../reader/epub_reader_page.dart';
import '../reader/reader_settings.dart';
import '../search/search_service.dart';
import 'book_detail_sheet.dart';
import '../diagnostics/reader_log.dart';
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

  /// 阅读设置缓存（P4-21）。
  ReaderSettings? _settings;
  late final ImportQueue _queue;
  final List<ImportJob> _batch = <ImportJob>[];
  int _reportedJobs = 0;
  String? _error;
  BookSortOrder _sort = BookSortOrder.recent;
  bool _grid = true;
  int _reloadToken = 0;

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
      setState(() => _items = items);
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

  /// 构造本书的搜索回调（P4-26）：首次查询时打开章节源，之后复用。
  Future<List<SearchPanelResult>> Function(String query)? _buildSearch(
    BookEntry entry,
    Uint8List bytes,
  ) {
    final store = widget.library.searchIndexStore();
    if (store == null) {
      return null;
    }
    SearchService? service;
    int? bookId;
    return (query) async {
      bookId ??= await widget.library.internalBookId(entry.id);
      final id = bookId;
      if (id == null) {
        return const <SearchPanelResult>[];
      }
      service ??= SearchService(
        source: await EpubChapterSource.open(bytes),
        store: store,
      );
      final results = await service!.search(id, query);
      return <SearchPanelResult>[
        for (final result in results)
          SearchPanelResult(
            spineIndex: result.spineIndex,
            charOffset: result.charOffset,
            chapterTitle: result.chapterTitle,
            context: result.context,
            matchLength: result.matchLength,
            cfi: result.cfi,
          ),
      ];
    };
  }

  /// 读取并缓存阅读设置（P4-21）。
  Future<void> _loadReaderSettings() async {
    final settings = await ReaderSettingsStore(widget.library).load();
    if (mounted) {
      setState(() => _settings = settings);
    }
  }

  /// 保存阅读设置（P4-21）。
  Future<void> _saveReaderSettings(ReaderSettings settings) async {
    setState(() => _settings = settings);
    unawaited(
      ReaderLog.instance.log(
        'user_settings',
        fields: <String, Object?>{
          'font_size': settings.fontSize,
          'line_height': settings.lineHeight,
          'paragraph_spacing': settings.paragraphSpacing,
          'theme': settings.themeId,
          'background': settings.backgroundId,
          'ink_mode': settings.inkMode,
        },
      ),
    );
    await ReaderSettingsStore(widget.library).save(settings);
  }

  Future<void> _open(BookEntry entry) async {
    if (_settings == null) {
      await _loadReaderSettings();
    }
    if (!mounted) {
      return;
    }
    // 大书读盘要几秒：先给个反馈，避免「点了没反应」。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在打开《${entry.title}》…'),
        duration: const Duration(seconds: 2),
      ),
    );
    final readWatch = Stopwatch()..start();
    final bytes = await widget.library.readBytes(entry);
    readWatch.stop();
    unawaited(
      ReaderLog.instance.log(
        'user_open_book',
        fields: <String, Object?>{
          'book': entry.title,
          'bytes': bytes.length,
          'read_ms': readWatch.elapsedMilliseconds,
        },
      ),
    );
    if (!mounted) {
      return;
    }
    // P4-24：后台建 2-gram 索引（断点续建）。
    // 延后 3 秒再启动：索引要逐章解析+排版，上千章的书会在阅读页刚打开时
    // 抢满主线程，导致翻页和按钮都点不动。
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3)).then(
        (_) => widget.library
            .ensureSearchIndex(entry.id, bytes)
            .catchError((Object _) => 0),
      ),
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EpubReaderPage(
          bytes: bytes,
          bookId: entry.id,
          store: widget.progressStore,
          bookmarks: widget.library.bookmarkStore(entry.id),
          annotations: widget.library.annotationStore(entry.id),
          settings: _settings ?? ReaderSettings.defaults,
          onSettingsChanged: _saveReaderSettings,
          onSearch: _buildSearch(entry, bytes),
          bookTitle: entry.title,
          onMarginsChanged: (margins) {
            final current = _settings ?? ReaderSettings.defaults;
            final next = current.copyWithMargins(margins);
            setState(() => _settings = next);
            unawaited(_saveReaderSettings(next));
          },
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
    final items = _items;
    final busy = _queue.isBusy;
    final ordered = items == null ? null : _sorted(items);
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
                : items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
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
                              entry: ordered[index].entry,
                              percentInt: ordered[index].percentInt,
                              onOpen: _open,
                              onLongPress: _openBookDetail,
                            ),
                          )
                        : ListView.builder(
                            key: const ValueKey<String>('bookshelf-list'),
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                            itemCount: ordered!.length,
                            itemBuilder: (context, index) => _BookRow(
                              entry: ordered[index].entry,
                              percentInt: ordered[index].percentInt,
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
    required this.percentInt,
    required this.onOpen,
    required this.onLongPress,
  });

  final BookEntry entry;
  final int? percentInt;
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
          if (entry.status == BookReadingStatus.reading)
            percentInt == null ? '在读' : '在读 $percentInt%',
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
    required this.percentInt,
    required this.onOpen,
    required this.onLongPress,
  });

  final BookEntry entry;
  final int? percentInt;
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
            Align(
              alignment: Alignment.bottomLeft,
              child: _ReadingBadge(percentInt: percentInt),
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
