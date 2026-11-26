import 'dart:convert';

import '../cloud_http.dart';
import '../cloud_models.dart';

class PikPakCloudProvider implements CloudProviderApi {
  PikPakCloudProvider(this.http);
  final CloudHttp http;
  static const _user = 'https://user.mypikpak.com';
  static const _files = 'https://api-drive.mypikpak.com';
  static const _webClient = 'YUMx5nI8ZU8Ap8pm';
  final _renewals = <CloudAccount, Future<void>>{};

  @override
  CloudDrive get drive => CloudDrive.pikpak;
  @override
  String get rootId => '';

  Map<String, String> _headers(CloudAccount account) {
    if (account.field('clientId') != _webClient ||
        account.field('deviceId').isEmpty) {
      throw const CloudException('PikPak 登录信息不完整，请重新网页登录', loginRequired: true);
    }
    return {
      'Origin': 'https://mypikpak.com',
      'Referer': 'https://mypikpak.com/',
      'X-Client-Id': _webClient,
      'X-Device-Id': account.field('deviceId'),
      'X-Sdk-Version': '8.1.4',
      'X-Protocol-Version': '301',
      if (account.field('accessToken').isNotEmpty)
        'Authorization': 'Bearer ${account.field('accessToken')}',
      if (account.field('captchaToken').isNotEmpty)
        'X-Captcha-Token': account.field('captchaToken'),
    };
  }

  Map<String, dynamic> _check(CloudResponse response) {
    if (response.status == 401) {
      throw const CloudException('PikPak 登录已失效，请重新登录', loginRequired: true);
    }
    final data = response.json;
    final error = cloudText(data['error']);
    if ({
          'unauthenticated',
          'invalid_grant',
          'invalid_refresh_token',
        }.contains(error) ||
        cloudInt(data['error_code']) == 4126) {
      throw const CloudException('PikPak 登录已失效，请重新登录', loginRequired: true);
    }
    if ({
      'captcha_required',
      'captcha_invalid',
      'captcha_token_invalid',
    }.contains(error)) {
      throw const CloudException('PikPak 需要安全验证，请重新网页登录', loginRequired: true);
    }
    if (response.status >= 300 ||
        error.isNotEmpty ||
        cloudInt(data['error_code']) != 0) {
      throw const CloudException('PikPak 未完成请求，请稍后重试');
    }
    return data;
  }

  bool _expires(CloudAccount account) {
    final value = account.field('expiresAt');
    final number = int.tryParse(value);
    final expiry = number == null
        ? DateTime.tryParse(value)
        : DateTime.fromMillisecondsSinceEpoch(
            number < 100000000000 ? number * 1000 : number,
          );
    return account.field('accessToken').isEmpty ||
        expiry != null &&
            expiry.isBefore(DateTime.now().add(const Duration(minutes: 1)));
  }

  Future<void> _renew(CloudAccount account) async {
    final pending = _renewals[account];
    if (pending != null) return pending;
    final refresh = _refresh(account);
    _renewals[account] = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_renewals[account], refresh)) {
        _renewals.removeWhere((key, value) => identical(key, account));
      }
    }
  }

  Future<void> _refresh(CloudAccount account) async {
    if (account.field('refreshToken').isEmpty) {
      throw const CloudException('PikPak 登录已过期，请重新登录', loginRequired: true);
    }
    final data = _check(
      await http.send(
        Uri.parse('$_user/v1/auth/token'),
        method: 'POST',
        headers: _headers(account),
        allowErrorStatus: true,
        json: {
          'client_id': _webClient,
          'grant_type': 'refresh_token',
          'refresh_token': account.field('refreshToken'),
        },
      ),
    );
    final access = cloudText(data['access_token']);
    if (access.isEmpty || RegExp(r'\s').hasMatch(access)) {
      throw const CloudException('PikPak 未返回有效登录令牌', loginRequired: true);
    }
    account.fields['accessToken'] = access;
    final refresh = cloudText(data['refresh_token']);
    if (refresh.isNotEmpty) account.fields['refreshToken'] = refresh;
    final lifetime = cloudInt(data['expires_in']);
    if (lifetime > 0) {
      account.fields['expiresAt'] =
          '${DateTime.now().millisecondsSinceEpoch + lifetime * 1000}';
    } else {
      account.fields.remove('expiresAt');
    }
  }

  Future<Map<String, dynamic>> _get(
    CloudAccount account,
    String path, {
    Map<String, String> parameters = const {},
    bool user = false,
  }) async {
    if (_expires(account)) await _renew(account);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.send(
          Uri.parse('${user ? _user : _files}$path')
              .replace(queryParameters: parameters),
          headers: _headers(account),
          allowErrorStatus: true,
        );
        return _check(response);
      } on CloudException catch (error) {
        if (!error.loginRequired ||
            attempt > 0 ||
            error.message.contains('安全验证')) {
          rethrow;
        }
        await _renew(account);
      }
    }
    throw const CloudException('PikPak 登录已失效，请重新登录', loginRequired: true);
  }

  @override
  Future<String> validate(CloudAccount account) async {
    final data = await _get(account, '/v1/user/me', user: true);
    final identity = cloudText(data['sub']);
    if (identity.isEmpty ||
        account.field('userId').isNotEmpty &&
            account.field('userId') != identity) {
      throw const CloudException('PikPak 登录账号不一致，请重新登录', loginRequired: true);
    }
    account.fields['userId'] = identity;
    final name = cloudText(data['name']);
    return name.isEmpty ? 'PikPak' : name;
  }

  @override
  Future<CloudListing> list(
    CloudAccount account,
    String folderId, {
    String? cursor,
  }) async {
    final data = await _get(
      account,
      '/drive/v1/files',
      parameters: {
        'parent_id': folderId,
        'limit': '500',
        'page_token': cursor ?? '',
        'thumbnail_size': 'SIZE_SMALL',
        'with_audit': 'false',
        'filters': jsonEncode({
          'trashed': {'eq': false},
        }),
      },
    );
    final rows = data['files'];
    if (rows is! List) throw const CloudException('PikPak 未返回有效文件列表');
    final next = cloudText(data['next_page_token']);
    if (next.isNotEmpty && next == cursor) {
      throw const CloudException('PikPak 返回重复分页，请刷新目录');
    }
    return CloudListing(
      rows.map(_entry).toList(),
      nextPage: next.isEmpty ? null : next,
    );
  }

  CloudEntry _entry(Object? value) {
    final data = cloudMap(value);
    final id = cloudText(data['id']), name = cloudText(data['name']);
    if (id.isEmpty || name.isEmpty) {
      throw const CloudException('PikPak 文件信息不完整');
    }
    return CloudEntry(
      id: id,
      name: name,
      size: cloudInt(data['size']),
      isFolder: data['kind'] == 'drive#folder',
    );
  }

  @override
  Future<CloudDownload> resolve(CloudAccount account, CloudEntry file) async {
    if (file.isFolder || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(file.id)) {
      throw const CloudException('请选择有效的 PikPak 文件');
    }
    final data = await _get(
      account,
      '/drive/v1/files/${file.id}',
      parameters: {'thumbnail_size': 'SIZE_SMALL'},
    );
    final original = cloudMap(
      cloudMap(data['links'])['application/octet-stream'],
    );
    final address = cloudText(original['url']);
    final url = cloudUrl(
      address.isEmpty ? cloudText(data['web_content_link']) : address,
    );
    final size = int.tryParse(cloudText(data['size'])) ?? file.size;
    if (file.size > 0 && size != file.size) {
      throw const CloudException('PikPak 原文件大小已变化，请刷新目录');
    }
    return CloudDownload(
      url,
      size: size,
      headers: {'User-Agent': cloudUserAgent},
    );
  }
}
