import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';

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

void main() {
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
}
