import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_source_compat.dart';
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
  int _searchVersion = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    final version = ++_searchVersion;
    setState(() {
      _searching = true;
      _error = null;
      _results = null;
    });
    try {
      final results = await widget.controller.search(query);
      if (!mounted || version != _searchVersion) return;
      setState(() {
        _results = results;
        _searching = false;
      });
      unawaited(_enrichResults(version, results));
    } on Object catch (error) {
      if (!mounted || version != _searchVersion) return;
      setState(() => _error = '搜索失败：$error');
    } finally {
      if (mounted && version == _searchVersion && _searching) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _enrichResults(
    int version,
    List<OnlineSourceSearchResult> results,
  ) async {
    if (!results.any((result) => result.books.isNotEmpty)) return;
    try {
      final enriched = await widget.controller.enrichSearchResults(results);
      if (!mounted || version != _searchVersion) return;
      setState(() => _results = enriched);
    } on Object {
      // 详情字段补齐失败时保留搜索结果。
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
      final skipped = widget.controller.lastSkippedChapters;
      final message = skipped > 0
          ? '《$book.name》已加入书架，跳过 $skipped 章'
          : '《$book.name》已加入书架';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey<String>(
                  'online-result-${result.source.id}-${book.bookUrl.hashCode}',
                ),
                onTap: () => _openBook(result.source, book),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                  child: Row(
                    children: <Widget>[
                      _BookThumb(
                        book: book,
                        source: result.source,
                        service: widget.controller.service,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              book.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              book.author.isEmpty ? '佚名' : book.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              onlineSearchTagLine(
                                sourceName: result.source.name,
                                status: book.status.isNotEmpty
                                    ? book.status
                                    : normalizeOnlineStatus(
                                        book.kind,
                                        lastChapter: book.lastChapter,
                                      ),
                                wordCount: book.wordCount,
                                chapterCount: book.chapterCount,
                                updateTime: book.updateTime,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const AppIcon(AppGlyph.chevronRight),
                    ],
                  ),
                ),
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

class _BookThumb extends StatefulWidget {
  const _BookThumb({
    required this.book,
    required this.source,
    required this.service,
  });

  final OnlineBook book;
  final BookSource source;
  final BookSourceService service;

  @override
  State<_BookThumb> createState() => _BookThumbState();
}

class _BookThumbState extends State<_BookThumb> {
  Future<Uint8List?>? _cover;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(_BookThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.coverUrl != widget.book.coverUrl ||
        oldWidget.source.id != widget.source.id) {
      _loadCover();
    }
  }

  void _loadCover() {
    final url = widget.book.coverUrl.trim();
    _cover = url.isEmpty
        ? null
        : widget.service.loadCover(
            widget.source,
            url,
            referer: widget.source.baseUrl,
          );
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
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
        width: 56,
        height: 75,
        child: _cover == null
            ? placeholder
            : FutureBuilder<Uint8List?>(
                future: _cover,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null || bytes.isEmpty) return placeholder;
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => placeholder,
                  );
                },
              ),
      ),
    );
  }
}
