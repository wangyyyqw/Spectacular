import 'dart:math' as math;

import 'package:flutter/material.dart';
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
  });

  /// 书架存储。
  final LibraryStore library;

  /// 当前标签是否可见；重新显示时读取最新书单。
  final bool active;

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
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _reload,
          child: ListView.builder(
            key: const ValueKey<String>('booklists-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 76),
            itemCount: bookLists.length,
            itemBuilder: (context, index) {
              final bookList = bookLists[index];
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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

/// 书单卡片：大标题、简介、右侧堆叠封面与书籍数量。
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('booklist-card-${bookList.id}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 148),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  covers.isEmpty ? 18 : 128,
                  44,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bookList.name,
                      key: ValueKey<String>('booklist-card-name-${bookList.id}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description,
                        key: ValueKey<String>(
                          'booklist-card-description-${bookList.id}',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 18,
                bottom: 14,
                child: Text(
                  '${books.length} 本书',
                  key: ValueKey<String>('booklist-card-count-${bookList.id}'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: .3,
                  ),
                ),
              ),
              if (covers.isNotEmpty)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: _CoverStack(
                    books: covers,
                    keyPrefix: bookList.id,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 右侧书封：最多三本，轻微旋转并相互叠压。
class _CoverStack extends StatelessWidget {
  const _CoverStack({required this.books, required this.keyPrefix});

  final List<BookEntry> books;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    const slot = 30.0;
    return SizedBox(
      width: slot * (books.length - 1) + 62,
      height: 90,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (index, book) in books.indexed)
            Positioned(
              left: slot * index,
              top: index.isOdd ? 2 : 6,
              child: Transform.rotate(
                angle: index == 0 ? -math.pi / 48 : math.pi / 72,
                alignment: Alignment.bottomCenter,
                child: BookCoverImage(
                  key: ValueKey<String>('booklist-cover-$keyPrefix-${book.id}'),
                  book: book,
                  width: 62,
                  height: 82,
                  showShadow: true,
                  shadowOpacity: .18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyBookLists extends StatelessWidget {
  const _EmptyBookLists({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              AppGlyph.bookmarkAdd,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('还没有书单', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '把想一起读的书收进书单，写下名称和简介',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey<String>('booklist-create-empty'),
              onPressed: onCreate,
              icon: const AppIcon(AppGlyph.add),
              label: const Text('新建书单'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

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
            key: const ValueKey<String>('booklists-load-retry'),
            onPressed: onRetry,
            icon: const AppIcon(AppGlyph.refresh),
            label: const Text('重新加载'),
          ),
        ],
      ),
    ),
  );
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
    final confirmed = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: Text('删除书单「${_bookList.name}」？'),
        content: const Text('只删除书单，书籍仍保留在书架。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>('booklist-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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
    final entries = _entries;
    final description = _bookList.description.trim();
    return Material(
      key: const ValueKey<String>('booklist-detail'),
      type: MaterialType.transparency,
      child: ReaderSheetForm(
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_bookList.name),
                  const SizedBox(height: 3),
                  Text(
                    '${entries.length} 本书',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey<String>('booklist-detail-edit'),
              tooltip: '编辑名称和简介',
              onPressed: _busy ? null : _edit,
              icon: const AppIcon(AppGlyph.edit),
            ),
          ],
        ),
        content: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (description.isNotEmpty) ...[
                    Text(
                      description,
                      key: const ValueKey<String>(
                        'booklist-detail-description',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.6,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  OutlinedButton.icon(
                    key: const ValueKey<String>('booklist-detail-add'),
                    onPressed: _busy ? null : _addBooks,
                    icon: const AppIcon(AppGlyph.add),
                    label: const Text('添加书籍'),
                  ),
                  const SizedBox(height: 8),
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        '还没有加入书籍',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final entry in entries)
                      ListTile(
                        key: ValueKey<String>('booklist-book-${entry.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: BookCoverImage(
                          book: entry,
                          width: 40,
                          height: 54,
                        ),
                        title: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          entry.author.isEmpty ? '未知作者' : entry.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          key: ValueKey<String>(
                            'booklist-book-remove-${entry.id}',
                          ),
                          tooltip: '移出书单',
                          onPressed: _busy ? null : () => _removeBook(entry),
                          icon: const AppIcon(AppGlyph.close),
                        ),
                      ),
                ],
              ),
        actions: [
          TextButton.icon(
            key: const ValueKey<String>('booklist-detail-delete'),
            onPressed: _busy ? null : _delete,
            icon: const AppIcon(AppGlyph.delete),
            label: const Text('删除书单'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
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
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        title: const Text('添加书籍'),
        scrollContent: false,
        content: SizedBox(
          height: MediaQuery.sizeOf(context).height * .55,
          child: Column(
            children: [
              TextField(
                key: const ValueKey<String>('booklist-picker-search'),
                decoration: const InputDecoration(
                  hintText: '搜索书名或作者',
                  prefixIcon: AppIcon(AppGlyph.search),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          '没有匹配的书籍',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        key: const ValueKey<String>('booklist-picker-list'),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final book = visible[index];
                          return CheckboxListTile(
                            key: ValueKey<String>('booklist-picker-${book.id}'),
                            contentPadding: EdgeInsets.zero,
                            value: _selected.contains(book.id),
                            title: Text(
                              book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              book.author.isEmpty ? '未知作者' : book.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(book.id);
                              } else {
                                _selected.remove(book.id);
                              }
                            }),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
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
    return Material(
      key: const ValueKey<String>('booklist-membership'),
      type: MaterialType.transparency,
      child: ReaderSheetForm(
        title: const Text('加入书单'),
        content: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_bookLists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '还没有书单，先新建一个',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final bookList in _bookLists)
                      CheckboxListTile(
                        key: ValueKey<String>(
                          'booklist-membership-${bookList.id}',
                        ),
                        contentPadding: EdgeInsets.zero,
                        value: _memberIds.contains(bookList.id),
                        title: Text(
                          bookList.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${bookList.bookIds.length} 本书'),
                        onChanged: _busy
                            ? null
                            : (value) => _toggle(bookList, value ?? false),
                      ),
                ],
              ),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _create,
            icon: const AppIcon(AppGlyph.add),
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
