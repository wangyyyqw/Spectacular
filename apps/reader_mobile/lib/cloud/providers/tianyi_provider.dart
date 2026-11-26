import '../cloud_http.dart';
import '../cloud_models.dart';

class TianyiCloudProvider implements CloudProviderApi {
  TianyiCloudProvider(this.http);
  final CloudHttp http;
  static const _origin = 'https://cloud.189.cn';
  static const _pageSize = 60;

  @override
  CloudDrive get drive => CloudDrive.tianyi;
  @override
  String get rootId => '-11';

  Future<Map<String, dynamic>> _get(
    CloudAccount account,
    String path, [
    Map<String, String> parameters = const {},
  ]) async {
    final cookies = cloudCookies(account.cookie);
    if (![
      cookies['COOKIE_LOGIN_USER'],
      cookies['LOGIN_USER'],
    ].any((value) => value?.isNotEmpty == true)) {
      throw const CloudException('请先登录天翼网盘', loginRequired: true);
    }
    final response = await http.send(
      Uri.parse('$_origin/api/$path.action').replace(
        queryParameters: {
          ...parameters,
          'noCache': '${DateTime.now().millisecondsSinceEpoch}',
        },
      ),
      headers: {
        'Cookie': account.cookie,
        'Accept': 'application/json;charset=UTF-8',
        'Sign-Type': '1',
        'Origin': _origin,
        'Referer': '$_origin/web/',
        if (account.field('browserId').isNotEmpty)
          'Browser-Id': account.field('browserId'),
      },
    );
    if (response.status >= 300) {
      throw const CloudException('天翼登录已失效，请重新登录', loginRequired: true);
    }
    final data = _check(response.json);
    acceptCloudCookies(account, response);
    return data;
  }

  Map<String, dynamic> _check(Map<String, dynamic> data) {
    const successful = {'', '0', 'Success', 'success'};
    final errors = ['errorCode', 'res_code', 'code']
        .map((key) => cloudText(data[key]))
        .where((code) => !successful.contains(code));
    final code = errors.firstOrNull ?? '';
    if ({
      'InvalidSessionKey',
      'CommonInvalidSessionKey',
      'SafeAccessLoginTimeout',
      'InvalidAccessToken',
      'AccessTokenHasExpired',
      'AccessTokenHasExired',
      'UserNotLogin',
      'InvalidDeviceStatus',
    }.contains(code)) {
      throw const CloudException('请在天翼官网完成验证后重新登录', loginRequired: true);
    }
    if (code == 'FileTooLarge') {
      throw const CloudException('天翼当前下载接口限制此文件大小，请使用官方客户端下载');
    }
    if (code.isNotEmpty || data['success'] == false) {
      throw const CloudException('天翼未完成请求，请刷新目录或稍后重试');
    }
    return data;
  }

  @override
  Future<String> validate(CloudAccount account) async {
    final data = await _get(account, 'open/user/getUserInfoForPortal');
    final userId = cloudText(data['userId']);
    final login = cloudText(data['loginName']);
    if (userId.isEmpty && login.isEmpty) {
      throw const CloudException('天翼未确认登录身份，请重新登录', loginRequired: true);
    }
    account.fields['userId'] = userId;
    final nickname = cloudText(cloudMap(data['userExtResp'])['nickName']);
    return nickname.isNotEmpty ? nickname : '天翼网盘';
  }

  @override
  Future<CloudListing> list(
    CloudAccount account,
    String folderId, {
    String? cursor,
  }) async {
    final page = int.tryParse(cursor ?? '1');
    if (page == null || page < 1) {
      throw const CloudException('天翼目录分页无效，请重新打开目录');
    }
    final data = await _get(account, 'open/file/listFiles', {
      'folderId': folderId,
      'pageNum': '$page',
      'pageSize': '$_pageSize',
      'mediaType': '0',
      'iconOption': '5',
      'orderBy': 'lastOpTime',
      'descending': 'true',
    });
    final listing = cloudMap(data['fileListAO']);
    if (listing.isEmpty) {
      throw const CloudException('天翼未返回有效目录，请刷新后重试');
    }
    final entries = [
      ..._entries(listing['folderList'], folder: true),
      ..._entries(listing['fileList'], folder: false),
    ];
    final count = int.tryParse(cloudText(listing['count']));
    final more = count == null
        ? entries.length == _pageSize
        : page * _pageSize < count;
    if (entries.isEmpty && count != null && count > (page - 1) * _pageSize) {
      throw const CloudException('天翼返回的目录不完整，请刷新后重试');
    }
    return CloudListing(entries, nextPage: more ? '${page + 1}' : null);
  }

  List<CloudEntry> _entries(Object? value, {required bool folder}) {
    if (value == null) return [];
    if (value is! List) {
      throw const CloudException('天翼返回的文件列表格式有误');
    }
    return value.map((item) {
      final data = cloudMap(item);
      final id = cloudText(data['id'] ?? data['fileId']);
      final name = cloudText(data['name'] ?? data['fileName']);
      final size = folder
          ? 0
          : int.tryParse(cloudText(data['size'] ?? data['fileSize']));
      if (id.isEmpty || name.isEmpty || size == null || size < 0) {
        throw const CloudException('天翼返回的文件信息不完整');
      }
      return CloudEntry(id: id, name: name, size: size, isFolder: folder);
    }).toList();
  }

  @override
  Future<CloudDownload> resolve(CloudAccount account, CloudEntry file) async {
    if (file.isFolder || file.id.isEmpty) {
      throw const CloudException('请选择天翼网盘中的文件');
    }
    final data = await _get(account, 'open/file/getFileDownloadUrl', {
      'fileId': file.id,
    });
    var url = cloudUrl(
      cloudText(data['fileDownloadUrl']).replaceAll('&amp;', '&'),
    );
    if (url.scheme == 'http' && url.host == 'download.cloud.189.cn') {
      url = url.replace(scheme: 'https', port: 443);
    }
    return CloudDownload(
      url,
      size: file.size,
      headers: {'User-Agent': cloudUserAgent, 'Referer': '$_origin/'},
    );
  }
}
