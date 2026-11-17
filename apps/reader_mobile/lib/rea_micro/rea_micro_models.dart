/// 阅微账号信息。
class ReaMicroUser {
  /// 创建账号信息。
  const ReaMicroUser({
    required this.id,
    required this.nickName,
    this.userTitle = '',
    this.avatar = '',
    this.email = '',
    this.level = 0,
    this.readFinishedBookNum = 0,
    this.totalReadTimeSeconds = 0,
    this.coin = 0,
    this.gem = 0,
    this.voucher = 0,
  });

  /// 用户标识。
  final int id;

  /// 昵称。
  final String nickName;

  /// 用户头衔。
  final String userTitle;

  /// 头像地址。
  final String avatar;

  /// 绑定邮箱。
  final String email;

  /// 当前等级。
  final int level;

  /// 已读完书籍数。
  final int readFinishedBookNum;

  /// 累计阅读时长（秒）。
  final int totalReadTimeSeconds;

  /// 铜钱。
  final int coin;

  /// 彩筹。
  final int gem;

  /// 阅券。
  final int voucher;

  /// 从接口数据解析；缺失字段使用安全默认值。
  factory ReaMicroUser.fromJson(Map<String, Object?> json) => ReaMicroUser(
    id: _intValue(json['id']),
    nickName: _stringValue(json['nickName']) ?? '阅微用户',
    userTitle: _stringValue(json['userTitle']) ?? '',
    avatar: _stringValue(json['avatar']) ?? '',
    email: _stringValue(json['email']) ?? '',
    level: _intValue(json['level']),
    readFinishedBookNum: _intValue(
      json['readFinishedBookNum'] ?? json['readFinishedBookCount'],
    ),
    totalReadTimeSeconds: _intValue(
      json['totalReadTime'] ?? json['totalReadTimeSeconds'] ?? json['readTime'],
    ),
    coin: _intValue(json['coin']),
    gem: _intValue(json['gem']),
    voucher: _intValue(json['voucher']),
  );

  /// 序列化到本地缓存。
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'nickName': nickName,
    'userTitle': userTitle,
    'avatar': avatar,
    'email': email,
    'level': level,
    'readFinishedBookNum': readFinishedBookNum,
    'totalReadTime': totalReadTimeSeconds,
    'coin': coin,
    'gem': gem,
    'voucher': voucher,
  };
}

/// 阅微按日阅读时长。
class ReaMicroChartPoint {
  /// 创建图表点。
  const ReaMicroChartPoint({
    required this.day,
    required this.durationSeconds,
    required this.readingDurationSeconds,
    required this.listeningDurationSeconds,
  });

  /// 日期，格式为 `yyyy-MM-dd`。
  final String day;

  /// 总时长（秒）。
  final int durationSeconds;

  /// 阅读时长（秒）。
  final int readingDurationSeconds;

  /// 听书时长（秒）。
  final int listeningDurationSeconds;

  /// 从接口数据解析。
  factory ReaMicroChartPoint.fromJson(Map<String, Object?> json) {
    final duration = _intValue(json['duration']);
    final listening = _intValue(json['listeningDuration']);
    final reading = _intValue(json['readingDuration']);
    return ReaMicroChartPoint(
      day: _stringValue(json['day']) ?? '',
      durationSeconds: duration,
      readingDurationSeconds: reading,
      listeningDurationSeconds: listening,
    );
  }
}

/// 阅微账号的完整阅读概览。
class ReaMicroOverview {
  /// 创建概览。
  const ReaMicroOverview({
    required this.years,
    required this.readDays,
    required this.totalDurationSeconds,
    required this.bookCount,
    required this.finishedBookCount,
    required this.registerTimestamp,
    required this.topBooks,
    required this.listeningDurationSeconds,
    required this.readingDurationSeconds,
  });

  /// 有阅读记录的年份。
  final List<int> years;

  /// 累计阅读天数。
  final int readDays;

  /// 累计阅读时长（秒）。
  final int totalDurationSeconds;

  /// 阅读过的书籍数。
  final int bookCount;

  /// 已读完书籍数。
  final int finishedBookCount;

  /// 注册时间（毫秒时间戳，0 表示未提供）。
  final int registerTimestamp;

  /// 阅读时长最高的书籍。
  final List<ReaMicroTopBook> topBooks;

  /// 听书时长（秒）。
  final int listeningDurationSeconds;

  /// 阅读时长（秒）。
  final int readingDurationSeconds;

  /// 从接口数据解析。
  factory ReaMicroOverview.fromJson(Map<String, Object?> json) {
    return ReaMicroOverview(
      years: _intList(json['years']),
      readDays: _intValue(json['readDays']),
      totalDurationSeconds: _intValue(json['totalDuration']),
      bookCount: _intValue(json['bookCount']),
      finishedBookCount: _intValue(json['finishedBookCount']),
      registerTimestamp: _timestampMillis(json['registerTimestamp']),
      topBooks: _topBooks(json['topBooks']),
      listeningDurationSeconds: _intValue(json['listeningDuration']),
      readingDurationSeconds: _intValue(json['readingDuration']),
    );
  }
}

/// 阅读时长最高的书籍。
class ReaMicroTopBook {
  /// 创建条目。
  const ReaMicroTopBook({
    required this.cover,
    required this.name,
    required this.durationSeconds,
    required this.bookId,
    required this.readDays,
    required this.listeningDurationSeconds,
    required this.readingDurationSeconds,
  });

  /// 封面地址。
  final String cover;

  /// 书名。
  final String name;

  /// 该周期阅读时长（秒）。
  final int durationSeconds;

  /// 云端书籍标识。
  final String bookId;

  /// 阅读天数。
  final int readDays;

  /// 听书时长（秒）。
  final int listeningDurationSeconds;

  /// 阅读时长（秒）。
  final int readingDurationSeconds;

  /// 从接口数据解析。
  factory ReaMicroTopBook.fromJson(Map<String, Object?> json) {
    return ReaMicroTopBook(
      cover: _stringValue(json['cover']) ?? '',
      name: _stringValue(json['name']) ?? '',
      durationSeconds: _intValue(json['duration']),
      bookId: _stringValue(json['bookId']) ?? json['bookId']?.toString() ?? '',
      readDays: _intValue(json['readDays']),
      listeningDurationSeconds: _intValue(json['listeningDuration']),
      readingDurationSeconds: _intValue(json['readingDuration']),
    );
  }
}

/// 阅微周/月统计中的单日时长。
class ReaMicroDayDuration {
  /// 创建单日时长。
  const ReaMicroDayDuration({
    required this.day,
    required this.durationSeconds,
    required this.listeningDurationSeconds,
    required this.readingDurationSeconds,
  });

  /// 当月日期（1～31）。
  final int day;

  /// 当日总时长（秒）。
  final int durationSeconds;

  /// 当日听书时长（秒）。
  final int listeningDurationSeconds;

  /// 当日阅读时长（秒）。
  final int readingDurationSeconds;

  /// 从接口数据解析。
  factory ReaMicroDayDuration.fromJson(Map<String, Object?> json) {
    return ReaMicroDayDuration(
      day: _intValue(json['day']),
      durationSeconds: _intValue(json['duration']),
      listeningDurationSeconds: _intValue(json['listeningDuration']),
      readingDurationSeconds: _intValue(json['readingDuration']),
    );
  }
}

/// 阅微年度统计中的单月时长。
class ReaMicroMonthDuration {
  /// 创建单月时长。
  const ReaMicroMonthDuration({
    required this.month,
    required this.durationSeconds,
    required this.listeningDurationSeconds,
    required this.readingDurationSeconds,
  });

  /// 月份（1～12）。
  final int month;

  /// 当月总时长（秒）。
  final int durationSeconds;

  /// 当月听书时长（秒）。
  final int listeningDurationSeconds;

  /// 当月阅读时长（秒）。
  final int readingDurationSeconds;

  /// 从接口数据解析。
  factory ReaMicroMonthDuration.fromJson(Map<String, Object?> json) {
    return ReaMicroMonthDuration(
      month: _intValue(json['month']),
      durationSeconds: _intValue(json['duration']),
      listeningDurationSeconds: _intValue(json['listeningDuration']),
      readingDurationSeconds: _intValue(json['readingDuration']),
    );
  }
}

/// 阅微周、月或年度统计。
class ReaMicroPeriodStats {
  /// 创建周期统计。
  const ReaMicroPeriodStats({
    required this.days,
    required this.months,
    required this.readDays,
    required this.totalDurationSeconds,
    required this.bookCount,
    required this.finishedBookCount,
    required this.continuousReadDays,
    required this.averageDailyDurationSeconds,
    required this.topBooks,
    required this.listeningDurationSeconds,
    required this.readingDurationSeconds,
  });

  /// 周/月统计中的逐日数据。
  final List<ReaMicroDayDuration> days;

  /// 年度统计中的逐月数据。
  final List<ReaMicroMonthDuration> months;

  /// 本周期阅读天数。
  final int readDays;

  /// 本周期总时长（秒）。
  final int totalDurationSeconds;

  /// 本周期阅读书籍数。
  final int bookCount;

  /// 本周期读完书籍数。
  final int finishedBookCount;

  /// 连续阅读天数。
  final int continuousReadDays;

  /// 日均时长（秒）。
  final int averageDailyDurationSeconds;

  /// 本周期阅读时长最高的书籍。
  final List<ReaMicroTopBook> topBooks;

  /// 听书时长（秒）。
  final int listeningDurationSeconds;

  /// 阅读时长（秒）。
  final int readingDurationSeconds;

  /// 从接口数据解析。
  factory ReaMicroPeriodStats.fromJson(Map<String, Object?> json) {
    return ReaMicroPeriodStats(
      days: <ReaMicroDayDuration>[
        if (json['days'] is List<Object?>)
          for (final item in json['days']! as List<Object?>)
            if (item is Map<String, Object?>)
              ReaMicroDayDuration.fromJson(item),
      ]..sort((left, right) => left.day.compareTo(right.day)),
      months: <ReaMicroMonthDuration>[
        if (json['months'] is List<Object?>)
          for (final item in json['months']! as List<Object?>)
            if (item is Map<String, Object?>)
              ReaMicroMonthDuration.fromJson(item),
      ]..sort((left, right) => left.month.compareTo(right.month)),
      readDays: _intValue(json['readDays']),
      totalDurationSeconds: _intValue(json['totalDuration']),
      bookCount: _intValue(json['bookCount']),
      finishedBookCount: _intValue(json['finishedBookCount']),
      continuousReadDays: _intValue(json['continuousReadDays']),
      averageDailyDurationSeconds: _intValue(json['avgDailyDuration']),
      topBooks: _topBooks(json['topBooks']),
      listeningDurationSeconds: _intValue(json['listeningDuration']),
      readingDurationSeconds: _intValue(json['readingDuration']),
    );
  }
}

/// 阅微云端的一本书阅读记录。
class ReaMicroBookRecord {
  /// 创建记录。
  const ReaMicroBookRecord({
    required this.bookId,
    required this.cloudBookId,
    required this.name,
    required this.author,
    required this.cover,
    required this.progress,
    required this.totalReadTimeSeconds,
    required this.readDays,
    required this.finishReadTime,
    required this.listeningDurationSeconds,
    required this.readingDurationSeconds,
  });

  /// 阅微书籍标识。
  final int bookId;

  /// 云端书籍标识。
  final int cloudBookId;

  /// 书名。
  final String name;

  /// 作者。
  final String author;

  /// 封面地址。
  final String cover;

  /// 全书进度（0～1）。
  final double progress;

  /// 累计阅读时长（秒）。
  final int totalReadTimeSeconds;

  /// 阅读天数。
  final int readDays;

  /// 读完时间（毫秒时间戳，0 表示未读完）。
  final int finishReadTime;

  /// 听书时长（秒）。
  final int listeningDurationSeconds;

  /// 阅读时长（秒）。
  final int readingDurationSeconds;

  /// 是否已读完。
  bool get finished => finishReadTime > 0 || progress >= 1;

  /// 从接口数据解析。
  factory ReaMicroBookRecord.fromJson(Map<String, Object?> json) {
    return ReaMicroBookRecord(
      bookId: _intValue(json['bookId']),
      cloudBookId: _intValue(json['cloudBookId']),
      name: _stringValue(json['name']) ?? '',
      author: _stringValue(json['author']) ?? '',
      cover: _stringValue(json['cover']) ?? '',
      progress: _progressValue(json['progress']),
      totalReadTimeSeconds: _intValue(json['totalReadTime']),
      readDays: _intValue(json['readDays']),
      finishReadTime: _timestampMillis(json['finishReadTime']),
      listeningDurationSeconds: _intValue(json['listeningDuration']),
      readingDurationSeconds: _intValue(json['readingDuration']),
    );
  }
}

/// 阅微完整阅读数据快照。
class ReaMicroCloudStats {
  /// 创建快照。
  const ReaMicroCloudStats({
    required this.overview,
    required this.week,
    required this.month,
    required this.year,
    required this.chart,
    required this.books,
    required this.fetchedAt,
  });

  /// 累计概览。
  final ReaMicroOverview overview;

  /// 本周统计。
  final ReaMicroPeriodStats week;

  /// 本月统计。
  final ReaMicroPeriodStats month;

  /// 本年度统计。
  final ReaMicroPeriodStats year;

  /// 最近 30 天趋势。
  final List<ReaMicroChartPoint> chart;

  /// 账号全部书籍阅读记录。
  final List<ReaMicroBookRecord> books;

  /// 拉取时间。
  final DateTime fetchedAt;
}

/// 阅微云端书籍搜索结果。
class ReaMicroCloudBook {
  /// 创建云端书籍。
  const ReaMicroCloudBook({
    required this.cloudBookId,
    required this.name,
    this.author = '',
    this.publishers = const <String>[],
  });

  /// 云端书籍标识，阅读时长上报使用该值。
  final int cloudBookId;

  /// 书名。
  final String name;

  /// 作者。
  final String author;

  /// 出版方信息。
  final List<String> publishers;

  /// 从接口数据解析。
  factory ReaMicroCloudBook.fromJson(Map<String, Object?> json) {
    final publishers = <String>[];
    final rawPublishers = json['bookPublishers'];
    if (rawPublishers is List<Object?>) {
      for (final item in rawPublishers) {
        if (item is String && item.trim().isNotEmpty) {
          publishers.add(item.trim());
        } else if (item is Map<String, Object?>) {
          final name = _stringValue(item['name']);
          if (name != null && name.trim().isNotEmpty) {
            publishers.add(name.trim());
          }
        }
      }
    }
    return ReaMicroCloudBook(
      cloudBookId: _intValue(json['cloudBookId']),
      name: _stringValue(json['name']) ?? '',
      author: _stringValue(json['author']) ?? '',
      publishers: publishers,
    );
  }
}

/// 本地书籍与阅微云端书籍的关联。
class ReaMicroBookLink {
  /// 创建关联。
  const ReaMicroBookLink({
    required this.cloudBookId,
    required this.name,
    this.author = '',
    required this.linkedAt,
  });

  /// 云端书籍标识。
  final int cloudBookId;

  /// 云端书名。
  final String name;

  /// 云端作者。
  final String author;

  /// 关联时间。
  final DateTime linkedAt;

  /// 从本地 JSON 解析。
  factory ReaMicroBookLink.fromJson(Map<String, Object?> json) =>
      ReaMicroBookLink(
        cloudBookId: _intValue(json['cloudBookId']),
        name: _stringValue(json['name']) ?? '',
        author: _stringValue(json['author']) ?? '',
        linkedAt: DateTime.fromMillisecondsSinceEpoch(
          _intValue(json['linkedAt']),
        ),
      );

  /// 序列化到本地 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'cloudBookId': cloudBookId,
    'name': name,
    'author': author,
    'linkedAt': linkedAt.millisecondsSinceEpoch,
  };
}

/// 按日聚合后的一条阅读时长上报。
class ReaMicroReadTimeEntry {
  /// 创建上报条目。
  const ReaMicroReadTimeEntry({
    required this.cloudBookId,
    required this.date,
    required this.durationSeconds,
  });

  /// 云端书籍标识。
  final int cloudBookId;

  /// 日期，格式为 `yyyy-MM-dd`。
  final String date;

  /// 当日累计时长（秒）。
  final int durationSeconds;

  /// 转换为阅微接口请求体。
  Map<String, Object?> toJson() => <String, Object?>{
    'bookId': cloudBookId,
    'date': date,
    'duration': durationSeconds,
    'verify': '',
  };
}

/// 阅微云端保存的阅读位置。
class ReaMicroReadProgress {
  /// 创建云端阅读位置。
  const ReaMicroReadProgress({
    required this.cloudBookId,
    required this.cfi,
    required this.chapterName,
    required this.progress,
    required this.readFinishTime,
  });

  /// 云端书籍标识。
  final String cloudBookId;

  /// EPUB CFI 位置。
  final String cfi;

  /// 章节名。
  final String chapterName;

  /// 全书进度（0～1）。
  final double progress;

  /// 云端最后阅读时间（毫秒时间戳，0 表示未提供）。
  final int readFinishTime;

  /// 是否包含可恢复的位置。
  bool get usable => cfi.trim().isNotEmpty;

  /// 从接口数据解析。
  factory ReaMicroReadProgress.fromJson(Map<String, Object?> json) {
    return ReaMicroReadProgress(
      cloudBookId: _stringValue(json['bookId']) ?? '',
      cfi: _stringValue(json['cfi']) ?? '',
      chapterName: _stringValue(json['chapterName']) ?? '',
      progress: _progressValue(json['progress']),
      readFinishTime: _timestampMillis(json['readFinishTime']),
    );
  }
}

/// 一本书的进度同步状态。
///
/// [localUpdatedAt] 记录本机最后一次产生或接收进度的时间，
/// [remoteUpdatedAt] 记录已处理的云端或局域网时间戳，[dirty] 表示尚有本地
/// 位置待上报。
class ReaMicroProgressState {
  /// 创建进度状态。
  const ReaMicroProgressState({
    required this.cfi,
    required this.chapterName,
    required this.progress,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    required this.uploadedAt,
    required this.dirty,
  });

  /// 当前 CFI。
  final String cfi;

  /// 当前章节名。
  final String chapterName;

  /// 当前全书进度（0～1）。
  final double progress;

  /// 本机最后变更时间（毫秒时间戳）。
  final int localUpdatedAt;

  /// 已处理的对端最后更新时间（毫秒时间戳）。
  final int remoteUpdatedAt;

  /// 最后成功上报云端的时间（毫秒时间戳）。
  final int uploadedAt;

  /// 是否有待上报的本地位置。
  final bool dirty;

  /// 从本地 JSON 解析。
  factory ReaMicroProgressState.fromJson(Map<String, Object?> json) =>
      ReaMicroProgressState(
        cfi: _stringValue(json['cfi']) ?? '',
        chapterName: _stringValue(json['chapterName']) ?? '',
        progress: _progressValue(json['progress']),
        localUpdatedAt: _intValue(json['localUpdatedAt']),
        remoteUpdatedAt: _intValue(json['remoteUpdatedAt']),
        uploadedAt: _intValue(json['uploadedAt']),
        dirty: json['dirty'] == true,
      );

  /// 序列化到本地 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'cfi': cfi,
    'chapterName': chapterName,
    'progress': progress,
    'localUpdatedAt': localUpdatedAt,
    'remoteUpdatedAt': remoteUpdatedAt,
    'uploadedAt': uploadedAt,
    'dirty': dirty,
  };

  /// 复制并覆盖部分字段。
  ReaMicroProgressState copyWith({
    String? cfi,
    String? chapterName,
    double? progress,
    int? localUpdatedAt,
    int? remoteUpdatedAt,
    int? uploadedAt,
    bool? dirty,
  }) => ReaMicroProgressState(
    cfi: cfi ?? this.cfi,
    chapterName: chapterName ?? this.chapterName,
    progress: progress ?? this.progress,
    localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
    remoteUpdatedAt: remoteUpdatedAt ?? this.remoteUpdatedAt,
    uploadedAt: uploadedAt ?? this.uploadedAt,
    dirty: dirty ?? this.dirty,
  );
}

/// 局域网同步清单中的一本书。
class ReaMicroLanBookProgress {
  /// 创建局域网进度。
  const ReaMicroLanBookProgress({
    required this.uuid,
    required this.cfi,
    required this.chapterName,
    required this.progress,
    required this.updatedAt,
    required this.finished,
  });

  /// 书籍 UUID，与本地书库标识一致。
  final String uuid;

  /// EPUB CFI 位置。
  final String cfi;

  /// 章节名。
  final String chapterName;

  /// 全书进度（0～1）。
  final double progress;

  /// 对方最后修改进度的时间（毫秒时间戳）。
  final int updatedAt;

  /// 对方是否已读完。
  final bool finished;

  /// 是否包含可合并的位置。
  bool get usable => uuid.trim().isNotEmpty && cfi.trim().isNotEmpty;

  /// 从清单条目解析。
  factory ReaMicroLanBookProgress.fromEntry(Map<String, Object?> entry) {
    final book = entry['book'];
    final snapshot = book is Map<String, Object?> ? book : entry;
    return ReaMicroLanBookProgress(
      uuid: _stringValue(entry['uuid']) ?? '',
      cfi: _stringValue(snapshot['epubcfi']) ?? '',
      chapterName: _stringValue(snapshot['chapter']) ?? '',
      progress: _progressValue(snapshot['progress']),
      updatedAt: _intValue(entry['progressUpdatedAt']),
      finished:
          snapshot['finished'] == true || _intValue(snapshot['finished']) > 0,
    );
  }
}

/// 局域网设备返回的同步清单。
class ReaMicroLanManifest {
  /// 创建清单。
  const ReaMicroLanManifest({
    required this.userId,
    required this.deviceId,
    required this.generatedAt,
    required this.books,
  });

  /// 清单所属账号。
  final int userId;

  /// 对端设备标识。
  final String deviceId;

  /// 生成时间（毫秒时间戳）。
  final int generatedAt;

  /// 对方提供的书籍进度。
  final List<ReaMicroLanBookProgress> books;

  /// 从服务端同步清单映射解析。
  factory ReaMicroLanManifest.fromJson(Map<String, Object?> json) {
    final rawBooks = json['books'];
    return ReaMicroLanManifest(
      userId: _intValue(json['userId']),
      deviceId: _stringValue(json['deviceId']) ?? '',
      generatedAt: _intValue(json['generatedAt']),
      books: <ReaMicroLanBookProgress>[
        if (rawBooks is List<Object?>)
          for (final item in rawBooks)
            if (item is Map<String, Object?>)
              ReaMicroLanBookProgress.fromEntry(item),
      ],
    );
  }
}

/// 阅微接口或网络失败。
class ReaMicroException implements Exception {
  /// 创建异常。
  const ReaMicroException(
    this.message, {
    this.statusCode,
    this.code,
    this.unauthorized = false,
  });

  /// 用户可读原因。
  final String message;

  /// HTTP 状态码。
  final int? statusCode;

  /// 业务码。
  final int? code;

  /// 是否为登录失效。
  final bool unauthorized;

  @override
  String toString() => message;
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _stringValue(Object? value) => value is String ? value : null;

List<int> _intList(Object? value) => <int>[
  if (value is List<Object?>)
    for (final item in value)
      if (_intValue(item) > 0) _intValue(item),
];

List<ReaMicroTopBook> _topBooks(Object? value) => <ReaMicroTopBook>[
  if (value is List<Object?>)
    for (final item in value)
      if (item is Map<String, Object?>) ReaMicroTopBook.fromJson(item),
];

double _progressValue(Object? value) {
  final raw = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  if (!raw.isFinite || raw <= 0) return 0;
  return raw > 1
      ? (raw / 100).clamp(0.0, 1.0).toDouble()
      : raw.clamp(0.0, 1.0).toDouble();
}

int _timestampMillis(Object? value) {
  if (value is num) {
    final raw = value.toInt();
    return raw > 0 && raw < 100000000000 ? raw * 1000 : raw;
  }
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return 0;
  final numeric = int.tryParse(text);
  if (numeric != null) return _timestampMillis(numeric);
  return DateTime.tryParse(text)?.millisecondsSinceEpoch ?? 0;
}
