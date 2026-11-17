import 'dart:convert';
import 'dart:math';

import '../library/library_store.dart';
import 'rea_micro_models.dart';
import 'rea_micro_s3.dart';

/// 阅微登录凭据、缓存账号与书籍关联的本地存储。
///
/// 令牌保存在应用私有的设置表中，不写入日志，也不导出到诊断文件。
class ReaMicroStore {
  /// 创建设置存储。
  ReaMicroStore(this._library);

  final LibraryStore _library;

  static const String _tokenKey = 'reamicro.auth.token';
  static const String _userKey = 'reamicro.auth.user';
  static const String _linksKey = 'reamicro.book.links';
  static const String _uploadedKey = 'reamicro.sync.uploaded';
  static const String _watermarksKey = 'reamicro.sync.watermarks';
  static const String _lastSyncKey = 'reamicro.sync.lastAt';
  static const String _progressKey = 'reamicro.progress.state';
  static const String _deviceIdKey = 'reamicro.device.id';
  static const String _cloudPrimaryKey = 'reamicro.cloud.primary';
  static const String _s3ConfigKey = 'reamicro.s3.config';
  static const String _s3LastSyncKey = 'reamicro.s3.lastAt';
  static const String _s3BookmarkBasesKey = 'reamicro.s3.bookmark.bases';
  static const int _maxUploadedKeys = 5000;

  /// 读取访问令牌。
  Future<String?> loadToken() async {
    final token = (await _library.getSetting(_tokenKey))?.trim();
    return token == null || token.isEmpty ? null : token;
  }

  /// 保存访问令牌。
  Future<void> saveToken(String token) =>
      _library.setSetting(_tokenKey, token.trim());

  /// 清除账号信息与令牌，保留书籍关联和同步台账。
  Future<void> clearAuth() async {
    await _library.setSetting(_tokenKey, '');
    await _library.setSetting(_userKey, '');
  }

  /// 读取上次缓存的账号信息；损坏时按未缓存处理。
  Future<ReaMicroUser?> loadCachedUser() async {
    final raw = await _library.getSetting(_userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?>
          ? ReaMicroUser.fromJson(decoded)
          : null;
    } on FormatException {
      return null;
    }
  }

  /// 缓存账号信息，供离线打开时展示。
  Future<void> saveCachedUser(ReaMicroUser user) =>
      _library.setSetting(_userKey, jsonEncode(user.toJson()));

  /// 读取本地书籍与阅微云端书籍的关联。
  Future<Map<String, ReaMicroBookLink>> loadLinks() async {
    final raw = await _library.getSetting(_linksKey);
    if (raw == null || raw.isEmpty) {
      return <String, ReaMicroBookLink>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return <String, ReaMicroBookLink>{};
      }
      final links = <String, ReaMicroBookLink>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is Map<String, Object?>) {
          final link = ReaMicroBookLink.fromJson(value);
          if (link.cloudBookId > 0) links[entry.key] = link;
        }
      }
      return links;
    } on FormatException {
      return <String, ReaMicroBookLink>{};
    }
  }

  /// 保存书籍关联。
  Future<void> saveLinks(Map<String, ReaMicroBookLink> links) =>
      _library.setSetting(
        _linksKey,
        jsonEncode(<String, Object?>{
          for (final entry in links.entries) entry.key: entry.value.toJson(),
        }),
      );

  /// 读取已上报的阅读时段台账，用于跨启动去重。
  Future<Set<String>> loadUploadedSessionKeys() async {
    final raw = await _library.getSetting(_uploadedKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) return <String>{};
      return <String>{
        for (final item in decoded)
          if (item is String && item.isNotEmpty) item,
      };
    } on FormatException {
      return <String>{};
    }
  }

  /// 保存上报台账，只保留最近的项目以避免设置值无限增长。
  Future<void> saveUploadedSessionKeys(Set<String> keys) {
    final values = keys.toList(growable: false);
    final start = values.length > _maxUploadedKeys
        ? values.length - _maxUploadedKeys
        : 0;
    return _library.setSetting(_uploadedKey, jsonEncode(values.sublist(start)));
  }

  /// 读取每本本地书籍已处理到的会话结束时间。
  ///
  /// 水位用于在去重台账截断后仍跳过旧会话，避免重复累加云端阅读时长。
  Future<Map<String, int>> loadSessionWatermarks() async {
    final raw = await _library.getSetting(_watermarksKey);
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return <String, int>{};
      return <String, int>{
        for (final entry in decoded.entries)
          if (entry.value is num) entry.key: (entry.value! as num).toInt(),
      };
    } on FormatException {
      return <String, int>{};
    }
  }

  /// 保存每本本地书籍已处理到的会话结束时间。
  Future<void> saveSessionWatermarks(Map<String, int> values) =>
      _library.setSetting(_watermarksKey, jsonEncode(values));

  /// 读取上次成功同步时间。
  Future<DateTime?> loadLastSyncAt() async {
    final value = int.tryParse(await _library.getSetting(_lastSyncKey) ?? '');
    return value == null || value <= 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value);
  }

  /// 保存上次成功同步时间。
  Future<void> saveLastSyncAt(DateTime value) => _library.setSetting(
    _lastSyncKey,
    value.millisecondsSinceEpoch.toString(),
  );

  /// 读取每本本地书籍的进度同步状态。
  Future<Map<String, ReaMicroProgressState>> loadProgressStates() async {
    final raw = await _library.getSetting(_progressKey);
    if (raw == null || raw.isEmpty) {
      return <String, ReaMicroProgressState>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return <String, ReaMicroProgressState>{};
      }
      return <String, ReaMicroProgressState>{
        for (final entry in decoded.entries)
          if (entry.value is Map<String, Object?>)
            entry.key: ReaMicroProgressState.fromJson(
              entry.value! as Map<String, Object?>,
            ),
      };
    } on FormatException {
      return <String, ReaMicroProgressState>{};
    }
  }

  /// 保存每本本地书籍的进度同步状态。
  Future<void> saveProgressStates(Map<String, ReaMicroProgressState> states) =>
      _library.setSetting(
        _progressKey,
        jsonEncode(<String, Object?>{
          for (final entry in states.entries) entry.key: entry.value.toJson(),
        }),
      );

  /// 切换账号时清除进度时间戳，避免把另一账号的位置当成已同步状态。
  Future<void> clearProgressStates() => _library.setSetting(_progressKey, '');

  /// 读取是否把阅微作为唯一阅读数据源。
  Future<bool> loadCloudPrimary() async =>
      (await _library.getSetting(_cloudPrimaryKey)) == '1';

  /// 保存唯一数据源选择。
  Future<void> saveCloudPrimary(bool value) =>
      _library.setSetting(_cloudPrimaryKey, value ? '1' : '0');

  /// 读取 S3 同步配置；缺失或损坏时返回 null。
  Future<ReaMicroS3Config?> loadS3Config() async {
    final raw = await _library.getSetting(_s3ConfigKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final config = ReaMicroS3Config.fromJson(decoded);
      return config.usable ? config : null;
    } on FormatException {
      return null;
    }
  }

  /// 保存 S3 同步配置；密钥只写入应用私有设置表。
  Future<void> saveS3Config(ReaMicroS3Config config) =>
      _library.setSetting(_s3ConfigKey, jsonEncode(config.toJson()));

  /// 清除 S3 同步配置。
  Future<void> clearS3Config() => _library.setSetting(_s3ConfigKey, '');

  /// 读取 S3 上次同步时间。
  Future<DateTime?> loadS3LastSyncAt() async {
    final value = int.tryParse(await _library.getSetting(_s3LastSyncKey) ?? '');
    return value == null || value <= 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value);
  }

  /// 保存 S3 上次同步时间。
  Future<void> saveS3LastSyncAt(DateTime value) => _library.setSetting(
    _s3LastSyncKey,
    value.millisecondsSinceEpoch.toString(),
  );

  /// 读取每本书上次与云端一致的书签文件哈希。
  Future<Map<String, String>> loadS3BookmarkBases() async {
    final raw = await _library.getSetting(_s3BookmarkBasesKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return <String, String>{};
      return <String, String>{
        for (final entry in decoded.entries)
          if (entry.value is String && (entry.value! as String).isNotEmpty)
            entry.key: entry.value! as String,
      };
    } on FormatException {
      return <String, String>{};
    }
  }

  /// 保存书签文件同步基准。
  Future<void> saveS3BookmarkBases(Map<String, String> values) =>
      _library.setSetting(_s3BookmarkBasesKey, jsonEncode(values));

  /// 清除书签文件同步基准。
  Future<void> clearS3BookmarkBases() =>
      _library.setSetting(_s3BookmarkBasesKey, '');

  /// 读取或生成用于区分本机的设备标识。
  Future<String> loadOrCreateDeviceId() async {
    final existing = (await _library.getSetting(_deviceIdKey))?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final value = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await _library.setSetting(_deviceIdKey, value);
    return value;
  }
}
