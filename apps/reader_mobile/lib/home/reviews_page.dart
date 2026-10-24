import 'package:flutter/material.dart';

import '../library/library_store.dart';

/// 书评页：随书架列出可写书评的书籍占位（写入依赖 P4-17 标注存储）。
class ReviewsPage extends StatefulWidget {
  /// 创建页面。
  const ReviewsPage({super.key, required this.library});

  /// 书架存储。
  final LibraryStore library;

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  List<BookEntry>? _books;

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
    if (mounted) {
      setState(() => _books = books);
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    return Scaffold(
      appBar: AppBar(title: const Text('书评')),
      body: books == null
          ? const Center(child: CircularProgressIndicator())
          : books.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.rate_review_outlined, size: 64),
                  SizedBox(height: 12),
                  Text('导入书籍后可以在这里写书评'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.construction,
                          size: 20,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '书评与划线随标注存储（P4-17）开放；当前先列出书架书目',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final book in books)
                  ListTile(
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
                    subtitle: const Text('暂无书评'),
                    enabled: false,
                  ),
              ],
            ),
    );
  }
}
