import 'dart:convert';

import 'library_store.dart';

/// 书单：名称、简介与按添加顺序排列的书籍 id。
class BookList {
  const BookList({
    required this.id,
    required this.name,
    this.description = '',
    this.bookIds = const <String>[],
    required this.createdAt,
  });

  /// 名称最大长度。
  static const maxNameLength = 40;

  /// 简介最大长度。
  static const maxDescriptionLength = 200;

  final String id;
  final String name;
  final String description;
  final List<String> bookIds;
  final DateTime createdAt;

  BookList copyWith({
    String? name,
    String? description,
    List<String>? bookIds,
  }) => BookList(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    bookIds: bookIds ?? this.bookIds,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'bookIds': bookIds,
    'createdAt': createdAt.toIso8601String(),
  };

  static BookList? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final createdAt = DateTime.tryParse('${value['createdAt']}');
    if (id is! String || name is! String || createdAt == null) return null;
    return BookList(
      id: id,
      name: name,
      description: value['description'] is String
          ? value['description'] as String
          : '',
      bookIds: value['bookIds'] is List
          ? List<String>.unmodifiable(
              (value['bookIds'] as List).whereType<String>(),
            )
          : const <String>[],
      createdAt: createdAt,
    );
  }
}

/// 书单存储：序列化到 settings 表，避免改动固定版本的数据库结构。
class BookListStore {
  BookListStore(this._library);

  final LibraryStore _library;

  /// settings 表中的书单键。
  static const settingKey = 'booklists.v1';

  Future<List<BookList>> list() async {
    final raw = await _library.getSetting(settingKey);
    if (raw == null || raw.isEmpty) return const <BookList>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <BookList>[];
      return <BookList>[
        for (final item in decoded) ?BookList.tryFromJson(item),
      ];
    } on FormatException {
      return const <BookList>[];
    }
  }

  Future<BookList> create({
    required String name,
    String description = '',
  }) async {
    final trimmedName = _checkedName(name);
    final lists = List<BookList>.of(await list());
    final now = DateTime.now();
    final created = BookList(
      id: 'bl${now.microsecondsSinceEpoch}${lists.length}',
      name: trimmedName,
      description: description.trim(),
      createdAt: now,
    );
    await _save(<BookList>[...lists, created]);
    return created;
  }

  Future<void> update(
    String id, {
    String? name,
    String? description,
  }) async {
    final lists = List<BookList>.of(await list());
    final index = lists.indexWhere((bookList) => bookList.id == id);
    if (index < 0) return;
    lists[index] = lists[index].copyWith(
      name: name == null ? null : _checkedName(name),
      description: description?.trim(),
    );
    await _save(lists);
  }

  Future<void> delete(String id) async {
    final lists = List<BookList>.of(await list());
    lists.removeWhere((bookList) => bookList.id == id);
    await _save(lists);
  }

  Future<void> addBooks(String id, Iterable<String> bookIds) => _editBooks(
    id,
    (current) {
      final seen = current.toSet();
      return <String>[
        ...current,
        for (final bookId in bookIds)
          if (seen.add(bookId)) bookId,
      ];
    },
  );

  Future<void> removeBook(String id, String bookId) => _editBooks(
    id,
    (current) => <String>[
      for (final value in current)
        if (value != bookId) value,
    ],
  );

  Future<void> setBooks(String id, Iterable<String> bookIds) => _editBooks(
    id,
    (_) => bookIds.toSet().toList(),
  );

  /// 包含指定书籍的书单 id。
  Future<Set<String>> listIdsForBook(String bookId) async => <String>{
    for (final bookList in await list())
      if (bookList.bookIds.contains(bookId)) bookList.id,
  };

  Future<void> _editBooks(
    String id,
    List<String> Function(List<String> current) edit,
  ) async {
    final lists = List<BookList>.of(await list());
    final index = lists.indexWhere((bookList) => bookList.id == id);
    if (index < 0) return;
    lists[index] = lists[index].copyWith(bookIds: edit(lists[index].bookIds));
    await _save(lists);
  }

  Future<void> _save(List<BookList> lists) => _library.setSetting(
    settingKey,
    jsonEncode(<Map<String, Object?>>[
      for (final bookList in lists) bookList.toJson(),
    ]),
  );

  String _checkedName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('书单名称不能为空');
    }
    return trimmed;
  }
}
