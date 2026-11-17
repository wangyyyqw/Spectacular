import 'dart:async';

import 'package:flutter/material.dart';

import '../library/library_store.dart';
import 'rea_micro_controller.dart';
import 'rea_micro_models.dart';

/// 将本地书籍匹配到阅微云端书籍。
///
/// 只有已关联的本地书籍才会提交阅读时长，避免同名书或不同版本写错账号数据。
class ReaMicroBookLinkPage extends StatefulWidget {
  /// 创建匹配页。
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

  @override
  void initState() {
    super.initState();
    unawaited(_loadBooks());
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
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
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _BookLinkSheet(controller: widget.controller, book: book),
    );
    if (changed == true && mounted) {
      setState(() {});
    }
  }

  List<BookEntry> get _visibleBooks {
    final books = _books ?? const <BookEntry>[];
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return books;
    return <BookEntry>[
      for (final book in books)
        if (book.title.toLowerCase().contains(query) ||
            book.author.toLowerCase().contains(query))
          book,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    final visible = _visibleBooks;
    return Scaffold(
      appBar: AppBar(
        title: const Text('匹配阅微书籍'),
        actions: [
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
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 2, 20, 10),
                    child: Text(
                      '点击书籍后搜索阅微云端条目。关联关系只保存在本机，'
                      '未关联的书籍不会上报阅读时长。',
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
                                leading: const Icon(Icons.menu_book_outlined),
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

class _BookLinkSheet extends StatefulWidget {
  const _BookLinkSheet({required this.controller, required this.book});

  final ReaMicroController controller;
  final BookEntry book;

  @override
  State<_BookLinkSheet> createState() => _BookLinkSheetState();
}

class _BookLinkSheetState extends State<_BookLinkSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.book.title,
  );
  late final TextEditingController _author = TextEditingController(
    text: widget.book.author,
  );
  ReaMicroCloudBook? _result;
  String? _error;
  bool _searching = false;
  bool _linking = false;
  bool _changed = false;

  ReaMicroBookLink? get _currentLink => widget.controller.links[widget.book.id];

  @override
  void dispose() {
    _name.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_searching || _linking) return;
    setState(() {
      _searching = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.controller.searchCloudBook(
        name: _name.text,
        author: _author.text,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        if (result == null) _error = '没有找到匹配的阅微云端书籍';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _linkBook() async {
    final result = _result;
    if (result == null || _linking) return;
    setState(() {
      _linking = true;
      _error = null;
    });
    try {
      await widget.controller.linkBook(widget.book.id, result);
      if (!mounted) return;
      setState(() {
        _changed = true;
        _linking = false;
      });
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _linking = false;
        _error = '关联失败：$error';
      });
    }
  }

  Future<void> _unlink() async {
    if (_linking) return;
    setState(() {
      _linking = true;
      _error = null;
    });
    try {
      await widget.controller.unlinkBook(widget.book.id);
      if (!mounted) return;
      setState(() {
        _changed = true;
        _linking = false;
      });
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _linking = false;
        _error = '解除关联失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _currentLink;
    final result = _result;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('匹配阅微书籍', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '本地《${widget.book.title}》',
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (link != null) ...[
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_done_outlined),
                  title: Text(link.name),
                  subtitle: Text(
                    '${link.author.isEmpty ? '未知作者' : link.author}'
                    ' · 云端 ID ${link.cloudBookId}',
                  ),
                  trailing: TextButton(
                    key: const ValueKey<String>('reamicro-unlink-book'),
                    onPressed: _linking ? null : _unlink,
                    child: const Text('解除关联'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey<String>('reamicro-cloud-name'),
              controller: _name,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => unawaited(_search()),
              decoration: const InputDecoration(
                labelText: '阅微书名',
                prefixIcon: Icon(Icons.book_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('reamicro-cloud-author'),
              controller: _author,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => unawaited(_search()),
              decoration: const InputDecoration(
                labelText: '作者（可选）',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey<String>('reamicro-cloud-search'),
              onPressed: _searching || _linking ? null : _search,
              icon: _searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_searching ? '正在搜索…' : '搜索阅微书籍'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey<String>('reamicro-cloud-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        result.author.isEmpty ? '未知作者' : result.author,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (result.publishers.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          result.publishers.join(' / '),
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '云端 ID：${result.cloudBookId}',
                        style: theme.textTheme.labelSmall,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          key: const ValueKey<String>('reamicro-link-book'),
                          onPressed: _linking ? null : _linkBook,
                          icon: const Icon(Icons.link),
                          label: Text(_linking ? '关联中…' : '关联这本书'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_changed),
              child: const Text('关闭'),
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
