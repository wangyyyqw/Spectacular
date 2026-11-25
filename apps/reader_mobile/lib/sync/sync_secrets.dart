import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sync_models.dart';

abstract interface class SyncSecretStore {
  Future<SyncCredentials?> read(String identity);
  Future<void> write(String identity, SyncCredentials credentials);
}

/// 不提供普通文件或 settings 明文回退；系统安全存储失败时明确停止。
class PlatformSyncSecrets implements SyncSecretStore {
  // 本应用不跨应用共享钥匙串，macOS 使用普通系统钥匙串避免新增分发签名权限。
  final _storage = Platform.isMacOS
      ? const FlutterSecureStorage(
          mOptions: MacOsOptions(usesDataProtectionKeychain: false),
        )
      : const FlutterSecureStorage();

  @override
  Future<SyncCredentials?> read(String identity) async {
    final value = await _storage.read(key: 'spectacular.sync.$identity');
    return value == null
        ? null
        : SyncCredentials.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> write(String identity, SyncCredentials credentials) =>
      _storage.write(
        key: 'spectacular.sync.$identity',
        value: jsonEncode(credentials.toJson()),
      );
}
