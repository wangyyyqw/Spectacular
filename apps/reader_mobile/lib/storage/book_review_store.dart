import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import 'db.dart';

/// 一本书的书评快照。
class BookReview {
  const BookReview({
    required this.bookId,
    required this.rating,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 正文按用户感知的字符计数，与编辑器限制保持一致。
  static const maxContentLength = 5000;

  /// 书籍 uuid。
  final String bookId;

  /// 评分 1～5；null 表示未评分。
  final int? rating;

  /// 书评正文。
  final String content;

  /// 创建时间。
  final DateTime createdAt;

  /// 更新时间。
  final DateTime updatedAt;
}

/// 书评存储接口，方便阅读页与测试替换实现。
abstract interface class BookReviewStore {
  /// 全部书评快照：书籍 uuid → 书评。
  Future<Map<String, BookReview>> snapshot();

  /// 保存或覆盖一条书评；评分和正文都为空时删除。
  Future<void> save(String bookId, {int? rating, required String content});

  /// 删除书评。
  Future<void> remove(String bookId);
}

/// drift 书评存储实现。
class DriftBookReviewStore implements BookReviewStore {
  /// 创建存储。
  DriftBookReviewStore(this._db);

  final AppDatabase _db;

  @override
  Future<Map<String, BookReview>> snapshot() async {
    final books = await (_db.select(
      _db.books,
    )..where((table) => table.deletedAt.isNull())).get();
    final uuidById = <int, String>{
      for (final book in books) book.id: book.uuid,
    };
    final rows = await _db.select(_db.bookReviews).get();
    return <String, BookReview>{
      for (final row in rows)
        if (uuidById[row.bookId] != null)
          uuidById[row.bookId]!: _toReview(uuidById[row.bookId]!, row),
    };
  }

  @override
  Future<void> save(
    String bookId, {
    int? rating,
    required String content,
  }) async {
    final normalizedContent = content.trim();
    if (normalizedContent.characters.length > BookReview.maxContentLength) {
      throw const FormatException('书评最多 5000 个字符');
    }
    final normalizedRating = rating?.clamp(1, 5);
    if (normalizedContent.isEmpty && normalizedRating == null) {
      await remove(bookId);
      return;
    }
    final internalId = await _bookIdOf(bookId);
    if (internalId == null) {
      throw const FormatException('书籍已移除，无法保存书评');
    }
    final existing = await (_db.select(
      _db.bookReviews,
    )..where((table) => table.bookId.equals(internalId))).getSingleOrNull();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.bookReviews)
        .insertOnConflictUpdate(
          BookReviewsCompanion.insert(
            bookId: Value<int>(internalId),
            rating: Value<int?>(normalizedRating),
            content: Value<String>(normalizedContent),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  @override
  Future<void> remove(String bookId) async {
    final internalId = await _bookIdOf(bookId);
    if (internalId == null) {
      return;
    }
    await (_db.delete(
      _db.bookReviews,
    )..where((table) => table.bookId.equals(internalId))).go();
  }

  Future<int?> _bookIdOf(String bookId) async {
    final rows =
        await (_db.select(_db.books)..where(
              (table) => table.uuid.equals(bookId) & table.deletedAt.isNull(),
            ))
            .get();
    return rows.isEmpty ? null : rows.single.id;
  }

  BookReview _toReview(String bookId, BookReviewRow row) => BookReview(
    bookId: bookId,
    rating: row.rating,
    content: row.content,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
  );
}
