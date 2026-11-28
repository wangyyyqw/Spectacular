import '../library/library_store.dart';

export '../library/library_store.dart' show bookshelfTagStacksKey;

/// 一个书架位置：未堆叠的单本，或同一标签下的多本书。
class ShelfStack<T> {
  const ShelfStack({required this.books, this.tag});

  final List<T> books;
  final BookTag? tag;
}

/// 堆叠按标签顺序展示；同书可属于多个堆叠，未堆叠书籍保持原顺序。
List<ShelfStack<T>> stackBooksByTags<T>({
  required List<T> books,
  required String Function(T) bookId,
  required Map<String, Set<String>> bookTags,
  required List<BookTag> tags,
}) {
  final stackedIds = <String>{};
  final stacks = <ShelfStack<T>>[];
  for (final tag in tags) {
    final matches = books
        .where((book) => bookTags[bookId(book)]?.contains(tag.id) ?? false)
        .toList();
    if (matches.length < 2) continue;
    stacks.add(ShelfStack(tag: tag, books: matches));
    stackedIds.addAll(matches.map(bookId));
  }
  return [
    ...stacks,
    for (final book in books)
      if (!stackedIds.contains(bookId(book))) ShelfStack(books: [book]),
  ];
}
