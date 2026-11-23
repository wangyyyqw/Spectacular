import 'dart:async';

import 'package:flutter/material.dart';

import '../library/library_store.dart';
import '../home/book_cover_image.dart';
import 'rea_micro_controller.dart';
import 'rea_micro_public_reading_page.dart';

/// 将本地书籍关联到阅微云端书籍并开始公开阅读。
///
/// 点击本地书后进入公开阅读页，按出版方选择云端版本；关联只决定
/// 阅微书库中的公开版本，阅读时长、进度和标注会独立同步。
class ReaMicroBookLinkPage extends StatefulWidget {
  /// 创建关联页。
  const ReaMicroBookLinkPage({super.key, required this.controller});

  /// 阅微状态控制器。
  final ReaMicroController controller;

  @override
  State<ReaMicroBookLinkPage> createState() => _ReaMicroBookLinkPageState();
}

class _ReaMicroBookLinkPageState extends State<ReaMicroBookLinkPage> {
  final _filter = TextEditingController();
  List<BookEntry>? _books;
  String? _error;
  String _query = '';
  bool _autoMatching = false;
  String _statusFilter = '未关联';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    unawaited(_loadBooks());
  }

  @override
  void dispose() {
    _filter.dispose();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBooks() async {
    try {
      final books = await widget.controller.listLocalBooks();
      if (!mounted) return;
      setState(() {
        _books = books;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '读取本地书架失败：$error');
    }
  }

  Future<void> _openBook(BookEntry book) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReaMicroPublicReadingPage(
          controller: widget.controller,
          book: book,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _autoMatch() async {
    if (_autoMatching) return;
    setState(() => _autoMatching = true);
    try {
      final count = await widget.controller.autoLinkMatchingBooks();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count == 0 ? '没有找到可自动匹配的书籍' : '已自动关联 $count 本书'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _autoMatching = false);
    }
  }

  List<BookEntry> get _visibleBooks {
    final books = _books ?? const <BookEntry>[];
    final query = _query.trim().toLowerCase();
    return <BookEntry>[
      for (final book in books)
        if ((_statusFilter == '全部' ||
                (_statusFilter == '已关联') ==
                    widget.controller.links.containsKey(book.id)) &&
            (query.isEmpty ||
                book.title.toLowerCase().contains(query) ||
                book.author.toLowerCase().contains(query)))
          book,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    final visible = _visibleBooks;
    return Scaffold(
      appBar: AppBar(
        title: const Text('关联书库'),
        actions: [
          IconButton(
            key: const ValueKey<String>('reamicro-auto-link'),
            tooltip: '按书名和作者自动匹配',
            onPressed: _autoMatching ? null : _autoMatch,
            icon: _autoMatching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: '刷新本地书架',
            onPressed: _loadBooks,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: books == null
            ? _error == null
                  ? const Center(child: CircularProgressIndicator())
                  : _ErrorView(message: _error!, onRetry: _loadBooks)
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      key: const ValueKey<String>('reamicro-link-filter'),
                      controller: _filter,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: '筛选本地书名或作者',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除筛选',
                                onPressed: () {
                                  _filter.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        for (final status in ['未关联', '已关联', '全部'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(status),
                              selected: _statusFilter == status,
                              onSelected: (_) =>
                                  setState(() => _statusFilter = status),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 2, 20, 10),
                    child: Text(
                      '未关联书籍也会同步阅读数据。选择来源或出版版本，'
                      '已有记录会沿用本书身份继续上传。',
                    ),
                  ),
                  Expanded(
                    child: visible.isEmpty
                        ? Center(
                            child: Text(
                              books.isEmpty ? '书架中还没有书籍' : '没有匹配的本地书籍',
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: visible.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1, indent: 56),
                            itemBuilder: (context, index) {
                              final book = visible[index];
                              final link = widget.controller.links[book.id];
                              return ListTile(
                                key: ValueKey<String>(
                                  'reamicro-link-book-${book.id}',
                                ),
                                leading: BookCoverImage(
                                  book: book,
                                  width: 40,
                                  height: 54,
                                ),
                                title: Text(
                                  book.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  link == null
                                      ? (book.author.isEmpty
                                            ? '未关联'
                                            : '${book.author} · 未关联')
                                      : '已关联：${link.name}'
                                            '${link.author.isEmpty ? '' : ' · ${link.author}'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Icon(
                                  link == null
                                      ? Icons.link_off
                                      : Icons.cloud_done_outlined,
                                  color: link == null
                                      ? Theme.of(context).colorScheme.outline
                                      : Theme.of(context).colorScheme.primary,
                                ),
                                onTap: () => _openBook(book),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}
