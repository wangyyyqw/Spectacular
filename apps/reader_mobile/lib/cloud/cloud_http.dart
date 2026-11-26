import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'cloud_models.dart';

const cloudUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class CloudResponse {
  const CloudResponse(this.status, this.body, this.headers);
  final int status;
  final String body;
  final Map<String, String> headers;
  Map<String, dynamic> get json {
    try {
      final value = jsonDecode(body);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // 官网可能返回验证码或登录页，不能将该页面作为文件列表。
    }
    throw const CloudException('网盘返回了验证页面，请重新登录后重试');
  }
}

/// 各网盘显式传入凭据；不设置共享 Cookie 或跨站默认授权头。
class CloudHttp {
  CloudHttp({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<CloudResponse> send(
    Uri uri, {
    String method = 'GET',
    Map<String, String> headers = const {},
    Object? json,
    Map<String, String>? form,
    bool allowErrorStatus = false,
    int? maxBodyBytes,
  }) async {
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll({'User-Agent': cloudUserAgent, ...headers});
    if (json != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(json);
    } else if (form != null) {
      request.bodyFields = form;
    }
    try {
      return await _read(
        request,
        allowErrorStatus,
        maxBodyBytes,
      ).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const CloudException('连接网盘超时，请检查网络后重试');
    } on SocketException {
      throw const CloudException('无法连接网盘，请检查网络后重试');
    } on http.ClientException {
      throw const CloudException('网盘连接中断，请重试');
    }
  }

  Future<CloudResponse> _read(
    http.Request request,
    bool allowErrorStatus,
    int? maxBodyBytes,
  ) async {
    final response = await _client.send(request);
    if (response.statusCode == 401 && !allowErrorStatus) {
      await response.stream.drain<void>();
      throw const CloudException('登录已失效，请重新登录', loginRequired: true);
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (maxBodyBytes != null && bytes.length + chunk.length >= maxBodyBytes) {
        bytes.addAll(chunk.take(maxBodyBytes - bytes.length));
        break;
      }
      bytes.addAll(chunk);
      if (bytes.length > 8 * 1024 * 1024) {
        throw const CloudException('网盘响应过大，请缩小目录后重试');
      }
    }
    if (response.statusCode >= 400 && !allowErrorStatus) {
      throw CloudException(
        response.statusCode == 429
            ? '网盘请求过于频繁，请稍后重试'
            : '网盘请求失败（${response.statusCode}），请稍后重试',
      );
    }
    return CloudResponse(
      response.statusCode,
      utf8.decode(bytes, allowMalformed: true),
      response.headers,
    );
  }

  void close() => _client.close();
}

Map<String, String> cloudCookies(String value) => {
  for (final part in value.split(';'))
    if (part.indexOf('=') > 0)
      part.substring(0, part.indexOf('=')).trim(): part
          .substring(part.indexOf('=') + 1)
          .trim(),
};

void acceptCloudCookies(CloudAccount account, CloudResponse response) {
  final cookies = cloudCookies(account.cookie);
  for (final raw in (response.headers['set-cookie'] ?? '').split(
    RegExp(r',(?=\s*[^\s;,=]+=)'),
  )) {
    if (raw.trim().isEmpty) continue;
    try {
      final cookie = Cookie.fromSetCookieValue(raw.trim());
      if (cookie.maxAge == 0 || cookie.value.isEmpty) {
        cookies.remove(cookie.name);
      } else {
        cookies[cookie.name] = cookie.value;
      }
    } on FormatException {
      // 忽略格式错误的可选 Cookie，不记录凭据内容。
    }
  }
  account.fields['cookie'] = cookies.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join('; ');
}
