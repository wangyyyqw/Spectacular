import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../diagnostics/reader_log.dart';
import 'rea_micro_models.dart';

/// 阅微账号内置对象存储的同步接口。
///
/// APK 通过该组接口签发临时地址，再由客户端直接上传或下载对象；
/// 与用户自行填写的 S3 兼容存储相互独立。
abstract interface class ReaMicroMoteSyncApi {
  /// 读取对象状态。
  Future<ReaMicroS3ObjectHead> fetchMoteHead(
    String token, {
    required String objectKey,
  });

  /// 获取上传地址。
  Future<ReaMicroS3SignedUrl> fetchMoteUploadUrl(
    String token, {
    required String objectKey,
    required int contentLength,
    String ifMatch = '',
    bool ifNoneMatch = false,
  });

  /// 确认对象已上传。
  Future<void> confirmMoteUpload(
    String token, {
    required String objectKey,
    required int contentLength,
  });

  /// 获取下载地址。
  Future<ReaMicroS3SignedUrl> fetchMoteDownloadUrl(
    String token, {
    required String objectKey,
  });

  /// 删除对象。
  Future<void> deleteMoteObject(String token, {required String objectKey});
}

/// 阅微原生平台搜索规则接口。
abstract interface class ReaMicroThirdPartyApi {
  Future<List<String>> fetchThirdPartyRuleNames(String token);
  Future<String> downloadThirdPartyRule(String token, String name);
}

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

  /// 读取指定日期所在周的书籍阅读记录。
  Future<List<ReaMicroBookRecord>> fetchBookRecordsByWeek(
    String token, {
    DateTime? date,
  });

  /// 读取指定月份的书籍阅读记录。
  Future<List<ReaMicroBookRecord>> fetchBookRecordsByMonth(
    String token, {
    int? year,
    int? month,
  });

  /// 读取指定年份的书籍阅读记录。
  Future<List<ReaMicroBookRecord>> fetchBookRecordsByYear(
    String token, {
    int? year,
  });

  /// 读取账号有划线或想法的书籍。
  Future<List<ReaMicroMarkBook>> fetchMarkBooks(String token);

  /// 从阅微阅读记录中隐藏一本书。
  Future<void> hideBookRecord(String token, {required int bookId});

  /// 按书名和作者搜索阅微云端书籍，返回全部候选。
  Future<List<ReaMicroCloudBook>> searchCloudBooks(
    String token, {
    required String name,
    String author = '',
  });

  /// 读取阅微云端书籍详情。
  Future<ReaMicroCloudBook?> fetchCloudBookInfo(
    String token, {
    required int bookId,
    bool byPublisherId = false,
  });

  /// 将本地书登记为用户书，返回用户书与匹配到的云端标识。
  Future<ReaMicroUserBookRegistration> registerUserBook(
    String token, {
    required String name,
    required String author,
    required String md5,
    String cover = '',
    String coverMd5 = '',
  });

  /// 在阅微创建出版书。
  Future<ReaMicroCloudBookRegistration> createCloudBook(
    String token, {
    required String name,
    required String author,
    String subtitle = '',
    String original = '',
    String translator = '',
    String bookAlias = '',
    String intro = '',
    String publisher = '',
    String isbn = '',
    String publishDate = '',
    String price = '',
    String cover = '',
    String wordCount = '',
    String status = '',
  });

  /// 建立用户书与出版书的关联。
  Future<void> relateCloudBook(
    String token, {
    required int userBookId,
    required int publisherId,
  });

  /// 按日上报阅读时长。
  Future<void> updateReadTimeByDate(
    String token,
    List<ReaMicroReadTimeEntry> entries, {
    List<ReaMicroReadSessionLog> sessionLogs = const <ReaMicroReadSessionLog>[],
    bool sessionAccounting = false,
  });

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

  /// 读取一本书在阅微的书评。
  Future<ReaMicroBookReview?> fetchBookReview(
    String token, {
    int? bookId,
    int? cloudBookId,
  });

  /// 提交一本书的评分与书评。
  Future<void> rateReview(
    String token, {
    int? bookId,
    int? cloudBookId,
    required int rating,
    required String comment,
    required bool publish,
  });

  /// 点赞一条阅微书评。
  Future<void> actReview(
    String token, {
    required int reviewId,
    int actionType = ReaMicroReviewActionState.likeType,
  });

  /// 取消点赞一条阅微书评。
  Future<void> unactReview(
    String token, {
    required int reviewId,
    int actionType = ReaMicroReviewActionState.likeType,
  });

  /// 读取当前账号对一条书评已执行过的互动。
  Future<ReaMicroReviewActionState> checkReviewAction(
    String token, {
    required int reviewId,
  });

  /// 读取一条书评的互动用户。
  Future<ReaMicroReviewActorPage> fetchReviewActors(
    String token, {
    required int reviewId,
    int actionType = ReaMicroReviewActionState.likeType,
    int page = 1,
    int pageSize = 20,
  });

  /// 读取书评流；[cloudBookId] 为空时读取全站书评。
  Future<List<ReaMicroBookReview>> fetchReviewFlow(
    String token, {
    int? cloudBookId,
    int page = 1,
    int pageSize = 20,
  });

  /// 读取账号的读完里程碑。
  Future<List<ReaMicroMilestone>> fetchMilestones(
    String token, {
    int pageSize = 100,
  });

  /// 删除读完里程碑。
  Future<void> deleteMilestone(String token, {required int milestoneId});

  /// 读取阅微账号保存的 S3 同步配置。
  Future<ReaMicroS3CloudConfigResponse> fetchS3CloudConfig(String token);

  /// 更新阅微账号保存的 S3 同步配置。
  Future<void> updateS3CloudConfig(
    String token, {
    required bool enabled,
    required String encryptedConfig,
  });

  /// 读取对象存储配额。
  Future<ReaMicroStorageQuota> fetchStorageQuota(String token);

  /// 使用积分扩容对象存储；[credit] 必须为 60 的整数倍。
  Future<ReaMicroStorageQuota> expandStorageQuota(
    String token, {
    required int credit,
  });

  /// 读取对象存储积分流水。
  Future<ReaMicroCreditLedgerPage> fetchCreditLedger(
    String token, {
    int page = 1,
    int pageSize = 20,
  });

  /// 读取阅微离线朗读引擎与官方音色目录。
  Future<ReaMicroTtsCatalog> fetchTtsVoices(String token);

  /// 释放网络客户端。
  void close();
}

/// 阅微 HTTP 接口实现。
class ReaMicroApiClient
    implements ReaMicroApi, ReaMicroMoteSyncApi, ReaMicroThirdPartyApi {
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
  Future<List<String>> fetchThirdPartyRuleNames(String token) async {
    final data = await _post('rest/user/query-third-party', {}, token: token);
    final files = data is Map ? data['files'] : null;
    return files is List ? files.whereType<String>().toList() : const [];
  }

  @override
  Future<String> downloadThirdPartyRule(String token, String name) async {
    final uri = Uri.parse('${baseUrl}rest/user/download-third-party')
        .replace(queryParameters: {'name': name});
    final response = await _client
        .get(uri, headers: _headers(token))
        .timeout(timeout);
    // 原生下载端点直接返回 UTF-8 JavaScript，不使用业务 JSON 包装。
    if (response.statusCode != 200) {
      throw ReaMicroException('下载平台搜索规则失败（HTTP ${response.statusCode}）');
    }
    return utf8.decode(response.bodyBytes);
  }

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
    return _fetchBookRecords(
      'rest/reader/get-read-record-list-by-all',
      token,
      const <String, Object?>{},
    );
  }

  Future<List<ReaMicroBookRecord>> _fetchBookRecords(
    String endpoint,
    String token,
    Map<String, Object?> body,
  ) async {
    // 正式服务固定每页 20 条，使用其实际页大小判断是否还有下一页。
    const pageSize = 20;
    final records = <ReaMicroBookRecord>[];
    final seen = <int>{};
    for (var page = 1; page <= 250; page++) {
      final data = await _post(endpoint, <String, Object?>{
        ...body,
        'pageNum': page,
        'pageSize': pageSize,
      }, token: token);
      final rawList = _responseList(data);
      var added = 0;
      for (final item in rawList) {
        if (item is! Map<String, Object?>) continue;
        final record = ReaMicroBookRecord.fromJson(item);
        if (seen.add(record.bookId)) {
          records.add(record);
          added++;
        }
      }
      if (rawList.length < pageSize) return records;
      if (added == 0) {
        throw const ReaMicroException('阅微书籍分页重复，未获得完整记录');
      }
    }
    throw const ReaMicroException('阅微书籍记录超过分页上限，未获得完整记录');
  }

  @override
  Future<List<ReaMicroBookRecord>> fetchBookRecordsByWeek(
    String token, {
    DateTime? date,
  }) {
    return _fetchBookRecords(
      'rest/reader/get-read-record-list-by-week',
      token,
      <String, Object?>{'date': _dateOnly(date ?? DateTime.now())},
    );
  }

  @override
  Future<List<ReaMicroBookRecord>> fetchBookRecordsByMonth(
    String token, {
    int? year,
    int? month,
  }) {
    final now = DateTime.now();
    return _fetchBookRecords(
      'rest/reader/get-read-record-list-by-month',
      token,
      <String, Object?>{'year': year ?? now.year, 'month': month ?? now.month},
    );
  }

  @override
  Future<List<ReaMicroBookRecord>> fetchBookRecordsByYear(
    String token, {
    int? year,
  }) {
    return _fetchBookRecords(
      'rest/reader/get-read-record-list-by-year',
      token,
      <String, Object?>{'year': year ?? DateTime.now().year},
    );
  }

  @override
  Future<List<ReaMicroMarkBook>> fetchMarkBooks(String token) async {
    const pageSize = 100;
    final books = <ReaMicroMarkBook>[];
    final seen = <String>{};
    for (var page = 1; page <= 50; page++) {
      final data = await _post(
        'rest/read/get-mark-book-list',
        <String, Object?>{'pageNum': page, 'pageSize': pageSize},
        token: token,
      );
      final rawList = _responseList(data);
      for (final item in rawList) {
        if (item is! Map<String, Object?>) continue;
        final book = ReaMicroMarkBook.fromJson(item);
        if (book.bookId <= 0 && book.cloudBookId <= 0) continue;
        final key = '${book.bookId}|${book.cloudBookId}';
        if (!seen.add(key)) continue;
        books.add(book);
      }
      if (rawList.length < pageSize) break;
    }
    return books;
  }

  @override
  Future<void> hideBookRecord(String token, {required int bookId}) async {
    await _post('rest/reader/hide-read-record', <String, Object?>{
      'bookId': bookId,
    }, token: token);
  }

  @override
  Future<List<ReaMicroCloudBook>> searchCloudBooks(
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
    final books = <ReaMicroCloudBook>[];
    for (final item in rawItems) {
      if (item is! Map<String, Object?>) continue;
      final book = ReaMicroCloudBook.fromJson(item);
      if (book.cloudBookId > 0 && book.name.isNotEmpty) books.add(book);
    }
    return books;
  }

  @override
  Future<ReaMicroCloudBook?> fetchCloudBookInfo(
    String token, {
    required int bookId,
    bool byPublisherId = false,
  }) async {
    final data = await _post(
      byPublisherId
          ? 'rest/book/get-cloud-info-by-i-d'
          : 'rest/book/get-cloud-info',
      <String, Object?>{'bookId': bookId},
      token: token,
    );
    final json = _objectData(data);
    if (json == null) return null;
    final book = ReaMicroCloudBook.fromJson(json);
    return book.cloudBookId > 0 && book.name.isNotEmpty ? book : null;
  }

  @override
  Future<ReaMicroUserBookRegistration> registerUserBook(
    String token, {
    required String name,
    required String author,
    required String md5,
    String cover = '',
    String coverMd5 = '',
  }) async {
    final data = await _post('rest/book/post-user-book', <String, Object?>{
      'name': name,
      'author': author,
      'md5': md5,
      'cover': cover,
      'coverMd5': coverMd5,
    }, token: token);
    final json = _objectData(data);
    if (json == null) {
      throw const ReaMicroException('阅微未返回用户书登记结果');
    }
    final result = ReaMicroUserBookRegistration.fromJson(json);
    if (result.userBookId <= 0) {
      throw const ReaMicroException('阅微用户书登记结果缺少标识');
    }
    return result;
  }

  @override
  Future<ReaMicroCloudBookRegistration> createCloudBook(
    String token, {
    required String name,
    required String author,
    String subtitle = '',
    String original = '',
    String translator = '',
    String bookAlias = '',
    String intro = '',
    String publisher = '',
    String isbn = '',
    String publishDate = '',
    String price = '',
    String cover = '',
    String wordCount = '',
    String status = '',
  }) async {
    final data = await _post('rest/book/post-cloud-book', <String, Object?>{
      'name': name,
      'author': author,
      'subtitle': subtitle,
      'original': original,
      'intro': intro,
      'cover': cover,
      'translator': translator,
      'publisher': publisher,
      'publishDate': publishDate,
      'price': price,
      'isbn': isbn,
      'bookAlias': bookAlias,
      'wordCount': wordCount,
      'status': status,
    }, token: token);
    final json = _objectData(data);
    if (json == null) {
      throw const ReaMicroException('阅微未返回云端书籍结果');
    }
    final result = ReaMicroCloudBookRegistration.fromJson(json);
    if (result.cloudBookId <= 0 || result.publisherId <= 0) {
      throw const ReaMicroException('阅微云端书籍结果缺少关联标识');
    }
    return result;
  }

  @override
  Future<void> relateCloudBook(
    String token, {
    required int userBookId,
    required int publisherId,
  }) async {
    await _post('rest/book/relate-cloud-book', <String, Object?>{
      'userBookId': userBookId,
      'bookPublisherId': publisherId,
    }, token: token);
  }

  @override
  Future<void> updateReadTimeByDate(
    String token,
    List<ReaMicroReadTimeEntry> entries, {
    List<ReaMicroReadSessionLog> sessionLogs = const <ReaMicroReadSessionLog>[],
    bool sessionAccounting = false,
  }) async {
    if (entries.isEmpty && sessionLogs.isEmpty) return;
    // 会话记账与旧式按日增量互斥；同时提交会被服务器以业务码 2 拒绝。
    final data = await _post(
      'rest/reader/update-read-time-by-date',
      <String, Object?>{
        if (!sessionAccounting)
          'list': <Object?>[for (final entry in entries) entry.toJson()],
        if (sessionLogs.isNotEmpty)
          'sessionLogs': <Object?>[for (final log in sessionLogs) log.toJson()],
        if (sessionLogs.isNotEmpty || sessionAccounting)
          'sessionAccounting': sessionAccounting,
      },
      token: token,
    );
    if (sessionAccounting &&
        (data is! Map<String, Object?> ||
            data['sessionAccountingSupported'] != true)) {
      throw const ReaMicroException('阅微服务器未确认会话记账，请稍后重试');
    }
  }

  @override
  Future<void> updateReadProgress(
    String token, {
    required int cloudBookId,
    required String cfi,
    required String chapterName,
    required double progress,
  }) async {
    try {
      await _post('rest/reader/update-read-progress', <String, Object?>{
        'bookId': cloudBookId,
        'cfi': cfi,
        'chapterName': chapterName,
        'progress': progress.clamp(0.0, 1.0),
      }, token: token);
    } on ReaMicroException catch (error) {
      _logProgressFailure(error, stage: 'upload', bookId: '$cloudBookId');
      rethrow;
    }
  }

  @override
  Future<ReaMicroReadProgress?> fetchReadProgress(
    String token, {
    required String cloudBookId,
  }) async {
    final Object? data;
    try {
      data = await _post('rest/reader/get-read-progress', <String, Object?>{
        'bookId': cloudBookId,
      }, token: token);
    } on ReaMicroException catch (error) {
      // 首次同步尚无云端进度；继续上报本地位置，不消耗失败重试额度。
      if (error.statusCode == 200 &&
          error.code == 2 &&
          error.message.trim().toLowerCase() == 'record not found') {
        return null;
      }
      _logProgressFailure(error, stage: 'fetch', bookId: cloudBookId);
      rethrow;
    }
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

  void _logProgressFailure(
    ReaMicroException error, {
    required String stage,
    required String bookId,
  }) {
    recordAppEvent(
      'reamicro_progress_failed',
      fields: {
        'stage_enum': stage,
        'user_book_id': int.tryParse(bookId) ?? 0,
        'code': error.code ?? 0,
        'http_status': error.statusCode ?? 0,
        'failure_reason_enum': error.unauthorized
            ? 'unauthorized'
            : error.code != null
            ? 'business_rejected'
            : 'transport',
      },
    );
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
      if (data is! List<Object?> &&
          !(data is Map<String, Object?> &&
              (data['list'] is List<Object?> ||
                  data['records'] is List<Object?>))) {
        throw const ReaMicroException('阅微标注清单格式不正确');
      }
      final rawItems = _responseList(data);
      for (final item in rawItems) {
        if (item is! Map<String, Object?>) continue;
        final mark = ReaMicroMark.fromJson(item);
        if (mark.id > 0 && mark.startCfi.isNotEmpty) marks.add(mark);
      }
      if (rawItems.length < pageSize) return marks;
    }
    // 缺少后续分页时不能把未读取的标注误判为已删除。
    throw const ReaMicroException('阅微标注清单未完整读取，请稍后重试');
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

  @override
  Future<ReaMicroBookReview?> fetchBookReview(
    String token, {
    int? bookId,
    int? cloudBookId,
  }) async {
    final data = await _post(
      'rest/rating/get-review-by-book-id-v2',
      <String, Object?>{
        if (bookId != null && bookId > 0) 'bookId': bookId,
        if (cloudBookId != null && cloudBookId > 0) 'cloudBookId': cloudBookId,
      },
      token: token,
    );
    final raw = switch (data) {
      final Map<String, Object?> map
          when map['review'] is Map<String, Object?> =>
        map['review']! as Map<String, Object?>,
      final Map<String, Object?> map when map.isNotEmpty => map,
      _ => null,
    };
    if (raw == null) return null;
    final review = ReaMicroBookReview.fromJson(raw);
    return review.id > 0 ? review : null;
  }

  @override
  Future<void> rateReview(
    String token, {
    int? bookId,
    int? cloudBookId,
    required int rating,
    required String comment,
    required bool publish,
  }) async {
    await _post('rest/rating/rate-review', <String, Object?>{
      if (bookId != null && bookId > 0) 'bookId': bookId,
      if (cloudBookId != null && cloudBookId > 0) 'cloudBookId': cloudBookId,
      'rating': rating.clamp(0, 10),
      'comment': comment.trim(),
      'status': publish ? 2 : 1,
    }, token: token);
  }

  @override
  Future<void> actReview(
    String token, {
    required int reviewId,
    int actionType = ReaMicroReviewActionState.likeType,
  }) async {
    await _post('rest/rating/act-review', <String, Object?>{
      'reviewId': reviewId,
      'actionType': actionType,
    }, token: token);
  }

  @override
  Future<void> unactReview(
    String token, {
    required int reviewId,
    int actionType = ReaMicroReviewActionState.likeType,
  }) async {
    await _post('rest/rating/unact-review', <String, Object?>{
      'reviewId': reviewId,
      'actionType': actionType,
    }, token: token);
  }

  @override
  Future<ReaMicroReviewActionState> checkReviewAction(
    String token, {
    required int reviewId,
  }) async {
    final data = await _post(
      'rest/rating/check-review-action',
      <String, Object?>{'reviewId': reviewId},
      token: token,
    );
    if (data is! Map<String, Object?>) {
      return ReaMicroReviewActionState.empty;
    }
    return ReaMicroReviewActionState.fromJson(data);
  }

  @override
  Future<ReaMicroReviewActorPage> fetchReviewActors(
    String token, {
    required int reviewId,
    int actionType = ReaMicroReviewActionState.likeType,
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _post('rest/rating/get-review-actors', <String, Object?>{
      'reviewId': reviewId,
      'actionType': actionType,
      'pageNum': page,
      'pageSize': pageSize,
    }, token: token);
    if (data is! Map<String, Object?>) {
      return const ReaMicroReviewActorPage(
        items: <ReaMicroReviewActor>[],
        total: 0,
      );
    }
    return ReaMicroReviewActorPage.fromJson(data);
  }

  @override
  Future<List<ReaMicroBookReview>> fetchReviewFlow(
    String token, {
    int? cloudBookId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _post(
      'rest/rating/get-review-flow-v2',
      <String, Object?>{
        'pageNum': page,
        'pageSize': pageSize,
        if (cloudBookId != null && cloudBookId > 0) 'bookId': cloudBookId,
      },
      token: token,
    );
    final raw = switch (data) {
      final Map<String, Object?> map when map['reviews'] is List<Object?> =>
        map['reviews']! as List<Object?>,
      final List<Object?> list => list,
      _ => const <Object?>[],
    };
    return <ReaMicroBookReview>[
      for (final item in raw)
        if (item is Map<String, Object?>) ReaMicroBookReview.fromJson(item),
    ];
  }

  @override
  Future<List<ReaMicroMilestone>> fetchMilestones(
    String token, {
    int pageSize = 100,
  }) async {
    final milestones = <ReaMicroMilestone>[];
    for (var page = 1; page <= 50; page++) {
      final data = await _post(
        'rest/rating/get-milestone-list-v2',
        <String, Object?>{'pageNum': page, 'pageSize': pageSize},
        token: token,
      );
      if (data is! List<Object?> &&
          !(data is Map<String, Object?> &&
              (data['milestones'] is List<Object?> ||
                  data['list'] is List<Object?> ||
                  data['records'] is List<Object?>))) {
        throw const ReaMicroException('阅微读完清单格式不正确');
      }
      final rawItems = switch (data) {
        final Map<String, Object?> map
            when map['milestones'] is List<Object?> =>
          map['milestones']! as List<Object?>,
        _ => _responseList(data),
      };
      milestones.addAll(<ReaMicroMilestone>[
        for (final item in rawItems)
          if (item is Map<String, Object?>) ReaMicroMilestone.fromJson(item),
      ]);
      if (rawItems.length < pageSize) {
        milestones.sort(
          (left, right) => right.ratingTime.compareTo(left.ratingTime),
        );
        return milestones;
      }
    }
    throw const ReaMicroException('阅微读完清单未完整读取，请稍后重试');
  }

  @override
  Future<void> deleteMilestone(String token, {required int milestoneId}) async {
    await _post('rest/rating/delete-milestone', <String, Object?>{
      'milestoneId': milestoneId,
    }, token: token);
  }

  @override
  Future<ReaMicroS3CloudConfigResponse> fetchS3CloudConfig(String token) async {
    final data = await _post(
      'rest/user/get-s3-sync-cloud-config',
      const <String, Object?>{},
      token: token,
    );
    if (data is! Map<String, Object?>) {
      throw const ReaMicroException('阅微云端同步配置格式不正确');
    }
    return ReaMicroS3CloudConfigResponse.fromJson(data);
  }

  @override
  Future<void> updateS3CloudConfig(
    String token, {
    required bool enabled,
    required String encryptedConfig,
  }) async {
    await _post('rest/user/update-s3-sync-cloud-config', <String, Object?>{
      'enabled': enabled,
      'encryptedConfig': enabled ? encryptedConfig : '',
    }, token: token);
  }

  @override
  Future<ReaMicroStorageQuota> fetchStorageQuota(String token) async {
    final data = await _post(
      'rest/s3/get-storage-quota',
      const <String, Object?>{},
      token: token,
    );
    if (data is! Map<String, Object?>) {
      throw const ReaMicroException('对象存储配额格式不正确');
    }
    return ReaMicroStorageQuota.fromJson(data);
  }

  @override
  Future<ReaMicroStorageQuota> expandStorageQuota(
    String token, {
    required int credit,
  }) async {
    final data = await _post('rest/s3/expand-storage-quota', <String, Object?>{
      'credit': credit,
    }, token: token);
    if (data is Map<String, Object?> && data.containsKey('capacityBytes')) {
      return ReaMicroStorageQuota.fromJson(data);
    }
    return fetchStorageQuota(token);
  }

  @override
  Future<ReaMicroCreditLedgerPage> fetchCreditLedger(
    String token, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _post('rest/s3/credit-ledger', <String, Object?>{
      'page': page,
      'pageSize': pageSize,
    }, token: token);
    if (data is! Map<String, Object?>) {
      throw const ReaMicroException('对象存储积分流水格式不正确');
    }
    return ReaMicroCreditLedgerPage.fromJson(data);
  }

  @override
  Future<ReaMicroTtsCatalog> fetchTtsVoices(String token) async {
    final data = await _get('rest/tts/voices', token: token);
    if (data is! Map<String, Object?>) {
      throw const ReaMicroException('阅微朗读音色目录格式不正确');
    }
    return ReaMicroTtsCatalog.fromJson(data);
  }

  @override
  Future<ReaMicroS3ObjectHead> fetchMoteHead(
    String token, {
    required String objectKey,
  }) async {
    final data = await _post('rest/s3/sync/head-object', <String, Object?>{
      'objectKey': objectKey,
    }, token: token);
    final json = _objectData(data);
    if (json == null) {
      throw const ReaMicroException('阅微对象存储状态格式不正确');
    }
    return ReaMicroS3ObjectHead.fromJson(json);
  }

  @override
  Future<ReaMicroS3SignedUrl> fetchMoteUploadUrl(
    String token, {
    required String objectKey,
    required int contentLength,
    String ifMatch = '',
    bool ifNoneMatch = false,
  }) async {
    final data = await _post(
      'rest/s3/sync/get-upload-url',
      _moteObjectBody(
        objectKey,
        contentLength: contentLength,
        ifMatch: ifMatch,
        ifNoneMatch: ifNoneMatch,
      ),
      token: token,
    );
    final json = _objectData(data);
    if (json == null) {
      throw const ReaMicroException('阅微对象存储未返回上传地址');
    }
    final result = ReaMicroS3SignedUrl.fromJson(json);
    if (result.url.trim().isEmpty) {
      throw const ReaMicroException('阅微对象存储上传地址为空');
    }
    return result;
  }

  @override
  Future<void> confirmMoteUpload(
    String token, {
    required String objectKey,
    required int contentLength,
  }) async {
    await _post(
      'rest/s3/sync/confirm-upload',
      _moteObjectBody(objectKey, contentLength: contentLength),
      token: token,
    );
  }

  @override
  Future<ReaMicroS3SignedUrl> fetchMoteDownloadUrl(
    String token, {
    required String objectKey,
  }) async {
    final data = await _post(
      'rest/s3/sync/get-download-url',
      _moteObjectBody(objectKey),
      token: token,
    );
    final json = _objectData(data);
    if (json == null) {
      throw const ReaMicroException('阅微对象存储未返回下载地址');
    }
    final result = ReaMicroS3SignedUrl.fromJson(json);
    if (result.url.trim().isEmpty) {
      throw const ReaMicroException('阅微对象存储下载地址为空');
    }
    return result;
  }

  @override
  Future<void> deleteMoteObject(
    String token, {
    required String objectKey,
  }) async {
    await _post(
      'rest/s3/sync/delete-object',
      _moteObjectBody(objectKey),
      token: token,
    );
  }

  Map<String, Object?> _moteObjectBody(
    String objectKey, {
    int contentLength = 0,
    String ifMatch = '',
    bool ifNoneMatch = false,
  }) => <String, Object?>{
    'objectKey': objectKey,
    if (ifMatch.trim().isNotEmpty) 'ifMatch': ifMatch.trim(),
    if (ifNoneMatch) 'ifNoneMatch': true,
    if (contentLength > 0) 'contentLength': contentLength,
  };

  Future<Object?> _post(
    String endpoint,
    Map<String, Object?> body, {
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = _headers(token);
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
    return _decodeResponse(response);
  }

  Future<Object?> _get(String endpoint, {String? token}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    late final http.Response response;
    try {
      response = await _client
          .get(uri, headers: _headers(token))
          .timeout(timeout);
    } on TimeoutException {
      throw const ReaMicroException('阅微接口请求超时，请稍后重试');
    } on SocketException {
      throw const ReaMicroException('无法连接阅微服务器，请检查网络');
    } on http.ClientException catch (error) {
      throw ReaMicroException('阅微接口请求失败：${error.message}');
    }
    return _decodeResponse(response);
  }

  Map<String, String> _headers(String? token) => <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json; charset=utf-8',
    'platform': Platform.isIOS || Platform.isMacOS ? 'ios' : 'android',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Object? _decodeResponse(http.Response response) {
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

Map<String, Object?>? _objectData(Object? data) {
  return switch (data) {
    final Map<String, Object?> map when map['data'] is Map<String, Object?> =>
      map['data']! as Map<String, Object?>,
    final Map<String, Object?> map => map,
    final List<Object?> list when list.isNotEmpty =>
      list.first is Map<String, Object?>
          ? list.first! as Map<String, Object?>
          : null,
    _ => null,
  };
}

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
