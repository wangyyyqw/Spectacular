import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/book_source/book_source_auth.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_script.dart';

class _FakeLoginLauncher implements BookSourceLoginLauncher {
  _FakeLoginLauncher(this.result);

  final BookSourceLoginPageResult? result;
  String? openedUrl;
  String? openedTitle;

  @override
  Future<BookSourceLoginPageResult?> open({
    required String url,
    required String title,
  }) async {
    openedUrl = url;
    openedTitle = title;
    return result;
  }
}

const _source = BookSource(
  id: 'fanqie',
  name: '番茄',
  sourceUrl: 'https://fanqienovel.com',
  loginUrl: 'https://fanqienovel.com',
  searchUrl: 'https://fanqienovel.com/search',
  search: BookListRule(),
  bookInfo: BookInfoRule(),
  toc: TocRule(),
  content: ContentRule(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('指定 key 按源保存、重启恢复，原生脚本读取并生成请求头', () async {
    final directory = await Directory.systemTemp.createTemp('auth-key-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    final source = _source.copyWith(
      id: 'key-source',
      loginUrl: '',
      loginUi: '[{"name":"API key","type":"password"},{"name":"帮助","type":"button"}]',
      header: '@js: JSON.stringify({"X-API-Key":source.getLoginInfoMap().get("API key")})',
    );
    final auth = BookSourceAuthService();
    expect(auth.fieldsFor(source).map((field) => field.name), ['API key']);
    expect(
      (await auth.loginWithCredentials(source, store, {
        'API key': ' key== ',
      })).success,
      isTrue,
    );
    final restored = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    await restored.load();
    expect(restored.loginInfo(source)['API key'], ' key== ');
    expect(await restored.hasLoginFor(source), isTrue);
    final script = QuickJsBookSourceScriptSession(
      jsLib: '',
      sourceKey: source.sourceUrl,
      loginInfo: restored.loginInfo(source),
    );
    expect(
      script.evaluate(
        'source.getLoginInfoMap().get("API key")',
        result: '',
        variables: const {},
        resolveString: (_) => '',
        resolveList: (_) => [],
      ),
      ' key== ',
    );
    script.dispose();
    final client = BookSourceHttpClient(
      cookieStore: restored,
      client: MockClient((request) async {
        expect(request.headers['X-API-Key'], ' key== ');
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    await client.fetchText(source, 'https://fanqienovel.com/test');
    await client.fetchText(
      source.copyWith(
        header: jsonEncode({
          'X-API-Key': '{{source.getLoginInfoMap().get("API key")}}',
        }),
      ),
      'https://fanqienovel.com/test',
    );
    await auth.logout(source, restored);
    expect(await restored.hasLoginFor(source), isFalse);
    expect(restored.loginInfo(source), isEmpty);
  });

  test('原生HashMap登录按脚本发送一次JSON，Cookie可用于发现，错误不泄露凭据', () async {
    final directory = await Directory.systemTemp.createTemp('auth-map-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    final source = _source.copyWith(
      loginUi: '[{"name":"用户名","type":"text"},{"name":"密码","type":"password"}]',
      loginUrl: r"""var BASE=String(baseUrl).replace(/\/+$/,'');
function hdr(){var h=new Packages.java.util.HashMap();h.put('Content-Type','application/json');h.put('Accept','application/json');return h;}
function body(r){return r&&typeof r.body==='function'?r.body():r;}
function login(){var m=source.getLoginInfoMap();var d=JSON.parse(body(java.post(BASE+'/reader-auth/login',JSON.stringify({username:m.get('用户名'),password:m.get('密码')}),hdr()))||'{}');if(d.error)throw d.error;}
""",
      loginCheckJs: '',
    );
    var posts = 0;
    var fail = false;
    final client = BookSourceHttpClient(
      cookieStore: store,
      client: MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          expect(request.headers['Content-Type'], contains('application/json'));
          expect(request.headers['Accept'], 'application/json');
          expect(jsonDecode(request.body), {
            'username': '用户',
            'password': ' 密码 ',
          });
          return http.Response(
            fail ? '{"error":"凭据错误"}' : '{"user":{"username":"用户"}}',
            fail ? 401 : 200,
            headers: {
              'content-type': 'application/json; charset=utf-8',
              if (!fail) 'set-cookie': 'session=valid; Path=/',
            },
          );
        }
        expect(request.headers['Cookie'], contains('session=valid'));
        return http.Response('{"rows":[]}', 200);
      }),
    );
    addTearDown(client.close);
    final auth = BookSourceAuthService();
    expect(
      (await auth.loginWithCredentials(source, store, {
        '用户名': '用户',
        '密码': ' 密码 ',
      }, httpClient: client)).success,
      isTrue,
    );
    expect(posts, 1);
    expect(store.loginInfo(source)['密码'], ' 密码 ');
    await client.fetchText(source, '${source.baseUrl}/reader-api/search');
    fail = true;
    final failed = await auth.loginWithCredentials(source, store, {
      '用户名': '用户',
      '密码': ' 密码 ',
    }, httpClient: client);
    expect(failed.success, isFalse);
    expect(failed.message, isNot(contains(' 密码 ')));
    expect(store.cookieHeader(source.baseUrl), contains('session=valid'));
  });

  test('脚本账号密码登录按声明执行POST，Cookie用于后续请求，失败不保存凭据', () async {
    final directory = await Directory.systemTemp.createTemp('auth-account-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    final source = _source.copyWith(
      id: 'account',
      loginUi: '[{"name":"账号","type":"text"},{"name":"密码","type":"password"}]',
      loginUrl: '''@js:
function login() {
 var info = source.getLoginInfoMap();
 var body = JSON.stringify({username:info.get("账号"),password:info.get("密码")});
 var result = JSON.parse(java.post(source.key+"/reader-auth/login",body,{"Content-Type":"application/json"}).body());
 if (!result.success) throw "登录失败";
}
''',
      loginCheckJs: '@js: JSON.parse(result).success',
    );
    var fail = false;
    var posts = 0;
    final client = BookSourceHttpClient(
      cookieStore: store,
      client: MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          expect(request.url.path, '/reader-auth/login');
          expect(jsonDecode(request.body), {
            'username': '用户',
            'password': ' 密码 ',
          });
          return http.Response(
            jsonEncode({'success': !fail}),
            200,
            headers: fail ? {} : {'set-cookie': 'session=valid; Path=/'},
          );
        }
        if (fail) {
          expect(request.headers.containsKey('Cookie'), isFalse);
        } else {
          expect(request.headers['Cookie'], contains('session=valid'));
        }
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    final auth = BookSourceAuthService();
    final result = await auth.loginWithCredentials(source, store, {
      '账号': '用户',
      '密码': ' 密码 ',
    }, httpClient: client);
    expect(result.success, isTrue, reason: result.message);
    expect(posts, 1);
    await client.fetchText(source, 'https://fanqienovel.com/chapters');
    await auth.logout(source, store);
    fail = true;
    await client.fetchText(source, 'https://fanqienovel.com/chapters');
    expect(
      (await auth.loginWithCredentials(source, store, {
        '账号': '用户',
        '密码': ' 密码 ',
      }, httpClient: client)).success,
      isFalse,
    );
    expect(store.loginInfo(source), isEmpty);
  });

  test('key 核验允许空网关使用脚本默认值，失败保留已有登录信息', () async {
    final directory = await Directory.systemTemp.createTemp('auth-check-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    final source = _source.copyWith(
      id: 'key-check',
      loginUrl: '',
      loginUi: jsonEncode([
        {'name': 'key', 'type': 'text'},
        {'name': '网关地址（留空使用默认）', 'type': 'text'},
      ]),
      header: '<js>JSON.stringify({"X-Key":source.getLoginInfoMap().get("key")})</js>',
      loginCheckJs: '''
var gateway = source.getLoginInfoMap().get("网关地址（留空使用默认）") || source.key;
var checked = JSON.parse(java.ajax(gateway+"/check"));
if (!checked.success) throw "无效 key";
source.putLoginHeader(JSON.stringify({Authorization:"Bearer "+checked.token}));
source.setVariable("已核验");
true;
''',
    );
    var checks = 0;
    var fail = false;
    final client = BookSourceHttpClient(
      cookieStore: store,
      client: MockClient((request) async {
        if (request.url.path == '/check') {
          checks++;
          expect(request.url.host, 'fanqienovel.com');
          expect(request.headers['X-Key'], fail ? 'bad-key' : 'new-key');
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response(
            jsonEncode({'success': !fail, 'token': 'new-token'}),
            200,
            headers: fail ? {'set-cookie': 'session=rejected'} : {},
          );
        }
        expect(request.headers['Authorization'], 'Bearer new-token');
        expect(request.headers['X-Key'], 'new-key');
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    await store.saveSourceLogin(
      source,
      info: {
        'key': 'old-key',
        '网关地址（留空使用默认）': 'https://old-gateway.example.test',
      },
      header: '{"Authorization":"Bearer old-token"}',
    );
    final auth = BookSourceAuthService();
    expect(
      (await auth.loginWithCredentials(source, store, {
        'key': 'new-key',
        '网关地址（留空使用默认）': '',
      }, httpClient: client)).success,
      isTrue,
    );
    expect(checks, 1);
    expect(store.loginInfo(source)['网关地址（留空使用默认）'], '');
    expect(store.sourceVariable(source), '已核验');
    await client.fetchText(source, 'https://fanqienovel.com/chapters');
    fail = true;
    expect(
      (await auth.loginWithCredentials(source, store, {
        'key': 'bad-key',
        '网关地址（留空使用默认）': '',
      }, httpClient: client)).success,
      isFalse,
    );
    expect(store.loginInfo(source)['key'], 'new-key');
    expect(store.loginInfo(source)['网关地址（留空使用默认）'], '');
    expect(store.loginHeader(source), contains('new-token'));
    expect(await store.hasCookiesFor(source), isFalse);
  });

  test('未声明登录表单时自动补出的账号密码仍需填写', () async {
    final directory = await Directory.systemTemp.createTemp('auth-required-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    final source = _source.copyWith(
      loginUrl: '@js:java.ajax("/reader-auth/login")',
    );
    final auth = BookSourceAuthService();
    final client = BookSourceHttpClient(
      cookieStore: store,
      client: MockClient((request) async {
        fail('账号密码为空时不应发送登录请求');
      }),
    );
    addTearDown(client.close);
    for (final entry in {
      '账号': {'账号': ' ', '密码': '密码'},
      '密码': {'账号': '用户', '密码': ''},
    }.entries) {
      final result = await auth.loginWithCredentials(
        source,
        store,
        entry.value,
        httpClient: client,
      );
      expect(result.success, isFalse);
      expect(result.message, '请输入${entry.key}');
      expect(store.loginInfo(source), isEmpty);
    }
  });

  test('只声明账号接口的旧源沿用参考项目 JSON 登录协议', () async {
    final directory = await Directory.systemTemp.createTemp('auth-fallback-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    final source = _source.copyWith(
      loginUrl: '@js:java.ajax("/reader-auth/login")',
    );
    final client = BookSourceHttpClient(
      cookieStore: store,
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/reader-auth/login');
        expect(request.headers['Content-Type'], 'application/json');
        expect(jsonDecode(request.body), {'username': '账号', 'password': '密码'});
        return http.Response(
          '{"success":true}',
          200,
          headers: {'set-cookie': 'session=valid'},
        );
      }),
    );
    addTearDown(client.close);
    expect(
      (await BookSourceAuthService().loginWithCredentials(source, store, {
        '账号': '账号',
        '密码': '密码',
      }, httpClient: client)).success,
      isTrue,
    );
  });

  test('登录页返回 Cookie 后保存到书源域名', () async {
    final directory = await Directory.systemTemp.createTemp('auth-login-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    final launcher = _FakeLoginLauncher(
      const BookSourceLoginPageResult(
        cookieHeader: 'sessionid=abc; sid_tt=xyz',
        url: 'https://fanqienovel.com/',
      ),
    );
    final auth = BookSourceAuthService(launcher: launcher);

    final result = await auth.login(_source, store);

    expect(result.success, isTrue);
    expect(result.message, contains('2 项 Cookie'));
    expect(launcher.openedUrl, 'https://fanqienovel.com');
    expect(launcher.openedTitle, '番茄');
    expect(store.cookieValue('fanqienovel.com', 'sessionid'), 'abc');
    expect(await store.hasCookiesFor(_source), isTrue);
    expect(await store.hasLoginFor(_source), isTrue);
  });

  test('取消登录不写入 Cookie', () async {
    final directory = await Directory.systemTemp.createTemp('auth-cancel-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    final auth = BookSourceAuthService(launcher: _FakeLoginLauncher(null));

    final result = await auth.login(_source, store);

    expect(result.success, isFalse);
    expect(result.message, '已取消登录');
    expect(await store.hasCookiesFor(_source), isFalse);
    expect(await store.hasLoginFor(_source), isFalse);
  });

  test('登录地址支持从脚本或登录配置中提取 HTTP 地址', () {
    const source = BookSource(
      id: 'js-login',
      name: '脚本登录',
      sourceUrl: 'https://example.com',
      loginUrl: '@js:"https://example.com/login?from=reader";',
      searchUrl: 'https://example.com/search',
      search: BookListRule(),
      bookInfo: BookInfoRule(),
      toc: TocRule(),
      content: ContentRule(),
    );
    final auth = BookSourceAuthService(launcher: _FakeLoginLauncher(null));

    expect(auth.loginUrlFor(source), 'https://example.com/login?from=reader');
  });

  test('Cookie 值中的等号不会被截断', () {
    final auth = BookSourceAuthService(launcher: _FakeLoginLauncher(null));

    expect(auth.parseLoginCookies('sessionid=abc==; uid=42'), <String, String>{
      'sessionid': 'abc==',
      'uid': '42',
    });
  });
}
