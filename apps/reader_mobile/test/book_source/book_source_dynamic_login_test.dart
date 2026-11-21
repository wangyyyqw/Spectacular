import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/book_source/book_source_auth.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_script.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';
import 'package:reader_mobile/book_source/book_source_rule_engine.dart';
import 'package:reader_mobile/book_source/online_chapter_content_store.dart';

class _Browser implements BookSourceLoginLauncher {
  String? openedUrl;
  bool cancel = false;
  bool redirect = false;

  @override
  Future<BookSourceLoginPageResult?> open({
    required String url,
    required String title,
  }) async {
    openedUrl = url;
    if (cancel) return null;
    return BookSourceLoginPageResult(
      cookieHeader: 'sessionid=sample==; uid=42',
      url: redirect ? 'https://redirect.example.test/complete' : url,
      cookiesByDomain: redirect
          ? {'web.example.test': 'sessionid=sample==; uid=42'}
          : const {},
    );
  }
}

const _source = BookSource(
  id: 'dynamic',
  name: '动态测试源',
  sourceUrl: 'https://api.example.test',
  loginUi: '''@js:
var rows = source.get('menu') === 'extra'
 ? [{name:'主题',type:'toggle',chars:['日间','夜间']}]
 : [{name:'密钥',type:'password'},
    {name:'接口',type:'select',chars:['甲','乙'],default:source.get('mode')||'甲',action:"setMode(result['接口'])"},
    {name:'网页登录',type:'button',action:'webLogin()'}];
source.put('menu','');
result=JSON.stringify(rows);
''',
  loginUrl: '''
function login() { source.put('confirmed',result['密钥']); }
function setMode(value) { source.put('mode',value); java.toast('已切换'+value); }
function webLogin() {
 java.startBrowserAwait('https://web.example.test/login','网页登录');
 var domain='web.example.test';
 source.setVariable(cookie.getCookie(domain));
 source.put('session',java.getCookie(domain,'sessionid'));
 java.longToast('已保存 Cookie');
}
function submenu() { source.put('menu','extra'); java.reLoginView(); }
''',
  searchUrl: '',
  search: BookListRule(),
  bookInfo: BookInfoRule(),
  toc: TocRule(),
  content: ContentRule(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('正式脚本入口兼容对象和 JSON 文本、条件赋值及章节编号', () {
    final script = QuickJsBookSourceScriptSession(jsLib: '');
    addTearDown(script.dispose);
    const engine = BookSourceRuleEngine();
    const context = BookSourceRuleContext(
      baseUrl: 'https://api.example.test',
      variables: {
        'bookUrl': 'https://api.example.test/book/1',
        'chapterUrl': 'data:;base64,NzY1NDMyMQ==',
        'chapterIndex': '2',
        'title': '第三章',
      },
    );
    expect(
      engine.evaluateString(
        {'id': '123'},
        '''<js>
var id=JSON.parse(result).id;
result=id+':'+result.id+':'+book.bookUrl+':'+chapter.index;
if(false) { result='不应进入'; }
</js>''',
        context,
        script: script,
      ),
      '123:123:https://api.example.test/book/1:2',
    );
    expect(
      engine.evaluateString(
        '7654321',
        '<js>java.hexDecodeToString(result)</js>',
        context,
        script: script,
      ),
      '7654321',
    );
    expect(
      engine.evaluateString(
        'text',
        '<js>java.timeFormatUTC(0,"yyyy-MM-dd HH:mm:ss",8)</js>',
        context,
        script: script,
      ),
      '1970-01-01 08:00:00',
    );
  });

  test('动态表单动作、菜单与 Cookie 跨会话保存，取消不提交状态', () async {
    final dir = await Directory.systemTemp.createTemp('dynamic-auth-');
    addTearDown(() => dir.delete(recursive: true));
    final store = BookSourceCookieStore(directoryProvider: () async => dir);
    final browser = _Browser();
    final auth = BookSourceAuthService(launcher: browser);
    final rows = await auth.rowsFor(_source, store);
    expect(rows.map((row) => row.type), ['password', 'select', 'button']);
    expect(rows[1].defaultValue, '甲');
    final values = {'密钥': ' key== ', '接口': '乙'};
    final changed = await auth.runAction(
      _source,
      store,
      values,
      rows[1].action,
    );
    expect(changed.success, isTrue);
    expect(changed.message, '已切换乙');
    expect(store.sourceValues(_source)['mode'], '乙');
    browser.redirect = true;
    expect(
      (await auth.runAction(_source, store, values, 'webLogin()')).success,
      isTrue,
    );
    expect(browser.openedUrl, 'https://web.example.test/login');
    expect(store.sourceVariable(_source), contains('sessionid=sample=='));
    expect(store.sourceValues(_source)['session'], 'sample==');
    final extra = await auth.runAction(_source, store, values, 'submenu()');
    expect(extra.rebuildView, isTrue);
    expect((await auth.rowsFor(_source, store)).single.name, '主题');
    expect((await auth.rowsFor(_source, store))[1].defaultValue, '乙');
    expect(
      (await auth.loginWithCredentials(_source, store, values)).success,
      isTrue,
    );
    expect(store.sourceValues(_source)['confirmed'], ' key== ');
    final restored = BookSourceCookieStore(directoryProvider: () async => dir);
    await restored.load();
    expect(restored.sourceValues(_source)['mode'], '乙');
    expect(restored.loginInfo(_source)['密钥'], ' key== ');
    browser.cancel = true;
    expect(
      (await auth.runAction(_source, restored, {
        '密钥': 'changed',
      }, 'webLogin()')).success,
      isFalse,
    );
    expect(restored.loginInfo(_source)['密钥'], ' key== ');
    await auth.logout(_source, restored);
    expect(restored.sourceValues(_source), isEmpty);
    expect(restored.cookieHeader('web.example.test'), isEmpty);
  });

  // 原书源只从显式指定的本地路径读取，避免把第三方脚本和密钥提交进仓库。
  const sourcePath = String.fromEnvironment('BOOK_SOURCE_JSON');
  test('本地书源动态登录与小说搜索、详情、目录、正文走正式入口', () async {
    final raw = jsonDecode(await File(sourcePath).readAsString());
    final source = BookSource.fromJson(
      Map<String, Object?>.from(raw is List ? raw.first as Map : raw as Map),
    );
    final dir = await Directory.systemTemp.createTemp('local-source-auth-');
    addTearDown(() => dir.delete(recursive: true));
    final store = BookSourceCookieStore(directoryProvider: () async => dir);
    final auth = BookSourceAuthService(launcher: _Browser());
    final rows = await auth.rowsFor(source, store);
    expect(rows.any((row) => row.type == 'password'), isTrue);
    final values = {
      for (final row in rows.where((row) => row.input))
        row.name: row.type == 'password' ? 'sample-key' : row.defaultValue,
    };
    expect(
      (await auth.loginWithCredentials(source, store, values)).success,
      isTrue,
    );
    final web = rows.firstWhere((row) => row.action.contains('fqWebLogin'));
    final webResult = await auth.runAction(source, store, values, web.action);
    expect(webResult.success, isTrue);
    expect(webResult.message, contains('Cookie'));
    expect(store.sourceVariable(source), contains('sessionid='));
    final client = BookSourceHttpClient(
      cookieStore: store,
      client: MockClient((request) async {
        expect(request.url.queryParameters['api_key'], 'sample-key');
        Map<String, Object?> data;
        if (request.url.path.endsWith('/search')) {
          expect(request.url.queryParameters['key'], '测试');
          data = {
            'search_tabs': [
              {
                'tab_type': 3,
                'data': [
                  {
                    'book_data': [
                      {'book_id': '123456', 'book_name': '测试书', 'author': '作者'},
                    ],
                  },
                ],
              },
            ],
            'next_passback': '下一页',
          };
        } else if (request.url.path.endsWith('/detail')) {
          data = {
            'data': {
              'book_id': '123456',
              'book_name': '测试书',
              'author': '作者',
              'abstract': '测试简介',
              'book_search_visible': true,
            },
          };
        } else if (request.url.path.endsWith('/catalog')) {
          data = {
            'data': {
              'item_data_list': [
                {'item_id': '7654321', 'title': '第一章', 'first_pass_time': 0},
              ],
            },
          };
        } else if (request.url.path.endsWith('/content')) {
          expect(request.url.queryParameters['book_id'], '123456');
          expect(request.url.queryParameters['item_id'], '7654321');
          data = {
            'data': {'content': '<p>第一章测试正文。</p>'},
          };
        } else {
          data = {'code': 0, 'data': <String, Object?>{}};
        }
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final service = BookSourceService(
      cookieStore: store,
      httpClient: client,
      chapterContentStore: OnlineChapterContentStore(
        directoryProvider: () async => dir,
      ),
    );
    addTearDown(service.dispose);
    const sampleChapter = OnlineChapter(
      index: 0,
      title: '示例',
      url: 'data:,123',
    );
    final before = service.chapterContentRevision(source, sampleChapter);
    await auth.loginWithCredentials(source, store, values);
    expect(
      service.chapterContentRevision(source, sampleChapter),
      isNot(before),
    );
    expect(
      service.discoverCategories(source).map((category) => category.title),
      contains('巅峰榜单'),
    );
    final books = await service.search(source, '测试');
    expect(books.single.name, '测试书');
    expect(store.sourceValues(source).values, contains('下一页'));
    final detail = await service.loadBookInfo(source, books.single);
    expect(detail.tocUrl, contains('book_id=123456'));
    final toc = await service.fetchToc(source, detail);
    expect(toc.single.url, startsWith('data:'));
    expect(
      await service.fetchChapterContent(source, toc.single, detail.bookUrl),
      contains('第一章测试正文'),
    );
  }, skip: sourcePath.isEmpty);
}
