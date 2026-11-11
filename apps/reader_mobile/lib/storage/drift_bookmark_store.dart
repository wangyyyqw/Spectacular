import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/revision_anchor_store.dart';
import 'db.dart';

/// 书签存储的 drift 实现（P4-13）：写 `annotations` 表，`type = 2`。
///
/// 位置一律存 CFI（§36.2）：重排后页号会变、CFI 不变，所以书签仍能定位。
class DriftBookmarkStore
    implements ReaderBookmarkStore, RelocatableBookmarkStore {
  /// 创建存储。
  DriftBookmarkStore(this._db, String bookUuid)
    : _binding = RevisionBookBinding(_db, bookUuid);

  final AppDatabase _db;
  final RevisionBookBinding _binding;

  /// 书签类型（P4-13）：0 高亮、1 笔记、2 书签。
  static const int _typeBookmark = 2;

  @override
  Future<List<ReaderBookmark>> list() async {
    final book = await _binding.read();
    if (book == null) {
      return const <ReaderBookmark>[];
    }
    final rows =
        await (_db.select(_db.annotations)
              ..where(
                (table) =>
                    table.bookId.equals(book.id) &
                    table.type.equals(_typeBookmark),
              )
              ..orderBy([(table) => OrderingTerm(expression: table.createdAt)]))
            .get();
    return [for (final row in rows) _toBookmark(row)]
      ..sort((a, b) => a.spineIndex.compareTo(b.spineIndex));
  }

  ReaderBookmark _toBookmark(AnnotationRow row) {
    final anchor = AnchorRecord.decode(row.anchorJson);
    final cfi = anchor != null && anchor.isResolved
        ? anchor.effective.start.cfi
        : row.startCfi;
    return ReaderBookmark(
      id: row.id,
      cfi: cfi,
      spineIndex: _spineIndexOf(cfi),
      label: row.quote,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      relocationStatus: anchor?.status ?? 'pending',
      relocationReason:
          anchor?.reason ?? (anchor == null ? '内容锚点缺失或格式不受支持，请重新建立记录' : null),
      currentQuote: anchor?.effective.quote,
    );
  }

  @override
  Future<ReaderBookmark?> add({
    required String cfi,
    required int spineIndex,
    required String label,
  }) async {
    final book = await _binding.writable();
    if (book == null) {
      return null;
    }
    final bookId = book.id;
    final anchor = await captureBookAnchor(_db, book, cfi);
    final now = DateTime.now();
    final id =
        'bm-${now.millisecondsSinceEpoch}-'
        '${math.Random().nextInt(0x7FFFFFFF).toRadixString(36)}';
    final inserted = await _db.transaction(() async {
      if (await _binding.writable() == null) return false;
      final existing =
          await (_db.select(_db.annotations)..where(
                (table) =>
                    table.bookId.equals(bookId) &
                    table.type.equals(_typeBookmark) &
                    table.startCfi.equals(cfi),
              ))
              .get();
      if (existing.isNotEmpty) return false;
      await _db
          .into(_db.annotations)
          .insert(
            AnnotationsCompanion.insert(
              id: id,
              bookId: bookId,
              type: _typeBookmark,
              startCfi: cfi,
              endCfi: cfi,
              anchorJson: Value(anchor?.encode()),
              quote: label,
              createdAt: now.millisecondsSinceEpoch,
              updatedAt: now.millisecondsSinceEpoch,
            ),
          );
      return true;
    });
    if (!inserted) return null;
    return ReaderBookmark(
      id: id,
      cfi: cfi,
      spineIndex: spineIndex,
      label: label,
      createdAt: now,
      relocationStatus: anchor?.status ?? 'pending',
      currentQuote: anchor?.effective.quote,
    );
  }

  @override
  Future<void> remove(String id) => _db.transaction(() async {
    final book = await _binding.writable();
    if (book == null) return;
    await (_db.delete(
          _db.annotations,
        )..where((table) => table.id.equals(id) & table.bookId.equals(book.id)))
        .go();
  });

  @override
  Future<void> relocate(String id, {required String cfi}) async {
    final book = await _binding.writable();
    if (book == null) throw const FormatException('书籍内容已更新，请重新打开阅读');
    final row =
        await (_db.select(_db.annotations)..where(
              (table) =>
                  table.id.equals(id) &
                  table.bookId.equals(book.id) &
                  table.type.equals(_typeBookmark),
            ))
            .getSingleOrNull();
    if (row == null) throw const FormatException('原书签不存在');
    final anchor = await captureBookAnchor(
      _db,
      book,
      cfi,
      existing: requireAnchorRecord(row.anchorJson),
    );
    if (anchor == null) throw const FormatException('无法确认当前阅读位置');
    await _db.transaction(() async {
      if (await _binding.writable() == null) {
        throw const FormatException('书籍内容已更新，请重新打开阅读');
      }
      await (_db.update(
        _db.annotations,
      )..where((table) => table.id.equals(id))).write(
        AnnotationsCompanion(
          startCfi: Value(cfi),
          endCfi: Value(cfi),
          anchorJson: Value(anchor.encode()),
        ),
      );
    });
  }

  static int _spineIndexOf(String cfi) {
    final parsed = EpubCfi.parse(cfi);
    return parsed == null ? 0 : (spineIndexOfCfi(parsed) ?? 0);
  }
}
