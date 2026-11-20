import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/book_source_auth.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_store.dart';
import 'package:reader_mobile/book_source/online_book_controller.dart';
import 'package:reader_mobile/book_source/online_source_page.dart';
import 'package:reader_mobile/library/library_store.dart';

class _Auth extends BookSourceAuthService {
  Map<String, String>? received;

  @override
  Future<BookSourceLoginResult> loginWithCredentials(
    BookSource source,
    BookSourceCookieStore store,
    Map<String, String> values, {
    BookSourceHttpClient? httpClient,
  }) async {
    received = values;
    return const BookSourceLoginResult(success: true, message: '登录信息已保存');
  }

  @override
  Future<BookSourceLoginResult> login(
    BookSource source,
    BookSourceCookieStore store,
  ) async {
    throw StateError('输入登录不应打开网页登录');
  }
}

void main() {
  testWidgets('登录面板使用源字段，密码和 key 隐藏并原样交给登录入口', (tester) async {
    final dir = Directory.systemTemp.createTempSync('source-login-ui-');
    final sourceStore = BookSourceStore(directoryProvider: () async => dir);
    final auth = _Auth();
    final controller = OnlineBookController(
      library: LibraryStore.memory(),
      store: sourceStore,
      cookieStore: BookSourceCookieStore(directoryProvider: () async => dir),
      authService: auth,
    );
    addTearDown(() {
      controller.dispose();
      dir.deleteSync(recursive: true);
    });
    late BookSource source;
    await tester.runAsync(() async {
      source = await sourceStore.importText(
        jsonEncode({
          'bookSourceName': '账号源',
          'bookSourceUrl': 'https://example.test',
          'searchUrl': 'https://example.test/search',
          'ruleSearch': {
            'bookList': '.book',
            'name': 'a@text',
            'bookUrl': 'a@href',
          },
          'ruleToc': {
            'chapterList': 'li',
            'chapterName': 'a@text',
            'chapterUrl': 'a@href',
          },
          'ruleContent': {'content': '#content'},
          'loginUi': [
            {'name': '账号', 'type': 'text'},
            {'name': '密码', 'type': 'password'},
            {'name': '指定 key', 'type': 'text'},
            {'name': '帮助', 'type': 'button'},
          ],
        }),
      );
      await controller.initialize();
    });
    await tester.pumpWidget(
      MaterialApp(home: OnlineSourcePage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('online-source-login-${source.id}')));
    await tester.pumpAndSettle();
    final account = find.byKey(const ValueKey('online-login-field-账号'));
    final password = find.byKey(const ValueKey('online-login-field-密码'));
    final key = find.byKey(const ValueKey('online-login-field-指定 key'));
    expect(tester.widget<TextField>(account).obscureText, isFalse);
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    expect(tester.widget<TextField>(key).enableSuggestions, isFalse);
    expect(tester.widget<TextField>(key).obscureText, isTrue);
    expect(find.byKey(const ValueKey('online-login-field-帮助')), findsNothing);
    await tester.enterText(account, '用户');
    await tester.enterText(password, ' 密码 ');
    await tester.enterText(key, ' key== ');
    await tester.tap(find.byKey(const ValueKey('online-login-submit')));
    await tester.pumpAndSettle();
    expect(auth.received, {'账号': '用户', '密码': ' 密码 ', '指定 key': ' key== '});
    expect(controller.isLoggedIn(source), isTrue);
    expect(tester.takeException(), isNull);
  });
}
