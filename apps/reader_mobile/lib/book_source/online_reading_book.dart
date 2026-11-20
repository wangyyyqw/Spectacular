import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:reader_core/api.dart' show BookMeta;
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/library_store.dart';
import 'book_source_models.dart';
import 'book_source_service.dart';
import 'online_epub_builder.dart';

/// 一次在线阅读使用同一目录快照；身份与下载后的 EPUB 分开。
class OnlineReadingBook {
  OnlineReadingBook({
    required this.source,
    required this.book,
    required List<OnlineChapter> chapters,
    required this.service,
  }) : chapters = List.unmodifiable(chapters);

  final BookSource source;
  final OnlineBook book;
  final List<OnlineChapter> chapters;
  final BookSourceService service;

  late final String id = 'online:${_digest([source.id, book.bookUrl])}';
  late final String revision = _digest([
    '在线正文1',
    id,
    for (final (index, chapter) in chapters.indexed)
      [chapter.url, chapterRevision(index)],
  ]);

  EpubChapterSource open() => EpubChapterSource.fromChapterLoader(
    meta: BookMeta(
      title: book.name,
      author: book.author,
      language: 'zh-CN',
      identifier: id,
    ),
    chapterTitles: [for (final chapter in chapters) chapter.title],
    resources: {'style.css': utf8.encode(OnlineEpubBuilder.chapterStylesheet)},
    loadChapterXhtml: (index) async {
      final chapter = chapters[index];
      final html = await service.fetchChapterContent(
        source,
        chapter,
        book.bookUrl,
      );
      return const OnlineEpubBuilder().buildChapterDocument(
        OnlineEpubChapter(title: chapter.title, html: html),
      );
    },
    loadNetworkImage: (url) =>
        service.loadCover(source, url, referer: book.bookUrl),
  );

  String chapterRevision(int index) =>
      service.chapterContentRevision(source, chapters[index]);

  static String _digest(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
}

/// 目录有新增、重排或规则变化时，按地址恢复到原章，丢弃旧版章内坐标。
class OnlineReadingProgress implements ReaderProgressStore {
  OnlineReadingProgress(this.library, this.book, {this.startChapter});

  final LibraryStore library;
  final OnlineReadingBook book;
  final int? startChapter;

  String get _key => 'online_reading_progress:${book.id}';

  @override
  Future<ReaderProgress?> load(String bookId) async {
    if (bookId != book.id) return null;
    final saved = await _load();
    final start = startChapter;
    if (start == null || saved?.spineIndex == start) return saved;
    return ReaderProgress(
      spineIndex: start,
      pageIndex: 0,
      finished: saved?.finished ?? false,
      contentRevision: book.revision,
    );
  }

  Future<ReaderProgress?> _load() async {
    final value = await library.getSetting(_key);
    if (value == null || value.isEmpty) return null;
    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic>) return null;
      final index = book.chapters.indexWhere(
        (chapter) => chapter.url == json['url'],
      );
      if (index < 0) return null;
      final sameRevision = json['revision'] == book.revision;
      final sameChapter =
          json['chapterRevision'] == book.chapterRevision(index);
      // CFI 含 spine 序号；目录只在末尾追加时仍可保留原章内锚点。
      final samePosition = sameChapter && index == json['spine'];
      return ReaderProgress(
        spineIndex: index,
        pageIndex: samePosition ? json['page'] as int? ?? 0 : 0,
        finished: sameRevision && json['finished'] == true,
        cfi: samePosition ? json['cfi'] as String? : null,
        scrollOffset: samePosition
            ? (json['scroll'] as num?)?.toDouble()
            : null,
        layoutFingerprint: samePosition ? json['layout'] as String? : null,
        approximate: !samePosition || json['approximate'] == true,
        contentRevision: book.revision,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    final spine = progress.spineIndex;
    if (bookId != book.id ||
        progress.contentRevision != book.revision ||
        spine < 0 ||
        spine >= book.chapters.length) {
      throw const ReaderProgressSaveException(ReaderProgressSaveResult.stale);
    }
    await library.setSetting(
      _key,
      jsonEncode({
        'url': book.chapters[spine].url,
        'revision': book.revision,
        'chapterRevision': book.chapterRevision(spine),
        'spine': spine,
        'page': progress.pageIndex,
        'cfi': progress.cfi,
        'scroll': progress.scrollOffset,
        'layout': progress.layoutFingerprint,
        'approximate': progress.approximate,
        'finished': progress.finished,
      }),
    );
  }

  @override
  Future<void> clear(String bookId) async {
    if (bookId == book.id) await library.setSetting(_key, '');
  }

  @override
  Future<Map<String, ReaderProgress>> snapshot() async => {
    book.id: ?await _load(),
  };
}
