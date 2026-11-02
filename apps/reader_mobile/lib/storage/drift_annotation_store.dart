import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reader_ui/annotations/annotation.dart';

import 'db.dart';

/// 标注存储的 drift 实现（P4-17）：写 `annotations` 表（type 0 高亮 / 1 笔记）。
class DriftAnnotationStore implements ReaderAnnotationStore {
  /// 创建存储。
  DriftAnnotationStore(this._db, this._bookUuid);

  final AppDatabase _db;
  final String _bookUuid;

  @override
  Future<List<ReaderAnnotation>> list() async {
    final bookId = await _bookIdOf();
    if (bookId == null) {
      return const <ReaderAnnotation>[];
    }
    final rows =
        await (_db.select(_db.annotations)
              ..where(
                (table) =>
                    table.bookId.equals(bookId) &
                    table.type.isSmallerThanValue(2),
              )
              ..orderBy([(table) => OrderingTerm(expression: table.createdAt)]))
            .get();
    return <ReaderAnnotation>[
      for (final row in rows) _toAnnotation(row),
    ];
  }

  @override
  Future<ReaderAnnotation?> add({
    required ReaderAnnotationType type,
    required String startCfi,
    required String endCfi,
    required String quote,
    String? contextBefore,
    String? contextAfter,
    int? color,
    ReaderAnnotationStyle style = ReaderAnnotationStyle.background,
    String? note,
  }) async {
    final bookId = await _bookIdOf();
    if (bookId == null) {
      return null;
    }
    // 同一区间不重复（同类型 + 同起止 CFI）。
    final existing = await (_db.select(_db.annotations)
          ..where(
            (table) =>
                table.bookId.equals(bookId) &
                table.type.equals(type.storageValue) &
                table.startCfi.equals(startCfi) &
                table.endCfi.equals(endCfi),
          ))
        .get();
    if (existing.isNotEmpty) {
      return null;
    }
    final now = DateTime.now();
    final id = 'an-${now.millisecondsSinceEpoch}-'
        '${math.Random().nextInt(0x7FFFFFFF).toRadixString(36)}';
    await _db.into(_db.annotations).insert(
      AnnotationsCompanion.insert(
        id: id,
        bookId: bookId,
        type: type.storageValue,
        startCfi: startCfi,
        endCfi: endCfi,
        quote: quote,
        contextBefore: Value<String?>(contextBefore),
        contextAfter: Value<String?>(contextAfter),
        style: Value<int?>(style.storageValue),
        color: Value<int?>(color),
        note: Value<String?>(note),
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      ),
    );
    return ReaderAnnotation(
      id: id,
      type: type,
      startCfi: startCfi,
      endCfi: endCfi,
      quote: quote,
      contextBefore: contextBefore,
      contextAfter: contextAfter,
      color: color,
      style: style,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> update(
    String id, {
    int? color,
    ReaderAnnotationStyle? style,
    String? note,
  }) async {
    await (_db.update(_db.annotations)
          ..where((table) => table.id.equals(id)))
        .write(
          AnnotationsCompanion(
            color: color == null ? const Value<int?>.absent() : Value<int?>(color),
            style: style == null
                ? const Value<int?>.absent()
                : Value<int?>(style.storageValue),
            note: note == null ? const Value<String?>.absent() : Value<String?>(note),
            updatedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  @override
  Future<void> remove(String id) async {
    await (_db.delete(
      _db.annotations,
    )..where((table) => table.id.equals(id))).go();
  }

  ReaderAnnotation _toAnnotation(AnnotationRow row) => ReaderAnnotation(
    id: row.id,
    type: ReaderAnnotationType.fromStorage(row.type),
    startCfi: row.startCfi,
    endCfi: row.endCfi,
    quote: row.quote,
    contextBefore: row.contextBefore,
    contextAfter: row.contextAfter,
    color: row.color,
    style: ReaderAnnotationStyle.fromStorage(row.style),
    note: row.note,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
  );

  Future<int?> _bookIdOf() async {
    final rows = await (_db.select(
      _db.books,
    )..where((table) => table.uuid.equals(_bookUuid))).get();
    return rows.isEmpty ? null : rows.single.id;
  }
}
