import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reader_ui/reader_session.dart';

import 'db.dart';

/// 阅读进度的 drift 实现（P4-10）：写 `reading_progress` 表。
///
/// 位置串包含章、页及连续滚动的页内偏移；百分比由 `ProgressWeights`
/// 按字符权重实时计算（P4-09）。
class DriftProgressStore implements ReaderProgressStore {
  /// 创建存储。
  DriftProgressStore(this._db);

  final AppDatabase _db;
  static final RegExp _scrollOffsetPattern = RegExp(r'(?:^|/)scroll:([^/]+)$');

  /// 读取某书进度。
  @override
  Future<ReaderProgress?> load(String bookId) async {
    final row = await _progressRow(bookId);
    if (row == null) {
      return null;
    }
    return ReaderProgress(
      spineIndex: row.spineIndex ?? 0,
      pageIndex: row.pageIndex ?? 0,
      scrollOffset: _scrollOffsetOf(row.locatorCfi),
    );
  }

  /// 写入某书进度（upsert）。
  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    final bookIdValue = await _bookIdOf(bookId);
    if (bookIdValue == null) {
      return;
    }
    await _db
        .into(_db.readingProgress)
        .insertOnConflictUpdate(
          ReadingProgressCompanion(
            bookId: Value<int>(bookIdValue),
            // P5 接入 CFI 前先用可读的位置串占位（§36.2：位置一律存字符串）。
            locatorCfi: Value<String>(_locatorOf(progress)),
            percent: const Value<double>(0),
            spineIndex: Value<int>(progress.spineIndex),
            pageIndex: Value<int>(progress.pageIndex),
            updatedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  /// 清除某书进度（删书时调用）。
  @override
  Future<void> clear(String bookId) async {
    final bookIdValue = await _bookIdOf(bookId);
    if (bookIdValue == null) {
      return;
    }
    await (_db.delete(
      _db.readingProgress,
    )..where((table) => table.bookId.equals(bookIdValue))).go();
  }

  /// 全部进度快照（统计页用）：book uuid → 进度。
  @override
  Future<Map<String, ReaderProgress>> snapshot() async {
    final rows = await _db.select(_db.readingProgress).get();
    if (rows.isEmpty) {
      return const <String, ReaderProgress>{};
    }
    final books = await (_db.select(
      _db.books,
    )..where((table) => table.deletedAt.isNull())).get();
    final uuidById = <int, String>{
      for (final book in books) book.id: book.uuid,
    };
    return <String, ReaderProgress>{
      for (final row in rows)
        if (uuidById[row.bookId] != null)
          uuidById[row.bookId]!: ReaderProgress(
            spineIndex: row.spineIndex ?? 0,
            pageIndex: row.pageIndex ?? 0,
            scrollOffset: _scrollOffsetOf(row.locatorCfi),
          ),
    };
  }

  /// 把旧版 `reader_progress.json` 一次性迁入表（幂等：有进度就跳过）。
  ///
  /// 返回迁移条数；读不到文件返回 0。
  Future<int> migrateLegacyJson(File file) async {
    if (!await file.exists()) {
      return 0;
    }
    final existing = await _db.select(_db.readingProgress).get();
    if (existing.isNotEmpty) {
      return 0;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return 0;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    var migrated = 0;
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) {
        continue;
      }
      final spine = value['spine'];
      final page = value['page'];
      if (spine is! int || page is! int) {
        continue;
      }
      final scroll = value['scroll'];
      final scrollOffset = scroll is num ? scroll.toDouble() : null;
      final bookIdValue = await _bookIdOf(entry.key);
      if (bookIdValue == null) {
        continue;
      }
      await _db
          .into(_db.readingProgress)
          .insertOnConflictUpdate(
            ReadingProgressCompanion(
              bookId: Value<int>(bookIdValue),
              locatorCfi: Value<String>(
                'spine:$spine/page:$page'
                '${scrollOffset == null ? '' : '/scroll:$scrollOffset'}',
              ),
              percent: const Value<double>(0),
              spineIndex: Value<int>(spine),
              pageIndex: Value<int>(page),
              updatedAt: Value<int>(now),
            ),
          );
      migrated += 1;
    }
    return migrated;
  }

  static String _locatorOf(ReaderProgress progress) =>
      'spine:${progress.spineIndex}/page:${progress.pageIndex}'
      '${progress.scrollOffset == null ? '' : '/scroll:${progress.scrollOffset}'}';

  static double? _scrollOffsetOf(String locator) {
    final value = _scrollOffsetPattern.firstMatch(locator)?.group(1);
    final offset = value == null ? null : double.tryParse(value);
    return offset != null && offset.isFinite && offset >= 0 ? offset : null;
  }

  Future<int?> _bookIdOf(String bookUuid) async {
    final rows = await (_db.select(
      _db.books,
    )..where((table) => table.uuid.equals(bookUuid))).get();
    return rows.isEmpty ? null : rows.single.id;
  }

  Future<ProgressRow?> _progressRow(String bookUuid) async {
    final bookIdValue = await _bookIdOf(bookUuid);
    if (bookIdValue == null) {
      return null;
    }
    final rows = await (_db.select(
      _db.readingProgress,
    )..where((table) => table.bookId.equals(bookIdValue))).get();
    return rows.isEmpty ? null : rows.single;
  }
}
