import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_script.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';
import 'package:reader_mobile/book_source/online_chapter_content_store.dart';

import 'book_source_test_helpers.dart';

const _source = BookSource(
  id: 'source-1',
  name: '示例源',
  sourceUrl: 'https://example.com',
  searchUrl: 'https://example.com/search',
  search: BookListRule(),
  bookInfo: BookInfoRule(),
  toc: TocRule(),
  content: ContentRule(),
);

final _png = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
]);

class _DelayedChapterCache extends OnlineChapterContentStore {
  final started = Completer<void>();
  final completeWrite = Completer<void>();

  @override
  Future<String?> read({
    required String sourceId,
    required String bookUrl,
    required String chapterUrl,
    required String rulesFingerprint,
  }) async => null;

  @override
  Future<void> write({
    required String sourceId,
    required String bookUrl,
    required String chapterUrl,
    required String rulesFingerprint,
    required String content,
  }) async {
    started.complete();
    await completeWrite.future;
  }
}

void main() {
  test('逐章JSON卷名形成连续分卷，不丢章节或混用缺失卷名', () async {
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'item_data_list': [
                  {'title': '第一章', 'url': '/1', 'volume_name': '上卷'},
                  {'title': '第二章', 'url': '/2', 'volume_name': '上卷'},
                  {'title': '第三章', 'url': '/3', 'volumeName': '下卷'},
                  {'title': '附录', 'url': '/4'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );
    addTearDown(service.dispose);
    final source = _source.copyWith(
      toc: const TocRule(
        chapterList: r'$..data.item_data_list[*]',
        chapterName: r'$.title',
        chapterUrl: r'$.url',
      ),
    );
    final chapters = await service.fetchToc(
      source,
      const OnlineBook(
        sourceId: 'source-1',
        sourceName: '示例源',
        name: '分卷书',
        author: '',
        bookUrl: 'https://example.com/catalog',
      ),
    );
    expect(chapters.map((chapter) => chapter.volume), ['上卷', '上卷', '下卷', '']);
    expect(chapters.map((chapter) => chapter.url), [
      'https://example.com/1',
      'https://example.com/2',
      'https://example.com/3',
      'https://example.com/4',
    ]);
  });

  test('真实后台详情和下载保持前台计时器响应，慢网络下载可立即取消', () async {
    final directory = await Directory.systemTemp.createTemp('online-worker-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stopped = Completer<void>();
    server.listen((request) async {
      if (request.uri.path == '/slow') await stopped.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'name': '后台测试书',
          'intro': '后台简介',
          'toc': '/toc',
          'chapters': [
            {'name': '第一章', 'url': '/chapter', 'volume_name': '第一卷'},
          ],
          'content': '<p>后台正文。</p>',
        }),
      );
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    final source = _source.copyWith(
      sourceUrl: base,
      bookInfo: const BookInfoRule(
        name: r'$.name',
        intro: r'$.intro',
        tocUrl: r'$.toc',
      ),
      toc: const TocRule(
        chapterList: r'$.chapters[*]',
        chapterName: r'$.name',
        chapterUrl: r'$.url',
      ),
      content: const ContentRule(content: r'$.content'),
      loadMode: BookSourceLoadMode.book,
    );
    final service = BookSourceService(
      backgroundOperations: true,
      httpClient: BookSourceHttpClient(allowPrivateHosts: true),
      cookieStore: BookSourceCookieStore(
        directoryProvider: () async => directory,
      ),
      chapterContentStore: OnlineChapterContentStore(
        directoryProvider: () async => directory,
      ),
    );
    addTearDown(() async {
      if (!stopped.isCompleted) stopped.complete();
      service.dispose();
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    final book = OnlineBook(
      sourceId: source.id,
      sourceName: source.name,
      name: '测试',
      author: '',
      bookUrl: '$base/book',
    );
    final info = await service.loadBookInfo(source, book);
    expect(info.intro, '后台简介');
    final chapters = await service.fetchToc(source, info);
    expect(chapters.single.volume, '第一卷');
    final completed = await service.download(source, book);
    expect(completed.bytes, isNotEmpty);
    var cancelled = false;
    var ticks = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      ticks++;
      if (ticks == 5) cancelled = true;
    });
    try {
      await expectLater(
        service.download(
          source,
          book.copyWith(bookUrl: '$base/slow'),
          isCancelled: () => cancelled,
        ),
        throwsA(
          isA<BookSourceException>().having(
            (e) => e.code,
            '取消代码',
            'ONLINE_CANCELLED',
          ),
        ),
      );
      expect(ticks, greaterThanOrEqualTo(5));
    } finally {
      timer.cancel();
    }
  });
  test('清理章节缓存前等待完整写入，不因布局取消提前释放', () async {
    final cache = _DelayedChapterCache();
    final service = BookSourceService(
      chapterContentStore: cache,
      httpClient: BookSourceHttpClient(
        client: MockClient(
          (_) async => http.Response(
            '<p>缓存正文</p>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      ),
      scriptFactory: fakeScriptFactory(
        FakeBookSourceScriptSession(
          (code, result, variables, current) => result,
        ),
      ),
    );
    addTearDown(service.dispose);
    addTearDown(() {
      if (!cache.completeWrite.isCompleted) cache.completeWrite.complete();
    });
    final reading = service.fetchChapterContent(
      const BookSource(
        id: 'delayed-cache',
        name: '慢写入测试源',
        sourceUrl: 'https://example.com',
        searchUrl: '/search',
        search: BookListRule(),
        bookInfo: BookInfoRule(),
        toc: TocRule(),
        content: ContentRule(content: 'p'),
      ),
      const OnlineChapter(index: 0, title: '第一章', url: 'https://example.com/1'),
      'https://example.com/book',
    );
    await cache.started.future;
    var stopped = false;
    final pending = service.chapterRequestsStopped.then((_) => stopped = true);
    await Future<void>.value();
    expect(stopped, isFalse, reason: '正文已返回但文件还未写完');
    cache.completeWrite.complete();
    await pending;
    await reading;
    expect(stopped, isTrue);
    await service.chapterRequestsStopped;
  });

  test('搜索地址支持常用 Legado 模板变量', () async {
    late Uri requested;
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response('<html></html>', 200);
        }),
      ),
    );
    addTearDown(service.dispose);
    const source = BookSource(
      id: 'template-source',
      name: '模板源',
      sourceUrl: 'https://example.com',
      searchUrl:
          'https://example.com/search?q=%s&offset={{ (page - 1) * 10 }}'
          '&kw={{keyword}}&page={{page}}',
      search: BookListRule(bookList: '.book'),
      bookInfo: BookInfoRule(),
      toc: TocRule(),
      content: ContentRule(),
    );

    await service.search(source, 'a b', page: 2);

    expect(requested.queryParameters['q'], 'a b');
    expect(requested.queryParameters['kw'], 'a b');
    expect(requested.queryParameters['offset'], '10');
    expect(requested.queryParameters['page'], '2');
  });

  test('搜索规则兼容 data.ret_data 包裹', () async {
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'code': 0,
              'data': <String, Object?>{
                'ret_data': <Object?>[
                  <String, Object?>{
                    'book_id': '1001',
                    'book_name': '序列为零',
                    'author': '测试作者',
                  },
                ],
              },
            }),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      ),
    );
    addTearDown(service.dispose);
    const source = BookSource(
      id: 'nested-search-source',
      name: '包裹源',
      sourceUrl: 'https://example.com',
      searchUrl: 'https://example.com/search?q={{key}}',
      search: BookListRule(
        bookList: '.ret_data[*]||.data[0]',
        name: 'book_name||title',
        author: 'author',
        bookUrl: 'https://example.com/detail?book_id=1001',
      ),
      bookInfo: BookInfoRule(),
      toc: TocRule(),
      content: ContentRule(),
    );

    final books = await service.search(source, '序列为零');

    expect(books, hasLength(1));
    expect(books.single.name, '序列为零');
    expect(books.single.author, '测试作者');
    expect(books.single.bookUrl, 'https://example.com/detail?book_id=1001');
  });

  test('数字 ID 搜索兼容 data 为单本详情', () async {
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'code': 0,
              'data': <String, Object?>{
                'book_id': '2002',
                'book_name': '单本详情',
                'author': '乙',
              },
            }),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      ),
    );
    addTearDown(service.dispose);
    const source = BookSource(
      id: 'detail-search-source',
      name: '详情源',
      sourceUrl: 'https://example.com',
      searchUrl: 'https://example.com/detail?book_id={{key}}',
      search: BookListRule(
        bookList: '.ret_data[*]||.data[0]',
        name: 'book_name||title',
        author: 'author',
        bookUrl: 'https://example.com/detail?book_id=2002',
      ),
      bookInfo: BookInfoRule(),
      toc: TocRule(),
      content: ContentRule(),
    );

    final books = await service.search(source, '2002');

    expect(books, hasLength(1));
    expect(books.single.name, '单本详情');
    expect(books.single.author, '乙');
    expect(books.single.bookUrl, 'https://example.com/detail?book_id=2002');
  });

  test('搜索结果直接解析章节数与更新时间', () async {
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'ret_data': <Object?>[
                <String, Object?>{
                  'book_name': '标签书',
                  'author': '作者',
                  'book_url': 'https://example.com/book/1',
                  'word_number': 13000,
                  'chapter_count': 12,
                  'update_time': '2025-06-11',
                },
              ],
            }),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      ),
    );
    addTearDown(service.dispose);
    const source = BookSource(
      id: 'tag-search-source',
      name: '番茄小说',
      sourceUrl: 'https://example.com',
      searchUrl: 'https://example.com/search?q={{key}}',
      search: BookListRule(
        bookList: '.ret_data[*]',
        name: 'book_name',
        author: 'author',
        bookUrl: 'book_url',
      ),
      bookInfo: BookInfoRule(),
      toc: TocRule(),
      content: ContentRule(),
    );

    final books = await service.search(source, '标签书');

    expect(books.single.wordCount, '1.3万字');
    expect(books.single.chapterCount, 12);
    expect(books.single.updateTime, '2025 06 11');
  });

  test('列表缺失字段保持为空，打开详情时才获取章节数与更新时间', () async {
    final requested = <String>[];
    final timestamp = DateTime(2025, 6, 11).millisecondsSinceEpoch ~/ 1000;
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          requested.add(request.url.path);
          final body = request.url.path == '/search'
              ? <String, Object?>{
                  'ret_data': <Object?>[
                    <String, Object?>{
                      'book_name': '短篇',
                      'author': '作者',
                      'book_url': 'https://example.com/book/1',
                    },
                  ],
                }
              : <String, Object?>{
                  'data': <String, Object?>{
                    'book_name': '短篇',
                    'author': '作者',
                    'word_number': 13000,
                    'content_chapter_number': 1,
                    'last_chapter_update_time': timestamp,
                  },
                };
          return http.Response(
            jsonEncode(body),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      ),
    );
    addTearDown(service.dispose);
    const source = BookSource(
      id: 'tag-detail-source',
      name: '番茄小说',
      sourceUrl: 'https://example.com',
      searchUrl: 'https://example.com/search?q={{key}}',
      search: BookListRule(
        bookList: '.ret_data[*]',
        name: 'book_name',
        author: 'author',
        bookUrl: 'book_url',
      ),
      bookInfo: BookInfoRule(
        init: 'data',
        name: 'book_name',
        author: 'author',
        wordCount: 'word_number',
      ),
      toc: TocRule(),
      content: ContentRule(),
    );

    final books = await service.search(source, '短篇');
    expect(books.single.chapterCount, 0);
    expect(books.single.updateTime, isEmpty);

    expect(requested, ['/search']);
    final info = await service.loadBookInfo(source, books.single);

    expect(info.wordCount, '1.3万字');
    expect(info.chapterCount, 1);
    expect(info.updateTime, '2025 06 11');
    expect(requested, ['/search', '/book/1']);
  });

  test('封面通过书源请求器加载并使用引用页缓存', () async {
    var requests = 0;
    String? referer;
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          requests++;
          referer = request.headers['Referer'] ?? request.headers['referer'];
          return http.Response.bytes(_png, 200);
        }),
      ),
    );
    addTearDown(service.dispose);

    final first = await service.loadCover(
      _source,
      'https://cdn.example.com/cover.png',
      referer: 'https://example.com/book/1',
    );
    final second = await service.loadCover(
      _source,
      'https://cdn.example.com/cover.png',
      referer: 'https://example.com/book/1',
    );

    expect(first, _png);
    expect(second, _png);
    expect(requests, 1);
    expect(referer, 'https://example.com/book/1');
  });

  test('跨站封面拒绝自动引用页时重试并缓存成功图片', () async {
    final referers = <String?>[];
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          final referer =
              request.headers['Referer'] ?? request.headers['referer'];
          referers.add(referer);
          return referer == null
              ? http.Response.bytes(_png, 200)
              : http.Response('Forbidden', 403);
        }),
      ),
    );
    addTearDown(service.dispose);

    final first = await service.loadCover(
      _source,
      'https://cdn.example.net/cover.jpg',
      referer: 'https://example.com/book/1',
    );
    final second = await service.loadCover(
      _source,
      'https://cdn.example.net/cover.jpg',
      referer: 'https://example.com/book/1',
    );

    expect(first, _png);
    expect(second, _png);
    expect(referers, <String?>['https://example.com/book/1', null]);
  });

  test('base64 封面不发起网络请求，无图数据返回空', () async {
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((_) async => throw StateError('不应发起网络请求')),
      ),
    );
    addTearDown(service.dispose);

    final dataUrl = 'data:image/png;base64,${base64Encode(_png)}';
    expect(await service.loadCover(_source, dataUrl), _png);
    expect(
      await service.loadCover(_source, 'data:text/plain;base64,AAAA'),
      isNull,
    );
  });

  test('详情 init 规则先收窄根节点', () async {
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          return http.Response(
            '{"data":{"book_name":"详情名","author":"详情作者","cover":"https://example.com/expired.jpg"}}',
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      ),
      scriptFactory: fakeScriptFactory(
        FakeBookSourceScriptSession((code, result, variables, session) => ''),
      ),
    );
    addTearDown(service.dispose);
    const source = BookSource(
      id: 'init-source',
      name: '详情源',
      sourceUrl: 'https://example.com',
      searchUrl: 'https://example.com/search',
      search: BookListRule(),
      bookInfo: BookInfoRule(
        init: 'data',
        name: 'book_name',
        author: 'author',
        coverUrl: 'cover',
      ),
      toc: TocRule(),
      content: ContentRule(),
    );

    final info = await service.loadBookInfo(
      source,
      const OnlineBook(
        sourceId: 'init-source',
        sourceName: '详情源',
        name: '搜索名',
        author: '',
        bookUrl: 'https://example.com/book/1',
        coverUrl: 'https://example.com/working-signed-cover.jpg',
      ),
    );

    expect(info.name, '详情名');
    expect(info.author, '详情作者');
    expect(info.coverUrl, 'https://example.com/working-signed-cover.jpg');
  });

  test('详情简介保留换行并按原段落归一化', () async {
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'book_name': '换行书',
                'abstract': '第一段\n第二段\n\n第三段\r\n第四段',
              },
            }),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      ),
      scriptFactory: fakeScriptFactory(
        FakeBookSourceScriptSession((code, result, variables, session) => ''),
      ),
    );
    addTearDown(service.dispose);
    const source = BookSource(
      id: 'intro-source',
      name: '简介源',
      sourceUrl: 'https://example.com',
      searchUrl: 'https://example.com/search',
      search: BookListRule(),
      bookInfo: BookInfoRule(init: 'data', intro: r'$.abstract'),
      toc: TocRule(),
      content: ContentRule(),
    );

    final info = await service.loadBookInfo(
      source,
      const OnlineBook(
        sourceId: 'intro-source',
        sourceName: '简介源',
        name: '换行书',
        author: '',
        bookUrl: 'https://example.com/book/1',
      ),
    );

    expect(info.intro, '第一段\n第二段\n\n第三段\n第四段');
  });

  test('data URL 章节地址交给正文脚本并只请求一次接口', () async {
    late FakeBookSourceScriptSession session;
    var requests = 0;
    session = FakeBookSourceScriptSession((code, result, variables, current) {
      expect(result, '12345');
      if (!current.responses.containsKey('content:12345')) {
        current.addPending(
          const BookSourcePendingRequest(
            key: 'content:12345',
            method: 'GET',
            url: 'https://example.com/content?item_id=12345',
          ),
        );
        return '';
      }
      return '<article><p>正文内容</p></article>';
    });
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          requests += 1;
          expect(request.url.queryParameters['item_id'], '12345');
          return http.Response('{"data":{"content":"ok"}}', 200);
        }),
      ),
      scriptFactory: fakeScriptFactory(session),
    );
    addTearDown(service.dispose);
    const source = BookSource(
      id: 'data-url-source',
      name: 'data URL 源',
      sourceUrl: 'https://example.com',
      searchUrl: 'https://example.com/search',
      search: BookListRule(),
      bookInfo: BookInfoRule(),
      toc: TocRule(),
      content: ContentRule(content: '<js>result = getContent(result);</js>'),
    );
    final chapter = OnlineChapter(
      index: 0,
      title: '第一章',
      url: 'data:;base64,${base64Encode(utf8.encode('12345'))}',
    );

    final content = await service.fetchChapterContent(
      source,
      chapter,
      'https://example.com/book/1',
    );

    expect(content, contains('正文内容'));
    expect(requests, 1);
  });

  test('搜索地址 @js 规则使用脚本返回的地址', () async {
    late Uri requested;
    final session = FakeBookSourceScriptSession((
      code,
      result,
      variables,
      current,
    ) {
      expect(code, contains('getUrl'));
      return 'https://example.com/search?q='
          '${Uri.encodeQueryComponent(variables['key'] ?? '')}';
    });
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            '{"ret_data":[{"title":"书","author":"人",'
            '"book_url":"https://example.com/detail/9"}]}',
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      ),
      scriptFactory: fakeScriptFactory(session),
    );
    addTearDown(service.dispose);
    const source = BookSource(
      id: 'js-search-source',
      name: 'JS 搜索源',
      sourceUrl: 'https://example.com',
      searchUrl: '@js:\nfunction getUrl(key) { return key; }\ngetUrl(key)',
      search: BookListRule(
        bookList: '.ret_data[*]',
        name: 'title',
        author: 'author',
        bookUrl: r'$.book_url',
      ),
      bookInfo: BookInfoRule(),
      toc: TocRule(),
      content: ContentRule(),
    );

    final books = await service.search(source, '测试');

    expect(requested.queryParameters['q'], '测试');
    expect(books.single.name, '书');
    expect(books.single.bookUrl, 'https://example.com/detail/9');
  });

  test('多行 sourceUrl 使用首个 HTTP 地址作为 baseUrl', () {
    const source = BookSource(
      id: 'multi-url',
      name: '多地址源',
      sourceUrl: 'https://api.example.com##\n说明文字\nhttp://backup.example.com',
      searchUrl: 'https://api.example.com/search',
      search: BookListRule(),
      bookInfo: BookInfoRule(),
      toc: TocRule(),
      content: ContentRule(),
    );
    expect(source.baseUrl, 'https://api.example.com');
  });
}
