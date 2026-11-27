import 'package:flutter/material.dart';
import 'package:reader_ui/theme/app_semantic_colors.dart';
import 'package:reader_ui/theme/reader_common_widgets.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../diagnostics/reader_log.dart';
import '../library/book_list_store.dart';
import '../library/library_store.dart';
import 'book_cover_image.dart';

/// 打开某本书的书单归属选择，可直接加入或移出已有书单。
Future<void> showBookListMembership(
  BuildContext context, {
  required LibraryStore library,
  required String bookId,
}) => showReaderDrawer<void>(
  context: context,
  builder: (_) => _BookMembershipSheet(library: library, bookId: bookId),
);

/// 笔记页的书单标签：书单卡片、详情、添加书籍与名称简介编辑。
class BookListsView extends StatefulWidget {
  /// 创建书单视图。
  const BookListsView({
    super.key,
    required this.library,
    this.active = true,
    this.query = '',
  });

  /// 书架存储。
  final LibraryStore library;

  /// 当前标签是否可见；重新显示时读取最新书单。
  final bool active;

  /// 名称、简介与书名的搜索词。
  final String query;

  @override
  State<BookListsView> createState() => _BookListsViewState();
}

class _BookListsViewState extends State<BookListsView> {
  BookListStore get _store => widget.library.bookListStore();

  List<BookList>? _bookLists;
  Map<String, BookEntry> _books = const <String, BookEntry>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(BookListsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library != widget.library ||
        (!oldWidget.active && widget.active)) {
      _reload();
    }
  }

  Future<void> _reload() async {
    try {
      final books = <BookEntry>[
        ...await widget.library.list(),
        // 已移除的书籍仍保留在书单中。
        ...await widget.library.retainedBooks(),
      ];
      final bookLists = List<BookList>.of(await _store.list())
        ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      if (!mounted) return;
      setState(() {
        _books = <String, BookEntry>{
          for (final book in books) book.id: book,
        };
        _bookLists = bookLists;
        _error = null;
      });
    } catch (error, stackTrace) {
      recordAppError('book_lists_reload_failed', error, stackTrace: stackTrace);
      if (mounted && _bookLists == null) {
        setState(() => _error = '书单加载失败，请重试');
      }
    }
  }

  Future<void> _create() async {
    if (!mounted) return;
    final draft = await _showBookListEditor(context);
    if (draft == null) return;
    try {
      await _store.create(name: draft.name, description: draft.description);
      await _reload();
    } catch (error, stackTrace) {
      recordAppError(
        'book_list_create_failed',
        error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _open(BookList bookList) async {
    await showReaderDrawer<void>(
      context: context,
      builder: (_) =>
          _BookListDetailSheet(library: widget.library, initial: bookList),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final bookLists = _bookLists;
    if (bookLists == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : _LoadError(message: _error!, onRetry: _reload);
    }
    if (bookLists.isEmpty) return _EmptyBookLists(onCreate: _create);
    final needle = widget.query.trim().toLowerCase();
    final visible = needle.isEmpty
        ? bookLists
        : [
            for (final bookList in bookLists)
              if (bookList.name.toLowerCase().contains(needle) ||
                  bookList.description.toLowerCase().contains(needle) ||
                  _resolve(
                    bookList,
                  ).any((book) => book.title.toLowerCase().contains(needle)))
                bookList,
          ];
    if (visible.isEmpty) {
      return _NoBookListMatches(query: widget.query.trim());
    }
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _reload,
          child: ListView.builder(
            key: const ValueKey<String>('booklists-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 76),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final bookList = visible[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _BookListCard(
                  bookList: bookList,
                  books: _resolve(bookList),
                  onTap: () => _open(bookList),
                ),
              );
            },
          ),
        ),
        Positioned(
          right: 16,
          bottom: 12,
          child: FloatingActionButton.small(
            key: const ValueKey<String>('booklist-create'),
            tooltip: '新建书单',
            shape: ReaderUiStyle.controlShape,
            onPressed: _create,
            child: const AppIcon(AppGlyph.add),
          ),
        ),
      ],
    );
  }

  List<BookEntry> _resolve(BookList bookList) => <BookEntry>[
    for (final id in bookList.bookIds) ?_books[id],
  ];
}

/// 书单卡片：左侧标题/简介与底栏元信息，右侧柔和展台与立体扇形书封堆叠。
class _BookListCard extends StatelessWidget {
  const _BookListCard({
    required this.bookList,
    required this.books,
    required this.onTap,
  });

  final BookList bookList;
  final List<BookEntry> books;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final covers = books.take(3).toList(growable: false);
    final description = bookList.description.trim();
    return Material(
      color: scheme.surface,
      shape: ReaderUiStyle.cardShapeOf(theme),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: GestureDetector(
          key: ValueKey<String>('booklist-card-${bookList.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 146),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 3,
                                    height: 16,
                                    margin: const EdgeInsets.only(
                                      top: 3,
                                      right: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.primary,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      bookList.name,
                                      key: ValueKey<String>(
                                        'booklist-card-name-${bookList.id}',
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            height: 1.3,
                                            color: scheme.onSurface,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.only(left: 11),
                                  child: Text(
                                    description,
                                    key: ValueKey<String>(
                                      'booklist-card-description-${bookList.id}',
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 12.5,
                                      color: scheme.onSurfaceVariant,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppIcon(
                                      AppGlyph.bookshelf,
                                      size: 13,
                                      color: scheme.primary,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${books.length} 本书',
                                      key: ValueKey<String>(
                                        'booklist-card-count-${bookList.id}',
                                      ),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurface,
                                            fontWeight: FontWeight.w500,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _formatCreatedDate(bookList.createdAt),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: .8,
                                  ),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (covers.isNotEmpty)
                    Container(
                      width: 138,
                      padding: const EdgeInsets.fromLTRB(8, 14, 14, 14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow.withValues(
                          alpha: .65,
                        ),
                        border: Border(
                          left: BorderSide(
                            color: scheme.outlineVariant.withValues(alpha: .7),
                          ),
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.center,
                        child: _CoverStack(
                          books: covers,
                          keyPrefix: bookList.id,
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Center(
                        child: AppIcon(
                          AppGlyph.chevronRight,
                          size: 18,
                          color: scheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatCreatedDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    final now = DateTime.now();
    if (local.year == now.year) {
      return '${local.month}月${local.day}日';
    }
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }
}

/// 右侧书封展台：最多三本，居中对称扇形叠压，前后错落且带书框描边与轻阴影。
class _CoverStack extends StatelessWidget {
  const _CoverStack({required this.books, required this.keyPrefix});

  final List<BookEntry> books;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = AppSemanticColors.of(context);
    const coverWidth = 58.0;
    const coverHeight = 78.0;
    final count = books.length;
    final step = count == 1 ? 0.0 : (count == 2 ? 28.0 : 25.0);
    final totalWidth = coverWidth + step * (count - 1);
    return SizedBox(
      width: totalWidth,
      height: coverHeight + 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var index = count - 1; index >= 0; index--)
            _coverItem(
              context,
              book: books[index],
              index: index,
              count: count,
              step: step,
              coverWidth: coverWidth,
              coverHeight: coverHeight,
              borderColor: semantics.bookCoverBorder,
              shadowColor: scheme.shadow,
              isLight: theme.brightness == Brightness.light,
            ),
        ],
      ),
    );
  }

  Widget _coverItem(
    BuildContext context, {
    required BookEntry book,
    required int index,
    required int count,
    required double step,
    required double coverWidth,
    required double coverHeight,
    required Color borderColor,
    required Color shadowColor,
    required bool isLight,
  }) {
    final double angle;
    final double topOffset;
    if (count == 1) {
      angle = 0;
      topOffset = 7;
    } else if (count == 2) {
      angle = index == 0 ? -0.05 : 0.06;
      topOffset = index == 0 ? 5 : 9;
    } else {
      angle = switch (index) {
        0 => -0.06,
        1 => 0.0,
        _ => 0.07,
      };
      topOffset = switch (index) {
        0 => 4,
        1 => 7,
        _ => 11,
      };
    }
    return Positioned(
      left: step * index,
      top: topOffset,
      child: Transform.rotate(
        angle: angle,
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: borderColor),
            boxShadow: isLight
                ? [
                    BoxShadow(
                      color: shadowColor.withValues(alpha: .12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: BookCoverImage(
              key: ValueKey<String>('booklist-cover-$keyPrefix-${book.id}'),
              book: book,
              width: coverWidth,
              height: coverHeight,
              showShadow: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoBookListMatches extends StatelessWidget {
  const _NoBookListMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) => ReaderEmptyState(
    icon: AppGlyph.searchOff,
    title: '没有找到相关书单',
    subtitle: '没有名称、简介或书名包含“$query”',
  );
}

class _EmptyBookLists extends StatelessWidget {
  const _EmptyBookLists({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => ReaderEmptyState(
    icon: AppGlyph.bookmarkAdd,
    title: '还没有书单',
    subtitle: '把想一起读的书收进书单，写下名称和简介',
    action: FilledButton.icon(
      key: const ValueKey<String>('booklist-create-empty'),
      onPressed: onCreate,
      icon: const AppIcon(AppGlyph.add, size: 18),
      label: const Text('新建书单'),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ReaderEmptyState(
      icon: AppGlyph.warning,
      iconColor: colors.error,
      iconContainerColor: colors.errorContainer,
      title: message,
      action: FilledButton.icon(
        key: const ValueKey<String>('booklists-load-retry'),
        onPressed: onRetry,
        icon: const AppIcon(AppGlyph.refresh, size: 18),
        label: const Text('重新加载'),
      ),
    );
  }
}

/// 书单详情：书籍列表、添加或移除书籍、编辑名称简介与删除书单。
class _BookListDetailSheet extends StatefulWidget {
  const _BookListDetailSheet({
    required this.library,
    required this.initial,
  });

  final LibraryStore library;
  final BookList initial;

  @override
  State<_BookListDetailSheet> createState() => _BookListDetailSheetState();
}

class _BookListDetailSheetState extends State<_BookListDetailSheet> {
  late BookList _bookList = widget.initial;
  Map<String, BookEntry> _books = const <String, BookEntry>{};
  bool _loading = true;
  bool _busy = false;

  BookListStore get _store => widget.library.bookListStore();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final books = <BookEntry>[
        ...await widget.library.list(),
        // 已移除的书籍仍保留在书单中。
        ...await widget.library.retainedBooks(),
      ];
      final bookLists = await _store.list();
      if (!mounted) return;
      setState(() {
        _books = <String, BookEntry>{
          for (final book in books) book.id: book,
        };
        _bookList = bookLists
            .where((bookList) => bookList.id == _bookList.id)
            .firstOrNull ??
            _bookList;
        _loading = false;
      });
    } catch (error, stackTrace) {
      recordAppError(
        'book_list_detail_load_failed',
        error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _loading = false);
    }
  }

  List<BookEntry> get _entries => <BookEntry>[
    for (final id in _bookList.bookIds) ?_books[id],
  ];

  Future<void> _edit() async {
    final draft = await _showBookListEditor(context, initial: _bookList);
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _store.update(
        _bookList.id,
        name: draft.name,
        description: draft.description,
      );
      await _reload();
    } catch (error, stackTrace) {
      recordAppError('book_list_update_failed', error, stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addBooks() async {
    // 选择器只列书架上的书；已移除的书籍仍保留在 selected 里，不会被移出。
    final books = (await widget.library.list()).toList()
      ..sort((left, right) => left.title.compareTo(right.title));
    if (!mounted) return;
    final selected = await showReaderDrawer<Set<String>>(
      context: context,
      builder: (_) => _BookPickerSheet(
        books: books,
        selected: _bookList.bookIds.toSet(),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _store.setBooks(_bookList.id, selected);
      await _reload();
    } catch (error, stackTrace) {
      recordAppError('book_list_set_books_failed', error, stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeBook(BookEntry entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _store.removeBook(_bookList.id, entry.id);
      await _reload();
    } catch (error, stackTrace) {
      recordAppError(
        'book_list_remove_book_failed',
        error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showReaderConfirmDialog(
      context: context,
      title: '删除书单「${_bookList.name}」？',
      message: '只删除书单，书籍仍保留在书架。',
      confirmLabel: '删除',
      confirmKey: const ValueKey<String>('booklist-delete-confirm'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _store.delete(_bookList.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error, stackTrace) {
      recordAppError('book_list_delete_failed', error, stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = AppSemanticColors.of(context);
    final entries = _entries;
    final description = _bookList.description.trim();
    return Material(
      key: const ValueKey<String>('booklist-detail'),
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: ReaderSheetForm(
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _bookList.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${entries.length} 本书',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '创建于 ${_BookListCard._formatCreatedDate(_bookList.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey<String>('booklist-detail-edit'),
                tooltip: '编辑名称和简介',
                color: scheme.onSurfaceVariant,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: _busy ? null : _edit,
                icon: const AppIcon(AppGlyph.edit, size: 20),
              ),
            ],
          ),
          content: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (description.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: ReaderUiStyle.controlRadius,
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: .75),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 3,
                              height: 16,
                              margin: const EdgeInsets.only(top: 3, right: 10),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                description,
                                key: const ValueKey<String>(
                                  'booklist-detail-description',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.55,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        Text(
                          '收录书籍',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (entries.isNotEmpty)
                          Text(
                            '共 ${entries.length} 本',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (entries.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 28,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: ReaderUiStyle.controlRadius,
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: .75),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(
                              AppGlyph.bookshelf,
                              size: 28,
                              color: scheme.outline,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '还没有加入书籍',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '点击下方「添加书籍」从书架挑选收进此书单',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: .8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(16),
                          ),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: .8),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < entries.length; i++) ...[
                              if (i > 0)
                                Divider(
                                  height: 1,
                                  indent: 70,
                                  endIndent: 14,
                                  color: scheme.outlineVariant.withValues(
                                    alpha: .7,
                                  ),
                                ),
                              _bookRow(context, entries[i], semantics),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: Row(
                children: [
                  TextButton.icon(
                    key: const ValueKey<String>('booklist-detail-delete'),
                    onPressed: _busy ? null : _delete,
                    icon: const AppIcon(AppGlyph.delete, size: 18),
                    label: const Text('删除书单'),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.error,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey<String>('booklist-detail-add'),
                      onPressed: _busy ? null : _addBooks,
                      icon: const AppIcon(AppGlyph.add, size: 18),
                      label: const Text('添加书籍'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookRow(
    BuildContext context,
    BookEntry entry,
    AppSemanticColors semantics,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: ValueKey<String>('booklist-book-${entry.id}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: semantics.bookCoverBorder),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: BookCoverImage(book: entry, width: 44, height: 60),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.author.trim().isEmpty ? '佚名' : entry.author.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: ValueKey<String>('booklist-book-remove-${entry.id}'),
            tooltip: '移出书单',
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            padding: EdgeInsets.zero,
            color: scheme.onSurfaceVariant,
            onPressed: _busy ? null : () => _removeBook(entry),
            icon: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: AppIcon(
                AppGlyph.close,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 从书架多选书籍；返回选中的书籍 id 集合。
class _BookPickerSheet extends StatefulWidget {
  const _BookPickerSheet({required this.books, required this.selected});

  final List<BookEntry> books;
  final Set<String> selected;

  @override
  State<_BookPickerSheet> createState() => _BookPickerSheetState();
}

class _BookPickerSheetState extends State<_BookPickerSheet> {
  late final Set<String> _selected = Set<String>.of(widget.selected);
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = AppSemanticColors.of(context);
    final query = _query.trim().toLowerCase();
    final visible = <BookEntry>[
      for (final book in widget.books)
        if (query.isEmpty ||
            book.title.toLowerCase().contains(query) ||
            book.author.toLowerCase().contains(query))
          book,
    ];
    return Material(
      type: MaterialType.transparency,
      child: ReaderSheetForm(
        title: Row(
          children: [
            const Text('添加书籍'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '已选 ${_selected.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        scrollContent: false,
        content: SizedBox(
          height: MediaQuery.sizeOf(context).height * .56,
          child: Column(
            children: [
              ReaderSearchField(
                fieldKey: const ValueKey<String>('booklist-picker-search'),
                controller: _searchController,
                hintText: '搜索书名或作者',
                onChanged: (value) => setState(() => _query = value),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const AppIcon(AppGlyph.close, size: 18),
                      ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: visible.isEmpty
                    ? const ReaderEmptyState(
                        icon: AppGlyph.searchOff,
                        title: '没有匹配的书籍',
                      )
                    : ListView.separated(
                        key: const ValueKey<String>('booklist-picker-list'),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final book = visible[index];
                          final checked = _selected.contains(book.id);
                          return Material(
                            color: checked
                                ? scheme.primaryContainer.withValues(alpha: .45)
                                : scheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: ReaderUiStyle.controlRadius,
                              side: BorderSide(
                                color: checked
                                    ? scheme.primary.withValues(alpha: .5)
                                    : scheme.outlineVariant.withValues(
                                        alpha: .75,
                                      ),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: CheckboxListTile(
                              key: ValueKey<String>(
                                'booklist-picker-${book.id}',
                              ),
                              contentPadding: const EdgeInsets.fromLTRB(
                                10,
                                4,
                                6,
                                4,
                              ),
                              secondary: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: semantics.bookCoverBorder,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: BookCoverImage(
                                    book: book,
                                    width: 36,
                                    height: 48,
                                  ),
                                ),
                              ),
                              value: checked,
                              title: Text(
                                book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: checked
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              subtitle: Text(
                                book.author.trim().isEmpty
                                    ? '佚名'
                                    : book.author.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onChanged: (value) => setState(() {
                                if (value == true) {
                                  _selected.add(book.id);
                                } else {
                                  _selected.remove(book.id);
                                }
                              }),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>('booklist-picker-confirm'),
            onPressed: () => Navigator.of(context).pop(_selected),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 单本书的书单归属：勾选即加入或移出，可现场新建书单。
class _BookMembershipSheet extends StatefulWidget {
  const _BookMembershipSheet({required this.library, required this.bookId});

  final LibraryStore library;
  final String bookId;

  @override
  State<_BookMembershipSheet> createState() => _BookMembershipSheetState();
}

class _BookMembershipSheetState extends State<_BookMembershipSheet> {
  BookListStore get _store => widget.library.bookListStore();

  List<BookList> _bookLists = const <BookList>[];
  Set<String> _memberIds = const <String>{};
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final bookLists = List<BookList>.of(await _store.list())
        ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      final memberIds = await _store.listIdsForBook(widget.bookId);
      if (!mounted) return;
      setState(() {
        _bookLists = bookLists;
        _memberIds = memberIds;
        _loading = false;
      });
    } catch (error, stackTrace) {
      recordAppError(
        'book_list_membership_load_failed',
        error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(BookList bookList, bool selected) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (selected) {
        await _store.addBooks(bookList.id, <String>[widget.bookId]);
      } else {
        await _store.removeBook(bookList.id, widget.bookId);
      }
      await _reload();
    } catch (error, stackTrace) {
      recordAppError(
        'book_list_membership_update_failed',
        error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final draft = await _showBookListEditor(context);
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final created = await _store.create(
        name: draft.name,
        description: draft.description,
      );
      await _store.addBooks(created.id, <String>[widget.bookId]);
      await _reload();
    } catch (error, stackTrace) {
      recordAppError(
        'book_list_membership_create_failed',
        error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: const ValueKey<String>('booklist-membership'),
      type: MaterialType.transparency,
      child: ReaderSheetForm(
        title: const Text('加入书单'),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        content: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_bookLists.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: ReaderUiStyle.controlRadius,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Text(
                        '还没有书单，先新建一个',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < _bookLists.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final bookList = _bookLists[i];
                          final joined = _memberIds.contains(bookList.id);
                          return Material(
                            color: joined
                                ? scheme.primaryContainer.withValues(alpha: .45)
                                : scheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: ReaderUiStyle.controlRadius,
                              side: BorderSide(
                                color: joined
                                    ? scheme.primary.withValues(alpha: .5)
                                    : scheme.outlineVariant.withValues(
                                        alpha: .75,
                                      ),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: CheckboxListTile(
                              key: ValueKey<String>(
                                'booklist-membership-${bookList.id}',
                              ),
                              contentPadding: const EdgeInsets.fromLTRB(
                                14,
                                2,
                                8,
                                2,
                              ),
                              value: joined,
                              title: Text(
                                bookList.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: joined
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              subtitle: Text('${bookList.bookIds.length} 本书'),
                              onChanged: _busy
                                  ? null
                                  : (value) => _toggle(bookList, value ?? false),
                            ),
                          );
                        },
                      ),
                    ],
                ],
              ),
        actions: [
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const AppIcon(AppGlyph.add, size: 18),
            label: const Text('新建书单'),
          ),
        ],
      ),
    );
  }
}

/// 编辑书单名称与简介；返回空表示取消。
Future<({String name, String description})?> _showBookListEditor(
  BuildContext context, {
  BookList? initial,
}) => showReaderDrawer<({String name, String description})>(
  context: context,
  builder: (_) => _BookListEditorSheet(initial: initial),
);

class _BookListEditorSheet extends StatefulWidget {
  const _BookListEditorSheet({this.initial});

  final BookList? initial;

  @override
  State<_BookListEditorSheet> createState() => _BookListEditorSheetState();
}

class _BookListEditorSheetState extends State<_BookListEditorSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.initial?.description ?? '',
  );

  bool get _canSave => _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: ReaderSheetForm(
        title: Text(widget.initial == null ? '新建书单' : '编辑书单'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey<String>('booklist-editor-name'),
              controller: _name,
              autofocus: true,
              maxLength: BookList.maxNameLength,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: '名称'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              key: const ValueKey<String>('booklist-editor-description'),
              controller: _description,
              maxLength: BookList.maxDescriptionLength,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '简介（可选）',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '简介显示在书单卡片上，方便找到想读的那一组。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>('booklist-editor-save'),
            onPressed: _canSave
                ? () => Navigator.of(context).pop((
                    name: _name.text.trim(),
                    description: _description.text.trim(),
                  ))
                : null,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
