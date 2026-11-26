import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/rea_micro/rea_micro_aggregate_search.dart';
import 'package:reader_mobile/library/library_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('平台搜索断线回退最近完整结果，鉴权失败不读取缓存', () async {
    var status = 200;
    final search = ReaMicroAggregateSearch(
      library: LibraryStore.memory(),
      clientFactory: () => MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            status == 200
                ? '{"code":200,"data":[{"title":"书","author":"作者"}]}'
                : '',
          ),
          status,
        ),
      ),
    );
    Future<ReaMicroPlatformSearchResult> query(String token) =>
        search.searchRule(
          token: token,
          title: '书',
          name: 'qidian_1',
          script: "function search(key){return fetch('https://example.test/list').text();}",
        );
    expect((await query('甲')).books.single.author, '作者');
    status = 503;
    expect((await query('甲')).books.single.author, '作者');
    expect((await query('乙')).books, isEmpty);
    status = 401;
    expect((await query('甲')).error, isNotNull);
  });

  test('菠萝包字数与更新时间分离，同版本旧缓存不覆盖内置修复', () async {
    final library = LibraryStore.memory();
    await library.setSetting(
      'reamicro.search.thirdPartyRules',
      jsonEncode({
        'sfacg_1':
            'function search(){return JSON.stringify({code:200,data:[]});}',
      }),
    );
    final search = ReaMicroAggregateSearch(
      library: library,
      clientFactory: () => MockClient((request) async {
        if (request.url.host != 'm.sfacg.com') return http.Response('', 404);
        return http.Response(
          request.url.path.contains('HTML5')
              ? jsonEncode({
                  'Novels': [
                    {'NovelID': 123},
                  ],
                })
              : '''
<span class="book_newtitle">示例书籍</span>
<div class="book_info2"><span>分类</span><span>连载中</span></div>
<span class="book_info3">示例作者 / 12572字<br>25-08-14 01:22</span>
<ul><li>资料</li><li><img src="//example.test/cover.jpg"></li></ul>
<li class="book_bk_qs1">第一行简介<br>第二行简介</li>
''',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    final results = <ReaMicroPlatformSearchResult>[];
    await search.search(token: 'test', title: '示例书籍', onResult: results.add);
    final result = results.singleWhere((result) => result.source == '菠萝包轻小说');
    expect(result.error, isNull);
    final book = result.books.single;
    expect(book.words, '1.3万');
    expect(book.publishDate, '25-08-14 01:22');
    expect(book.status, '连载中');
    expect(book.cover, 'https://example.test/cover.jpg');
  });

  test('豆瓣优先使用大封面并保留简介与出版社，页数标记为页', () async {
    final search = ReaMicroAggregateSearch(
      clientFactory: () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'books': [
              {
                'title': '示例书籍',
                'author': ['示例作者'],
                'publisher': '示例出版社',
                'image': 'https://img3.doubanio.com/small.jpg',
                'images': {'large': 'https://img3.doubanio.com/large.jpg'},
                'summary': '详细简介',
                'pages': 320,
                'price': '49.00元',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final result = await search.searchRule(
      name: 'douban_4',
      script: await File('assets/rea_micro/search/douban_4.js').readAsString(),
      title: '示例书籍',
    );
    expect(result.error, isNull);
    final book = result.books.single;
    expect(book.cover, 'https://img3.doubanio.com/large.jpg');
    expect(book.intro, '详细简介');
    expect(book.publisher, '示例出版社');
    expect(book.words, '320页');
    expect(book.price, '49.00元');
  });

  test('全部十个阅微原生规则通过正式运行时入口加载', () async {
    final root = Directory('assets/rea_micro/search');
    final names = (jsonDecode(
      await File('${root.path}/manifest.json').readAsString(),
    ) as List).cast<String>();
    expect(names, hasLength(10));
    final search = ReaMicroAggregateSearch(
      clientFactory: () => MockClient((_) async => http.Response('', 404)),
    );
    for (final name in names) {
      final result = await search.searchRule(
        name: name,
        script: await File('${root.path}/$name.js').readAsString(),
        title: '',
      );
      expect(result.error, isNull, reason: name);
      expect(result.books, isEmpty, reason: name);
    }
  });

  test('刺猬猫原生规则查列表和详情，重放不重复请求且保留不同作者候选', () async {
    final urls = <String>[];
    final search = ReaMicroAggregateSearch(
      clientFactory: () => MockClient((request) async {
        urls.add(request.url.path);
        return http.Response(
          request.url.path.startsWith('/get-search')
              ? '<li data-book-id="123"></li><li data-book-id="123"></li>'
              : '''
<meta property="og:novel:book_name" content="笨蛋哈利与马尔福大小姐的二三事">
<meta property="og:novel:author" content="Luis没了">
<meta property="og:description" content="平台简介">
<meta property="og:image" content="https://example.com/cover.jpg">
<p class="book-grade"><b>0</b><b>0</b><b>100000</b></p>
<p class="update-state">连载 · 更新中</p>''',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    final result = await search.searchRule(
      name: 'ciweimao_1',
      script: await File('assets/rea_micro/search/ciweimao_1.js')
          .readAsString(),
      title: '笨蛋哈利与马尔福大小姐的二三事',
    );
    expect(result.error, isNull);
    expect(result.books, hasLength(1));
    final book = result.books.single;
    expect(book.author, 'Luis没了');
    expect(book.intro, '平台简介');
    expect(book.words, '10.0万');
    expect(book.status, '连载');
    expect(book.candidate.linkable, isTrue);
    expect(urls, hasLength(2));
  });

  test('原生 GBK 编码桥和响应解码支持晋江飞卢中文查询', () async {
    final search = ReaMicroAggregateSearch(
      clientFactory: () => MockClient((request) async {
        expect(request.url.query, 'q=%D6%D0%CE%C4');
        return http.Response.bytes(
          const GbkCodec().encode('中文书名'),
          200,
          headers: {'content-type': 'text/html; charset=gb2312'},
        );
      }),
    );
    final result = await search.searchRule(
      name: 'faloo_1',
      title: '中文',
      script: '''
function search(key){
  var title=fetch('https://example.com/?q='+gbkEncode(key)).text();
  return JSON.stringify({code:200,data:[{title:title,author:'作者',publisher:'飞卢小说网'}]});
}
''',
    );
    expect(result.error, isNull);
    expect(result.books.single.title, '中文书名');
  });

  test('长书名无结果时缩短查询并继续使用完整书名筛选', () async {
    final queryKeys = <String>[];
    final search = ReaMicroAggregateSearch(
      clientFactory: () => MockClient((request) async {
        final key = request.url.queryParameters['q']!;
        queryKeys.add(key);
        return http.Response(
          jsonEncode({
            'code': 200,
            'data': key == '笨蛋哈利'
                ? [
                    {'title': '笨蛋哈利与马尔福大小姐的二三事', 'publisher': '刺猬猫阅读'},
                    {'title': '完全不同作品', 'publisher': '刺猬猫阅读'},
                  ]
                : <Map<String, String>>[],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final result = await search.searchRule(
      name: 'ciweimao_1',
      title: '笨蛋哈利与马尔福大小姐的二三事',
      script: '''
function search(key){return fetch('https://example.com/?q='+encodeURIComponent(key)).text();}
''',
    );
    expect(result.error, isNull);
    expect(queryKeys, ['笨蛋哈利与马尔福大小姐的二三事', '笨蛋哈利']);
    expect(result.books.single.title, '笨蛋哈利与马尔福大小姐的二三事');
  });

  test('平台超时不阻断其他结果，取消后不再请求详情或回填结果', () async {
    final slow = Completer<http.Response>();
    const fastRule = '''
function search(key){return JSON.stringify({code:200,data:[{title:key,author:'作者',publisher:'起点中文网'}]});}
''';
    const slowRule = '''
function search(key){return fetch('https://example.com/slow').text();}
''';
    final updates = <ReaMicroPlatformSearchResult>[];
    final search = ReaMicroAggregateSearch(
      rulesLoader: () async => {'qidian_1': fastRule, 'faloo_1': slowRule},
      clientFactory: () => MockClient((_) => slow.future),
      requestTimeout: const Duration(milliseconds: 30),
      sourceTimeout: const Duration(milliseconds: 100),
    );
    await search.search(token: 'token', title: '书', onResult: updates.add);
    expect(updates.first.source, '起点中文网');
    expect(updates.first.books.single.title, '书');
    expect(updates.last.error, isNotNull);
    var cancelled = false;
    final waiting = Completer<http.Response>();
    final urls = <String>[];
    final cancellable = ReaMicroAggregateSearch(
      rulesLoader: () async => {
        'ciweimao_1': '''
function search(key){fetch('https://example.com/list');fetch('https://example.com/detail');return '';}
''',
      },
      clientFactory: () => MockClient((request) {
        urls.add(request.url.path);
        return waiting.future;
      }),
    );
    final run = cancellable.search(
      token: 'token',
      title: '书',
      isCancelled: () => cancelled,
      onResult: (_) => fail('已取消的搜索不能回填'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    cancelled = true;
    waiting.complete(http.Response('', 200));
    await run;
    expect(urls, ['/list']);
    slow.complete(http.Response('', 200));
  });
}
