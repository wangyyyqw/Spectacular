import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../library/library_store.dart';
import 'book_cover_stack.dart';

/// 网格与列表共用的堆叠入口，数量和标签作为整体语义对外提供。
class BookStackTile extends StatelessWidget {
  const BookStackTile({
    super.key,
    required this.tag,
    required this.books,
    required this.grid,
    required this.showTitle,
    required this.onOpen,
  });

  final BookTag tag;
  final List<BookEntry> books;
  final bool grid;
  final bool showTitle;
  final VoidCallback onOpen;

  String get _label => '${tag.name} · ${books.length} 本';

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$_label，点击展开',
    button: true,
    child: InkWell(
      key: ValueKey('book-stack-${tag.id}'),
      borderRadius: BorderRadius.circular(4),
      onTap: onOpen,
      child: ExcludeSemantics(child: grid ? _grid(context) : _row(context)),
    ),
  );

  Widget _cover(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: BookCoverStack(books: books)),
      if (!showTitle && grid)
        Positioned(
          bottom: 2,
          left: 0,
          right: 0,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Text(
              _label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
    ],
  );

  Widget _grid(BuildContext context) => Column(
    children: [
      AspectRatio(aspectRatio: 3 / 4, child: _cover(context)),
      if (showTitle) ...[
        const SizedBox(height: 6),
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(20),
          child: Text(
            _label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ],
  );

  Widget _row(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
    child: Row(
      children: [
        SizedBox(width: 66, height: 88, child: _cover(context)),
        const SizedBox(width: 20),
        Expanded(
          child: Text(_label, style: Theme.of(context).textTheme.titleMedium),
        ),
        const AppIcon(AppGlyph.chevronRight, size: 20),
      ],
    ),
  );
}
