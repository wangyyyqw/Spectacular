import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cloud_models.dart';

abstract interface class CloudAccountStore {
  Future<CloudAccount?> read(CloudDrive drive);
  Future<void> save(CloudAccount account);
  Future<void> remove(CloudDrive drive);
}

/// 每个网盘独立保存；安全存储失败时不回退普通文件或同步设置。
class SecureCloudAccounts implements CloudAccountStore {
  final _storage = Platform.isMacOS
      ? const FlutterSecureStorage(
          mOptions: MacOsOptions(usesDataProtectionKeychain: false),
        )
      : const FlutterSecureStorage();
  String _key(CloudDrive drive) => 'spectacular.cloud.${drive.name}';

  @override
  Future<CloudAccount?> read(CloudDrive drive) async {
    final value = await _storage.read(key: _key(drive));
    if (value == null) return null;
    try {
      return CloudAccount.fromJson(
        drive,
        jsonDecode(value) as Map<String, dynamic>,
      );
    } on Object {
      throw const CloudException('已保存的网盘登录信息无法读取，请重新登录');
    }
  }

  @override
  Future<void> save(CloudAccount account) => _storage.write(
    key: _key(account.drive),
    value: jsonEncode(account.toJson()),
  );

  @override
  Future<void> remove(CloudDrive drive) => _storage.delete(key: _key(drive));
}
