import '../library/library_store.dart';

/// 按当前设备的书架分组保存堆叠偏好；标签关联仍由书库正常同步。
const bookshelfTagStacksKey = 'local.bookshelf.tagStacks';

/// 一个书架位置：未堆叠的单本，或同一标签下的多本书。
class ShelfStack<T> {
  const ShelfStack({required this.books, this.tag});

  final List<T> books;
  final BookTag? tag;
}

/// 已排序、已限定书架分组的书籍按标签选择顺序认领，堆叠占首本的位置。
List<ShelfStack<T>> stackBooksByTags<T>({
  required List<T> books,
  required String Function(T) bookId,
  required Map<String, Set<String>> bookTags,
  required List<BookTag> tags,
}) {
  final owners = <String, ShelfStack<T>>{};
  for (final tag in tags) {
    final matches = books.where((book) {
      final id = bookId(book);
      return !owners.containsKey(id) &&
          (bookTags[id]?.contains(tag.id) ?? false);
    }).toList();
    if (matches.length < 2) continue;
    final stack = ShelfStack(tag: tag, books: matches);
    for (final book in matches) {
      owners[bookId(book)] = stack;
    }
  }
  final emitted = <ShelfStack<T>>{};
  return [
    for (final book in books)
      if (owners[bookId(book)] case final stack?) ...[
        if (emitted.add(stack)) stack,
      ] else
        ShelfStack(books: [book]),
  ];
}
