import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'book_source_models.dart';

/// 在线书源 HTTP 响应。
class BookSourceHttpResponse {
  const BookSourceHttpResponse({
    required this.uri,
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.bytes,
  });

  final Uri uri;
  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final Uint8List bytes;
}

/// 单书源请求器。
///
/// Cookie 只保存在当前进程内，不写日志；重启后需要重新建立会话。
class BookSourceHttpClient {
  BookSourceHttpClient({
    http.Client? client,
    this.defaultTimeout = const Duration(seconds: 45),
    this.allowPrivateHosts = false,
  }) : _client = client ?? http.Client();

  static const int maxRedirects = 5;
  static const int maxResponseBytes = 24 * 1024 * 1024;

  final http.Client _client;
  final Duration defaultTimeout;
  final bool allowPrivateHosts;
  final Map<String, Map<String, String>> _cookies =
      <String, Map<String, String>>{};
  final Map<String, Future<void>> _rateLocks = <String, Future<void>>{};
  final Map<String, DateTime> _lastRequestAt = <String, DateTime>{};
  final Map<String, DateTime> _cooldownUntil = <String, DateTime>{};

  /// 请求文本资源。
  Future<BookSourceHttpResponse> fetchText(
    BookSource source,
    String url, {
    Map<String, String> headers = const <String, String>{},
    Map<String, Object?> options = const <String, Object?>{},
    String referer = '',
  }) {
    return _send(
      source,
      url,
      headers: headers,
      options: options,
      referer: referer,
    );
  }

  /// 请求二进制资源。
  Future<BookSourceHttpResponse> fetchBytes(
    BookSource source,
    String url, {
    Map<String, String> headers = const <String, String>{},
    String referer = '',
  }) {
    return _send(
      source,
      url,
      headers: headers,
      options: const <String, Object?>{},
      referer: referer,
    );
  }

  void close() => _client.close();

  Future<BookSourceHttpResponse> _send(
    BookSource source,
    String rawUrl, {
    required Map<String, String> headers,
    required Map<String, Object?> options,
    required String referer,
  }) async {
    var uri = _validateUrl(rawUrl);
    var method = _stringOption(options, 'method').ifBlank('GET').toUpperCase();
    if (method != 'GET' && method != 'POST') {
      throw const BookSourceException(
        '书源请求方法暂只支持 GET 和 POST',
        code: 'ONLINE_HTTP_METHOD',
      );
    }
    var body = _stringOption(options, 'body');
    var currentReferer = referer;

    for (var redirects = 0; ; redirects++) {
      await _waitTurn(source);
      final response = await _sendOnce(
        source,
        uri,
        method: method,
        headers: headers,
        options: options,
        referer: currentReferer,
        body: body,
      );
      final status = response.statusCode;
      if (_isRedirect(status)) {
        final location = response.headers['location']?.trim() ?? '';
        if (location.isEmpty) {
          throw BookSourceException(
            '请求被重定向但缺少目标地址（HTTP $status）',
            code: 'ONLINE_HTTP_REDIRECT',
            statusCode: status,
          );
        }
        if (redirects >= maxRedirects) {
          throw BookSourceException(
            '请求重定向次数过多',
            code: 'ONLINE_HTTP_REDIRECT',
            statusCode: status,
          );
        }
        final next = _validateUrl(uri.resolve(location).toString());
        if (status == 303 ||
            ((status == 301 || status == 302) && method == 'POST')) {
          method = 'GET';
          body = '';
        }
        currentReferer = uri.toString();
        uri = next;
        continue;
      }
      if (status == 429 || status == 503) {
        _recordCooldown(source, response.headers);
      }
      if (status < 200 || status >= 300) {
        final detail = _httpErrorDetail(response.body);
        throw BookSourceException(
          detail.isEmpty ? '请求失败（HTTP $status）' : '请求失败（HTTP $status）：$detail',
          code: 'ONLINE_HTTP_STATUS',
          statusCode: status,
        );
      }
      return response;
    }
  }

  Future<BookSourceHttpResponse> _sendOnce(
    BookSource source,
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    required Map<String, Object?> options,
    required String referer,
    required String body,
  }) async {
    final requestHeaders = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/125.0 Mobile Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6',
      ..._sourceHeaders(source),
      ..._optionHeaders(options),
      ...headers,
    };
    if (referer.isNotBlank) requestHeaders['Referer'] = referer;
    final cookies = _cookies[source.id];
    if (cookies != null && cookies.isNotEmpty) {
      requestHeaders['Cookie'] = cookies.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
    }

    final timeout = source.respondTime > 0
        ? Duration(milliseconds: source.respondTime.clamp(3000, 180000))
        : defaultTimeout;
    try {
      final request = http.Request(method, uri)..headers.addAll(requestHeaders);
      if (method == 'POST' && body.isNotEmpty) request.body = body;
      final streamed = await _client.send(request).timeout(timeout);
      final responseHeaders = <String, String>{
        for (final entry in streamed.headers.entries)
          entry.key.toLowerCase(): entry.value,
      };
      _rememberCookies(source.id, streamed.headers['set-cookie']);
      final declaredLength = int.tryParse(
        responseHeaders['content-length'] ?? '',
      );
      if (declaredLength != null && declaredLength > maxResponseBytes) {
        throw const BookSourceException(
          '书源响应过大，请检查书源规则',
          code: 'ONLINE_HTTP_TOO_LARGE',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream.timeout(timeout)) {
        if (builder.length + chunk.length > maxResponseBytes) {
          throw const BookSourceException(
            '书源响应过大，请检查书源规则',
            code: 'ONLINE_HTTP_TOO_LARGE',
          );
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.length > maxResponseBytes) {
        throw const BookSourceException(
          '书源响应过大，请检查书源规则',
          code: 'ONLINE_HTTP_TOO_LARGE',
        );
      }
      return BookSourceHttpResponse(
        uri: streamed.request?.url ?? uri,
        statusCode: streamed.statusCode,
        headers: responseHeaders,
        body: _decodeBody(bytes, responseHeaders['content-type']),
        bytes: bytes,
      );
    } on BookSourceException {
      rethrow;
    } on TimeoutException {
      throw const BookSourceException(
        '书源请求超时，请检查网络或站点状态',
        code: 'ONLINE_HTTP_TIMEOUT',
      );
    } on SocketException catch (error) {
      throw BookSourceException(
        '无法连接书源站点：${error.osError?.message ?? error.message}',
        code: 'ONLINE_HTTP_NETWORK',
      );
    } on http.ClientException catch (error) {
      throw BookSourceException(
        '书源请求失败：${error.message}',
        code: 'ONLINE_HTTP_CLIENT',
      );
    }
  }

  bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  void _recordCooldown(BookSource source, Map<String, String> headers) {
    final raw = headers['retry-after']?.trim() ?? '';
    var millis = 10000;
    final seconds = int.tryParse(raw);
    if (seconds != null && seconds > 0) {
      millis = seconds * 1000;
    } else {
      final date = DateTime.tryParse(raw);
      if (date != null) {
        millis = date.difference(DateTime.now()).inMilliseconds;
      }
    }
    millis = millis.clamp(3000, 120000);
    final until = DateTime.now().add(Duration(milliseconds: millis));
    final current = _cooldownUntil[source.id];
    if (current == null || until.isAfter(current)) {
      _cooldownUntil[source.id] = until;
    }
  }

  Uri _validateUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const BookSourceException('书源返回了无效地址', code: 'ONLINE_HTTP_URL');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const BookSourceException(
        '书源只允许访问 HTTP(S) 地址',
        code: 'ONLINE_HTTP_SCHEME',
      );
    }
    final host = uri.host.toLowerCase();
    if (!allowPrivateHosts && isBlockedHost(host)) {
      throw const BookSourceException(
        '书源地址指向本机或内网，已拒绝访问',
        code: 'ONLINE_HTTP_PRIVATE_HOST',
      );
    }
    return uri;
  }

  /// 判断主机是否指向本机、私网或链路本地地址。
  static bool isBlockedHost(String rawHost) {
    final host = rawHost.trim().toLowerCase();
    return host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        _isPrivateAddress(host);
  }

  static bool _isPrivateAddress(String host) {
    if (host == '::1' || host == '0:0:0:0:0:0:0:1') {
      return true;
    }
    if (host.contains(':')) {
      if (host.startsWith('fc') ||
          host.startsWith('fd') ||
          host.startsWith('fe8') ||
          host.startsWith('fe9') ||
          host.startsWith('fea') ||
          host.startsWith('feb')) {
        return true;
      }
      if (host.startsWith('::ffff:')) {
        return _isPrivateAddress(host.substring('::ffff:'.length));
      }
      return false;
    }
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
      octets.add(value);
    }
    return octets[0] == 10 ||
        (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] == 192 && octets[1] == 168) ||
        (octets[0] == 127) ||
        (octets[0] == 169 && octets[1] == 254) ||
        octets[0] == 0;
  }

  Map<String, String> _sourceHeaders(BookSource source) {
    final text = source.header.trim();
    if (text.isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const <String, String>{};
      return <String, String>{
        for (final entry in decoded.entries)
          if (entry.key is String) '${entry.key}': '${entry.value}',
      };
    } on FormatException {
      return const <String, String>{};
    }
  }

  Map<String, String> _optionHeaders(Map<String, Object?> options) {
    final value = options['headers'];
    if (value is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in value.entries)
        if (entry.key is String) '${entry.key}': '${entry.value}',
    };
  }

  String _stringOption(Map<String, Object?> options, String key) {
    final value = options[key];
    return value == null ? '' : '$value'.trim();
  }

  void _rememberCookies(String sourceId, String? raw) {
    if (raw == null || raw.trim().isEmpty) return;
    final jar = _cookies.putIfAbsent(sourceId, () => <String, String>{});
    for (final part in raw.split(RegExp(r',(?=\s*[^;,=]+=)'))) {
      final pair = part.split(';').first.trim();
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      final name = pair.substring(0, index).trim();
      final value = pair.substring(index + 1).trim();
      if (name.isEmpty) continue;
      if (value.isEmpty) {
        jar.remove(name);
      } else {
        jar[name] = value;
      }
    }
  }

  String _decodeBody(Uint8List bytes, String? contentType) {
    final match = RegExp(
      r'charset\s*=\s*([^;\s]+)',
      caseSensitive: false,
    ).firstMatch(contentType ?? '');
    final charset = (match?.group(1) ?? 'utf-8')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .toLowerCase();
    if (charset == 'gbk' || charset == 'gb2312' || charset == 'gb18030') {
      // Flutter 自带编码表不包含 GBK；保留原始字节可让站点切换到 UTF-8。
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    }
    try {
      return Encoding.getByName(charset)?.decode(bytes) ??
          const Utf8Decoder(allowMalformed: true).convert(bytes);
    } on FormatException {
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    }
  }

  String _httpErrorDetail(String body) {
    final text = body.trim();
    if (text.isEmpty || text.startsWith('<')) return '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        for (final key in const <String>['detail', 'error', 'msg', 'message']) {
          final value = decoded[key];
          if (value != null && '$value'.trim().isNotEmpty) {
            return '$value'.trim();
          }
        }
      }
    } on FormatException {
      // 非 JSON 错误正文只在较短时展示。
    }
    return text.length <= 160 ? text : '';
  }

  Future<void> _waitTurn(BookSource source) {
    final interval = _rateInterval(source.concurrentRate);
    final previous = _rateLocks[source.id] ?? Future<void>.value();
    final next = previous.then((_) async {
      final cooldown = _cooldownUntil.remove(source.id);
      if (cooldown != null) {
        final wait = cooldown.difference(DateTime.now());
        if (wait > Duration.zero) {
          await Future<void>.delayed(wait);
        }
      }
      if (interval > Duration.zero) {
        final last = _lastRequestAt[source.id];
        if (last != null) {
          final elapsed = DateTime.now().difference(last);
          if (elapsed < interval) {
            await Future<void>.delayed(interval - elapsed);
          }
        }
      }
      _lastRequestAt[source.id] = DateTime.now();
    });
    _rateLocks[source.id] = next.catchError((Object _) {});
    return next;
  }

  Duration _rateInterval(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text == '0') return Duration.zero;
    final parts = text.split('/');
    final millis = int.tryParse(parts.last.trim()) ?? 0;
    if (millis <= 0) return Duration.zero;
    final count = parts.length > 1
        ? (int.tryParse(parts.first.trim()) ?? 1)
        : 1;
    return Duration(milliseconds: (millis / count.clamp(1, 100)).ceil());
  }
}

extension _BlankString on String {
  bool get isNotBlank => trim().isNotEmpty;

  String ifBlank(String fallback) => trim().isEmpty ? fallback : this;
}
