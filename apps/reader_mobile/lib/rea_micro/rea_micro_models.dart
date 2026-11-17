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
