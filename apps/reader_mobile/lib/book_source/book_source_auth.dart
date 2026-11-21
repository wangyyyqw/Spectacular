import 'dart:convert';

import 'package:flutter/services.dart';

import 'book_source_cookie_store.dart';
import 'book_source_models.dart';
import 'book_source_login_config.dart';
import 'book_source_http_client.dart';
import 'book_source_script.dart';

/// 网页登录页返回的 Cookie。
class BookSourceLoginPageResult {
  const BookSourceLoginPageResult({
    required this.cookieHeader,
    required this.url,
    this.cookiesByDomain = const {},
  });

  final String cookieHeader;
  final String url;
  final Map<String, String> cookiesByDomain;
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
      cookiesByDomain: {
        for (final entry in (result['cookiesByDomain'] as Map? ?? {}).entries)
          '${entry.key}': '${entry.value}',
      },
    );
  }
}

/// 书源登录结果。
class BookSourceLoginResult {
  const BookSourceLoginResult({
    required this.success,
    required this.message,
    this.rebuildView = false,
  });

  final bool success;
  final String message;
  final bool rebuildView;
}

/// 管理书源输入登录、网页登录与登录信息。
class BookSourceAuthService {
  BookSourceAuthService({BookSourceLoginLauncher? launcher})
    : launcher = launcher ?? const AndroidBookSourceLoginLauncher();

  final BookSourceLoginLauncher launcher;

  QuickJsBookSourceScriptSession createScript(
    BookSource source,
    BookSourceCookieStore store, {
    Map<String, String>? info,
  }) => QuickJsBookSourceScriptSession(
    jsLib: source.jsLib,
    sourceKey: source.sourceUrl,
    loginInfo: info ?? store.loginInfo(source),
    loginHeader: store.loginHeader(source),
    sourceVariable: store.sourceVariable(source),
    sourceValues: store.sourceValues(source),
    cookieProvider: store.cookieValue,
    cookieHeaderProvider: store.cookieHeader,
  );

  Future<List<BookSourceLoginField>> rowsFor(
    BookSource source,
    BookSourceCookieStore store,
  ) async {
    await store.load();
    final script = createScript(source, store);
    try {
      final rows = bookSourceLoginRows(source, script: script);
      await store.saveSourceValues(source, script.sourceValueChanges);
      return rows.isEmpty ? fieldsFor(source) : rows;
    } finally {
      script.dispose();
    }
  }

  /// 执行源声明的按钮或选择动作，成功后立即保存设置。
  Future<BookSourceLoginResult> runAction(
    BookSource source,
    BookSourceCookieStore store,
    Map<String, String> values,
    String action, {
    BookSourceHttpClient? httpClient,
  }) async {
    await store.load();
    final script = createScript(source, store, info: values);
    final client = httpClient ?? BookSourceHttpClient(cookieStore: store);
    try {
      final uri = Uri.tryParse(action);
      final code =
          uri != null &&
              const {'http', 'https'}.contains(uri.scheme) &&
              uri.host.isNotEmpty
          ? 'java.startBrowser(${jsonEncode(action)}, ${jsonEncode(source.name)})'
          : '${bookSourceLoginScript(source)}\n${unwrapBookSourceScript(action)}';
      await _execute(source, store, script, client, code, '');
      await store.saveSourceValues(source, script.sourceValueChanges);
      await store.saveSourceLogin(
        source,
        info: script.loginInfo,
        header: script.loginHeader,
        variable: script.sourceVariable,
        invalidateContent: true,
      );
      return BookSourceLoginResult(
        success: true,
        message: script.messages.join('\n').trim(),
        rebuildView: script.rebuildLoginView,
      );
    } on Object {
      return const BookSourceLoginResult(
        success: false,
        message: '书源操作失败，请检查网络和书源配置',
      );
    } finally {
      script.dispose();
      if (httpClient == null) client.close();
    }
  }

  Future<({String value, String body})> _execute(
    BookSource source,
    BookSourceCookieStore store,
    QuickJsBookSourceScriptSession script,
    BookSourceHttpClient client,
    String code,
    String result, {
    bool formResult = true,
  }) async {
    var body = result;
    for (var pass = 0; pass < 8; pass++) {
      final value = script.evaluate(
        code,
        result: result,
        variables: {
          'baseUrl': source.baseUrl,
          if (formResult) '_resultJson': jsonEncode(script.loginInfo),
        },
        resolveString: (_) => '',
        resolveList: (_) => const [],
      );
      final requests = script.takePendingRequests();
      final browsers = script.takeBrowserRequests();
      for (final browser in browsers) {
        final url = Uri.parse(source.baseUrl).resolve(browser.url);
        if (!const {'http', 'https'}.contains(url.scheme) || url.host.isEmpty) {
          throw const BookSourceException('网页登录地址无效');
        }
        final page = await launcher.open(
          url: url.toString(),
          title: browser.title.isEmpty ? source.name : browser.title,
        );
        if (page == null && browser.wait) {
          throw const BookSourceException('已取消网页登录');
        }
        if (page != null) {
          await _savePageCookies(source, page, store);
        }
        script.rememberBrowser(browser.key, page?.url ?? '');
      }
      if (requests.isEmpty && !browsers.any((browser) => browser.wait)) {
        return (value: value, body: body);
      }
      for (final request in requests) {
        final response = await client.fetchText(
          source.copyWith(header: ''),
          Uri.parse(source.baseUrl).resolve(request.url).toString(),
          headers: {
            ...evaluateBookSourceHeaders(source.header, script, source.baseUrl),
            ...request.headers,
          },
          options: {
            'method': request.method,
            'body': request.body,
            'useLoginHeader': false,
          },
        );
        _requireSuccessfulLoginResponse(response.body);
        body = response.body;
        script.rememberResponse(request.key, body);
      }
    }
    throw const BookSourceException('登录脚本请求未完成');
  }

  List<BookSourceLoginField> fieldsFor(BookSource source) {
    final fields = bookSourceLoginFields(source);
    if (fields.isNotEmpty) return fields;
    if (bookSourceAccountEndpoint(source).isNotEmpty) {
      return const [
        BookSourceLoginField('账号', 'text', ''),
        BookSourceLoginField('密码', 'password', ''),
      ];
    }
    return const [];
  }

  Future<BookSourceLoginResult> loginWithCredentials(
    BookSource source,
    BookSourceCookieStore store,
    Map<String, String> values, {
    BookSourceHttpClient? httpClient,
  }) async {
    await store.load();
    final configuredFields = (await rowsFor(
      source,
      store,
    )).where((row) => row.input).toList();
    final fields = configuredFields.isNotEmpty
        ? configuredFields
        : fieldsFor(source);
    if (fields.isEmpty) {
      return const BookSourceLoginResult(success: false, message: '书源没有登录输入配置');
    }
    final info = {
      ...store.loginInfo(source),
      if (source.loginUi.trim().startsWith('@js:') ||
          source.loginUi.trim().startsWith('<js>'))
        ...values,
    };
    for (final field in fields) {
      final value = values[field.name] ?? field.defaultValue;
      // 自定义字段的空值交给源脚本处理，仅自动补出的账号密码必填。
      if (source.loginUi.trim().isEmpty && value.trim().isEmpty) {
        return BookSourceLoginResult(
          success: false,
          message: '请输入${field.name}',
        );
      }
      // 密码等秘密保留原值，不能因 trim 改变凭据。
      info[field.name] = field.secret ? value : value.trim();
    }
    final client = httpClient ?? BookSourceHttpClient(cookieStore: store);
    QuickJsBookSourceScriptSession? script;
    var committed = false;
    final previousCookies = store.cookieHeader(source.baseUrl);
    try {
      final endpoint = bookSourceAccountEndpoint(source);
      final raw = source.loginUrl.trim();
      // 部分 key 源只声明 loginUi，脚本请求头直接读取输入值。
      if ((raw.isEmpty || raw.startsWith('http')) &&
          source.loginCheckJs.trim().isEmpty) {
        await store.saveSourceLogin(
          source,
          info: info,
          invalidateContent: true,
        );
        committed = true;
        return const BookSourceLoginResult(success: true, message: '登录信息已保存');
      }
      script = createScript(source, store, info: info)..loginHeader = '';
      var code = raw.startsWith('@js:') ? raw.substring(4) : raw;
      if (raw.startsWith('http')) code = '';
      if (code.startsWith('<js>')) {
        code = code.substring(4).replaceFirst(RegExp(r'</js>\s*$'), '');
      }
      if (RegExp(r'function\s+login\s*\(').hasMatch(code)) {
        code = '$code\nlogin();';
      }
      var responseBody = '';
      final loginSource = source.copyWith(header: '');
      Map<String, String> requestHeaders() {
        // 使用正在登录的输入信息求值，不能读取上一账号的持久化凭据。
        return evaluateBookSourceHeaders(
          source.header,
          script!,
          source.baseUrl,
        );
      }

      Future<String> execute(
        String code,
        String result, {
        bool formResult = true,
      }) async {
        final evaluated = await _execute(
          source,
          store,
          script!,
          client,
          code,
          result,
          formResult: formResult,
        );
        responseBody = evaluated.body;
        return evaluated.value;
      }

      // 旧源只暴露晚风账号接口时，沿用参考项目的 JSON 请求协议。
      final usesLoginInfo = code.contains('getLoginInfo');
      if (endpoint.isNotEmpty && !usesLoginInfo) {
        final user = fields.firstWhere(
          (field) => !field.secret,
          orElse: () => fields.first,
        );
        final password = fields.firstWhere(
          (field) => field.type == 'password',
          orElse: () => fields.last,
        );
        final response = await client.fetchText(
          loginSource,
          Uri.parse(source.baseUrl).resolve(endpoint).toString(),
          headers: {...requestHeaders(), 'Content-Type': 'application/json'},
          options: {
            'method': 'POST',
            'useLoginHeader': false,
            'body': jsonEncode({
              'username': info[user.name],
              'password': info[password.name],
            }),
          },
        );
        _requireSuccessfulLoginResponse(response.body);
        responseBody = response.body;
      } else {
        if (await execute(code, '') == 'false') {
          throw const BookSourceException('登录脚本拒绝登录');
        }
      }
      var check = source.loginCheckJs.trim();
      if (check.isNotEmpty) {
        if (check.startsWith('@js:')) check = check.substring(4);
        if (check.startsWith('<js>')) {
          check = check.substring(4).replaceFirst(RegExp(r'</js>\s*$'), '');
        }
        // 状态核验的 result 是响应文本，按钮和 login() 的 result 才是表单。
        final checked = await execute(check, responseBody, formResult: false);
        if (checked == 'false') {
          throw const BookSourceException('登录状态核验未通过');
        }
      }
      if (endpoint.isNotEmpty &&
          source.enabledCookieJar &&
          !await store.hasCookiesFor(source)) {
        throw const BookSourceException('登录响应未返回有效 Cookie');
      }
      await store.saveSourceLogin(
        source,
        info: script.loginInfo,
        header: script.loginHeader,
        variable: script.sourceVariable,
        invalidateContent: true,
      );
      await store.saveSourceValues(source, script.sourceValueChanges);
      committed = true;
      final cookies = store.cookieHeader(source.baseUrl);
      if (cookies.isNotEmpty) {
        await store.saveLoginCookies(
          Uri.parse(source.baseUrl).host,
          parseLoginCookies(cookies),
        );
      }
      return const BookSourceLoginResult(
        success: true,
        message: '登录成功，信息已保存在本机',
      );
    } on Object {
      if (!committed) {
        final afterCookies = store.cookieHeader(source.baseUrl);
        if (afterCookies != previousCookies) {
          final restore = {
            for (final name in parseLoginCookies(afterCookies).keys) name: '',
            ...parseLoginCookies(previousCookies),
          };
          await store.saveLoginCookies(Uri.parse(source.baseUrl).host, restore);
        }
      }
      // 原始异常可能包含脚本、请求或凭据，不展示给日志或界面。
      return const BookSourceLoginResult(
        success: false,
        message: '登录失败，请检查账号、密码或 key 及书源配置',
      );
    } finally {
      script?.dispose();
      if (httpClient == null) client.close();
    }
  }

  void _requireSuccessfulLoginResponse(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map &&
          (data['success'] == false ||
              (data['error'] != null && '${data['error']}'.isNotEmpty))) {
        throw const BookSourceException('服务端拒绝登录');
      }
    } on FormatException {
      // 网页或普通文本响应交给源脚本核验。
    }
  }

  Future<void> _savePageCookies(
    BookSource source,
    BookSourceLoginPageResult page,
    BookSourceCookieStore store,
  ) async {
    final headers = page.cookiesByDomain.isEmpty
        ? {Uri.parse(page.url).host: page.cookieHeader}
        : page.cookiesByDomain;
    for (final entry in headers.entries) {
      await store.saveLoginCookies(
        entry.key,
        parseLoginCookies(entry.value),
        source: source,
      );
    }
  }

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
    await _savePageCookies(source, page, store);
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
