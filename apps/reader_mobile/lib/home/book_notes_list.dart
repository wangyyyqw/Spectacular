import 'package:flutter/material.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../library/library_store.dart';
import 'book_cover_image.dart';
import 'desktop_layout.dart';

const _listInsets = EdgeInsets.fromLTRB(16, 12, 16, 24);
const _song = 'builtin_song';

/// 按最近笔记展示书目，打开一本书时才读取它的标注正文。
class BookNotesList extends StatelessWidget {
  const BookNotesList({
    super.key,
    required this.books,
    required this.counts,
    required this.loadNotes,
    required this.onRefresh,
    this.query = '',
  });

  final List<BookEntry> books;
  final Map<String, BookNoteCounts> counts;
  final Future<List<ReaderAnnotation>> Function(String bookId) loadNotes;
  final Future<void> Function() onRefresh;
  final String query;

  List<({BookEntry book, BookNoteCounts counts})> get _notedBooks {
    final needle = query.trim().toLowerCase();
    return [
      for (final book in books)
        if (counts[book.id] case final count?
            when (count.thoughts > 0 || count.marks > 0) &&
                (needle.isEmpty ||
                    book.title.toLowerCase().contains(needle) ||
                    book.author.toLowerCase().contains(needle)))
          (book: book, counts: count),
    ]..sort((left, right) {
      final byTime = right.counts.updatedAt.compareTo(left.counts.updatedAt);
      return byTime != 0 ? byTime : left.book.title.compareTo(right.book.title);
    });
  }

  Future<void> _openBook(BuildContext context, BookEntry book) =>
      showReaderDrawer<void>(
        context: context,
        builder: (_) =>
            _BookNotesPage(title: book.title, load: () => loadNotes(book.id)),
      );

  @override
  Widget build(BuildContext context) {
    final noted = _notedBooks;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        key: const PageStorageKey<String>('book-notes-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (noted.isEmpty)
            if (query.trim().isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _NotesMessage('还没有笔记', hint: '阅读时划线或写下想法，就会在这里按书归集。'),
              )
            else
              SliverFillRemaining(
                hasScrollBody: false,
                child: _NotesMessage(
                  '没有找到相关笔记',
                  hint: '没有书名或作者包含“${query.trim()}”',
                ),
              )
          else
            SliverPadding(padding: _listInsets, sliver: _bookRows(noted)),
        ],
      ),
    );
  }

  Widget _bookRows(List<({BookEntry book, BookNoteCounts counts})> noted) =>
      SliverLayoutBuilder(
        builder: (context, bounds) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final columns = usesDesktopLayout(context)
              ? ((bounds.crossAxisExtent + 16) / (300 * scale + 16))
                    .floor()
                    .clamp(1, 3)
              : 1;
          return SliverList.separated(
            itemCount: (noted.length / columns).ceil(),
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, row) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                for (var column = 0; column < columns; column++)
                  Expanded(
                    child: row * columns + column < noted.length
                        ? _BookNotesCard(
                            book: noted[row * columns + column].book,
                            counts: noted[row * columns + column].counts,
                            onTap: () => _openBook(
                              context,
                              noted[row * columns + column].book,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          );
        },
      );
}

class _BookNotesCard extends StatelessWidget {
  const _BookNotesCard({
    required this.book,
    required this.counts,
    required this.onTap,
  });

  final BookEntry book;
  final BookNoteCounts counts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(4),
    clipBehavior: Clip.antiAlias,
    child: Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: BookCoverImage(book: book, width: 58, height: 82),
              ),
              const SizedBox(width: 12),
              Expanded(child: _details(context)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _details(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        book.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(height: 1.35, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        book.author.trim().isEmpty ? '未知作者' : book.author,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          if (counts.thoughts > 0)
            _CountBadge(AppGlyph.note, '想法 ${counts.thoughts}'),
          if (counts.marks > 0)
            _CountBadge(AppGlyph.formatUnderlined, '划线 ${counts.marks}'),
        ],
      ),
    ],
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.glyph, this.label);

  final AppGlyph glyph;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(glyph, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _BookNotesPage extends StatefulWidget {
  const _BookNotesPage({required this.title, required this.load});

  final String title;
  final Future<List<ReaderAnnotation>> Function() load;

  @override
  State<_BookNotesPage> createState() => _BookNotesPageState();
}

class _BookNotesPageState extends State<_BookNotesPage> {
  late Future<List<ReaderAnnotation>> _notes = _load();

  Future<List<ReaderAnnotation>> _load() async {
    final notes = await widget.load();
    return notes.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    title: Text(widget.title),
    contentPadding: EdgeInsets.zero,
    scrollContent: false,
    content: SizedBox(
      height: MediaQuery.sizeOf(context).height * .84,
      child: _body(),
    ),
  );

  Widget _body() => FutureBuilder<List<ReaderAnnotation>>(
    future: _notes,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(
          child: CircularProgressIndicator(semanticsLabel: '正在读取笔记'),
        );
      }
      if (snapshot.hasError) {
        return Center(
          child: SingleChildScrollView(
            child: _NotesMessage(
              '笔记读取失败',
              onRetry: () {
                final notes = _load();
                setState(() {
                  _notes = notes;
                });
              },
            ),
          ),
        );
      }
      final notes = snapshot.requireData;
      if (notes.isEmpty) return const _NotesMessage('这本书还没有笔记');
      return ListView.separated(
        padding: _listInsets,
        itemCount: notes.length,
        itemBuilder: (_, index) => _NoteCard(notes[index]),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
      );
    },
  );
}

class _NoteCard extends StatelessWidget {
  const _NoteCard(this.annotation);

  final ReaderAnnotation annotation;

  @override
  Widget build(BuildContext context) {
    final thought = annotation.type == ReaderAnnotationType.thought;
    final note = annotation.note;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(context, thought),
            const SizedBox(height: 10),
            if (thought && note != null && note.trim().isNotEmpty) ...[
              Text(
                note,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(height: 1.55),
              ),
              const SizedBox(height: 10),
            ],
            Container(
              padding: thought
                  ? const EdgeInsetsDirectional.only(start: 10)
                  : null,
              decoration: thought
                  ? BoxDecoration(
                      border: BorderDirectional(
                        start: BorderSide(
                          color: scheme.outlineVariant,
                          width: 2,
                        ),
                      ),
                    )
                  : null,
              child: Text(
                annotation.quote,
                style:
                    (thought
                            ? Theme.of(context).textTheme.bodySmall
                            : Theme.of(context).textTheme.bodyMedium)
                        ?.copyWith(fontFamily: _song, height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, bool thought) {
    final date = annotation.updatedAt.toLocal();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return DefaultTextStyle.merge(
      style: Theme.of(context).textTheme.bodySmall!,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 5,
            children: [
              AppIcon(
                thought ? AppGlyph.note : AppGlyph.formatUnderlined,
                size: 16,
                color: muted,
              ),
              Text(thought ? '想法' : '划线'),
            ],
          ),
          Text('${date.year}年${date.month}月${date.day}日'),
        ],
      ),
    );
  }
}

class _NotesMessage extends StatelessWidget {
  const _NotesMessage(this.title, {this.hint, this.onRetry});

  final String title;
  final String? hint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              onRetry == null ? AppGlyph.note : AppGlyph.error,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              OutlinedButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ],
        ),
      ),
    );
  }
}
