import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:reader_core/epub/importer.dart';

import '../library/library_store.dart';
import '../reader/epub_reader_page.dart';
import '../storage/file_progress_store.dart';

/// 书架页：书籍网格、EPUB 导入、点击进入阅读、长按删除。
class BookshelfPage extends StatefulWidget {
  /// 创建页面。
  const BookshelfPage({
    super.key,
    required this.library,
    required this.progressStore,
    this.pickEpubFile = _pickWithFilePicker,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 阅读进度存储（进阅读页用）。
  final FileReaderProgressStore progressStore;

  /// 选文件入口（默认 file_picker；测试注入）。
  final Future<String?> Function() pickEpubFile;

  static Future<String?> _pickWithFilePicker() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['epub'],
    );
    if (files.isEmpty) {
      return null;
    }
    return files.single.path;
  }

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  List<BookEntry>? _books;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.library.removeListener(_reload);
    super.dispose();
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

  Future<void> _import() async {
    if (_importing) {
      return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final path = await widget.pickEpubFile();
      if (path == null) {
        return;
      }
      final bytes = await File(path).readAsBytes();
      final entry = await widget.library.importBytes(
        bytes,
        fallbackTitle: path.split(Platform.pathSeparator).last,
      );
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('已导入《${entry.title}》')),
        );
      }
    } on LibraryImportException catch (error) {
      if (mounted) {
        // P3-27：拒绝文案由码表驱动，给原因与建议，不暴露堆栈。
        final friendly = EpubRejectionMessages.forCode(
          error.errorCode,
          error.message,
        );
        setState(() => _error = '${friendly.title}。${friendly.suggestion}');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '导入失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
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
    return Scaffold(
      appBar: AppBar(title: const Text('书架')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(_importing ? '导入中…' : '导入 EPUB'),
      ),
      body: _error != null
          ? _ErrorPane(message: _error!, onRetry: _import)
          : books == null
          ? const Center(child: CircularProgressIndicator())
          : books.isEmpty
          ? const _EmptyPane()
          : RefreshIndicator(
              onRefresh: () async => _reload(),
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.62,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: books.length,
                itemBuilder: (context, index) =>
                    _BookCard(entry: books[index], onOpen: _open, onRemove: _confirmRemove),
              ),
            ),
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
  const _BookCard({required this.entry, required this.onOpen, required this.onRemove});

  final BookEntry entry;
  final Future<void> Function(BookEntry) onOpen;
  final Future<void> Function(BookEntry) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = Container(
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
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onOpen(entry),
      onLongPress: () => onRemove(entry),
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

/// 封面占位字形：标题首字符，空标题回退「书」。
String _coverGlyph(String title) {
  final chars = title.characters;
  return chars.isEmpty ? '书' : chars.first.toString();
}
