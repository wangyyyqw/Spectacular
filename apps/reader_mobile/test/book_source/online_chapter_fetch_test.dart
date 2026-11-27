import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';
import 'package:reader_mobile/book_source/online_chapter_content_store.dart';
import 'package:reader_mobile/book_source/online_chapter_request.dart';

import 'book_source_test_helpers.dart';

const _book = OnlineBook(
  sourceId: 'chapter-source',
  sourceName: '逐章测试源',
  name: '逐章测试书',
  author: '测试作者',
  bookUrl: 'https://example.test/book',
  tocUrl: 'https://example.test/toc',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('online-chapter-fetch-');
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('请求身份规范化地址片段和嵌套字段顺序，保留查询与请求正文', () {
    final first = onlineRequestIdentity(
      'https://EXAMPLE.test/read/../read/1?id=1#title',
      {
        'method': 'POST',
        'body': 'chapter=1',
        'headers': {'B': '2', 'A': '1'},
        'extra': [
          {'b': 2, 'a': 1},
          '末项',
        ],
      },
    );
    final reordered = {
      'extra': [
        {'a': 1, 'b': 2},
        '末项',
      ],
      'headers': {'A': '1', 'B': '2'},
      'body': 'chapter=1',
      'method': 'POST',
    };
    expect(
      onlineRequestIdentity('https://example.test/read/1?id=1', reordered),
      first,
    );
    expect(
      onlineRequestIdentity('https://example.test/read/1?id=2', reordered),
      isNot(first),
    );
    expect(
      onlineRequestIdentity('https://example.test/read/1?id=1', {
        ...reordered,
        'body': 'chapter=2',
      }),
      isNot(first),
    );
  });

  test('旧目录 data 选项与新目录身份一致，正文中的片段字符不被丢弃', () {
    const url = 'data:;base64,NzYwMDc4MzAzOTAwOTkxNTQxNw==';
    expect(
      onlineRequestIdentity('$url,{"type":"novel"}', const {}),
      onlineRequestIdentity(url, const {'type': 'novel'}),
    );
    expect(
      onlineRequestIdentity('$url,{"type":"novel"}', const {'type': 'comic'}),
      onlineRequestIdentity(url, const {'type': 'comic'}),
    );
    expect(
      onlineRequestIdentity('data:text/plain,正文#第一段', const {}),
      isNot(onlineRequestIdentity('data:text/plain,正文#第二段', const {})),
    );
  });

  test('正文分页跳过重复候选并保留剩余页，相对下一章和重定向不混入正文', () async {
    final requested = <String>[];
    final service = _service(directory, (request) async {
      requested.add(
        request.url.path +
            (request.url.hasQuery ? '?${request.url.query}' : ''),
      );
      if (request.url.path == '/next-alias') {
        return http.Response('', 302, headers: {'location': '/read/2'});
      }
      if (request.url.path == '/read/2') {
        return _json({'content': '<p>下一章正文不能合并进当前章。</p>'});
      }
      final page = request.url.queryParameters['page'] ?? '1';
      return _json({
        'content': '<p>当前章第$page页的正常正文。</p>',
        'next': switch (page) {
          '1' => [
            '/read/1#重复',
            '1?page=2',
            '/next-alias',
            '/read/2#章首',
            '1?page=2#重复',
          ],
          '2' => ['1?page=2', '1?page=3'],
          _ => ['/read/1#循环'],
        },
      });
    });

    final content = await service.fetchChapterContent(
      _source(),
      _chapter(0, '/read/1'),
      _book.bookUrl,
      nextChapterUrl: '../read/2#章首',
    );
    expect(content, contains('第1页'));
    expect(content, contains('第2页'));
    expect(content, contains('第3页'));
    expect(content, isNot(contains('下一章正文')));
    expect(requested, [
      '/read/1',
      '/read/1?page=2',
      '/next-alias',
      '/read/2',
      '/read/1?page=3',
    ]);
  });

  test('正文脚本能读取规范化下一章地址，末章提供空边界', () async {
    final boundaries = <String?>[];
    final service = _service(
      directory,
      (_) async => _json({'content': '脚本原文'}),
      scriptFactory: (_) =>
          FakeBookSourceScriptSession((code, result, variables, session) {
            boundaries.add(variables['nextChapterUrl']);
            return '<p>脚本处理后可阅读的正常正文。</p>';
          }),
    );
    final source = _source(contentRule: '<js>result</js>', nextRule: '');
    final chapter = _chapter(0, '/read/1');
    await service.fetchChapterContent(
      source,
      chapter,
      _book.bookUrl,
      nextChapterUrl: './2#章首',
    );
    await service.fetchChapterContent(source, chapter, _book.bookUrl);
    expect(boundaries, ['https://example.test/read/2', '']);
  });

  test('有正文地址的卷首返回空正文时回退到卷标题', () async {
    final service = _service(directory, (_) async => _json({'content': ''}));
    const chapter = OnlineChapter(
      index: 0,
      title: '第二卷',
      volume: '第二卷',
      url: 'https://example.test/foreword',
    );

    final content = await service.fetchChapterContent(
      _source(),
      chapter,
      _book.bookUrl,
    );

    expect(content, contains('第二卷'));
  });

  test('同一 POST 接口的目录页和章节正文按请求选项区分，下一章不会误判当前章', () async {
    final tocBodies = <String>[];
    final contentBodies = <String>[];
    const firstOptions = {
      'method': 'POST',
      'body': 'chapter=1',
      'headers': {'B': '2', 'A': '1'},
    };
    const secondOptions = {'method': 'POST', 'body': 'chapter=2'};
    final service = _service(directory, (request) async {
      if (request.url.path == '/toc') {
        tocBodies.add(request.body);
        return _json(switch (request.body) {
          '' => {
            'chapters': [
              {'title': '第一章', 'url': _requestUrl('/content', firstOptions)},
              {
                'title': '第一章重复',
                'url': _requestUrl('/content', {
                  'headers': {'A': '1', 'B': '2'},
                  'body': 'chapter=1',
                  'method': 'POST',
                }),
              },
            ],
            'next': [
              _requestUrl('/toc', {'method': 'POST', 'body': 'page=2'}),
            ],
          },
          'page=2' => {
            'chapters': [
              {'title': '第二章', 'url': _requestUrl('/content', secondOptions)},
            ],
            'next': [
              _requestUrl('/toc', {'method': 'POST', 'body': 'page=2'}),
              _requestUrl('/toc', {'method': 'POST', 'body': 'page=3'}),
            ],
          },
          _ => {
            'chapters': [
              {'title': '第三章', 'url': '/3'},
            ],
          },
        });
      }
      contentBodies.add(request.body);
      return _json(switch (request.body) {
        'chapter=1' => {
          'content': '<p>第一章首页的正常正文。</p>',
          'next': [
            _requestUrl('/content', {
              'method': 'POST',
              'body': 'chapter=1&page=2',
            }),
            _requestUrl('/content', secondOptions),
          ],
        },
        'chapter=1&page=2' => {
          'content': '<p>第一章第二页的正常正文。</p>',
          'next': [
            _requestUrl('/content', firstOptions),
            _requestUrl('/content', secondOptions),
          ],
        },
        _ => {'content': '<p>第二章独立的正常正文。</p>'},
      });
    });
    final source = _source();
    final chapters = await service.fetchToc(source, _book);
    expect(chapters.map((chapter) => chapter.title), ['第一章', '第二章', '第三章']);
    expect(tocBodies, ['', 'page=2', 'page=3']);
    expect(chapters[0].url, chapters[1].url);
    expect(
      onlineChapterIdentity(chapters[0]),
      isNot(onlineChapterIdentity(chapters[1])),
    );
    final first = await service.fetchChapterContent(
      source,
      chapters[0],
      _book.bookUrl,
      nextChapter: chapters[1],
    );
    expect(first, contains('第一章首页'));
    expect(first, contains('第一章第二页'));
    expect(first, isNot(contains('第二章独立')));
    final second = await service.fetchChapterContent(
      source,
      chapters[1],
      _book.bookUrl,
      nextChapter: chapters[2],
    );
    expect(second, contains('第二章独立'));
    expect(contentBodies, ['chapter=1', 'chapter=1&page=2', 'chapter=2']);
  });

  test('正文分页超过上限报错，未缓存截断正文且可重新加载', () async {
    var runaway = true;
    var requests = 0;
    final service = _service(directory, (request) async {
      requests += 1;
      final page = int.parse(request.url.queryParameters['page']!);
      return _json({
        'content': '<p>长章第$page页可阅读的正常正文。</p>',
        if (runaway) 'next': ['?page=${page + 1}'],
      });
    });
    final source = _source();
    final chapter = _chapter(0, '/long?page=1');
    await expectLater(
      service.fetchChapterContent(source, chapter, _book.bookUrl),
      throwsA(
        isA<BookSourceException>().having(
          (error) => error.code,
          '错误码',
          'ONLINE_CONTENT_PAGE_LIMIT',
        ),
      ),
    );
    expect(requests, BookSourceService.maxChapterContentPages);
    expect(
      await service.chapterContentStore.read(
        sourceId: source.id,
        bookUrl: _book.bookUrl,
        chapterUrl: chapter.url,
        rulesFingerprint: service.chapterContentRevision(source, chapter),
      ),
      isNull,
    );
    runaway = false;
    expect(
      await service.fetchChapterContent(source, chapter, _book.bookUrl),
      contains('长章第1页'),
    );
    await service.fetchChapterContent(source, chapter, _book.bookUrl);
    expect(requests, BookSourceService.maxChapterContentPages + 1);
  });

  test('目录分页超过上限报错，不返回残缺目录', () async {
    var requests = 0;
    final service = _service(directory, (request) async {
      requests += 1;
      final page = int.parse(request.url.queryParameters['page'] ?? '1');
      return _json({
        'chapters': [
          {'title': '第$page章', 'url': '/chapter/$page'},
        ],
        'next': ['?page=${page + 1}'],
      });
    });
    await expectLater(
      service.fetchToc(_source(), _book),
      throwsA(
        isA<BookSourceException>().having(
          (error) => error.code,
          '错误码',
          'ONLINE_TOC_PAGE_LIMIT',
        ),
      ),
    );
    expect(requests, 30);
  });

  test('新正文规则版本隔离之前可能混章的磁盘缓存', () async {
    var requests = 0;
    final service = _service(directory, (_) async {
      requests += 1;
      return _json({'content': '<p>重新获取后属于本章的正常正文。</p>'});
    });
    final source = _source();
    final chapter = _chapter(0, '/1');
    String digest(Object value) =>
        sha256.convert(utf8.encode(jsonEncode(value))).toString();
    final legacyRules = digest({
      'version': 2,
      'base': source.baseUrl,
      'headers': source.header,
      'jsLib': source.jsLib,
      'content': source.content.content,
      'next': source.content.nextContentUrl,
      'replace': source.content.replaceRegex,
      'source': source.content.sourceRegex,
    });
    await service.chapterContentStore.write(
      sourceId: source.id,
      bookUrl: _book.bookUrl,
      chapterUrl: chapter.url,
      rulesFingerprint: digest([
        legacyRules,
        chapter.title,
        chapter.updateTime,
        chapter.requestOptions,
      ]),
      content: '<p>原章正文以及误合并的下一章正文。</p>',
    );
    final content = await service.fetchChapterContent(
      source,
      chapter,
      _book.bookUrl,
    );
    expect(content, contains('属于本章'));
    expect(content, isNot(contains('误合并')));
    expect(requests, 1);
  });

  test('普通加载共用正在强刷的结果，旧响应晚结束不能覆盖新缓存', () async {
    final oldResponse = Completer<http.Response>();
    final freshResponse = Completer<http.Response>();
    final oldStarted = Completer<void>();
    final freshStarted = Completer<void>();
    var requests = 0;
    final service = _service(directory, (_) {
      requests += 1;
      if (requests == 1) {
        oldStarted.complete();
        return oldResponse.future;
      }
      freshStarted.complete();
      return freshResponse.future;
    });
    final source = _source();
    final chapter = _chapter(0, '/1');
    final old = service.fetchChapterContent(source, chapter, _book.bookUrl);
    await oldStarted.future;
    final fresh = service.fetchChapterContent(
      source,
      chapter,
      _book.bookUrl,
      forceRefresh: true,
    );
    await freshStarted.future;
    final repeatedRefresh = service.fetchChapterContent(
      source,
      chapter,
      _book.bookUrl,
      forceRefresh: true,
    );
    final shared = service.fetchChapterContent(source, chapter, _book.bookUrl);
    freshResponse.complete(_json({'content': '<p>强刷后的最新正常正文。</p>'}));
    for (final task in [fresh, repeatedRefresh, shared]) {
      expect(await task, contains('最新正常正文'));
    }
    oldResponse.complete(_json({'content': '<p>晚结束的旧版正常正文。</p>'}));
    expect(await old, contains('旧版正常正文'));
    expect(
      await service.fetchChapterContent(source, chapter, _book.bookUrl),
      contains('最新正常正文'),
    );
    expect(requests, 2);
  });

  test('旧缓存写入已开始时同键强刷串行写入，最终保留最新正文', () async {
    final store = _BlockingChapterStore(directory);
    var requests = 0;
    final freshStarted = Completer<void>();
    final service = _service(directory, (_) async {
      requests += 1;
      if (requests == 2) freshStarted.complete();
      return _json({
        'content': requests == 1
            ? '<p>普通加载得到的旧版正常正文。</p>'
            : '<p>强刷得到的最新正常正文。</p>',
      });
    }, store: store);
    final source = _source();
    final chapter = _chapter(0, '/1');
    final old = service.fetchChapterContent(source, chapter, _book.bookUrl);
    await store.firstWrite.future;
    final fresh = service.fetchChapterContent(
      source,
      chapter,
      _book.bookUrl,
      forceRefresh: true,
    );
    await freshStarted.future;
    final shared = service.fetchChapterContent(source, chapter, _book.bookUrl);
    store.releaseWrite.complete();
    await old;
    expect(await fresh, contains('最新正常正文'));
    expect(await shared, contains('最新正常正文'));
    expect(
      await service.fetchChapterContent(source, chapter, _book.bookUrl),
      contains('最新正常正文'),
    );
    expect(requests, 2);
  });

  test('强刷失败保留原正文缓存，后续普通加载可离线回退', () async {
    var requests = 0;
    final service = _service(directory, (_) async {
      requests += 1;
      return requests == 1
          ? _json({'content': '<p>此前已保存的正常正文。</p>'})
          : http.Response('', 503);
    });
    final source = _source();
    final chapter = _chapter(0, '/1');
    await service.fetchChapterContent(source, chapter, _book.bookUrl);
    await expectLater(
      service.fetchChapterContent(
        source,
        chapter,
        _book.bookUrl,
        forceRefresh: true,
      ),
      throwsA(isA<BookSourceException>()),
    );
    expect(
      await service.fetchChapterContent(source, chapter, _book.bookUrl),
      contains('此前已保存'),
    );
    expect(requests, 2);
  });

  test('子集下载使用完整目录的相邻章边界，不把未选中的下一章并入正文', () async {
    final requested = <String>[];
    final service = _service(directory, (request) async {
      requested.add(request.url.path);
      return _json({
        'content': '<p>第${request.url.path.substring(1)}章独立的正常正文。</p>',
        if (request.url.path == '/1') 'next': ['/2'],
      });
    });
    final chapters = [_chapter(0, '/1'), _chapter(1, '/2'), _chapter(2, '/3')];
    final result = await service.download(
      _source(),
      _book,
      preparedBook: _book.copyWith(coverUrl: 'https://example.test/cover.png'),
      selectedChapters: [chapters[0], chapters[2]],
      chapterDirectory: chapters,
    );
    expect(requested, ['/1', '/3']);
    expect(result.skippedChapters, 0);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final first = utf8.decode(
      archive.findFile('OEBPS/text/chapter_0001.xhtml')!.content,
    );
    final second = utf8.decode(
      archive.findFile('OEBPS/text/chapter_0002.xhtml')!.content,
    );
    expect(first, contains('第1章独立'));
    expect(first, isNot(contains('第2章独立')));
    expect(second, contains('第3章独立'));
  });

  test('整本转换复用目录并嵌入封面、远程插图和内嵌图，不重复请求目录', () async {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==';
    final requests = <String>[];
    final service = _service(directory, (request) async {
      requests.add(request.url.path);
      return request.url.path.endsWith('.png')
          ? http.Response.bytes(base64Decode(png), 200)
          : _json({
              'content':
                    '<p>一段正文和两幅插图。</p><img src="/inline.png"/><img data-original="data:image/png;base64,$png"/>',
            });
    });
    final result = await service.download(
      _source(),
      _book,
      preparedBook: _book.copyWith(coverUrl: 'https://example.test/cover.png'),
      chapterDirectory: [_chapter(0, '/1')],
    );
    expect(requests, ['/cover.png', '/1', '/inline.png']);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    expect(
      archive.findFile('OEBPS/Images/cover.png')!.content,
      base64Decode(png),
    );
    final illustration = archive.files.singleWhere(
      (entry) =>
          entry.name.startsWith('OEBPS/Images/') &&
          !entry.name.endsWith('/cover.png'),
    );
    final html = utf8.decode(
      archive.findFile('OEBPS/text/chapter_0001.xhtml')!.content,
    );
    expect(
      '../${illustration.name.substring(6)}'.allMatches(html),
      hasLength(2),
    );
    expect(html, isNot(contains('data:image')));
  });
}

BookSource _source({
  String contentRule = r'$.content',
  String nextRule = r'$.next[*]',
}) => BookSource(
  id: 'chapter-source',
  name: '逐章测试源',
  sourceUrl: 'https://example.test',
  searchUrl: 'https://example.test/search',
  search: const BookListRule(),
  bookInfo: const BookInfoRule(),
  toc: const TocRule(
    chapterList: r'$.chapters[*]',
    chapterName: r'$.title',
    chapterUrl: r'$.url',
    nextTocUrl: r'$.next[*]',
  ),
  content: ContentRule(content: contentRule, nextContentUrl: nextRule),
);

OnlineChapter _chapter(int index, String url) => OnlineChapter(
  index: index,
  title: '第${index + 1}章',
  url: Uri.parse(_book.bookUrl).resolve(url).toString(),
);

String _requestUrl(String url, Map<String, Object?> options) =>
    '$url,${jsonEncode(options)}';

http.Response _json(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

BookSourceService _service(
  Directory directory,
  Future<http.Response> Function(http.Request) handler, {
  OnlineChapterContentStore? store,
  BookSourceScriptFactory? scriptFactory,
}) {
  final cookies = BookSourceCookieStore(
    directoryProvider: () async => directory,
  );
  final service = BookSourceService(
    cookieStore: cookies,
    chapterContentStore:
        store ??
        OnlineChapterContentStore(directoryProvider: () async => directory),
    httpClient: BookSourceHttpClient(
      cookieStore: cookies,
      client: MockClient(handler),
    ),
    scriptFactory:
        scriptFactory ??
        (_) => FakeBookSourceScriptSession(
          (code, result, variables, session) => result,
        ),
  );
  addTearDown(service.dispose);
  return service;
}

class _BlockingChapterStore extends OnlineChapterContentStore {
  _BlockingChapterStore(Directory directory)
    : super(directoryProvider: () async => directory);

  final firstWrite = Completer<void>();
  final releaseWrite = Completer<void>();
  int _writes = 0;

  @override
  Future<void> write({
    required String sourceId,
    required String bookUrl,
    required String chapterUrl,
    required String rulesFingerprint,
    required String content,
  }) async {
    if (++_writes == 1) {
      firstWrite.complete();
      await releaseWrite.future;
    }
    await super.write(
      sourceId: sourceId,
      bookUrl: bookUrl,
      chapterUrl: chapterUrl,
      rulesFingerprint: rulesFingerprint,
      content: content,
    );
  }
}
