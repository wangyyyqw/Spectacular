import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart';

import 'book_source_compat.dart';
import 'book_source_cookie_store.dart';
import 'book_source_http_client.dart';
import 'book_source_models.dart';
import 'book_source_discovery.dart';
import 'book_source_rule_engine.dart';
import 'book_source_script.dart';
import 'online_epub_builder.dart';
import 'online_chapter_content_store.dart';
import 'online_chapter_request.dart';

const List<String> _onlineWordCountFields = <String>[
  'wordCount',
  'word_count',
  'word_number',
  'wordNum',
  'word_num',
  'words',
  'total_words',
  'totalWords',
];

const List<String> _onlineChapterCountFields = <String>[
  'chapterCount',
  'chapter_count',
  'chapter_count_total',
  'total_chapters',
  'totalChapter',
  'total_chapter',
  'chapter_num',
  'chapterNum',
  'chapters_count',
  'latest_chapter_index',
  'serial_count',
  'content_chapter_number',
  'real_chapter_order',
  'estimated_chapter_count',
];

const List<String> _onlineUpdateTimeFields = <String>[
  'updateTime',
  'updated_at',
  'update_time',
  'last_chapter_update_time',
  'last_chapter_first_pass_time',
  'latest_chapter_update_time',
  'latest_update_time',
  'firstPassTime',
  'first_pass_time',
];

/// 单个来源的搜索结果或错误。
class OnlineSourceSearchResult {
  const OnlineSourceSearchResult({
    required this.source,
    required this.books,
    this.error = '',
  });

  final BookSource source;
  final List<OnlineBook> books;
  final String error;
}

/// 在线书籍下载结果。
class OnlineBookDownloadResult {
  const OnlineBookDownloadResult({
    required this.book,
    required this.chapters,
    required this.bytes,
    required this.skippedChapters,
    this.skippedReasons = const <String>[],
  });

  final OnlineBook book;
  final List<OnlineChapter> chapters;
  final Uint8List bytes;
  final int skippedChapters;
  final List<String> skippedReasons;
}

typedef OnlineDownloadProgress = void Function(
  int completed,
  int total,
  String message,
);

/// 为一次书源操作创建独立 JS 会话。
typedef BookSourceScriptFactory = BookSourceScriptSession Function(
  BookSource source,
);

class _ChapterContentRequest {
  _ChapterContentRequest({required this.forceRefresh});

  final bool forceRefresh;
  late final Future<String> task;
}

/// 执行书源搜索、详情、目录、正文与 EPUB 下载。
class BookSourceService {
  factory BookSourceService({
    BookSourceHttpClient? httpClient,
    BookSourceRuleEngine ruleEngine = const BookSourceRuleEngine(),
    OnlineEpubBuilder epubBuilder = const OnlineEpubBuilder(),
    BookSourceScriptFactory? scriptFactory,
    BookSourceCookieStore? cookieStore,
    OnlineChapterContentStore? chapterContentStore,
  }) {
    final store = cookieStore ?? BookSourceCookieStore();
    return BookSourceService._(
      cookieStore: store,
      http: httpClient ?? BookSourceHttpClient(cookieStore: store),
      rules: ruleEngine,
      epubBuilder: epubBuilder,
      chapterContentStore: chapterContentStore ?? OnlineChapterContentStore(),
      scriptFactory:
          scriptFactory ??
          (source) => QuickJsBookSourceScriptSession(
            jsLib: source.jsLib,
            cookieProvider: (domain, name) => store.cookieValue(domain, name),
            sourceKey: source.sourceUrl,
            loginInfo: store.loginInfo(source),
            loginHeader: store.loginHeader(source),
            sourceVariable: store.sourceVariable(source),
          ),
    );
  }

  BookSourceService._({
    required this.cookieStore,
    required this.http,
    required this.rules,
    required this.epubBuilder,
    required this.chapterContentStore,
    required this.scriptFactory,
  });

  final BookSourceCookieStore cookieStore;
  final BookSourceHttpClient http;
  final BookSourceRuleEngine rules;
  final OnlineEpubBuilder epubBuilder;
  final BookSourceScriptFactory scriptFactory;
  final OnlineChapterContentStore chapterContentStore;
  final Map<String, _ChapterContentRequest> _chapterRequests = {};
  final Map<String, Future<void>> _chapterWrites = {};
  final Map<String, Future<Uint8List?>> _coverCache =
      <String, Future<Uint8List?>>{};
  final Map<String, List<BookDiscoverCategory>> _discoverCategoryCache =
      <String, List<BookDiscoverCategory>>{};

  static const int maxChapterContentPages = 100;

  void dispose() => http.close();

  /// 来源停止产生请求后，等待已有章节读取与缓存写入释放资源。
  /// 阅读页退出仍可立即取消布局；清理缓存目录时再等待这些独立任务。
  Future<void> get chapterRequestsStopped async {
    while (_chapterRequests.isNotEmpty || _chapterWrites.isNotEmpty) {
      await Future.wait<void>([
        for (final request in _chapterRequests.values.toList())
          request.task.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        for (final write in _chapterWrites.values.toList())
          write.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ]);
    }
  }

  /// 并发搜索多个来源；单个失败不影响其他来源。
  Future<List<OnlineSourceSearchResult>> searchMany(
    List<BookSource> sources,
    String query, {
    int concurrency = 3,
  }) async {
    await cookieStore.load();
    final enabled = <BookSource>[
      for (final source in sources)
        if (source.enabled &&
            source.searchUrl.isNotBlank &&
            source.search.bookList.isNotBlank)
          source,
    ];
    if (enabled.isEmpty) return const <OnlineSourceSearchResult>[];
    final results = List<OnlineSourceSearchResult?>.filled(
      enabled.length,
      null,
    );
    var cursor = 0;

    Future<void> worker() async {
      while (cursor < enabled.length) {
        final index = cursor++;
        final source = enabled[index];
        try {
          final books = await search(source, query);
          results[index] = OnlineSourceSearchResult(
            source: source,
            books: books,
          );
        } on Object catch (error) {
          results[index] = OnlineSourceSearchResult(
            source: source,
            books: const <OnlineBook>[],
            error: '$error',
          );
        }
      }
    }

    await Future.wait(<Future<void>>[
      for (
        var index = 0;
        index < math.min(concurrency, enabled.length);
        index++
      )
        worker(),
    ]);
    return <OnlineSourceSearchResult>[for (final result in results) ?result];
  }

  /// 读取来源声明的发现分类，脚本使用现有正式书源运行时。
  List<BookDiscoverCategory> discoverCategories(BookSource source) {
    final cacheKey = '${source.id}|${source.exploreUrl}';
    final cached = _discoverCategoryCache[cacheKey];
    if (cached != null) return cached;
    var raw = source.exploreUrl.trim();
    final scriptDeclared = raw.startsWith('@js:') || raw.startsWith('<js>');
    if (scriptDeclared) {
      final filter = parseDiscoverFilter(raw, const []);
      if (filter != null) {
        final categories = <BookDiscoverCategory>[
          for (final group in filter.groups)
            for (final option in group.options)
              if (option.parameters.isNotEmpty)
                BookDiscoverCategory(
                  option.title,
                  filter.category({
                    ...filter.defaults,
                    group.name: option.title,
                  }).url,
                ),
        ];
        return _cacheDiscoverCategories(cacheKey, categories);
      }
    }
    final parsed = scriptDeclared
        ? <BookDiscoverCategory>[]
        : parseDiscoverCategories(raw);
    if (!scriptDeclared && parsed.isNotEmpty) {
      return _cacheDiscoverCategories(cacheKey, parsed);
    }
    if (scriptDeclared || raw.startsWith('[') || raw.startsWith('{')) {
      final script = scriptFactory(source);
      try {
        final body = scriptDeclared
            ? raw.substring(4).replaceFirst(RegExp(r'</js>\s*$'), '')
            : '($raw)';
        raw = script.evaluate(
          'JSON.stringify(eval(${jsonEncode(body)}))',
          result: '',
          variables: {'baseUrl': source.baseUrl},
          resolveString: (_) => '',
          resolveList: (_) => const [],
        );
      } finally {
        script.dispose();
      }
    }
    return _cacheDiscoverCategories(cacheKey, parseDiscoverCategories(raw));
  }

  List<BookDiscoverCategory> _cacheDiscoverCategories(
    String key,
    List<BookDiscoverCategory> categories,
  ) {
    final result = List<BookDiscoverCategory>.unmodifiable(categories);
    _discoverCategoryCache[key] = result;
    while (_discoverCategoryCache.length > 64) {
      _discoverCategoryCache.remove(_discoverCategoryCache.keys.first);
    }
    return result;
  }

  /// 发现列表与搜索列表共用请求、规则和字段解析，只替换地址及列表声明。
  Future<List<OnlineBook>> discover(
    BookSource source,
    BookDiscoverCategory category, {
    int page = 1,
  }) async {
    final rawRule = source.raw['ruleExplore'];
    final rule = rawRule is Map
        ? BookListRule.fromJson(Map<String, Object?>.from(rawRule))
        : source.search;
    return _loadBookList(
      source,
      '',
      page: page,
      listRule: rule,
      requestUrl: category.url,
      requestOptions: category.options,
    );
  }

  /// 搜索单个来源。
  Future<List<OnlineBook>> search(
    BookSource source,
    String rawQuery, {
    int page = 1,
  }) => _loadBookList(source, rawQuery, page: page);

  Future<List<OnlineBook>> _loadBookList(
    BookSource source,
    String rawQuery, {
    int page = 1,
    BookListRule? listRule,
    String? requestUrl,
    Map<String, Object?>? requestOptions,
  }) async {
    await cookieStore.load();
    final fields = listRule ?? source.search;
    final query = rawQuery.trim();
    if (requestUrl == null && query.isEmpty) {
      throw const BookSourceException('请输入要搜索的书名或作者');
    }
    if (requestUrl == null && !source.canSearch) {
      throw const BookSourceException('该书源未启用或不支持搜索');
    }
    final script = scriptFactory(source);
    try {
      final url = _searchUrl(source, query, page, script, requestUrl);
      final response = await http.fetchText(
        source,
        url,
        options: requestOptions ?? source.searchOptions,
        referer: source.baseUrl,
      );
      final root = _parseBody(response.body);
      final context = BookSourceRuleContext(
        baseUrl: source.baseUrl,
        pageUrl: response.uri.toString(),
        variables: <String, String>{
          'key': query,
          'searchKey': query,
          'page': '$page',
          'searchPage': '$page',
        },
      );
      var nodes = rules.evaluateList(
        root,
        fields.bookList,
        context,
        script: script,
      );
      if (nodes.isEmpty && root is Map) {
        final data = root['data'];
        if (data is Map) {
          nodes = rules.evaluateList(
            data,
            fields.bookList,
            context,
            script: script,
          );
          if (nodes.isEmpty) nodes = <Object>[data];
        } else if (data is List) {
          nodes = data.whereType<Object>().toList();
        }
      }
      if (nodes.isEmpty && root is List) {
        nodes = root.whereType<Object>().toList();
      }
      // 列表声明可能直接命中 JSON 数组；每个数组元素才是一条书籍。
      nodes = [
        for (final node in nodes)
          if (node is List) ...node.whereType<Object>() else node,
      ];
      if (nodes.isEmpty && root is Document && requestUrl == null) {
        return _fallbackHtmlSearch(
          source,
          root,
          query,
          response.uri.toString(),
        );
      }

      final books = <OnlineBook>[];
      final seen = <String>{};
      for (final node in nodes) {
        final name = _field(node, fields.name, context, script).ifBlank(
          _commonJsonField(node, const <String>['name', 'title', 'bookName']),
        );
        if (name.isEmpty) continue;
        final bookUrlRule = _field(node, fields.bookUrl, context, script);
        var bookUrl = bookUrlRule;
        if (bookUrl.isEmpty && node is Element) {
          bookUrl =
              node.attributes['href'] ??
              node.querySelector('a')?.attributes['href'] ??
              '';
        }
        bookUrl = _commonJsonField(node, const <String>[
          'bookUrl',
          'url',
          'detailUrl',
        ]).ifBlank(bookUrl);
        final bookRequest = splitBookSourceUrlOptions(bookUrl);
        final absoluteBookUrl = rules.resolveUrl(
          context.pageUrl,
          bookRequest.url,
        );
        if (absoluteBookUrl.isEmpty) continue;
        final author = _field(
          node,
          fields.author,
          context,
          script,
        ).ifBlank(_commonJsonField(node, const <String>['author', 'writer']));
        var cover = _field(node, fields.coverUrl, context, script).ifBlank(
          _commonJsonField(node, const <String>[
            'coverUrl',
            'cover',
            'picUrl',
            'imageUrl',
            'thumb_url',
            'thumbUrl',
          ]),
        );
        // 部分书源用图片标识拼出的旧地址已失效，保留接口提供的签名缩略图。
        if (Uri.tryParse(cover)?.path.contains('/novel-pic-r/') ?? false) {
          final thumbnail = _commonJsonField(node, const [
            'thumb_url',
            'thumbUrl',
          ]);
          if (_isHttpUrl(thumbnail)) cover = thumbnail;
        }
        final lastChapter = _field(node, fields.lastChapter, context, script)
            .ifBlank(
              _commonJsonField(node, const <String>[
                'lastChapter',
                'latestChapter',
                'last_chapter',
                'last_chapter_title',
                'latest_chapter_name',
                'lastChapterTitle',
              ]),
            );
        final kindRaw = _field(node, fields.kind, context, script).ifBlank(
          _commonJsonField(node, const <String>[
            'kind',
            'category',
            'status',
            'bookStatus',
          ]),
        );
        final status = normalizeOnlineStatus(kindRaw, lastChapter: lastChapter)
            .ifBlank(
              normalizeOnlineStatus(
                _commonJsonField(node, const [
                  'status',
                  'bookStatus',
                  'serializeStatus',
                  'serializeStatusName',
                  'creation_status',
                ]),
              ),
            );
        final rawWordCount = _field(
          node,
          fields.wordCount,
          context,
          script,
        ).ifBlank(_commonJsonField(node, _onlineWordCountFields));
        final rawChapterCount = _field(
          node,
          fields.chapterCount,
          context,
          script,
        ).ifBlank(_commonJsonField(node, _onlineChapterCountFields));
        final rawUpdateTime = _field(
          node,
          fields.updateTime,
          context,
          script,
        ).ifBlank(_commonJsonField(node, _onlineUpdateTimeFields));
        final book = OnlineBook(
          sourceId: source.id,
          sourceName: source.name,
          name: name,
          author: author,
          bookUrl: absoluteBookUrl,
          tocUrl: absoluteBookUrl,
          bookOptions: bookRequest.options,
          tocOptions: bookRequest.options,
          coverUrl: rules.resolveUrl(context.pageUrl, cover),
          intro: normalizeOnlineIntro(
            _field(node, fields.intro, context, script, true).ifBlank(
              _commonJsonField(node, const <String>[
                'intro',
                'description',
                'desc',
              ]),
            ),
          ),
          kind: requestUrl == null ? status.ifBlank(kindRaw) : kindRaw,
          status: status,
          wordCount: normalizeOnlineWordCount(rawWordCount),
          chapterCount: parseOnlineChapterCount(rawChapterCount),
          updateTime: formatOnlineUpdateTime(rawUpdateTime),
          lastChapter: lastChapter,
        );
        final identity = '${book.name}|${book.author}|${book.bookUrl}';
        if (!seen.add(identity)) continue;
        books.add(book);
      }
      return books;
    } finally {
      script.dispose();
    }
  }

  /// 从详情页补齐搜索结果的章节数、更新时间等标签字段。
  ///
  /// 单个详情失败或无响应时保留原搜索结果，不阻断搜索。
  Future<List<OnlineBook>> enrichSearchResults(
    BookSource source,
    List<OnlineBook> books, {
    int limit = 8,
    int concurrency = 3,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    await cookieStore.load();
    if (books.isEmpty || limit <= 0) return books;
    final enriched = List<OnlineBook>.of(books);
    final selected = math.min(limit, books.length);
    final deadline = DateTime.now().add(timeout);
    var cursor = 0;

    Future<void> worker() async {
      while (cursor < selected) {
        final index = cursor++;
        final book = books[index];
        if (book.chapterCount > 0 &&
            book.updateTime.isNotBlank &&
            book.wordCount.isNotBlank &&
            book.status.isNotBlank) {
          continue;
        }
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) return;
        try {
          final info = await loadBookInfo(source, book).timeout(remaining);
          enriched[index] = _mergeSearchMetadata(book, info);
        } on Object {
          // 详情不可用时继续展示搜索结果已有字段。
        }
      }
    }

    await Future.wait(<Future<void>>[
      for (var index = 0; index < math.min(concurrency, selected); index++)
        worker(),
    ]);
    return enriched;
  }

  OnlineBook _mergeSearchMetadata(OnlineBook base, OnlineBook detail) {
    return base.copyWith(
      author: base.author.isNotBlank ? base.author : detail.author,
      coverUrl: base.coverUrl.isNotBlank ? base.coverUrl : detail.coverUrl,
      intro: base.intro.isNotBlank ? base.intro : detail.intro,
      kind: base.kind.isNotBlank ? base.kind : detail.kind,
      status: base.status.isNotBlank ? base.status : detail.status,
      wordCount: base.wordCount.isNotBlank ? base.wordCount : detail.wordCount,
      chapterCount: base.chapterCount > 0
          ? base.chapterCount
          : detail.chapterCount,
      updateTime: base.updateTime.isNotBlank
          ? base.updateTime
          : detail.updateTime,
      lastChapter: base.lastChapter.isNotBlank
          ? base.lastChapter
          : detail.lastChapter,
    );
  }

  /// 读取详情页字段并定位目录地址。
  Future<OnlineBook> loadBookInfo(BookSource source, OnlineBook book) async {
    await cookieStore.load();
    final script = scriptFactory(source);
    try {
      final response = await http.fetchText(
        source,
        book.bookUrl,
        options: book.bookOptions,
        referer: source.baseUrl,
      );
      var root = _parseBody(response.body);
      final context = BookSourceRuleContext(
        baseUrl: source.baseUrl,
        pageUrl: response.uri.toString(),
        variables: <String, String>{'bookUrl': book.bookUrl},
      );
      if (source.bookInfo.init.trim().isNotEmpty) {
        final initialized = rules.evaluateList(
          root,
          source.bookInfo.init,
          context,
          script: script,
        );
        if (initialized.isNotEmpty) root = initialized.first;
      }
      final name = _field(
        root,
        source.bookInfo.name,
        context,
        script,
      ).ifBlank(book.name);
      final author = _field(
        root,
        source.bookInfo.author,
        context,
        script,
      ).ifBlank(book.author);
      final tocRequest = _urlField(
        root,
        source.bookInfo.tocUrl,
        context,
        script,
      );
      final coverRequest = _urlField(
        root,
        source.bookInfo.coverUrl,
        context,
        script,
      );
      final lastChapter = _field(
        root,
        source.bookInfo.lastChapter,
        context,
        script,
      ).ifBlank(book.lastChapter);
      final kindRaw = _field(
        root,
        source.bookInfo.kind,
        context,
        script,
      ).ifBlank(book.kind);
      final status = normalizeOnlineStatus(kindRaw, lastChapter: lastChapter);
      final wordCount = _field(
        root,
        source.bookInfo.wordCount,
        context,
        script,
      ).ifBlank(book.wordCount);
      final chapterCountRaw = _field(
        root,
        source.bookInfo.chapterCount,
        context,
        script,
      ).ifBlank(_commonJsonField(root, _onlineChapterCountFields));
      final updateTimeRaw = _field(
        root,
        source.bookInfo.updateTime,
        context,
        script,
      ).ifBlank(_commonJsonField(root, _onlineUpdateTimeFields));
      final parsedChapterCount = parseOnlineChapterCount(chapterCountRaw);
      final formattedUpdateTime = formatOnlineUpdateTime(updateTimeRaw);
      return book.copyWith(
        name: name,
        author: author,
        tocUrl: rules
            .resolveUrl(response.uri.toString(), tocRequest.url)
            .ifBlank(book.tocUrl.ifBlank(book.bookUrl)),
        tocOptions: tocRequest.url.isEmpty
            ? book.tocOptions
            : tocRequest.options,
        coverUrl: rules
            .resolveUrl(response.uri.toString(), coverRequest.url)
            .ifBlank(book.coverUrl),
        intro: normalizeOnlineIntro(
          _field(
            root,
            source.bookInfo.intro,
            context,
            script,
            true,
          ).ifBlank(book.intro),
        ),
        kind: status.ifBlank(kindRaw),
        status: status,
        wordCount: normalizeOnlineWordCount(wordCount),
        chapterCount: parsedChapterCount > 0
            ? parsedChapterCount
            : book.chapterCount,
        updateTime: formattedUpdateTime.isNotEmpty
            ? formattedUpdateTime
            : book.updateTime,
        lastChapter: lastChapter,
      );
    } finally {
      script.dispose();
    }
  }

  /// 读取目录，并跟随 `nextTocUrl` 合并后续页。
  Future<List<OnlineChapter>> fetchToc(
    BookSource source,
    OnlineBook book,
  ) async {
    await cookieStore.load();
    final script = scriptFactory(source);
    try {
      final tocUrl = book.tocUrl.isNotBlank ? book.tocUrl : book.bookUrl;
      final tocIdentity = onlineRequestIdentity(tocUrl, book.tocOptions);
      final bookIdentity = onlineRequestIdentity(
        book.bookUrl,
        book.bookOptions,
      );
      final pendingPages = <({String url, Map<String, Object?> options})>[
        (url: tocUrl, options: book.tocOptions),
      ];
      final chapters = <OnlineChapter>[];
      final seenChapters = <String>{};
      final seenPages = <String>{};
      var pageCount = 0;
      var volume = '';
      while (pendingPages.isNotEmpty) {
        final current = pendingPages.removeAt(0);
        if (!current.url.isNotBlank) continue;
        final identity = onlineRequestIdentity(current.url, current.options);
        if (!seenPages.add(identity)) continue;
        if (pageCount >= 30) {
          throw const BookSourceException(
            '目录分页过多，已停止获取，请检查书源目录规则',
            code: 'ONLINE_TOC_PAGE_LIMIT',
          );
        }
        pageCount += 1;
        final response = await http.fetchText(
          source,
          current.url,
          options: current.options,
          referer: book.bookUrl,
        );
        final responseIdentity = onlineRequestIdentity(
          response.uri.toString(),
          current.options,
        );
        if (responseIdentity != identity && !seenPages.add(responseIdentity)) {
          continue;
        }
        final root = _parseBody(response.body);
        final context = BookSourceRuleContext(
          baseUrl: source.baseUrl,
          pageUrl: response.uri.toString(),
          variables: <String, String>{
            'bookUrl': book.bookUrl,
            'tocUrl': current.url,
          },
        );
        final nodes = rules.evaluateList(
          root,
          source.toc.chapterList,
          context,
          script: script,
        );
        for (final node in nodes) {
          var name = _field(node, source.toc.chapterName, context, script);
          var chapterUrl = _field(node, source.toc.chapterUrl, context, script);
          final volumeFlag = _field(
            node,
            source.toc.isVolume,
            context,
            script,
          ).toLowerCase();
          final isVolume =
              volumeFlag.isNotEmpty &&
              !const {
                'null',
                'false',
                'no',
                'not',
                '0',
                '0.0',
              }.contains(volumeFlag);
          if (node is Element) {
            final link = node.localName == 'a' ? node : node.querySelector('a');
            name = name.ifBlank(link?.text ?? node.text);
            if (!isVolume) {
              chapterUrl = chapterUrl.ifBlank(link?.attributes['href'] ?? '');
            }
          } else if (node is Map) {
            name = name.ifBlank(
              _commonJsonField(node, const <String>[
                'chapterName',
                'title',
                'name',
              ]),
            );
            if (!isVolume) {
              chapterUrl = chapterUrl.ifBlank(
                _commonJsonField(node, const <String>[
                  'chapterUrl',
                  'url',
                  'link',
                ]),
              );
            }
          }
          name = cleanOnlineChapterTitle(name);
          final chapterRequest = splitBookSourceUrlOptions(chapterUrl);
          final absolute = rules.resolveUrl(
            context.pageUrl,
            chapterRequest.url,
          );
          final chapterIdentity = onlineRequestIdentity(
            absolute,
            chapterRequest.options,
          );
          if (isVolume) {
            if (name.isNotEmpty) volume = name;
            // 卷头没有正文地址时只分组，避免补成目录页或锚点章节。
            if (chapterRequest.url.trim().startsWith('#') ||
                (!_isHttpUrl(absolute) && !absolute.startsWith('data:')) ||
                chapterIdentity == responseIdentity ||
                chapterIdentity == tocIdentity ||
                chapterIdentity == bookIdentity) {
              continue;
            }
          }
          if (name.isEmpty ||
              absolute.isEmpty ||
              !seenChapters.add(chapterIdentity)) {
            continue;
          }
          chapters.add(
            OnlineChapter(
              index: chapters.length,
              title: name,
              url: absolute,
              volume: volume,
              updateTime: _field(node, source.toc.updateTime, context, script),
              requestOptions: chapterRequest.options,
            ),
          );
        }
        final nextPages = _urlRequests(
          root,
          source.toc.nextTocUrl,
          context,
          script,
        );
        for (final next in nextPages) {
          final resolved = rules.resolveUrl(response.uri.toString(), next.url);
          if (resolved.isNotEmpty) {
            pendingPages.add((url: resolved, options: next.options));
          }
        }
      }
      if (chapters.isEmpty) {
        throw const BookSourceException(
          '目录为空，可能是书源规则失效或站点限制',
          code: 'ONLINE_TOC_EMPTY',
        );
      }
      return chapters;
    } finally {
      script.dispose();
    }
  }

  /// 下载完整书籍并生成 EPUB。
  Future<OnlineBookDownloadResult> download(
    BookSource source,
    OnlineBook searchBook, {
    OnlineDownloadProgress? onProgress,
    bool Function()? isCancelled,
    OnlineBook? preparedBook,
    List<OnlineChapter>? selectedChapters,
    List<OnlineChapter>? chapterDirectory,
  }) async {
    await cookieStore.load();
    onProgress?.call(0, 0, '正在读取详情');
    final info = preparedBook ?? await loadBookInfo(source, searchBook);
    _checkCancelled(isCancelled);
    onProgress?.call(0, 0, '正在读取目录');
    final toc = selectedChapters ?? await fetchToc(source, info);
    _checkCancelled(isCancelled);
    final directory = chapterDirectory ?? toc;
    final nextChapters = <String, OnlineChapter>{};
    if (chapterDirectory != null || selectedChapters == null) {
      for (var index = 0; index + 1 < directory.length; index++) {
        nextChapters[onlineChapterIdentity(directory[index])] =
            directory[index + 1];
      }
    } else {
      // 子集不代表完整目录，仅采用序号确实相邻的已知章节。
      final byIndex = {for (final chapter in directory) chapter.index: chapter};
      for (final chapter in toc) {
        final next = byIndex[chapter.index + 1];
        if (next != null) nextChapters[onlineChapterIdentity(chapter)] = next;
      }
    }

    final images = <String, OnlineEpubImage>{};
    var imageBytes = 0;
    final cover = selectedChapters == null
        ? await _downloadCover(source, info)
        : null;
    final chapters = <OnlineEpubChapter>[];
    final skippedReasons = <String>[];
    var skipped = 0;
    for (var index = 0; index < toc.length; index++) {
      _checkCancelled(isCancelled);
      final chapter = toc[index];
      onProgress?.call(index, toc.length, '正在下载：${chapter.title}');
      String? content;
      Object? failure;
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          content = await fetchChapterContent(
            source,
            chapter,
            info.bookUrl,
            forceRefresh: source.loadMode == BookSourceLoadMode.book,
            nextChapter: nextChapters[onlineChapterIdentity(chapter)],
          );
          failure = null;
          break;
        } on Object catch (error) {
          failure = error;
          final transient = error is BookSourceException && error.isTransient;
          if (!transient || attempt >= 2) break;
          await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
          _checkCancelled(isCancelled);
        }
      }
      if (content == null) {
        skipped += 1;
        _recordSkipped(skippedReasons, chapter.title, failure);
        onProgress?.call(
          index + 1,
          toc.length,
          '已下载 ${index + 1}/${toc.length} 章（跳过 $skipped 章）',
        );
        continue;
      }
      try {
        final prepared = await _prepareContentImages(
          source,
          content,
          chapter.url,
          images,
          imageBytes,
        );
        imageBytes = prepared.totalBytes;
        if (prepared.html.trim().isEmpty) {
          skipped += 1;
          _recordSkipped(skippedReasons, chapter.title, '正文为空');
        } else {
          chapters.add(
            OnlineEpubChapter(
              title: chapter.title,
              html: prepared.html,
              sourceUrl: chapter.url,
              volume: chapter.volume,
            ),
          );
        }
      } on Object catch (error) {
        skipped += 1;
        _recordSkipped(skippedReasons, chapter.title, error);
      }
      onProgress?.call(
        index + 1,
        toc.length,
        skipped > 0
            ? '已下载 ${index + 1}/${toc.length} 章（跳过 $skipped 章）'
            : '已下载 ${index + 1}/${toc.length} 章',
      );
    }
    if (chapters.isEmpty) {
      final detail = skippedReasons.isEmpty ? '' : '（${skippedReasons.first}）';
      throw BookSourceException(
        '正文下载失败，没有可导入的章节$detail',
        code: 'ONLINE_CONTENT_EMPTY',
      );
    }
    onProgress?.call(toc.length, toc.length, '正在生成 EPUB');
    final bytes = epubBuilder.build(
      OnlineEpubInput(
        title: info.name,
        author: info.author,
        intro: info.intro,
        sourceName: info.sourceName,
        bookUrl: info.bookUrl,
        cover: cover,
        images: images.values.toList(),
        chapters: chapters,
      ),
    );
    return OnlineBookDownloadResult(
      book: info,
      chapters: toc,
      bytes: bytes,
      skippedChapters: skipped,
      skippedReasons: skippedReasons,
    );
  }

  /// 下载单章正文，并跟随 `nextContentUrl` 合并分页。
  Future<String> fetchChapterContent(
    BookSource source,
    OnlineChapter chapter,
    String bookUrl, {
    bool forceRefresh = false,
    OnlineChapter? nextChapter,
    String? nextChapterUrl,
  }) async {
    final boundary = _nextChapterRequest(
      source,
      chapter,
      nextChapter: nextChapter,
      nextChapterUrl: nextChapterUrl,
    );
    final fingerprint = chapterContentRevision(
      source,
      chapter,
      nextChapter: nextChapter,
      nextChapterUrl: nextChapterUrl,
    );
    final key = jsonEncode([source.id, bookUrl, chapter.url, fingerprint]);
    final pending = _chapterRequests[key];
    if (pending != null && (!forceRefresh || pending.forceRefresh)) {
      return pending.task;
    }
    // 新强刷替换旧普通任务的缓存写入资格，后来的普通加载共用强刷。
    final request = _ChapterContentRequest(forceRefresh: forceRefresh);
    _chapterRequests[key] = request;
    request.task = _readOrFetchChapter(
      source,
      chapter,
      bookUrl,
      fingerprint,
      boundary,
      key,
      request,
    );
    try {
      return await request.task;
    } finally {
      if (identical(_chapterRequests[key], request)) {
        _chapterRequests.remove(key);
      }
    }
  }

  Future<String> _readOrFetchChapter(
    BookSource source,
    OnlineChapter chapter,
    String bookUrl,
    String fingerprint,
    ({String url, Map<String, Object?> options})? boundary,
    String key,
    _ChapterContentRequest request,
  ) async {
    if (!request.forceRefresh) {
      try {
        final cached = await chapterContentStore.read(
          sourceId: source.id,
          bookUrl: bookUrl,
          chapterUrl: chapter.url,
          rulesFingerprint: fingerprint,
        );
        if (cached != null) return cached;
      } on Object {
        // 缓存不可用时仍允许在线阅读。
      }
    }
    final content = await _fetchChapterContent(
      source,
      chapter,
      bookUrl,
      boundary,
    );
    await _writeChapterContent(
      source,
      chapter,
      bookUrl,
      fingerprint,
      content,
      key,
      request,
    );
    return content;
  }

  Future<void> _writeChapterContent(
    BookSource source,
    OnlineChapter chapter,
    String bookUrl,
    String fingerprint,
    String content,
    String key,
    _ChapterContentRequest request,
  ) async {
    final previous = _chapterWrites[key] ?? Future<void>.value();
    final write = previous.then((_) async {
      if (!identical(_chapterRequests[key], request)) return;
      try {
        await chapterContentStore.write(
          sourceId: source.id,
          bookUrl: bookUrl,
          chapterUrl: chapter.url,
          rulesFingerprint: fingerprint,
          content: content,
        );
      } on Object {
        // 正文已获取，缓存写入失败不影响本次阅读。
      }
    });
    _chapterWrites[key] = write;
    try {
      await write;
    } finally {
      if (identical(_chapterWrites[key], write)) {
        _chapterWrites.remove(key)?.ignore();
      }
    }
  }

  Future<String> _fetchChapterContent(
    BookSource source,
    OnlineChapter chapter,
    String bookUrl,
    ({String url, Map<String, Object?> options})? boundary,
  ) async {
    await cookieStore.load();
    final script = scriptFactory(source);
    try {
      final pendingPages = <({String url, Map<String, Object?> options})>[
        (url: chapter.url, options: chapter.requestOptions),
      ];
      final seen = <String>{};
      final htmlParts = <String>[];
      final boundaryId = boundary == null
          ? null
          : onlineRequestIdentity(boundary.url, boundary.options);
      var pageCount = 0;
      String? contentPageUrl;
      while (pendingPages.isNotEmpty) {
        final current = pendingPages.removeAt(0);
        if (!current.url.isNotBlank) continue;
        final identity = onlineRequestIdentity(current.url, current.options);
        if (identity == boundaryId || !seen.add(identity)) continue;
        if (pageCount >= maxChapterContentPages) {
          throw const BookSourceException(
            '章节正文分页过多，已停止获取，请检查书源分页规则',
            code: 'ONLINE_CONTENT_PAGE_LIMIT',
          );
        }
        pageCount += 1;
        final data = _decodeDataUrl(current.url);
        final Object? root;
        final String pageUrl;
        if (data != null) {
          root = data;
          pageUrl = bookUrl;
        } else {
          final response = await http.fetchText(
            source,
            current.url,
            options: current.options,
            referer: bookUrl,
          );
          root = _parseBody(response.body);
          pageUrl = response.uri.toString();
          final responseIdentity = onlineRequestIdentity(
            pageUrl,
            current.options,
          );
          // 重定向目标可能已读取，或已经进入目录中的下一章。
          if (responseIdentity == boundaryId ||
              (responseIdentity != identity && !seen.add(responseIdentity))) {
            continue;
          }
        }
        contentPageUrl ??= pageUrl;
        final context = BookSourceRuleContext(
          baseUrl: source.baseUrl,
          pageUrl: pageUrl,
          variables: <String, String>{
            'bookUrl': bookUrl,
            'chapterUrl': chapter.url,
            'nextChapterUrl': boundary?.url ?? '',
            'title': chapter.title,
          },
        );
        final html = await _evaluateContentRule(
          source: source,
          root: root,
          rule: source.content.content,
          context: context,
          script: script,
          referer: pageUrl,
        );
        if (html.trim().isNotEmpty) {
          htmlParts.add(_resolveChapterImages(html.trim(), pageUrl));
        }
        if (data != null) break;
        final nextPages = _urlRequests(
          root,
          source.content.nextContentUrl,
          context,
          script,
        );
        for (final next in nextPages) {
          final resolved = rules.resolveUrl(pageUrl, next.url);
          if (resolved.isNotEmpty) {
            pendingPages.add((url: resolved, options: next.options));
          }
        }
      }
      var content = cleanOnlineChapterContent(htmlParts.join('\n'));
      if (source.content.replaceRegex.isNotBlank) {
        final pageUrl = contentPageUrl ?? bookUrl;
        // 全章分页合并后执行一次；磁盘缓存保存已经替换的结果。
        content = await _evaluateContentRule(
          source: source,
          root: content,
          rule: source.content.replaceRegex,
          context: BookSourceRuleContext(
            baseUrl: source.baseUrl,
            pageUrl: pageUrl,
            variables: <String, String>{
              'bookUrl': bookUrl,
              'chapterUrl': chapter.url,
              'nextChapterUrl': boundary?.url ?? '',
              'title': chapter.title,
            },
          ),
          script: script,
          referer: pageUrl,
        );
        content = _resolveChapterImages(content, pageUrl);
      }
      final reason = chapterContentFailureReason(content);
      if (reason != null) {
        throw BookSourceException(
          '章节正文无效：$reason',
          code: 'ONLINE_CONTENT_INVALID',
        );
      }
      return content;
    } finally {
      script.dispose();
    }
  }

  String _resolveChapterImages(String html, String pageUrl) {
    if (!html.toLowerCase().contains('<img')) return html;
    final document = rules.parseHtml(html);
    for (final image in document.querySelectorAll('img')) {
      final raw = (image.attributes['data-src'] ?? '')
          .trim()
          .ifBlank((image.attributes['data-original'] ?? '').trim())
          .ifBlank((image.attributes['src'] ?? '').trim());
      if (raw.isNotEmpty) {
        image.attributes['src'] = rules.resolveUrl(pageUrl, raw);
      }
      image.attributes.remove('data-src');
      image.attributes.remove('data-original');
    }
    return document.body?.innerHtml ?? html;
  }

  Future<String> _evaluateContentRule({
    required BookSource source,
    required Object? root,
    required String rule,
    required BookSourceRuleContext context,
    required BookSourceScriptSession script,
    required String referer,
  }) async {
    if (rule.trim().isEmpty) return '';
    for (var pass = 0; pass < 5; pass++) {
      final html = rules.evaluateHtml(root, rule, context, script: script);
      final pending = script.takePendingRequests();
      if (pending.isEmpty) return html;
      for (final request in pending) {
        final data = _decodeDataUrl(request.url);
        if (data != null) {
          script.rememberResponse(request.key, data);
          continue;
        }
        final isPost = request.method.toUpperCase() == 'POST';
        final response = await http.fetchText(
          source,
          request.url,
          headers: request.headers,
          options: isPost
              ? <String, Object?>{'method': 'POST', 'body': request.body}
              : const <String, Object?>{},
          referer: referer,
        );
        script.rememberResponse(request.key, response.body);
      }
    }
    throw const BookSourceException(
      '正文脚本请求次数过多，已停止',
      code: 'ONLINE_CONTENT_SCRIPT_LOOP',
    );
  }

  ({String url, Map<String, Object?> options})? _nextChapterRequest(
    BookSource source,
    OnlineChapter chapter, {
    OnlineChapter? nextChapter,
    String? nextChapterUrl,
  }) {
    final request = nextChapter == null
        ? splitBookSourceUrlOptions(nextChapterUrl ?? '')
        : (url: nextChapter.url, options: nextChapter.requestOptions);
    if (!request.url.isNotBlank) return null;
    final chapterUrl = rules.resolveUrl(source.baseUrl, chapter.url);
    final base = chapterUrl.startsWith('data:') ? source.baseUrl : chapterUrl;
    final resolved = rules.resolveUrl(base, request.url);
    return (
      url:
          Uri.tryParse(resolved)?.removeFragment().normalizePath().toString() ??
          resolved,
      options: request.options,
    );
  }

  /// 影响正文的书源设置发生变化时，不复用旧章内容与章内坐标。
  String contentRulesFingerprint(BookSource source) => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'version': 4,
            'base': source.baseUrl,
            'headers': source.header,
            'jsLib': source.jsLib,
            'content': source.content.content,
            'next': source.content.nextContentUrl,
            'replace': source.content.replaceRegex,
            'source': source.content.sourceRegex,
          }),
        ),
      )
      .toString();

  String chapterContentRevision(
    BookSource source,
    OnlineChapter chapter, {
    OnlineChapter? nextChapter,
    String? nextChapterUrl,
  }) {
    final boundary = _nextChapterRequest(
      source,
      chapter,
      nextChapter: nextChapter,
      nextChapterUrl: nextChapterUrl,
    );
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              contentRulesFingerprint(source),
              chapter.title,
              chapter.updateTime,
              onlineChapterIdentity(chapter),
              if (boundary != null)
                onlineRequestIdentity(boundary.url, boundary.options),
            ]),
          ),
        )
        .toString();
  }

  String? _decodeDataUrl(String raw) {
    final text = raw.trim();
    if (!text.startsWith('data:')) return null;
    final comma = text.indexOf(',');
    if (comma < 0) return null;
    final meta = text.substring(5, comma).toLowerCase();
    final payload = text.substring(comma + 1);
    try {
      if (meta.endsWith(';base64')) {
        return utf8.decode(base64.decode(payload), allowMalformed: true);
      }
      return UriData.parse(text).contentAsString(encoding: utf8);
    } on FormatException {
      throw const BookSourceException(
        '章节地址中的 data URL 无法解码',
        code: 'ONLINE_CHAPTER_DATA_URL',
      );
    }
  }

  /// 加载封面或插图；同一来源地址在进程内缓存，失败结果不保留。
  Future<Uint8List?> loadCover(
    BookSource source,
    String url, {
    String referer = '',
  }) {
    final raw = url.trim();
    if (raw.isEmpty) return Future<Uint8List?>.value();
    final data = decodeDataUrlImage(raw);
    if (data != null) return Future<Uint8List?>.value(data);
    if (!_isHttpUrl(raw)) return Future<Uint8List?>.value();
    final key = '${source.id}|${referer.trim()}|$raw';
    final cached = _coverCache[key];
    if (cached != null) return cached;
    final future = _fetchImageBytes(source, raw, referer: referer);
    _coverCache[key] = future;
    while (_coverCache.length > 64) {
      _coverCache.remove(_coverCache.keys.first);
    }
    return future
        .then((bytes) {
          if (bytes == null) _coverCache.remove(key);
          return bytes;
        })
        .catchError((Object _) {
          _coverCache.remove(key);
          return null;
        });
  }

  Future<Uint8List?> _fetchImageBytes(
    BookSource source,
    String url, {
    String referer = '',
  }) async {
    try {
      final response = await http.fetchBytes(source, url, referer: referer);
      if (response.bytes.isEmpty || response.bytes.length > 8 * 1024 * 1024) {
        return null;
      }
      return _imageType(response.bytes) == null ? null : response.bytes;
    } on BookSourceException {
      return null;
    }
  }

  Future<OnlineEpubImage?> _downloadCover(
    BookSource source,
    OnlineBook book,
  ) async {
    final coverUrl = book.coverUrl.trim();
    final bytes = await loadCover(source, coverUrl, referer: book.bookUrl);
    if (bytes == null) return null;
    final type = _imageType(bytes);
    if (type == null) return null;
    return OnlineEpubImage(
      path: 'images/cover.${type.extension}',
      bytes: bytes,
      mediaType: type.mediaType,
    );
  }

  Future<_PreparedContent> _prepareContentImages(
    BookSource source,
    String html,
    String pageUrl,
    Map<String, OnlineEpubImage> images,
    int initialBytes,
  ) async {
    if (html.trim().isEmpty) {
      return _PreparedContent(html: '', totalBytes: initialBytes);
    }
    final document = rules.parseHtml(html);
    final fragment = document.body ?? document.documentElement;
    if (fragment == null) {
      return _PreparedContent(html: '', totalBytes: initialBytes);
    }
    var totalBytes = initialBytes;
    final downloads = <String>[];
    for (final image in fragment.querySelectorAll('img')) {
      final raw = (image.attributes['data-src'] ?? '')
          .trim()
          .ifBlank((image.attributes['data-original'] ?? '').trim())
          .ifBlank((image.attributes['src'] ?? '').trim());
      final absolute = rules.resolveUrl(pageUrl, raw);
      if (absolute.isEmpty || absolute.startsWith('data:')) {
        if (absolute.isEmpty) image.remove();
        continue;
      }
      image.attributes['src'] = absolute;
      final cached = images[absolute];
      if (cached != null) {
        image.attributes['src'] = '../${cached.path}';
        continue;
      }
      if (downloads.contains(absolute) ||
          downloads.length >= 80 ||
          totalBytes >= 32 * 1024 * 1024) {
        image.remove();
        continue;
      }
      downloads.add(absolute);
      try {
        final response = await http.fetchBytes(
          source,
          absolute,
          referer: pageUrl,
        );
        if (response.bytes.isEmpty ||
            response.bytes.length > 8 * 1024 * 1024 ||
            totalBytes + response.bytes.length > 32 * 1024 * 1024) {
          image.remove();
          continue;
        }
        final type = _imageType(response.bytes);
        if (type == null) {
          image.remove();
          continue;
        }
        final digest = sha256
            .convert(response.bytes)
            .toString()
            .substring(0, 16);
        final path = 'images/$digest.${type.extension}';
        final asset = OnlineEpubImage(
          path: path,
          bytes: response.bytes,
          mediaType: type.mediaType,
        );
        images[absolute] = asset;
        totalBytes += response.bytes.length;
        image.attributes['src'] = '../$path';
      } on Object {
        image.remove();
      }
    }
    return _PreparedContent(
      html: fragment.nodes
          .map((node) => node is Element ? node.outerHtml : node.text)
          .join(),
      totalBytes: totalBytes,
    );
  }

  String _searchUrl(
    BookSource source,
    String query,
    int page, [
    BookSourceScriptSession? script,
    String? requestUrl,
  ]) {
    final encoded = Uri.encodeQueryComponent(query);
    final searchUrl = (requestUrl ?? source.searchUrl).trim();
    if (searchUrl.toLowerCase().startsWith('@js:')) {
      if (script == null) {
        throw const BookSourceException('该书源的搜索地址依赖 JS，当前版本暂不支持');
      }
      final body = searchUrl
          .substring(4)
          .replaceAllMapped(
            RegExp(r'\{\{\s*\(\s*page\s*-\s*1\s*\)\s*\*\s*10\s*\}\}'),
            (_) => '${(page - 1) * 10}',
          );
      final prepared = body
          .replaceAll('{{page}}', '$page')
          .replaceAll('{{searchPage}}', '$page')
          .replaceAll('{{key}}', encoded)
          .replaceAll('{{keyword}}', encoded)
          .replaceAll('{{searchKey}}', encoded);
      final result = script
          .evaluate(
            prepared,
            result: '',
            variables: <String, String>{
              'key': query,
              'keyword': query,
              'searchKey': query,
              'page': '$page',
              'searchPage': '$page',
              'baseUrl': source.baseUrl,
            },
            resolveString: (_) => '',
            resolveList: (_) => const <String>[],
          )
          .trim();
      if (!_isHttpUrl(result)) {
        throw const BookSourceException('书源搜索地址无效');
      }
      return result;
    }
    var template = searchUrl.replaceAllMapped(
      RegExp(r'\{\{\s*\(\s*page\s*-\s*1\s*\)\s*\*\s*10\s*\}\}'),
      (_) => '${(page - 1) * 10}',
    );
    template = template
        .replaceAll('{{page}}', '$page')
        .replaceAll('{{searchPage}}', '$page');
    template = template.replaceAllMapped(
      RegExp(r'''\{\{\s*baseUrl\s*\+\s*['"]([^'"]*)['"]\s*\}\}'''),
      (match) =>
          '${source.baseUrl.replaceFirst(RegExp(r'/+$'), '')}'
          '${match.group(1)}',
    );
    template = template.replaceAll('{{baseUrl}}', source.baseUrl);
    for (final token in const <String>[
      '{{key}}',
      '{{keyword}}',
      '{{searchKey}}',
      '{key}',
      '{keyword}',
      '%s',
    ]) {
      template = template.replaceAll(
        RegExp(RegExp.escape(token), caseSensitive: false),
        encoded,
      );
    }
    template = template.replaceAll(RegExp(r'\{\{[^{}]+\}\}'), '');
    if (template.startsWith(r'$') ||
        template.startsWith('@js:') ||
        template.contains('<js>')) {
      throw const BookSourceException('该书源的搜索地址依赖 JS，当前版本暂不支持');
    }
    template = _resolveTemplate(template, source.baseUrl);
    if (!_isHttpUrl(template)) {
      throw const BookSourceException('书源搜索地址无效');
    }
    return template;
  }

  String _resolveTemplate(String template, String baseUrl) {
    if (_isHttpUrl(template)) return template;
    final base = Uri.tryParse(baseUrl);
    if (base == null) return template;
    try {
      return base.resolve(template).toString();
    } on FormatException {
      return template;
    }
  }

  Object? _parseBody(String body) {
    final text = body.trim();
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        return jsonDecode(text);
      } on FormatException {
        // JSON 失败时按 HTML 继续，兼容 JSON 外层的广告文本。
      }
    }
    return rules.parseHtml(body);
  }

  String _field(
    Object? node,
    String rule,
    BookSourceRuleContext context, [
    BookSourceScriptSession? script,
    bool preserveNewlines = false,
  ]) {
    if (rule.trim().isEmpty) return '';
    return rules
        .evaluateString(
          node,
          rule,
          context,
          script: script,
          preserveNewlines: preserveNewlines,
        )
        .trim();
  }

  ({String url, Map<String, Object?> options}) _urlField(
    Object? node,
    String rule,
    BookSourceRuleContext context, [
    BookSourceScriptSession? script,
  ]) {
    return splitBookSourceUrlOptions(_field(node, rule, context, script));
  }

  List<({String url, Map<String, Object?> options})> _urlRequests(
    Object? node,
    String rule,
    BookSourceRuleContext context, [
    BookSourceScriptSession? script,
  ]) {
    final raw = _field(node, rule, context, script);
    if (raw.isEmpty) {
      return const <({String url, Map<String, Object?> options})>[];
    }
    return <({String url, Map<String, Object?> options})>[
      for (final line in raw.split(RegExp(r'[\r\n]+')))
        if (line.trim().isNotEmpty) splitBookSourceUrlOptions(line),
    ];
  }

  void _recordSkipped(List<String> reasons, String title, Object? failure) {
    if (reasons.length >= 20) return;
    final name = title.trim().isEmpty ? '未命名章节' : title.trim();
    final rawReason = switch (failure) {
      BookSourceException(:final message) => message,
      null => '未知错误',
      _ => '$failure',
    };
    final detail = rawReason
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .ifBlank('未知错误');
    final limitedDetail = detail.length <= 160
        ? detail
        : '${detail.substring(0, 160)}…';
    reasons.add('$name：$limitedDetail');
  }

  String _commonJsonField(Object? node, List<String> names) {
    if (node is! Map) return '';
    for (final name in names) {
      final value = node[name];
      if (value == null) continue;
      final text = '$value'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  List<OnlineBook> _fallbackHtmlSearch(
    BookSource source,
    Document document,
    String query,
    String pageUrl,
  ) {
    final lowerQuery = query.toLowerCase();
    final books = <OnlineBook>[];
    final seen = <String>{};
    for (final link in document.querySelectorAll('a[href]')) {
      final name = link.text.trim();
      if (name.isEmpty || name.length > 120) continue;
      if (!name.toLowerCase().contains(lowerQuery) && books.length >= 3) {
        continue;
      }
      final href = link.attributes['href']?.trim() ?? '';
      final absolute = rules.resolveUrl(pageUrl, href);
      if (absolute.isEmpty || !seen.add(absolute)) continue;
      final parent = link.parent;
      final container = parent?.parent ?? parent;
      final author =
          container?.querySelector('.author,[class*=author]')?.text.trim() ??
          '';
      final cover =
          container?.querySelector('img')?.attributes['src']?.trim() ?? '';
      books.add(
        OnlineBook(
          sourceId: source.id,
          sourceName: source.name,
          name: name,
          author: author,
          bookUrl: absolute,
          tocUrl: absolute,
          coverUrl: rules.resolveUrl(pageUrl, cover),
        ),
      );
      if (books.length >= 50) break;
    }
    return books;
  }

  void _checkCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() == true) {
      throw const BookSourceException('已取消', code: 'ONLINE_CANCELLED');
    }
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.hasAuthority;
  }

  _ImageType? _imageType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return const _ImageType('jpg', 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return const _ImageType('png', 'image/png');
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return const _ImageType('webp', 'image/webp');
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return const _ImageType('gif', 'image/gif');
    }
    return null;
  }
}

class _PreparedContent {
  const _PreparedContent({required this.html, required this.totalBytes});

  final String html;
  final int totalBytes;
}

class _ImageType {
  const _ImageType(this.extension, this.mediaType);

  final String extension;
  final String mediaType;
}

extension _BlankString on String {
  bool get isNotBlank => trim().isNotEmpty;

  String ifBlank(String fallback) => trim().isEmpty ? fallback : this;
}
