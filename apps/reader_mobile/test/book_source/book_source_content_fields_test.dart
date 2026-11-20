import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_script.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';
import 'package:reader_mobile/book_source/online_chapter_content_store.dart';
import 'package:reader_mobile/book_source/online_chapter_request.dart';

import 'book_source_test_helpers.dart';

const _book = OnlineBook(
  sourceId: 'fields-source',
  sourceName: '字段测试源',
  name: '字段测试书',
  author: '测试作者',
  bookUrl: 'https://example.test/book',
  tocUrl: 'https://example.test/toc',
);

const _chapter = OnlineChapter(
  index: 0,
  title: '第一章',
  url: 'https://example.test/chapter/1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('source-fields-');
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('无地址分卷不补成章节，卷标题跨目录分页且有正文地址的卷首可读', () async {
    final requests = <String>[];
    final service = _service(directory, (request) async {
      requests.add(request.url.path);
      return _json(
        request.url.path == '/toc'
            ? {
                'chapters': [
                  {'title': '第一卷', 'isVolume': true, 'url': '/toc#volume-1'},
                  {'title': '第一章', 'readUrl': '/chapter/1'},
                  {'title': '第二卷', 'isVolume': 'yes', 'readUrl': '/foreword'},
                ],
                'next': ['/toc/2'],
              }
            : {
                'chapters': [
                  {'title': '第二章', 'readUrl': '/chapter/2'},
                  {'title': '第三卷', 'isVolume': '1'},
                  {'title': '第三章', 'readUrl': '/chapter/3'},
                ],
              },
      );
    });
    final source = _source(
      toc: const TocRule(
        chapterList: r'$.chapters[*]',
        chapterName: r'$.title',
        chapterUrl: r'$.readUrl',
        isVolume: r'$.isVolume',
        nextTocUrl: r'$.next[*]',
      ),
    );

    final chapters = await service.fetchToc(source, _book);

    expect(chapters.map((chapter) => chapter.title), [
      '第一章',
      '第二卷',
      '第二章',
      '第三章',
    ]);
    expect(chapters.map((chapter) => chapter.volume), [
      '第一卷',
      '第二卷',
      '第二卷',
      '第三卷',
    ]);
    expect(chapters.map((chapter) => chapter.index), [0, 1, 2, 3]);
    expect(chapters[1].url, 'https://example.test/foreword');
    expect(requests, ['/toc', '/toc/2']);
  });

  test('HTML 分卷缺正文地址时忽略锚点回退与脚本占位地址', () async {
    final service = _service(
      directory,
      (_) async => http.Response(
        '<ul class="toc">'
        '<li data-volume="true"><a href="/toc#first">第一卷</a></li>'
        '<li data-read="/chapter/1"><a>第一章</a></li>'
        '<li data-volume="true" data-read="#second">第二卷</li>'
        '<li data-read="/chapter/2">第二章</li>'
        '<li data-volume="true" data-read="javascript:void(0)">第三卷</li>'
        '<li data-read="/chapter/3">第三章</li>'
        '</ul>',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      ),
    );
    final source = _source(
      toc: const TocRule(
        chapterList: '.toc li',
        chapterName: 'text',
        chapterUrl: '@data-read',
        isVolume: '@data-volume',
      ),
    );

    final chapters = await service.fetchToc(source, _book);

    expect(chapters.map((chapter) => chapter.title), ['第一章', '第二章', '第三章']);
    expect(chapters.map((chapter) => chapter.volume), ['第一卷', '第二卷', '第三卷']);
  });

  test('分卷指向目录或详情锚点时只分组，同地址不同 POST 请求仍可作为卷首', () async {
    final service = _service(
      directory,
      (_) async => _json({
        'chapters': [
          {'title': '第一卷', 'isVolume': true, 'url': '/toc#first'},
          {'title': '第一章', 'url': '/chapter/1'},
          {'title': '第二卷', 'isVolume': true, 'url': '/book#second'},
          {'title': '第二章', 'url': '/chapter/2'},
          {'title': '第三卷', 'isVolume': true, 'url': '/toc'},
          {'title': '第三章', 'url': '/chapter/3'},
          {
            'title': '卷首正文',
            'isVolume': true,
            'url': '/toc,{"method":"POST","body":"content=foreword"}',
          },
        ],
      }),
    );

    final chapters = await service.fetchToc(_source(), _book);

    expect(chapters.map((chapter) => chapter.title), [
      '第一章',
      '第二章',
      '第三章',
      '卷首正文',
    ]);
    expect(chapters.map((chapter) => chapter.volume), [
      '第一卷',
      '第二卷',
      '第三卷',
      '卷首正文',
    ]);
    expect(chapters.last.url, _book.tocUrl);
    expect(chapters.last.requestOptions, {
      'method': 'POST',
      'body': 'content=foreword',
    });
  });

  test('分卷真值遵循 Legado，空值和各类假值仍是普通章节', () async {
    const falseValues = <Object?>[
      null,
      '',
      false,
      ' FALSE ',
      'No',
      'not',
      0,
      '0.0',
    ];
    final service = _service(
      directory,
      (_) async => _json({
        'chapters': [
          for (final (index, value) in falseValues.indexed)
            {
              'title': '普通章节${index + 1}',
              'url': '/chapter/${index + 1}',
              'isVolume': value,
            },
          {'title': '附录卷', 'isVolume': '其他非空文本'},
          {'title': '附录正文', 'url': '/appendix'},
        ],
      }),
    );

    final chapters = await service.fetchToc(_source(), _book);

    expect(chapters, hasLength(falseValues.length + 1));
    expect(
      chapters.take(falseValues.length).map((chapter) => chapter.volume),
      everyElement(isEmpty),
    );
    expect(chapters.last.title, '附录正文');
    expect(chapters.last.volume, '附录卷');
  });

  test('合并全部正文分页后执行一次全文替换并保留段落', () async {
    final requests = <String>[];
    final service = _service(directory, (request) async {
      requests.add(request.url.toString());
      return _json(
        request.url.queryParameters['page'] == '2'
            ? {'content': '<p>连页尾部</p><p>姓名：乙</p><p>章节正常正文。（本章完）</p>'}
            : {
                'content': '<p>姓名：甲</p><p>连页头部</p>',
                'next': ['?page=2'],
              },
      );
    });
    final source = _source(replaceRegex: r'##连页头部</p>\s*<p>连页尾部##跨页接续');

    final content = await service.fetchChapterContent(
      source,
      _chapter,
      _book.bookUrl,
    );

    expect(requests, hasLength(2));
    expect(content, contains('<p>姓名：甲</p>'));
    expect(content, contains('<p>跨页接续</p>'));
    expect(content, contains('<p>姓名：乙</p>'));
    expect(content, isNot(contains('本章完')));
    expect(content, isNot(contains('连页头部')));
    expect(content, isNot(contains('连页尾部')));
  });

  test('全文替换支持 Java 分组引用且直接复用已替换的缓存', () async {
    var requests = 0;
    final service = _service(directory, (_) async {
      requests += 1;
      return _json({'content': '<p>姓名：甲</p><p>姓名：乙</p>'});
    });
    final source = _source(replaceRegex: r'##姓名：([^<]+)##姓名：$1同学');

    final first = await service.fetchChapterContent(
      source,
      _chapter,
      _book.bookUrl,
    );
    final cached = await service.fetchChapterContent(
      source,
      _chapter,
      _book.bookUrl,
    );

    expect(first, '<p>姓名：甲同学</p><p>姓名：乙同学</p>');
    expect(cached, first);
    expect(requests, 1);
  });

  test('全文替换生成的懒加载图片转换为正式阅读可用的绝对地址', () async {
    final service = _service(
      directory,
      (_) async => _json({'content': '<p>正文中的插图占位。</p>'}),
    );

    final content = await service.fetchChapterContent(
      _source(replaceRegex: r'##插图占位##<img data-src="/images/page.png">'),
      _chapter,
      _book.bookUrl,
    );

    expect(content, contains('src="https://example.test/images/page.png"'));
    expect(content, isNot(contains('data-src')));
    expect(content, contains('<p>正文中的<img'));
  });

  test('正文替换脚本读取完整章内容，缓存读取不再次执行替换', () async {
    var requests = 0;
    var replacements = 0;
    final service = _service(
      directory,
      (request) async {
        requests += 1;
        return _json(
          request.url.queryParameters['page'] == '2'
              ? {'content': '<p>第二页的正常正文。</p>'}
              : {
                  'content': '<p>第一页的正常正文。</p>',
                  'next': ['?page=2'],
                },
        );
      },
      scriptFactory: (_) =>
          FakeBookSourceScriptSession((code, result, variables, session) {
            replacements += 1;
            expect(result, contains('第一页'));
            expect(result, contains('第二页'));
            expect(variables['chapterUrl'], _chapter.url);
            expect(variables['title'], _chapter.title);
            return '$result<p>全文替换只追加一次。</p>';
          }),
    );
    final source = _source(replaceRegex: '@js:result');

    final first = await service.fetchChapterContent(
      source,
      _chapter,
      _book.bookUrl,
    );
    final cached = await service.fetchChapterContent(
      source,
      _chapter,
      _book.bookUrl,
    );

    expect(cached, first);
    expect(first, contains('全文替换只追加一次'));
    expect(replacements, 1);
    expect(requests, 2);
  });

  test('正文替换脚本请求复用现有调度链路', () async {
    final requested = <String>[];
    final service = _service(
      directory,
      (request) async {
        requested.add(request.url.path);
        return request.url.path == '/replacement'
            ? http.Response(
                '可阅读的替换正文。',
                200,
                headers: {'content-type': 'text/plain; charset=utf-8'},
              )
            : _json({'content': '<p>替换前的正常正文。</p>'});
      },
      scriptFactory: (_) =>
          FakeBookSourceScriptSession((code, result, variables, session) {
            final body = session.responses['replacement'];
            if (body != null) return '<p>$body</p>';
            session.addPending(
              const BookSourcePendingRequest(
                key: 'replacement',
                url: 'https://example.test/replacement',
                method: 'GET',
                body: '',
                headers: {},
              ),
            );
            return '';
          }),
    );

    final content = await service.fetchChapterContent(
      _source(replaceRegex: '@js:result'),
      _chapter,
      _book.bookUrl,
    );

    expect(content, '<p>可阅读的替换正文。</p>');
    expect(requested, ['/chapter/1', '/replacement']);
  });

  test('替换后空正文被拒绝且不写入缓存，可修复后重试', () async {
    var requests = 0;
    final service = _service(directory, (_) async {
      requests += 1;
      return _json({'content': requests == 1 ? '广告段落' : '能够阅读的正常正文。'});
    });
    final source = _source(replaceRegex: r'##广告段落##');

    await expectLater(
      service.fetchChapterContent(source, _chapter, _book.bookUrl),
      throwsA(
        isA<BookSourceException>().having(
          (error) => error.code,
          '错误码',
          'ONLINE_CONTENT_INVALID',
        ),
      ),
    );
    expect(
      await service.chapterContentStore.read(
        sourceId: source.id,
        bookUrl: _book.bookUrl,
        chapterUrl: _chapter.url,
        rulesFingerprint: service.chapterContentRevision(source, _chapter),
      ),
      isNull,
    );
    expect(
      await service.fetchChapterContent(source, _chapter, _book.bookUrl),
      contains('能够阅读'),
    );
    expect(requests, 2);
  });

  test('sourceRegex 保留资源嗅探语义，不被当作纯 HTTP 正文替换', () async {
    final service = _service(
      directory,
      (_) async => _json({'content': '<p>正常正文不会被资源嗅探正则删除。</p>'}),
    );

    final content = await service.fetchChapterContent(
      _source(sourceRegex: '.*'),
      _chapter,
      _book.bookUrl,
    );

    expect(content, contains('正常正文不会被资源嗅探正则删除'));
  });

  test('正文 v4 隔离 v3 未处理缓存，重新取得正文并保留旧缓存文件', () async {
    var requests = 0;
    final service = _service(directory, (_) async {
      requests += 1;
      return _json({'content': '<p>姓名：甲的新正文。</p>'});
    });
    final source = _source(replaceRegex: r'##姓名：##作者：');
    final legacyRules = _digest({
      'version': 3,
      'base': source.baseUrl,
      'headers': source.header,
      'jsLib': source.jsLib,
      'content': source.content.content,
      'next': source.content.nextContentUrl,
      'replace': source.content.replaceRegex,
      'source': source.content.sourceRegex,
    });
    final legacyChapter = _digest([
      legacyRules,
      _chapter.title,
      _chapter.updateTime,
      onlineChapterIdentity(_chapter),
    ]);
    const legacyContent = '<p>姓名：甲的旧版未替换正文。</p>';
    await service.chapterContentStore.write(
      sourceId: source.id,
      bookUrl: _book.bookUrl,
      chapterUrl: _chapter.url,
      rulesFingerprint: legacyChapter,
      content: legacyContent,
    );

    final content = await service.fetchChapterContent(
      source,
      _chapter,
      _book.bookUrl,
    );

    expect(service.contentRulesFingerprint(source), isNot(legacyRules));
    expect(content, contains('作者：甲的新正文'));
    expect(content, isNot(contains('旧版')));
    expect(requests, 1);
    expect(
      await service.chapterContentStore.read(
        sourceId: source.id,
        bookUrl: _book.bookUrl,
        chapterUrl: _chapter.url,
        rulesFingerprint: legacyChapter,
      ),
      legacyContent,
    );
  });
}

BookSource _source({
  TocRule toc = const TocRule(
    chapterList: r'$.chapters[*]',
    chapterName: r'$.title',
    chapterUrl: r'$.url',
    isVolume: r'$.isVolume',
    nextTocUrl: r'$.next[*]',
  ),
  String replaceRegex = '',
  String sourceRegex = '',
}) => BookSource(
  id: _book.sourceId,
  name: _book.sourceName,
  sourceUrl: 'https://example.test',
  searchUrl: 'https://example.test/search',
  search: const BookListRule(),
  bookInfo: const BookInfoRule(),
  toc: toc,
  content: ContentRule(
    content: r'$.content',
    nextContentUrl: r'$.next[*]',
    replaceRegex: replaceRegex,
    sourceRegex: sourceRegex,
  ),
);

String _digest(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

http.Response _json(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

BookSourceService _service(
  Directory directory,
  Future<http.Response> Function(http.Request) handler, {
  BookSourceScriptFactory? scriptFactory,
}) {
  final cookies = BookSourceCookieStore(
    directoryProvider: () async => directory,
  );
  final service = BookSourceService(
    cookieStore: cookies,
    chapterContentStore: OnlineChapterContentStore(
      directoryProvider: () async => directory,
    ),
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
