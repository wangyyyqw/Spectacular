import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/epub_document.dart';

import '../library/library_store.dart';
import 'book_source_models.dart';
import 'online_chapter_request.dart';

/// 阅微在线 EPUB 保留的书源与章节身份，不改写原书和同步标记。
class OnlineEpubMetadata {
  OnlineEpubMetadata({
    required this.sourceId,
    required this.detailUrl,
    required this.bookName,
    required List<OnlineEpubIndexedChapter> chapters,
    this.onDemand = false,
    this.syncMarker = false,
    this.progressOnly = false,
  }) : chapters = List.unmodifiable(chapters);

  static const indexPath = 'OEBPS/reamicro-online-chapters.json';
  static const markerPath = 'OEBPS/reamicro-sync-online-marker.json';
  static const _maxMetadataBytes = 16 * 1024 * 1024;

  final String sourceId;
  final String detailUrl;
  final String bookName;
  final List<OnlineEpubIndexedChapter> chapters;
  final bool onDemand;
  final bool syncMarker;
  final bool progressOnly;

  /// 完整离线书仍按原 EPUB 阅读；占位页和按需书从已导入书源获取正文。
  bool get requiresOnlineReading =>
      onDemand || progressOnly || chapters.any((chapter) => !chapter.ready);

  /// 只读中央目录及两份小型元数据，普通 EPUB 不读取正文。
  static Future<OnlineEpubMetadata?> read(
    LibraryStore library,
    BookEntry entry,
  ) async {
    final archive = entry.filePath.isEmpty
        ? EpubArchive.fromBytes(await library.readBytes(entry), verify: false)
        : await EpubArchive.fromFile(File(entry.filePath));
    try {
      final index = await _readJson(archive, indexPath);
      if (index == null) return null;
      final marker = await _readJson(archive, markerPath);
      return fromJson(index, marker: marker);
    } finally {
      archive.close();
    }
  }

  /// v1 完整索引没有状态，沿用阅微将其视为已下载章节的兼容规则。
  static OnlineEpubMetadata? fromJson(
    Map<String, Object?> index, {
    Map<String, Object?>? marker,
  }) {
    final version = _integer(index['version']) ?? 1;
    if (version != 1 && version != 2) return null;
    final sourceId = _text(index['sourceId']);
    final detailUrl = _text(index['detailUrl']);
    if (sourceId.isEmpty || detailUrl.isEmpty) return null;
    final legacyFull = version == 1 && !index.containsKey('mode');
    final chapters = <OnlineEpubIndexedChapter>[];
    final rows = index['chapters'];
    if (rows is List) {
      for (final row in rows) {
        final value = _jsonObject(row);
        if (value == null) continue;
        final href = _chapterPath(_text(value['href']));
        final url = _text(value['url']);
        if (href == null || url.isEmpty) continue;
        chapters.add(
          OnlineEpubIndexedChapter(
            sourceChapterId: _text(value['sourceChapterId']),
            url: url,
            title: _text(value['title']),
            volume: _text(value['volumeTitle']),
            href: href,
            ready:
                _text(value['state']).toUpperCase() == 'READY' ||
                (legacyFull && !value.containsKey('state')),
          ),
        );
      }
    }
    final matchingMarker =
        marker != null &&
        _integer(marker['version']) == 1 &&
        _text(marker['sourceId']) == sourceId &&
        _text(marker['detailUrl']) == detailUrl;
    if (chapters.isEmpty && !matchingMarker) return null;
    return OnlineEpubMetadata(
      sourceId: sourceId,
      detailUrl: detailUrl,
      bookName: _text(index['bookName']),
      chapters: chapters,
      onDemand: _text(index['mode']).toUpperCase() == 'ON_DEMAND',
      syncMarker: matchingMarker,
      progressOnly: matchingMarker && marker['progressOnly'] == true,
    );
  }

  /// 显式身份优先；别名和 URL 摘要必须唯一，不用书名或站点域名猜源。
  BookSource? sourceIn(Iterable<BookSource> sources) =>
      findSource(sourceId, sources);

  static BookSource? findSource(String sourceId, Iterable<BookSource> sources) {
    if (sourceId.trim().isEmpty) return null;
    final exact = sources.where((source) => source.id == sourceId).toList();
    if (exact.isNotEmpty) return exact.length == 1 ? exact.single : null;
    final matches = sources.where((source) {
      final identities = <String>{
        source.id,
        if (source.sourceUrl.trim().isNotEmpty)
          stableBookSourceId(source.sourceUrl),
        if (source.sourceUrl.trim().isNotEmpty)
          legacyBookSourceId(source.sourceUrl),
        for (final key in const [
          'reamicroSourceId',
          'reamicroPackageId',
          'bookSourceId',
        ])
          if (_text(source.raw[key]).isNotEmpty) _text(source.raw[key]),
      };
      final aliases = source.raw['reamicroSourceAliases'];
      if (aliases is List) {
        identities.addAll(
          aliases.map(_text).where((value) => value.isNotEmpty),
        );
      }
      return identities.contains(sourceId) ||
          _sameSourceUrl(sourceId, source.sourceUrl);
    }).toList();
    return matches.length == 1 ? matches.single : null;
  }

  OnlineBookLink linkFor(BookSource source, BookEntry entry) {
    final request = splitBookSourceUrlOptions(detailUrl);
    return OnlineBookLink(
      sourceId: source.id,
      bookUrl: request.url,
      name: entry.title,
      author: entry.author,
      bookOptions: request.options,
    );
  }

  /// 原 EPUB 的封面、分卷页不计作正文；按 href 找到真实章节 URL。
  Future<String?> chapterIdentityForSpine(
    LibraryStore library,
    BookEntry entry,
    int spineIndex,
  ) async {
    if (spineIndex < 0 || chapters.isEmpty) return null;
    final opened = entry.filePath.isEmpty
        ? await openEpub(await library.readBytes(entry), verifyCrc: false)
        : await openEpubFile(File(entry.filePath));
    final document = opened.document;
    if (document == null) return null;
    try {
      if (spineIndex >= document.spine.length) return null;
      final path = document.resources.resolve(
        document.spine[spineIndex].href,
        baseDir: p.posix.dirname(document.opfPath),
      );
      final matches = chapters.where((chapter) => chapter.href == path);
      if (matches.length != 1) return null;
      return onlineChapterIdentity(matches.single.toChapter(0, detailUrl));
    } finally {
      document.archive.close();
    }
  }

  static Future<Map<String, Object?>?> _readJson(
    EpubArchive archive,
    String path,
  ) async {
    final length = archive.uncompressedSizeOf(path);
    if (length == null || length <= 0 || length > _maxMetadataBytes) {
      return null;
    }
    final bytes = await archive.readBytesAsync(path);
    if (bytes == null) return null;
    try {
      return _jsonObject(jsonDecode(utf8.decode(bytes)));
    } on FormatException {
      return null;
    }
  }
}

/// 同步文件中的章节路径与源请求地址，状态只决定是否存在离线正文。
class OnlineEpubIndexedChapter {
  const OnlineEpubIndexedChapter({
    required this.sourceChapterId,
    required this.url,
    required this.title,
    required this.volume,
    required this.href,
    required this.ready,
  });

  final String sourceChapterId;
  final String url;
  final String title;
  final String volume;
  final String href;
  final bool ready;

  OnlineChapter toChapter(int index, String detailUrl) {
    // data 正文逗号后的 JSON 是内容，不是 Legado 请求选项。
    if (url.trimLeft().toLowerCase().startsWith('data:')) {
      return OnlineChapter(
        index: index,
        title: title,
        url: url,
        volume: volume,
      );
    }
    final request = splitBookSourceUrlOptions(url);
    final base = splitBookSourceUrlOptions(detailUrl).url;
    return OnlineChapter(
      index: index,
      title: title,
      url: Uri.tryParse(base)?.resolve(request.url).toString() ?? request.url,
      volume: volume,
      requestOptions: request.options,
    );
  }
}

Map<String, Object?>? _jsonObject(Object? value) {
  if (value is! Map) return null;
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

String _text(Object? value) => value is String ? value.trim() : '';

int? _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse(_text(value));

String? _chapterPath(String href) {
  final uri = Uri.tryParse(href);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  final raw = uri.path.replaceAll('\\', '/');
  if (raw.isEmpty || raw.startsWith('/')) return null;
  final path = p.posix.normalize(raw.startsWith('OEBPS/') ? raw : 'OEBPS/$raw');
  return p.posix.isWithin('OEBPS', path) ? path : null;
}

bool _sameSourceUrl(String left, String right) {
  String? normalize(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    final normalized = uri.normalizePath();
    return canonicalBookSourceUrl(normalized.toString());
  }

  final url = normalize(left);
  return url != null && url == normalize(right);
}
