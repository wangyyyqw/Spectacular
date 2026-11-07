import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/position/locator.dart';
import 'package:reader_core/position/text_length.dart';

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
  static const int _characterIndexVersion = 2;
  static const String _characterIndexPrefix = 'character-index-v2:';
  final Map<String, Future<ProgressWeights?>> _characterIndexTasks =
      <String, Future<ProgressWeights?>>{};

  /// 旧书首次打开时按新的正文聚合语义刷新字符统计。
  ///
  /// 结果按「书籍 + 内容摘要」记录在现有设置表；已是最新时直接返回，
  /// 阅读期间不再扫描整本书。扫描可被 [isCancelled] 中止，未完成不写库。
  Future<ProgressWeights?> ensureCharacterIndex(
    String bookId,
    EpubChapterSource source,
    String revision, {
    bool Function()? isCancelled,
  }) {
    final running = _characterIndexTasks[bookId];
    if (running != null) return running;
    late final Future<ProgressWeights?> task;
    task = _ensureCharacterIndex(bookId, source, revision, isCancelled)
        .whenComplete(() {
          if (identical(_characterIndexTasks[bookId], task)) {
            _characterIndexTasks.remove(bookId);
          }
        });
    _characterIndexTasks[bookId] = task;
    return task;
  }

  Future<ProgressWeights?> _ensureCharacterIndex(
    String bookId,
    EpubChapterSource source,
    String revision,
    bool Function()? isCancelled,
  ) async {
    final book = await resolveBookRow(_db, bookId);
    if (book == null || book.deletedAt != null) return null;
    if (book.contentRevision != null && book.contentRevision != revision) {
      return null;
    }
    final key = '$_characterIndexPrefix${book.uuid}';
    final setting = _decodeCharacterIndex(await _readSetting(key));
    final excluded = <int>{...source.document.progressExcludedSpineIndexes};
    for (var spine = 0; spine < source.chapterCount; spine++) {
      if (source.isChapterMissing(spine)) excluded.add(spine);
    }
    if (setting != null &&
        setting.version == _characterIndexVersion &&
        setting.revision == revision &&
        _sameIntSet(setting.excluded, excluded)) {
      return characterWeights(bookId);
    }
    final counts = List<int>.filled(source.chapterCount, 0);
    for (var spine = 0; spine < source.chapterCount; spine++) {
      if (isCancelled?.call() == true) return null;
      if (excluded.contains(spine) || source.isChapterMissing(spine)) {
        excluded.add(spine);
        continue;
      }
      counts[spine] = source.semanticCharacterCount(spine);
      if (spine % 8 == 7) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (isCancelled?.call() == true) return null;
    final current = await resolveBookRow(_db, book.uuid);
    if (current == null ||
        current.deletedAt != null ||
        current.contentRevision != book.contentRevision ||
        current.sourcePath != book.sourcePath) {
      return null;
    }
    final weights = ProgressWeights.fromCharCounts(counts, excluded: excluded);
    await _db.transaction(() async {
      final rows = await (_db.select(
        _db.spineItems,
      )..where((table) => table.bookId.equals(book.id))).get();
      final bySpine = <int, SpineItemRow>{
        for (final row in rows) row.spineIndex: row,
      };
      for (var spine = 0; spine < source.chapterCount; spine++) {
        final item = source.document.spine[spine];
        final existing = bySpine[spine];
        if (existing == null) {
          await _db
              .into(_db.spineItems)
              .insert(
                SpineItemsCompanion.insert(
                  bookId: book.id,
                  spineIndex: spine,
                  href: item.href,
                  linear: Value<int>(item.linear ? 1 : 0),
                  charCount: Value<int>(counts[spine]),
                  charStart: Value<int>(weights.charStarts[spine]),
                ),
              );
        } else {
          await (_db.update(
            _db.spineItems,
          )..where((table) => table.id.equals(existing.id))).write(
            SpineItemsCompanion(
              href: Value<String>(item.href),
              linear: Value<int>(item.linear ? 1 : 0),
              charCount: Value<int>(counts[spine]),
              charStart: Value<int>(weights.charStarts[spine]),
            ),
          );
        }
      }
      await (_db.delete(_db.spineItems)..where(
            (table) =>
                table.bookId.equals(book.id) &
                table.spineIndex.isBiggerOrEqualValue(source.chapterCount),
          ))
          .go();
      await (_db.update(
        _db.books,
      )..where((table) => table.id.equals(book.id))).write(
        BooksCompanion(charCount: Value<int>(weights.totalCharacters)),
      );
      await _db
          .into(_db.settingsTable)
          .insertOnConflictUpdate(
            SettingsTableCompanion.insert(
              key: key,
              value: jsonEncode(<String, Object?>{
                'version': _characterIndexVersion,
                'revision': revision,
                'excluded': excluded.toList()..sort(),
              }),
            ),
          );
    });
    return weights;
  }

  /// 读取某本书已落库的字符权重；没有 spine 统计时返回 null。
  Future<ProgressWeights?> characterWeights(String bookId) async {
    final book = await resolveBookRow(_db, bookId);
    if (book == null) return null;
    final rows =
        await (_db.select(_db.spineItems)
              ..where((table) => table.bookId.equals(book.id))
              ..orderBy([
                (table) => OrderingTerm(expression: table.spineIndex),
              ]))
            .get();
    if (rows.isEmpty) return null;
    final setting = _decodeCharacterIndex(
      await _readSetting('$_characterIndexPrefix${book.uuid}'),
    );
    return ProgressWeights.fromCharCounts(
      <int>[for (final row in rows) row.charCount ?? 0],
      excluded: <int>{
        for (final row in rows)
          if (row.linear == 0) row.spineIndex,
        ...?setting?.excluded,
      },
    );
  }

  Future<String?> _readSetting(String key) async {
    final row = await (_db.select(
      _db.settingsTable,
    )..where((table) => table.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  ({int version, String revision, Set<int> excluded})? _decodeCharacterIndex(
    String? source,
  ) {
    if (source == null) return null;
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      return (
        version: json['version'] as int,
        revision: json['revision'] as String,
        excluded: <int>{
          for (final value in json['excluded'] as List<dynamic>)
            if (value is int) value,
        },
      );
    } catch (_) {
      return null;
    }
  }

  bool _sameIntSet(Set<int> left, Set<int> right) =>
      left.length == right.length && left.containsAll(right);

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
    final saved = await _rowFor(book.id);
    final row = saved == null ? null : await _upgradeAnchor(book, saved);
    return row == null ? null : _toProgress(row);
  }

  Future<ProgressRow> _upgradeAnchor(BookRow book, ProgressRow row) async {
    final record = AnchorRecord.decode(row.anchorJson);
    if (record == null ||
        record.semanticVersion == currentAnchorSemanticVersion) {
      return row;
    }
    final verified = await verifyAnchorSemantics(
      _db,
      book,
      record,
      progress: true,
    );
    final percent = await _percentOf(book, verified);
    final anchorJson = mergeAnchorMetadata(verified.encode(), row.anchorJson);
    await _db.transaction(() async {
      final currentBook = await resolveBookRow(_db, book.uuid);
      final current = await _rowFor(book.id);
      if (currentBook == null ||
          !_sameContent(book, currentBook) ||
          current?.anchorJson != row.anchorJson ||
          current?.updatedAt != row.updatedAt) {
        return;
      }
      await (_db.update(
        _db.readingProgress,
      )..where((table) => table.bookId.equals(book.id))).write(
        ReadingProgressCompanion(
          anchorJson: Value(anchorJson),
          locatorCfi: Value(verified.effective.start.cfi),
          spineIndex: Value(verified.effective.start.spineIndex),
          pageIndex: const Value(0),
          percent: Value(percent),
        ),
      );
    });
    return await _rowFor(book.id) ?? row;
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
    final readingPercent = progress.readingPercent;
    final percent = readingPercent == null
        ? await _percentOf(book, record)
        : (readingPercent * 100).clamp(0.0, 100.0);
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
            : _encodeAnchor(record, saved, progress, percent),
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
    final index = await loadBookAnchorIndex(_db, book, startCfi: point.cfi);
    final chapter = index?.chapter(point.spineIndex);
    final offset = chapter?.offsetFor(point.cfi);
    final length = chapter == null
        ? 0
        : TextLengthScanner.countPlainText(chapter.text);
    final ratio = chapter != null && offset != null && length > 0
        ? TextLengthScanner.countPlainText(chapter.text.substring(0, offset)) /
              length
        : point.chapterLength == 0
        ? 0.0
        : point.charOffset / point.chapterLength;
    final weights = await characterWeights(book.uuid);
    if (weights == null || point.spineIndex >= weights.chapterCount) {
      // 兼容尚无导入字数统计的旧书，按章等权；单章仍保留精确比例。
      final count = book.spineCount > 0 ? book.spineCount : 1;
      return ((point.spineIndex + ratio) / count * 100).clamp(0, 100);
    }
    return weights.percentOf(
          point.spineIndex,
          charOffsetInChapter: weights.charCounts[point.spineIndex] * ratio,
        ) *
        100;
  }

  String? _encodeAnchor(
    AnchorRecord? record,
    ProgressRow? saved,
    ReaderProgress progress,
    double percent,
  ) {
    if (record == null && progress.readingPercent == null) return null;
    final metadata = <String, Object?>{
      // 百分比标记同时区分「真实 0%」与没有比例字段的旧记录。
      if (progress.readingPercent != null)
        'readingPercent': progress.readingPercent!.clamp(0.0, 1.0),
      if (progress.scrollOffset != null) 'scrollOffset': progress.scrollOffset,
      if (progress.layoutFingerprint != null)
        'layoutFingerprint': progress.layoutFingerprint,
    };
    if (record == null) return jsonEncode(metadata);
    final original = AnchorRecord.decode(saved?.anchorJson)?.original;
    return jsonEncode({
      ...AnchorRecord(
        original: original ?? record.original,
        current: original == null ? record.current : record.effective,
        status: record.status,
        reason: record.reason,
        semanticVersion: record.semanticVersion,
      ).toJson(),
      ...metadata,
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
    final result = <String, ReaderProgress>{};
    for (final row in rows) {
      final book = booksById[row.bookId];
      if (book == null) continue;
      result[book.uuid] = _toProgress(await _upgradeAnchor(book, row));
    }
    return result;
  }

  ReaderProgress _toProgress(ProgressRow row) {
    final record = AnchorRecord.decode(row.anchorJson);
    final usable = record != null && record.status != 'pending';
    final anchor = usable ? record.effective : null;
    final anchorPercent = _anchorReadingPercent(row.anchorJson);
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
      // 没有内容锚点的旧页号，以及无法用原文确认的锚点，都只能近似恢复；
      // 不能让调用方把这类位置当成精确 CFI。
      approximate:
          record == null ||
          record.status == 'pending' ||
          record.status == 'approximate' ||
          anchor?.approximate == true,
      // 旧版已有内容锚点时，percent 列仍代表同一次保存的正文比例；
      // 新格式优先使用锚点内的 0～1 字段。只有完全没有锚点的旧页号
      // 记录才交给书架按既有字符权重兜底，避免把未知比例伪造成 0%。
      readingPercent:
          anchorPercent ??
          (record != null ? (row.percent / 100).clamp(0.0, 1.0) : null),
      layoutFingerprint: _anchorLayoutFingerprint(row.anchorJson),
    );
  }

  double? _anchorReadingPercent(String? source) {
    if (source == null) return null;
    try {
      final value =
          (jsonDecode(source) as Map<String, dynamic>)['readingPercent'];
      if (value is! num || !value.isFinite) return null;
      return value.toDouble().clamp(0.0, 1.0);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
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

  /// 把旧版 `reader_progress.json` 逐书迁入表。
  ///
  /// 已有数据库进度的书保持原值；迁移中断后重跑只补齐剩余书籍。
  /// 返回本次新插入的条数；读不到文件返回 0。
  Future<int> migrateLegacyJson(File file) async {
    if (!await file.exists()) {
      return 0;
    }
    final existing = await (_db.selectOnly(
      _db.readingProgress,
    )..addColumns([_db.readingProgress.bookId])).get();
    final existingBookIds = <int>{
      for (final row in existing) row.read(_db.readingProgress.bookId)!,
    };
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
      if (existingBookIds.contains(bookIdValue)) continue;
      await _db
          .into(_db.readingProgress)
          .insert(
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
            mode: InsertMode.insertOrIgnore,
          );
      existingBookIds.add(bookIdValue);
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
