import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_source_models.dart';
import 'book_source_service.dart';
import 'online_book_controller.dart';
import 'online_book_toc_page.dart';
import 'online_chapter_request.dart';
import 'online_reading_book.dart';

typedef OnlineBookReadCallback = Future<void> Function(
  BuildContext context,
  OnlineReadingBook book, {
  int? startChapter,
});

/// 在线书籍详情、目录、阅读与下载。
class OnlineBookDetailPage extends StatefulWidget {
  const OnlineBookDetailPage({
    super.key,
    required this.controller,
    required this.source,
    required this.book,
    this.onRead,
  });

  final OnlineBookController controller;
  final BookSource source;
  final OnlineBook book;
  final OnlineBookReadCallback? onRead;

  @override
  State<OnlineBookDetailPage> createState() => _OnlineBookDetailPageState();
}

class _OnlineBookDetailPageState extends State<OnlineBookDetailPage> {
  OnlineBook? _info;
  List<OnlineChapter>? _chapters;
  OnlineCatalogLoad? _catalogLoad;
  bool _loading = true;
  bool _refreshing = false;
  bool _usingCachedCatalog = false;
  bool _downloading = false;
  bool _opening = false;
  bool _cancelRequested = false;
  String? _error;
  int _completed = 0;
  int _total = 0;
  String _progressMessage = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  BookSource? get _currentSource {
    if (!widget.controller.initialized) return widget.source;
    for (final source in widget.controller.sources) {
      if (source.id == widget.source.id) return source;
    }
    return null;
  }

  bool _sameCatalogSource(BookSource first, BookSource second) =>
      widget.controller.catalogs.requestIdentity(first, widget.book) ==
      widget.controller.catalogs.requestIdentity(second, widget.book);

  Future<void> _load() async {
    if (_refreshing) return;
    setState(() {
      _loading = _chapters == null;
      _refreshing = true;
      _error = null;
    });
    final source = _currentSource ?? widget.source;
    final load = _catalogLoad = widget.controller.loadCatalog(
      source,
      _info ?? widget.book,
    );
    if (_chapters == null) {
      final cached = await load.cached;
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _info = cached.book;
          _chapters = cached.chapters;
          _usingCachedCatalog = true;
          _loading = false;
        });
      }
    }
    try {
      final catalog = await load.refresh;
      if (!mounted) return;
      setState(() {
        _info = catalog.book;
        _chapters = catalog.chapters;
        _usingCachedCatalog = false;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _info ??= widget.book;
        _error = '$error';
        _loading = false;
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    final info = _info ?? widget.book;
    setState(() {
      _downloading = true;
      _cancelRequested = false;
      _completed = 0;
      _total = _chapters?.length ?? 0;
      _progressMessage = '准备下载';
    });
    try {
      await widget.controller.downloadAndImport(
        _currentSource ?? widget.source,
        info,
        onProgress: (completed, total, message) {
          if (!mounted) return;
          setState(() {
            _completed = completed;
            _total = total;
            _progressMessage = message;
          });
        },
        isCancelled: () => _cancelRequested,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on BookSourceException catch (error) {
      if (!mounted) return;
      if (error.code == 'ONLINE_CANCELLED') {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已取消下载')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('下载失败：${error.message}')));
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('下载失败：$error')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  bool get _canRead =>
      widget.onRead != null &&
      _currentSource?.enabled == true &&
      _currentSource?.loadMode == BookSourceLoadMode.chapter &&
      (_chapters?.isNotEmpty ?? false);

  Future<void> _read([OnlineChapter? selectedChapter]) async {
    if (!_canRead || _opening || _downloading) return;
    setState(() => _opening = true);
    final selectedIdentity = selectedChapter == null
        ? null
        : onlineChapterIdentity(selectedChapter);
    OnlineCatalogLoad? usedLoad;
    try {
      final source = _currentSource!;
      final currentLoad = _catalogLoad;
      final load = usedLoad =
          currentLoad != null && _sameCatalogSource(currentLoad.source, source)
          ? currentLoad
          : widget.controller.loadCatalog(source, _info ?? widget.book);
      final catalog = await load.forReading();
      if (!mounted) return;
      final currentSource = _currentSource;
      if (currentSource == null ||
          !currentSource.enabled ||
          currentSource.loadMode != BookSourceLoadMode.chapter ||
          !_sameCatalogSource(currentSource, source)) {
        throw const BookSourceException('来源已更新，请重新打开目录');
      }
      final start = selectedIdentity == null
          ? null
          : catalog.chapters.indexWhere(
              (chapter) => onlineChapterIdentity(chapter) == selectedIdentity,
            );
      if (start == -1) {
        throw const BookSourceException('所选章节已不在最新目录中，请重新选择');
      }
      setState(() {
        _info = catalog.book;
        _chapters = catalog.chapters;
      });
      await widget.onRead!(
        context,
        OnlineReadingBook(
          source: source,
          book: catalog.book,
          chapters: catalog.chapters,
          service: widget.controller.service,
        ),
        startChapter: start,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开阅读页：$error')));
      }
    } finally {
      if (identical(_catalogLoad, usedLoad)) _catalogLoad = null;
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _showToc() async {
    final chapters = _chapters;
    if (chapters == null || _opening || _downloading) return;
    final book = OnlineReadingBook(
      source: _currentSource ?? widget.source,
      book: _info ?? widget.book,
      chapters: chapters,
      service: widget.controller.service,
    );
    final progress = await OnlineReadingProgress(
      widget.controller.library,
      book,
    ).load(book.id);
    if (!mounted) return;
    final selected = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => OnlineBookTocPage(
          bookTitle: book.book.name,
          chapters: chapters,
          currentChapter: progress?.spineIndex,
          selectable: _canRead,
        ),
      ),
    );
    if (selected != null && mounted) await _read(chapters[selected]);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info ?? widget.book;
    return PopScope(
      canPop: !_downloading,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('书籍详情'),
          actions: [
            IconButton(
              key: const ValueKey('online-book-refresh-catalog'),
              tooltip: '刷新目录',
              onPressed: _refreshing || _downloading || _opening ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: _refreshing
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                children: <Widget>[
                  _header(info),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _chapters == null
                              ? '详情加载不完整：$_error'
                              : '目录更新失败，已保留现有目录：$_error',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                  if (info.intro.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 20),
                    Text('简介', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    SelectableText(info.intro),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '目录',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (_chapters != null)
                        Text(
                          '${_chapters!.length} 章'
                          '${_usingCachedCatalog ? ' · 缓存目录' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_chapters == null)
                    TextButton(onPressed: _load, child: const Text('重新读取目录'))
                  else
                    for (final (index, chapter) in _chapters!.take(40).indexed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        onTap: _canRead && !_downloading && !_opening
                            ? () => _read(chapter)
                            : null,
                        title: Text(
                          '${index + 1}. ${chapter.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  if (_chapters != null && _chapters!.length > 40)
                    TextButton.icon(
                      key: const ValueKey('online-book-full-toc'),
                      onPressed: _downloading || _opening ? null : _showToc,
                      icon: const Icon(Icons.list),
                      label: Text('查看全部 ${_chapters!.length} 章'),
                    ),
                ],
              ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: _downloading ? _buildProgress() : _buildDownloadButton(),
          ),
        ),
      ),
    );
  }

  Widget _header(OnlineBook info) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 96,
            height: 130,
            child: _BookCover(
              source: widget.source,
              service: widget.controller.service,
              url: info.coverUrl,
              referer: info.bookUrl,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(info.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(info.author.isEmpty ? '未知作者' : info.author),
              const SizedBox(height: 6),
              Text(
                info.sourceName,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (info.kind.isNotEmpty || info.wordCount.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  <String>[
                    if (info.kind.isNotEmpty) info.kind,
                    if (info.wordCount.isNotEmpty) info.wordCount,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (info.lastChapter.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '最新：${info.lastChapter}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgress() {
    final value = _total > 0 ? (_completed / _total).clamp(0.0, 1.0) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        LinearProgressIndicator(value: value),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _progressMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              key: const ValueKey<String>('online-book-cancel-download'),
              onPressed: () => setState(() => _cancelRequested = true),
              child: const Text('取消'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloadButton() {
    final ready = (_chapters?.isNotEmpty ?? false) && !_opening;
    if (_canRead) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            key: const ValueKey<String>('online-book-read'),
            onPressed: ready ? () => _read() : null,
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('在线阅读'),
          ),
          OutlinedButton.icon(
            key: const ValueKey<String>('online-book-download'),
            onPressed: ready ? _download : null,
            icon: const Icon(Icons.download_outlined),
            label: const Text('下载并加入书架'),
          ),
        ],
      );
    }
    return FilledButton.icon(
      key: const ValueKey<String>('online-book-download'),
      onPressed: ready ? _download : null,
      icon: const AppIcon(AppGlyph.upload),
      label: Text(ready ? '下载并加入书架' : '目录不可用'),
    );
  }
}

class _BookCover extends StatefulWidget {
  const _BookCover({
    required this.source,
    required this.service,
    required this.url,
    required this.referer,
  });

  final BookSource source;
  final BookSourceService service;
  final String url;
  final String referer;

  @override
  State<_BookCover> createState() => _BookCoverState();
}

class _BookCoverState extends State<_BookCover> {
  Future<Uint8List?>? _cover;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(_BookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.referer != widget.referer ||
        oldWidget.source.id != widget.source.id) {
      _loadCover();
    }
  }

  void _loadCover() {
    final url = widget.url.trim();
    _cover = url.isEmpty
        ? null
        : widget.service.loadCover(widget.source, url, referer: widget.referer);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.menu_book_outlined, size: 38),
    );
    final broken = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.broken_image_outlined, size: 34),
    );
    final cover = _cover;
    if (cover == null) return placeholder;
    return FutureBuilder<Uint8List?>(
      future: cover,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) return broken;
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => broken,
        );
      },
    );
  }
}
