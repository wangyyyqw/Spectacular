import 'dart:io';

import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';

import '../storage/db.dart';
import 'revision_anchor_index.dart';

/// 当前身份优先；历史别名必须唯一，不能把歧义旧数据挂到其他书。
Future<BookRow?> resolveBookRow(
  AppDatabase db,
  String id, {
  bool allowAliases = true,
}) async {
  final exact = await (db.select(
    db.books,
  )..where((table) => table.uuid.equals(id))).getSingleOrNull();
  if (exact != null || !allowAliases) return exact;
  final aliases = await (db.select(
    db.bookIdAliases,
  )..where((table) => table.aliasId.equals(id))).get();
  final legacy = await (db.select(
    db.books,
  )..where((table) => table.legacyUuid.equals(id))).get();
  final ids = {
    for (final alias in aliases) alias.bookId,
    for (final book in legacy) book.id,
  };
  if (ids.length != 1) return null;
  return (db.select(
    db.books,
  )..where((table) => table.id.equals(ids.single))).getSingleOrNull();
}

final _bookIndexes = Expando<Map<String, Future<AnchorBook?>>>();

/// 索引最多缓存两本当前原书，持续保存进度不重复解析全书。
Future<AnchorBook?> loadBookAnchorIndex(AppDatabase db, BookRow row) {
  final path = row.sourcePath;
  if (path == null) return Future.value(null);
  final cache = _bookIndexes[db] ??= {};
  final key = '$path:${row.contentRevision}:${row.layoutVersion}';
  final existing = cache.remove(key);
  if (existing != null) {
    cache[key] = existing;
    return existing;
  }
  while (cache.length >= 2) {
    cache.remove(cache.keys.first);
  }
  final loading = _readIndex(row);
  cache[key] = loading;
  return loading.then((book) {
    // 文件恢复后允许重新建立索引，不能永久缓存缺失结果。
    if (book == null && identical(cache[key], loading)) cache.remove(key);
    return book;
  });
}

Future<AnchorBook?> _readIndex(BookRow row) async {
  try {
    final file = File(row.sourcePath!);
    if (!await file.exists()) return null;
    return await buildRevisionAnchorBook(await file.readAsBytes());
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on StateError {
    // 旧 EPUB 损坏时保留原记录，不把新内容伪装成旧锚点。
    return null;
  }
}

/// 首次原始锚点永留，手动修正只替换当前锚点。
Future<AnchorRecord?> captureBookAnchor(
  AppDatabase db,
  BookRow row,
  String startCfi, {
  String? endCfi,
  bool approximate = false,
  AnchorRecord? existing,
}) async {
  final book = await loadBookAnchorIndex(db, row);
  final anchor = book?.capture(
    startCfi,
    endCfi: endCfi,
    approximate: approximate,
  );
  if (anchor == null) return null;
  return AnchorRecord(
    original: existing?.original ?? anchor,
    current: existing == null ? null : anchor,
    status: approximate ? 'approximate' : 'verified',
  );
}

/// 缺少旧文件时只保存历史证据，不用新选区替换最初引用。
Future<AnchorRecord> originalAnnotationAnchor(
  AppDatabase db,
  BookRow book,
  AnnotationRow row,
) async {
  final existing = AnchorRecord.decode(row.anchorJson);
  if (existing != null) return existing;
  final index = await loadBookAnchorIndex(db, book);
  final range = row.type == 2
      ? null
      : index?.legacyRange(
          startCfi: row.startCfi,
          endCfi: row.endCfi,
          quote: row.quote,
          contextBefore: row.contextBefore ?? '',
          contextAfter: row.contextAfter ?? '',
        );

  return AnchorRecord(
    original:
        range ??
        LocationAnchor(
          revision: 'legacy',
          start: _legacyPoint(row.startCfi),
          end: row.type == 2 ? null : _legacyPoint(row.endCfi),
          quote: row.type == 2 ? '' : row.quote,
        ),
    status: 'pending',
    reason: '旧版本缺少内容锚点',
  );
}

AnchorPoint _legacyPoint(String cfi) {
  final parsed = EpubCfi.parse(cfi);
  return AnchorPoint(
    cfi: cfi,
    spineIndex: parsed == null ? 0 : spineIndexOfCfi(parsed) ?? 0,
    href: '',
    title: '',
    chapterFingerprint: '',
    paragraphFingerprint: '',
    charOffset: 0,
    chapterLength: 0,
    quote: '',
    contextBefore: '',
    contextAfter: '',
  );
}

/// 构造时立即读取内容版本，尚无标注的旧会话也不能回写新版。
class RevisionBookBinding {
  RevisionBookBinding(this.db, this.id) : _initial = resolveBookRow(db, id);

  final AppDatabase db;
  final String id;
  final Future<BookRow?> _initial;
  String? _signature;

  String _key(BookRow row) =>
      '${row.uuid}:${row.sourcePath}:${row.contentRevision}:${row.layoutVersion}';

  Future<BookRow?> read() async {
    await _bindInitial();
    final row = await resolveBookRow(db, id);
    if (row != null) _signature ??= _key(row);
    return row;
  }

  Future<BookRow?> writable() async {
    await _bindInitial();
    final row = await resolveBookRow(db, id, allowAliases: false);
    if (row == null || row.deletedAt != null) return null;
    _signature ??= _key(row);
    return _signature == _key(row) ? row : null;
  }

  Future<void> _bindInitial() async {
    final row = await _initial;
    if (row != null) _signature ??= _key(row);
  }
}
