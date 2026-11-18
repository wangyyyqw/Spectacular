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
      years: _yearList(json['years']),
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

/// 阅微有标注的书籍。
class ReaMicroMarkBook {
  /// 创建标注书籍。
  const ReaMicroMarkBook({
    required this.bookId,
    required this.cloudBookId,
    required this.name,
    required this.author,
    required this.cover,
    required this.thoughtCount,
    required this.underlineCount,
  });

  /// 阅微内部书籍标识。
  final int bookId;

  /// 云端书籍标识。
  final int cloudBookId;

  /// 书名。
  final String name;

  /// 作者。
  final String author;

  /// 封面地址。
  final String cover;

  /// 想法数量。
  final int thoughtCount;

  /// 划线数量。
  final int underlineCount;

  /// 标注总数。
  int get markCount => thoughtCount + underlineCount;

  /// 从接口数据解析。
  factory ReaMicroMarkBook.fromJson(Map<String, Object?> json) =>
      ReaMicroMarkBook(
        bookId: _intValue(json['bookId']),
        cloudBookId: _intValue(json['cloudBookId']),
        name: _stringValue(json['bookName']) ?? '',
        author: _stringValue(json['bookAuthor']) ?? '',
        cover: _stringValue(json['bookCover']) ?? '',
        thoughtCount: _intValue(json['thoughtCount']),
        underlineCount: _intValue(json['underlineCount']),
      );
}

/// 阅读记录统计周期。
enum ReaMicroRecordPeriod {
  /// 周。
  week,

  /// 月。
  month,

  /// 年。
  year,
}

/// 一条阅读时长会话日志。
///
/// 服务端按 [id] 去重，因此同一次阅读在多次重试时也能保持稳定。
class ReaMicroReadSessionLog {
  /// 创建会话日志。
  const ReaMicroReadSessionLog({
    required this.id,
    required this.cloudBookId,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.recordDay,
    this.listening = false,
  });

  /// 稳定会话标识。
  final String id;

  /// 云端书籍标识。
  final int cloudBookId;

  /// 开始时间（毫秒时间戳）。
  final int startedAt;

  /// 结束时间（毫秒时间戳）。
  final int endedAt;

  /// 会话时长（秒）。
  final int durationSeconds;

  /// 归属日期，格式为 `yyyy-MM-dd`。
  final String recordDay;

  /// 是否为听书。
  final bool listening;

  /// 转换为阅微接口请求体。
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'bookId': cloudBookId,
    'startedAt': startedAt,
    'endedAt': endedAt,
    'duration': durationSeconds,
    'listening': listening,
    'recordDay': recordDay,
  };
}

/// 阅微云端书籍的出版方条目。
class ReaMicroCloudPublisher {
  /// 创建出版方条目。
  const ReaMicroCloudPublisher({
    required this.publisherId,
    this.name = '',
    this.publisher = '',
    this.cover = '',
  });

  /// 出版方标识；建立用户书关联时使用。
  final int publisherId;

  /// 书名或出版方展示名称（接口不同版本字段不同）。
  final String name;

  /// 出版社名称。
  final String publisher;

  /// 封面地址。
  final String cover;

  /// 展示名称。
  String get displayName =>
      publisher.trim().isNotEmpty ? publisher.trim() : name.trim();

  /// 从接口数据解析。
  factory ReaMicroCloudPublisher.fromJson(Map<String, Object?> json) {
    final id = _intValue(
      json['bookPublisherId'] ??
          json['publisherId'] ??
          json['id'] ??
          json['cloudBookId'],
    );
    return ReaMicroCloudPublisher(
      publisherId: id,
      name: _stringValue(json['name']) ?? '',
      publisher: _stringValue(json['publisher']) ?? '',
      cover: _stringValue(json['cover']) ?? '',
    );
  }
}

/// 阅微云端书籍搜索结果。
class ReaMicroCloudBook {
  /// 创建云端书籍。
  const ReaMicroCloudBook({
    required this.cloudBookId,
    required this.name,
    this.author = '',
    this.subtitle = '',
    this.original = '',
    this.publishers = const <ReaMicroCloudPublisher>[],
  });

  /// 云端书籍标识，阅读时长上报使用该值。
  final int cloudBookId;

  /// 书名。
  final String name;

  /// 作者。
  final String author;

  /// 副标题。
  final String subtitle;

  /// 原作名。
  final String original;

  /// 出版方信息。
  final List<ReaMicroCloudPublisher> publishers;

  /// 可直接用于用户书关联的出版方。
  ReaMicroCloudPublisher? get linkablePublisher {
    for (final publisher in publishers) {
      if (publisher.publisherId > 0) return publisher;
    }
    return null;
  }

  /// 出版方展示文本。
  List<String> get publisherNames => <String>[
    for (final publisher in publishers)
      if (publisher.displayName.isNotEmpty) publisher.displayName,
  ];

  /// 从接口数据解析。
  factory ReaMicroCloudBook.fromJson(Map<String, Object?> json) {
    final publishers = <ReaMicroCloudPublisher>[];
    final rawPublishers = json['bookPublishers'] ?? json['publishers'];
    if (rawPublishers is List<Object?>) {
      for (final item in rawPublishers) {
        if (item is String && item.trim().isNotEmpty) {
          publishers.add(
            ReaMicroCloudPublisher(publisherId: 0, publisher: item.trim()),
          );
        } else if (item is Map<String, Object?>) {
          final publisher = ReaMicroCloudPublisher.fromJson(item);
          if (publisher.publisherId > 0 || publisher.displayName.isNotEmpty) {
            publishers.add(publisher);
          }
        }
      }
    }
    return ReaMicroCloudBook(
      cloudBookId: _intValue(
        json['cloudBookId'] ?? json['CloudBookId'] ?? json['cloudBookID'],
      ),
      name: _stringValue(json['name']) ?? _stringValue(json['BookName']) ?? '',
      author:
          _stringValue(json['author']) ??
          _stringValue(json['BookAuthor']) ??
          '',
      subtitle: _stringValue(json['subtitle']) ?? '',
      original: _stringValue(json['original']) ?? '',
      publishers: publishers,
    );
  }
}

/// 阅微用户书登记结果。
class ReaMicroUserBookRegistration {
  /// 创建登记结果。
  const ReaMicroUserBookRegistration({
    required this.userBookId,
    this.cloudBookId = 0,
    this.publisherId = 0,
    this.publisher = '',
  });

  /// 用户书标识。
  final int userBookId;

  /// 接口已匹配到的云端书标识。
  final int cloudBookId;

  /// 接口已匹配到的出版方标识。
  final int publisherId;

  /// 接口返回的出版方名称。
  final String publisher;

  /// 从接口数据解析。
  factory ReaMicroUserBookRegistration.fromJson(Map<String, Object?> json) {
    return ReaMicroUserBookRegistration(
      userBookId: _intValue(json['id'] ?? json['userBookId']),
      cloudBookId: _intValue(
        json['cloudBookID'] ?? json['cloudBookId'] ?? json['bookId'],
      ),
      publisherId: _intValue(json['bookPublisherId'] ?? json['publisherId']),
      publisher: _stringValue(json['publisher']) ?? '',
    );
  }
}

/// 阅微出版书创建结果。
class ReaMicroCloudBookRegistration {
  /// 创建出版书结果。
  const ReaMicroCloudBookRegistration({
    required this.cloudBookId,
    required this.publisherId,
  });

  /// 云端书标识。
  final int cloudBookId;

  /// 出版方标识，用于建立用户书关联。
  final int publisherId;

  /// 从接口数据解析。
  factory ReaMicroCloudBookRegistration.fromJson(Map<String, Object?> json) {
    return ReaMicroCloudBookRegistration(
      cloudBookId: _intValue(
        json['cloudBookId'] ?? json['CloudBookId'] ?? json['cloudBookID'],
      ),
      publisherId: _intValue(
        json['bookPublisherId'] ?? json['publisherId'] ?? json['CloudBookId'],
      ),
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
    this.userBookId = 0,
    this.publisherId = 0,
    required this.linkedAt,
  });

  /// 云端书籍标识。
  final int cloudBookId;

  /// 云端书名。
  final String name;

  /// 云端作者。
  final String author;

  /// 阅微用户书标识；为 0 表示还未登记到阅微。
  final int userBookId;

  /// 阅微出版方标识；为 0 表示还未建立出版书关联。
  final int publisherId;

  /// 关联时间。
  final DateTime linkedAt;

  /// 从本地 JSON 解析。
  factory ReaMicroBookLink.fromJson(Map<String, Object?> json) =>
      ReaMicroBookLink(
        cloudBookId: _intValue(json['cloudBookId']),
        name: _stringValue(json['name']) ?? '',
        author: _stringValue(json['author']) ?? '',
        userBookId: _intValue(json['userBookId']),
        publisherId: _intValue(json['publisherId']),
        linkedAt: DateTime.fromMillisecondsSinceEpoch(
          _intValue(json['linkedAt']),
        ),
      );

  /// 序列化到本地 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'cloudBookId': cloudBookId,
    'name': name,
    'author': author,
    'userBookId': userBookId,
    'publisherId': publisherId,
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

/// 阅微云端标注。
class ReaMicroMark {
  /// 创建标注。
  const ReaMicroMark({
    required this.id,
    required this.bookId,
    required this.chapter,
    required this.kind,
    required this.startCfi,
    required this.endCfi,
    required this.quote,
    required this.note,
    required this.style,
    required this.color,
    required this.synced,
    required this.createdAt,
    required this.updatedAt,
    this.bookName = '',
    this.bookAuthor = '',
  });

  /// 云端标注标识。
  final int id;

  /// 云端书籍标识或本地书籍 UUID。
  final String bookId;

  /// 书名。
  final String bookName;

  /// 作者。
  final String bookAuthor;

  /// 章节名。
  final String chapter;

  /// 类型：0 划线、1 想法。
  final int kind;

  /// 起点 CFI。
  final String startCfi;

  /// 终点 CFI。
  final String endCfi;

  /// 原文。
  final String quote;

  /// 想法正文。
  final String note;

  /// 样式。
  final int style;

  /// 颜色字符串。
  final String color;

  /// 是否已同步。
  final int synced;

  /// 创建时间（毫秒时间戳）。
  final int createdAt;

  /// 更新时间（毫秒时间戳）。
  final int updatedAt;

  /// 从接口数据解析。
  factory ReaMicroMark.fromJson(Map<String, Object?> json) => ReaMicroMark(
    id: _intValue(json['id']),
    bookId: _stringValue(json['bookId']) ?? '',
    bookName: _stringValue(json['bookName']) ?? '',
    bookAuthor: _stringValue(json['bookAuthor']) ?? '',
    chapter: _stringValue(json['chapter']) ?? '',
    kind: _intValue(json['kind']),
    startCfi: _stringValue(json['startCfi']) ?? '',
    endCfi: _stringValue(json['endCfi']) ?? '',
    quote: _stringValue(json['quote']) ?? '',
    note: _stringValue(json['note']) ?? '',
    style: _intValue(json['style']),
    color: _stringValue(json['color']) ?? '',
    synced: _intValue(json['synced']),
    createdAt: _timestampMillis(json['createdAt']),
    updatedAt: _timestampMillis(json['updatedAt']),
  );
}

/// 提交到阅微的标注内容。
class ReaMicroMarkDraft {
  /// 创建待提交标注。
  const ReaMicroMarkDraft({
    required this.cloudId,
    required this.bookId,
    required this.chapter,
    required this.kind,
    required this.startCfi,
    required this.endCfi,
    required this.quote,
    required this.note,
    required this.style,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 云端标注标识；新标注为 0。
  final int cloudId;

  /// 云端书籍标识。
  final String bookId;

  /// 章节名。
  final String chapter;

  /// 类型。
  final int kind;

  /// 起点 CFI。
  final String startCfi;

  /// 终点 CFI。
  final String endCfi;

  /// 原文。
  final String quote;

  /// 想法正文。
  final String note;

  /// 样式。
  final int style;

  /// 颜色。
  final String color;

  /// 创建时间（毫秒）。
  final int createdAt;

  /// 更新时间（毫秒）。
  final int updatedAt;

  /// 转换为接口请求字段。
  Map<String, Object?> toJson() => <String, Object?>{
    'id': cloudId,
    'bookId': bookId,
    'chapter': chapter,
    'kind': kind,
    'startCfi': startCfi,
    'endCfi': endCfi,
    'quote': quote,
    'note': note,
    'style': style,
    'color': color,
    'synced': 1,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

/// 单条标注提交结果。
class ReaMicroMarkUpsertResult {
  /// 创建结果。
  const ReaMicroMarkUpsertResult({
    required this.id,
    required this.success,
    required this.message,
    this.mark,
  });

  /// 云端标注标识。
  final int id;

  /// 是否成功。
  final bool success;

  /// 失败原因。
  final String message;

  /// 服务端返回的完整标注。
  final ReaMicroMark? mark;

  /// 从接口数据解析。
  factory ReaMicroMarkUpsertResult.fromJson(Map<String, Object?> json) {
    final mark = json['mark'];
    return ReaMicroMarkUpsertResult(
      id: _intValue(json['id']),
      success: json['success'] != false,
      message: _stringValue(json['message']) ?? '',
      mark: mark is Map<String, Object?> ? ReaMicroMark.fromJson(mark) : null,
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
    required this.title,
    required this.author,
    required this.cloudId,
    required this.cfi,
    required this.chapterName,
    required this.progress,
    required this.updatedAt,
    required this.finished,
    this.files = const <ReaMicroLanFile>[],
    this.marks = const <ReaMicroLanMark>[],
  });

  /// 书籍 UUID，与本地书库标识一致。
  final String uuid;

  /// 阅微书名，用于本地书籍身份不一致时匹配。
  final String title;

  /// 阅微作者。
  final String author;

  /// 阅微云端书籍标识。
  final int cloudId;

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

  /// 对方设备上的原书文件清单。
  final List<ReaMicroLanFile> files;

  /// 对方设备上的划线与想法。
  final List<ReaMicroLanMark> marks;

  /// 是否包含可合并的位置。
  bool get usable => uuid.trim().isNotEmpty && cfi.trim().isNotEmpty;

  /// 是否提供可重建 EPUB 的文件。
  bool get hasFiles => files.isNotEmpty;

  /// 从清单条目解析。
  factory ReaMicroLanBookProgress.fromEntry(Map<String, Object?> entry) {
    final book = entry['book'];
    final snapshot = book is Map<String, Object?> ? book : entry;
    final rawFiles = entry['files'];
    final rawMarks = entry['marks'];
    return ReaMicroLanBookProgress(
      uuid: _stringValue(entry['uuid']) ?? '',
      title: _stringValue(snapshot['title']) ?? '',
      author: _stringValue(snapshot['author']) ?? '',
      cloudId: _intValue(snapshot['cloudId']),
      cfi: _stringValue(snapshot['epubcfi']) ?? '',
      chapterName: _stringValue(snapshot['chapter']) ?? '',
      progress: _progressValue(snapshot['progress']),
      updatedAt: _intValue(entry['progressUpdatedAt']),
      finished:
          snapshot['finished'] == true || _intValue(snapshot['finished']) > 0,
      files: <ReaMicroLanFile>[
        if (rawFiles is List<Object?>)
          for (final item in rawFiles)
            if (item is Map<String, Object?>) ReaMicroLanFile.fromJson(item),
      ],
      marks: <ReaMicroLanMark>[
        if (rawMarks is List<Object?>)
          for (final item in rawMarks)
            if (item is Map<String, Object?>) ReaMicroLanMark.fromJson(item),
      ],
    );
  }
}

/// 局域网同步清单中的一条划线或想法。
class ReaMicroLanMark {
  /// 创建标注快照。
  const ReaMicroLanMark({
    required this.startCfi,
    required this.endCfi,
    required this.kind,
    required this.chapter,
    required this.quote,
    required this.note,
    required this.style,
    required this.color,
    required this.synced,
    required this.cloudId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 起点 CFI。
  final String startCfi;

  /// 终点 CFI。
  final String endCfi;

  /// 类型：0 划线、1 想法。
  final int kind;

  /// 章节名。
  final String chapter;

  /// 原文。
  final String quote;

  /// 想法正文。
  final String note;

  /// 样式。
  final int style;

  /// 颜色字符串。
  final String color;

  /// 对方是否已同步到云端。
  final int synced;

  /// 对方记录的云端标注标识，0 表示尚未同步。
  final int cloudId;

  /// 创建时间（毫秒时间戳）。
  final int createdAt;

  /// 更新时间（毫秒时间戳）。
  final int updatedAt;

  /// 是否包含可合并的位置。
  bool get usable => startCfi.trim().isNotEmpty;

  /// 从清单数据解析。
  factory ReaMicroLanMark.fromJson(Map<String, Object?> json) =>
      ReaMicroLanMark(
        startCfi: _stringValue(json['startCfi']) ?? '',
        endCfi: _stringValue(json['endCfi']) ?? '',
        kind: _intValue(json['kind']),
        chapter: _stringValue(json['chapter']) ?? '',
        quote: _stringValue(json['quote']) ?? '',
        note: _stringValue(json['note']) ?? '',
        style: _intValue(json['style']),
        color: _stringValue(json['color']) ?? '',
        synced: _intValue(json['synced']),
        cloudId: _intValue(json['cloudId']),
        createdAt: _timestampMillis(json['createdAt']),
        updatedAt: _timestampMillis(json['updatedAt']),
      );
}

/// 局域网设备上的一本书内文件。
class ReaMicroLanFile {
  /// 创建文件信息。
  const ReaMicroLanFile({
    required this.relativePath,
    required this.size,
    required this.md5,
    required this.mtime,
  });

  /// 相对书籍目录的路径。
  final String relativePath;

  /// 文件字节数。
  final int size;

  /// 文件 MD5。
  final String md5;

  /// 文件修改时间（毫秒时间戳）。
  final int mtime;

  /// 从清单数据解析。
  factory ReaMicroLanFile.fromJson(Map<String, Object?> json) =>
      ReaMicroLanFile(
        relativePath: _stringValue(json['relativePath']) ?? '',
        size: _intValue(json['size']),
        md5: _stringValue(json['md5']) ?? '',
        mtime: _timestampMillis(json['mtime']),
      );
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

/// 阅微书评。
class ReaMicroBookReview {
  /// 创建书评。
  const ReaMicroBookReview({
    required this.id,
    required this.rating,
    required this.comment,
    required this.status,
    required this.publishTime,
    required this.commentUpdateTime,
    required this.likeCount,
    required this.isLiked,
    required this.bookId,
    required this.bookName,
    required this.bookAuthor,
    required this.bookCover,
    required this.userId,
    required this.userName,
    required this.title,
    required this.titleLevel,
    required this.userAvatar,
    required this.userRemark,
    required this.userLevel,
    required this.vip,
    required this.readTotalTimeSeconds,
    required this.style,
    required this.seal,
    required this.popularity,
    this.statusKnown = false,
  });

  /// 书评标识。
  final int id;

  /// 评分 1～10，0 表示未评分。
  final int rating;

  /// 书评正文。
  final String comment;

  /// 状态，1 为私有、2 为公开发布；接口未返回时为 0。
  final int status;

  /// 接口是否返回了发布状态。
  final bool statusKnown;

  /// 发布时间（毫秒时间戳）。
  final int publishTime;

  /// 正文更新时间（毫秒时间戳）。
  final int commentUpdateTime;

  /// 点赞数。
  final int likeCount;

  /// 当前账号是否已点赞。
  final bool isLiked;

  /// 阅微内部书籍标识。
  final int bookId;

  final String bookName;
  final String bookAuthor;
  final String bookCover;
  final int userId;
  final String userName;
  final String title;
  final int titleLevel;
  final String userAvatar;
  final String userRemark;
  final int userLevel;
  final bool vip;

  /// 读完本书时的累计阅读时长（秒）。
  final int readTotalTimeSeconds;
  final String style;
  final String seal;
  final int popularity;

  /// 是否已公开发布。
  bool get published => statusKnown && status == 2;

  /// 解析接口数据。
  factory ReaMicroBookReview.fromJson(Map<String, Object?> json) {
    return ReaMicroBookReview(
      id: _intValue(json['id']),
      rating: _intValue(json['rating']),
      comment: _stringValue(json['comment']) ?? '',
      status: _intValue(json['status']),
      publishTime: _timestampMillis(json['publishTime']),
      commentUpdateTime: _timestampMillis(json['commentUpdateTime']),
      likeCount: _intValue(json['likeCount']),
      isLiked: json['isLiked'] == true || _intValue(json['isLiked']) > 0,
      bookId: _intValue(json['bookId']),
      bookName: _stringValue(json['bookName']) ?? '',
      bookAuthor: _stringValue(json['bookAuthor']) ?? '',
      bookCover: _stringValue(json['bookCover']) ?? '',
      userId: _intValue(json['userId']),
      userName: _stringValue(json['userName']) ?? '',
      title: _stringValue(json['title']) ?? '',
      titleLevel: _intValue(json['titleLevel']),
      userAvatar: _stringValue(json['userAvatar']) ?? '',
      userRemark: _stringValue(json['userRemark']) ?? '',
      userLevel: _intValue(json['userLevel']),
      vip: json['vip'] == true || _intValue(json['vip']) > 0,
      readTotalTimeSeconds: _intValue(json['readTotalTime']),
      style: _stringValue(json['style']) ?? '',
      seal: _stringValue(json['seal']) ?? '',
      popularity: _intValue(json['popularity']),
      statusKnown: json.containsKey('status'),
    );
  }
}

/// 阅微书评互动用户分页。
class ReaMicroReviewActorPage {
  /// 创建互动用户分页。
  const ReaMicroReviewActorPage({required this.items, required this.total});

  /// 当前页用户。
  final List<ReaMicroReviewActor> items;

  /// 互动用户总数。
  final int total;

  /// 从接口数据解析。
  factory ReaMicroReviewActorPage.fromJson(Map<String, Object?> json) {
    final raw = json['items'];
    return ReaMicroReviewActorPage(
      items: <ReaMicroReviewActor>[
        if (raw is List<Object?>)
          for (final item in raw)
            if (item is Map<String, Object?>)
              ReaMicroReviewActor.fromJson(item),
      ],
      total: _intValue(json['total']),
    );
  }
}

/// 阅微书评互动用户。
class ReaMicroReviewActor {
  /// 创建互动用户。
  const ReaMicroReviewActor({
    required this.userId,
    required this.userName,
    required this.title,
    required this.titleLevel,
    required this.userAvatar,
    required this.userLevel,
    required this.vip,
    required this.actedAt,
    required this.actionType,
    required this.collectionName,
  });

  final int userId;
  final String userName;
  final String title;
  final int titleLevel;
  final String userAvatar;
  final int userLevel;
  final bool vip;

  /// 互动时间（毫秒时间戳）。
  final int actedAt;

  /// 互动类型，0 为点赞。
  final int actionType;

  /// 用户称号或收藏名。
  final String collectionName;

  /// 从接口数据解析。
  factory ReaMicroReviewActor.fromJson(Map<String, Object?> json) =>
      ReaMicroReviewActor(
        userId: _intValue(json['userId']),
        userName: _stringValue(json['userName']) ?? '',
        title: _stringValue(json['title']) ?? '',
        titleLevel: _intValue(json['titleLevel']),
        userAvatar: _stringValue(json['userAvatar']) ?? '',
        userLevel: _intValue(json['userLevel']),
        vip: json['vip'] == true || _intValue(json['vip']) > 0,
        actedAt: _timestampMillis(json['actedAt']),
        actionType: _intValue(json['actionType']),
        collectionName: _stringValue(json['collectionName']) ?? '',
      );
}

/// 当前账号对一条书评已执行过的互动。
class ReaMicroReviewActionState {
  /// 创建互动状态。
  const ReaMicroReviewActionState({required this.actionTypes});

  /// 点赞互动类型。
  static const int likeType = 0;

  /// 已执行过的互动类型。
  final Set<int> actionTypes;

  /// 是否已点赞。
  bool get liked => actionTypes.contains(likeType);

  /// 空状态。
  static const ReaMicroReviewActionState empty = ReaMicroReviewActionState(
    actionTypes: <int>{},
  );

  /// 从接口数据解析。
  factory ReaMicroReviewActionState.fromJson(Map<String, Object?> json) {
    final raw = json['actionTypes'];
    return ReaMicroReviewActionState(
      actionTypes: <int>{
        if (raw is List<Object?>)
          for (final item in raw)
            if (_intValue(item) >= 0) _intValue(item),
      },
    );
  }
}

/// 阅微读完里程碑。
class ReaMicroMilestone {
  /// 创建里程碑。
  const ReaMicroMilestone({
    required this.id,
    required this.rating,
    required this.status,
    required this.ratingTime,
    required this.cloudBookId,
    required this.name,
    required this.author,
    required this.cover,
    required this.comment,
    required this.style,
    required this.seal,
    required this.popularity,
    required this.totalReadTimeSeconds,
    required this.startReadTime,
    required this.readDays,
    required this.lastReadTime,
    required this.maxDayReadDurationSeconds,
    required this.maxDayReadTime,
    required this.immersiveReadTimeSeconds,
    required this.fragmentReadTimeSeconds,
    required this.deepReadTimeSeconds,
    required this.deepFragmentReadTimeSeconds,
    required this.listeningDurationSeconds,
    required this.readingDurationSeconds,
  });

  final int id;
  final int rating;
  final int status;
  final int ratingTime;
  final int cloudBookId;
  final String name;
  final String author;
  final String cover;
  final String comment;
  final String style;
  final String seal;
  final int popularity;
  final int totalReadTimeSeconds;
  final int startReadTime;
  final int readDays;
  final int lastReadTime;
  final int maxDayReadDurationSeconds;
  final int maxDayReadTime;
  final int immersiveReadTimeSeconds;
  final int fragmentReadTimeSeconds;
  final int deepReadTimeSeconds;
  final int deepFragmentReadTimeSeconds;
  final int listeningDurationSeconds;
  final int readingDurationSeconds;

  /// 解析接口数据。
  factory ReaMicroMilestone.fromJson(Map<String, Object?> json) {
    return ReaMicroMilestone(
      id: _intValue(json['id']),
      rating: _intValue(json['rating']),
      status: _intValue(json['status']),
      ratingTime: _timestampMillis(json['ratingTime']),
      cloudBookId: _intValue(json['cloudBookId']),
      name: _stringValue(json['name']) ?? '',
      author: _stringValue(json['author']) ?? '',
      cover: _stringValue(json['cover']) ?? '',
      comment: _stringValue(json['comment']) ?? '',
      style: _stringValue(json['style']) ?? '',
      seal: _stringValue(json['seal']) ?? '',
      popularity: _intValue(json['popularity']),
      totalReadTimeSeconds: _intValue(json['totalReadTime']),
      startReadTime: _timestampMillis(json['startReadTime']),
      readDays: _intValue(json['readDays']),
      lastReadTime: _timestampMillis(json['lastReadTime']),
      maxDayReadDurationSeconds: _intValue(json['maxDayReadDuration']),
      maxDayReadTime: _timestampMillis(json['maxDayReadTime']),
      immersiveReadTimeSeconds: _intValue(json['immersiveReadTime']),
      fragmentReadTimeSeconds: _intValue(json['fragmentReadTime']),
      deepReadTimeSeconds: _intValue(json['deepReadTime']),
      deepFragmentReadTimeSeconds: _intValue(json['deepFragmentReadTime']),
      listeningDurationSeconds: _intValue(json['listeningDuration']),
      readingDurationSeconds: _intValue(json['readingDuration']),
    );
  }
}

/// 阅微账号的对象存储配额。
class ReaMicroStorageQuota {
  /// 创建配额。
  const ReaMicroStorageQuota({
    required this.capacityBytes,
    required this.capacityGib,
    required this.credit,
    required this.usedBytes,
  });

  /// 总容量（字节）。
  final int capacityBytes;

  /// 总容量（GiB，服务端直接返回）。
  final int capacityGib;

  /// 可用于扩容的积分。
  final int credit;

  /// 已使用容量（字节）。
  final int usedBytes;

  /// 已使用比例，无容量时为 0。
  double get usedRatio => capacityBytes <= 0
      ? 0
      : (usedBytes / capacityBytes).clamp(0.0, 1.0).toDouble();

  /// 从接口数据解析。
  factory ReaMicroStorageQuota.fromJson(Map<String, Object?> json) =>
      ReaMicroStorageQuota(
        capacityBytes: _intValue(json['capacityBytes']),
        capacityGib: _intValue(json['capacityGib']),
        credit: _intValue(json['credit']),
        usedBytes: _intValue(json['usedBytes']),
      );
}

/// 一条对象存储积分流水。
class ReaMicroCreditLedgerItem {
  /// 创建流水。
  const ReaMicroCreditLedgerItem({
    required this.action,
    required this.amount,
    required this.balanceAfter,
    required this.objectKey,
    required this.operation,
    required this.createTime,
  });

  /// 积分动作。
  final String action;

  /// 本次变更积分。
  final int amount;

  /// 变更后余额。
  final int balanceAfter;

  /// 关联对象。
  final String objectKey;

  /// 操作说明。
  final String operation;

  /// 发生时间（毫秒时间戳）。
  final int createTime;

  /// 从接口数据解析。
  factory ReaMicroCreditLedgerItem.fromJson(Map<String, Object?> json) =>
      ReaMicroCreditLedgerItem(
        action: _stringValue(json['action']) ?? '',
        amount: _intValue(json['amount']),
        balanceAfter: _intValue(json['balanceAfter']),
        objectKey: _stringValue(json['objectKey']) ?? '',
        operation: _stringValue(json['operation']) ?? '',
        createTime: _timestampMillis(json['createTime']),
      );
}

/// 对象存储积分流水分页。
class ReaMicroCreditLedgerPage {
  /// 创建分页。
  const ReaMicroCreditLedgerPage({required this.items, required this.hasMore});

  /// 当前页流水。
  final List<ReaMicroCreditLedgerItem> items;

  /// 是否还有下一页。
  final bool hasMore;

  /// 从接口数据解析。
  factory ReaMicroCreditLedgerPage.fromJson(Map<String, Object?> json) {
    final raw = json['list'];
    return ReaMicroCreditLedgerPage(
      items: <ReaMicroCreditLedgerItem>[
        if (raw is List<Object?>)
          for (final item in raw)
            if (item is Map<String, Object?>)
              ReaMicroCreditLedgerItem.fromJson(item),
      ],
      hasMore: json['hasMore'] == true,
    );
  }
}

/// 阅微账号保存的 S3 同步配置响应。
class ReaMicroS3CloudConfigResponse {
  /// 创建响应。
  const ReaMicroS3CloudConfigResponse({
    required this.enabled,
    required this.encryptedConfig,
  });

  /// 云端是否启用。
  final bool enabled;

  /// 配置密文。
  final String encryptedConfig;

  /// 从接口数据解析。
  factory ReaMicroS3CloudConfigResponse.fromJson(Map<String, Object?> json) =>
      ReaMicroS3CloudConfigResponse(
        enabled: json['enabled'] == true,
        encryptedConfig: _stringValue(json['encryptedConfig']) ?? '',
      );
}

/// 阅微内置对象存储返回的临时访问地址。
class ReaMicroS3SignedUrl {
  /// 创建访问地址。
  const ReaMicroS3SignedUrl({required this.url});

  /// 上传或下载地址。
  final String url;

  /// 从接口数据解析。
  factory ReaMicroS3SignedUrl.fromJson(Map<String, Object?> json) =>
      ReaMicroS3SignedUrl(url: _stringValue(json['url']) ?? '');
}

/// 阅微内置对象存储的对象状态。
class ReaMicroS3ObjectHead {
  /// 创建对象状态。
  const ReaMicroS3ObjectHead({
    required this.exists,
    required this.contentLength,
    required this.etag,
  });

  /// 对象是否存在。
  final bool exists;

  /// 对象字节数。
  final int contentLength;

  /// 对象 ETag。
  final String etag;

  /// 从接口数据解析。
  factory ReaMicroS3ObjectHead.fromJson(Map<String, Object?> json) =>
      ReaMicroS3ObjectHead(
        exists: json['exists'] == true,
        contentLength: _intValue(json['contentLength']),
        etag: _stringValue(json['etag']) ?? '',
      );
}

/// 阅微朗读引擎下载项。
class ReaMicroTtsEngine {
  /// 创建引擎项。
  const ReaMicroTtsEngine({
    required this.platform,
    required this.abi,
    required this.version,
    required this.downloadUrl,
    required this.sha256,
    required this.size,
  });

  /// 平台标识。
  final String platform;

  /// CPU 架构。
  final String abi;

  /// 引擎版本。
  final String version;

  /// 下载地址。
  final String downloadUrl;

  /// 压缩包校验值。
  final String sha256;

  /// 压缩包字节数。
  final int size;

  /// 从接口数据解析。
  factory ReaMicroTtsEngine.fromJson(Map<String, Object?> json) =>
      ReaMicroTtsEngine(
        platform: _stringValue(json['platform']) ?? '',
        abi: _stringValue(json['abi']) ?? '',
        version: _stringValue(json['version']) ?? '',
        downloadUrl: _stringValue(json['downloadUrl']) ?? '',
        sha256: _stringValue(json['sha256']) ?? '',
        size: _intValue(json['size']),
      );
}

/// 阅微官方离线朗读音色。
class ReaMicroTtsVoice {
  /// 创建音色。
  const ReaMicroTtsVoice({
    required this.id,
    required this.downloadUrl,
    this.name = '',
    this.language = '',
    this.quality = '',
    this.folderName = '',
    this.modelDirectory = '',
    this.numberOfSpeakers = 0,
  });

  /// 音色标识。
  final String id;

  /// 模型下载地址。
  final String downloadUrl;

  /// 显示名称。
  final String name;

  /// 语言。
  final String language;

  /// 音质。
  final String quality;

  /// 解压目录名。
  final String folderName;

  /// 模型目录。
  final String modelDirectory;

  /// 说话人数量。
  final int numberOfSpeakers;

  /// 界面显示名称。
  String get displayName => name.trim().isEmpty ? id : name;

  /// 从接口数据解析。
  factory ReaMicroTtsVoice.fromJson(Map<String, Object?> json) {
    final id = _stringValue(json['id']) ?? '';
    return ReaMicroTtsVoice(
      id: id,
      downloadUrl: _stringValue(json['downloadUrl']) ?? '',
      name: _stringValue(json['name']) ?? '',
      language: _stringValue(json['language']) ?? '',
      quality: _stringValue(json['quality']) ?? '',
      folderName: _stringValue(json['folderName']) ?? '',
      modelDirectory: _stringValue(json['modelDirectory']) ?? '',
      numberOfSpeakers: _intValue(json['numberOfSpeakers']),
    );
  }
}

/// 阅微朗读引擎与音色目录。
class ReaMicroTtsCatalog {
  /// 创建目录。
  const ReaMicroTtsCatalog({required this.engines, required this.voices});

  /// 可下载的离线引擎。
  final List<ReaMicroTtsEngine> engines;

  /// 可下载的官方音色。
  final List<ReaMicroTtsVoice> voices;

  /// 从接口数据解析。
  factory ReaMicroTtsCatalog.fromJson(Map<String, Object?> json) =>
      ReaMicroTtsCatalog(
        engines: <ReaMicroTtsEngine>[
          if (json['engines'] is List<Object?>)
            for (final item in json['engines']! as List<Object?>)
              if (item is Map<String, Object?>)
                ReaMicroTtsEngine.fromJson(item),
        ],
        voices: <ReaMicroTtsVoice>[
          if (json['voices'] is List<Object?>)
            for (final item in json['voices']! as List<Object?>)
              if (item is Map<String, Object?>) ReaMicroTtsVoice.fromJson(item),
        ],
      );
}

/// 阅微写操作结果。
class ReaMicroActionResult {
  /// 创建结果。
  const ReaMicroActionResult({
    required this.success,
    required this.message,
    this.unauthorized = false,
  });

  final bool success;
  final String message;
  final bool unauthorized;
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

List<int> _yearList(Object? value) {
  final years = <int>{};
  if (value is List<Object?>) {
    for (final item in value) {
      final year = item is Map<String, Object?>
          ? _intValue(item['year'])
          : _intValue(item);
      if (year > 0) years.add(year);
    }
  }
  final result = years.toList(growable: false)..sort();
  return result;
}

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
