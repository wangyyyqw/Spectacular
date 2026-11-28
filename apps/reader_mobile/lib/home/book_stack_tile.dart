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
    required this.onOpen,
  });

  final BookTag tag;
  final List<BookEntry> books;
  final bool grid;
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
      child: ExcludeSemantics(child: grid ? _grid() : _row()),
    ),
  );

  Widget _grid() => Column(
    children: [
      AspectRatio(
        aspectRatio: 3 / 4,
        child: BookCoverStack(books: books),
      ),
    ],
  );

  Widget _row() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
    child: Row(
      children: [
        SizedBox(width: 66, height: 88, child: BookCoverStack(books: books)),
        const Spacer(),
        const AppIcon(AppGlyph.chevronRight, size: 20),
      ],
    ),
  );
}
