import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_source_compat.dart';
import 'book_source_models.dart';
import 'book_source_service.dart';
import 'online_book_controller.dart';
import 'online_book_detail_page.dart';
import 'online_reading_book.dart';
import 'online_reading_catalog_store.dart';

/// 在线书源搜索页。
class OnlineSearchPage extends StatefulWidget {
  const OnlineSearchPage({super.key, required this.controller, this.onRead});

  final OnlineBookController controller;
  final OnlineBookReadCallback? onRead;

  @override
  State<OnlineSearchPage> createState() => _OnlineSearchPageState();
}

class _OnlineSearchPageState extends State<OnlineSearchPage> {
  final TextEditingController _query = TextEditingController();
  List<OnlineSourceSearchResult>? _results;
  bool _searching = false;
  String? _error;
  int _searchVersion = 0;
  int _recentVersion = 0;
  bool _openingRecent = false;
  List<OnlineReadingCatalog> _recent = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sourcesChanged);
    unawaited(_loadRecent());
  }

  @override
  void didUpdateWidget(OnlineSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_sourcesChanged);
    widget.controller.addListener(_sourcesChanged);
    unawaited(_loadRecent());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sourcesChanged);
    _query.dispose();
    super.dispose();
  }

  void _sourcesChanged() {
    if (widget.controller.initialized) {
      unawaited(_loadRecent(initialize: false));
    }
  }

  Future<void> _loadRecent({bool initialize = true}) async {
    final version = ++_recentVersion;
    if (initialize) await widget.controller.initialize();
    final recent = await widget.controller.catalogs.recent(
      widget.controller.sources,
    );
    if (!mounted || version != _recentVersion) return;
    setState(() => _recent = recent);
  }

  BookSource? _sourceFor(String id) {
    for (final source in widget.controller.sources) {
      if (source.id == id &&
          source.enabled &&
          source.loadMode == BookSourceLoadMode.chapter) {
        return source;
      }
    }
    return null;
  }

  Future<void> _resume(OnlineReadingCatalog catalog, BookSource source) async {
    if (_openingRecent) return;
    final currentSource = _sourceFor(source.id);
    if (currentSource == null) return;
    final onRead = widget.onRead;
    if (onRead == null) return _openBook(currentSource, catalog.book);
    setState(() => _openingRecent = true);
    FocusScope.of(context).unfocus();
    try {
      final load = widget.controller.loadCatalog(currentSource, catalog.book);
      final current = await load.forReading();
      if (!mounted) return;
      final activeSource = _sourceFor(source.id);
      if (activeSource == null ||
          widget.controller.catalogs.requestIdentity(
                activeSource,
                catalog.book,
              ) !=
              widget.controller.catalogs.requestIdentity(
                currentSource,
                catalog.book,
              )) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('来源已更新，请重新打开目录')));
        return;
      }
      await onRead(
        context,
        OnlineReadingBook(
          source: activeSource,
          book: current.book,
          chapters: current.chapters,
          service: widget.controller.service,
          bookshelfId: widget.controller
              .shelfEntryFor(activeSource, current.book)
              ?.id,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法继续阅读：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _openingRecent = false);
        await _loadRecent(initialize: false);
      }
    }
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
    } on Object catch (error) {
      if (!mounted || version != _searchVersion) return;
      setState(() => _error = '搜索失败：$error');
    } finally {
      if (mounted && version == _searchVersion && _searching) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _openBook(BookSource source, OnlineBook book) async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => OnlineBookDetailPage(
          controller: widget.controller,
          source: source,
          book: book,
          onRead: widget.onRead,
        ),
      ),
    );
    if (imported == true && mounted) {
      final skipped = widget.controller.lastSkippedChapters;
      final message = skipped > 0
          ? '《${book.name}》已加入书架，跳过 $skipped 章'
          : '《${book.name}》已加入书架';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
    if (mounted) await _loadRecent(initialize: false);
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
      return _recent.isEmpty ? const _SearchHint() : _buildRecent();
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

  Widget _buildRecent() {
    return ListView(
      key: const ValueKey('online-recent-readings'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Text('最近逐章阅读', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          '从已保存的章节位置继续阅读，未缓存的正文仍需联网。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final catalog in _recent)
          if (_sourceFor(catalog.book.sourceId) case final source?)
            Card(
              child: ListTile(
                key: ValueKey('online-recent-${catalog.book.bookUrl}'),
                title: Text(catalog.book.name),
                subtitle: Text(
                  '${source.name} · ${catalog.chapters.length} 章'
                  '${catalog.book.author.isEmpty ? '' : ' · ${catalog.book.author}'}'
                  '${catalog.isStale ? ' · 目录待更新' : ''}',
                ),
                leading: const Icon(Icons.menu_book_outlined),
                onTap: _openingRecent ? null : () => _resume(catalog, source),
                trailing: IconButton(
                  tooltip: '查看详情与目录',
                  onPressed: _openingRecent
                      ? null
                      : () async {
                          final current = _sourceFor(source.id);
                          if (current != null) {
                            await _openBook(current, catalog.book);
                          }
                        },
                  icon: const Icon(Icons.list),
                ),
              ),
            ),
      ],
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
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    book.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                                if (widget.controller.shelfEntryFor(
                                      result.source,
                                      book,
                                    ) !=
                                    null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    '已在书架',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: book.author.isEmpty
                                              ? '佚名'
                                              : book.author,
                                        ),
                                        if ((book.status.isNotEmpty
                                                ? book.status
                                                : normalizeOnlineStatus(
                                                    book.kind,
                                                    lastChapter:
                                                        book.lastChapter,
                                                  ))
                                            .trim()
                                            .isNotEmpty)
                                          TextSpan(
                                            text:
                                                ' · ${book.status.isNotEmpty ? book.status : normalizeOnlineStatus(book.kind, lastChapter: book.lastChapter)}',
                                          ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    result.source.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              onlineSearchTagLine(
                                sourceName: result.source.name,
                                includePlatform: false,
                                includeStatus: false,
                                status: book.status.isNotEmpty
                                    ? book.status
                                    : normalizeOnlineStatus(
                                        book.kind,
                                        lastChapter: book.lastChapter,
                                      ),
                                wordCount: book.wordCount,
                                chapterCount: book.chapterCount,
                                updateTime: book.updateTime,
                                kind: book.kind,
                                lastChapter: book.lastChapter,
                                intro: book.intro,
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
              '结果按来源分组。打开条目后可以按章阅读，或下载为 EPUB。',
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
