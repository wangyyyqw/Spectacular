import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/book_source_auth.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';

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
