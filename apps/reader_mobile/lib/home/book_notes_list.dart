import 'package:flutter/material.dart';
import 'package:reader_ui/theme/app_semantic_colors.dart';
import 'package:reader_ui/theme/reader_common_widgets.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
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

  /// 与书评卡片保持一致的 3:4 封面尺寸与 6dp 贴边内缩。
  static const double _coverInset = 6;
  static const double _coverWidth = 84;
  static const double _coverHeight = _coverWidth * 4 / 3;
  static const double _coverRadius = ReaderUiStyle.cardCorner - _coverInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = AppSemanticColors.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Material(
      color: scheme.surface,
      shape: ReaderUiStyle.cardShapeOf(theme),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: CustomPaint(
            painter: _NotebookCardPainter(
              lineColor: scheme.outlineVariant.withValues(
                alpha: isLight ? .42 : .30,
              ),
              contentStartX: _coverInset * 2 + _coverWidth + 12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(_coverInset),
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_coverRadius),
                        border: Border.all(color: semantics.bookCoverBorder),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_coverRadius - 1),
                        child: SizedBox(
                          width: _coverWidth,
                          height: _coverHeight,
                          child: BookCoverImage(book: book),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                    child: _details(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _details(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final author = book.author.trim().isEmpty ? '未知作者' : book.author.trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _coverHeight - 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      _formatNoteDate(counts.updatedAt),
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: .82),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (counts.thoughts > 0)
                _CountBadge(
                  AppGlyph.note,
                  '想法 ${counts.thoughts}',
                  accent: true,
                ),
              if (counts.marks > 0)
                _CountBadge(
                  AppGlyph.formatUnderlined,
                  '划线 ${counts.marks}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatNoteDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    final now = DateTime.now();
    if (local.year == now.year) {
      return '${local.month}月${local.day}日';
    }
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }
}

/// 笔记卡片右侧的极淡横格笔记线，保持轻盈留白质感。
class _NotebookCardPainter extends CustomPainter {
  const _NotebookCardPainter({
    required this.lineColor,
    required this.contentStartX,
  });

  final Color lineColor;
  final double contentStartX;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.8;
    final startX = contentStartX;
    final endX = size.width - 14.0;
    if (endX > startX + 24) {
      final y1 = size.height - 46.0;
      final y2 = size.height - 12.0;
      if (y1 > 48) {
        canvas.drawLine(Offset(startX, y1), Offset(endX, y1), linePaint);
      }
      if (y2 > y1 + 14) {
        canvas.drawLine(Offset(startX, y2), Offset(endX, y2), linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_NotebookCardPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      oldDelegate.contentStartX != contentStartX;
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.glyph, this.label, {this.accent = false});

  final AppGlyph glyph;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = accent
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    final iconColor = accent ? scheme.primary : scheme.onSurfaceVariant;
    final textColor = accent ? scheme.onPrimaryContainer : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(glyph, size: 12.5, color: iconColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor,
                fontWeight: accent ? FontWeight.w500 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
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
      final list = ListView.separated(
        padding: _listInsets,
        itemCount: notes.length,
        itemBuilder: (_, index) => _NoteCard(notes[index]),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
      );
      return usesDesktopLayout(context) ? SelectionArea(child: list) : list;
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(context, thought),
            const SizedBox(height: 12),
            if (thought && note != null && note.trim().isNotEmpty) ...[
              Text(
                note,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: BorderDirectional(
                  start: BorderSide(
                    color: thought ? scheme.primary : scheme.outline,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                annotation.quote,
                style:
                    (thought
                            ? theme.textTheme.bodySmall
                            : theme.textTheme.bodyMedium)
                        ?.copyWith(
                          fontFamily: _song,
                          height: 1.65,
                          color: thought
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, bool thought) {
    final date = annotation.updatedAt.toLocal();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: thought
                ? scheme.primaryContainer
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                thought ? AppGlyph.note : AppGlyph.formatUnderlined,
                size: 13,
                color: thought ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                thought ? '想法' : '划线',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: thought
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Text(
          '${date.year}年${date.month}月${date.day}日',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
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
    final colors = Theme.of(context).colorScheme;
    return ReaderEmptyState(
      icon: onRetry == null ? AppGlyph.note : AppGlyph.error,
      iconColor: onRetry == null ? colors.onSurfaceVariant : colors.error,
      iconContainerColor: onRetry == null
          ? colors.surfaceContainerHigh
          : colors.errorContainer,
      title: title,
      subtitle: hint,
      action: onRetry == null
          ? null
          : OutlinedButton(onPressed: onRetry, child: const Text('重试')),
    );
  }
}
