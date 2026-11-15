import 'package:drift/drift.dart';

import '../library/revision_anchor_store.dart' show resolveBookRow;
import 'db.dart';

/// 一次前台阅读会话。
class ReadingSession {
  const ReadingSession({
    required this.bookId,
    required this.startedAt,
    required this.endedAt,
    required this.duration,
    this.pageTurns = 0,
    this.charactersRead = 0,
    this.bookTitle,
  });

  /// 书籍 uuid。
  final String bookId;

  /// 开始时间。
  final DateTime startedAt;

  /// 结束时间。
  final DateTime endedAt;

  /// 有效阅读时长。
  final Duration duration;

  /// 本段阅读完成的翻页次数。
  final int pageTurns;

  /// 本段阅读翻过页面的非空白字符数。
  final int charactersRead;

  /// 读取时附带的书名，让已移出书架的历史记录仍能识别书籍。
  final String? bookTitle;
}

/// 阅读会话存储接口，便于统计页与测试替换实现。
abstract interface class ReadingSessionStore {
  /// 追加一段有效阅读时长。
  /// 持久化实现无法解析书籍身份时抛出 [ReadingSessionSaveException]。
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    int pageTurns = 0,
    int charactersRead = 0,
  });

  /// 全部已保存会话，包含移出书架的书籍，按开始时间升序。
  Future<List<ReadingSession>> list();
}

/// 时段无法保存的身份原因，供生命周期诊断使用。
enum ReadingSessionSaveFailure { bookMissing, mismatchedBinding }

/// 时段无法归属时明确失败，避免统计被静默丢弃。
class ReadingSessionSaveException implements Exception {
  const ReadingSessionSaveException(this.reason);

  final ReadingSessionSaveFailure reason;

  @override
  String toString() => switch (reason) {
    ReadingSessionSaveFailure.bookMissing => '阅读时段未保存：书籍身份无法解析或记录已不存在',
    ReadingSessionSaveFailure.mismatchedBinding => '阅读时段未保存：书籍身份与已绑定会话不一致',
  };
}

/// drift 阅读会话存储。
class DriftReadingSessionStore implements ReadingSessionStore {
  /// 创建存储。
  DriftReadingSessionStore(this._db);

  final AppDatabase _db;

  /// 开始计时前固定整数主键，后续重键或旧标识重导入不改变时段归属。
  ReadingSessionStore bindBook(String bookId) =>
      _BoundReadingSessionStore(this, bookId);

  @override
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    int pageTurns = 0,
    int charactersRead = 0,
  }) async {
    final duration = endedAt.difference(startedAt);
    if (duration <= Duration.zero) {
      return;
    }
    final book = await resolveBookRow(_db, bookId);
    if (book == null) {
      throw const ReadingSessionSaveException(
        ReadingSessionSaveFailure.bookMissing,
      );
    }
    await _addForBook(
      book.id,
      startedAt: startedAt,
      endedAt: endedAt,
      pageTurns: pageTurns,
      charactersRead: charactersRead,
    );
  }

  Future<void> _addForBook(
    int bookId, {
    required DateTime startedAt,
    required DateTime endedAt,
    required int pageTurns,
    required int charactersRead,
  }) => _db.transaction(() async {
    final book = await (_db.select(
      _db.books,
    )..where((table) => table.id.equals(bookId))).getSingleOrNull();
    if (book == null) {
      throw const ReadingSessionSaveException(
        ReadingSessionSaveFailure.bookMissing,
      );
    }
    await _db
        .into(_db.readingSessions)
        .insert(
          ReadingSessionsCompanion.insert(
            bookId: bookId,
            startedAt: startedAt.millisecondsSinceEpoch,
            endedAt: endedAt.millisecondsSinceEpoch,
            durationMs: endedAt.difference(startedAt).inMilliseconds,
            pageTurns: Value<int>(pageTurns < 0 ? 0 : pageTurns),
            charactersRead: Value<int>(charactersRead < 0 ? 0 : charactersRead),
          ),
        );
  });

  @override
  Future<List<ReadingSession>> list() async {
    final sessions = _db.readingSessions;
    final books = _db.books;
    final query =
        _db.select(sessions).join([
          innerJoin(books, books.id.equalsExp(sessions.bookId)),
        ])..orderBy([
          OrderingTerm.asc(sessions.startedAt),
          OrderingTerm.asc(sessions.id),
        ]);
    final rows = await query.get();
    return [
      for (final row in rows)
        _toSession(row.readTable(sessions), row.readTable(books)),
    ];
  }

  ReadingSession _toSession(ReadingSessionRow row, BookRow book) =>
      ReadingSession(
        bookId: book.uuid,
        bookTitle: book.title,
        startedAt: DateTime.fromMillisecondsSinceEpoch(row.startedAt),
        endedAt: DateTime.fromMillisecondsSinceEpoch(row.endedAt),
        duration: Duration(milliseconds: row.durationMs),
        pageTurns: row.pageTurns,
        charactersRead: row.charactersRead,
      );
}

class _BoundReadingSessionStore implements ReadingSessionStore {
  _BoundReadingSessionStore(this._store, this._bookId)
    : _initialBookId = resolveBookRow(
        _store._db,
        _bookId,
      ).then((book) => book?.id) {
    _initialBookId.ignore();
  }

  final DriftReadingSessionStore _store;
  final String _bookId;
  final Future<int?> _initialBookId;

  @override
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    int pageTurns = 0,
    int charactersRead = 0,
  }) async {
    if (endedAt.difference(startedAt) <= Duration.zero) return;
    if (bookId != _bookId) {
      throw const ReadingSessionSaveException(
        ReadingSessionSaveFailure.mismatchedBinding,
      );
    }
    final internalId = await _initialBookId;
    if (internalId == null) {
      throw const ReadingSessionSaveException(
        ReadingSessionSaveFailure.bookMissing,
      );
    }
    await _store._addForBook(
      internalId,
      startedAt: startedAt,
      endedAt: endedAt,
      pageTurns: pageTurns,
      charactersRead: charactersRead,
    );
  }

  @override
  Future<List<ReadingSession>> list() => _store.list();
}
