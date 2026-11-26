import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/app_semantic_colors.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

import '../library/library_store.dart';
import 'book_cover_image.dart';
import 'reading_insights.dart';

/// 与书架列表视图保持一致的封面尺寸（66×88，3:4）。
const double _rankingCoverWidth = 66;
const double _rankingCoverHeight = 88;

typedef _RankedBook = ({
  String id,
  String title,
  BookEntry? book,
  BookReadingTotals totals,
});

/// 按累计阅读时长排序，封面、次数、翻页和字数共同说明阅读投入。
class BookReadingRanking extends StatelessWidget {
  const BookReadingRanking({
    super.key,
    required this.books,
    required this.totals,
    this.bookTitles = const {},
    required this.onOpen,
  });

  final List<BookEntry> books;
  final Map<String, BookReadingTotals> totals;
  final Map<String, String> bookTitles;
  final ValueChanged<BookEntry> onOpen;

  List<_RankedBook> get _ranked {
    final byId = {for (final book in books) book.id: book};
    return [
      for (final entry in totals.entries)
        (
          id: entry.key,
          title: byId[entry.key]?.title ?? bookTitles[entry.key] ?? '已移出书架的书籍',
          book: byId[entry.key],
          totals: entry.value,
        ),
    ]..sort((left, right) {
      final time = right.totals.duration.compareTo(left.totals.duration);
      return time == 0 ? left.title.compareTo(right.title) : time;
    });
  }

  Future<void> _showAll(BuildContext context, List<_RankedBook> ranked) async {
    final maxDuration = ranked.isEmpty
        ? Duration.zero
        : ranked.first.totals.duration;
    final book = await showReaderDrawer<BookEntry>(
      context: context,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .76,
        child: ReaderSheetForm(
          title: Text('累计阅读排行 · ${ranked.length} 本'),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          scrollContent: false,
          content: ListView.separated(
            itemCount: ranked.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              indent: _rankingCoverWidth + 14,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            itemBuilder: (context, index) {
              final item = ranked[index];
              return _RankingRow(
                rank: index + 1,
                book: item,
                maxDuration: maxDuration,
                onOpen: item.book == null
                    ? null
                    : () => Navigator.of(context).pop(item.book),
              );
            },
          ),
        ),
      ),
    );
    if (book != null && context.mounted) {
      onOpen(book);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ranked = _ranked;
    if (ranked.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: ReaderUiStyle.cardDecorationOf(theme),
        child: Row(
          children: [
            AppIcon(
              AppGlyph.autoStories,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '开始阅读后，这里会按投入时长列出书目。',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final visible = ranked.take(3).toList();
    final maxDuration = ranked.first.totals.duration;
    return Material(
      color: scheme.surface,
      shape: ReaderUiStyle.cardShapeOf(theme),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                indent: 14 + _rankingCoverWidth + 14,
                endIndent: 14,
                color: scheme.outlineVariant,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _RankingRow(
                rank: index + 1,
                book: visible[index],
                maxDuration: maxDuration,
                onOpen: visible[index].book == null
                    ? null
                    : () => onOpen(visible[index].book!),
              ),
            ),
          ],
          if (ranked.length > 3) ...[
            Divider(height: 1, color: scheme.outlineVariant),
            GestureDetector(
              key: const ValueKey('stats-ranking-all'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _showAll(context, ranked),
              child: Container(
                height: 46,
                width: double.infinity,
                color: scheme.surfaceContainerLow.withValues(alpha: .65),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '查看全部 ${ranked.length} 本',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AppIcon(
                      AppGlyph.chevronRight,
                      size: 16,
                      color: scheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.rank,
    required this.book,
    required this.maxDuration,
    required this.onOpen,
  });

  final int rank;
  final _RankedBook book;
  final Duration maxDuration;
  final VoidCallback? onOpen;

  double get _ratio {
    if (maxDuration <= Duration.zero) return 0;
    return (book.totals.duration.inSeconds / maxDuration.inSeconds).clamp(
      0.06,
      1.0,
    );
  }

  Widget _cover(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = AppSemanticColors.of(context);
    final isTop3 = rank <= 3;
    final cover = book.book == null
        ? Container(
            width: _rankingCoverWidth,
            height: _rankingCoverHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: semantics.bookCoverBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppGlyph.menuBook,
                  size: 22,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 4),
                Text(
                  '已移出',
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant.withValues(alpha: .8),
                  ),
                ),
              ],
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: semantics.bookCoverBorder),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: BookCoverImage(
                book: book.book!,
                width: _rankingCoverWidth,
                height: _rankingCoverHeight,
                showShadow: false,
              ),
            ),
          );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        cover,
        Positioned(
          left: 5,
          top: 5,
          child: Container(
            constraints: const BoxConstraints(minWidth: 20),
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isTop3
                  ? scheme.primary
                  : scheme.inverseSurface.withValues(alpha: .78),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: isTop3 ? scheme.onPrimary : scheme.onInverseSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _details(BuildContext context, {required bool showDuration}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final author = book.book?.author.trim() ?? '';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _rankingCoverHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
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
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (!showDuration) ...[
                    const SizedBox(width: 10),
                    _duration(context),
                  ],
                ],
              ),
              if (showDuration) ...[
                const SizedBox(height: 4),
                _duration(context),
              ],
              if (author.isNotEmpty || book.book == null) ...[
                const SizedBox(height: 3),
                Text(
                  book.book == null ? '已移出书架' : author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                '${book.totals.sessions} 次 · ${book.totals.pageTurns} 次翻页 · ${book.totals.charactersRead} 字',
                key: ValueKey('stats-ranking-counts-${book.id}'),
                maxLines: 2,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      Container(
                        height: 4,
                        width: double.infinity,
                        color: scheme.surfaceContainerHighest,
                      ),
                      Container(
                        height: 4,
                        width: constraints.maxWidth * _ratio,
                        color: rank == 1
                            ? scheme.primary
                            : scheme.primary.withValues(alpha: .65),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _duration(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      formatReadingDuration(book.totals.duration),
      key: ValueKey('stats-ranking-duration-${book.id}'),
      style: TextStyle(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: rank == 1 ? scheme.primary : scheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('stats-ranking-${book.id}'),
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    onTap: onOpen,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(13) > 17;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cover(context),
              const SizedBox(width: 14),
              Expanded(child: _details(context, showDuration: stacked)),
            ],
          );
        },
      ),
    ),
  );
}
