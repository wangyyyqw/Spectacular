/// 仅开放已经接入书籍导入的七个网盘。
enum CloudDrive {
  baidu('百度网盘', 'https://pan.baidu.com/'),
  quark('夸克网盘', 'https://pan.quark.cn/'),
  aliyun('阿里云盘', 'https://www.alipan.com/drive'),
  pan123('123 网盘', 'https://yun.123pan.cn/'),
  tianyi('天翼网盘', 'https://cloud.189.cn/web/login.html'),
  pikpak('PikPak', 'https://mypikpak.com/drive/all'),
  lanzou('蓝奏云', 'https://pc.woozooo.com/account.php?action=login');

  const CloudDrive(this.label, this.loginUrl);
  final String label;
  final String loginUrl;
}

/// 账号只在内存和系统安全存储之间流转，不写入书库或同步设置。
class CloudAccount {
  CloudAccount(this.drive, Map<String, String> fields, {this.name = ''})
    : fields = Map.of(fields);

  final CloudDrive drive;
  final Map<String, String> fields;
  String name;
  String field(String key) => fields[key] ?? '';
  String get cookie => field('cookie');
  Map<String, Object?> toJson() => {'fields': fields, 'name': name};

  factory CloudAccount.fromJson(CloudDrive drive, Map<String, dynamic> value) =>
      CloudAccount(drive, {
        for (final entry in (value['fields'] as Map).entries)
          entry.key as String: entry.value as String,
      }, name: value['name'] as String? ?? '');
}

class CloudEntry {
  const CloudEntry({
    required this.id,
    required this.name,
    this.isFolder = false,
    this.size = 0,
    this.extra = const {},
  });
  final String id;
  final String name;
  final bool isFolder;
  final int size;
  final Map<String, dynamic> extra;
  bool get isBook =>
      !isFolder &&
      RegExp(r'\.(epub|txt)$', caseSensitive: false).hasMatch(name);
}

class CloudListing {
  const CloudListing(this.entries, {this.nextPage});
  final List<CloudEntry> entries;
  final String? nextPage;
}

class CloudDownload {
  const CloudDownload(this.url, {this.headers = const {}, this.size = 0});
  final Uri url;
  final Map<String, String> headers;
  final int size;
}

class CloudException implements Exception {
  const CloudException(
    this.message, {
    this.loginRequired = false,
    this.unavailable = false,
  });
  final String message;
  final bool loginRequired;
  final bool unavailable;
  @override
  String toString() => message;
}

abstract interface class CloudProviderApi {
  CloudDrive get drive;
  String get rootId;
  Future<String> validate(CloudAccount account);
  Future<CloudListing> list(
    CloudAccount account,
    String folderId, {
    String? cursor,
  });
  Future<CloudDownload> resolve(CloudAccount account, CloudEntry file);
}

Map<String, dynamic> cloudMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
String cloudText(Object? value) => value == null ? '' : '$value';
int cloudInt(Object? value) => int.tryParse(cloudText(value)) ?? 0;

Uri cloudUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
    throw const CloudException('网盘未返回有效下载地址，请刷新目录后重试');
  }
  return uri;
}
