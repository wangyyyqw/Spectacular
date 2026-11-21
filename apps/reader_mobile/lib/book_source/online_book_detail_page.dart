import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_source_models.dart';
import 'book_source_discovery.dart';
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
      final source = _currentSource ?? widget.source;
      if (source.loadMode == BookSourceLoadMode.chapter &&
          _chapters?.isNotEmpty == true) {
        await widget.controller.addToShelf(source, info, _chapters!);
        if (!mounted) return;
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已加入书架')));
        return;
      }
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
          bookshelfId: widget.controller
              .shelfEntryFor(currentSource, catalog.book)
              ?.id,
        ),
        startChapter: start,
      );
      if (mounted &&
          widget.controller.shelfEntryFor(currentSource, catalog.book) ==
              null) {
        final add = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('加入书架'),
            content: Text('是否将《${catalog.book.name}》加入书架，保留阅读位置？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('暂不加入'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('加入书架'),
              ),
            ],
          ),
        );
        if (add == true && mounted) {
          await widget.controller.addToShelf(
            currentSource,
            catalog.book,
            catalog.chapters,
          );
          if (mounted) setState(() {});
        }
      }
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
        body: ListView(
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
            if (_loading)
              const LinearProgressIndicator()
            else if (_chapters == null)
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
    final kind = onlineBookPlatformAndTags(info.kind);
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
              fallbackUrl: widget.book.coverUrl,
              referer: info.bookUrl,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                info.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                [
                  info.author.isEmpty ? '未知作者' : info.author,
                  if (info.status.isNotEmpty) info.status,
                  if (info.wordCount.isNotEmpty) info.wordCount,
                  if (kind.platform.isNotEmpty) kind.platform,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (info.lastChapter.isNotEmpty || info.chapterCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (info.chapterCount > 0) '${info.chapterCount}章',
                    if (info.lastChapter.isNotEmpty) '最新：${info.lastChapter}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (kind.tags.isNotEmpty || info.updateTime.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (info.updateTime.isNotEmpty) info.updateTime,
                    if (kind.tags.isNotEmpty) kind.tags,
                  ].join(' · '),
                  maxLines: 1,
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
    final source = _currentSource ?? widget.source;
    final inShelf =
        widget.controller.shelfEntryFor(source, _info ?? widget.book) != null;
    final label = inShelf
        ? '已在书架'
        : source.loadMode == BookSourceLoadMode.chapter
        ? '加入书架'
        : '下载并加入书架';
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
            onPressed: ready && !inShelf ? _download : null,
            icon: Icon(inShelf ? Icons.check : Icons.library_add_outlined),
            label: Text(label),
          ),
        ],
      );
    }
    return FilledButton.icon(
      key: const ValueKey<String>('online-book-download'),
      onPressed: ready && !inShelf ? _download : null,
      icon: const AppIcon(AppGlyph.upload),
      label: Text(ready ? label : '目录不可用'),
    );
  }
}

class _BookCover extends StatefulWidget {
  const _BookCover({
    required this.source,
    required this.service,
    required this.url,
    required this.referer,
    this.fallbackUrl = '',
  });

  final BookSource source;
  final BookSourceService service;
  final String url;
  final String referer;
  final String fallbackUrl;

  @override
  State<_BookCover> createState() => _BookCoverState();
}

class _BookCoverState extends State<_BookCover> {
  Future<Uint8List?>? _cover;
  Uint8List? _lastCover;

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
    final source = widget.source;
    final urls = {widget.url.trim(), widget.fallbackUrl.trim()}..remove('');
    final referer = widget.referer;
    _cover = () async {
      for (final url in urls) {
        final bytes = await widget.service.loadCover(
          source,
          url,
          referer: referer,
        );
        if (bytes != null && bytes.isNotEmpty) {
          _lastCover = bytes;
          return bytes;
        }
      }
      return _lastCover;
    }();
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
        final bytes = snapshot.data ?? _lastCover;
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
