import 'package:reader_ui/rating/reader_rating.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:flutter/services.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_drawer_style.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../library/library_store.dart';
import '../rea_micro/rea_micro_controller.dart';
import '../rea_micro/rea_micro_annotation_cfi.dart';
import '../rea_micro/rea_micro_models.dart';
import '../storage/book_review_store.dart';
import 'book_cover_image.dart';
import 'book_lists_view.dart';
import 'book_notes_list.dart';
import 'desktop_layout.dart';
import 'review_ticket.dart';
import 'reviews_cloud.dart';
import '../diagnostics/reader_log.dart';

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
  double _dragDx = 0;
  List<BookEntry>? _books;
  final _loadedSections = <int>{};
  Map<String, BookNoteCounts> _counts = const {};
  Map<String, Duration> _durations = const {};
  Map<String, int> _readDays = const {};
  Map<String, ({int cloudBookId, int bookId, bool published})>
  _cloudReviewTargets = const {};
  Set<String> _cloudFinishedBooks = const {};
  Map<String, int> _cloudReviewRatings = const {};
  Set<String>? _noteSearchMatches;
  int _noteSearchRequest = 0;
  Map<String, BookReview> _reviews = const <String, BookReview>{};
  Set<String> _finishedBooks = const {};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _keyboardFocus = FocusNode();
  _ReviewSort _sort = _ReviewSort.updated;
  bool _searching = false;
  bool _inlineSearchAvailable = false;
  String _query = '';
  int _reloadToken = 0;
  int _editToken = 0;
  String? _error;
  String? _cloudError;
  bool _signedIn = false;
  Map<String, ({int cloudBookId, int bookId})> _cloudMarkBooks = const {};

  bool get _notes => _section == 0;

  bool get _bookListsTab => _section == 2;

  BookReviewStore? get _store =>
      widget.reviewStore ?? widget.library.reviewStore();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)..addListener(_changeSection);
    widget.library.addListener(_onLibraryChanged);
    widget.reaMicro?.addListener(_onReaMicroChanged);
    _signedIn = widget.reaMicro?.signedIn ?? false;
    if (widget.active && !_bookListsTab) _reload();
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
      _loadedSections.clear();
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
      _tabs.animateTo(_section + 1);
    } else if (previous && _section > 0) {
      _tabs.animateTo(_section - 1);
    }
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
    if (_inlineSearchAvailable && !_searching) {
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
    _searchChanged('');
  }

  void _searchChanged(String value) {
    final request = ++_noteSearchRequest;
    setState(() {
      _query = value;
      _noteSearchMatches = null;
    });
    if (!_notes || value.trim().isEmpty) return;
    unawaited(_searchNotes(value.trim().toLowerCase(), request));
  }

  Future<void> _searchNotes(String query, int request) async {
    final matches = <String>{};
    for (final book in _books ?? const <BookEntry>[]) {
      if (!mounted || request != _noteSearchRequest || !_notes) return;
      if (book.title.toLowerCase().contains(query) ||
          book.author.toLowerCase().contains(query)) {
        matches.add(book.id);
        continue;
      }
      if ((_counts[book.id]?.thoughts ?? 0) + (_counts[book.id]?.marks ?? 0) ==
          0) {
        continue;
      }
      try {
        final notes = await _loadNotes(book.id);
        if (notes.any(
          (note) =>
              note.quote.toLowerCase().contains(query) ||
              (note.note?.toLowerCase().contains(query) ?? false),
        )) {
          matches.add(book.id);
        }
      } catch (_) {
        // 单本笔记不可用时仍允许搜索其余书籍。
      }
    }
    if (mounted && request == _noteSearchRequest && _notes) {
      setState(() => _noteSearchMatches = matches);
    }
  }

  final _noteCloudIds = <String, Map<String, int>>{};

  bool _noteIsLocal(String bookId, ReaderAnnotation note) =>
      !(_noteCloudIds[bookId]?.containsKey(note.id) ?? false) &&
      !(widget.reaMicro?.annotationCloudIds(bookId).containsKey(note.id) ??
          false) &&
      !RegExp(r'^mark-(?:cloud|lan)-[1-9]\d*$').hasMatch(note.id);

  Future<void> _deleteNote(String bookId, ReaderAnnotation annotation) async {
    final controller = widget.reaMicro;
    final remote = _cloudMarkBooks[bookId];
    if (controller != null && controller.signedIn && remote != null) {
      final result = await controller.deleteNote(
        bookId,
        annotation,
        cloudId: _noteCloudIds[bookId]?[annotation.id],
      );
      if (!result.success) throw FormatException(result.message);
    } else {
      await widget.library.removeBookAnnotation(bookId, annotation.id);
    }
    await _reload();
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
    final token = ++_reloadToken;
    if (_bookListsTab) return;
    final library = widget.library;
    final section = _section;
    final notes = _notes;
    try {
      final books = <BookEntry>[
        ...await library.list(),
        // 软删除的书仍保留笔记和书单关联，继续在此页展示。
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
      var visibleBooks = books;
      var visibleCounts = counts;
      var visibleReviews = reviews;
      var visibleDurations = durations;
      var visibleReadDays = const <String, int>{};
      var targets =
          const <String, ({int cloudBookId, int bookId, bool published})>{};
      var cloudFinished = const <String>{};
      var cloudRatings = const <String, int>{};
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
                  controller.loadBookReview(
                    link.cloudBookId,
                    bookId: link.userBookId,
                  ),
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
            visibleReadDays = merge.readDays;
            targets = merge.targets;
            cloudFinished = merge.finishedBooks;
            cloudRatings = merge.ratings;
            for (final book in books) {
              final link = controller.links[book.id];
              if (link != null) {
                targets = {
                  ...targets,
                  book.id:
                      targets[book.id] ??
                      (
                        cloudBookId: link.cloudBookId,
                        bookId: link.userBookId,
                        published: false,
                      ),
                };
              }
            }
          }
        } catch (_) {
          cloudError = notes ? '阅微笔记读取失败，已显示本地笔记' : '阅微书评读取失败，已显示本地书评';
        }
      }
      if (mounted &&
          widget.active &&
          token == _reloadToken &&
          section == _section) {
        setState(() {
          _loadedSections.add(section);
          _books = visibleBooks;
          _finishedBooks = finished;
          _counts = notes ? visibleCounts : _counts;
          _reviews = notes ? _reviews : visibleReviews;
          _durations = notes ? _durations : visibleDurations;
          _readDays = notes ? _readDays : visibleReadDays;
          _cloudReviewTargets = notes ? _cloudReviewTargets : targets;
          _cloudFinishedBooks = notes ? _cloudFinishedBooks : cloudFinished;
          _cloudReviewRatings = notes ? _cloudReviewRatings : cloudRatings;
          _cloudMarkBooks = markBooks;
          _cloudError = cloudError;
          _error = null;
        });
      }
    } catch (error, stackTrace) {
      if (!mounted ||
          !widget.active ||
          token != _reloadToken ||
          section != _section) {
        return;
      }
      final label = notes ? '笔记' : '书评';
      if (!_loadedSections.contains(section)) {
        setState(() => _error = '$label加载失败，请重试');
      } else {
        recordAppError('reviews_reload_failed', error, stackTrace: stackTrace);
      }
    }
  }

  Future<void> _edit(BookEntry book) async {
    final store = _store;
    final cloud = _cloudReviewTargets[book.id];
    if (store == null && cloud == null) {
      recordAppEvent('review_store_unavailable');
      return;
    }
    final token = ++_editToken;
    final BookReview? review;
    try {
      final finished = await widget.library.finishedBookIds();
      if (!mounted || !widget.active || token != _editToken) return;
      if (!finished.contains(book.id) &&
          !_cloudFinishedBooks.contains(book.id)) {
        recordAppEvent('review_requires_finished_book');
        return;
      }
      review = cloud == null
          ? (await store!.snapshot())[book.id]
          : _reviews[book.id];
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
    BookReviewStore? store,
    BookReview? review,
  ) async {
    final draft = await _showPanel<_ReviewDraft>(
      (_) => _ReviewEditorSheet(
        book: book,
        review: review,
        cloud: _cloudReviewTargets.containsKey(book.id),
        published: _cloudReviewTargets[book.id]?.published ?? false,
        onCommit: (draft) async {
          final cloud = _cloudReviewTargets[book.id];
          if (cloud != null) {
            final controller = widget.reaMicro;
            if (controller == null || !controller.signedIn) {
              throw const FormatException('账号已退出，请重新登录后保存');
            }
            final rawRating = _cloudReviewRatings[book.id];
            final initialCloudRating = rawRating == null || rawRating == 0
                ? null
                : (rawRating / 2).clamp(.5, 5);
            final result = await controller.saveReview(
              cloudBookId: cloud.cloudBookId,
              bookId: cloud.bookId,
              rating:
                  (draft.delete ||
                      (draft.rating == review?.rating &&
                          draft.rating == initialCloudRating))
                  ? rawRating ?? ((review?.rating ?? 0) * 2).round()
                  : ((draft.rating ?? 0) * 2).round(),
              comment: draft.delete ? '' : draft.content,
              publish: !draft.delete && draft.publish,
            );
            if (!result.success) throw FormatException(result.message);
          }
          if (store != null &&
              (cloud == null || _finishedBooks.contains(book.id))) {
            if (draft.delete) {
              await store.remove(book.id);
            } else {
              await store.save(
                book.id,
                rating: draft.rating,
                content: draft.content,
              );
            }
          }
        },
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
        canEdit:
            _finishedBooks.contains(book.id) ||
            _cloudFinishedBooks.contains(book.id),
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

  Future<void> _chooseSort() async {
    final selected = await _showPanel<_ReviewSort>(
      (context) => ReaderSheetForm(
        title: const Text('书评排序'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final sort in _ReviewSort.values)
              ListTile(
                key: ValueKey<String>('reviews-sort-${sort.name}'),
                contentPadding: EdgeInsets.zero,
                leading: AppIcon(
                  sort == _sort
                      ? AppGlyph.radioChecked
                      : AppGlyph.radioUnchecked,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                title: Text(sort.label),
                selected: sort == _sort,
                selectedColor: Theme.of(context).colorScheme.onSurface,
                onTap: () => Navigator.of(context).pop(sort),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _sort = selected);
  }

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
        if (desktop && widget.active && !_bookListsTab)
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
                          child: _sectionBody(),
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
    final theme = Theme.of(context);
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
                                    child: TabBar(
                                      controller: _tabs,
                                      isScrollable: true,
                                      tabAlignment: TabAlignment.start,
                                      labelPadding: const EdgeInsets.only(
                                        right: 20,
                                      ),
                                      indicator: const BoxDecoration(),
                                      dividerColor: Colors.transparent,
                                      overlayColor:
                                          const WidgetStatePropertyAll(
                                            Colors.transparent,
                                          ),
                                      splashFactory: NoSplash.splashFactory,
                                      labelColor: theme.colorScheme.onSurface,
                                      unselectedLabelColor:
                                          theme.colorScheme.onSurface,
                                      labelStyle: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w600,
                                          ),
                                      unselectedLabelStyle: theme
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(fontSize: 14),
                                      tabs: const [
                                        Tab(
                                          key: ValueKey('notes-tab'),
                                          text: '笔记',
                                        ),
                                        Tab(
                                          key: ValueKey('reviews-tab'),
                                          text: '书评',
                                        ),
                                        Tab(
                                          key: ValueKey('booklists-tab'),
                                          text: '书单',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (inlineSearch)
                                SizedBox(width: 300, child: _searchField()),
                              if (!_bookListsTab &&
                                  !_notes &&
                                  _books?.isNotEmpty == true)
                                IconButton(
                                  key: const ValueKey('reviews-sort'),
                                  tooltip: '书评排序',
                                  onPressed: _chooseSort,
                                  icon: const AppIcon(AppGlyph.sort),
                                ),
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
                                      data: theme,
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
                            : IconButton(
                                key: const ValueKey('reviews-search-button'),
                                tooltip: _bookListsTab
                                    ? '搜索书单'
                                    : _notes
                                    ? '搜索笔记'
                                    : '搜索书评',
                                onPressed: _toggleSearch,
                                icon: const AppIcon(AppGlyph.search),
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

  Widget _searchField() {
    final theme = Theme.of(context);
    final muted = ReaderDrawerStyle.mutedOf(theme);
    final border = OutlineInputBorder(
      borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
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
          hintText: _bookListsTab
              ? '搜索书单名称、简介或书名'
              : _notes
              ? '搜索书名、作者或笔记'
              : '搜索书名、作者或书评',
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
              : IconButton(
                  tooltip: '清除搜索',
                  onPressed: _clearSearch,
                  icon: AppIcon(AppGlyph.close, color: muted),
                ),
        ),
        onChanged: _searchChanged,
      ),
    );
  }

  Future<List<ReaderAnnotation>> _loadNotes(String bookId) async {
    final local = await widget.library.listBookAnnotations(bookId);
    _noteCloudIds[bookId] = {};
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
      final book = await widget.library.bookById(bookId);
      final cfis = local.isEmpty || book == null || book.filePath.isEmpty
          ? null
          : await ReaMicroAnnotationCfis.load(
              book.filePath,
              local: local.expand((mark) => [mark.startCfi, mark.endCfi]),
              remote: cloud.expand((mark) => [mark.startCfi, mark.endCfi]),
            );
      return mergeCloudMarks(
        local,
        cloud,
        cloudIds: controller.annotationCloudIds(bookId),
        resolvedCloudIds: _noteCloudIds[bookId],
        cfis: cfis,
      );
    } catch (_) {
      return local;
    }
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
    if (books == null || !_loadedSections.contains(_section)) {
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
        query: _query,
        searchMatches: _noteSearchMatches ?? const {},
        onDelete: _deleteNote,
        isLocal: _noteIsLocal,
      );
    } else if (books.isEmpty) {
      body = const _EmptyReviews();
    } else {
      body = RefreshIndicator(
        onRefresh: _reload,
        child: _ReviewList(
          books: books,
          finishedBooks: {..._finishedBooks, ..._cloudFinishedBooks},
          reviews: _reviews,
          durations: _durations,
          readDays: _readDays,
          query: _query,
          sort: _sort,
          onResetSearch: _resetSearch,
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
              child: RepaintBoundary(child: child),
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
    required this.readDays,
    required this.query,
    required this.sort,
    required this.onResetSearch,
    required this.onOpen,
    required this.onEdit,
  });

  final List<BookEntry> books;
  final Set<String> finishedBooks;
  final Map<String, BookReview> reviews;
  final Map<String, Duration> durations;
  final Map<String, int> readDays;
  final String query;
  final _ReviewSort sort;
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

    final allReviewed = <BookEntry>[
      for (final book in books)
        if (reviews[book.id]?.content.trim().isNotEmpty ?? false) book,
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
        if ((finishedBooks.contains(book.id) || reviews[book.id] != null) &&
            !(reviews[book.id]?.content.trim().isNotEmpty ?? false) &&
            matches(book))
          book,
    ];
    final pendingCount = books
        .where(
          (book) =>
              (finishedBooks.contains(book.id) || reviews[book.id] != null) &&
              !(reviews[book.id]?.content.trim().isNotEmpty ?? false),
        )
        .length;
    if (sort == _ReviewSort.title) {
      pending.sort(
        (left, right) =>
            left.title.toLowerCase().compareTo(right.title.toLowerCase()),
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _ReviewSummary(
          reviewed: allReviewed.length,
          total: allReviewed.length + pendingCount,
          reviews: reviews,
        ),
        const SizedBox(height: 10),
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
          'review-${review?.content.trim().isNotEmpty == true ? 'card' : 'pending'}-${book.id}',
        ),
        book: book,
        review: review,
        duration: durations[book.id],
        readDays: readDays[book.id],
        onTap:
            review == null ||
                (review.content.trim().isEmpty &&
                    finishedBooks.contains(book.id))
            ? () => onEdit(book)
            : () => onOpen(book, review),
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

  final num? rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReaderRatingStars(rating: rating, size: size),
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
        borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
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
    this.cloud = false,
    this.published = false,
  });

  final BookEntry book;
  final BookReview? review;
  final Future<void> Function(_ReviewDraft draft) onCommit;
  final bool cloud;
  final bool published;

  @override
  State<_ReviewEditorSheet> createState() => _ReviewEditorSheetState();
}

class _ReviewEditorSheetState extends State<_ReviewEditorSheet> {
  late final TextEditingController _controller;
  late final num? _initialRating;
  late final String _initialContent;
  num? _rating;
  late bool _publish;
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
    _publish = widget.published;
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
      (widget.cloud && _publish != widget.published) ||
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
      _ReviewDraft(
        rating: _rating,
        content: _controller.text.trim(),
        publish: _publish,
      ),
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
        content: Text(
          widget.cloud ? '书评正文会从阅微删除，保留评分与读完状态。' : '评分和正文都会删除，且不可恢复。',
        ),
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

  Widget _ratingPicker(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('评分（可选）', style: theme.textTheme.labelLarge),
      const SizedBox(height: 6),
      ReaderRatingPicker(
        rating: _rating,
        keyPrefix: 'review-rating',
        onChanged: _saving
            ? null
            : (value) => setState(() {
                _rating = value;
                _error = null;
              }),
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
        maxLength: widget.cloud ? 2000 : BookReview.maxContentLength,
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
        if (widget.cloud)
          ReaderSwitchListTile(
            key: const ValueKey('review-publish'),
            contentPadding: EdgeInsets.zero,
            title: const Text('发布到阅微'),
            value: _publish,
            onChanged: _saving
                ? null
                : (value) => setState(() => _publish = value),
          ),
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
    publish: widget.cloud && _publish,
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
    this.publish = false,
  });

  final bool isEditing;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final VoidCallback onClose;
  final bool saving;
  final String? error;
  final bool publish;

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
          label: Text(
            saving
                ? '正在保存…'
                : publish
                ? '发布书评'
                : '保存书评',
          ),
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
  const _ReviewDraft({this.rating, this.content = '', this.publish = false})
    : delete = false;

  const _ReviewDraft.delete()
    : rating = null,
      content = '',
      delete = true,
      publish = false;

  final num? rating;
  final String content;
  final bool delete;
  final bool publish;
}

String _reviewDate(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
