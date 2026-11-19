import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart';

import 'book_source_compat.dart';
import 'book_source_http_client.dart';
import 'book_source_models.dart';
import 'book_source_rule_engine.dart';
import 'online_epub_builder.dart';

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

/// 执行书源搜索、详情、目录、正文与 EPUB 下载。
class BookSourceService {
  BookSourceService({
    BookSourceHttpClient? httpClient,
    BookSourceRuleEngine ruleEngine = const BookSourceRuleEngine(),
    this.epubBuilder = const OnlineEpubBuilder(),
  }) : http = httpClient ?? BookSourceHttpClient(),
       rules = ruleEngine;

  final BookSourceHttpClient http;
  final BookSourceRuleEngine rules;
  final OnlineEpubBuilder epubBuilder;
  final Map<String, Future<Uint8List?>> _coverCache =
      <String, Future<Uint8List?>>{};

  void dispose() => http.close();

  /// 并发搜索多个来源；单个失败不影响其他来源。
  Future<List<OnlineSourceSearchResult>> searchMany(
    List<BookSource> sources,
    String query, {
    int concurrency = 3,
  }) async {
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

  /// 搜索单个来源。
  Future<List<OnlineBook>> search(
    BookSource source,
    String rawQuery, {
    int page = 1,
  }) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      throw const BookSourceException('请输入要搜索的书名或作者');
    }
    if (!source.canSearch) {
      throw const BookSourceException('该书源未启用或不支持搜索');
    }
    final url = _searchUrl(source, query, page);
    final response = await http.fetchText(
      source,
      url,
      options: source.searchOptions,
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
    var nodes = rules.evaluateList(root, source.search.bookList, context);
    if (nodes.isEmpty && root is List) {
      nodes = root.whereType<Object>().toList();
    }
    if (nodes.isEmpty && root is Document) {
      return _fallbackHtmlSearch(source, root, query, response.uri.toString());
    }

    final books = <OnlineBook>[];
    final seen = <String>{};
    for (final node in nodes) {
      final name = _field(node, source.search.name, context).ifBlank(
        _commonJsonField(node, const <String>['name', 'title', 'bookName']),
      );
      if (name.isEmpty) continue;
      final bookUrlRule = _field(node, source.search.bookUrl, context);
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
        source.search.author,
        context,
      ).ifBlank(_commonJsonField(node, const <String>['author', 'writer']));
      final cover = _field(node, source.search.coverUrl, context).ifBlank(
        _commonJsonField(node, const <String>[
          'coverUrl',
          'cover',
          'picUrl',
          'imageUrl',
        ]),
      );
      final lastChapter = _field(node, source.search.lastChapter, context)
          .ifBlank(
            _commonJsonField(node, const <String>[
              'lastChapter',
              'latestChapter',
              'last_chapter',
            ]),
          );
      final kindRaw = _field(node, source.search.kind, context).ifBlank(
        _commonJsonField(node, const <String>[
          'kind',
          'category',
          'status',
          'bookStatus',
        ]),
      );
      final status = normalizeOnlineStatus(kindRaw, lastChapter: lastChapter);
      final rawWordCount = _field(node, source.search.wordCount, context)
          .ifBlank(
            _commonJsonField(node, const <String>[
              'wordCount',
              'words',
              'word_count',
            ]),
          );
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
        intro: _field(node, source.search.intro, context).ifBlank(
          _commonJsonField(node, const <String>[
            'intro',
            'description',
            'desc',
          ]),
        ),
        kind: status.ifBlank(kindRaw),
        wordCount: normalizeOnlineWordCount(rawWordCount),
        lastChapter: lastChapter,
      );
      final identity = '${book.name}|${book.author}|${book.bookUrl}';
      if (!seen.add(identity)) continue;
      books.add(book);
    }
    return books;
  }

  /// 读取详情页字段并定位目录地址。
  Future<OnlineBook> loadBookInfo(BookSource source, OnlineBook book) async {
    final response = await http.fetchText(
      source,
      book.bookUrl,
      options: book.bookOptions,
      referer: source.baseUrl,
    );
    final root = _parseBody(response.body);
    final context = BookSourceRuleContext(
      baseUrl: source.baseUrl,
      pageUrl: response.uri.toString(),
      variables: <String, String>{'bookUrl': book.bookUrl},
    );
    final name = _field(root, source.bookInfo.name, context).ifBlank(book.name);
    final author = _field(
      root,
      source.bookInfo.author,
      context,
    ).ifBlank(book.author);
    final tocRequest = _urlField(root, source.bookInfo.tocUrl, context);
    final coverRequest = _urlField(root, source.bookInfo.coverUrl, context);
    final lastChapter = _field(
      root,
      source.bookInfo.lastChapter,
      context,
    ).ifBlank(book.lastChapter);
    final kindRaw = _field(
      root,
      source.bookInfo.kind,
      context,
    ).ifBlank(book.kind);
    final status = normalizeOnlineStatus(kindRaw, lastChapter: lastChapter);
    final wordCount = _field(
      root,
      source.bookInfo.wordCount,
      context,
    ).ifBlank(book.wordCount);
    return book.copyWith(
      name: name,
      author: author,
      tocUrl: rules
          .resolveUrl(response.uri.toString(), tocRequest.url)
          .ifBlank(book.tocUrl.ifBlank(book.bookUrl)),
      tocOptions: tocRequest.url.isEmpty ? book.tocOptions : tocRequest.options,
      coverUrl: rules
          .resolveUrl(response.uri.toString(), coverRequest.url)
          .ifBlank(book.coverUrl),
      intro: _field(root, source.bookInfo.intro, context).ifBlank(book.intro),
      kind: status.ifBlank(kindRaw),
      wordCount: normalizeOnlineWordCount(wordCount),
      lastChapter: lastChapter,
    );
  }

  /// 读取目录，并跟随 `nextTocUrl` 合并后续页。
  Future<List<OnlineChapter>> fetchToc(
    BookSource source,
    OnlineBook book,
  ) async {
    var currentUrl = book.tocUrl.isNotBlank ? book.tocUrl : book.bookUrl;
    var currentOptions = book.tocOptions;
    final pendingPages = <({String url, Map<String, Object?> options})>[];
    final chapters = <OnlineChapter>[];
    final seenUrls = <String>{};
    final seenPages = <String>{};
    while (currentUrl.isNotBlank) {
      if (!seenPages.add(currentUrl) || seenPages.length > 30) break;
      final response = await http.fetchText(
        source,
        currentUrl,
        options: currentOptions,
        referer: book.bookUrl,
      );
      final root = _parseBody(response.body);
      final context = BookSourceRuleContext(
        baseUrl: source.baseUrl,
        pageUrl: response.uri.toString(),
        variables: <String, String>{
          'bookUrl': book.bookUrl,
          'tocUrl': currentUrl,
        },
      );
      final nodes = rules.evaluateList(root, source.toc.chapterList, context);
      for (final node in nodes) {
        var name = _field(node, source.toc.chapterName, context);
        var chapterUrl = _field(node, source.toc.chapterUrl, context);
        if (node is Element) {
          final link = node.localName == 'a' ? node : node.querySelector('a');
          name = name.ifBlank(link?.text ?? node.text);
          chapterUrl = chapterUrl.ifBlank(link?.attributes['href'] ?? '');
        } else if (node is Map) {
          name = name.ifBlank(
            _commonJsonField(node, const <String>[
              'chapterName',
              'title',
              'name',
            ]),
          );
          chapterUrl = chapterUrl.ifBlank(
            _commonJsonField(node, const <String>['chapterUrl', 'url', 'link']),
          );
        }
        final chapterRequest = splitBookSourceUrlOptions(chapterUrl);
        final absolute = rules.resolveUrl(context.pageUrl, chapterRequest.url);
        name = cleanOnlineChapterTitle(name);
        if (name.isEmpty || absolute.isEmpty || !seenUrls.add(absolute)) {
          continue;
        }
        chapters.add(
          OnlineChapter(
            index: chapters.length,
            title: name,
            url: absolute,
            updateTime: _field(node, source.toc.updateTime, context),
            requestOptions: chapterRequest.options,
          ),
        );
      }
      final nextPages = _urlRequests(root, source.toc.nextTocUrl, context);
      for (final next in nextPages) {
        final resolved = rules.resolveUrl(response.uri.toString(), next.url);
        if (resolved.isNotEmpty) {
          pendingPages.add((url: resolved, options: next.options));
        }
      }
      if (pendingPages.isEmpty) break;
      final page = pendingPages.removeAt(0);
      currentUrl = page.url;
      currentOptions = page.options;
    }
    if (chapters.isEmpty) {
      throw const BookSourceException(
        '目录为空，可能是书源规则失效或站点限制',
        code: 'ONLINE_TOC_EMPTY',
      );
    }
    return chapters;
  }

  /// 下载完整书籍并生成 EPUB。
  Future<OnlineBookDownloadResult> download(
    BookSource source,
    OnlineBook searchBook, {
    OnlineDownloadProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call(0, 0, '正在读取详情');
    final info = await loadBookInfo(source, searchBook);
    _checkCancelled(isCancelled);
    onProgress?.call(0, 0, '正在读取目录');
    final toc = await fetchToc(source, info);
    _checkCancelled(isCancelled);

    final images = <String, OnlineEpubImage>{};
    var imageBytes = 0;
    final cover = await _downloadCover(source, info);
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
          content = await fetchChapterContent(source, chapter, info.bookUrl);
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
            OnlineEpubChapter(title: chapter.title, html: prepared.html),
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
    String bookUrl,
  ) async {
    var currentUrl = chapter.url;
    var currentOptions = chapter.requestOptions;
    final pendingPages = <({String url, Map<String, Object?> options})>[];
    final seen = <String>{};
    final htmlParts = <String>[];
    while (currentUrl.isNotBlank) {
      if (!seen.add(currentUrl) || seen.length > 8) break;
      final response = await http.fetchText(
        source,
        currentUrl,
        options: currentOptions,
        referer: bookUrl,
      );
      final root = _parseBody(response.body);
      final context = BookSourceRuleContext(
        baseUrl: source.baseUrl,
        pageUrl: response.uri.toString(),
        variables: <String, String>{
          'bookUrl': bookUrl,
          'chapterUrl': chapter.url,
          'title': chapter.title,
        },
      );
      final html = rules.evaluateHtml(root, source.content.content, context);
      if (html.trim().isNotEmpty) htmlParts.add(html.trim());
      final nextPages = _urlRequests(
        root,
        source.content.nextContentUrl,
        context,
      );
      for (final next in nextPages) {
        final resolved = rules.resolveUrl(response.uri.toString(), next.url);
        if (resolved.isNotEmpty) {
          pendingPages.add((url: resolved, options: next.options));
        }
      }
      if (pendingPages.isEmpty) break;
      final page = pendingPages.removeAt(0);
      currentUrl = page.url;
      currentOptions = page.options;
    }
    final content = cleanOnlineChapterContent(htmlParts.join('\n'));
    final reason = chapterContentFailureReason(content);
    if (reason != null) {
      throw BookSourceException(
        '章节正文无效：$reason',
        code: 'ONLINE_CONTENT_INVALID',
      );
    }
    return content;
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

  String _searchUrl(BookSource source, String query, int page) {
    final encoded = Uri.encodeQueryComponent(query);
    var template = source.searchUrl.replaceAllMapped(
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

  String _field(Object? node, String rule, BookSourceRuleContext context) {
    if (rule.trim().isEmpty) return '';
    return rules.evaluateString(node, rule, context).trim();
  }

  ({String url, Map<String, Object?> options}) _urlField(
    Object? node,
    String rule,
    BookSourceRuleContext context,
  ) {
    return splitBookSourceUrlOptions(_field(node, rule, context));
  }

  List<({String url, Map<String, Object?> options})> _urlRequests(
    Object? node,
    String rule,
    BookSourceRuleContext context,
  ) {
    final raw = _field(node, rule, context);
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
