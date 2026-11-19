import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_source_models.dart';
import 'book_source_service.dart';
import 'online_book_controller.dart';
import 'online_book_detail_page.dart';

/// 在线书源搜索页。
class OnlineSearchPage extends StatefulWidget {
  const OnlineSearchPage({super.key, required this.controller});

  final OnlineBookController controller;

  @override
  State<OnlineSearchPage> createState() => _OnlineSearchPageState();
}

class _OnlineSearchPageState extends State<OnlineSearchPage> {
  final TextEditingController _query = TextEditingController();
  List<OnlineSourceSearchResult>? _results;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _results = null;
    });
    try {
      final results = await widget.controller.search(query);
      if (!mounted) return;
      setState(() => _results = results);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '搜索失败：$error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openBook(BookSource source, OnlineBook book) async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => OnlineBookDetailPage(
          controller: widget.controller,
          source: source,
          book: book,
        ),
      ),
    );
    if (imported == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('《$book.name》已加入书架')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(title: const Text('在线找书')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('online-search-query'),
                    controller: _query,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: '输入书名或作者',
                      prefixIcon: const AppIcon(AppGlyph.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  key: const ValueKey<String>('online-search-submit'),
                  onPressed: _searching ? null : _search,
                  child: Text(_searching ? '搜索中' : '搜索'),
                ),
              ],
            ),
          ),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildBody(results)),
        ],
      ),
    );
  }

  Widget _buildBody(List<OnlineSourceSearchResult>? results) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (results == null) {
      return const _SearchHint();
    }
    if (results.isEmpty) {
      return const Center(child: Text('没有已启用的书源'));
    }
    final total = results.fold<int>(
      0,
      (sum, result) => sum + result.books.length,
    );
    if (total == 0) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const AppIcon(AppGlyph.searchOff, size: 42),
          const SizedBox(height: 12),
          const Center(child: Text('没有找到匹配结果')),
          const SizedBox(height: 18),
          for (final result in results)
            if (result.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${result.source.name}：${result.error}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _search,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: <Widget>[
          Text(
            '共 ${results.where((result) => result.books.isNotEmpty).length} 个来源、'
            '$total 条结果',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          for (final result in results)
            if (result.books.isNotEmpty) _buildGroup(result),
          for (final result in results)
            if (result.error.isNotEmpty && result.books.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '${result.source.name}：${result.error}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildGroup(OnlineSourceSearchResult result) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  result.source.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                '${result.books.length} 条',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final book in result.books)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                key: ValueKey<String>(
                  'online-result-${result.source.id}-${book.bookUrl.hashCode}',
                ),
                contentPadding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                leading: _BookThumb(book: book),
                title: Text(
                  book.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  <String>[
                    if (book.author.isNotEmpty) book.author,
                    if (book.kind.isNotEmpty) book.kind,
                    if (book.wordCount.isNotEmpty) book.wordCount,
                    if (book.lastChapter.isNotEmpty) book.lastChapter,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const AppIcon(AppGlyph.chevronRight),
                onTap: () => _openBook(result.source, book),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const AppIcon(AppGlyph.search, size: 44),
            const SizedBox(height: 14),
            Text('在全部已启用书源中搜索', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            const Text(
              '结果按来源分组。打开条目后可以查看目录并下载为 EPUB。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookThumb extends StatelessWidget {
  const _BookThumb({required this.book});

  final OnlineBook book;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          book.name.isEmpty ? '书' : book.name.characters.first,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        width: 46,
        height: 62,
        child: book.coverUrl.isEmpty
            ? placeholder
            : Image.network(
                book.coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
  }
}
