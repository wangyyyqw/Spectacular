import 'package:drift/drift.dart';

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

/// drift 阅读会话存储。
class DriftReadingSessionStore implements ReadingSessionStore {
  /// 创建存储。
  DriftReadingSessionStore(this._db);

  final AppDatabase _db;

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
    final internalId = await _bookIdOf(bookId);
    if (internalId == null) {
      return;
    }
    await _db
        .into(_db.readingSessions)
        .insert(
          ReadingSessionsCompanion.insert(
            bookId: internalId,
            startedAt: startedAt.millisecondsSinceEpoch,
            endedAt: endedAt.millisecondsSinceEpoch,
            durationMs: duration.inMilliseconds,
            pageTurns: Value<int>(pageTurns < 0 ? 0 : pageTurns),
            charactersRead: Value<int>(charactersRead < 0 ? 0 : charactersRead),
          ),
        );
  }

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

  Future<int?> _bookIdOf(String bookId) async {
    final rows = await (_db.select(
      _db.books,
    )..where((table) => table.uuid.equals(bookId))).get();
    return rows.isEmpty ? null : rows.single.id;
  }
}
