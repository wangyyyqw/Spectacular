import '../cloud_http.dart';
import '../cloud_models.dart';

/// 夸克个人盘只读接口；下载使用所选文件的原文件地址。
class QuarkCloudProvider implements CloudProviderApi {
  QuarkCloudProvider(this.http);
  final CloudHttp http;
  final Map<CloudAccount, Future<void>> _renewing = {};
  static const _agent = '$cloudUserAgent quark-cloud-drive/2.5.20';

  @override
  CloudDrive get drive => CloudDrive.quark;
  @override
  String get rootId => '0';

  Map<String, String> _headers(CloudAccount account) {
    if (account.drive != drive ||
        (cloudCookies(account.cookie)['__pus'] ?? '').isEmpty) {
      throw const CloudException('请先完成夸克网盘登录', loginRequired: true);
    }
    return {
      'Cookie': account.cookie,
      'User-Agent': _agent,
      'Origin': 'https://pan.quark.cn',
      'Referer': 'https://pan.quark.cn/',
    };
  }

  Uri _uri(String path, Map<String, String> query) => Uri.https(
    'drive-pc.quark.cn',
    '/1/clouddrive/$path',
    {'pr': 'ucpro', 'fr': 'pc', ...query},
  );

  Future<Map<String, dynamic>> _request(
    CloudAccount account,
    String path, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final sentCookie = account.cookie;
      try {
        final response = await http.send(
          _uri(path, query),
          method: body == null ? 'GET' : 'POST',
          headers: _headers(account),
          json: body,
        );
        final result = _checked(response);
        acceptCloudCookies(account, response);
        return result;
      } on CloudException catch (error) {
        if (!error.loginRequired || attempt > 0) rethrow;
        if (account.cookie == sentCookie) await _renew(account);
      }
    }
  }

  Map<String, dynamic> _checked(CloudResponse response) {
    final data = response.json;
    final code = int.tryParse(cloudText(data['code']));
    final status = int.tryParse(cloudText(data['status']));
    if (status == 401 || code == 31001) {
      throw const CloudException('夸克登录已失效，请重新登录', loginRequired: true);
    }
    if (code != 0 || (status != null && status != 200)) {
      throw const CloudException('夸克暂未允许此操作，请在官网检查文件权限后重试');
    }
    return data;
  }

  Future<void> _renew(CloudAccount account) =>
      _renewing.putIfAbsent(account, () async {
        try {
          final cookies = cloudCookies(account.cookie)..remove('__puus');
          final response = await http.send(
            _uri('config', const {}),
            headers: {
              ..._headers(account),
              'Cookie': cookies.entries
                  .map((entry) => '${entry.key}=${entry.value}')
                  .join('; '),
            },
          );
          _checked(response);
          acceptCloudCookies(account, response);
        } finally {
          _renewing.removeWhere((owner, _) => identical(owner, account));
        }
      });

  @override
  Future<String> validate(CloudAccount account) async {
    await list(account, rootId);
    return account.name.isEmpty ? drive.label : account.name;
  }

  @override
  Future<CloudListing> list(
    CloudAccount account,
    String folderId, {
    String? cursor,
  }) async {
    final page = cursor == null ? 1 : int.tryParse(cursor);
    if (folderId.isEmpty || page == null || page < 1) {
      throw const CloudException('夸克目录信息已失效，请刷新目录');
    }
    final data = cloudMap(
      (await _request(
        account,
        'file/sort',
        query: {
          'pdir_fid': folderId,
          '_page': '$page',
          '_size': '100',
          '_fetch_total': '1',
          '_fetch_sub_dirs': '0',
          '_sort': 'file_type:asc,file_name:asc',
        },
      ))['data'],
    );
    final rows = data['list'];
    if (rows is! List) throw const CloudException('夸克未返回完整目录，请刷新重试');
    return CloudListing(
      rows.map((row) => _entry(cloudMap(row))).toList(),
      nextPage: rows.length == 100 ? '${page + 1}' : null,
    );
  }

  CloudEntry _entry(Map<String, dynamic> row) {
    final id = cloudText(row['fid']);
    final name = cloudText(row['file_name']);
    if (id.isEmpty || name.isEmpty) {
      throw const CloudException('夸克文件信息不完整，请刷新目录');
    }
    return CloudEntry(
      id: id,
      name: name,
      size: cloudInt(row['size']),
      isFolder: row['dir'] == true || row['dir'] == 1,
    );
  }

  @override
  Future<CloudDownload> resolve(CloudAccount account, CloudEntry file) async {
    if (!file.isBook || file.id.isEmpty) {
      throw const CloudException('请选择夸克网盘中的 EPUB 或 TXT 文件');
    }
    final data = await _request(
      account,
      'file/download',
      query: {'sys': 'win32', 've': '3.23.2'},
      body: {
        'fids': [file.id],
      },
    );
    final rows = data['data'];
    if (rows is! List || rows.length != 1) {
      throw const CloudException('夸克未返回原文件地址，请在官网检查下载权限');
    }
    return _download(account, file, cloudMap(rows.single));
  }

  CloudDownload _download(
    CloudAccount account,
    CloudEntry file,
    Map<String, dynamic> row,
  ) {
    if (cloudText(row['fid']) != file.id ||
        (file.size > 0 && cloudInt(row['size']) != file.size)) {
      throw const CloudException('夸克返回的文件与所选书籍不一致，请刷新目录');
    }
    final url = cloudUrl(cloudText(row['download_url']));
    if (url.scheme != 'https' || !url.host.endsWith('.quark.cn')) {
      throw const CloudException('夸克返回的下载站点异常，请稍后重试');
    }
    return CloudDownload(url, size: file.size, headers: _headers(account));
  }
}
