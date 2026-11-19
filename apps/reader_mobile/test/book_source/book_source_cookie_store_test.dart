import 'dart:io';

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
