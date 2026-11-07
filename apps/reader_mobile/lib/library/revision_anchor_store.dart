import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';

import '../reader/epub_chapter_source.dart';
import '../storage/db.dart';

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
final _readingSources = Expando<Map<String, _ReadingAnchorSource>>();

/// 借用阅读会话已打开的原书，解除绑定不关闭仍由阅读页持有的来源。
Future<void Function()> bindReadingAnchorSource(
  AppDatabase db,
  String bookId,
  EpubChapterSource source,
  String revision,
) async {
  final row = await resolveBookRow(db, bookId, allowAliases: false);
  if (row == null ||
      (row.contentRevision != null && row.contentRevision != revision)) {
    return () {};
  }
  final sources = _readingSources[db] ??= {};
  final binding = _ReadingAnchorSource(row, source, revision);
  sources[bookId] = binding;
  return () {
    if (identical(sources[bookId], binding)) sources.remove(bookId);
  };
}

/// 日常保存只索引起止 CFI 之间的章节；完整索引仅供覆盖更新迁移使用。
Future<AnchorBook?> loadBookAnchorIndex(
  AppDatabase db,
  BookRow row, {
  required String startCfi,
  String? endCfi,
}) {
  final first = _spineOf(startCfi);
  final last = endCfi == null ? first : _spineOf(endCfi);
  if (first == null || last == null || first < 0 || last < first) {
    return Future.value(null);
  }
  final binding = _readingSources[db]?[row.uuid];
  if (binding != null && binding.matches(row)) {
    return Future.value(binding.index(first, last));
  }
  final path = row.sourcePath;
  if (path == null) return Future.value(null);
  final cache = _bookIndexes[db] ??= {};
  final key = '$path:${row.contentRevision}:${row.layoutVersion}:$first:$last';
  final existing = cache.remove(key);
  if (existing != null) {
    cache[key] = existing;
    return existing;
  }
  while (cache.length >= 2) {
    cache.remove(cache.keys.first);
  }
  final loading = _readIndex(row, first, last);
  cache[key] = loading;
  return loading.then((book) {
    // 文件恢复后允许重新建立索引，不能永久缓存缺失结果。
    if (book == null && identical(cache[key], loading)) cache.remove(key);
    return book;
  });
}

int? _spineOf(String cfi) {
  final parsed = EpubCfi.parse(cfi);
  return parsed == null ? null : spineIndexOfCfi(parsed);
}

Future<AnchorBook?> _readIndex(BookRow row, int first, int last) async {
  try {
    final file = File(row.sourcePath!);
    if (!await file.exists()) return null;
    final source = await EpubChapterSource.openFile(file, verifyCrc: false);
    try {
      return _ReadingAnchorSource(
        row,
        source,
        row.contentRevision ??
            (await sha256.bind(file.openRead()).first).toString(),
      ).index(first, last);
    } finally {
      source.close();
    }
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on StateError {
    // 旧 EPUB 损坏时保留原记录，不把新内容伪装成旧锚点。
    return null;
  }
}

class _ReadingAnchorSource {
  _ReadingAnchorSource(this.row, this.source, this.revision);

  final BookRow row;
  final EpubChapterSource source;
  final String revision;
  final _chapters = <int, AnchorChapter>{};

  bool matches(BookRow current) =>
      row.uuid == current.uuid &&
      row.sourcePath == current.sourcePath &&
      row.contentRevision == current.contentRevision &&
      row.layoutVersion == current.layoutVersion;

  AnchorBook? index(int first, int last) {
    if (last >= source.chapterCount) return null;
    final chapters = <AnchorChapter>[];
    for (var spine = first; spine <= last; spine++) {
      final chapter = _chapters.remove(spine) ?? source.anchorChapter(spine);
      _chapters[spine] = chapter;
      while (_chapters.length > EpubChapterSource.documentCacheChapterLimit) {
        _chapters.remove(_chapters.keys.first);
      }
      chapters.add(chapter);
    }
    return AnchorBook(revision: revision, chapters: chapters);
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
  final book = await loadBookAnchorIndex(
    db,
    row,
    startCfi: startCfi,
    endCfi: endCfi,
  );
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
  final index = await loadBookAnchorIndex(
    db,
    book,
    startCfi: row.startCfi,
    endCfi: row.endCfi,
  );
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
