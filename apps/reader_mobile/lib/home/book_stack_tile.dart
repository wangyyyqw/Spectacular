import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../library/library_store.dart';
import 'book_cover_stack.dart';

/// 堆叠名称在网格中跟随书名开关，列表始终显示；数量保留在整体语义中。
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

  Widget _grid(BuildContext context) => Column(
    children: [
      AspectRatio(
        aspectRatio: 3 / 4,
        child: BookCoverStack(books: books),
      ),
      if (showTitle) ...[
        const SizedBox(height: 6),
        Expanded(child: Center(child: _title(context))),
      ],
    ],
  );

  Widget _row(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
    child: Row(
      children: [
        SizedBox(width: 66, height: 88, child: BookCoverStack(books: books)),
        const SizedBox(width: 16),
        Expanded(child: _title(context)),
        const SizedBox(width: 12),
        const AppIcon(AppGlyph.chevronRight, size: 20),
      ],
    ),
  );

  Widget _title(BuildContext context) => Text(
    tag.name,
    key: ValueKey('book-stack-title-${tag.id}'),
    textAlign: grid ? TextAlign.center : TextAlign.start,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontWeight: FontWeight.w600),
  );
}
