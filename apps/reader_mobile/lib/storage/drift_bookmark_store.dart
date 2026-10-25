import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/reader_session.dart';

import 'db.dart';

/// 书签存储的 drift 实现（P4-13）：写 `annotations` 表，`type = 2`。
///
/// 位置一律存 CFI（§36.2）：重排后页号会变、CFI 不变，所以书签仍能定位。
class DriftBookmarkStore implements ReaderBookmarkStore {
  /// 创建存储。
  DriftBookmarkStore(this._db, this._bookUuid);

  final AppDatabase _db;
  final String _bookUuid;

  /// 书签类型（P4-13）：0 高亮、1 笔记、2 书签。
  static const int _typeBookmark = 2;

  @override
  Future<List<ReaderBookmark>> list() async {
    final bookId = await _bookIdOf();
    if (bookId == null) {
      return const <ReaderBookmark>[];
    }
    final rows =
        await (_db.select(_db.annotations)
              ..where(
                (table) =>
                    table.bookId.equals(bookId) &
                    table.type.equals(_typeBookmark),
              )
              ..orderBy([
                (table) => OrderingTerm(expression: table.createdAt),
              ]))
            .get();
    return <ReaderBookmark>[
      for (final row in rows)
        ReaderBookmark(
          id: row.id,
          cfi: row.startCfi,
          spineIndex: _spineIndexOf(row.startCfi),
          label: row.quote,
          createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
        ),
    ]..sort((a, b) => a.spineIndex.compareTo(b.spineIndex));
  }

  @override
  Future<ReaderBookmark?> add({
    required String cfi,
    required int spineIndex,
    required String label,
  }) async {
    final bookId = await _bookIdOf();
    if (bookId == null) {
      return null;
    }
    final existing = await (_db.select(_db.annotations)
          ..where(
            (table) =>
                table.bookId.equals(bookId) &
                table.type.equals(_typeBookmark) &
                table.startCfi.equals(cfi),
          ))
        .get();
    if (existing.isNotEmpty) {
      return null;
    }
    final now = DateTime.now();
    final id = 'bm-${now.millisecondsSinceEpoch}-'
        '${math.Random().nextInt(0x7FFFFFFF).toRadixString(36)}';
    await _db.into(_db.annotations).insert(
      AnnotationsCompanion.insert(
        id: id,
        bookId: bookId,
        type: _typeBookmark,
        startCfi: cfi,
        endCfi: cfi,
        quote: label,
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      ),
    );
    return ReaderBookmark(
      id: id,
      cfi: cfi,
      spineIndex: spineIndex,
      label: label,
      createdAt: now,
    );
  }

  @override
  Future<void> remove(String id) async {
    await (_db.delete(
      _db.annotations,
    )..where((table) => table.id.equals(id))).go();
  }

  Future<int?> _bookIdOf() async {
    final rows = await (_db.select(
      _db.books,
    )..where((table) => table.uuid.equals(_bookUuid))).get();
    return rows.isEmpty ? null : rows.single.id;
  }

  static int _spineIndexOf(String cfi) {
    final parsed = EpubCfi.parse(cfi);
    return parsed == null ? 0 : (spineIndexOfCfi(parsed) ?? 0);
  }
}
