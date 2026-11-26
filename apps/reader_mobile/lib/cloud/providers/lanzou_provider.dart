import 'dart:io';
import 'dart:math' as math;

import '../cloud_http.dart';
import '../cloud_models.dart';
import 'lanzou_protocol.dart';

class LanzouCloudProvider implements CloudProviderApi {
  LanzouCloudProvider(this.http);
  final CloudHttp http;
  static const _site = 'https://pc.woozooo.com';

  @override
  CloudDrive get drive => CloudDrive.lanzou;
  @override
  String get rootId => '-1';

  Future<CloudResponse> _accountRequest(
    CloudAccount account,
    Uri uri, {
    Map<String, String>? form,
  }) async {
    final cookies = cloudCookies(account.cookie);
    if (cookies['ylogin']?.isNotEmpty != true ||
        cookies['phpdisk_info']?.isNotEmpty != true) {
      throw const CloudException('请先登录蓝奏云', loginRequired: true);
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final response = await http.send(
        uri,
        method: form == null ? 'GET' : 'POST',
        form: form,
        allowErrorStatus: true,
        headers: {
          'Cookie': account.cookie,
          'Origin': _site,
          'Referer': '$_site/mydisk.php',
        },
      );
      if (response.status == 401 ||
          response.status == 403 ||
          response.status >= 300 && response.status < 400) {
        throw const CloudException('蓝奏登录已失效，请重新登录', loginRequired: true);
      }
      if (response.status >= 400) {
        throw const CloudException('蓝奏暂未完成请求，请稍后重试');
      }
      acceptCloudCookies(account, response);
      final challenge = lanzouPageCookie(response.body);
      if (challenge == null) return response;
      final current = cloudCookies(account.cookie)..['acw_sc__v2'] = challenge;
      account.fields['cookie'] = current.entries
          .map((pair) => '${pair.key}=${pair.value}')
          .join('; ');
    }
    throw const CloudException('蓝奏需要安全验证，请重新网页登录', loginRequired: true);
  }

  Future<Map<String, String>> _context(CloudAccount account) async {
    final response = await _accountRequest(
      account,
      Uri.parse('$_site/mydisk.php?item=files&action=index'),
    );
    final parameters = LanzouPageData(response.body).accountParameters;
    final uid =
        parameters['uid'] ?? cloudCookies(account.cookie)['ylogin'] ?? '';
    if (!RegExp(r'^\d+$').hasMatch(uid)) {
      throw const CloudException('蓝奏未返回账号身份，请重新登录', loginRequired: true);
    }
    return {...parameters, 'uid': uid};
  }

  Future<Map<String, dynamic>> _call(
    CloudAccount account,
    Map<String, String> context,
    Map<String, String> fields,
  ) async {
    final response = await _accountRequest(
      account,
      Uri.parse('$_site/doupload.php').replace(queryParameters: context),
      form: fields,
    );
    final data = response.json;
    final status = cloudInt(data['zt']);
    if (status == 9) {
      throw const CloudException('蓝奏登录已失效，请重新登录', loginRequired: true);
    }
    if (status != 1 && status != 2) {
      throw const CloudException('蓝奏未完成请求，请稍后重试或在官网确认文件权限');
    }
    return data;
  }

  List<dynamic> _rows(Map<String, dynamic> data) {
    if (data['text'] is List) return data['text'] as List;
    if (cloudInt(data['zt']) == 2) return [];
    throw const CloudException('蓝奏返回的目录格式有误，请刷新后重试');
  }

  @override
  Future<String> validate(CloudAccount account) async {
    final context = await _context(account);
    _rows(
      await _call(account, context, {
        'task': '5',
        'folder_id': rootId,
        'pg': '1',
      }),
    );
    account.fields['userId'] = context['uid']!;
    return '蓝奏云';
  }

  @override
  Future<CloudListing> list(
    CloudAccount account,
    String folderId, {
    String? cursor,
  }) async {
    final page = int.tryParse(cursor ?? '1');
    if (page == null || page < 1) throw const CloudException('蓝奏分页无效，请重新打开目录');
    final context = await _context(account);
    final entries = <CloudEntry>[];
    if (page == 1) {
      final folders = await _call(account, context, {
        'task': '47',
        'folder_id': _id(folderId),
      });
      entries.addAll(_rows(folders).map((row) => _entry(row, folder: true)));
    }
    final files = await _call(account, context, {
      'task': '5',
      'folder_id': _id(folderId),
      'pg': '$page',
    });
    final rows = _rows(files);
    entries.addAll(rows.map((row) => _entry(row, folder: false)));
    return CloudListing(entries, nextPage: rows.isEmpty ? null : '${page + 1}');
  }

  String _id(String value) {
    final id = value.replaceFirst(RegExp(r'^[df]:'), '');
    if (!RegExp(r'^(?:-1|\d+)$').hasMatch(id)) {
      throw const CloudException('蓝奏文件编号无效');
    }
    return id;
  }

  CloudEntry _entry(Object? value, {required bool folder}) {
    final row = cloudMap(value);
    final id = cloudText(folder ? row['fol_id'] ?? row['id'] : row['id']);
    final name = cloudText(
      folder ? row['name'] : row['name_all'] ?? row['name'],
    );
    if (id.isEmpty || name.isEmpty) throw const CloudException('蓝奏文件信息不完整');
    final match = RegExp(
      r'^\s*([\d.]+)\s*([KMGT]?)',
      caseSensitive: false,
    ).firstMatch(cloudText(row['size']));
    final size = match == null
        ? 0
        : ((double.tryParse(match[1]!) ?? 0) *
                  math.pow(
                    1024,
                    ['', 'K', 'M', 'G', 'T'].indexOf(match[2]!.toUpperCase()),
                  ))
              .round();
    return CloudEntry(
      id: '${folder ? 'd' : 'f'}:${_id(id)}',
      name: name,
      isFolder: folder,
      size: folder ? 0 : size,
    );
  }

  @override
  Future<CloudDownload> resolve(CloudAccount account, CloudEntry file) async {
    if (file.isFolder) throw const CloudException('请选择蓝奏云中的文件');
    final context = await _context(account);
    // task 22 只读取文件已有访问链接，不创建分享或修改访问密码。
    final data = await _call(account, context, {
      'task': '22',
      'file_id': _id(file.id),
    });
    final info = cloudMap(data['info']);
    final link = cloudText(info['f_id']);
    if (link.isEmpty) throw const CloudException('蓝奏未返回文件访问链接');
    var base = cloudText(info['is_newd']);
    if (base.isEmpty) base = 'https://pan.lanzoui.com';
    if (!base.contains('://')) base = 'https://$base';
    final url = Uri.parse(base).resolve(link);
    _checkShare(url);
    return _LanzouDownload(http).resolve(url, cloudText(info['pwd']));
  }
}

void _checkShare(Uri url) {
  cloudUrl(url.toString());
  if (!RegExp(r'(?:^|\.)lanzou[a-z]*\.com$').hasMatch(url.host)) {
    throw const CloudException('蓝奏返回的文件访问域名无效');
  }
}

/// 下载会话与登录 Cookie 分离，仅保存公开页面自己的响应 Cookie。
class _LanzouDownload {
  _LanzouDownload(this.http);
  final CloudHttp http;
  final _cookies = <String, Map<String, String>>{};

  Map<String, String> _headers(Uri uri, Uri referer) {
    final values = <String, String>{};
    for (final entry in _cookies.entries) {
      if (uri.host == entry.key || uri.host.endsWith('.${entry.key}')) {
        values.addAll(entry.value);
      }
    }
    return {
      'User-Agent': cloudUserAgent,
      'Referer': referer.toString(),
      if (values.isNotEmpty)
        'Cookie': values.entries
            .map((pair) => '${pair.key}=${pair.value}')
            .join('; '),
    };
  }

  void _accept(Uri uri, CloudResponse response) {
    for (final raw in (response.headers['set-cookie'] ?? '').split(
      RegExp(r',(?=\s*[^\s;,=]+=)'),
    )) {
      if (raw.trim().isEmpty) continue;
      try {
        final cookie = Cookie.fromSetCookieValue(raw);
        final domain = (cookie.domain ?? uri.host).replaceFirst(
          RegExp(r'^\.'),
          '',
        );
        if (uri.host != domain && !uri.host.endsWith('.$domain')) continue;
        if (!domain.contains('.')) continue;
        final jar = _cookies.putIfAbsent(domain, () => {});
        if (cookie.maxAge == 0) {
          jar.remove(cookie.name);
        } else {
          jar[cookie.name] = cookie.value;
        }
      } on FormatException {
        // 不完整的可选 Cookie 不影响读取其他下载信息。
      }
    }
  }

  Future<CloudResponse> _request(
    Uri uri,
    Uri referer, {
    String method = 'GET',
    Map<String, String>? form,
    bool probe = false,
  }) async {
    final response = await http.send(
      uri,
      method: method,
      form: form,
      headers: {
        ..._headers(uri, referer),
        if (form != null) 'Origin': referer.origin,
        if (form != null) 'X-Requested-With': 'XMLHttpRequest',
        if (probe && method == 'GET') 'Range': 'bytes=0-8191',
      },
      allowErrorStatus: true,
      maxBodyBytes: probe ? 8192 : null,
    );
    _accept(uri, response);
    return response;
  }

  bool _redirect(CloudResponse response) =>
      {301, 302, 303, 307, 308}.contains(response.status);

  Uri _location(Uri source, String value) {
    if (value.isEmpty) throw const CloudException('蓝奏下载跳转不完整，请重试');
    return cloudUrl(source.resolve(value).toString());
  }

  Future<({Uri url, LanzouPageData page})> _page(Uri url, Uri referer) async {
    for (var step = 0; step < 8; step++) {
      _checkShare(url);
      final response = await _request(url, referer);
      if (_redirect(response)) {
        url = _location(url, response.headers['location'] ?? '');
        continue;
      }
      final challenge = lanzouPageCookie(response.body);
      if (challenge != null) {
        _cookies.putIfAbsent(url.host, () => {})['acw_sc__v2'] = challenge;
        continue;
      }
      if (response.status != 200) {
        throw const CloudException('蓝奏访问页面暂不可用，请稍后重试');
      }
      return (url: url, page: LanzouPageData(response.body));
    }
    throw const CloudException('蓝奏需要额外网页验证，请重新登录后重试');
  }

  Future<CloudDownload> resolve(Uri url, String password) async {
    var content = await _page(url, url);
    if (content.page.frame.isNotEmpty && password.isEmpty) {
      final frame = content.url.resolve(content.page.frame);
      if (frame.origin != content.url.origin) {
        throw const CloudException('蓝奏下载框架地址无效');
      }
      content = await _page(frame, content.url);
    }
    final request = content.page.download(password);
    final endpoint = content.url.resolve(request.endpoint);
    if (endpoint.origin != content.url.origin) {
      throw const CloudException('蓝奏下载接口地址无效');
    }
    final response = await _request(
      endpoint,
      content.url,
      method: 'POST',
      form: request.fields,
    );
    final data = response.json;
    if (response.status != 200 || cloudInt(data['zt']) != 1) {
      throw const CloudException('蓝奏未生成下载地址，请在官网确认文件权限');
    }
    final domain = cloudUrl(cloudText(data['dom']));
    final path = cloudText(data['url']);
    if (path.isEmpty ||
        path == '0' ||
        path.startsWith('/') ||
        path.contains('://')) {
      throw const CloudException('蓝奏返回的下载路径无效');
    }
    return _follow(cloudUrl('${domain.origin}/file/$path'), content.url);
  }

  bool _html(CloudResponse response) {
    if (RegExp(
      r'attachment|filename=',
      caseSensitive: false,
    ).hasMatch(response.headers['content-disposition'] ?? '')) {
      return false;
    }
    return response.headers['content-type']?.toLowerCase().contains(
          'text/html',
        ) ==
        true;
  }

  Future<CloudDownload> _follow(Uri url, Uri referer) async {
    _cookies.putIfAbsent(url.host, () => {})['down_ip'] = '1';
    for (var step = 0; step < 8; step++) {
      var response = await _request(url, referer, method: 'HEAD', probe: true);
      if (!_redirect(response) &&
          (response.status != 200 ||
              _html(response) ||
              response.headers['content-type'] == null)) {
        response = await _request(url, referer, probe: true);
      }
      if (_redirect(response)) {
        url = _location(url, response.headers['location'] ?? '');
        continue;
      }
      if (response.status != 200 && response.status != 206) {
        throw const CloudException('蓝奏文件下载地址暂不可用，请刷新后重试');
      }
      final challenge = lanzouPageCookie(response.body);
      if (challenge != null) {
        _cookies.putIfAbsent(url.host, () => {})['acw_sc__v2'] = challenge;
        continue;
      }
      if (_html(response)) {
        url = await _confirm(url, response);
        continue;
      }
      if ((response.headers['content-type'] ?? '').contains(
        'application/json',
      )) {
        throw const CloudException('蓝奏返回了错误页面，未获得原文件');
      }
      final range = RegExp(r'/([0-9]+)$')
          .firstMatch(response.headers['content-range'] ?? '');
      final size = range == null
          ? cloudInt(response.headers['content-length'])
          : cloudInt(range[1]);
      return CloudDownload(url, size: size, headers: _headers(url, referer));
    }
    throw const CloudException('蓝奏下载跳转过多，请在官网检查文件');
  }

  Future<Uri> _confirm(Uri url, CloudResponse page) async {
    final fields = LanzouPageData(page.body).confirmation;
    if (fields == null) throw const CloudException('蓝奏要求交互验证，请在官网完成后重试');
    await Future<void>.delayed(const Duration(seconds: 2));
    final response = await _request(
      url.resolve('ajax.php'),
      url,
      method: 'POST',
      form: fields,
    );
    final data = response.json;
    if (cloudInt(data['zt']) != 1) throw const CloudException('蓝奏下载验证未通过，请重试');
    return _location(url, cloudText(data['url']));
  }
}
