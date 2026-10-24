import 'package:flutter/material.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/library_store.dart';
import '../storage/file_progress_store.dart';

/// 统计页：书量、在读、最近阅读（数据来自书架与进度存储的真值）。
/// 阅读时长/热力图等埋点指标随 P4-31 落地。
class StatsPage extends StatefulWidget {
  /// 创建页面。
  const StatsPage({super.key, required this.library, required this.progressStore});

  /// 书架存储。
  final LibraryStore library;

  /// 进度存储。
  final FileReaderProgressStore progressStore;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  List<BookEntry>? _books;
  Map<String, ReaderProgress>? _progress;

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

  Future<void> _reload() async {
    final books = await widget.library.list();
    final progress = await widget.progressStore.snapshot();
    if (mounted) {
      setState(() {
        _books = books;
        _progress = progress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: books == null || progress == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    _StatCard(
                      icon: Icons.library_books_outlined,
                      label: '总书数',
                      value: '${books.length}',
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      icon: Icons.auto_stories,
                      label: '在读',
                      value: '${progress.length}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('最近阅读', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (books.isEmpty)
                  const _ComingPane(hint: '导入书籍后这里会展示阅读动态')
                else
                  ..._recent(books, progress),
                const SizedBox(height: 16),
                const _ComingPane(hint: '阅读时长、热力图与成就随 P4 埋点（P4-31）开放'),
              ],
            ),
    );
  }

  List<Widget> _recent(
    List<BookEntry> books,
    Map<String, ReaderProgress> progress,
  ) {
    final read = books
        .where((book) => book.lastReadAt != null)
        .toList()
      ..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
    if (read.isEmpty) {
      return const <Widget>[
        ListTile(dense: true, title: Text('还没有阅读记录，从书架打开一本书吧')),
      ];
    }
    return <Widget>[
      for (final book in read.take(5))
        ListTile(
          dense: true,
          leading: Container(
            width: 34,
            height: 48,
            decoration: BoxDecoration(
              color: HSLColor.fromAHSL(
                1,
                book.coverHue.toDouble(),
                0.42,
                0.38,
              ).toColor(),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              book.title.characters.first.toString(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_progressLabel(book, progress)),
          trailing: Text(
            _relativeTime(book.lastReadAt!),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ];
  }

  String _progressLabel(BookEntry book, Map<String, ReaderProgress> progress) {
    final current = progress[book.id];
    if (current == null) {
      return '尚未开始';
    }
    final total = book.spineCount;
    final chapter = '第 ${current.spineIndex + 1} 章 · 第 ${current.pageIndex + 1} 页';
    return total == null ? chapter : '$chapter / 共 $total 章';
  }

  String _relativeTime(DateTime time) {
    final delta = DateTime.now().difference(time);
    if (delta.inMinutes < 1) return '刚刚';
    if (delta.inHours < 1) return '${delta.inMinutes} 分钟前';
    if (delta.inDays < 1) return '${delta.inHours} 小时前';
    return '${delta.inDays} 天前';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: theme.textTheme.headlineSmall),
                  Text(label, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComingPane extends StatelessWidget {
  const _ComingPane({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.hourglass_empty,
              size: 20,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(hint, style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}
