import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';

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
  test('后台快照合并仅修改实际变动键，保留前台新设置', () async {
    final directory = await Directory.systemTemp.createTemp('cookie-worker-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    await store.load();
    await store.saveSourceValues(_source, {'甲': '旧', '乙': '旧'});
    final before = store.detachedSnapshot;
    final worker = BookSourceCookieStore.detached(before);
    await worker.saveSourceValues(_source, {'甲': '后台', '乙': '后台', '丙': '新'});
    await store.saveSourceValues(_source, {'甲': '前台'});
    await store.mergeDetachedChanges(before, worker.detachedSnapshot);
    expect(store.sourceValues(_source), {'甲': '前台', '乙': '后台', '丙': '新'});
    expect(worker.sourceValues(_source)['甲'], '后台');
  });
  test('旧版登录文件升级保留凭据与 Cookie，源设置合并并可重新读取', () async {
    final directory = await Directory.systemTemp.createTemp('cookie-upgrade-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/book_sources/cookies.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'version': 3,
        'loginInfo': {
          'fanqie': {'密钥': '原密钥'},
        },
        'loginHeaders': {'fanqie': '{"X-Key":"原密钥"}'},
        'variables': {'fanqie': '原变量'},
        'cookies': {
          'fanqienovel.com': {'sessionid': '原会话'},
        },
        'loginDomains': ['fanqienovel.com'],
      }),
    );
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    await store.saveSourceValues(_source, {'接口': '甲'});
    await store.saveSourceValues(_source, {'频道': '女频'});
    final restored = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    await restored.load();
    expect(restored.loginInfo(_source), {'密钥': '原密钥'});
    expect(restored.loginHeader(_source), '{"X-Key":"原密钥"}');
    expect(restored.sourceVariable(_source), '原变量');
    expect(restored.cookieHeader('fanqienovel.com'), 'sessionid=原会话');
    expect(restored.sourceValues(_source), {'接口': '甲', '频道': '女频'});
    expect(restored.settingsRevision(_source), 0);
  });

  test('Set-Cookie 持久化并在新实例中按域名复用', () async {
    final directory = await Directory.systemTemp.createTemp('cookie-store-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );

    await store.absorbSetCookie(
      _source,
      Uri.parse('https://fanqienovel.com/login'),
      'sessionid=abc; Path=/; Domain=.fanqienovel.com; HttpOnly, '
      'uid=42; Path=/',
    );

    expect(store.cookieValue('fanqienovel.com', 'sessionid'), 'abc');
    expect(await store.hasCookiesFor(_source), isTrue);
    expect(await store.hasLoginFor(_source), isFalse);

    final reloaded = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    await reloaded.load();
    expect(reloaded.cookieValue('fanqienovel.com', 'sessionid'), 'abc');
    expect(await reloaded.hasLoginFor(_source), isFalse);
    final cookies = await reloaded.cookiesFor(
      _source,
      Uri.parse('https://api.fanqienovel.com/reading/bookapi'),
    );
    expect(cookies, <String, String>{'sessionid': 'abc', 'uid': '42'});
  });

  test('网页登录 Cookie 可保存、读取并清除', () async {
    final directory = await Directory.systemTemp.createTemp('cookie-login-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );

    await store.saveLoginCookies('fanqienovel.com', <String, String>{
      'sessionid': 'token=with=equals',
      'sid_tt': 'abc',
    });

    expect(
      store.cookieValue('fanqienovel.com', 'sessionid'),
      'token=with=equals',
    );
    expect(store.cookieHeader('fanqienovel.com'), contains('sid_tt=abc'));
    expect(await store.hasCookiesFor(_source), isTrue);
    expect(await store.hasLoginFor(_source), isTrue);

    final reloaded = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    expect(await reloaded.hasLoginFor(_source), isTrue);

    await store.clearForSource(_source);
    expect(store.cookieValue('fanqienovel.com', 'sessionid'), '');
    expect(await store.hasCookiesFor(_source), isFalse);
    expect(await store.hasLoginFor(_source), isFalse);
  });

  test('过期 Cookie 会从存储中移除', () async {
    final directory = await Directory.systemTemp.createTemp('cookie-expire-');
    addTearDown(() => directory.delete(recursive: true));
    final store = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );

    await store.saveLoginCookies('example.com', <String, String>{
      'session': 'abc',
    });
    await store.absorbSetCookie(
      _source,
      Uri.parse('https://example.com/logout'),
      'session=; Max-Age=0; Path=/',
    );

    expect(store.cookieValue('example.com', 'session'), '');
  });
}
