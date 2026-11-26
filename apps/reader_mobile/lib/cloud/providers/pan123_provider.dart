import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart' show getCrc32;

import '../cloud_http.dart';
import '../cloud_models.dart';

class Pan123CloudProvider implements CloudProviderApi {
  Pan123CloudProvider(this.http);
  final CloudHttp http;
  static const _host = 'yun.123pan.cn';
  @override
  CloudDrive get drive => CloudDrive.pan123;
  @override
  String get rootId => '0';

  static String _crc(String value) =>
      getCrc32(utf8.encode(value)).toRadixString(16);

  /// 由请求路径、时间和随机数生成网页版认证头，不保存账号密码。
  Map<String, String> _headers(CloudAccount account, String path) {
    final access = account
        .field('accessToken')
        .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
    if (access.isEmpty) {
      throw const CloudException('请先登录 123 网盘', loginRequired: true);
    }
    final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final time = DateTime.fromMillisecondsSinceEpoch(
      (seconds + 57600) * 1000,
      isUtc: true,
    );
    final digits =
        '${time.year}${time.month.toString().padLeft(2, '0')}'
        '${time.day.toString().padLeft(2, '0')}${time.hour.toString().padLeft(2, '0')}'
        '${time.minute.toString().padLeft(2, '0')}';
    const alphabet = 'adefghlmyijnopkqrstubcvwsz';
    final key = _crc(
      digits.split('').map((digit) => alphabet[int.parse(digit)]).join(),
    );
    final nonce = Random.secure().nextInt(10000000);
    account.fields.putIfAbsent('loginUuid', () {
      final random = Random.secure();
      return List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
    });
    return {
      'Authorization': 'Bearer $access',
      'platform': 'web',
      'app-version': '3',
      'loginuuid': account.field('loginUuid'),
      'auth-key': key,
      'auth-value':
          '$seconds-$nonce-${_crc('$seconds|$nonce|$path|web|3|$key')}',
      'Origin': 'https://$_host',
      'Referer': 'https://$_host/',
    };
  }

  Future<Map<String, dynamic>> _request(
    CloudAccount account,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final response = await http.send(
      Uri.https(_host, path, query),
      method: body == null ? 'GET' : 'POST',
      headers: _headers(account, path),
      json: body,
      allowErrorStatus: true,
    );
    if (response.status == 401) {
      throw const CloudException('123 登录已失效，请重新登录', loginRequired: true);
    }
    final json = response.json;
    final code = cloudInt(json['code']);
    if ({401, 20101}.contains(code)) {
      throw const CloudException('123 登录已失效，请重新登录', loginRequired: true);
    }
    if (response.status == 429 || {429, 100011}.contains(code)) {
      throw const CloudException('123 请求过于频繁，请稍后重试');
    }
    if (response.status >= 300 ||
        !json.containsKey('code') ||
        code != 0 ||
        json['data'] is! Map) {
      throw const CloudException('123 网盘请求失败，请检查文件权限后重试');
    }
    return cloudMap(json['data']);
  }

  @override
  Future<String> validate(CloudAccount account) async {
    final data = await _request(account, '/b/api/user/info');
    final user = cloudText(
      data['UID'] ??
          data['Uid'] ??
          data['uid'] ??
          data['UserId'] ??
          data['userId'],
    );
    final name = cloudText(data['Nickname']);
    if (user.isEmpty && name.isEmpty) {
      throw const CloudException('123 未返回有效账号信息，请重新登录');
    }
    if (user.isNotEmpty &&
        account.field('userId').isNotEmpty &&
        user != account.field('userId')) {
      throw const CloudException('123 账号已变化，请重新登录', loginRequired: true);
    }
    if (user.isNotEmpty) account.fields['userId'] = user;
    await list(account, rootId);
    return name.isEmpty ? drive.label : name;
  }

  @override
  Future<CloudListing> list(
    CloudAccount account,
    String folderId, {
    String? cursor,
  }) async {
    final data = await _request(
      account,
      '/b/api/file/list/new',
      query: {
        'driveId': '0',
        'parentFileId': folderId,
        'limit': '100',
        'next': cursor ?? '0',
        'orderBy': 'file_name',
        'orderDirection': 'asc',
        'trashed': 'false',
        'SearchData': '',
        'Page': '1',
        'OnlyLookAbnormalFile': '0',
        'event': 'homeListFile',
        'operateType': '1',
        'inDirectSpace': 'false',
      },
    );
    return _listing(data, cursor);
  }

  CloudListing _listing(Map<String, dynamic> data, String? cursor) {
    final rows = data['InfoList'] is Map
        ? cloudMap(data['InfoList'])['list']
        : data['InfoList'] ?? data['infoList'];
    if (rows is! List) throw const CloudException('123 文件列表不完整，请刷新目录');
    final entries = rows.map((raw) {
      final item = cloudMap(raw);
      final id = cloudText(item['FileId']);
      final name = cloudText(item['FileName']);
      if (id.isEmpty || name.isEmpty) {
        throw const CloudException('123 文件信息不完整，请刷新目录');
      }
      return CloudEntry(
        id: id,
        name: name,
        isFolder: cloudInt(item['Type']) == 1,
        size: cloudInt(item['Size']),
        extra: {
          'etag': cloudText(item['Etag']),
          's3keyFlag': cloudText(item['S3KeyFlag']),
        },
      );
    }).toList();
    final next = cloudText(data['Next']);
    if (entries.isNotEmpty &&
        cursor != null &&
        next != '-1' &&
        next == cursor) {
      throw const CloudException('123 目录分页重复，请刷新目录');
    }
    return CloudListing(
      entries,
      nextPage: entries.isEmpty || !data.containsKey('Next') || next == '-1'
          ? null
          : next,
    );
  }

  @override
  Future<CloudDownload> resolve(CloudAccount account, CloudEntry file) async {
    final id = int.tryParse(file.id);
    if (file.isFolder || id == null || id <= 0) {
      throw const CloudException('请选择有效的 EPUB 或 TXT 文件');
    }
    final data = await _request(
      account,
      '/api/file/download_info',
      body: {
        'driveId': 0,
        'type': 0,
        'fileId': id,
        'fileName': file.name,
        'size': file.size,
        'etag': cloudText(file.extra['etag']),
        's3keyFlag': cloudText(file.extra['s3keyFlag']),
      },
    );
    return CloudDownload(
      await _downloadTarget(_decodeAddress(cloudText(data['DownloadUrl']))),
      size: file.size,
      headers: const {
        'Referer': 'https://yun.123pan.cn/',
        'User-Agent': cloudUserAgent,
      },
    );
  }

  Uri _decodeAddress(String wrapped) {
    final uri = Uri.tryParse(wrapped);
    final encoded = uri?.hasScheme == true
        ? uri!.queryParameters['params']
        : wrapped;
    String address = wrapped;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        address = utf8.decode(base64.decode(base64.normalize(encoded)));
      } on FormatException {
        throw const CloudException('123 下载地址解析失败，请重新获取');
      }
    }
    if (uri?.path.contains('download-v2') == true && address == wrapped) {
      throw const CloudException('123 未返回原文件地址，请稍后重试');
    }
    return cloudUrl(address);
  }

  Future<Uri> _downloadTarget(Uri address) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final response = await http.send(
        address,
        headers: const {
          'Range': 'bytes=0-4095',
          'Referer': 'https://yun.123pan.cn/',
        },
        maxBodyBytes: 4096,
      );
      final location = response.headers['location'];
      if (response.status >= 300 && response.status < 400 && location != null) {
        address = cloudUrl(address.resolve(location).toString());
        continue;
      }
      if (!response.body.trimLeft().startsWith('{') ||
          !(response.headers['content-type'] ?? '').contains(
            'application/json',
          )) {
        return address;
      }
      final data = response.json;
      final next = cloudText(cloudMap(data['data'])['redirect_url']);
      if (next.isEmpty) {
        if (data.containsKey('code') && cloudInt(data['code']) != 0) {
          throw const CloudException('123 暂未生成文件下载地址，请稍后重试');
        }
        return address;
      }
      address = cloudUrl(next);
    }
    throw const CloudException('123 下载地址跳转过多，请重试');
  }
}
