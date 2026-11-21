import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';

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

void main() {
  test('手动跟随重定向并保留最终地址', () async {
    final requests = <Uri>[];
    final client = BookSourceHttpClient(
      client: MockClient((request) async {
        requests.add(request.url);
        if (requests.length == 1) {
          return http.Response(
            '',
            302,
            headers: <String, String>{'location': '/book/2'},
          );
        }
        return http.Response('ok', 200);
      }),
    );
    addTearDown(client.close);

    final response = await client.fetchText(
      _source,
      'https://example.com/book/1',
    );

    expect(requests, <Uri>[
      Uri.parse('https://example.com/book/1'),
      Uri.parse('https://example.com/book/2'),
    ]);
    expect(response.uri, Uri.parse('https://example.com/book/2'));
    expect(response.body, 'ok');
  });

  test('限流响应携带状态码并标记可重试', () async {
    final client = BookSourceHttpClient(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode('{"detail":"请稍后"}'),
          429,
          headers: <String, String>{'retry-after': '1'},
        ),
      ),
    );
    addTearDown(client.close);

    await expectLater(
      client.fetchText(_source, 'https://example.com/search'),
      throwsA(
        isA<BookSourceException>()
            .having((error) => error.statusCode, 'statusCode', 429)
            .having((error) => error.isTransient, 'isTransient', isTrue)
            .having((error) => error.message, 'message', contains('请稍后')),
      ),
    );
  });

  test('图片请求保留书源显式引用页，403 不触发自动引用页重试', () async {
    const source = BookSource(
      id: 'explicit-referer',
      name: '显式引用页',
      sourceUrl: 'https://example.com',
      searchUrl: 'https://example.com/search',
      header: '{"referer":"https://images.example.net/"}',
      search: BookListRule(),
      bookInfo: BookInfoRule(),
      toc: TocRule(),
      content: ContentRule(),
    );
    final referers = <String?>[];
    final client = BookSourceHttpClient(
      client: MockClient((request) async {
        referers.add(request.headers['Referer'] ?? request.headers['referer']);
        return http.Response('Forbidden', 403);
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.fetchBytes(
        source,
        'https://images.example.net/cover.jpg',
        referer: 'https://example.com/book/1',
      ),
      throwsA(
        isA<BookSourceException>().having(
          (error) => error.statusCode,
          'statusCode',
          403,
        ),
      ),
    );

    expect(referers, <String?>['https://images.example.net/']);
  });

  test('图片引用页重试不扩展到文本、同站图片或非 403 响应', () async {
    final requests = <Uri>[];
    final client = BookSourceHttpClient(
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          'Unavailable',
          request.url.path == '/missing.jpg' ? 404 : 403,
        );
      }),
    );
    addTearDown(client.close);

    final operations = <Future<BookSourceHttpResponse> Function()>[
      () => client.fetchText(
        _source,
        'https://other.example.net/book/1',
        referer: 'https://example.com/search',
      ),
      () => client.fetchBytes(
        _source,
        'https://example.com/cover.jpg',
        referer: 'https://example.com/book/1',
      ),
      () => client.fetchBytes(
        _source,
        'https://other.example.net/missing.jpg',
        referer: 'https://example.com/book/1',
      ),
    ];
    for (final operation in operations) {
      await expectLater(operation(), throwsA(isA<BookSourceException>()));
    }

    expect(requests, <Uri>[
      Uri.parse('https://other.example.net/book/1'),
      Uri.parse('https://example.com/cover.jpg'),
      Uri.parse('https://other.example.net/missing.jpg'),
    ]);
  });

  test('跨站图片移除自动引用页后仍失败时只重试一次', () async {
    final referers = <String?>[];
    final client = BookSourceHttpClient(
      client: MockClient((request) async {
        referers.add(request.headers['Referer'] ?? request.headers['referer']);
        return http.Response('Forbidden', 403);
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.fetchBytes(
        _source,
        'https://other.example.net/cover.jpg',
        referer: 'https://example.com/book/1',
      ),
      throwsA(isA<BookSourceException>()),
    );

    expect(referers, <String?>['https://example.com/book/1', null]);
  });

  test('404 不标记为临时错误，内网地址在发请求前拒绝', () async {
    final client = BookSourceHttpClient(
      client: MockClient((_) async => http.Response('missing', 404)),
    );
    addTearDown(client.close);

    await expectLater(
      client.fetchText(_source, 'https://example.com/book'),
      throwsA(
        isA<BookSourceException>()
            .having((error) => error.statusCode, 'statusCode', 404)
            .having((error) => error.isTransient, 'isTransient', isFalse),
      ),
    );
    await expectLater(
      client.fetchText(_source, 'http://127.0.0.1/private'),
      throwsA(
        isA<BookSourceException>().having(
          (error) => error.code,
          'code',
          'ONLINE_HTTP_PRIVATE_HOST',
        ),
      ),
    );
  });

  test('登录 Cookie 会持久化并自动附加到后续请求', () async {
    final directory = await Directory.systemTemp.createTemp('http-cookie-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    var requests = 0;
    final client = BookSourceHttpClient(
      cookieStore: store,
      client: MockClient((request) async {
        requests += 1;
        if (requests == 1) {
          return http.Response(
            'ok',
            200,
            headers: <String, String>{
              'set-cookie': 'sessionid=abc; Path=/; HttpOnly',
            },
          );
        }
        expect(request.headers['Cookie'], contains('sessionid=abc'));
        return http.Response('ok', 200);
      }),
    );
    addTearDown(client.close);

    await client.fetchText(_source, 'https://example.com/login');
    await client.fetchText(_source, 'https://example.com/bookshelf');

    expect(store.cookieValue('example.com', 'sessionid'), 'abc');
    expect(requests, 2);
  });

  test('显式 Cookie 优先，关闭 CookieJar 时不自动携带', () async {
    final directory = await Directory.systemTemp.createTemp('http-cookie-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    await store.saveLoginCookies('example.com', <String, String>{
      'sessionid': 'saved',
    });
    final headers = <String?>[];
    final client = BookSourceHttpClient(
      cookieStore: store,
      client: MockClient((request) async {
        headers.add(request.headers['Cookie']);
        return http.Response('ok', 200);
      }),
    );
    addTearDown(client.close);

    await client.fetchText(
      _source,
      'https://example.com/one',
      headers: const <String, String>{'Cookie': 'manual=1'},
    );
    const noJarSource = BookSource(
      id: 'source-2',
      name: '关闭 Cookie',
      sourceUrl: 'https://example.com',
      searchUrl: 'https://example.com/search',
      enabledCookieJar: false,
      search: BookListRule(),
      bookInfo: BookInfoRule(),
      toc: TocRule(),
      content: ContentRule(),
    );
    await client.fetchText(noJarSource, 'https://example.com/two');

    expect(headers.first, 'manual=1');
    expect(headers.last, isNull);
  });
}
