import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/position/location_anchor.dart';

import '../diagnostics/reader_log.dart';
import '../library/revision_anchor_store.dart';

import 'package:reader_core/epub/epub_chapter_source.dart';

import 'db.dart';

/// 阅读进度的 drift 实现（P4-10）：写 `reading_progress` 表。
///
/// 当前内容锚点、章页坐标及滚动偏移分别保存；百分比复用归档条目权重，
/// 结合当前章锚点比例计算，不为保存进度扫描全书。
class DriftProgressStore implements ReaderProgressStore {
  /// 创建存储。
  DriftProgressStore(this._db);

  final AppDatabase _db;
  final _rejectedSaves = <ReaderProgressSaveResult, int>{};

  /// 阅读期间借用现有章节源，避免保存进度和笔记时重新打开整本 EPUB。
  Future<void Function()> bindSource(
    String bookId,
    EpubChapterSource source,
    String revision,
  ) => bindReadingAnchorSource(_db, bookId, source, revision);

  /// 读取某书进度。
  @override
  Future<ReaderProgress?> load(String bookId) async {
    final book = await resolveBookRow(_db, bookId);
    if (book == null) return null;
    final row = await _rowFor(book.id);
    return row == null ? null : _toProgress(book, row);
  }

  /// 真实 CFI 与内容版本一起保存；旧阅读会话不得回写新版。
  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    final result = await saveResult(bookId, progress);
    if (result != ReaderProgressSaveResult.saved) {
      throw ReaderProgressSaveException(result);
    }
  }

  /// 返回成功、过期或书籍不存在；其他存储异常仍向调用方抛出。
  Future<ReaderProgressSaveResult> saveResult(
    String bookId,
    ReaderProgress progress,
  ) async {
    final book = await resolveBookRow(_db, bookId, allowAliases: false);
    if (book == null) {
      final alias = await resolveBookRow(_db, bookId);
      return _rejectSave(
        bookId,
        alias != null && alias.deletedAt == null
            ? ReaderProgressSaveResult.stale
            : ReaderProgressSaveResult.bookMissing,
      );
    }
    if (book.deletedAt != null) {
      return _rejectSave(bookId, ReaderProgressSaveResult.bookMissing);
    }
    final result = _matchesRevision(book, progress)
        ? await _saveCurrent(book, progress)
        : ReaderProgressSaveResult.stale;
    return result == ReaderProgressSaveResult.saved
        ? result
        : _rejectSave(bookId, result);
  }

  Future<ReaderProgressSaveResult> _saveCurrent(
    BookRow book,
    ReaderProgress progress,
  ) async {
    try {
      return await _prepareAndWriteProgress(book, progress);
    } catch (error, stack) {
      final result = await _currentSaveResult(book, progress);
      if (result != ReaderProgressSaveResult.saved) return result;
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<ReaderProgressSaveResult> _prepareAndWriteProgress(
    BookRow book,
    ReaderProgress progress,
  ) async {
    final prior = await _rowFor(book.id);
    final record = progress.cfi == null
        ? null
        : await captureBookAnchor(
            _db,
            book,
            progress.cfi!,
            approximate: progress.approximate,
            existing: AnchorRecord.decode(prior?.anchorJson),
          );
    if (progress.cfi != null && record == null) {
      throw StateError('无法保存阅读位置的内容锚点，请重试');
    }
    final readingPercent = progress.readingPercent;
    final percent = readingPercent == null
        ? await _percentOf(book, record)
        : (readingPercent * 100).clamp(0.0, 100.0);
    return _db.transaction(
      () => _writeProgress(book, progress, record, percent),
    );
  }

  Future<ReaderProgressSaveResult> _writeProgress(
    BookRow book,
    ReaderProgress progress,
    AnchorRecord? record,
    double percent,
  ) async {
    final result = await _currentSaveResult(book, progress);
    if (result != ReaderProgressSaveResult.saved) return result;
    final saved = await _rowFor(book.id);
    await _db
        .into(_db.readingProgress)
        .insertOnConflictUpdate(
          _progressValues(book.id, progress, record, saved, percent),
        );
    return ReaderProgressSaveResult.saved;
  }

  Future<ReaderProgressSaveResult> _currentSaveResult(
    BookRow book,
    ReaderProgress progress,
  ) async {
    final current = await (_db.select(
      _db.books,
    )..where((table) => table.id.equals(book.id))).getSingleOrNull();
    if (current == null || current.deletedAt != null) {
      return ReaderProgressSaveResult.bookMissing;
    }
    return _sameContent(book, current) && _matchesRevision(current, progress)
        ? ReaderProgressSaveResult.saved
        : ReaderProgressSaveResult.stale;
  }

  Future<ReaderProgressSaveResult> _rejectSave(
    String bookId,
    ReaderProgressSaveResult result,
  ) async {
    final count = (_rejectedSaves[result] ?? 0) + 1;
    _rejectedSaves[result] = count;
    await ReaderLog.instance.log(
      'progress_save_rejected',
      fields: {
        'book_id': bookId,
        'status': result == ReaderProgressSaveResult.stale
            ? 'stale'
            : 'missing',
        'count': count,
      },
    );
    return result;
  }

  ReadingProgressCompanion _progressValues(
    int bookId,
    ReaderProgress progress,
    AnchorRecord? record,
    ProgressRow? saved,
    double percent,
  ) {
    // 无真实位置的调用用于书架读完标记，不能清掉已有内容锚点。
    final preserveLocation =
        progress.cfi == null && AnchorRecord.decode(saved?.anchorJson) != null;
    return ReadingProgressCompanion(
      bookId: Value(bookId),
      locatorCfi: Value(
        preserveLocation ? saved!.locatorCfi : progress.cfi ?? '',
      ),
      anchorJson: Value(
        preserveLocation
            ? saved!.anchorJson
            : _encodeAnchor(record, saved, progress),
      ),
      percent: Value(preserveLocation ? saved!.percent : percent),
      spineIndex: Value(
        preserveLocation ? saved!.spineIndex : progress.spineIndex,
      ),
      pageIndex: Value(
        preserveLocation ? saved!.pageIndex : progress.pageIndex,
      ),
      finished: Value(progress.finished),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    );
  }

  Future<double> _percentOf(BookRow book, AnchorRecord? record) async {
    if (record == null) return 0;
    final point = record.effective.start;
    final weights = await loadBookProgressIndex(_db, book);
    if (weights == null) return 0;
    if (point.chapterLength == 0) {
      final elementPercent = await loadElementReadingPercent(
        _db,
        book,
        point.cfi,
      );
      if (elementPercent != null) return elementPercent * 100;
    }
    final ratio = point.chapterLength == 0
        ? 0.0
        : point.charOffset / point.chapterLength;
    return weights.percentOf(point.spineIndex, ratio) * 100;
  }

  String? _encodeAnchor(
    AnchorRecord? record,
    ProgressRow? saved,
    ReaderProgress progress,
  ) {
    final metadata = <String, Object?>{
      if (progress.scrollOffset != null) 'scrollOffset': progress.scrollOffset,
      if (progress.layoutFingerprint != null)
        'layoutFingerprint': progress.layoutFingerprint,
    };
    if (record == null) {
      return metadata.isEmpty ? null : jsonEncode(metadata);
    }
    final original = AnchorRecord.decode(saved?.anchorJson)?.original;
    return jsonEncode({
      ...AnchorRecord(
        original: original ?? record.original,
        current: original == null ? record.current : record.effective,
        status: record.status,
        reason: record.reason,
      ).toJson(),
      ...metadata,
    });
  }

  bool _matchesRevision(BookRow book, ReaderProgress progress) =>
      progress.contentRevision == book.contentRevision ||
      (progress.contentRevision == null && progress.cfi == null);

  bool _sameContent(BookRow first, BookRow second) =>
      first.uuid == second.uuid &&
      first.sourcePath == second.sourcePath &&
      first.contentRevision == second.contentRevision &&
      first.layoutVersion == second.layoutVersion;

  /// 清除某书进度（删书时调用）。
  @override
  Future<void> clear(String bookId) async {
    final bookIdValue = (await resolveBookRow(
      _db,
      bookId,
      allowAliases: false,
    ))?.id;
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
    final booksById = {for (final book in books) book.id: book};
    final result = <String, ReaderProgress>{};
    for (final row in rows) {
      final book = booksById[row.bookId];
      if (book == null) continue;
      result[book.uuid] = _toProgress(book, row);
    }
    return result;
  }

  ReaderProgress _toProgress(BookRow book, ProgressRow row) {
    final record = AnchorRecord.decode(row.anchorJson);
    final usable = record != null && record.status != 'pending';
    final anchor = usable ? record.effective : null;
    return ReaderProgress(
      spineIndex: anchor?.start.spineIndex ?? row.spineIndex ?? 0,
      pageIndex: row.pageIndex ?? 0,
      finished: row.finished,
      scrollOffset: _anchorScrollOffset(row.anchorJson),
      cfi: anchor?.start.cfi,
      contentRevision: anchor?.revision ?? book.contentRevision,
      // 没有可靠内容锚点的位置只能近似恢复。
      approximate:
          record == null ||
          record.status == 'pending' ||
          record.status == 'approximate' ||
          anchor?.approximate == true,
      readingPercent: (row.percent / 100).clamp(0.0, 1.0),
      layoutFingerprint: _anchorLayoutFingerprint(row.anchorJson),
    );
  }

  double? _anchorScrollOffset(String? source) {
    if (source == null) return null;
    try {
      final value =
          (jsonDecode(source) as Map<String, dynamic>)['scrollOffset'];
      final offset = value is num ? value.toDouble() : null;
      return offset != null && offset.isFinite && offset >= 0 ? offset : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  String? _anchorLayoutFingerprint(String? source) {
    if (source == null) return null;
    try {
      final value =
          (jsonDecode(source) as Map<String, dynamic>)['layoutFingerprint'];
      return value is String && value.isNotEmpty ? value : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<ProgressRow?> _rowFor(int bookId) => (_db.select(
    _db.readingProgress,
  )..where((table) => table.bookId.equals(bookId))).getSingleOrNull();
}
