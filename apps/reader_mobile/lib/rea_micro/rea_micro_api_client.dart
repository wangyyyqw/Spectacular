import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'rea_micro_models.dart';

/// 阅微数据接口；抽出接口便于同步逻辑使用内存实现测试。
abstract interface class ReaMicroApi {
  /// 发送邮箱验证码。
  Future<void> sendEmailCode(String email);

  /// 使用邮箱与验证码登录，返回访问令牌。
  Future<String> loginWithEmail({required String email, required String code});

  /// 读取当前账号信息。
  Future<ReaMicroUser> fetchUser(String token);

  /// 读取最近若干天的阅读时长。
  Future<List<ReaMicroChartPoint>> fetchReadTimeChart(
    String token, {
    int limit = 30,
  });

  /// 按书名和作者搜索阅微云端书籍。
  Future<ReaMicroCloudBook?> searchCloudBook(
    String token, {
    required String name,
    String author = '',
  });

  /// 按日上报阅读时长。
  Future<void> updateReadTimeByDate(
    String token,
    List<ReaMicroReadTimeEntry> entries,
  );

  /// 释放网络客户端。
  void close();
}

/// 阅微 HTTP 接口实现。
class ReaMicroApiClient implements ReaMicroApi {
  /// 创建客户端。
  ReaMicroApiClient({
    http.Client? client,
    this.baseUrl = defaultBaseUrl,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  /// 阅微开放接口根地址。
  static const String defaultBaseUrl = 'https://api.reamicro.zhendong.ltd/';

  final http.Client _client;

  /// 接口根地址。
  final String baseUrl;

  /// 单次请求超时。
  final Duration timeout;

  @override
  Future<void> sendEmailCode(String email) async {
    await _post('rest/user/send-email-code', <String, Object?>{'email': email});
  }

  @override
  Future<String> loginWithEmail({
    required String email,
    required String code,
  }) async {
    final data = await _post('rest/user/login-or-register', <String, Object?>{
      'type': 'email',
      'email': email,
      'code': code,
    });
    final token = switch (data) {
      final String value => value,
      final Map<String, Object?> map =>
        _stringValue(map['token']) ??
            _stringValue(map['accessToken']) ??
            _stringValue(map['access_token']),
      _ => null,
    };
    if (token == null || token.trim().isEmpty) {
      throw const ReaMicroException('登录成功但未返回访问令牌');
    }
    return token;
  }

  @override
  Future<ReaMicroUser> fetchUser(String token) async {
    final data = await _post(
      'rest/user/get-user-info',
      const <String, Object?>{},
      token: token,
    );
    if (data is! Map<String, Object?>) {
      throw const ReaMicroException('账号信息格式不正确');
    }
    return ReaMicroUser.fromJson(data);
  }

  @override
  Future<List<ReaMicroChartPoint>> fetchReadTimeChart(
    String token, {
    int limit = 30,
  }) async {
    final data = await _post(
      'rest/reader/get-read-time-chart',
      <String, Object?>{'limit': limit, 'isFillZero': true},
      token: token,
    );
    final rawList = switch (data) {
      final List<Object?> list => list,
      final Map<String, Object?> map =>
        map['charts'] is List<Object?>
            ? map['charts']! as List<Object?>
            : const <Object?>[],
      _ => const <Object?>[],
    };
    final points = <ReaMicroChartPoint>[
      for (final item in rawList)
        if (item is Map<String, Object?>) ReaMicroChartPoint.fromJson(item),
    ]..sort((left, right) => left.day.compareTo(right.day));
    return points;
  }

  @override
  Future<ReaMicroCloudBook?> searchCloudBook(
    String token, {
    required String name,
    String author = '',
  }) async {
    final data = await _post('rest/book/search-cloud-book', <String, Object?>{
      'name': name,
      'author': author,
    }, token: token);
    final rawItems = switch (data) {
      final List<Object?> list => list,
      final Map<String, Object?> map =>
        map['list'] is List<Object?>
            ? map['list']! as List<Object?>
            : map['books'] is List<Object?>
            ? map['books']! as List<Object?>
            : <Object?>[map],
      _ => const <Object?>[],
    };
    for (final item in rawItems) {
      if (item is! Map<String, Object?>) continue;
      final book = ReaMicroCloudBook.fromJson(item);
      if (book.cloudBookId > 0 && book.name.isNotEmpty) return book;
    }
    return null;
  }

  @override
  Future<void> updateReadTimeByDate(
    String token,
    List<ReaMicroReadTimeEntry> entries,
  ) async {
    if (entries.isEmpty) return;
    await _post('rest/reader/update-read-time-by-date', <String, Object?>{
      'list': <Object?>[for (final entry in entries) entry.toJson()],
    }, token: token);
  }

  Future<Object?> _post(
    String endpoint,
    Map<String, Object?> body, {
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'platform': Platform.isIOS || Platform.isMacOS ? 'ios' : 'android',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    late final http.Response response;
    try {
      response = await _client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(timeout);
    } on TimeoutException {
      throw const ReaMicroException('阅微接口请求超时，请稍后重试');
    } on SocketException {
      throw const ReaMicroException('无法连接阅微服务器，请检查网络');
    } on http.ClientException catch (error) {
      throw ReaMicroException('阅微接口请求失败：${error.message}');
    }
    final raw = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? decoded;
    try {
      decoded = raw.isEmpty ? null : jsonDecode(raw);
    } on FormatException {
      throw ReaMicroException(
        '阅微服务器返回了无法解析的数据（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
    final map = decoded is Map<String, Object?> ? decoded : null;
    final code = map == null ? null : _intValue(map['code']);
    final message = map == null
        ? null
        : _stringValue(map['message']) ?? _stringValue(map['msg']);
    final unauthorized =
        response.statusCode == 401 ||
        response.statusCode == 403 ||
        code == 401 ||
        code == 403;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReaMicroException(
        message?.trim().isNotEmpty == true
            ? message!.trim()
            : '阅微接口请求失败（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
        code: code,
        unauthorized: unauthorized,
      );
    }
    if (code != null && code != 0 && code != 200) {
      throw ReaMicroException(
        message?.trim().isNotEmpty == true
            ? message!.trim()
            : '阅微接口返回业务码 $code',
        statusCode: response.statusCode,
        code: code,
        unauthorized: code == 401 || code == 403,
      );
    }
    if (map == null) return decoded;
    if (!map.containsKey('code')) return map;
    return map['data'];
  }

  @override
  void close() => _client.close();
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _stringValue(Object? value) => value is String ? value : null;
