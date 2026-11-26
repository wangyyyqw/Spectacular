import '../cloud_http.dart';
import '../cloud_models.dart';
import 'aliyun_device.dart';

class AliyunCloudProvider implements CloudProviderApi {
  AliyunCloudProvider(this.http);
  final CloudHttp http;
  static const _api = 'https://api.aliyundrive.com';
  static const _authErrors = {
    'AccessTokenInvalid',
    'AccessTokenExpired',
    'InvalidAccessToken',
    'InvalidParameter.RefreshToken',
  };
  static const _deviceErrors = {
    'DeviceSessionSignatureInvalid',
    'DeviceSessionNotFound',
    'UserDeviceOffline',
    'SignatureInvalid',
    'InvalidDeviceSession',
  };
  @override
  CloudDrive get drive => CloudDrive.aliyun;
  @override
  String get rootId => 'root';

  @override
  Future<String> validate(CloudAccount account) async {
    await _profile(account);
    await list(account, rootId);
    return account.name.isEmpty ? drive.label : account.name;
  }

  Map<String, String> _headers(CloudAccount account, {String? canary}) => {
    'Authorization': 'Bearer ${account.field('accessToken')}',
    'Referer': 'https://www.alipan.com/',
    'Origin': 'https://www.alipan.com',
    'X-Canary': canary ?? 'client=web,app=adrive,version=v6.8.12',
    'X-Request-Id': AliyunDevice.randomHex(16),
    if (account.field('deviceId').isNotEmpty)
      'X-Device-Id': account.field('deviceId'),
  };

  Map<String, dynamic> _checked(CloudResponse response) {
    if (response.status == 401) {
      throw const CloudException('阿里云盘登录已失效，请重新登录', loginRequired: true);
    }
    final data = response.json;
    final code = cloudText(data['code']);
    if (_authErrors.contains(code)) {
      throw const CloudException('阿里云盘登录已失效，请重新登录', loginRequired: true);
    }
    if (response.status == 429 || code.contains('TooManyRequests')) {
      throw const CloudException('阿里云盘请求过于频繁，请稍后重试');
    }
    if (response.status >= 300 ||
        code.isNotEmpty && code != '0' ||
        data['success'] == false) {
      throw const CloudException('阿里云盘请求失败，请检查文件权限后重试');
    }
    return data;
  }

  Future<void> _refresh(CloudAccount account) async {
    final refresh = account.field('refreshToken');
    if (refresh.isEmpty) {
      throw const CloudException('阿里云盘登录已失效，请重新登录', loginRequired: true);
    }
    final response = await http.send(
      Uri.parse('https://auth.aliyundrive.com/v2/account/token'),
      method: 'POST',
      json: {'grant_type': 'refresh_token', 'refresh_token': refresh},
      allowErrorStatus: true,
    );
    final data = _checked(response);
    final token = cloudText(data['access_token']);
    final user = cloudText(data['user_id']);
    if (token.isEmpty ||
        user.isNotEmpty &&
            account.field('userId').isNotEmpty &&
            user != account.field('userId')) {
      throw const CloudException('阿里返回的账号凭据不一致，请重新登录', loginRequired: true);
    }
    account.fields['accessToken'] = token;
    if (cloudText(data['refresh_token']).isNotEmpty) {
      account.fields['refreshToken'] = cloudText(data['refresh_token']);
    }
    if (user.isNotEmpty) account.fields['userId'] = user;
    final seconds = cloudInt(data['expires_in']);
    account.fields['expiresAt'] = seconds > 0
        ? '${DateTime.now().millisecondsSinceEpoch + seconds * 1000}'
        : '';
  }

  Future<void> _fresh(CloudAccount account) async {
    final raw = account.field('expiresAt');
    final expiry =
        int.tryParse(raw) ??
        DateTime.tryParse(raw)?.millisecondsSinceEpoch ??
        0;
    if (account.field('accessToken').isEmpty ||
        expiry > 0 && expiry <= DateTime.now().millisecondsSinceEpoch + 60000) {
      await _refresh(account);
    }
  }

  Future<void> _device(CloudAccount account) async {
    final expiry = cloudInt(account.field('sessionExpiresAt'));
    if (account.field('signature').isNotEmpty &&
        expiry > DateTime.now().millisecondsSinceEpoch + 60000) {
      return;
    }
    if (account.field('devicePrivateKey').isEmpty) {
      account.fields['devicePrivateKey'] = AliyunDevice.newKey();
    }
    if (account.field('deviceId').isEmpty) {
      account.fields['deviceId'] = AliyunDevice.randomHex(16);
    }
    final signed = AliyunDevice.sign(account);
    final response = await http.send(
      Uri.parse('$_api/users/v1/users/device/create_session'),
      method: 'POST',
      headers: {..._headers(account), 'X-Signature': signed.signature},
      json: {
        'deviceName': 'Spectacular',
        'modelName': 'Windows网页版',
        'pubKey': signed.publicKey,
      },
      allowErrorStatus: true,
    );
    if (_checked(response)['result'] != true) {
      throw const CloudException('阿里设备授权失败，请在官网检查登录设备后重试');
    }
    account.fields.addAll({
      'signature': signed.signature,
      'sessionExpiresAt':
          '${DateTime.now().millisecondsSinceEpoch + 20 * 60000}',
    });
  }

  Future<Map<String, dynamic>> _post(
    CloudAccount account,
    String path,
    Map<String, dynamic> body, {
    bool signed = true,
    String? canary,
  }) async {
    await _fresh(account);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (signed) await _device(account);
        final response = await http.send(
          Uri.parse(path.startsWith('https:') ? path : '$_api$path'),
          method: 'POST',
          json: body,
          allowErrorStatus: true,
          headers: {
            ..._headers(account, canary: canary),
            if (signed) 'X-Signature': account.field('signature'),
          },
        );
        if (response.status != 401 &&
            attempt == 0 &&
            _deviceErrors.contains(response.json['code'])) {
          account.fields.remove('signature');
          continue;
        }
        return _checked(response);
      } on CloudException catch (error) {
        if (!error.loginRequired || attempt != 0) rethrow;
        await _refresh(account);
      }
    }
    throw const CloudException('阿里设备会话已失效，请重新登录', loginRequired: true);
  }

  Future<void> _profile(CloudAccount account) async {
    final data = await _post(
      account,
      'https://user.aliyundrive.com/v2/user/get',
      {},
      signed: false,
    );
    final user = cloudText(data['user_id']);
    if (user.isEmpty ||
        account.field('userId').isNotEmpty && user != account.field('userId')) {
      throw const CloudException('阿里账号身份校验失败，请重新登录', loginRequired: true);
    }
    account.fields['userId'] = user;
    for (final pair in const {
      'default_drive_id': 'defaultDriveId',
      'resource_drive_id': 'resourceDriveId',
      'backup_drive_id': 'backupDriveId',
    }.entries) {
      if (cloudText(data[pair.key]).isNotEmpty) {
        account.fields[pair.value] = cloudText(data[pair.key]);
      }
    }
    account.name = cloudText(data['nick_name'] ?? data['name']);
  }

  Future<String> _drive(CloudAccount account) async {
    if (account.field('userId').isEmpty ||
        account.field('resourceDriveId').isEmpty &&
            account.field('defaultDriveId').isEmpty) {
      await _profile(account);
    }
    final id = account.field('resourceDriveId').isNotEmpty
        ? account.field('resourceDriveId')
        : account.field('defaultDriveId');
    if (id.isEmpty) throw const CloudException('阿里云盘未返回可访问的个人空间');
    return id;
  }

  @override
  Future<CloudListing> list(
    CloudAccount account,
    String folderId, {
    String? cursor,
  }) async {
    final driveId = await _drive(account);
    final data = await _post(account, '/adrive/v3/file/list', {
      'drive_id': driveId,
      'parent_file_id': folderId,
      'limit': 100,
      'marker': cursor ?? '',
      'fields': '*',
      'all': false,
      'order_by': 'name',
      'order_direction': 'ASC',
    });
    if (data['items'] is! List) throw const CloudException('阿里文件列表不完整，请重试');
    final entries = (data['items'] as List)
        .map((raw) => _entry(cloudMap(raw), driveId))
        .toList();
    final next = cloudText(data['next_marker']);
    if (next.isNotEmpty && next == cursor) {
      throw const CloudException('阿里目录分页重复，请刷新目录');
    }
    return CloudListing(entries, nextPage: next.isEmpty ? null : next);
  }

  CloudEntry _entry(Map<String, dynamic> item, String driveId) {
    final id = cloudText(item['file_id']), name = cloudText(item['name']);
    if (id.isEmpty || name.isEmpty) {
      throw const CloudException('阿里文件信息不完整，请刷新目录');
    }
    return CloudEntry(
      id: id,
      name: name,
      isFolder: item['type'] == 'folder',
      size: cloudInt(item['size']),
      extra: {'driveId': driveId},
    );
  }

  @override
  Future<CloudDownload> resolve(CloudAccount account, CloudEntry file) async {
    if (file.isFolder) throw const CloudException('请选择 EPUB 或 TXT 文件');
    final driveId = await _drive(account);
    if (file.extra['driveId'] != null && file.extra['driveId'] != driveId) {
      throw const CloudException('阿里文件所属空间已变化，请重新打开目录');
    }
    final data = await _downloadInfo(account, file, driveId);
    final address = cloudText(data['download_url']);
    if (data['type'] == 'folder' ||
        cloudText(data['file_id']).isNotEmpty &&
            cloudText(data['file_id']) != file.id ||
        file.size > 0 &&
            cloudInt(data['size']) > 0 &&
            cloudInt(data['size']) != file.size) {
      throw const CloudException('阿里源文件已变化，请刷新目录后重试');
    }
    return CloudDownload(
      cloudUrl(address),
      size: file.size,
      headers: {
        'Referer': 'https://www.aliyundrive.com/',
        'User-Agent': cloudUserAgent,
      },
    );
  }

  Future<Map<String, dynamic>> _downloadInfo(
    CloudAccount account,
    CloudEntry file,
    String driveId,
  ) async {
    var data = await _post(account, '/v2/file/get_download_url', {
      'drive_id': driveId,
      'file_id': file.id,
      'expire_sec': 14400,
    }, canary: 'client=Android,app=adrive,version=v4.1.0');
    var address = cloudText(
      data['download_url'] ?? data['cdn_url'] ?? data['url'],
    );
    if (address.isEmpty) {
      data = await _post(account, '/v2/file/get', {
        'drive_id': driveId,
        'file_id': file.id,
        'fields': '*',
        'url_expire_sec': 14400,
      }, canary: 'client=Android,app=adrive,version=v4.1.0');
      address = cloudText(data['download_url']);
    }
    return {...data, 'download_url': address};
  }
}
