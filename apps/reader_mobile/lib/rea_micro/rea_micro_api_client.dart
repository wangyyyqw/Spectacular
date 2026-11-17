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

  /// 读取账号完整阅读概览。
  Future<ReaMicroOverview> fetchOverview(String token);

  /// 读取指定日期所在周的统计。
  Future<ReaMicroPeriodStats> fetchWeekStats(String token, {DateTime? date});

  /// 读取指定月份的统计。
  Future<ReaMicroPeriodStats> fetchMonthStats(
    String token, {
    int? year,
    int? month,
  });

  /// 读取指定年份的统计。
  Future<ReaMicroPeriodStats> fetchYearStats(String token, {int? year});

  /// 读取账号全部书籍的阅读记录。
  Future<List<ReaMicroBookRecord>> fetchBookRecords(String token);

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

  /// 上报一本书的当前阅读位置。
  Future<void> updateReadProgress(
    String token, {
    required int cloudBookId,
    required String cfi,
    required String chapterName,
    required double progress,
  });

  /// 读取一本书的云端阅读位置。
  Future<ReaMicroReadProgress?> fetchReadProgress(
    String token, {
    required String cloudBookId,
  });

  /// 读取云端标注；[bookId] 为空时读取账号全部标注。
  Future<List<ReaMicroMark>> fetchMarks(
    String token, {
    String? bookId,
    int pageSize = 200,
  });

  /// 新增或更新一条云端标注，返回云端标识。
  Future<int?> upsertMark(String token, ReaMicroMarkDraft mark);

  /// 删除一条云端标注。
  Future<void> deleteMark(String token, {required int id});

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
  Future<ReaMicroOverview> fetchOverview(String token) async {
    final data = await _post(
      'rest/statistic/get-overview-read-duration',
      const <String, Object?>{},
      token: token,
    );
    if (data is! Map<String, Object?>) {
      throw const ReaMicroException('阅读概览格式不正确');
    }
    return ReaMicroOverview.fromJson(data);
  }

  @override
  Future<ReaMicroPeriodStats> fetchWeekStats(
    String token, {
    DateTime? date,
  }) async {
    final value = date ?? DateTime.now();
    return _fetchPeriodStats(
      'rest/statistic/get-week-read-duration',
      token,
      <String, Object?>{'date': _dateOnly(value)},
    );
  }

  @override
  Future<ReaMicroPeriodStats> fetchMonthStats(
    String token, {
    int? year,
    int? month,
  }) async {
    final value = DateTime.now();
    return _fetchPeriodStats(
      'rest/statistic/get-month-read-duration',
      token,
      <String, Object?>{
        'year': year ?? value.year,
        'month': month ?? value.month,
      },
    );
  }

  @override
  Future<ReaMicroPeriodStats> fetchYearStats(String token, {int? year}) async {
    return _fetchPeriodStats(
      'rest/statistic/get-year-read-duration',
      token,
      <String, Object?>{'year': year ?? DateTime.now().year},
    );
  }

  Future<ReaMicroPeriodStats> _fetchPeriodStats(
    String endpoint,
    String token,
    Map<String, Object?> body,
  ) async {
    final data = await _post(endpoint, body, token: token);
    if (data is! Map<String, Object?>) {
      throw const ReaMicroException('阅读统计格式不正确');
    }
    return ReaMicroPeriodStats.fromJson(data);
  }

  @override
  Future<List<ReaMicroBookRecord>> fetchBookRecords(String token) async {
    const pageSize = 200;
    final records = <ReaMicroBookRecord>[];
    for (var page = 1; page <= 20; page++) {
      final data = await _post(
        'rest/reader/get-read-record-list-by-all',
        <String, Object?>{'pageNum': page, 'pageSize': pageSize},
        token: token,
      );
      final rawList = _responseList(data);
      records.addAll(<ReaMicroBookRecord>[
        for (final item in rawList)
          if (item is Map<String, Object?>) ReaMicroBookRecord.fromJson(item),
      ]);
      if (rawList.length < pageSize) break;
    }
    return records;
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

  @override
  Future<void> updateReadProgress(
    String token, {
    required int cloudBookId,
    required String cfi,
    required String chapterName,
    required double progress,
  }) async {
    await _post('rest/reader/update-read-progress', <String, Object?>{
      'bookId': cloudBookId,
      'cfi': cfi,
      'chapterName': chapterName,
      'progress': progress.clamp(0.0, 1.0),
    }, token: token);
  }

  @override
  Future<ReaMicroReadProgress?> fetchReadProgress(
    String token, {
    required String cloudBookId,
  }) async {
    final data = await _post('rest/reader/get-read-progress', <String, Object?>{
      'bookId': cloudBookId,
    }, token: token);
    final Map<String, Object?>? json = switch (data) {
      final Map<String, Object?> map => map,
      final List<Object?> list when list.isNotEmpty =>
        list.first is Map<String, Object?>
            ? list.first! as Map<String, Object?>
            : null,
      _ => null,
    };
    if (json == null) return null;
    final result = ReaMicroReadProgress.fromJson(json);
    return result.usable ? result : null;
  }

  @override
  Future<List<ReaMicroMark>> fetchMarks(
    String token, {
    String? bookId,
    int pageSize = 200,
  }) async {
    final marks = <ReaMicroMark>[];
    for (var page = 1; page <= 50; page++) {
      final data = await _post('rest/read/get-mark-list', <String, Object?>{
        'pageNum': page,
        'pageSize': pageSize,
        if (bookId != null && bookId.trim().isNotEmpty) 'bookId': bookId,
      }, token: token);
      final rawItems = _responseList(data);
      for (final item in rawItems) {
        if (item is! Map<String, Object?>) continue;
        final mark = ReaMicroMark.fromJson(item);
        if (mark.id > 0 && mark.startCfi.isNotEmpty) marks.add(mark);
      }
      if (rawItems.length < pageSize) break;
    }
    return marks;
  }

  @override
  Future<int?> upsertMark(String token, ReaMicroMarkDraft mark) async {
    final data = await _post('rest/read/batch-upsert-mark', <String, Object?>{
      'items': <Object?>[mark.toJson()],
    }, token: token);
    final results = _markUpsertResults(data);
    for (final result in results) {
      if (!result.success) {
        throw ReaMicroException(
          result.message.trim().isEmpty ? '阅微标注提交失败' : result.message,
        );
      }
      if (result.id > 0) return result.id;
      if (result.mark != null && result.mark!.id > 0) {
        return result.mark!.id;
      }
    }
    return null;
  }

  @override
  Future<void> deleteMark(String token, {required int id}) async {
    await _post('rest/read/delete-mark', <String, Object?>{
      'id': id,
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

List<Object?> _responseList(Object? data) {
  return switch (data) {
    final List<Object?> list => list,
    final Map<String, Object?> map when map['list'] is List<Object?> =>
      map['list']! as List<Object?>,
    final Map<String, Object?> map when map['records'] is List<Object?> =>
      map['records']! as List<Object?>,
    _ => const <Object?>[],
  };
}

List<ReaMicroMarkUpsertResult> _markUpsertResults(Object? data) {
  final rawItems = switch (data) {
    final List<Object?> list => list,
    final Map<String, Object?> map when map['results'] is List<Object?> =>
      map['results']! as List<Object?>,
    final Map<String, Object?> map when map['items'] is List<Object?> =>
      map['items']! as List<Object?>,
    final Map<String, Object?> map when map['list'] is List<Object?> =>
      map['list']! as List<Object?>,
    final Map<String, Object?> map => <Object?>[map],
    _ => const <Object?>[],
  };
  return <ReaMicroMarkUpsertResult>[
    for (final item in rawItems)
      if (item is Map<String, Object?>) ReaMicroMarkUpsertResult.fromJson(item),
  ];
}

String _dateOnly(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
