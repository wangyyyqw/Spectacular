import 'package:drift/drift.dart';
import 'package:reader_core/text/search.dart';

import '../storage/db.dart';

/// 搜索结果的一处命中（P4-24，供 P4-25 查询/定位使用）。
class SearchHit {
  /// 创建命中。
  const SearchHit({required this.spineIndex, required this.charOffset});

  /// 章节序号。
  final int spineIndex;

  /// 章内字符偏移。
  final int charOffset;
}

/// 全文索引的持久化（P4-24，§66.3）：章节原文 + 2-gram 倒排。
class SearchIndexStore {
  /// 创建存储。
  SearchIndexStore(this._db);

  final AppDatabase _db;

  /// 已索引到的章（断点续建用）：返回最后一个已写入的 spine，没有则 null。
  Future<int?> lastIndexedSpine(int bookId) async {
    final row = await _db
        .customSelect(
          'SELECT MAX(spine_index) AS max_spine FROM chapter_text '
          'WHERE book_id = ?',
          variables: <Variable<int>>[Variable<int>(bookId)],
        )
        .getSingle();
    return row.data['max_spine'] as int?;
  }

  /// 已索引部分的字符总数（续建时累计 charStart 用）。
  Future<int> indexedCharCount(int bookId) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(LENGTH(text)), 0) AS total FROM chapter_text '
          'WHERE book_id = ?',
          variables: <Variable<int>>[Variable<int>(bookId)],
        )
        .getSingle();
    return (row.data['total'] as int?) ?? 0;
  }

  /// 一本书已建索引的章数。
  Future<int> indexedChapterCount(int bookId) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS total FROM chapter_text WHERE book_id = ?',
          variables: <Variable<int>>[Variable<int>(bookId)],
        )
        .getSingle();
    return (row.data['total'] as int?) ?? 0;
  }

  /// 写入一章的原文与 gram（同一事务，保证断点一致）。
  Future<void> saveChapter({
    required int bookId,
    required int spineIndex,
    required String text,
    required int charStart,
  }) async {
    final grams = SearchTokenizer.gramsOf(text);
    await _db.transaction(() async {
      await _db
          .into(_db.chapterTexts)
          .insert(
            ChapterTextsCompanion.insert(
              bookId: bookId,
              spineIndex: spineIndex,
              chapterText: text,
              charStart: Value<int>(charStart),
            ),
            mode: InsertMode.insertOrReplace,
          );
      if (grams.isEmpty) {
        return;
      }
      await _db.batch((batch) {
        for (final gram in grams) {
          batch.insert(
            _db.searchGrams,
            SearchGramsCompanion.insert(
              bookId: bookId,
              gram: gram.gram,
              spineIndex: spineIndex,
              charOffset: gram.offset,
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    });
  }

  /// 删除一本书的全部索引（删书/重建用）。
  Future<void> clearBook(int bookId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.searchGrams,
      )..where((table) => table.bookId.equals(bookId))).go();
      await (_db.delete(
        _db.chapterTexts,
      )..where((table) => table.bookId.equals(bookId))).go();
    });
  }

  /// 某 gram 的全部命中（按章节与位置排序）。
  Future<List<SearchHit>> lookup(int bookId, String gram) async {
    final rows =
        await (_db.select(_db.searchGrams)..where(
              (table) => table.bookId.equals(bookId) & table.gram.equals(gram),
            )
            ..orderBy([
              (table) => OrderingTerm(expression: table.spineIndex),
              (table) => OrderingTerm(expression: table.charOffset),
            ]))
            .get();
    return <SearchHit>[
      for (final row in rows)
        SearchHit(spineIndex: row.spineIndex, charOffset: row.charOffset),
    ];
  }

  /// 章节原文（上下文提取）。
  Future<String?> chapterText(int bookId, int spineIndex) async {
    final rows = await (_db.select(_db.chapterTexts)..where(
          (table) =>
              table.bookId.equals(bookId) & table.spineIndex.equals(spineIndex),
        ))
        .get();
    return rows.isEmpty ? null : rows.single.chapterText;
  }
}
