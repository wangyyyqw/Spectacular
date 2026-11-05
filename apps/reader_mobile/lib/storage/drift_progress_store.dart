import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/position/location_anchor.dart';

import '../library/revision_anchor_store.dart';
import '../reader/epub_chapter_source.dart';

import 'db.dart';

/// 阅读进度的 drift 实现（P4-10）：写 `reading_progress` 表。
///
/// 位置串包含章、页及连续滚动的页内偏移；百分比复用导入字数权重，
/// 结合当前章锚点比例计算，不为保存进度扫描全书。
class DriftProgressStore implements ReaderProgressStore {
  /// 创建存储。
  DriftProgressStore(this._db);

  final AppDatabase _db;
  static final RegExp _scrollOffsetPattern = RegExp(r'(?:^|/)scroll:([^/]+)$');

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
    return row == null ? null : _toProgress(row);
  }

  /// 真实 CFI 与内容版本一起保存；旧阅读会话不得回写新版。
  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    final book = await resolveBookRow(_db, bookId, allowAliases: false);
    if (book == null || book.deletedAt != null) return;
    if (!await _matchesRevision(book, progress)) return;
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
    final percent = await _percentOf(book, record);
    await _db.transaction(
      () => _writeProgress(book, progress, record, percent),
    );
  }

  Future<void> _writeProgress(
    BookRow book,
    ReaderProgress progress,
    AnchorRecord? record,
    double percent,
  ) async {
    final current = await resolveBookRow(_db, book.uuid, allowAliases: false);
    if (current == null ||
        current.deletedAt != null ||
        !_sameContent(book, current)) {
      return;
    }
    final saved = await _rowFor(book.id);
    await _db
        .into(_db.readingProgress)
        .insertOnConflictUpdate(
          _progressValues(book.id, progress, record, saved, percent),
        );
  }

  ReadingProgressCompanion _progressValues(
    int bookId,
    ReaderProgress progress,
    AnchorRecord? record,
    ProgressRow? saved,
    double percent,
  ) {
    // 无真实位置的调用用于书架读完标记，不能清掉已有内容锚点。
    final preserveLocation = progress.cfi == null && saved?.anchorJson != null;
    return ReadingProgressCompanion(
      bookId: Value(bookId),
      locatorCfi: Value(
        preserveLocation
            ? saved!.locatorCfi
            : progress.cfi ?? _locatorOf(progress),
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
    final chapter =
        await (_db.select(_db.spineItems)..where(
              (table) =>
                  table.bookId.equals(book.id) &
                  table.spineIndex.equals(point.spineIndex),
            ))
            .getSingleOrNull();
    final ratio = point.chapterLength == 0
        ? 0.0
        : point.charOffset / point.chapterLength;
    if (chapter == null || book.charCount <= 0) {
      // 兼容尚无导入字数统计的旧书，按章等权；单章仍保留精确比例。
      final count = book.spineCount > 0 ? book.spineCount : 1;
      return ((point.spineIndex + ratio) / count * 100).clamp(0, 100);
    }
    final sum = _db.spineItems.charCount.sum();
    final totals = await (_db.selectOnly(_db.spineItems)
          ..addColumns([sum])
          ..where(
            _db.spineItems.bookId.equals(book.id) &
                _db.spineItems.linear.equals(1),
          ))
        .getSingle();
    final total = totals.read(sum) ?? 0;
    if (total <= 0) return 0;
    final before = chapter.charStart ?? 0;
    final within = chapter.linear == 0 ? 0 : (chapter.charCount ?? 0) * ratio;
    return ((before + within) / total * 100).clamp(0, 100);
  }

  String? _encodeAnchor(
    AnchorRecord? record,
    ProgressRow? saved,
    ReaderProgress progress,
  ) {
    if (record == null) return null;
    final original = AnchorRecord.decode(saved?.anchorJson)?.original;
    return jsonEncode({
      ...AnchorRecord(
        original: original ?? record.original,
        current: original == null ? record.current : record.effective,
        status: record.status,
        reason: record.reason,
      ).toJson(),
      if (progress.scrollOffset != null) 'scrollOffset': progress.scrollOffset,
    });
  }

  Future<bool> _matchesRevision(BookRow book, ReaderProgress progress) async {
    final revision = progress.contentRevision;
    if (revision == null) {
      return progress.cfi == null || book.contentRevision == null;
    }
    if (book.contentRevision != null) return revision == book.contentRevision;
    final cfi = progress.cfi;
    if (cfi == null) return false;
    final index = await loadBookAnchorIndex(_db, book, startCfi: cfi);
    return index?.revision == revision;
  }

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
    return <String, ReaderProgress>{
      for (final row in rows)
        if (booksById[row.bookId] != null)
          booksById[row.bookId]!.uuid: _toProgress(row),
    };
  }

  ReaderProgress _toProgress(ProgressRow row) {
    final record = AnchorRecord.decode(row.anchorJson);
    final usable = record != null && record.status != 'pending';
    final anchor = usable ? record.effective : null;
    return ReaderProgress(
      spineIndex: anchor?.start.spineIndex ?? row.spineIndex ?? 0,
      pageIndex: row.pageIndex ?? 0,
      finished: row.finished,
      scrollOffset:
          _anchorScrollOffset(row.anchorJson) ??
          _scrollOffsetOf(row.locatorCfi),
      cfi: record?.status == 'pending'
          ? null
          : anchor?.start.cfi ??
                (row.locatorCfi.startsWith('epubcfi(') ? row.locatorCfi : null),
      contentRevision: anchor?.revision,
      approximate:
          record?.status == 'approximate' || anchor?.approximate == true,
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
      final bookIdValue = (await resolveBookRow(_db, entry.key))?.id;
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
              finished: Value<bool>(value['finished'] == true),
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

  Future<ProgressRow?> _rowFor(int bookId) => (_db.select(
    _db.readingProgress,
  )..where((table) => table.bookId.equals(bookId))).getSingleOrNull();
}
