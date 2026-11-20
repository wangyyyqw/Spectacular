import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../library/library_store.dart';
import 'book_source_models.dart';
import 'online_chapter_request.dart';

/// 在线阅读使用的完整详情与目录快照，正文仍由逐章缓存负责。
class OnlineReadingCatalog {
  OnlineReadingCatalog({
    required this.book,
    required List<OnlineChapter> chapters,
    this.lastReadAt,
    this.isStale = false,
  }) : chapters = List.unmodifiable(chapters);

  final OnlineBook book;
  final List<OnlineChapter> chapters;
  final DateTime? lastReadAt;

  /// 最近入口仍可保留书籍信息，过期目录必须联网重新获取后才能阅读。
  final bool isStale;
}

/// 持久化在线目录与最多 20 本最近阅读，不创建本地 EPUB 书架条目。
class OnlineReadingCatalogStore {
  OnlineReadingCatalogStore(this.library, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final LibraryStore library;
  final DateTime Function() _now;

  static const _recentKey = 'online_reading_recent:v1';
  static const _recentLimit = 20;

  // 同一存储上的不同页面也共享完整读改写队列，避免互相覆盖最近记录。
  static final _queues = Expando<_CatalogOperationQueue>();
  _CatalogOperationQueue get _queue =>
      _queues[library] ??= _CatalogOperationQueue();

  /// 详情和目录的完整请求及规则共同区分刷新任务。
  String requestIdentity(BookSource source, OnlineBook book) => _digest([
    source.id,
    _rulesFingerprint(source),
    onlineRequestIdentity(book.bookUrl, book.bookOptions),
    onlineRequestIdentity(
      book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl,
      book.tocOptions,
    ),
  ]);

  /// 来源开关与加载方式变化不删除快照；规则变化后等待新目录成功保存。
  /// 同一详情接口的不同请求参数不得借用另一书的目录。
  Future<OnlineReadingCatalog?> read(BookSource source, OnlineBook book) {
    if (!_validBook(source, book)) return Future.value();
    return _queue.run(() => _readMatchingCatalog(source, book));
  }

  /// 更新目录与详情，保留最近阅读时间；写入失败由在线请求继续提供内容。
  Future<void> save(
    BookSource source,
    OnlineBook book,
    List<OnlineChapter> chapters, {
    bool Function()? isCurrent,
  }) => _write(() async {
    if (!_validCatalog(source, book, chapters) || isCurrent?.call() == false) {
      return;
    }
    final recent = await _readRecent();
    DateTime? lastReadAt;
    for (final item in recent) {
      if (item.matches(source.id, book.bookUrl)) {
        lastReadAt = item.lastReadAt;
        break;
      }
    }
    lastReadAt ??= (await _readCatalog(source, book.bookUrl))?.lastReadAt;
    if (isCurrent?.call() == false) return;
    await _saveCatalog(source, book, chapters, lastReadAt);
  });

  /// 进入逐章阅读时登记最近入口，供正文加载失败后重试。
  ///
  /// 保留已保存的有效目录，避免旧目录中的选章操作覆盖后台刷新的新快照。
  Future<void> remember(
    BookSource source,
    OnlineBook book,
    List<OnlineChapter> chapters, {
    bool preserveSavedCatalog = false,
  }) => _write(() async {
    if (!_validCatalog(source, book, chapters)) return;
    final recent = await _readRecent();
    final lastReadAt = _now().toUtc();
    final cached = await _readMatchingCatalog(
      source,
      book,
      allowStale: preserveSavedCatalog,
    );
    if (cached?.isStale == true) {
      // 旧快照进入阅读时，后台可能已保存新规则目录，只更新时间。
      final key = _catalogKey(source.id, book.bookUrl);
      final json =
          jsonDecode((await library.getSetting(key))!) as Map<String, dynamic>;
      json['lastReadAt'] = lastReadAt.toIso8601String();
      await library.setSetting(key, jsonEncode(json));
    } else {
      await _saveCatalog(
        source,
        cached?.book ?? book,
        cached?.chapters ?? chapters,
        lastReadAt,
      );
    }
    await _saveRecent([
      _RecentBook(source.id, book.bookUrl, lastReadAt),
      for (final item in recent)
        if (!item.matches(source.id, book.bookUrl)) item,
    ]);
  });

  /// 当前可用逐章来源的最近阅读；暂时关闭来源时保留其已有记录。
  Future<List<OnlineReadingCatalog>> recent(List<BookSource> sources) =>
      _queue.run(() async {
        try {
          final available = {
            for (final source in sources)
              if (source.enabled &&
                  source.loadMode == BookSourceLoadMode.chapter)
                source.id: source,
          };
          final catalogs = <OnlineReadingCatalog>[];
          for (final item in await _readRecent()) {
            final source = available[item.sourceId];
            if (source == null) continue;
            final catalog = await _readCatalog(
              source,
              item.bookUrl,
              allowStale: true,
            );
            if (catalog == null) continue;
            catalogs.add(
              OnlineReadingCatalog(
                book: catalog.book,
                chapters: catalog.chapters,
                lastReadAt: item.lastReadAt,
                isStale: catalog.isStale,
              ),
            );
          }
          return List<OnlineReadingCatalog>.unmodifiable(catalogs);
        } on Object {
          return const <OnlineReadingCatalog>[];
        }
      });

  /// 移除一本在线书的目录与最近入口，不操作正文缓存或阅读位置。
  Future<void> remove(BookSource source, OnlineBook book) => _write(() async {
    if (!_validBook(source, book)) return;
    final recent = await _readRecent();
    await library.setSetting(_catalogKey(source.id, book.bookUrl), '');
    await _saveRecent([
      for (final item in recent)
        if (!item.matches(source.id, book.bookUrl)) item,
    ]);
  });

  Future<void> _write(Future<void> Function() action) => _queue.run(() async {
    try {
      await action();
    } on Object {
      // 缓存与最近记录是辅助数据，存储不可用不阻止本次阅读。
    }
  });

  Future<OnlineReadingCatalog?> _readMatchingCatalog(
    BookSource source,
    OnlineBook book, {
    bool allowStale = false,
  }) async {
    final cached = await _readCatalog(
      source,
      book.bookUrl,
      allowStale: allowStale,
    );
    if (cached == null) return null;
    try {
      final requested = onlineRequestIdentity(book.bookUrl, book.bookOptions);
      final stored = onlineRequestIdentity(
        cached.book.bookUrl,
        cached.book.bookOptions,
      );
      return requested == stored ? cached : null;
    } on Object {
      return null;
    }
  }

  Future<OnlineReadingCatalog?> _readCatalog(
    BookSource source,
    String bookUrl, {
    bool allowStale = false,
  }) async {
    try {
      final raw = await library.getSetting(_catalogKey(source.id, bookUrl));
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['version'] != 1 ||
          json['sourceId'] != source.id ||
          json['bookUrl'] != bookUrl) {
        return null;
      }
      final isStale = json['rules'] != _rulesFingerprint(source);
      if (isStale && !allowStale) return null;
      final book = _bookFromJson(json['book'] as Map<String, dynamic>);
      final chapters = [
        for (final value in json['chapters'] as List)
          _chapterFromJson(value as Map<String, dynamic>),
      ];
      if (book.bookUrl != bookUrl || !_validCatalog(source, book, chapters)) {
        return null;
      }
      return OnlineReadingCatalog(
        book: book.copyWith(sourceName: source.name),
        chapters: chapters,
        lastReadAt: json['lastReadAt'] == null
            ? null
            : DateTime.parse(json['lastReadAt'] as String),
        isStale: isStale,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _saveCatalog(
    BookSource source,
    OnlineBook book,
    List<OnlineChapter> chapters,
    DateTime? lastReadAt,
  ) => library.setSetting(
    _catalogKey(source.id, book.bookUrl),
    jsonEncode({
      'version': 1,
      'sourceId': source.id,
      'bookUrl': book.bookUrl,
      'rules': _rulesFingerprint(source),
      'book': _bookToJson(book),
      'chapters': [for (final chapter in chapters) _chapterToJson(chapter)],
      'lastReadAt': lastReadAt?.toUtc().toIso8601String(),
    }),
  );

  Future<List<_RecentBook>> _readRecent() async {
    // 读取失败时让写入方停止更新，避免用空索引覆盖仍有效的历史记录。
    final raw = await library.getSetting(_recentKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['version'] != 1) return const [];
      final entries = <_RecentBook>[];
      for (final value in json['books'] as List) {
        try {
          final item = value as Map<String, dynamic>;
          final sourceId = item['sourceId'] as String;
          final bookUrl = item['bookUrl'] as String;
          if (sourceId.trim().isEmpty || bookUrl.trim().isEmpty) continue;
          entries.add(
            _RecentBook(
              sourceId,
              bookUrl,
              DateTime.parse(item['lastReadAt'] as String),
            ),
          );
        } on Object {
          // 单条损坏不遮蔽其余可读目录。
        }
      }
      return _orderedRecent(entries);
    } on Object {
      return const [];
    }
  }

  Future<void> _saveRecent(List<_RecentBook> recent) => library.setSetting(
    _recentKey,
    jsonEncode({
      'version': 1,
      'books': [
        for (final item in _orderedRecent(recent))
          {
            'sourceId': item.sourceId,
            'bookUrl': item.bookUrl,
            'lastReadAt': item.lastReadAt.toUtc().toIso8601String(),
          },
      ],
    }),
  );

  List<_RecentBook> _orderedRecent(List<_RecentBook> entries) {
    final ordered = entries.indexed.toList()
      ..sort((a, b) {
        final order = b.$2.lastReadAt.compareTo(a.$2.lastReadAt);
        return order == 0 ? a.$1.compareTo(b.$1) : order;
      });
    final seen = <String>{};
    return [
      for (final (_, item) in ordered)
        if (seen.add(_identity(item.sourceId, item.bookUrl))) item,
    ].take(_recentLimit).toList(growable: false);
  }

  bool _validBook(BookSource source, OnlineBook book) =>
      source.id.trim().isNotEmpty &&
      book.sourceId == source.id &&
      book.bookUrl.trim().isNotEmpty &&
      book.name.trim().isNotEmpty &&
      book.chapterCount >= 0;

  bool _validCatalog(
    BookSource source,
    OnlineBook book,
    List<OnlineChapter> chapters,
  ) {
    if (!_validBook(source, book) || chapters.isEmpty) return false;
    final seen = <String>{};
    for (final (index, chapter) in chapters.indexed) {
      if (chapter.index != index ||
          chapter.title.trim().isEmpty ||
          chapter.url.trim().isEmpty ||
          !seen.add(onlineChapterIdentity(chapter))) {
        return false;
      }
    }
    return true;
  }

  String _catalogKey(String sourceId, String bookUrl) =>
      'online_reading_catalog:v1:${_identity(sourceId, bookUrl)}';

  String _identity(String sourceId, String bookUrl) =>
      _digest([sourceId, bookUrl]);

  String _rulesFingerprint(BookSource source) => _digest({
    'version': 1,
    'baseUrl': source.baseUrl,
    'header': source.header,
    'jsLib': source.jsLib,
    'enabledCookieJar': source.enabledCookieJar,
    'bookInfo': {
      'name': source.bookInfo.name,
      'author': source.bookInfo.author,
      'kind': source.bookInfo.kind,
      'wordCount': source.bookInfo.wordCount,
      'chapterCount': source.bookInfo.chapterCount,
      'updateTime': source.bookInfo.updateTime,
      'lastChapter': source.bookInfo.lastChapter,
      'intro': source.bookInfo.intro,
      'coverUrl': source.bookInfo.coverUrl,
      'tocUrl': source.bookInfo.tocUrl,
      'init': source.bookInfo.init,
    },
    'toc': {
      'chapterList': source.toc.chapterList,
      'chapterName': source.toc.chapterName,
      'chapterUrl': source.toc.chapterUrl,
      'updateTime': source.toc.updateTime,
      'nextTocUrl': source.toc.nextTocUrl,
      'isVolume': source.toc.isVolume,
    },
  });

  String _digest(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
}

Map<String, Object?> _bookToJson(OnlineBook book) => {
  'sourceId': book.sourceId,
  'sourceName': book.sourceName,
  'name': book.name,
  'author': book.author,
  'bookUrl': book.bookUrl,
  'tocUrl': book.tocUrl,
  'coverUrl': book.coverUrl,
  'intro': book.intro,
  'kind': book.kind,
  'status': book.status,
  'wordCount': book.wordCount,
  'chapterCount': book.chapterCount,
  'updateTime': book.updateTime,
  'lastChapter': book.lastChapter,
  'bookOptions': book.bookOptions,
  'tocOptions': book.tocOptions,
};

OnlineBook _bookFromJson(Map<String, dynamic> json) => OnlineBook(
  sourceId: json['sourceId'] as String,
  sourceName: json['sourceName'] as String,
  name: json['name'] as String,
  author: json['author'] as String,
  bookUrl: json['bookUrl'] as String,
  tocUrl: json['tocUrl'] as String,
  coverUrl: json['coverUrl'] as String,
  intro: json['intro'] as String,
  kind: json['kind'] as String,
  status: json['status'] as String,
  wordCount: json['wordCount'] as String,
  chapterCount: json['chapterCount'] as int,
  updateTime: json['updateTime'] as String,
  lastChapter: json['lastChapter'] as String,
  bookOptions: (json['bookOptions'] as Map).cast<String, Object?>(),
  tocOptions: (json['tocOptions'] as Map).cast<String, Object?>(),
);

Map<String, Object?> _chapterToJson(OnlineChapter chapter) => {
  'index': chapter.index,
  'title': chapter.title,
  'url': chapter.url,
  'volume': chapter.volume,
  'updateTime': chapter.updateTime,
  'requestOptions': chapter.requestOptions,
};

OnlineChapter _chapterFromJson(Map<String, dynamic> json) => OnlineChapter(
  index: json['index'] as int,
  title: json['title'] as String,
  url: json['url'] as String,
  volume: json['volume'] as String,
  updateTime: json['updateTime'] as String,
  requestOptions: (json['requestOptions'] as Map).cast<String, Object?>(),
);

class _RecentBook {
  const _RecentBook(this.sourceId, this.bookUrl, this.lastReadAt);

  final String sourceId;
  final String bookUrl;
  final DateTime lastReadAt;

  bool matches(String source, String url) =>
      sourceId == source && bookUrl == url;
}

class _CatalogOperationQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }
}
