import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/decorations/decoration_image_store.dart';

import '../library/revision_anchor_store.dart';
import 'db.dart';

/// 使用书籍版本绑定保存装饰；同一原文区间更新原记录。
class DriftDecorationStore implements ReaderDecorationStore {
  /// 图片清理由宿主提供，引用检查覆盖整个数据库。
  DriftDecorationStore(this._db, String bookId, {this.images})
    : _binding = RevisionBookBinding(_db, bookId);

  final AppDatabase _db;
  final RevisionBookBinding _binding;

  /// 独立图片存储，用于删除无引用图片。
  final ReaderDecorationImageStore? images;

  @override
  Future<List<ReaderDecoration>> list() async {
    final book = await _binding.read();
    if (book == null) return const [];
    final rows =
        await (_db.select(_db.decorations)
              ..where((table) => table.bookId.equals(book.id))
              ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]))
            .get();
    return [for (final row in rows) _toDecoration(row)];
  }

  @override
  Future<ReaderDecoration?> add({
    required String startCfi,
    required String endCfi,
    required String quote,
    required ReaderDecorationStyle style,
    String? contextBefore,
    String? contextAfter,
  }) async {
    final book = await _binding.writable();
    if (book == null) return null;
    final anchor = await _capture(book, startCfi, endCfi, (
      quote: quote,
      before: contextBefore ?? '',
      after: contextAfter ?? '',
    ));
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await _db.transaction(() async {
      if (await _binding.writable() == null) return null;
      final existing =
          await (_db.select(_db.decorations)..where(
                (table) =>
                    table.bookId.equals(book.id) &
                    table.startCfi.equals(startCfi) &
                    table.endCfi.equals(endCfi),
              ))
              .getSingleOrNull();
      if (existing != null) {
        await (_db.update(
          _db.decorations,
        )..where((table) => table.id.equals(existing.id))).write(
          DecorationsCompanion(
            styleJson: Value(jsonEncode(style.toJson())),
            updatedAt: Value(now),
          ),
        );
        return (_db.select(
          _db.decorations,
        )..where((table) => table.id.equals(existing.id))).getSingle();
      }
      final id =
          'dc-$now-${math.Random().nextInt(0x7fffffff).toRadixString(36)}';
      await _db
          .into(_db.decorations)
          .insert(
            DecorationsCompanion.insert(
              id: id,
              bookId: book.id,
              startCfi: startCfi,
              endCfi: endCfi,
              quote: quote,
              contextBefore: Value(contextBefore),
              contextAfter: Value(contextAfter),
              anchorJson: Value(anchor?.encode()),
              styleJson: jsonEncode(style.toJson()),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return (_db.select(
        _db.decorations,
      )..where((table) => table.id.equals(id))).getSingle();
    });
    if (result == null) return null;
    await _cleanImages();
    return _toDecoration(result);
  }

  @override
  Future<void> update(String id, {required ReaderDecorationStyle style}) async {
    await _db.transaction(() async {
      final book = await _binding.writable();
      if (book == null) return;
      await (_db.update(_db.decorations)..where(
            (table) => table.bookId.equals(book.id) & table.id.equals(id),
          ))
          .write(
            DecorationsCompanion(
              styleJson: Value(jsonEncode(style.toJson())),
              updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
            ),
          );
    });
    await _cleanImages();
  }

  @override
  Future<void> remove(String id) async {
    await _db.transaction(() async {
      final book = await _binding.writable();
      if (book == null) return;
      await (_db.delete(_db.decorations)..where(
            (table) => table.bookId.equals(book.id) & table.id.equals(id),
          ))
          .go();
    });
    await _cleanImages();
  }

  @override
  Future<void> relocate(
    String id, {
    required String startCfi,
    required String endCfi,
  }) async {
    final book = await _binding.writable();
    if (book == null) throw const FormatException('书籍内容已更新，请重新打开阅读');
    final row =
        await (_db.select(_db.decorations)..where(
              (table) => table.bookId.equals(book.id) & table.id.equals(id),
            ))
            .getSingleOrNull();
    if (row == null) throw const FormatException('原装饰不存在');
    final original = await _originalAnchor(book, row);
    final anchor = await captureBookAnchor(
      _db,
      book,
      startCfi,
      endCfi: endCfi,
      existing: original,
    );
    if (anchor == null) throw const FormatException('无法确认所选文字的位置');
    await _db.transaction(() async {
      if (await _binding.writable() == null) {
        throw const FormatException('书籍内容已更新，请重新打开阅读');
      }
      await (_db.update(
        _db.decorations,
      )..where((table) => table.id.equals(id))).write(
        DecorationsCompanion(
          startCfi: Value(startCfi),
          endCfi: Value(endCfi),
          anchorJson: Value(anchor.encode()),
        ),
      );
    });
  }

  Future<AnchorRecord?> _capture(
    BookRow book,
    String first,
    String last,
    ({String quote, String before, String after}) evidence,
  ) async {
    final anchor = await captureBookAnchor(_db, book, first, endCfi: last);
    if (anchor == null ||
        normalizeAnchorText(anchor.effective.quote) ==
            normalizeAnchorText(evidence.quote)) {
      return anchor;
    }
    final index = await loadBookAnchorIndex(
      _db,
      book,
      startCfi: first,
      endCfi: last,
    );
    final original = index?.legacyRange(
      startCfi: first,
      endCfi: last,
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

  Future<AnchorRecord> _originalAnchor(BookRow book, DecorationRow row) async {
    final saved = AnchorRecord.decode(row.anchorJson);
    if (saved != null) return saved;
    final index = await loadBookAnchorIndex(
      _db,
      book,
      startCfi: row.startCfi,
      endCfi: row.endCfi,
    );
    final historical = (index ?? AnchorBook(revision: 'legacy', chapters: []))
        .legacyRange(
          startCfi: row.startCfi,
          endCfi: row.endCfi,
          quote: row.quote,
          contextBefore: row.contextBefore ?? '',
          contextAfter: row.contextAfter ?? '',
        );
    if (historical == null) throw const FormatException('无法确认原装饰的内容锚点');
    return AnchorRecord(
      original: historical,
      status: 'pending',
      reason: '旧版本缺少内容锚点',
    );
  }

  Future<void> _cleanImages() async {
    final imageStore = images;
    if (imageStore == null) return;
    await _db.transaction(() async {
      final rows = await _db.select(_db.decorations).get();
      final paths = {
        for (final row in rows)
          if (_style(row.styleJson).backgroundImagePath case final String path)
            path,
      };
      try {
        await imageStore.removeUnused(paths);
      } on FileSystemException {
        return;
      }
    });
  }

  ReaderDecorationStyle _style(String raw) {
    try {
      return ReaderDecorationStyle.fromJson(jsonDecode(raw));
    } on FormatException {
      return const ReaderDecorationStyle();
    }
  }

  ReaderDecoration _toDecoration(DecorationRow row) {
    final anchor = AnchorRecord.decode(row.anchorJson);
    return ReaderDecoration(
      id: row.id,
      startCfi: row.startCfi,
      endCfi: row.endCfi,
      quote: row.quote,
      style: _style(row.styleJson),
      contextBefore: row.contextBefore,
      contextAfter: row.contextAfter,
      anchorData: row.anchorJson,
      relocationStatus: anchor?.status,
      relocationReason: anchor?.reason,
      currentQuote: anchor?.effective.quote,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
    );
  }
}
