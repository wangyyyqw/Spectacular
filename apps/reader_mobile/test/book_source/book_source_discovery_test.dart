import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/book_source/book_source_discovery.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';

import 'book_source_test_helpers.dart';

void main() {
  test('旧分类声明按排序、平台、分类与标签组合，分页模板保留', () {
    final categories = parseDiscoverCategories(
      '最近更新::/list?sort=updated_desc&page={{page}}&limit=20\n'
      '人气最高::/list?sort=popularity_desc&page={{page}}&limit=20\n'
      '起点::/list?platform=qidian&sort=cache_desc&page={{page}}&limit=20\n'
      '修仙::/list?tag=修仙&sort=cache_desc&page={{page}}&limit=20',
    );
    final filter = parseDiscoverFilter(
      '',
      categories,
      kinds: ['qidian 仙侠 修仙,凡人流'],
    )!;
    expect(filter.groups.map((group) => group.name), ['排序', '平台', '分类', '标签']);
    final selection = {
      ...filter.defaults,
      '排序': '人气最高',
      '平台': '起点',
      '分类': '仙侠',
      '标签': '凡人流',
    };
    final category = filter.category(selection);
    expect(Uri.parse(category.url).queryParameters, {
      'sort': 'popularity_desc',
      'platform': 'qidian',
      'category': '仙侠',
      'tag': '凡人流',
      'page': '{{page}}',
      'limit': '20',
    });
    expect(category.url, contains('{{page}}'));
    expect(
      Uri.parse(filter.category(filter.defaults).url).queryParameters
          .containsKey('platform'),
      isFalse,
    );
  });

  test('脚本筛选提取原声明，平台选择不覆盖独立排序', () {
    const raw = """@js:
var groups=[["排序",[["最近更新",{"sort":"updated_desc"}]],2],["平台",[["起点",{"platform":"qidian","sort":"cache_desc"}]],2],["分类",[["仙侠",{"category":"仙侠","sort":"cache_desc"}]],3],["标签",[["修仙",{"tag":"修仙","sort":"cache_desc"}]],3]];
var sorts=[{label:'更新时间',value:'updated_desc'},{label:'人气最高',value:'popularity_desc'}];
function search(params){var parts=[];parts.push('cache_min=1');parts.push('page={{page}}');parts.push('limit=20');return '/list?'+parts.join('&');}
""";
    final filter = parseDiscoverFilter(raw, const [])!;
    final category = filter.category({
      ...filter.defaults,
      '排序': '人气最高',
      '平台': '起点',
      '分类': '仙侠',
      '标签': '修仙',
    });
    expect(Uri.parse(category.url).queryParameters['sort'], 'popularity_desc');
    expect(Uri.parse(category.url).queryParameters['cache_min'], '1');
    expect(Uri.parse(category.url).queryParameters['category'], '仙侠');
    expect(Uri.parse(category.url).queryParameters['tag'], '修仙');
  });
  test('脚本发现分类在正式运行时求值并序列化对象数组', () {
    final session = FakeBookSourceScriptSession((
      code,
      result,
      variables,
      session,
    ) {
      expect(code, contains('JSON.stringify(eval('));
      expect(variables['baseUrl'], 'https://example.com');
      return '[{"title":"人气最高","url":"/popular"}]';
    });
    final service = BookSourceService(
      scriptFactory: fakeScriptFactory(session),
    );
    addTearDown(service.dispose);
    const source = BookSource(
      id: 'js-discovery',
      name: '脚本来源',
      sourceUrl: 'https://example.com',
      searchUrl: '/search',
      search: BookListRule(),
      bookInfo: BookInfoRule(),
      toc: TocRule(),
      content: ContentRule(),
      exploreUrl: '@js:[{title:"人气最高",url:"/popular"}]',
    );
    expect(service.discoverCategories(source).single.title, '人气最高');
  });
  test('发现分类支持 JSON、逐行声明和请求参数', () {
    final categories = parseDiscoverCategories(
      '[{"title":"最近更新","url":"/latest,{\\"headers\\":{\\"X-List\\":\\"latest\\"}}"},'
      '{"title":"人气最高","url":"/popular?page={{page}}"}]',
    );
    expect(categories.map((item) => item.title), ['最近更新', '人气最高']);
    expect(categories.first.url, '/latest');
    expect(categories.first.options['headers'], {'X-List': 'latest'});
    expect(
      parseDiscoverCategories('最近更新::/latest\n人气最高::/popular'),
      hasLength(2),
    );
  });

  test('发现正式入口使用独立列表规则、分类请求参数和分页，搜索规则继续有效', () async {
    final requests = <http.Request>[];
    final service = BookSourceService(
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'rank': [
                {
                  'title': '发现书',
                  'writer': '发现作者',
                  'url': '/book/1',
                  'latest': '第十章',
                },
                {'title': '第二本发现书', 'writer': '第二位作者', 'url': '/book/3'},
              ],
              'search': [
                {'name': '搜索书', 'author': '搜索作者', 'url': '/book/2'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    addTearDown(service.dispose);
    final source = BookSource(
      id: 'discovery',
      name: '测试平台',
      sourceUrl: 'https://example.com',
      searchUrl: '/search?q={{key}}',
      search: const BookListRule(
        bookList: r'$.search',
        name: 'name',
        author: 'author',
        bookUrl: 'url',
      ),
      bookInfo: const BookInfoRule(),
      toc: const TocRule(),
      content: const ContentRule(),
      exploreUrl: '最近更新::/rank?page={{page}}',
      raw: {
        'ruleExplore': {
          'bookList': r'$.rank',
          'name': 'title',
          'author': 'writer',
          'bookUrl': 'url',
          'lastChapter': 'latest',
        },
      },
    );
    final category = BookDiscoverCategory(
      '最近更新',
      '/rank?page={{page}}',
      options: {
        'headers': {'X-List': 'rank'},
      },
    );
    final found = await service.discover(source, category, page: 2);
    expect(requests.last.url.toString(), 'https://example.com/rank?page=2');
    expect(requests.last.headers['X-List'], 'rank');
    expect(found.map((book) => book.name), ['发现书', '第二本发现书']);
    expect(found.first.author, '发现作者');
    expect(found.first.bookUrl, 'https://example.com/book/1');
    expect(found.first.lastChapter, '第十章');
    expect((await service.search(source, '搜索书')).single.name, '搜索书');
    expect(requests.last.url.queryParameters['q'], '搜索书');
  });
}
