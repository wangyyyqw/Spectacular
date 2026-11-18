import 'dart:io';

import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/position/book_progress_index.dart';

import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/chapter/book_progress.dart';

import '../storage/db.dart';

/// 当前身份优先；修订前身份必须唯一，避免关联到另一条书籍记录。
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
  final ids = {for (final alias in aliases) alias.bookId};
  if (ids.length != 1) return null;
  return (db.select(
    db.books,
  )..where((table) => table.id.equals(ids.single))).getSingleOrNull();
}

final _bookIndexes = Expando<Map<String, Future<AnchorBook?>>>();
final _readingSources = Expando<Map<String, _ReadingAnchorSource>>();
final _progressIndexes = Expando<Map<String, Future<BookProgressIndex?>>>();

/// 进度只用条目元数据；借用活跃来源或按文件版本缓存轻量权重。
Future<BookProgressIndex?> loadBookProgressIndex(AppDatabase db, BookRow row) {
  final binding = _readingSources[db]?[row.uuid];
  if (binding != null && binding.matches(row)) {
    return Future.value(binding.source.progressIndex);
  }
  final key =
      '${row.uuid}:${row.sourcePath}:${row.contentRevision}:'
      '${row.layoutVersion}:${row.spineCount}';
  final cache = _progressIndexes[db] ??= {};
  final cached = cache.remove(key);
  if (cached != null) {
    cache[key] = cached;
    return cached;
  }
  while (cache.length >= 2) {
    cache.remove(cache.keys.first);
  }
  late final Future<BookProgressIndex?> task;
  task = _readProgressIndex(row).then((result) {
    // 文件缺失或损坏是暂时状态，恢复来源后应重新读取真实条目元数据。
    if (!result.cacheable && identical(cache[key], task)) cache.remove(key);
    return result.index;
  });
  cache[key] = task;
  return task;
}

Future<({BookProgressIndex index, bool cacheable})> _readProgressIndex(
  BookRow row,
) async {
  final path = row.sourcePath;
  if (path != null) {
    try {
      final result = await openEpubFile(File(path), verifyCrc: false);
      final document = result.document;
      if (document != null) {
        try {
          return (index: bookProgressIndexFor(document), cacheable: true);
        } finally {
          document.archive.close();
        }
      }
    } on FileSystemException {
      // 原书文件暂不可用时保留 CFI，只降级元数据权重。
    } on FormatException {
      // 损坏的归档不应阻止已有阅读进度展示。
    } on StateError {
      // 缺少必要文档时同样按可读章等权降级。
    }
  }
  return (
    index: BookProgressIndex.fromUncompressedSizes(
      List<int?>.filled(row.spineCount, null),
    ),
    cacheable: false,
  );
}

/// 借用阅读会话已打开的原书，解除绑定不关闭仍由阅读页持有的来源。
Future<void Function()> bindReadingAnchorSource(
  AppDatabase db,
  String bookId,
  EpubChapterSource source,
  String revision,
) async {
  final row = await resolveBookRow(db, bookId, allowAliases: false);
  if (row == null || row.contentRevision != revision) {
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
    return binding.index(first, last);
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
      return await _ReadingAnchorSource(
        row,
        source,
        row.contentRevision,
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
      !source.isClosed &&
      row.uuid == current.uuid &&
      row.sourcePath == current.sourcePath &&
      row.contentRevision == current.contentRevision &&
      row.layoutVersion == current.layoutVersion;

  Future<AnchorBook?> index(int first, int last) async {
    if (last >= source.chapterCount) return null;
    final chapters = <AnchorChapter>[];
    for (var spine = first; spine <= last; spine++) {
      final chapter =
          _chapters.remove(spine) ??
          (source.isChapterMissing(spine)
              ? AnchorChapter(
                  spineIndex: spine,
                  href: source.document.spine[spine].href,
                  blocks: const [],
                  readable: false,
                )
              : await source.loadAnchorChapter(spine));
      _chapters[spine] = chapter;
      while (_chapters.length > EpubChapterSource.documentCacheChapterLimit) {
        _chapters.remove(_chapters.keys.first);
      }
      chapters.add(chapter);
    }
    return AnchorBook(revision: revision, chapters: chapters);
  }

  Future<LocationAnchor?> elementAnchor(String cfi) async {
    final spine = _spineOf(cfi);
    if (spine == null || source.isChapterMissing(spine)) return null;
    final chapter = await source.loadAnchorChapter(spine);
    if (!source.isValidElementCfi(cfi)) return null;
    if (chapter.text.isNotEmpty || source.readingPercentForCfi(cfi) == null) {
      return null;
    }
    // 空文本章没有字符坐标，只保留经真实文档元素核验的原始 CFI。
    return LocationAnchor(
      revision: revision,
      start: AnchorPoint(
        cfi: cfi,
        spineIndex: spine,
        href: chapter.href,
        title: chapter.title,
        chapterFingerprint: chapter.fingerprint,
        paragraphFingerprint: '',
        charOffset: 0,
        chapterLength: 0,
        quote: '',
        contextBefore: '',
        contextAfter: '',
      ),
      quote: '',
    );
  }
}

Future<T?> _withElementSource<T>(
  AppDatabase db,
  BookRow row,
  Future<T?> Function(_ReadingAnchorSource source) read,
) async {
  final binding = _readingSources[db]?[row.uuid];
  if (binding != null && binding.matches(row)) return read(binding);
  final path = row.sourcePath;
  if (path == null) return null;
  try {
    final file = File(path);
    final source = await EpubChapterSource.openFile(file, verifyCrc: false);
    try {
      return await read(_ReadingAnchorSource(row, source, row.contentRevision));
    } finally {
      source.close();
    }
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on StateError {
    return null;
  }
}

/// 无字符的图片章按经核验的元素顺序计算比例，不制造正文偏移。
Future<double?> loadElementReadingPercent(
  AppDatabase db,
  BookRow row,
  String cfi,
) => _withElementSource(db, row, (binding) async {
  if (await binding.elementAnchor(cfi) == null) return null;
  return binding.source.readingPercentForCfi(cfi);
});

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
  final anchor =
      book?.capture(startCfi, endCfi: endCfi, approximate: approximate) ??
      (endCfi == null
          ? await _withElementSource(
              db,
              row,
              (binding) => binding.elementAnchor(startCfi),
            )
          : null);
  if (anchor == null) return null;
  return AnchorRecord(
    original: existing?.original ?? anchor,
    current: existing == null ? null : anchor,
    status: approximate ? 'approximate' : 'verified',
  );
}

/// 读取可识别的锚点证据；不把旧版待定位记录当作精确位置。
AnchorRecord requireAnchorRecord(String? source) {
  final record = AnchorRecord.decode(source);
  if (record == null) {
    throw const FormatException('内容锚点缺失或格式不受支持，请重新建立记录');
  }
  return record;
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
