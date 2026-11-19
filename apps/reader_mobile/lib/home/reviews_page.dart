import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../library/library_store.dart';
import '../rea_micro/rea_micro_controller.dart';
import '../rea_micro/rea_micro_models.dart';
import '../storage/book_review_store.dart';
import 'book_cover_image.dart';
import 'book_notes_list.dart';
import 'desktop_layout.dart';
import 'reading_insights.dart';
import 'review_ticket.dart';
import 'reviews_cloud.dart';

enum _ReviewFilter {
  all('全部'),
  reviewed('已写'),
  pending('待写');

  const _ReviewFilter(this.label);

  final String label;
}

enum _ReviewSort {
  updated('最近更新'),
  rating('评分优先'),
  title('书名');

  const _ReviewSort(this.label);

  final String label;
}

/// 书评页：按书架展示已写书评与待写书目，支持评分、正文编辑和删除。
class ReviewsPage extends StatefulWidget {
  /// 创建页面。
  const ReviewsPage({
    super.key,
    required this.library,
    this.reviewStore,
    this.active = true,
    this.reaMicro,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 可注入的书评存储；为空时使用书架数据库实现。
  final BookReviewStore? reviewStore;

  /// 当前标签是否可见；重新显示时读取最新书评。
  final bool active;

  /// 阅微控制器；登录后把云端笔记和书评并入当前页面。
  final ReaMicroController? reaMicro;

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  int _section = 0;
  List<BookEntry>? _books;
  Map<String, BookNoteCounts> _counts = const {};
  Map<String, Duration> _durations = const {};
  Map<String, BookReview> _reviews = const <String, BookReview>{};
  Set<String> _finishedBooks = const {};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _keyboardFocus = FocusNode();
  _ReviewFilter _filter = _ReviewFilter.all;
  _ReviewSort _sort = _ReviewSort.updated;
  bool _searching = false;
  String _query = '';
  int _reloadToken = 0;
  int _editToken = 0;
  String? _error;
  String? _cloudError;
  bool _signedIn = false;
  Map<String, ({int cloudBookId, int bookId})> _cloudMarkBooks = const {};

  bool get _notes => _section == 0;

  BookReviewStore? get _store =>
      widget.reviewStore ?? widget.library.reviewStore();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_changeSection);
    widget.library.addListener(_onLibraryChanged);
    widget.reaMicro?.addListener(_onReaMicroChanged);
    _signedIn = widget.reaMicro?.signedIn ?? false;
    if (widget.active) _reload();
  }

  @override
  void dispose() {
    widget.library.removeListener(_onLibraryChanged);
    widget.reaMicro?.removeListener(_onReaMicroChanged);
    _tabs.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReviewsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final libraryChanged = oldWidget.library != widget.library;
    final controllerChanged = oldWidget.reaMicro != widget.reaMicro;
    if (libraryChanged) {
      oldWidget.library.removeListener(_onLibraryChanged);
      widget.library.addListener(_onLibraryChanged);
      _books = null;
    }
    if (controllerChanged) {
      oldWidget.reaMicro?.removeListener(_onReaMicroChanged);
      widget.reaMicro?.addListener(_onReaMicroChanged);
      _signedIn = widget.reaMicro?.signedIn ?? false;
      _cloudMarkBooks = const {};
    }
    if (oldWidget.active != widget.active ||
        libraryChanged ||
        controllerChanged ||
        oldWidget.reviewStore != widget.reviewStore) {
      _editToken++;
      if (widget.active) {
        _reload();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.active) _keyboardFocus.requestFocus();
        });
      }
    }
  }

  void _changeSection() {
    if (_section == _tabs.index) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _section = _tabs.index;
      _editToken++;
      _books = null;
      _error = null;
      _searching = false;
      _query = '';
      _searchController.clear();
    });
    if (usesDesktopLayout(context)) _keyboardFocus.requestFocus();
    if (widget.active) _reload();
  }

  void _onLibraryChanged() {
    if (widget.active) _reload();
  }

  void _onReaMicroChanged() {
    if (!mounted) return;
    final signedIn = widget.reaMicro?.signedIn ?? false;
    if (signedIn == _signedIn) return;
    _signedIn = signedIn;
    if (widget.active) {
      _reload();
    } else {
      setState(() {});
    }
  }

  void _toggleSearch() {
    if (usesDesktopLayout(context)) {
      _searchFocus.requestFocus();
      return;
    }
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
    if (!_searching) {
      FocusScope.of(context).unfocus();
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _resetSearchAndFilter() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = false;
      _query = '';
      _filter = _ReviewFilter.all;
    });
  }

  Future<void> _reload() async {
    final token = ++_reloadToken;
    final library = widget.library;
    final notes = _notes;
    try {
      final books = await library.list();
      final finished = notes ? _finishedBooks : await library.finishedBookIds();
      final counts = notes ? await library.bookNoteCounts() : _counts;
      final reviews = notes
          ? _reviews
          : await _store?.snapshot() ?? const <String, BookReview>{};
      final durations = notes
          ? _durations
          : await library.bookReadingDurations(minimumCountedSessionDuration);
      var visibleBooks = books;
      var visibleCounts = counts;
      var visibleReviews = reviews;
      var visibleDurations = durations;
      var markBooks = const <String, ({int cloudBookId, int bookId})>{};
      String? cloudError;
      final controller = widget.reaMicro;
      if (controller != null && controller.signedIn) {
        try {
          if (notes) {
            final remoteBooks = await controller.loadMarkBooks();
            final merge = mergeCloudMarkBooks(
              books: books,
              counts: counts,
              links: controller.links,
              markBooks: remoteBooks,
            );
            visibleBooks = <BookEntry>[
              ...withRemoteCovers(books, merge.coverUrls),
              ...merge.extraBooks,
            ];
            visibleCounts = merge.counts;
            markBooks = merge.markBooks;
          } else {
            final milestones = await controller.loadMilestones();
            final records = <CloudReviewRecord>[
              for (final milestone in milestones)
                CloudReviewRecord.fromMilestone(milestone),
            ];
            final seen = <int>{
              for (final record in records) record.cloudBookId,
            };
            final pendingLinks = <ReaMicroBookLink>[];
            for (final link in controller.links.values) {
              if (seen.add(link.cloudBookId)) pendingLinks.add(link);
            }
            final limitedLinks = pendingLinks.take(24).toList(growable: false);
            final fetched = await Future.wait<ReaMicroBookReview?>(
              <Future<ReaMicroBookReview?>>[
                for (final link in limitedLinks)
                  controller.loadBookReview(link.cloudBookId),
              ],
            );
            for (var index = 0; index < fetched.length; index++) {
              final review = fetched[index];
              if (review == null) continue;
              records.add(
                CloudReviewRecord.fromReview(
                  review,
                  cloudBookId: limitedLinks[index].cloudBookId,
                ),
              );
            }
            final merge = mergeCloudReviews(
              books: books,
              reviews: reviews,
              links: controller.links,
              records: records,
            );
            visibleBooks = <BookEntry>[
              ...withRemoteCovers(books, merge.coverUrls),
              ...merge.extraBooks,
            ];
            visibleReviews = merge.reviews;
            visibleDurations = <String, Duration>{
              ...durations,
              ...merge.durations,
            };
          }
        } catch (_) {
          cloudError = notes ? '阅微笔记读取失败，已显示本地笔记' : '阅微书评读取失败，已显示本地书评';
        }
      }
      if (mounted && widget.active && token == _reloadToken) {
        setState(() {
          _books = visibleBooks;
          _finishedBooks = finished;
          _counts = notes ? visibleCounts : _counts;
          _reviews = notes ? _reviews : visibleReviews;
          _durations = notes ? _durations : visibleDurations;
          _cloudMarkBooks = markBooks;
          _cloudError = cloudError;
          _error = null;
        });
      }
    } catch (_) {
      if (!mounted || !widget.active || token != _reloadToken) return;
      final label = notes ? '笔记' : '书评';
      if (_books == null) {
        setState(() => _error = '$label加载失败，请重试');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label刷新失败'),
            action: SnackBarAction(label: '重试', onPressed: _reload),
          ),
        );
      }
    }
  }

  Future<void> _edit(BookEntry book) async {
    final store = _store;
    if (store == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前无法保存书评')));
      return;
    }
    final token = ++_editToken;
    final BookReview? review;
    try {
      final finished = await widget.library.finishedBookIds();
      if (!mounted || !widget.active || token != _editToken) return;
      if (!finished.contains(book.id)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('标记读完后才能评分或写书评')));
        return;
      }
      review = (await store.snapshot())[book.id];
    } catch (_) {
      if (mounted && widget.active && token == _editToken) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('书评读取失败，请重试')));
      }
      return;
    }
    if (!mounted || !widget.active || token != _editToken) return;
    await _showEditor(book, store, review);
  }

  Future<void> _showEditor(
    BookEntry book,
    BookReviewStore store,
    BookReview? review,
  ) async {
    final draft = await _showPanel<_ReviewDraft>(
      (_) => _ReviewEditorSheet(
        book: book,
        review: review,
        onCommit: (draft) => draft.delete
            ? store.remove(book.id)
            : store.save(book.id, rating: draft.rating, content: draft.content),
      ),
      editing: true,
    );
    if (draft == null || !mounted || !widget.active) {
      return;
    }
    await _reload();
    if (mounted && widget.active) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(draft.delete ? '书评已删除' : '书评已保存')));
    }
  }

  Future<void> _openReview(BookEntry book, BookReview review) async {
    final token = ++_editToken;
    final edit = await _showPanel<bool>(
      (_) => _ReviewDetailSheet(
        book: book,
        review: review,
        canEdit: _finishedBooks.contains(book.id),
      ),
    );
    if (edit == true && mounted && widget.active && token == _editToken) {
      await _edit(book);
    }
  }

  Future<T?> _showPanel<T>(WidgetBuilder builder, {bool editing = false}) {
    if (usesDesktopLayout(context)) {
      return showDialog<T>(
        context: context,
        barrierDismissible: !editing,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 680,
              maxHeight: MediaQuery.sizeOf(context).height * .88,
            ),
            child: builder(context),
          ),
        ),
      );
    }
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: !editing,
      enableDrag: !editing,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = usesDesktopLayout(context);
    return CallbackShortcuts(
      bindings: {
        if (desktop && widget.active && !_notes)
          SingleActivator(
            LogicalKeyboardKey.keyF,
            meta: Theme.of(context).platform == TargetPlatform.macOS,
            control: Theme.of(context).platform != TargetPlatform.macOS,
          ): _toggleSearch,
      },
      child: ExcludeFocus(
        excluding: !widget.active,
        child: Focus(
          focusNode: _keyboardFocus,
          autofocus: widget.active,
          child: Scaffold(
            appBar: AppBar(
              centerTitle: false,
              scrolledUnderElevation: 0,
              title: _searching ? _searchField() : Text(_notes ? '笔记' : '书评'),
              actions: _actions(),
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: desktop ? 1280 : 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(desktop),
                    Expanded(child: _sectionBody()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool desktop) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
    child: LayoutBuilder(
      builder: (context, bounds) => Wrap(
        spacing: 24,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: desktop ? math.min(260, bounds.maxWidth) : bounds.maxWidth,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: ShapeDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: const StadiumBorder(),
              ),
              child: TabBar(
                controller: _tabs,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: ShapeDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: const StadiumBorder(),
                ),
                dividerColor: Colors.transparent,
                labelColor: Theme.of(context).colorScheme.onSurface,
                unselectedLabelColor: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
                labelStyle: const TextStyle(
                  fontFamily: 'builtin_song',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(key: ValueKey('notes-tab'), text: '笔记'),
                  Tab(key: ValueKey('reviews-tab'), text: '书评'),
                ],
              ),
            ),
          ),
          if (desktop && !_notes)
            SizedBox(
              width: math.min(360, bounds.maxWidth),
              child: _searchField(),
            ),
        ],
      ),
    ),
  );

  Widget _searchField() => TextField(
    key: const ValueKey<String>('reviews-search-field'),
    controller: _searchController,
    focusNode: _searchFocus,
    autofocus: !usesDesktopLayout(context),
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: '搜索书名、作者或书评',
      border: InputBorder.none,
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              tooltip: '清除搜索',
              onPressed: _clearSearch,
              icon: const AppIcon(AppGlyph.close),
            ),
    ),
    onChanged: (value) => setState(() => _query = value),
  );

  List<Widget> _actions() {
    final books = _books;
    return _searching
        ? [
            IconButton(
              tooltip: '关闭搜索',
              onPressed: _toggleSearch,
              icon: const AppIcon(AppGlyph.close),
            ),
          ]
        : [
            if (!_notes && books != null && books.isNotEmpty)
              PopupMenuButton<_ReviewSort>(
                key: const ValueKey<String>('reviews-sort'),
                tooltip: '书评排序',
                initialValue: _sort,
                onSelected: (value) => setState(() => _sort = value),
                icon: const AppIcon(AppGlyph.sort),
                itemBuilder: (_) => <PopupMenuEntry<_ReviewSort>>[
                  for (final sort in _ReviewSort.values)
                    appCheckedMenuItem<_ReviewSort>(
                      key: ValueKey<String>('reviews-sort-${sort.name}'),
                      value: sort,
                      checked: sort == _sort,
                      child: Text(sort.label),
                    ),
                ],
              ),
            if (!_notes && books != null && books.isNotEmpty)
              IconButton(
                tooltip: '搜索书评',
                onPressed: _toggleSearch,
                icon: const AppIcon(AppGlyph.search),
              ),
            IconButton(
              key: ValueKey(_notes ? 'notes-refresh' : 'reviews-refresh'),
              tooltip: _notes ? '刷新笔记' : '刷新书评',
              onPressed: _reload,
              icon: const AppIcon(AppGlyph.refresh),
            ),
          ];
  }

  Future<List<ReaderAnnotation>> _loadNotes(String bookId) async {
    final local =
        await widget.library.annotationStore(bookId)?.list() ??
        const <ReaderAnnotation>[];
    final remote = _cloudMarkBooks[bookId];
    final controller = widget.reaMicro;
    if (remote == null || controller == null || !controller.signedIn) {
      return local;
    }
    try {
      final cloud = await controller.loadBookMarks(
        cloudBookId: remote.cloudBookId,
        bookId: remote.bookId,
      );
      return mergeCloudMarks(local, cloud);
    } catch (_) {
      return local;
    }
  }

  Widget _sectionBody() {
    final books = _books;
    if (books == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : _ReviewLoadError(message: _error!, onRetry: _reload);
    }
    Widget body;
    if (_notes) {
      body = BookNotesList(
        books: books,
        counts: _counts,
        loadNotes: _loadNotes,
        onRefresh: _reload,
      );
    } else if (books.isEmpty) {
      body = const _EmptyReviews();
    } else {
      body = RefreshIndicator(
        onRefresh: _reload,
        child: _ReviewList(
          books: books,
          finishedBooks: _finishedBooks,
          reviews: _reviews,
          durations: _durations,
          query: _query,
          filter: _filter,
          sort: _sort,
          onFilterChanged: (filter) => setState(() => _filter = filter),
          onResetSearchAndFilter: _resetSearchAndFilter,
          onOpen: _openReview,
          onEdit: _edit,
        ),
      );
    }
    final cloudError = _cloudError;
    if (cloudError == null) return body;
    return Column(
      children: [
        _CloudNotice(message: cloudError, onRetry: _reload),
        Expanded(child: body),
      ],
    );
  }
}

class _ReviewList extends StatelessWidget {
  const _ReviewList({
    required this.books,
    required this.finishedBooks,
    required this.reviews,
    required this.durations,
    required this.query,
    required this.filter,
    required this.sort,
    required this.onFilterChanged,
    required this.onResetSearchAndFilter,
    required this.onOpen,
    required this.onEdit,
  });

  final List<BookEntry> books;
  final Set<String> finishedBooks;
  final Map<String, BookReview> reviews;
  final Map<String, Duration> durations;
  final String query;
  final _ReviewFilter filter;
  final _ReviewSort sort;
  final ValueChanged<_ReviewFilter> onFilterChanged;
  final VoidCallback onResetSearchAndFilter;
  final Future<void> Function(BookEntry, BookReview) onOpen;
  final Future<void> Function(BookEntry) onEdit;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    bool matches(BookEntry book) {
      if (normalizedQuery.isEmpty) {
        return true;
      }
      final review = reviews[book.id];
      return book.title.toLowerCase().contains(normalizedQuery) ||
          book.author.toLowerCase().contains(normalizedQuery) ||
          (review != null &&
              review.content.toLowerCase().contains(normalizedQuery));
    }

    final allReviewed = <BookEntry>[
      for (final book in books)
        if (reviews[book.id] != null) book,
    ];
    final reviewed = <BookEntry>[
      for (final book in allReviewed)
        if (matches(book)) book,
    ];
    int compareBooks(BookEntry left, BookEntry right) {
      switch (sort) {
        case _ReviewSort.updated:
          return reviews[right.id]!.updatedAt.compareTo(
            reviews[left.id]!.updatedAt,
          );
        case _ReviewSort.rating:
          final byRating = (reviews[right.id]!.rating ?? 0).compareTo(
            reviews[left.id]!.rating ?? 0,
          );
          if (byRating != 0) {
            return byRating;
          }
          return reviews[right.id]!.updatedAt.compareTo(
            reviews[left.id]!.updatedAt,
          );
        case _ReviewSort.title:
          return left.title.toLowerCase().compareTo(right.title.toLowerCase());
      }
    }

    reviewed.sort(compareBooks);
    final pending = <BookEntry>[
      for (final book in books)
        if (finishedBooks.contains(book.id) &&
            reviews[book.id] == null &&
            matches(book))
          book,
    ];
    final pendingCount = books
        .where(
          (book) => finishedBooks.contains(book.id) && reviews[book.id] == null,
        )
        .length;
    if (sort == _ReviewSort.title) {
      pending.sort(
        (left, right) =>
            left.title.toLowerCase().compareTo(right.title.toLowerCase()),
      );
    }
    final showReviewed = filter != _ReviewFilter.pending;
    final showPending = filter != _ReviewFilter.reviewed;
    final visibleReviewed = showReviewed ? reviewed : const <BookEntry>[];
    final visiblePending = showPending ? pending : const <BookEntry>[];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _ReviewSummary(
          reviewed: allReviewed.length,
          total: allReviewed.length + pendingCount,
          reviews: reviews,
        ),
        _ReviewFilterBar(
          reviewed: reviewed.length,
          pending: pending.length,
          selected: filter,
          onSelected: onFilterChanged,
        ),
        const SizedBox(height: 10),
        if (visibleReviewed.isEmpty && visiblePending.isEmpty)
          _NoReviewMatches(
            query: query.trim(),
            filter: filter,
            onReset: onResetSearchAndFilter,
          )
        else if (usesDesktopLayout(context))
          LayoutBuilder(
            builder: (context, bounds) {
              final columns = (bounds.maxWidth / 380).floor().clamp(1, 3);
              final width = (bounds.maxWidth - (columns - 1) * 20) / columns;
              return Wrap(
                key: const ValueKey('reviews-desktop-grid'),
                spacing: 20,
                children: [
                  for (final book in [...visibleReviewed, ...visiblePending])
                    SizedBox(
                      key: ValueKey(book.id),
                      width: width,
                      child: _ticket(book),
                    ),
                ],
              );
            },
          )
        else
          for (final book in [...visibleReviewed, ...visiblePending])
            _ticket(book),
      ],
    );
  }

  Widget _ticket(BookEntry book) {
    final review = reviews[book.id];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ReviewTicket(
        key: ValueKey(
          'review-${review == null ? 'pending' : 'card'}-${book.id}',
        ),
        book: book,
        review: review,
        duration: durations[book.id],
        onTap: review == null ? () => onEdit(book) : () => onOpen(book, review),
      ),
    );
  }
}

class _ReviewFilterBar extends StatelessWidget {
  const _ReviewFilterBar({
    required this.reviewed,
    required this.pending,
    required this.selected,
    required this.onSelected,
  });

  final int reviewed;
  final int pending;
  final _ReviewFilter selected;
  final ValueChanged<_ReviewFilter> onSelected;

  int _count(_ReviewFilter filter) => switch (filter) {
    _ReviewFilter.all => reviewed + pending,
    _ReviewFilter.reviewed => reviewed,
    _ReviewFilter.pending => pending,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final filter in _ReviewFilter.values)
          Expanded(
            child: Semantics(
              key: ValueKey<String>('reviews-filter-selected-${filter.name}'),
              selected: filter == selected,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: filter == selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      width: filter == selected ? 2 : 1,
                    ),
                  ),
                ),
                child: TextButton(
                  key: ValueKey<String>('reviews-filter-${filter.name}'),
                  onPressed: () => onSelected(filter),
                  style: TextButton.styleFrom(
                    foregroundColor: filter == selected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  child: Text(
                    '${filter.label} ${_count(filter)}',
                    style: TextStyle(
                      fontWeight: filter == selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NoReviewMatches extends StatelessWidget {
  const _NoReviewMatches({
    required this.query,
    required this.filter,
    required this.onReset,
  });

  final String query;
  final _ReviewFilter filter;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = query.isNotEmpty
        ? '没有找到相关书评'
        : switch (filter) {
            _ReviewFilter.all => '没有可显示的书评',
            _ReviewFilter.reviewed => '还没有写过书评',
            _ReviewFilter.pending => '没有待写书评',
          };
    return Card(
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      key: const ValueKey<String>('reviews-no-results'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            AppIcon(
              query.isNotEmpty ? AppGlyph.searchOff : AppGlyph.rateReview,
              color: theme.colorScheme.outline,
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(title, style: theme.textTheme.titleMedium),
            if (query.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '没有书名、作者或书评正文包含“$query”',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onReset,
              icon: const AppIcon(AppGlyph.filterOff),
              label: Text(query.isEmpty ? '查看全部书评' : '清除搜索与筛选'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({
    required this.reviewed,
    required this.total,
    required this.reviews,
  });

  final int reviewed;
  final int total;
  final Map<String, BookReview> reviews;

  @override
  Widget build(BuildContext context) {
    final ratings = reviews.values
        .map((review) => review.rating)
        .whereType<int>()
        .toList();
    final average = ratings.isEmpty
        ? null
        : ratings.reduce((left, right) => left + right) / ratings.length;
    final scheme = Theme.of(context).colorScheme;
    return Text(
      '已写 $reviewed 篇 · 待写 ${total - reviewed} 本${average == null ? '' : ' · 平均 ${average.toStringAsFixed(1)} 星'}',
      key: const ValueKey('reviews-summary'),
      style: TextStyle(
        fontSize: 12,
        color: scheme.onSurfaceVariant,
        height: 1.5,
      ),
    );
  }
}

class _ReviewDetailSheet extends StatelessWidget {
  const _ReviewDetailSheet({
    required this.book,
    required this.review,
    required this.canEdit,
  });

  final BookEntry book;
  final BookReview review;
  final bool canEdit;

  Future<void> _copy(BuildContext context) async {
    final text = <String>[
      book.title,
      if (book.author.isNotEmpty) book.author,
      '评分：${review.rating == null ? '未评分' : '${review.rating}/5'}',
      '更新：${_reviewDate(review.updatedAt)}',
      '',
      review.content.isEmpty ? '仅评分，未写正文。' : review.content,
    ].join('\n');
    var message = '书评已复制';
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      message = '复制失败，请重试';
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = review.content.isEmpty ? '仅评分，未写正文。' : review.content;
    return Material(
      key: const ValueKey<String>('review-detail'),
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.84,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 14),
                child: Column(
                  children: [
                    if (!usesDesktopLayout(context)) ...[
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BookCoverImage(book: book, width: 50, height: 68),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                book.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge,
                              ),
                              if (book.author.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  book.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 10,
                                runSpacing: 4,
                                children: [
                                  _StarRow(rating: review.rating, size: 18),
                                  Text(
                                    '${_reviewDate(review.updatedAt)} 更新',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭书评详情',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const AppIcon(AppGlyph.close),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${review.content.characters.length} 字',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        content,
                        key: const ValueKey<String>('review-detail-content'),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.75,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              _actions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        final copy = OutlinedButton.icon(
          key: const ValueKey<String>('review-detail-copy'),
          onPressed: () => _copy(context),
          icon: const AppIcon(AppGlyph.copy),
          label: const Text('复制书评'),
        );
        final edit = FilledButton.icon(
          key: const ValueKey<String>('review-detail-edit'),
          onPressed: canEdit ? () => Navigator.of(context).pop(true) : null,
          icon: const AppIcon(AppGlyph.edit),
          label: const Text('编辑书评'),
        );
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [copy, const SizedBox(height: 8), edit],
              )
            : Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 12),
                  Expanded(child: edit),
                ],
              );
      },
    ),
  );
}

class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating, required this.size});

  final int? rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = rating ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          AppIcon(
            AppGlyph.star,
            filled: star <= value,
            size: size,
            color: star <= value
                ? const Color(0xFFE0A327)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        if (rating == null) ...[
          const SizedBox(width: 4),
          Text(
            '未评分',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyReviews extends StatelessWidget {
  const _EmptyReviews();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(AppGlyph.rateReview, size: 64),
          SizedBox(height: 12),
          Text('标记读完后，可以在这里评分和写书评'),
        ],
      ),
    );
  }
}

class _ReviewLoadError extends StatelessWidget {
  const _ReviewLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            AppGlyph.warning,
            size: 40,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(message),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('reviews-load-retry'),
            onPressed: onRetry,
            icon: const AppIcon(AppGlyph.refresh),
            label: const Text('重新加载'),
          ),
        ],
      ),
    ),
  );
}

class _CloudNotice extends StatelessWidget {
  const _CloudNotice({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              key: const ValueKey<String>('reviews-cloud-error'),
              style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _ReviewEditorSheet extends StatefulWidget {
  const _ReviewEditorSheet({
    required this.book,
    required this.review,
    required this.onCommit,
  });

  final BookEntry book;
  final BookReview? review;
  final Future<void> Function(_ReviewDraft draft) onCommit;

  @override
  State<_ReviewEditorSheet> createState() => _ReviewEditorSheetState();
}

class _ReviewEditorSheetState extends State<_ReviewEditorSheet> {
  late final TextEditingController _controller;
  late final int? _initialRating;
  late final String _initialContent;
  int? _rating;
  bool _allowPop = false;
  bool _discardDialogVisible = false;
  bool _closing = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialRating = widget.review?.rating;
    _initialContent = widget.review?.content ?? '';
    _rating = _initialRating;
    _controller = TextEditingController(text: _initialContent)
      ..addListener(_refresh);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _error = null);

  bool get _canSave =>
      !_saving &&
      _dirty &&
      (_rating != null || _controller.text.trim().isNotEmpty);

  bool get _dirty =>
      _rating != _initialRating ||
      _controller.text.trim() != _initialContent.trim();

  void _finish(_ReviewDraft draft) {
    if (_closing || _saving) {
      return;
    }
    _closing = true;
    if (_allowPop) {
      Navigator.of(context).pop(draft);
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(draft);
      }
    });
  }

  Future<bool> _confirmDiscard() async {
    if (_discardDialogVisible) {
      return false;
    }
    _discardDialogVisible = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存的书评？'),
        content: const Text('评分或正文还没有保存，离开后本次修改会丢失。'),
        actions: [
          TextButton(
            key: const ValueKey<String>('review-discard-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            key: const ValueKey<String>('review-discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    _discardDialogVisible = false;
    return discard == true;
  }

  Future<void> _close() async {
    if (_closing || _saving) {
      return;
    }
    if (!_dirty) {
      _closing = true;
      Navigator.of(context).pop();
      return;
    }
    final discard = await _confirmDiscard();
    if (!discard || !mounted) {
      return;
    }
    _closing = true;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    await _commit(
      _ReviewDraft(rating: _rating, content: _controller.text.trim()),
    );
  }

  Future<void> _commit(_ReviewDraft draft) async {
    if (_saving || _closing) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onCommit(draft);
      if (mounted) {
        _saving = false;
        _finish(draft);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : draft.delete
              ? '删除失败，书评未删除，请重试'
              : '保存失败，草稿已保留，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书评？'),
        content: const Text('评分和正文都会删除，且不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _commit(const _ReviewDraft.delete());
    }
  }

  Widget _heading(ThemeData theme) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.review == null ? '写书评' : '编辑书评',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 3),
            Text(
              widget.book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      IconButton(
        key: const ValueKey('review-editor-close'),
        tooltip: '关闭',
        onPressed: _saving ? null : _close,
        icon: const AppIcon(AppGlyph.close),
      ),
    ],
  );

  void _setRating(int star) => setState(() {
    _rating = _rating == star ? null : star;
    _error = null;
  });

  Widget _ratingPicker(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('评分', style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var star = 1; star <= 5; star++)
            Semantics(
              selected: star == _rating,
              child: IconButton(
                key: ValueKey<String>('review-rating-$star'),
                tooltip: '$star 星',
                onPressed: _saving ? null : () => _setRating(star),
                iconSize: 34,
                color: const Color(0xFFE0A327),
                icon: AppIcon(AppGlyph.star, filled: star <= (_rating ?? 0)),
              ),
            ),
        ],
      ),
    ],
  );

  Widget _contentInput(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('书评内容', style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey<String>('review-content'),
        controller: _controller,
        readOnly: _saving,
        minLines: 4,
        maxLines: 8,
        maxLength: BookReview.maxContentLength,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(
          hintText: '写下这本书带给你的感受…',
          alignLabelWithHint: true,
        ),
      ),
    ],
  );

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(theme),
          const SizedBox(height: 18),
          _ratingPicker(theme),
          const SizedBox(height: 16),
          _contentInput(theme),
        ],
      ),
    );
  }

  Widget _actions() => _ReviewEditorActions(
    isEditing: widget.review != null,
    canSave: _canSave,
    onSave: _save,
    onDelete: _delete,
    saving: _saving,
    error: _error,
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && (!_dirty || _allowPop),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Material(
      key: const ValueKey<String>('review-editor'),
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: _content(context)),
              _actions(),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ReviewEditorActions extends StatelessWidget {
  const _ReviewEditorActions({
    required this.isEditing,
    required this.canSave,
    required this.onSave,
    required this.onDelete,
    required this.saving,
    required this.error,
  });

  final bool isEditing;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final bool saving;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    key: const ValueKey('review-save-error'),
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            FilledButton.icon(
              key: const ValueKey<String>('review-save'),
              onPressed: canSave ? onSave : null,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const AppIcon(AppGlyph.check),
              label: Text(saving ? '正在保存…' : '保存书评'),
            ),
            if (isEditing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                key: const ValueKey<String>('review-delete'),
                onPressed: saving ? null : onDelete,
                icon: const AppIcon(AppGlyph.delete),
                label: const Text('删除书评'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewDraft {
  const _ReviewDraft({this.rating, this.content = ''}) : delete = false;

  const _ReviewDraft.delete() : rating = null, content = '', delete = true;

  final int? rating;
  final String content;
  final bool delete;
}

String _reviewDate(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
