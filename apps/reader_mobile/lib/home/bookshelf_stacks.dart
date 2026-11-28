import 'dart:convert';

import '../library/library_store.dart';

export '../library/library_store.dart' show bookshelfTagStacksKey;

/// 旧版有已选堆叠标签时保留开启状态，新设置直接保存统一开关。
Future<bool> loadBookshelfTagStacking(LibraryStore library) async {
  final raw = await library.getSetting(bookshelfTagStacksKey);
  if (raw == null) return false;
  final value = jsonDecode(raw);
  return value == true ||
      value is Map<String, dynamic> &&
          value.values.any((ids) => ids is List && ids.isNotEmpty);
}

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
