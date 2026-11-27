import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:reader_core/api.dart' show BookMeta;
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/library_store.dart';
import 'book_source_models.dart';
import 'book_source_service.dart';
import 'online_chapter_request.dart';
import 'online_epub_builder.dart';
import 'online_review.dart';

/// 一次在线阅读使用同一目录快照；身份与下载后的 EPUB 分开。
class OnlineReadingBook {
  OnlineReadingBook({
    required this.source,
    required this.book,
    required List<OnlineChapter> chapters,
    required this.service,
    this.bookshelfId,
    this.initialChapterIdentity,
  }) : chapters = List.unmodifiable(chapters);

  final BookSource source;
  final OnlineBook book;
  final List<OnlineChapter> chapters;
  final BookSourceService service;
  final String? bookshelfId;

  /// 只用于首次从原 EPUB 进入在线阅读，原章内坐标不套到生成的正文。
  final String? initialChapterIdentity;

  late final String id =
      bookshelfId ?? 'online:${_digest([source.id, book.bookUrl])}';
  late final String revision = _digest([
    '在线正文5',
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
    chapterVolumes: [for (final chapter in chapters) chapter.volume],
    resources: {
      OnlineEpubBuilder.stylesheetPath: utf8.encode(
        OnlineEpubBuilder.chapterStylesheet,
      ),
    },
    loadChapterXhtml: (index) async {
      final chapter = chapters[index];
      final html = await service.fetchChapterContent(
        source,
        chapter,
        book.bookUrl,
        nextChapter: _nextChapter(index),
      );
      return const OnlineEpubBuilder().buildChapterDocument(
        OnlineEpubChapter(
          title: chapter.title,
          html: prepareOnlineReviewHtml(html),
          volume: chapter.volume,
        ),
      );
    },
    loadNetworkImage: (url) =>
        service.loadCover(source, url, referer: book.bookUrl),
  );

  Future<bool> isChapterCached(int index) => service.isChapterCached(
    source,
    chapters[index],
    book.bookUrl,
    nextChapter: _nextChapter(index),
  );

  String chapterRevision(int index) => _digest([
    '在线正文5',
    service.chapterContentRevision(
      source,
      chapters[index],
      nextChapter: _nextChapter(index),
    ),
  ]);

  OnlineChapter? _nextChapter(int index) =>
      index + 1 < chapters.length ? chapters[index + 1] : null;

  /// 首屏准备完成后顺序缓存后两章，离开或跳章时停止后续请求。
  Future<void> prefetchAfter(
    int index, {
    required bool Function() isActive,
  }) async {
    for (
      var next = index + 1;
      next <= index + 2 && next < chapters.length;
      next++
    ) {
      if (!isActive()) return;
      try {
        await service.fetchChapterContent(
          source,
          chapters[next],
          book.bookUrl,
          nextChapter: _nextChapter(next),
        );
      } on Object {
        // 邻章失败不遮蔽当前正文，正式进入章节时仍可重试。
      }
    }
  }

  static String _digest(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
}

/// 目录有新增、重排或规则变化时，按章节请求身份恢复，丢弃旧版章内坐标。
class OnlineReadingProgress implements ReaderProgressStore {
  OnlineReadingProgress(this.library, this.book, {this.startChapter});

  final LibraryStore library;
  final OnlineReadingBook book;
  final int? startChapter;

  String get _key => 'online_reading_progress:${book.id}';

  /// 同步器读取最后一次实际保存的位置；目录重排仍由正式 load 处理。
  static Future<ReaderProgress?> savedSnapshot(
    LibraryStore library,
    String bookId,
  ) async {
    final raw = await library.getSetting('online_reading_progress:$bookId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      final cfi = value['cfi'] as String?;
      final spine = value['spine'] as int?;
      final revision = value['revision'] as String?;
      if (cfi == null ||
          cfi.trim().isEmpty ||
          spine == null ||
          spine < 0 ||
          revision == null ||
          revision.isEmpty) {
        return null;
      }
      return ReaderProgress(
        spineIndex: spine,
        pageIndex: value['page'] as int? ?? 0,
        cfi: cfi,
        contentRevision: revision,
        finished: value['finished'] == true,
        readingPercent: (value['percent'] as num?)?.toDouble(),
        chapterTitle: value['title'] as String?,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<ReaderProgress?> load(String bookId) async {
    if (bookId != book.id) return null;
    final saved = await _load();
    final start = startChapter;
    if (start != null && (start < 0 || start >= book.chapters.length)) {
      return saved;
    }
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
    if (value == null || value.isEmpty) {
      final identity = book.initialChapterIdentity;
      if (identity == null) return null;
      final matches = [
        for (final (index, chapter) in book.chapters.indexed)
          if (onlineChapterIdentity(chapter) == identity) index,
      ];
      if (matches.length != 1) return null;
      return ReaderProgress(
        spineIndex: matches.single,
        pageIndex: 0,
        approximate: true,
        contentRevision: book.revision,
      );
    }
    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic>) return null;
      final identity = json['chapterIdentity'];
      final index = identity is String
          ? book.chapters.indexWhere(
              (chapter) => onlineChapterIdentity(chapter) == identity,
            )
          : _legacyChapterIndex(json);
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
        readingPercent: sameRevision
            ? (json['percent'] as num?)?.toDouble()
            : null,
        chapterTitle: book.chapters[index].title,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  int _legacyChapterIndex(Map<String, dynamic> json) {
    final matches = [
      for (final (index, chapter) in book.chapters.indexed)
        if (chapter.url == json['url']) index,
    ];
    // 旧记录没有请求参数证据；同地址多章时不猜测要恢复的章节。
    return matches.length == 1 ? matches.single : -1;
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
        'chapterIdentity': onlineChapterIdentity(book.chapters[spine]),
        'revision': book.revision,
        'chapterRevision': book.chapterRevision(spine),
        'spine': spine,
        'page': progress.pageIndex,
        'cfi': progress.cfi,
        'scroll': progress.scrollOffset,
        'layout': progress.layoutFingerprint,
        'approximate': progress.approximate,
        'finished': progress.finished,
        'percent': progress.readingPercent,
        'title': progress.chapterTitle,
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
