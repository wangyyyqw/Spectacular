import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' show KeyParameter, RC4Engine;

import '../cloud_http.dart';
import '../cloud_models.dart';

/// 使用百度网页个人盘接口读取目录及原文件下载地址。
class BaiduCloudProvider implements CloudProviderApi {
  BaiduCloudProvider(this.http);
  final CloudHttp http;

  @override
  CloudDrive get drive => CloudDrive.baidu;
  @override
  String get rootId => '/';

  Map<String, String> _headers(CloudAccount account) {
    if (account.drive != drive ||
        (cloudCookies(account.cookie)['BDUSS'] ?? '').isEmpty) {
      throw const CloudException('请先完成百度网盘登录', loginRequired: true);
    }
    return {
      'Cookie': account.cookie,
      'Referer': 'https://pan.baidu.com/disk/main',
    };
  }

  Future<Map<String, dynamic>> _get(
    CloudAccount account,
    String endpoint,
    Map<String, String> query,
  ) async {
    final response = await http.send(
      Uri.https('pan.baidu.com', '/api/$endpoint', {
        'app_id': '250528',
        'clienttype': '0',
        'web': '1',
        ...query,
      }),
      headers: _headers(account),
    );
    final data = response.json;
    final code = int.tryParse(cloudText(data['errno']));
    if (code == -6 || code == 111) {
      throw const CloudException('百度登录已失效，请重新登录', loginRequired: true);
    }
    if (code != 0) {
      throw const CloudException('百度暂未允许此操作，请在官网检查文件权限后重试');
    }
    acceptCloudCookies(account, response);
    return data;
  }

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
    if (!folderId.startsWith('/')) {
      throw const CloudException('百度目录信息已失效，请返回上级重新打开');
    }
    final page = cursor == null ? 1 : int.tryParse(cursor);
    if (page == null || page < 1) {
      throw const CloudException('百度分页信息已失效，请刷新目录');
    }
    final data = await _get(account, 'list', {
      'dir': folderId,
      'page': '$page',
      'num': '100',
      'order': 'name',
      'desc': '0',
      'channel': 'chunlei',
    });
    final rows = data['list'];
    if (rows is! List) throw const CloudException('百度未返回完整目录，请刷新重试');
    final more = data['has_more'];
    return CloudListing(
      rows.map((row) => _entry(cloudMap(row))).toList(),
      nextPage: (more == null ? rows.length == 100 : more == 1 || more == true)
          ? '${page + 1}'
          : null,
    );
  }

  CloudEntry _entry(Map<String, dynamic> row) {
    final folder = row['isdir'] == 1 || row['isdir'] == true;
    final path = cloudText(row['path']);
    final id = cloudText(row['fs_id']);
    final name = cloudText(row['server_filename']);
    if (id.isEmpty || name.isEmpty || (folder && !path.startsWith('/'))) {
      throw const CloudException('百度文件信息不完整，请刷新目录');
    }
    return CloudEntry(
      id: folder ? path : id,
      name: name,
      isFolder: folder,
      size: cloudInt(row['size']),
      extra: {'path': path, 'fsId': id},
    );
  }

  Future<Map<String, String>> _downloadParameters(CloudAccount account) async {
    final response = await _get(account, 'gettemplatevariable', {
      'fields': jsonEncode(['sign1', 'sign3', 'timestamp', 'bdstoken']),
    });
    final values = cloudMap(response['result']);
    final key = cloudText(values['sign3']);
    final text = cloudText(values['sign1']);
    final timestamp = cloudText(values['timestamp']);
    final token = cloudText(values['bdstoken']);
    if (key.isEmpty || text.isEmpty || int.tryParse(timestamp) == null) {
      throw const CloudException('百度下载授权尚未就绪，请重新登录后重试');
    }
    final cipher = RC4Engine()
      ..init(true, KeyParameter(Uint8List.fromList(utf8.encode(key))));
    final signature = cipher.process(Uint8List.fromList(utf8.encode(text)));
    return {
      'sign': base64Encode(signature),
      'timestamp': timestamp,
      if (token.isNotEmpty) 'bdstoken': token,
    };
  }

  @override
  Future<CloudDownload> resolve(CloudAccount account, CloudEntry file) async {
    if (!file.isBook || !RegExp(r'^\d+$').hasMatch(file.id)) {
      throw const CloudException('请选择百度网盘中的 EPUB 或 TXT 文件');
    }
    final data = await _get(account, 'download', {
      ...await _downloadParameters(account),
      'type': 'dlink',
      'fidlist': '[${file.id}]',
    });
    final rows = data['dlink'];
    if (rows is! List || rows.length != 1) {
      throw const CloudException('百度未返回原文件地址，请在官网检查下载权限');
    }
    final row = cloudMap(rows.single);
    if (cloudText(row['fs_id']) != file.id) {
      throw const CloudException('百度返回的文件与所选书籍不一致，请刷新目录');
    }
    final url = cloudUrl(cloudText(row['dlink']));
    if (url.scheme != 'https' ||
        !['baidu.com', 'baidupcs.com', 'baidubce.com'].any(
          (domain) => url.host == domain || url.host.endsWith('.$domain'),
        )) {
      throw const CloudException('百度返回的下载站点异常，请稍后重试');
    }
    return CloudDownload(
      url,
      size: file.size,
      headers: {
        'User-Agent': 'netdisk',
        'Referer': 'https://pan.baidu.com/',
        'Cookie': 'BDUSS=${cloudCookies(account.cookie)['BDUSS']}',
      },
    );
  }
}
