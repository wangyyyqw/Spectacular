import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_drawer_style.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../library/library_store.dart';
import '../storage/book_review_store.dart';
import 'book_cover_image.dart';
import 'book_lists_view.dart';
import 'book_notes_list.dart';
import 'desktop_layout.dart';
import 'review_ticket.dart';
import '../diagnostics/reader_log.dart';

/// 书评页：按书架展示已写书评与待写书目，支持评分、正文编辑和删除。
class ReviewsPage extends StatefulWidget {
  /// 创建页面。
  const ReviewsPage({
    super.key,
    required this.library,
    this.reviewStore,
    this.active = true,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 可注入的书评存储；为空时使用书架数据库实现。
  final BookReviewStore? reviewStore;

  /// 当前标签是否可见；重新显示时读取最新书评。
  final bool active;

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  int _section = 0;
  List<BookEntry>? _books;
  Map<String, BookNoteCounts> _counts = const {};
  Map<String, Duration> _durations = const {};
  Map<String, BookReview> _reviews = const <String, BookReview>{};
  Set<String> _finishedBooks = const {};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _keyboardFocus = FocusNode();
  bool _searching = false;
  bool _inlineSearchAvailable = false;
  String _query = '';
  int _reloadToken = 0;
  int _editToken = 0;
  double _dragDx = 0;
  String? _error;

  bool get _notes => _section == 0;

  bool get _bookListsTab => _section == 2;

  BookReviewStore? get _store =>
      widget.reviewStore ?? widget.library.reviewStore();

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_onLibraryChanged);
    if (widget.active) _reload();
  }

  @override
  void dispose() {
    widget.library.removeListener(_onLibraryChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReviewsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final libraryChanged = oldWidget.library != widget.library;
    if (libraryChanged) {
      oldWidget.library.removeListener(_onLibraryChanged);
      widget.library.addListener(_onLibraryChanged);
      _books = null;
    }
    if (oldWidget.active != widget.active ||
        libraryChanged ||
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

  void _changeSection(int index) {
    if (_section == index) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _section = index;
      _editToken++;
      _books = null;
      _error = null;
      _searching = false;
      _query = '';
      _searchController.clear();
    });
    if (usesDesktopLayout(context)) _keyboardFocus.requestFocus();
    if (widget.active && !_bookListsTab) _reload();
  }

  void _endSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _dragDx;
    _dragDx = 0;
    final next = velocity < -150 || (velocity.abs() <= 150 && distance <= -60);
    final previous =
        velocity > 150 || (velocity.abs() <= 150 && distance >= 60);
    if (next && _section < 2) {
      _changeSection(_section + 1);
    } else if (previous && _section > 0) {
      _changeSection(_section - 1);
    }
  }

  void _onLibraryChanged() {
    if (widget.active) _reload();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
    if (_searching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  void _openSearch() {
    if (_searching) {
      _searchFocus.requestFocus();
      return;
    }
    if (_inlineSearchAvailable) {
      _searchFocus.requestFocus();
      return;
    }
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _resetSearch() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  Future<void> _reload() async {
    if (_bookListsTab) return;
    final token = ++_reloadToken;
    final library = widget.library;
    final notes = _notes;
    try {
      final books = <BookEntry>[
        ...await library.list(),
        // 已移除书籍的笔记与书评继续展示，不跟随书架增删。
        ...await library.retainedBooks(),
      ];
      final finished = notes ? _finishedBooks : await library.finishedBookIds();
      final counts = notes ? await library.bookNoteCounts() : _counts;
      final reviews = notes
          ? _reviews
          : await _store?.snapshot() ?? const <String, BookReview>{};
      final durations = notes
          ? _durations
          : await library.bookReadingDurations();
      if (mounted && widget.active && token == _reloadToken) {
        setState(() {
          _books = books;
          _finishedBooks = finished;
          _counts = counts;
          _reviews = {
            for (final book in books)
              if (reviews[book.id] != null) book.id: reviews[book.id]!,
          };
          _durations = durations;
          _error = null;
        });
      }
    } catch (error, stackTrace) {
      if (!mounted || !widget.active || token != _reloadToken) return;
      final label = notes ? '笔记' : '书评';
      if (_books == null) {
        setState(() => _error = '$label加载失败，请重试');
      } else {
        recordAppError('reviews_reload_failed', error, stackTrace: stackTrace);
      }
    }
  }

  Future<void> _edit(BookEntry book) async {
    final store = _store;
    if (store == null) {
      recordAppEvent('review_store_unavailable');
      return;
    }
    final token = ++_editToken;
    final BookReview? review;
    try {
      final finished = await widget.library.finishedBookIds();
      if (!mounted || !widget.active || token != _editToken) return;
      if (!finished.contains(book.id)) {
        recordAppEvent('review_requires_finished_book');
        return;
      }
      review = (await store.snapshot())[book.id];
    } catch (error, stackTrace) {
      if (mounted && widget.active && token == _editToken) {
        recordAppError('review_load_failed', error, stackTrace: stackTrace);
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
      recordAppEvent(draft.delete ? 'review_deleted' : 'review_saved');
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

  Future<T?> _showPanel<T>(WidgetBuilder builder, {bool editing = false}) =>
      showReaderDrawer<T>(
        context: context,
        isDismissible: !editing,
        enableDrag: !editing,
        waitForDismissal: true,
        builder: builder,
      );

  @override
  Widget build(BuildContext context) {
    final desktop = usesDesktopLayout(context);
    return CallbackShortcuts(
      bindings: {
        if (desktop && widget.active)
          const SingleActivator(
            LogicalKeyboardKey.escape,
            includeRepeats: false,
          ): () {
            if (_searching || _query.isNotEmpty || _searchFocus.hasFocus) {
              _resetSearch();
              _keyboardFocus.requestFocus();
            }
          },
        if (desktop && widget.active)
          SingleActivator(
            LogicalKeyboardKey.keyF,
            meta: Theme.of(context).platform == TargetPlatform.macOS,
            control: Theme.of(context).platform != TargetPlatform.macOS,
          ): _openSearch,
      },
      child: ExcludeFocus(
        excluding: !widget.active,
        child: Focus(
          focusNode: _keyboardFocus,
          autofocus: widget.active,
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 0,
              automaticallyImplyLeading: false,
              centerTitle: false,
              scrolledUnderElevation: 0,
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: desktop ? 1280 : 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(desktop),
                    Expanded(
                      child: GestureDetector(
                        key: const ValueKey('reviews-section-body'),
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) => _dragDx = 0,
                        onHorizontalDragUpdate: (details) =>
                            _dragDx += details.delta.dx,
                        onHorizontalDragEnd: _endSwipe,
                        child: _SectionTransition(
                          index: _section,
                          child: KeyedSubtree(
                            key: ValueKey(_section),
                            child: _sectionBody(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool desktop) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: SizedBox(
        height: 48,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fullWidth = constraints.maxWidth;
            final wide = desktop && fullWidth >= 680;
            _inlineSearchAvailable = wide;
            final expandedSearch = _searching || (!wide && _query.isNotEmpty);
            final inlineSearch = wide && !expandedSearch;
            return Stack(
              alignment: Alignment.centerRight,
              children: [
                Positioned.fill(
                  child: ExcludeFocus(
                    excluding: expandedSearch,
                    child: ExcludeSemantics(
                      excluding: expandedSearch,
                      child: AnimatedOpacity(
                        opacity: expandedSearch ? 0 : 1,
                        duration: const Duration(milliseconds: 140),
                        child: IgnorePointer(
                          ignoring: expandedSearch,
                          child: Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: desktop ? 320 : 252,
                                    ),
                                    child: _SectionSlider(
                                      index: _section,
                                      onSelected: _changeSection,
                                    ),
                                  ),
                                ),
                              ),
                              if (inlineSearch)
                                SizedBox(width: 300, child: _searchField()),
                              SizedBox(width: inlineSearch ? 4 : 48),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!wide || expandedSearch)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: expandedSearch ? fullWidth : 44,
                    height: 44,
                    alignment: Alignment.centerRight,
                    child: ClipRect(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.centerRight,
                          children: [...previous, ?current],
                        ),
                        child: expandedSearch
                            ? OverflowBox(
                                key: const ValueKey('reviews-search-expanded'),
                                alignment: Alignment.centerRight,
                                minWidth: fullWidth,
                                maxWidth: fullWidth,
                                minHeight: 48,
                                maxHeight: 48,
                                child: Row(
                                  children: [
                                    Expanded(child: _searchField()),
                                    Theme(
                                      data: _noFeedback(context),
                                      child: IconButton(
                                        tooltip: '关闭搜索',
                                        highlightColor: Colors.transparent,
                                        hoverColor: Colors.transparent,
                                        focusColor: Colors.transparent,
                                        onPressed: _resetSearch,
                                        icon: const AppIcon(AppGlyph.close),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : _SearchButton(
                                key: const ValueKey('reviews-search-button'),
                                tooltip: _searchTooltip,
                                onPressed: _toggleSearch,
                              ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String get _searchTooltip => switch (_section) {
    0 => '搜索笔记',
    1 => '搜索书评',
    _ => '搜索书单',
  };

  String get _searchHint => switch (_section) {
    0 => '搜索书名或作者',
    1 => '搜索书名、作者或书评',
    _ => '搜索书单或书名',
  };

  Widget _searchField() {
    final theme = Theme.of(context);
    final muted = ReaderDrawerStyle.mutedOf(theme);
    final border = OutlineInputBorder(
      borderRadius: ReaderUiStyle.controlRadius,
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    return Material(
      color: ReaderDrawerStyle.searchSurfaceOf(theme),
      borderRadius: border.borderRadius,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      child: TextField(
        key: const ValueKey<String>('reviews-search-field'),
        controller: _searchController,
        focusNode: _searchFocus,
        autofocus: !usesDesktopLayout(context),
        textInputAction: TextInputAction.search,
        cursorColor: ReaderDrawerStyle.textOf(theme),
        decoration: InputDecoration(
          hintText: _searchHint,
          hintStyle: TextStyle(color: muted),
          filled: true,
          isDense: true,
          fillColor: ReaderDrawerStyle.searchSurfaceOf(theme),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: theme.colorScheme.primary),
          ),
          prefixIconConstraints: const BoxConstraints.tightFor(
            width: 40,
            height: 40,
          ),
          suffixIconConstraints: const BoxConstraints.tightFor(
            width: 40,
            height: 40,
          ),
          prefixIcon: AppIcon(AppGlyph.search, size: 20, color: muted),
          suffixIcon: _query.isEmpty
              ? null
              : Theme(
                  data: _noFeedback(context),
                  child: IconButton(
                    tooltip: '清除搜索',
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    onPressed: _clearSearch,
                    icon: AppIcon(AppGlyph.close, color: muted),
                  ),
                ),
        ),
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _sectionBody() {
    if (_bookListsTab) {
      return BookListsView(
        library: widget.library,
        active: widget.active,
        query: _query,
      );
    }
    final books = _books;
    if (books == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : _ReviewLoadError(message: _error!, onRetry: _reload);
    }
    if (_notes) {
      return BookNotesList(
        books: books,
        counts: _counts,
        query: _query,
        loadNotes: (id) async =>
            await widget.library.annotationStore(id)?.list() ??
            const <ReaderAnnotation>[],
        onRefresh: _reload,
      );
    }
    if (books.isEmpty) return const _EmptyReviews();
    return RefreshIndicator(
      onRefresh: _reload,
      child: _ReviewList(
        books: books,
        finishedBooks: _finishedBooks,
        reviews: _reviews,
        durations: _durations,
        query: _query,
        onResetSearch: _resetSearch,
        onOpen: _openReview,
        onEdit: _edit,
      ),
    );
  }
}

ThemeData _noFeedback(BuildContext context) => Theme.of(context).copyWith(
  splashFactory: NoSplash.splashFactory,
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
  focusColor: Colors.transparent,
);

class _SearchButton extends StatelessWidget {
  const _SearchButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: ReaderUiStyle.controlShape.copyWith(
        side: BorderSide(color: scheme.outlineVariant),
      ),
      elevation: 0,
      child: Theme(
        data: _noFeedback(context),
        child: IconButton(
          tooltip: tooltip,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          onPressed: onPressed,
          icon: const AppIcon(AppGlyph.search),
        ),
      ),
    );
  }
}

class _SectionSlider extends StatelessWidget {
  const _SectionSlider({required this.index, required this.onSelected});

  static const _sections = <({String key, String label})>[
    (key: 'notes', label: '笔记'),
    (key: 'reviews', label: '书评'),
    (key: 'booklists', label: '书单'),
  ];

  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segment = constraints.maxWidth / _sections.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: index * segment,
                top: 0,
                width: segment,
                height: constraints.maxHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: .08),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < _sections.length; i++)
                    Expanded(
                      child: Semantics(
                        key: ValueKey('${_sections[i].key}-tab'),
                        label: _sections[i].label,
                        button: true,
                        selected: index == i,
                        onTap: () => onSelected(i),
                        excludeSemantics: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onSelected(i),
                          child: Center(
                            child: Text(
                              _sections[i].label,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.2,
                                fontWeight: index == i
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: index == i
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 切换笔记、书评、书单时沿用书架的轻微横向滑入淡入。
class _SectionTransition extends StatefulWidget {
  const _SectionTransition({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_SectionTransition> createState() => _SectionTransitionState();
}

class _SectionTransitionState extends State<_SectionTransition> {
  double _direction = 0;

  @override
  void didUpdateWidget(_SectionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _direction = (widget.index - oldWidget.index).sign.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    final key = ValueKey(widget.index);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        reverseDuration: const Duration(milliseconds: 150),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        layoutBuilder: _layoutLayers,
        transitionBuilder: (child, animation) {
          final direction = child.key == key ? _direction : -_direction;
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: Offset(direction * .1, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(key: key, child: widget.child),
      ),
    );
  }

  Widget _layoutLayers(Widget? current, List<Widget> previous) => Stack(
    fit: StackFit.expand,
    children: [
      for (final child in previous)
        ExcludeFocus(
          child: ExcludeSemantics(
            child: IgnorePointer(child: HeroMode(enabled: false, child: child)),
          ),
        ),
      ?current,
    ],
  );
}

class _ReviewList extends StatelessWidget {
  const _ReviewList({
    required this.books,
    required this.finishedBooks,
    required this.reviews,
    required this.durations,
    required this.query,
    required this.onResetSearch,
    required this.onOpen,
    required this.onEdit,
  });

  final List<BookEntry> books;
  final Set<String> finishedBooks;
  final Map<String, BookReview> reviews;
  final Map<String, Duration> durations;
  final String query;
  final VoidCallback onResetSearch;
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

    final reviewed = <BookEntry>[
      for (final book in books)
        if (reviews[book.id] != null && matches(book)) book,
    ];
    reviewed.sort(
      (left, right) =>
          reviews[right.id]!.updatedAt.compareTo(reviews[left.id]!.updatedAt),
    );
    final pending = <BookEntry>[
      for (final book in books)
        if (finishedBooks.contains(book.id) &&
            reviews[book.id] == null &&
            matches(book))
          book,
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        if (reviewed.isEmpty && pending.isEmpty)
          _NoReviewMatches(query: query.trim(), onReset: onResetSearch)
        else if (usesDesktopLayout(context))
          LayoutBuilder(
            builder: (context, bounds) {
              final columns = (bounds.maxWidth / 380).floor().clamp(1, 3);
              final width = (bounds.maxWidth - (columns - 1) * 20) / columns;
              return Wrap(
                key: const ValueKey('reviews-desktop-grid'),
                spacing: 20,
                children: [
                  for (final book in [...reviewed, ...pending])
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
          for (final book in [...reviewed, ...pending]) _ticket(book),
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

class _NoReviewMatches extends StatelessWidget {
  const _NoReviewMatches({required this.query, required this.onReset});

  final String query;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = query.isNotEmpty ? '没有找到相关书评' : '没有可显示的书评';
    return Card(
      elevation: 0,
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
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onReset,
                icon: const AppIcon(AppGlyph.filterOff),
                label: const Text('清除搜索'),
              ),
            ],
          ],
        ),
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
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) recordAppEvent('review_copied');
    } catch (error, stackTrace) {
      if (context.mounted) {
        recordAppError('review_copy_failed', error, stackTrace: stackTrace);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = review.content.isEmpty ? '仅评分，未写正文。' : review.content;
    return Material(
      key: const ValueKey<String>('review-detail'),
      type: MaterialType.transparency,
      child: ReaderSheetForm(
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCoverImage(book: book, width: 50, height: 68),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title),
                  if (book.author.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(book.author, style: theme.textTheme.bodySmall),
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
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${review.content.characters.length} 字',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            SelectableText(
              content,
              key: const ValueKey<String>('review-detail-content'),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.75),
            ),
          ],
        ),
        actions: [SizedBox(width: double.infinity, child: _actions(context))],
      ),
    );
  }

  Widget _actions(BuildContext context) => LayoutBuilder(
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
            color: Theme.of(context).colorScheme.onSurface,
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
    final discard = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
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
    final confirmed = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
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
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              widget.book.title,
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
                color: theme.colorScheme.onSurface,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ratingPicker(theme),
        const SizedBox(height: 16),
        _contentInput(theme),
      ],
    );
  }

  Widget _actions() => _ReviewEditorActions(
    isEditing: widget.review != null,
    canSave: _canSave,
    onSave: _save,
    onDelete: _delete,
    onClose: _close,
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
      type: MaterialType.transparency,
      child: ReaderSheetForm(
        title: _heading(Theme.of(context)),
        showCloseButton: false,
        content: _content(context),
        actions: [SizedBox(width: double.infinity, child: _actions())],
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
    required this.onClose,
    required this.saving,
    required this.error,
  });

  final bool isEditing;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final VoidCallback onClose;
  final bool saving;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
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
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey<String>('review-cancel'),
          onPressed: saving ? null : onClose,
          child: const Text('取消'),
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
