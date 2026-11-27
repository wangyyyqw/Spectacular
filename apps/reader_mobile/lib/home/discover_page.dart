import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import '../book_source/book_source_discovery.dart';
import '../book_source/book_source_compat.dart';
import '../book_source/book_source_models.dart';
import '../book_source/online_book_controller.dart';
import '../book_source/online_book_detail_page.dart';
import '../book_source/online_source_page.dart';
import 'book_collection_layout.dart';
import 'discover_choice_dialog.dart';
import 'discover_filter_dialog.dart';
import 'book_search_bar.dart';
import 'desktop_layout.dart';
import '../diagnostics/reader_log.dart';

typedef _SearchGroup = ({BookSource source, List<OnlineBook> books});

/// 发现页沿用书架的搜索、按钮栏和图书列表布局。
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({
    super.key,
    required this.controller,
    this.onRead,
    this.active = true,
  });

  final OnlineBookController controller;
  final OnlineBookReadCallback? onRead;
  final bool active;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  static const int _gridBatchSize = 21;
  static const int _maxSourcePagesPerBatch = 4;

  final _query = TextEditingController();
  final _scroll = ScrollController();
  final LinkedHashMap<String, _DiscoverPageSnapshot> _cache =
      LinkedHashMap<String, _DiscoverPageSnapshot>();
  BookSource? _source;
  List<BookDiscoverCategory> _categories = const [];
  BookDiscoverCategory? _category;
  List<({BookSource source, OnlineBook book})> _books = const [];
  List<_SearchGroup> _searchGroups = const [];
  final _expandedSources = <String>{};
  bool _loading = false;
  bool _searchMode = false;
  bool _hasMore = true;
  bool _grid = false;
  int _page = 0;
  int _version = 0;
  String? _error;
  int? _sourceSettingsRevision;
  final Map<String, Map<String, String>> _filterSelections = {};
  BookDiscoverCategory? _filteredCategory;

  List<BookSource> get _sources => widget.controller.sources
      .where(
        (source) =>
            source.enabled &&
            source.enabledExplore &&
            source.exploreUrl.trim().isNotEmpty,
      )
      .toList();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sourcesChanged);
    _scroll.addListener(_loadNearBottom);
    if (widget.active) {
      unawaited(_initialize());
    }
  }

  @override
  void didUpdateWidget(DiscoverPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sourcesChanged);
      widget.controller.addListener(_sourcesChanged);
      _source = null;
    }
    if (widget.active &&
        (!oldWidget.active || oldWidget.controller != widget.controller)) {
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    await widget.controller.initialize();
    if (!mounted) return;
    _sourcesChanged();
  }

  void _sourcesChanged() {
    if (!mounted || !widget.active) return;
    final sources = _sources;
    final previous = _source;
    final current = sources
        .where(
          (item) =>
              item.id ==
              (previous?.id ?? widget.controller.selectedDiscoverSourceId),
        )
        .firstOrNull;
    final settingsRevision = current == null
        ? null
        : widget.controller.cookieStore.settingsRevision(current);
    if (current != null &&
        identical(current, previous) &&
        settingsRevision == _sourceSettingsRevision) {
      setState(() {});
      return;
    }
    if (previous != null && current != null) _cache.clear();
    if (sources.isEmpty) {
      if (_searchMode && previous == null) {
        setState(() {});
        return;
      }
      ++_version;
      setState(() {
        _source = null;
        _sourceSettingsRevision = null;
        _category = null;
        _categories = const [];
        _books = const [];
        _searchMode = false;
        _searchGroups = const [];
        _loading = false;
        _error = null;
      });
    } else {
      unawaited(_selectSource(current ?? sources.first));
    }
  }

  Future<void> _selectSource(
    BookSource source, {
    BookDiscoverCategory? category,
  }) async {
    final version = ++_version;
    setState(() {
      _source = source;
      _sourceSettingsRevision = widget.controller.cookieStore.settingsRevision(
        source,
      );
      _categories = const [];
      _category = null;
      _books = const [];
      _loading = true;
      _error = null;
      _searchMode = false;
      _searchGroups = const [];
      _filteredCategory = null;
      _query.clear();
    });
    try {
      await widget.controller.selectDiscoverSource(source.id);
      final categories = await widget.controller.service.loadDiscoverCategories(
        source,
      );
      if (!mounted || version != _version) return;
      setState(() {
        _categories = categories;
        _category = category ?? categories.firstOrNull;
        _filteredCategory = category;
        _loading = false;
      });
      await _load(reset: true);
    } on Object catch (error) {
      recordAppError('book_source_discover_categories_failed', error);
      if (!mounted || version != _version) return;
      setState(() {
        _loading = false;
        _error = '无法读取发现分类：$error';
      });
    }
  }

  void _loadNearBottom() {
    if (widget.active &&
        _scroll.position.extentAfter < 400 &&
        !_searchMode &&
        _hasMore &&
        !_loading &&
        _error == null) {
      unawaited(_load());
    }
  }

  void _toggleGrid() {
    final grid = !_grid;
    setState(() => _grid = grid);
    if (grid &&
        !_loading &&
        _hasMore &&
        _books.isNotEmpty &&
        _books.length % _gridBatchSize != 0) {
      unawaited(_load());
    }
  }

  Future<void> _load({bool reset = false, bool force = false}) async {
    final source = _source;
    final category = _category;
    if (source == null || category == null || (!reset && _loading)) return;
    final version = ++_version;
    final cacheKey = _cacheKey(source, category);
    if (reset && !force) {
      final cached = _cachedPage(cacheKey);
      if (cached != null) {
        setState(() {
          _books = List<({BookSource source, OnlineBook book})>.of(
            cached.books,
          );
          _page = cached.page;
          _hasMore = cached.hasMore;
          _loading = false;
          _error = null;
        });
        if (_scroll.hasClients) _scroll.jumpTo(0);
        return;
      }
    }

    final nextBooks = reset
        ? <({BookSource source, OnlineBook book})>[]
        : List<({BookSource source, OnlineBook book})>.of(_books);
    final seen = nextBooks
        .map((item) => '${item.source.id}|${item.book.bookUrl}')
        .toSet();
    final targetCount = _grid
        ? ((nextBooks.length ~/ _gridBatchSize) + 1) * _gridBatchSize
        : nextBooks.length + 1;
    var nextPage = reset ? 1 : _page + 1;
    var sourceHasMore = true;
    var addedAny = false;
    var stalled = false;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _books = const [];
        _hasMore = true;
        _page = 0;
      }
    });
    if (reset && _scroll.hasClients) _scroll.jumpTo(0);
    try {
      var requests = 0;
      while (requests < _maxSourcePagesPerBatch) {
        final books = await widget.controller.service.discover(
          source,
          category,
          page: nextPage,
        );
        if (!mounted || version != _version) return;
        requests += 1;
        sourceHasMore = books.isNotEmpty;
        var pageAdded = 0;
        for (final book in books) {
          if (seen.add('${source.id}|${book.bookUrl}')) {
            nextBooks.add((source: source, book: book));
            pageAdded += 1;
          }
        }
        if (pageAdded == 0) {
          stalled = true;
          break;
        }
        addedAny = true;
        if (!_grid ||
            nextBooks.length >= targetCount ||
            !sourceHasMore ||
            requests >= _maxSourcePagesPerBatch) {
          break;
        }
        nextPage += 1;
      }
      if (!mounted || version != _version) return;
      final hasMore = sourceHasMore && addedAny && !stalled;
      setState(() {
        _books = List<({BookSource source, OnlineBook book})>.unmodifiable(
          nextBooks,
        );
        _page = nextPage;
        _hasMore = hasMore;
      });
      if (addedAny) {
        _storePage(cacheKey, _books, nextPage, hasMore);
      }
    } on Object catch (error) {
      recordAppEvent(
        'book_source_discover_failed',
        fields: {
          'error': error,
          'page': nextPage,
          'http_status': error is BookSourceException
              ? error.statusCode ?? 0
              : 0,
          'code_enum': error is BookSourceException ? error.code ?? '' : '',
        },
      );
      if (mounted && version == _version) {
        setState(() {
          _books = List<({BookSource source, OnlineBook book})>.unmodifiable(
            nextBooks,
          );
          _page = nextPage;
          _hasMore = sourceHasMore && addedAny && !stalled;
          _error = '加载失败：$error';
        });
      }
    } finally {
      if (mounted && version == _version) setState(() => _loading = false);
    }
  }

  String _cacheKey(BookSource source, BookDiscoverCategory category) =>
      '${source.id}|${category.title}|${category.url}';

  _DiscoverPageSnapshot? _cachedPage(String key) {
    final cached = _cache.remove(key);
    if (cached != null) _cache[key] = cached;
    return cached;
  }

  void _storePage(
    String key,
    List<({BookSource source, OnlineBook book})> books,
    int page,
    bool hasMore,
  ) {
    _cache.remove(key);
    _cache[key] = _DiscoverPageSnapshot(
      books: List<({BookSource source, OnlineBook book})>.unmodifiable(books),
      page: page,
      hasMore: hasMore,
    );
    while (_cache.length > 16) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) {
      ++_version;
      setState(() {
        _searchMode = false;
        _searchGroups = const [];
        _expandedSources.clear();
        _loading = false;
        _error = null;
      });
      final source = _source;
      if (source != null && _category == null) {
        await _selectSource(source);
      } else {
        await _load(reset: true);
      }
      return;
    }
    FocusScope.of(context).unfocus();
    final version = ++_version;
    setState(() {
      _searchMode = true;
      _loading = true;
      _error = null;
      _searchGroups = const [];
      _expandedSources.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    try {
      final results = await widget.controller.search(query);
      if (!mounted || version != _version) return;
      setState(() {
        _searchGroups = rankOnlineSearchResults(query, [
          for (final result in results)
            if (result.books.isNotEmpty)
              (
                source: result.source,
                books: rankOnlineSearchResults(
                  query,
                  result.books,
                  (book) => book,
                ),
              ),
        ], (group) => group.books.first);
        final failures = results.where((result) => result.error.isNotEmpty);
        _error = _searchGroups.isEmpty && failures.isNotEmpty
            ? failures
                  .map((result) => '${result.source.name}：${result.error}')
                  .join('\n')
            : null;
      });
    } on Object catch (error) {
      if (mounted && version == _version) {
        setState(() => _error = '搜索失败：$error');
      }
    } finally {
      if (mounted && version == _version) setState(() => _loading = false);
    }
  }

  Future<void> _open(BookSource source, OnlineBook book) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OnlineBookDetailPage(
          controller: widget.controller,
          source: source,
          book: book,
          onRead: widget.onRead,
        ),
      ),
    );
  }

  Future<void> _manageSources() async {
    await showReaderDrawer<void>(
      context: context,
      builder: (_) => OnlineSourcePage(
        controller: widget.controller,
        onRead: widget.onRead,
      ),
    );
    if (mounted) _sourcesChanged();
  }

  Future<BookDiscoverFilter?> _filterFor(BookSource source) async {
    final categories = source.id == _source?.id && _categories.isNotEmpty
        ? _categories
        : await widget.controller.service.loadDiscoverCategories(source);
    return parseDiscoverFilter(
      source.exploreUrl,
      categories,
      kinds: [
        for (final item in _books)
          if (item.source.id == source.id) item.book.kind,
      ],
    );
  }

  Future<void> _openFilter() async {
    final result = await showReaderDialog<DiscoverFilterResult>(
      context: context,
      builder: (_) => DiscoverFilterDialog(
        sources: _sources,
        source: _source,
        filterFor: _filterFor,
        selections: _filterSelections,
      ),
    );
    if (!mounted || result == null) return;
    _filterSelections[result.source.id] = result.selection;
    if (_source?.id != result.source.id) {
      await _selectSource(result.source, category: result.category);
      return;
    }
    if (result.category != null) {
      setState(() {
        _filteredCategory = result.category;
        _category = result.category;
        _searchMode = false;
        _query.clear();
      });
      await _load(reset: true);
    }
  }

  Future<void> _pickCategory() async {
    final category = await showReaderDialog<BookDiscoverCategory>(
      context: context,
      builder: (context) => DiscoverChoiceDialog<BookDiscoverCategory>(
        title: '分类分组',
        options: [?_filteredCategory, ..._categories],
        labelFor: (category) => category.title,
        selected: _category,
      ),
    );
    if (category != null && mounted) {
      setState(() {
        _category = category;
        _searchMode = false;
      });
      await _load(reset: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sourcesChanged);
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: usesDesktopLayout(context)
              ? desktopBookPageMaxWidth
              : double.infinity,
        ),
        child: LayoutBuilder(builder: _buildPage),
      ),
    );
  }

  Widget _buildPage(BuildContext context, BoxConstraints bounds) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: bookSearchBar(
        context,
        section: '发现',
        keyPrefix: 'discover',
        controller: _query,
        availableWidth: bounds.maxWidth,
        searchLabel: '在线搜索',
        onSearch: _search,
        onSubmitted: (_) => _search(),
        clearButton: !_searchMode
            ? null
            : IconButton(
                tooltip: '返回发现',
                icon: const AppIcon(AppGlyph.close),
                onPressed: () {
                  _query.clear();
                  unawaited(_search());
                },
              ),
        actionKey: const ValueKey('discover-source-menu'),
        actionLabel: '筛选管理',
        desktopAction: '筛选管理',
        actionIcon: const AppIcon(AppGlyph.more),
        onAction: _openFilter,
      ),
      body: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (_searchMode) {
                final count = _searchGroups.fold<int>(
                  0,
                  (sum, group) => sum + group.books.length,
                );
                return Container(
                  key: const ValueKey('discover-category-toolbar'),
                  alignment: AlignmentDirectional.centerStart,
                  constraints: const BoxConstraints(
                    minHeight: kMinInteractiveDimension,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _loading
                        ? '搜索结果'
                        : '${_searchGroups.length} 个书源 · $count 条结果',
                    style: theme.textTheme.bodyMedium,
                  ),
                );
              }
              final categories = [?_filteredCategory, ..._categories];
              var categoryWidth = 32.0;
              for (final category in categories) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: category.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: category == _category
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                categoryWidth += painter.width + 20;
                painter.dispose();
              }
              final showPicker =
                  categories.isNotEmpty &&
                  categoryWidth > constraints.maxWidth - 56;
              return Row(
                key: const ValueKey('discover-category-toolbar'),
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          if (_categories.isEmpty)
                            Text(
                              _source?.name ?? '发现',
                              style: theme.textTheme.bodyMedium,
                            )
                          else
                            for (final category in [
                              ?_filteredCategory,
                              ..._categories,
                            ])
                              Semantics(
                                selected: category == _category,
                                button: true,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _category = category;
                                      _searchMode = false;
                                    });
                                    unawaited(_load(reset: true));
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 20),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      category.title,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colors.onSurface,
                                            fontWeight: category == _category
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                  if (showPicker)
                    IconButton(
                      key: const ValueKey('discover-category-picker'),
                      tooltip: '分类分组',
                      onPressed: _categories.isEmpty ? null : _pickCategory,
                      icon: const AppIcon(AppGlyph.chevronDown, size: 18),
                    ),
                  IconButton(
                    key: const ValueKey('discover-toggle-view'),
                    tooltip: _grid ? '列表视图' : '网格视图',
                    onPressed: _toggleGrid,
                    icon: AppIcon(
                      _grid ? AppGlyph.listView : AppGlyph.gridView,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              );
            },
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildList(bounds.maxWidth)),
        ],
      ),
    );
  }

  Widget _buildList(double width) {
    if (_searchMode ? _searchGroups.isEmpty : _books.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loading
                    ? '正在加载…'
                    : _error ??
                          (_searchMode
                              ? '没有找到匹配结果'
                              : _source == null
                              ? '添加支持发现的书源，或搜索书名与作者'
                              : _category == null
                              ? '该书源没有可用的发现分类'
                              : '暂无图书'),
                textAlign: TextAlign.center,
              ),
              if (!_loading)
                TextButton(
                  onPressed: _error != null
                      ? () {
                          if (_searchMode) {
                            unawaited(_search());
                          } else if (_category == null && _source != null) {
                            unawaited(_selectSource(_source!));
                          } else {
                            unawaited(_load(reset: true, force: true));
                          }
                        }
                      : _manageSources,
                  child: Text(_error != null ? '重试' : '管理书源'),
                ),
            ],
          ),
        ),
      );
    }
    final inset = BookCollectionLayout.listInset(context, width);
    if (_searchMode) {
      return RefreshIndicator(
        onRefresh: _search,
        child: ListView.separated(
          key: const ValueKey('discover-search-results'),
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(inset, 8, inset, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _searchGroups.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, index) => _searchCard(_searchGroups[index]),
        ),
      );
    }
    final footer = _hasMore || _error != null;
    return RefreshIndicator(
      onRefresh: () => _load(reset: true, force: true),
      child: _grid
          ? GridView.builder(
              key: const ValueKey('discover-grid'),
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                BookCollectionLayout.inset,
                4,
                BookCollectionLayout.inset,
                28,
              ),
              gridDelegate: BookCollectionLayout.grid(context, width).delegate,
              itemCount: _books.length + (footer ? 1 : 0),
              itemBuilder: (_, index) => index == _books.length
                  ? _footer()
                  : _bookTile(
                      _books[index].source,
                      _books[index].book,
                      grid: true,
                    ),
            )
          : ListView.separated(
              key: const ValueKey('discover-list'),
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(inset, 8, inset, 28),
              separatorBuilder: (_, _) =>
                  const SizedBox(height: BookCollectionLayout.rowSeparator),
              itemCount: _books.length + (footer ? 1 : 0),
              itemBuilder: (_, index) => index == _books.length
                  ? _footer()
                  : _bookTile(_books[index].source, _books[index].book),
            ),
    );
  }

  Widget _searchCard(_SearchGroup group) {
    final source = group.source;
    final books = group.books;
    final expanded = _expandedSources.contains(source.id);
    return Card(
      key: ValueKey('discover-source-card-${source.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _bookTile(source, books.first)),
                if (books.length > 1)
                  Semantics(
                    expanded: expanded,
                    child: TextButton(
                      key: ValueKey('discover-expand-${source.id}'),
                      onPressed: () => setState(() {
                        if (expanded) {
                          _expandedSources.remove(source.id);
                        } else {
                          _expandedSources.add(source.id);
                        }
                      }),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            expanded
                                ? AppGlyph.chevronUp
                                : AppGlyph.chevronDown,
                            size: 18,
                          ),
                          Text(
                            '${books.length} 条',
                            semanticsLabel:
                                '${expanded ? '收起' : '展开'}${source.name}的 ${books.length} 条结果',
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (expanded)
              for (final book in books.skip(1)) ...[
                const Divider(height: 1),
                ListTile(
                  key: ValueKey('discover-book-${source.id}-${book.bookUrl}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    book.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    book.author.isEmpty ? '佚名' : book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing:
                      widget.controller.shelfEntryFor(source, book) == null
                      ? null
                      : Text(
                          '已在书架',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                  onTap: () => _open(source, book),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _footer() => TextButton(
    onPressed: _loading
        ? null
        : () => _error == null ? _load() : _load(reset: true, force: true),
    child: Text(
      _loading
          ? '加载中…'
          : _error == null
          ? '加载更多'
          : '加载失败，点击重试',
    ),
  );

  Widget _bookTile(BookSource source, OnlineBook book, {bool grid = false}) {
    final theme = Theme.of(context);
    final summary = onlineBookCardSummary(book);
    final showSourceName = _searchMode && !grid;
    final cover = _DiscoverCover(
      controller: widget.controller,
      source: source,
      book: book,
      grid: grid,
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                book.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (grid
                            ? theme.textTheme.bodyMedium
                            : theme.textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (widget.controller.shelfEntryFor(source, book) != null) ...[
              const SizedBox(width: 6),
              Text(
                '已在书架',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
        if (!grid) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  summary.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (showSourceName) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
        if (!grid) ...[
          const SizedBox(height: 3),
          Text(
            summary.latest,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (!grid) ...[
          const SizedBox(height: 3),
          Text(
            summary.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
    return InkWell(
      key: ValueKey('discover-book-${source.id}-${book.bookUrl}'),
      onTap: () => _open(source, book),
      child: Padding(
        padding: grid ? EdgeInsets.zero : BookCollectionLayout.rowPadding,
        child: grid
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: BookCollectionLayout.coverAspectRatio,
                    child: cover,
                  ),
                  const SizedBox(height: BookCollectionLayout.titleGap),
                  Expanded(child: details),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cover,
                  const SizedBox(width: BookCollectionLayout.rowTextGap),
                  Expanded(child: details),
                ],
              ),
      ),
    );
  }
}

class _DiscoverCover extends StatefulWidget {
  const _DiscoverCover({
    required this.controller,
    required this.source,
    required this.book,
    required this.grid,
  });
  final OnlineBookController controller;
  final BookSource source;
  final OnlineBook book;
  final bool grid;
  @override
  State<_DiscoverCover> createState() => _DiscoverCoverState();
}

class _DiscoverCoverState extends State<_DiscoverCover> {
  Future<Uint8List?>? _cover;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_DiscoverCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.coverUrl != widget.book.coverUrl ||
        oldWidget.source != widget.source) {
      _load();
    }
  }

  void _load() {
    _cover = widget.book.coverUrl.isEmpty
        ? null
        : widget.controller.service.loadCover(
            widget.source,
            widget.book.coverUrl,
            referer: widget.source.baseUrl,
          );
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            widget.book.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
    return SizedBox(
      width: widget.grid
          ? double.infinity
          : BookCollectionLayout.rowCover.width,
      height: widget.grid
          ? double.infinity
          : BookCollectionLayout.rowCover.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final logicalWidth = widget.grid
              ? (constraints.maxWidth.isFinite ? constraints.maxWidth : 150.0)
              : BookCollectionLayout.rowCover.width;
          final decodeWidth =
              (logicalWidth * MediaQuery.devicePixelRatioOf(context))
                  .ceil()
                  .clamp(64, 640);
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: FutureBuilder<Uint8List?>(
              future: _cover,
              builder: (_, snapshot) => snapshot.data == null
                  ? placeholder
                  : Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      cacheWidth: decodeWidth,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, error, stack) => placeholder,
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _DiscoverPageSnapshot {
  const _DiscoverPageSnapshot({
    required this.books,
    required this.page,
    required this.hasMore,
  });

  final List<({BookSource source, OnlineBook book})> books;
  final int page;
  final bool hasMore;
}
