import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

enum SyncProvider { webdav, s3 }

const syncProtocolVersion = 2;

/// 连接位置与选项；凭证和恢复密钥不进入普通设置或同步数据。
class SyncProfile {
  const SyncProfile({
    required this.provider,
    required this.endpoint,
    this.bucket = '',
    this.region = 'us-east-1',
    this.prefix = 'spectacular-sync',
    this.automatic = true,
    this.preferences = false,
    this.resources = false,
  });

  final SyncProvider provider;
  final String endpoint;
  final String bucket;
  final String region;
  final String prefix;
  final bool automatic;
  final bool preferences;
  final bool resources;

  Uri get uri => Uri.parse(endpoint.trim().replaceAll(RegExp(r'/+$'), ''));
  String get directory => prefix.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  String get identity => syncDigest({
    'provider': provider.name,
    'endpoint': uri.toString(),
    'bucket': bucket.trim(),
    'prefix': directory,
  });

  void validate() {
    final address = uri;
    final local = const {
      'localhost',
      '127.0.0.1',
      '::1',
    }.contains(address.host);
    if (address.host.isEmpty ||
        (address.scheme != 'https' && !(local && address.scheme == 'http')) ||
        address.userInfo.isNotEmpty ||
        address.hasQuery ||
        address.hasFragment) {
      throw const FormatException('请使用不含账号、查询参数的 HTTPS 服务地址');
    }
    if (directory.isEmpty) throw const FormatException('同步目录不能为空');
    validateSyncPath(directory);
    if (provider == SyncProvider.s3 &&
        (bucket.trim().isEmpty || region.trim().isEmpty)) {
      throw const FormatException('请填写 S3 存储桶与区域');
    }
  }

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'endpoint': endpoint,
    'bucket': bucket,
    'region': region,
    'prefix': prefix,
    'automatic': automatic,
    'preferences': preferences,
    'resources': resources,
  };

  factory SyncProfile.fromJson(Map<String, dynamic> json) => SyncProfile(
    provider: SyncProvider.values.byName(json['provider'] as String),
    endpoint: json['endpoint'] as String,
    bucket: json['bucket'] as String,
    region: json['region'] as String,
    prefix: json['prefix'] as String,
    automatic: json['automatic'] as bool,
    preferences: json['preferences'] as bool,
    resources: json['resources'] as bool,
  );
}

class SyncCredentials {
  const SyncCredentials({
    this.access = '',
    this.secret = '',
    this.recovery = '',
  });
  final String access;
  final String secret;
  final String recovery;

  Map<String, String> toJson() => {
    'access': access,
    'secret': secret,
    'recovery': recovery,
  };
  factory SyncCredentials.fromJson(Map<String, dynamic> json) =>
      SyncCredentials(
        access: json['access'] as String,
        secret: json['secret'] as String,
        recovery: json['recovery'] as String,
      );
}

/// 业务快照与操作共用稳定键；删除保留数据，图书历史仍可显示。
class SyncEntity {
  const SyncEntity(this.key, this.data, {this.deleted = false});
  final String key;
  final Map<String, dynamic> data;
  final bool deleted;
  String get type => key.split('/').first;
  String get id => key.substring(type.length + 1);
  String get digest => syncDigest({
    'data': type == 'book'
        ? (Map<String, dynamic>.of(data)
            ..remove('uuid')
            ..remove('aliases'))
        : data,
    'deleted': deleted,
  });
}

/// 实体级版本向量区分因果更新与并发更新，不依赖设备时钟。
class SyncRecord extends SyncEntity {
  const SyncRecord(
    super.key,
    super.data, {
    required this.device,
    required this.clock,
    required this.vector,
    super.deleted,
  });
  final String device;
  final int clock;
  final Map<String, int> vector;
  String get version => '$clock:$device';

  bool covers(SyncRecord other) => other.vector.entries.every(
    (entry) => (vector[entry.key] ?? 0) >= entry.value,
  );

  SyncRecord observed(SyncRecord other) => SyncRecord(
    key,
    data,
    device: device,
    clock: clock,
    deleted: deleted,
    vector: {
      ...vector,
      for (final entry in other.vector.entries)
        entry.key: max(vector[entry.key] ?? 0, entry.value),
    },
  );

  Map<String, Object?> toJson() => {
    'key': key,
    'data': data,
    'deleted': deleted,
    'device': device,
    'clock': clock,
    'vector': vector,
  };

  factory SyncRecord.fromJson(Map<String, dynamic> json) {
    final key = json['key'] as String;
    if (!syncTypes.contains(key.split('/').first) || !key.contains('/')) {
      throw const FormatException('同步数据包含未知类型');
    }
    final vector = Map<String, int>.from(json['vector'] as Map);
    final device = json['device'] as String;
    final clock = json['clock'] as int;
    if (clock <= 0 ||
        vector[device] != clock ||
        vector.values.any((value) => value <= 0)) {
      throw const FormatException('同步修订版本无效');
    }
    return SyncRecord(
      key,
      Map<String, dynamic>.from(json['data'] as Map),
      deleted: json['deleted'] as bool,
      device: device,
      clock: clock,
      vector: vector,
    );
  }
}

const syncTypes = {
  'book',
  'activity',
  'reading_progress',
  'annotations',
  'decorations',
  'decoration_rule_groups',
  'decoration_rules',
  'book_reviews',
  'reading_sessions',
  'shelf_groups',
  'shelf_group_books',
  'book_tags',
  'book_tag_links',
  'user_fonts',
  'setting',
  'list',
  'list_member',
  'book_color',
  'decoration_style',
  'decoration_selection',
};

String syncDigest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_sortedJson(value)))).toString();

Object? _sortedJson(Object? value) {
  if (value is List) return value.map(_sortedJson).toList();
  if (value is! Map) return value;
  final keys = value.keys.cast<String>().toList()..sort();
  return {for (final key in keys) key: _sortedJson(value[key])};
}

String newSyncId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256),
).map((value) => value.toRadixString(16).padLeft(2, '0')).join();

void validateSyncPath(String path) {
  if (path.startsWith('/') ||
      path.contains('\\') ||
      path.runes.any((value) => value < 32) ||
      path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const FormatException('同步路径无效');
  }
}
