import 'package:flutter/services.dart';

import 'book_source_cookie_store.dart';
import 'book_source_models.dart';

/// 网页登录页返回的 Cookie。
class BookSourceLoginPageResult {
  const BookSourceLoginPageResult({
    required this.cookieHeader,
    required this.url,
  });

  final String cookieHeader;
  final String url;
}

/// 打开书源网页登录页。
abstract class BookSourceLoginLauncher {
  Future<BookSourceLoginPageResult?> open({
    required String url,
    required String title,
  });
}

/// Android 原生 WebView 登录页。
class AndroidBookSourceLoginLauncher implements BookSourceLoginLauncher {
  const AndroidBookSourceLoginLauncher();

  static const MethodChannel _channel = MethodChannel(
    'com.spectacular.reader_mobile/online_source_login',
  );

  @override
  Future<BookSourceLoginPageResult?> open({
    required String url,
    required String title,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>('login', {
      'url': url,
      'title': title,
    });
    if (result == null) return null;
    return BookSourceLoginPageResult(
      cookieHeader: '${result['cookie'] ?? ''}',
      url: '${result['url'] ?? url}',
    );
  }
}

/// 书源登录结果。
class BookSourceLoginResult {
  const BookSourceLoginResult({required this.success, required this.message});

  final bool success;
  final String message;
}

/// 管理书源网页登录与 Cookie。
class BookSourceAuthService {
  BookSourceAuthService({BookSourceLoginLauncher? launcher})
    : launcher = launcher ?? const AndroidBookSourceLoginLauncher();

  final BookSourceLoginLauncher launcher;

  Future<BookSourceLoginResult> login(
    BookSource source,
    BookSourceCookieStore store,
  ) async {
    final loginUrl = loginUrlFor(source);
    if (loginUrl.isEmpty) {
      return const BookSourceLoginResult(
        success: false,
        message: '该源没有可用的网页登录地址',
      );
    }
    final page = await launcher.open(url: loginUrl, title: source.name);
    if (page == null) {
      return const BookSourceLoginResult(success: false, message: '已取消登录');
    }
    final cookies = parseLoginCookies(page.cookieHeader);
    if (cookies.isEmpty) {
      return const BookSourceLoginResult(
        success: false,
        message: '登录页未返回 Cookie，请确认已完成登录',
      );
    }
    final domain =
        Uri.tryParse(page.url)?.host ?? Uri.tryParse(loginUrl)?.host ?? '';
    await store.saveLoginCookies(domain, cookies);
    return BookSourceLoginResult(
      success: true,
      message: '登录成功，已保存 ${cookies.length} 项 Cookie',
    );
  }

  Future<void> logout(BookSource source, BookSourceCookieStore store) {
    return store.clearForSource(source);
  }

  String loginUrlFor(BookSource source) {
    for (final value in <String>[
      source.loginUrl,
      source.loginUi,
      source.sourceUrl,
    ]) {
      final direct = value.trim();
      if (_isHttpUrl(direct)) return _cleanUrl(direct);
      final match = RegExp(r'''https?://[^\s"'<>]+''').firstMatch(value);
      if (match != null) return _cleanUrl(match.group(0) ?? '');
    }
    return '';
  }

  Map<String, String> parseLoginCookies(String raw) {
    final cookies = <String, String>{};
    for (final part in raw.split(';')) {
      final text = part.trim();
      final index = text.indexOf('=');
      if (index <= 0) continue;
      final name = text.substring(0, index).trim();
      final value = text.substring(index + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) cookies[name] = value;
    }
    return cookies;
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  String _cleanUrl(String value) {
    return value.trim().replaceFirst(RegExp(r'''[,;)\]}。，；]+$'''), '').trim();
  }
}
