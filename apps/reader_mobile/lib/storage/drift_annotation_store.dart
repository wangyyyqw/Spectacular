import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_core/position/location_anchor.dart';

import '../library/revision_anchor_store.dart';
import 'db.dart';

/// 标注存储的 drift 实现（P4-17）：写 `annotations` 表（type 0 高亮 / 1 笔记）。
class DriftAnnotationStore
    implements ReaderAnnotationStore, RelocatableAnnotationStore {
  /// 创建存储。
  DriftAnnotationStore(this._db, String bookUuid)
    : _binding = RevisionBookBinding(_db, bookUuid);

  final AppDatabase _db;
  final RevisionBookBinding _binding;

  @override
  Future<List<ReaderAnnotation>> list() async {
    final bookId = (await _binding.read())?.id;
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
    return <ReaderAnnotation>[for (final row in rows) _toAnnotation(row)];
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
    final book = await _binding.writable();
    if (book == null) {
      return null;
    }
    final bookId = book.id;
    final anchor = await _captureSelection(book, startCfi, endCfi, (
      quote: quote,
      before: contextBefore ?? '',
      after: contextAfter ?? '',
    ));
    final now = DateTime.now();
    final id =
        'an-${now.millisecondsSinceEpoch}-'
        '${math.Random().nextInt(0x7FFFFFFF).toRadixString(36)}';
    final inserted = await _db.transaction(() async {
      if (await _binding.writable() == null) return false;
      // 同一区间不重复（同类型 + 同起止 CFI）。
      final existing =
          await (_db.select(_db.annotations)..where(
                (table) =>
                    table.bookId.equals(bookId) &
                    table.type.equals(type.storageValue) &
                    table.startCfi.equals(startCfi) &
                    table.endCfi.equals(endCfi),
              ))
              .get();
      if (existing.isNotEmpty) return false;
      await _db
          .into(_db.annotations)
          .insert(
            AnnotationsCompanion.insert(
              id: id,
              bookId: bookId,
              type: type.storageValue,
              startCfi: startCfi,
              endCfi: endCfi,
              anchorJson: Value(anchor?.encode()),
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
      return true;
    });
    if (!inserted) return null;
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
      relocationStatus: anchor?.status,
      relocationReason: anchor?.reason,
      currentQuote: anchor?.effective.quote,
      anchorData: anchor?.encode(),
    );
  }

  @override
  Future<void> update(
    String id, {
    ReaderAnnotationType? type,
    int? color,
    ReaderAnnotationStyle? style,
    String? note,
    bool clearNote = false,
  }) async {
    await _db.transaction(() async {
      final book = await _binding.writable();
      if (book == null) return;
      await (_db.update(_db.annotations)..where(
            (table) => table.id.equals(id) & table.bookId.equals(book.id),
          ))
          .write(
            AnnotationsCompanion(
              type: type == null
                  ? const Value<int>.absent()
                  : Value<int>(type.storageValue),
              color: color == null
                  ? const Value<int?>.absent()
                  : Value<int?>(color),
              style: style == null
                  ? const Value<int?>.absent()
                  : Value<int?>(style.storageValue),
              note: clearNote
                  ? const Value<String?>(null)
                  : note == null
                  ? const Value<String?>.absent()
                  : Value<String?>(note),
              updatedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
            ),
          );
    });
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
  Future<void> relocate(
    String id, {
    required String startCfi,
    required String endCfi,
  }) async {
    final book = await _binding.writable();
    if (book == null) throw const FormatException('书籍内容已更新，请重新打开阅读');
    final row =
        await (_db.select(_db.annotations)..where(
              (table) => table.id.equals(id) & table.bookId.equals(book.id),
            ))
            .getSingleOrNull();
    if (row == null) throw const FormatException('原标注不存在');
    final anchor = await captureBookAnchor(
      _db,
      book,
      startCfi,
      endCfi: endCfi,
      existing: await originalAnnotationAnchor(_db, book, row),
    );
    if (anchor == null) throw const FormatException('无法确认所选文字的位置');
    await _db.transaction(() async {
      if (await _binding.writable() == null) {
        throw const FormatException('书籍内容已更新，请重新打开阅读');
      }
      await (_db.update(
        _db.annotations,
      )..where((table) => table.id.equals(id))).write(
        AnnotationsCompanion(
          startCfi: Value(startCfi),
          endCfi: Value(endCfi),
          anchorJson: Value(anchor.encode()),
        ),
      );
    });
  }

  /// 无法对应原引用的合法偏移也不能标成可靠定位。
  Future<AnchorRecord?> _captureSelection(
    BookRow book,
    String startCfi,
    String endCfi,
    ({String quote, String before, String after}) evidence,
  ) async {
    final anchor = await captureBookAnchor(_db, book, startCfi, endCfi: endCfi);
    if (anchor == null ||
        _matchingText(anchor.effective.quote) ==
            _matchingText(evidence.quote)) {
      return anchor;
    }
    final index = await loadBookAnchorIndex(
      _db,
      book,
      startCfi: startCfi,
      endCfi: endCfi,
    );
    final original = index?.legacyRange(
      startCfi: startCfi,
      endCfi: endCfi,
      quote: evidence.quote,
      contextBefore: evidence.before,
      contextAfter: evidence.after,
    );
    return original == null
        ? null
        : AnchorRecord(
            original: original,
            status: 'pending',
            reason: '原引用与当前位置文字不一致',
          );
  }

  String _matchingText(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  ReaderAnnotation _toAnnotation(AnnotationRow row) {
    final anchor = AnchorRecord.decode(row.anchorJson);
    return ReaderAnnotation(
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
      relocationStatus: anchor?.status,
      relocationReason: anchor?.reason,
      currentQuote: anchor?.effective.quote,
      anchorData: row.anchorJson,
    );
  }
}
