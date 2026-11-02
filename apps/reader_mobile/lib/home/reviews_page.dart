import 'dart:io';

import 'package:flutter/material.dart';

import '../library/library_store.dart';
import '../storage/book_review_store.dart';

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
  const ReviewsPage({super.key, required this.library, this.reviewStore});

  /// 书架存储。
  final LibraryStore library;

  /// 可注入的书评存储；为空时使用书架数据库实现。
  final BookReviewStore? reviewStore;

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  List<BookEntry>? _books;
  Map<String, BookReview> _reviews = const <String, BookReview>{};
  final TextEditingController _searchController = TextEditingController();
  _ReviewFilter _filter = _ReviewFilter.all;
  _ReviewSort _sort = _ReviewSort.updated;
  bool _searching = false;
  String _query = '';
  int _reloadToken = 0;

  BookReviewStore? get _store =>
      widget.reviewStore ?? widget.library.reviewStore();

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.library.removeListener(_reload);
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
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
    final books = await widget.library.list();
    final store = _store;
    final reviews = store == null
        ? const <String, BookReview>{}
        : await store.snapshot();
    if (mounted && token == _reloadToken) {
      setState(() {
        _books = books;
        _reviews = reviews;
      });
    }
  }

  Future<void> _edit(BookEntry book) async {
    final store = _store;
    if (store == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前无法保存书评')));
      return;
    }
    final review = _reviews[book.id];
    final draft = await showModalBottomSheet<_ReviewDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewEditorSheet(book: book, review: review),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      if (draft.delete) {
        await store.remove(book.id);
      } else {
        await store.save(book.id, rating: draft.rating, content: draft.content);
      }
      await _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('书评保存失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                key: const ValueKey<String>('reviews-search-field'),
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索书名、作者或书评',
                  border: InputBorder.none,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: _clearSearch,
                          icon: const Icon(Icons.clear),
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : const Text('书评'),
        actions: _searching
            ? [
                IconButton(
                  tooltip: '关闭搜索',
                  onPressed: _toggleSearch,
                  icon: const Icon(Icons.close),
                ),
              ]
            : [
                if (books != null && books.isNotEmpty)
                  PopupMenuButton<_ReviewSort>(
                    key: const ValueKey<String>('reviews-sort'),
                    tooltip: '书评排序',
                    initialValue: _sort,
                    onSelected: (value) => setState(() => _sort = value),
                    icon: const Icon(Icons.sort),
                    itemBuilder: (_) => <PopupMenuEntry<_ReviewSort>>[
                      for (final sort in _ReviewSort.values)
                        CheckedPopupMenuItem<_ReviewSort>(
                          key: ValueKey<String>('reviews-sort-${sort.name}'),
                          value: sort,
                          checked: sort == _sort,
                          child: Text(sort.label),
                        ),
                    ],
                  ),
                if (books != null && books.isNotEmpty)
                  IconButton(
                    tooltip: '搜索书评',
                    onPressed: _toggleSearch,
                    icon: const Icon(Icons.search),
                  ),
                IconButton(
                  key: const ValueKey<String>('reviews-refresh'),
                  tooltip: '刷新书评',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
      ),
      body: books == null
          ? const Center(child: CircularProgressIndicator())
          : books.isEmpty
          ? const _EmptyReviews()
          : RefreshIndicator(
              onRefresh: _reload,
              child: _ReviewList(
                books: books,
                reviews: _reviews,
                query: _query,
                filter: _filter,
                sort: _sort,
                onFilterChanged: (filter) => setState(() => _filter = filter),
                onResetSearchAndFilter: _resetSearchAndFilter,
                onEdit: _edit,
              ),
            ),
    );
  }
}

class _ReviewList extends StatelessWidget {
  const _ReviewList({
    required this.books,
    required this.reviews,
    required this.query,
    required this.filter,
    required this.sort,
    required this.onFilterChanged,
    required this.onResetSearchAndFilter,
    required this.onEdit,
  });

  final List<BookEntry> books;
  final Map<String, BookReview> reviews;
  final String query;
  final _ReviewFilter filter;
  final _ReviewSort sort;
  final ValueChanged<_ReviewFilter> onFilterChanged;
  final VoidCallback onResetSearchAndFilter;
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
        if (reviews[book.id] == null && matches(book)) book,
    ];
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _ReviewSummary(
          reviewed: allReviewed.length,
          total: books.length,
          reviews: reviews,
        ),
        const SizedBox(height: 14),
        _ReviewFilterBar(
          reviewed: reviewed.length,
          pending: pending.length,
          selected: filter,
          onSelected: onFilterChanged,
        ),
        const SizedBox(height: 24),
        if (visibleReviewed.isEmpty && visiblePending.isEmpty)
          _NoReviewMatches(
            query: query.trim(),
            filter: filter,
            onReset: onResetSearchAndFilter,
          )
        else ...[
          if (showReviewed) ...[
            _SectionTitle(title: '我的书评', detail: '${reviewed.length} 篇'),
            const SizedBox(height: 10),
            if (reviewed.isEmpty)
              const _NoReviewCard()
            else
              for (final book in reviewed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ReviewCard(
                    book: book,
                    review: reviews[book.id]!,
                    onTap: () => onEdit(book),
                  ),
                ),
          ],
          if (showPending && pending.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SectionTitle(title: '待写书评', detail: '${pending.length} 本'),
            const SizedBox(height: 10),
            for (final book in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PendingBookTile(book: book, onTap: () => onEdit(book)),
              ),
          ],
        ],
      ],
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final filter in _ReviewFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey<String>('reviews-filter-${filter.name}'),
                label: Text('${filter.label} ${_count(filter)}'),
                selected: filter == selected,
                showCheckmark: false,
                onSelected: (_) => onSelected(filter),
              ),
            ),
        ],
      ),
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
      key: const ValueKey<String>('reviews-no-results'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              query.isNotEmpty ? Icons.search_off : Icons.rate_review_outlined,
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
              icon: const Icon(Icons.filter_alt_off_outlined),
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
    final theme = Theme.of(context);
    final ratings = reviews.values
        .map((review) => review.rating)
        .whereType<int>()
        .toList();
    final average = ratings.isEmpty
        ? null
        : ratings.reduce((left, right) => left + right) / ratings.length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer.withValues(alpha: 0.82),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.56),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.auto_stories_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已写 $reviewed / $total 本',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  average == null
                      ? '给读过的书留下一点想法。'
                      : '平均评分 ${average.toStringAsFixed(1)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.72,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (average != null)
            Icon(
              Icons.star_rounded,
              key: const ValueKey<String>('reviews-average-star'),
              color: const Color(0xFFE0A327),
              size: 30,
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        Text(
          detail,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.book,
    required this.review,
    required this.onTap,
  });

  final BookEntry book;
  final BookReview review;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = review.content.isEmpty ? '仅评分，未写正文。' : review.content;
    return Card(
      key: ValueKey<String>('review-card-${book.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReviewCover(book: book),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        _StarRow(rating: review.rating, size: 18),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _relativeTime(review.updatedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '编辑',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingBookTile extends StatelessWidget {
  const _PendingBookTile({required this.book, required this.onTap});

  final BookEntry book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey<String>('review-pending-${book.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: _ReviewCover(book: book, width: 38, height: 50),
        title: Text(
          book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
        ),
        subtitle: Text(
          '写下评分或读后感',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Text(
          '写书评',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _ReviewCover extends StatelessWidget {
  const _ReviewCover({required this.book, this.width = 42, this.height = 56});

  final BookEntry book;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: HSLColor.fromAHSL(
          1,
          book.coverHue.toDouble(),
          0.42,
          0.38,
        ).toColor(),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        book.title.isEmpty ? '书' : book.title.characters.first,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final coverPath = book.coverPath;
    if (coverPath == null) {
      return placeholder;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        File(coverPath),
        width: width,
        height: height,
        fit: BoxFit.cover,
        cacheWidth: (width * 3).round(),
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
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
          Icon(
            star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
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

class _NoReviewCard extends StatelessWidget {
  const _NoReviewCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.edit_note_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '还没有书评，从下方选一本书开始写吧。',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
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
          Icon(Icons.rate_review_outlined, size: 64),
          SizedBox(height: 12),
          Text('导入书籍后可以在这里写书评'),
        ],
      ),
    );
  }
}

class _ReviewEditorSheet extends StatefulWidget {
  const _ReviewEditorSheet({required this.book, required this.review});

  final BookEntry book;
  final BookReview? review;

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

  void _refresh() => setState(() {});

  bool get _canSave => _rating != null || _controller.text.trim().isNotEmpty;

  bool get _dirty =>
      _rating != _initialRating ||
      _controller.text.trim() != _initialContent.trim();

  void _finish(_ReviewDraft draft) {
    if (_closing) {
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
    if (_closing) {
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

  void _save() {
    _finish(_ReviewDraft(rating: _rating, content: _controller.text.trim()));
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
      _finish(const _ReviewDraft.delete());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.review != null;
    return PopScope(
      canPop: !_dirty || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _close();
        }
      },
      child: Material(
        key: const ValueKey<String>('review-editor'),
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEditing ? '编辑书评' : '写书评',
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
                        tooltip: '关闭',
                        onPressed: _close,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('评分', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var star = 1; star <= 5; star++)
                        IconButton(
                          key: ValueKey<String>('review-rating-$star'),
                          tooltip: '$star 星',
                          onPressed: () => setState(
                            () => _rating = _rating == star ? null : star,
                          ),
                          iconSize: 34,
                          color: const Color(0xFFE0A327),
                          icon: Icon(
                            star <= (_rating ?? 0)
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('书评内容', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey<String>('review-content'),
                    controller: _controller,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 1000,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: '写下这本书带给你的感受…',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const ValueKey<String>('review-save'),
                    onPressed: _canSave ? _save : null,
                    icon: const Icon(Icons.check),
                    label: const Text('保存书评'),
                  ),
                  if (isEditing) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      key: const ValueKey<String>('review-delete'),
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除书评'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
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

String _relativeTime(DateTime time) {
  final delta = DateTime.now().difference(time);
  if (delta.isNegative || delta.inMinutes < 1) return '刚刚';
  if (delta.inHours < 1) return '${delta.inMinutes} 分钟前';
  if (delta.inDays < 1) return '${delta.inHours} 小时前';
  return '${delta.inDays} 天前';
}
