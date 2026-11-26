import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

import 'book_source_models.dart';
import 'book_source_discovery.dart';
import 'book_source_service.dart';
import 'online_book_controller.dart';
import 'online_chapter_cache_icon.dart';
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
  bool _closed = false;
  bool _showIntroduction = true;
  bool _catalogReversed = false;
  final Set<String> _collapsedVolumes = {};
  List<OnlineChapter>? _groupedChapters;
  List<_CatalogVolume> _volumes = [];
  int _downloadSequence = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _closed = true;
    _cancelRequested = true;
    super.dispose();
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
    load.info?.then<void>((info) {
      if (mounted && identical(_catalogLoad, load)) {
        setState(() => _info = info);
      }
    }, onError: (Object error, StackTrace stack) {}).ignore();
    try {
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
      final catalog = await load.refresh.timeout(
        const Duration(seconds: 50),
        onTimeout: () => throw const BookSourceException('详情或目录加载超时，请重试'),
      );
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
    final sequence = ++_downloadSequence;
    bool cancelled() =>
        _closed || _cancelRequested || sequence != _downloadSequence;
    final info = _info ?? widget.book;
    setState(() {
      _downloading = true;
      _cancelRequested = false;
    });
    try {
      final source = _currentSource ?? widget.source;
      if (source.loadMode == BookSourceLoadMode.chapter &&
          _chapters?.isNotEmpty == true) {
        await waitOnlineOperation(
          widget.controller.addToShelf(
            source,
            info,
            _chapters!,
            isCancelled: cancelled,
          ),
          cancelled,
        );
        if (!mounted || cancelled()) return;
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已加入书架')));
        return;
      }
      await waitOnlineOperation(
        widget.controller.downloadAndImport(
          source,
          info,
          isCancelled: cancelled,
        ),
        cancelled,
      );
      if (!mounted || cancelled()) return;
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
      final catalog = await waitOnlineOperation(
        load.forReading(),
        () => _closed,
      );
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
        final add = await showReaderDialog<bool>(
          context: context,
          builder: (context) => ReaderFrostedAlertDialog(
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
            isCancelled: () => _closed,
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

  @override
  Widget build(BuildContext context) {
    final info = _info ?? widget.book;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _closed = true;
          _cancelRequested = true;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('书籍详情'),
          leading: BackButton(
            onPressed: () {
              _cancelRequested = true;
              Navigator.of(context).maybePop();
            },
          ),
          actions: [
            IconButton(
              key: const ValueKey('online-book-refresh-catalog'),
              tooltip: '刷新目录',
              onPressed: _refreshing || _downloading || _opening ? null : _load,
              icon: const AppIcon(AppGlyph.refresh),
            ),
          ],
          bottom: _refreshing
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            children: [
              _header(info),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _chapters == null
                        ? '详情加载不完整：$_error'
                        : '目录更新失败，已保留现有目录：$_error',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Expanded(
                key: const ValueKey('online-book-content-container'),
                child: _showIntroduction
                    ? SingleChildScrollView(
                        key: const PageStorageKey('online-book-introduction'),
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: SelectableText(
                            info.intro.isEmpty ? '暂无简介' : info.intro,
                          ),
                        ),
                      )
                    : _catalogContent(),
              ),
            ],
          ),
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

  Widget _catalogContent() {
    final chapters = _chapters;
    if (chapters == null) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: TextButton(onPressed: _load, child: const Text('重新读取目录')),
            );
    }
    final volumes = _catalogVolumes(chapters);
    final namedVolumes = volumes.where((volume) => volume.title.isNotEmpty);
    final hasExpandedVolume = namedVolumes.any(
      (volume) => !_collapsedVolumes.contains(volume.id),
    );
    final rows = <({int? chapter, _CatalogVolume? volume})>[];
    for (final volume in _catalogReversed ? volumes.reversed : volumes) {
      if (volume.title.isNotEmpty) {
        rows.add((chapter: null, volume: volume));
        if (_collapsedVolumes.contains(volume.id)) continue;
      }
      for (var position = 0; position < volume.end - volume.start; position++) {
        final chapterIndex = _catalogReversed
            ? volume.end - position - 1
            : volume.start + position;
        final firstChapterIndex = _catalogReversed
            ? volume.end - 1
            : volume.start;
        if (chapterIndex == firstChapterIndex &&
            chapters[chapterIndex].title.trim() == volume.title.trim()) {
          continue;
        }
        rows.add((chapter: chapterIndex, volume: null));
      }
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${chapters.length} 章${_usingCachedCatalog ? ' · 缓存目录' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              key: const ValueKey('online-book-toggle-volumes'),
              style: IconButton.styleFrom(
                fixedSize: const Size(48, 48),
                visualDensity: VisualDensity.standard,
              ),
              tooltip: hasExpandedVolume ? '折叠全部' : '展开全部',
              onPressed: namedVolumes.isEmpty
                  ? null
                  : () => setState(() {
                      for (final volume in namedVolumes) {
                        if (hasExpandedVolume) {
                          _collapsedVolumes.add(volume.id);
                        } else {
                          _collapsedVolumes.remove(volume.id);
                        }
                      }
                    }),
              icon: _catalogChevron(hasExpandedVolume),
            ),
            IconButton(
              key: const ValueKey('online-book-order'),
              style: IconButton.styleFrom(
                fixedSize: const Size(48, 48),
                visualDensity: VisualDensity.standard,
              ),
              tooltip: _catalogReversed ? '正序排列' : '倒序排列',
              isSelected: _catalogReversed,
              onPressed: () =>
                  setState(() => _catalogReversed = !_catalogReversed),
              icon: _catalogSort(false),
              selectedIcon: _catalogSort(true),
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            key: const PageStorageKey('online-book-directory'),
            itemCount: rows.length,
            itemBuilder: (context, position) {
              final row = rows[position];
              final volume = row.volume;
              if (volume != null) {
                final expanded = !_collapsedVolumes.contains(volume.id);
                return Semantics(
                  expanded: expanded,
                  child: ListTile(
                    key: ValueKey('online-book-volume-${volume.start}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    minTileHeight: 36,
                    minVerticalPadding: 2,
                    visualDensity: VisualDensity.compact,
                    onTap: () => setState(() {
                      if (expanded) {
                        _collapsedVolumes.add(volume.id);
                      } else {
                        _collapsedVolumes.remove(volume.id);
                      }
                    }),
                    title: Text(
                      volume.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${volume.end - volume.start}章',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        SizedBox(
                          key: ValueKey(
                            'online-book-volume-arrow-${volume.start}',
                          ),
                          width: 48,
                          height: 32,
                          child: Center(child: _catalogChevron(expanded)),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final index = row.chapter!;
              final chapter = chapters[index];
              return ListTile(
                key: ValueKey('online-book-chapter-$index'),
                contentPadding: EdgeInsets.only(
                  left: chapter.volume.trim().isEmpty ? 0 : 12,
                ),
                dense: true,
                minTileHeight: 36,
                minVerticalPadding: 2,
                visualDensity: VisualDensity.compact,
                onTap: _canRead && !_downloading && !_opening
                    ? () => _read(chapter)
                    : null,
                trailing: OnlineChapterCacheIcon(
                  cached: widget.controller.service.isChapterCached(
                    _currentSource!,
                    chapter,
                    (_info ?? widget.book).bookUrl,
                    nextChapter: index + 1 < chapters.length
                        ? chapters[index + 1]
                        : null,
                  ),
                ),
                title: Text(
                  '${index + 1}. ${chapter.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _catalogChevron(bool expanded) => SizedBox(
    width: 20,
    height: 20,
    child: Transform.translate(
      // 两个箭头的路径中心分别在 11.75 和 12.25，统一到画布中心。
      offset: Offset(0, expanded ? 20 / 96 : -20 / 96),
      child: AppIcon(
        expanded ? AppGlyph.chevronUp : AppGlyph.chevronDown,
        size: 20,
      ),
    ),
  );

  Widget _catalogSort(bool reversed) => SizedBox(
    width: 20,
    height: 20,
    child: RotatedBox(
      quarterTurns: reversed ? 2 : 0,
      child: Transform.translate(
        // 排序线条的视觉中心是 9.25，移动到 24 单位画布的中心。
        offset: const Offset(2.75 * 20 / 24, 0),
        child: const AppIcon(AppGlyph.sort, size: 20),
      ),
    ),
  );

  List<_CatalogVolume> _catalogVolumes(List<OnlineChapter> chapters) {
    if (identical(_groupedChapters, chapters)) return _volumes;
    _groupedChapters = chapters;
    _volumes = [];
    for (var start = 0; start < chapters.length;) {
      final title = chapters[start].volume.trim();
      var end = start + 1;
      while (end < chapters.length && chapters[end].volume.trim() == title) {
        end++;
      }
      _volumes.add(
        _CatalogVolume(
          id: '$title:${onlineChapterIdentity(chapters[start])}',
          title: title,
          start: start,
          end: end,
        ),
      );
      start = end;
    }
    _collapsedVolumes.retainAll(_volumes.map((volume) => volume.id));
    return _volumes;
  }

  Widget _contentTabs() {
    final theme = Theme.of(context);
    if (theme.useMaterial3) {
      return SegmentedButton<bool>(
        key: const ValueKey('online-book-content-tabs'),
        segments: const [
          ButtonSegment(
            value: true,
            label: Text('简介', key: ValueKey('online-book-intro-tab')),
          ),
          ButtonSegment(
            value: false,
            label: Text('目录', key: ValueKey('online-book-toc-tab')),
          ),
        ],
        selected: {_showIntroduction},
        showSelectedIcon: false,
        onSelectionChanged: (values) =>
            setState(() => _showIntroduction = values.single),
      );
    }
    return Container(
      key: const ValueKey('online-book-content-tabs'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: .09),
        borderRadius: ReaderUiStyle.buttonRadiusOf(theme),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (intro, label) in [(true, '简介'), (false, '目录')])
            Semantics(
              selected: _showIntroduction == intro,
              child: TextButton(
                key: ValueKey(
                  intro ? 'online-book-intro-tab' : 'online-book-toc-tab',
                ),
                onPressed: () => setState(() => _showIntroduction = intro),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 26),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: theme.colorScheme.onSurface.withValues(
                    alpha: _showIntroduction == intro ? 1 : .6,
                  ),
                  backgroundColor: _showIntroduction == intro
                      ? theme.colorScheme.surface
                      : Colors.transparent,
                  elevation: _showIntroduction == intro ? 1 : 0,
                  shadowColor: Colors.black.withValues(alpha: .05),
                  shape: RoundedRectangleBorder(
                    borderRadius: ReaderUiStyle.buttonRadiusOf(theme),
                  ),
                  textStyle: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: _showIntroduction == intro
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
                child: Text(label),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(OnlineBook info) {
    final kind = onlineBookPlatformAndTags(info.kind);
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  key: const ValueKey('online-book-cover'),
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
                    const SizedBox(height: 4),
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
                    if (info.lastChapter.isNotEmpty ||
                        info.chapterCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (info.chapterCount > 0) '${info.chapterCount}章',
                          if (info.lastChapter.isNotEmpty)
                            '最新：${info.lastChapter}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (kind.tags.isNotEmpty || info.updateTime.isNotEmpty) ...[
                      const SizedBox(height: 4),
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
                    // 为屏幕居中的切换按钮预留底部高度，大字模式随文字一起增高。
                    SizedBox(
                      height:
                          (Theme.of(context).useMaterial3 ? 48 : 34) +
                          MediaQuery.textScalerOf(context).scale(14) -
                          14,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _contentTabs(),
      ],
    );
  }

  Widget _buildProgress() {
    return TextButton(
      key: const ValueKey<String>('online-book-cancel-download'),
      onPressed: () => setState(() => _cancelRequested = true),
      child: const Text('取消下载'),
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

class _CatalogVolume {
  const _CatalogVolume({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
  });

  final String id;
  final String title;
  final int start;
  final int end;
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
