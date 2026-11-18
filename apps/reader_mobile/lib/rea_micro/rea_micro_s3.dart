import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import '../library/library_store.dart';
import 'rea_micro_api_client.dart';
import 'rea_micro_cbor.dart';

/// S3 同步失败。
class ReaMicroS3Exception implements Exception {
  /// 创建异常。
  const ReaMicroS3Exception(this.message);

  /// 用户可读原因。
  final String message;

  @override
  String toString() => message;
}

/// 清单提交冲突，可重新读取后重试。
class ReaMicroS3ConflictException extends ReaMicroS3Exception {
  /// 创建冲突异常。
  const ReaMicroS3ConflictException(super.message);
}

/// 阅微 S3 同步配置。
class ReaMicroS3Config {
  /// 创建配置。
  const ReaMicroS3Config({
    required this.endpoint,
    required this.bucket,
    required this.region,
    required this.accessKey,
    required this.secretKey,
    required this.prefix,
    this.provider = 'S3',
  });

  /// 空配置。
  static const ReaMicroS3Config empty = ReaMicroS3Config(
    endpoint: '',
    bucket: '',
    region: 'us-east-1',
    accessKey: '',
    secretKey: '',
    prefix: 'reamicro',
    provider: 'S3',
  );

  /// 从 JSON 恢复。
  factory ReaMicroS3Config.fromJson(Map<String, Object?> json) {
    String read(String key, [String fallback = '']) {
      final value = json[key];
      return value is String ? value : fallback;
    }

    return ReaMicroS3Config(
      provider: read('provider', 'S3'),
      endpoint: read('endpoint'),
      bucket: read('bucket'),
      region: read('region', 'us-east-1'),
      accessKey: read('accessKey'),
      secretKey: read('secretKey'),
      prefix: read('prefix', 'reamicro'),
    );
  }

  /// 服务端点，例如 `https://s3.bitiful.net`。
  final String endpoint;

  /// 存储桶。
  final String bucket;

  /// 区域；部分兼容服务使用 `auto`。
  final String region;

  /// 访问密钥。
  final String accessKey;

  /// 私密密钥；只保存在应用私有设置表中。
  final String secretKey;

  /// 同步目录前缀。
  final String prefix;

  /// 阅微同步提供方；当前支持 `S3` 与账号内置 `Mote`。
  final String provider;

  /// 规范化后的提供方标识。
  String get normalizedProvider => provider.trim().toUpperCase();

  /// 是否使用阅微账号内置存储。
  bool get isMote => normalizedProvider == 'MOTE';

  /// 是否具备同步所需的全部字段。
  bool get usable => isMote
      ? normalizedPrefix.isNotEmpty
      : normalizedEndpoint.isNotEmpty &&
            bucket.trim().isNotEmpty &&
            region.trim().isNotEmpty &&
            accessKey.trim().isNotEmpty &&
            secretKey.isNotEmpty;

  /// 去掉末尾斜杠的端点。
  String get normalizedEndpoint {
    var value = endpoint.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// 去掉首尾斜杠的同步目录。
  String get normalizedPrefix {
    var value = prefix.trim().replaceAll('\\', '/');
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// 阅微用于定位本地清单缓存的配置指纹。
  String fingerprint(String userId) {
    final payload = <String>[
      normalizedProvider,
      normalizedEndpoint,
      bucket.trim(),
      normalizedPrefix,
      userId,
    ].join('|');
    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// 转换为可持久化 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'provider': provider,
    'endpoint': endpoint,
    'bucket': bucket,
    'region': region,
    'accessKey': accessKey,
    'secretKey': secretKey,
    'prefix': prefix,
  };

  /// 复制并覆盖部分字段。
  ReaMicroS3Config copyWith({
    String? endpoint,
    String? bucket,
    String? region,
    String? accessKey,
    String? secretKey,
    String? prefix,
    String? provider,
  }) => ReaMicroS3Config(
    provider: provider ?? this.provider,
    endpoint: endpoint ?? this.endpoint,
    bucket: bucket ?? this.bucket,
    region: region ?? this.region,
    accessKey: accessKey ?? this.accessKey,
    secretKey: secretKey ?? this.secretKey,
    prefix: prefix ?? this.prefix,
  );
}

/// 阅微账号加密保存的 S3 配置。
class ReaMicroS3CloudConfig {
  /// 创建云端配置。
  const ReaMicroS3CloudConfig({
    required this.enabled,
    required this.encryptedConfig,
    this.config,
  });

  /// 云端是否启用了配置同步。
  final bool enabled;

  /// 云端返回的加密配置原文。
  final String encryptedConfig;

  /// 已解密并解析的配置；无法解密时为空。
  final ReaMicroS3Config? config;

  /// 是否可直接载入配置。
  bool get usable => enabled && config != null && config!.usable;
}

/// 与阅微一致的账号级 S3 配置加密。
///
/// 密钥取 `reamicro-s3-config-v1:<userId>` 的前 16 个 UTF-8 字节，
/// 使用 AES-128-CBC 和 PKCS#7 填充，输出为 `IV + 密文` 的 Base64。
class ReaMicroS3ConfigCrypto {
  ReaMicroS3ConfigCrypto._();

  static const String _keyPrefix = 'reamicro-s3-config-v1:';

  /// 加密配置。
  static String encrypt(ReaMicroS3Config config, int userId) {
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(config.toJson())));
    final padding = 16 - plain.length % 16;
    final padded = Uint8List(plain.length + padding)
      ..setRange(0, plain.length, plain)
      ..fillRange(plain.length, plain.length + padding, padding);
    final iv = Uint8List.fromList(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final cipher = CBCBlockCipher(AESEngine())
      ..init(
        true,
        ParametersWithIV<KeyParameter>(KeyParameter(_key(userId)), iv),
      );
    final encrypted = Uint8List(padded.length);
    for (var offset = 0; offset < padded.length; offset += 16) {
      cipher.processBlock(padded, offset, encrypted, offset);
    }
    return base64Encode(<int>[...iv, ...encrypted]);
  }

  /// 解密配置；格式或填充无效时返回空。
  static ReaMicroS3Config? decrypt(String value, int userId) {
    try {
      final raw = base64Decode(value.trim());
      if (raw.length <= 16 || raw.length % 16 != 0) return null;
      final iv = Uint8List.sublistView(raw, 0, 16);
      final encrypted = Uint8List.sublistView(raw, 16);
      final cipher = CBCBlockCipher(AESEngine())
        ..init(
          false,
          ParametersWithIV<KeyParameter>(KeyParameter(_key(userId)), iv),
        );
      final plain = Uint8List(encrypted.length);
      for (var offset = 0; offset < encrypted.length; offset += 16) {
        cipher.processBlock(encrypted, offset, plain, offset);
      }
      final padding = plain.last;
      if (padding < 1 ||
          padding > 16 ||
          plain.length < padding ||
          plain
              .sublist(plain.length - padding)
              .any((byte) => byte != padding)) {
        return null;
      }
      final decoded = jsonDecode(
        utf8.decode(Uint8List.sublistView(plain, 0, plain.length - padding)),
      );
      if (decoded is! Map<String, Object?>) return null;
      return ReaMicroS3Config.fromJson(decoded);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static Uint8List _key(int userId) {
    final bytes = utf8.encode('$_keyPrefix$userId');
    final key = Uint8List(16);
    key.setRange(0, min(16, bytes.length), bytes.take(16));
    return key;
  }
}

/// 一次 S3 对象读取结果。
class ReaMicroS3Object {
  /// 创建结果。
  const ReaMicroS3Object({required this.bytes, required this.etag});

  /// 对象内容。
  final Uint8List bytes;

  /// 服务端 ETag，可能为空弱校验值。
  final String etag;
}

/// 最小 S3 客户端接口，便于测试替换。
abstract class ReaMicroS3Client {
  /// 读取对象；不存在返回 null。
  Future<ReaMicroS3Object?> get(String key);

  /// 上传对象并返回 ETag。
  Future<String> put(
    String key,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
    String? ifMatch,
    String? ifNoneMatch,
  });

  /// 删除对象；不存在视为成功。
  Future<void> delete(String key);
}

/// AWS Signature V4 签名结果。
class ReaMicroS3Signature {
  /// 创建签名结果。
  const ReaMicroS3Signature({
    required this.authorization,
    required this.amzDate,
    required this.payloadHash,
  });

  /// `Authorization` 请求头。
  final String authorization;

  /// `x-amz-date` 请求头。
  final String amzDate;

  /// 载荷 SHA-256 十六进制值。
  final String payloadHash;
}

/// AWS Signature V4 签名器。
class ReaMicroS3Signer {
  ReaMicroS3Signer._();

  /// 对一次 S3 请求签名。
  static ReaMicroS3Signature sign({
    required String method,
    required Uri uri,
    required String region,
    required String accessKey,
    required String secretKey,
    required Uint8List payload,
    Map<String, String> extraHeaders = const <String, String>{},
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final amzDate = _amzDate(timestamp);
    final dateStamp = amzDate.substring(0, 8);
    final payloadHash = sha256.convert(payload).toString();
    final headers = <String, String>{
      'host': uri.hasPort ? '${uri.host}:${uri.port}' : uri.host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      for (final entry in extraHeaders.entries)
        entry.key.toLowerCase(): _collapseSpaces(entry.value),
    };
    final keys = headers.keys.toList()..sort();
    final canonicalHeaders = StringBuffer();
    for (final key in keys) {
      canonicalHeaders
        ..write(key)
        ..write(':')
        ..write(headers[key])
        ..write('\n');
    }
    final signedHeaders = keys.join(';');
    final canonicalUri = uri.path.isEmpty ? '/' : uri.path;
    final canonicalQuery = uri.hasQuery
        ? (uri.queryParameters.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key)))
              .map((entry) => '${_encode(entry.key)}=${_encode(entry.value)}')
              .join('&')
        : '';
    final canonicalRequest = <String>[
      method,
      canonicalUri,
      canonicalQuery,
      canonicalHeaders.toString(),
      signedHeaders,
      payloadHash,
    ].join('\n');
    final scope = '$dateStamp/${region.trim()}/s3/aws4_request';
    final stringToSign = <String>[
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    final secret = utf8.encode('AWS4${secretKey.trim()}');
    final dateKey = Hmac(sha256, secret).convert(utf8.encode(dateStamp)).bytes;
    final regionKey = Hmac(
      sha256,
      dateKey,
    ).convert(utf8.encode(region.trim())).bytes;
    final serviceKey = Hmac(sha256, regionKey).convert(utf8.encode('s3')).bytes;
    final signingKey = Hmac(
      sha256,
      serviceKey,
    ).convert(utf8.encode('aws4_request')).bytes;
    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();
    final authorization =
        'AWS4-HMAC-SHA256 Credential=${accessKey.trim()}/$scope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';
    return ReaMicroS3Signature(
      authorization: authorization,
      amzDate: amzDate,
      payloadHash: payloadHash,
    );
  }

  static String _amzDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}'
        '${two(value.month)}${two(value.day)}'
        'T${two(value.hour)}${two(value.minute)}${two(value.second)}Z';
  }

  static String _collapseSpaces(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _encode(String value) {
    final bytes = utf8.encode(value);
    final buffer = StringBuffer();
    for (final byte in bytes) {
      final unreserved =
          (byte >= 0x41 && byte <= 0x5a) ||
          (byte >= 0x61 && byte <= 0x7a) ||
          (byte >= 0x30 && byte <= 0x39) ||
          byte == 0x2d ||
          byte == 0x2e ||
          byte == 0x5f ||
          byte == 0x7e;
      if (unreserved) {
        buffer.writeCharCode(byte);
      } else {
        buffer
          ..write('%')
          ..write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
      }
    }
    return buffer.toString();
  }
}

/// 通过 S3 兼容 HTTP 接口读写对象。
class ReaMicroS3HttpClient implements ReaMicroS3Client {
  /// 创建客户端。
  ReaMicroS3HttpClient(this.config, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// 同步配置。
  final ReaMicroS3Config config;
  final http.Client _http;

  @override
  Future<ReaMicroS3Object?> get(String key) async {
    final response = await _send('GET', key);
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReaMicroS3Exception(
        '读取 $key 失败：HTTP ${response.statusCode} ${_errorText(response)}',
      );
    }
    return ReaMicroS3Object(
      bytes: response.bodyBytes,
      etag: (response.headers['etag'] ?? '').trim(),
    );
  }

  @override
  Future<String> put(
    String key,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
    String? ifMatch,
    String? ifNoneMatch,
  }) async {
    final headers = <String, String>{'content-type': contentType};
    if (ifMatch != null && ifMatch.isNotEmpty) {
      headers['if-match'] = ifMatch;
    }
    if (ifNoneMatch != null && ifNoneMatch.isNotEmpty) {
      headers['if-none-match'] = ifNoneMatch;
    }
    final response = await _send('PUT', key, bytes: bytes, headers: headers);
    if (response.statusCode == 412 || response.statusCode == 409) {
      throw const ReaMicroS3ConflictException('云端清单已被其他设备修改');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReaMicroS3Exception(
        '上传 $key 失败：HTTP ${response.statusCode} ${_errorText(response)}',
      );
    }
    return (response.headers['etag'] ?? '').trim();
  }

  @override
  Future<void> delete(String key) async {
    final response = await _send('DELETE', key);
    if (response.statusCode == 404) return;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReaMicroS3Exception(
        '删除 $key 失败：HTTP ${response.statusCode} ${_errorText(response)}',
      );
    }
  }

  Future<http.Response> _send(
    String method,
    String key, {
    Uint8List? bytes,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final uri = _uriFor(key);
    final payload = bytes ?? Uint8List(0);
    final signature = ReaMicroS3Signer.sign(
      method: method,
      uri: uri,
      region: config.region,
      accessKey: config.accessKey,
      secretKey: config.secretKey,
      payload: payload,
      extraHeaders: headers,
    );
    final request = http.Request(method, uri)
      ..headers.addAll(headers)
      ..headers['x-amz-content-sha256'] = signature.payloadHash
      ..headers['x-amz-date'] = signature.amzDate
      ..headers['authorization'] = signature.authorization;
    if (method != 'GET' && method != 'HEAD') {
      request.bodyBytes = payload;
    }
    try {
      final streamed = await _http
          .send(request)
          .timeout(const Duration(seconds: 120));
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ReaMicroS3Exception('连接 S3 超时，请检查端点与网络');
    } on SocketException catch (error) {
      throw ReaMicroS3Exception('连接 S3 失败：${error.message}');
    } on http.ClientException catch (error) {
      throw ReaMicroS3Exception('连接 S3 失败：${error.message}');
    }
  }

  Uri _uriFor(String key) {
    final base = Uri.parse(config.normalizedEndpoint);
    final basePath = base.path == '/' ? '' : base.path;
    final path = '$basePath/${config.bucket.trim()}/$key';
    return base.replace(path: path);
  }

  String _errorText(http.Response response) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (text.isEmpty) return '';
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }
}

/// 阅微账号内置对象存储客户端。
///
/// 对象读写通过阅微签发临时地址，实际字节仍直接走对象存储，
/// 因此与 APK 的 `Mote` 同步协议保持一致。
class ReaMicroMoteS3Client implements ReaMicroS3Client {
  /// 创建客户端。
  ReaMicroMoteS3Client({
    required this.api,
    required this.token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? http.Client();

  /// 阅微内置对象存储接口。
  final ReaMicroMoteSyncApi api;

  /// 当前账号令牌。
  final String token;

  /// 单次传输超时。
  final Duration timeout;

  final http.Client _http;

  @override
  Future<ReaMicroS3Object?> get(String key) async {
    final head = await api.fetchMoteHead(token, objectKey: key);
    if (!head.exists) return null;
    final signed = await api.fetchMoteDownloadUrl(token, objectKey: key);
    late final http.Response response;
    try {
      response = await _http.get(Uri.parse(signed.url)).timeout(timeout);
    } on TimeoutException {
      throw const ReaMicroS3Exception('从阅微对象存储下载超时');
    } on http.ClientException catch (error) {
      throw ReaMicroS3Exception('从阅微对象存储下载失败：${error.message}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReaMicroS3Exception('从阅微对象存储下载失败：HTTP ${response.statusCode}');
    }
    final etag = head.etag.trim().isNotEmpty
        ? head.etag.trim()
        : (response.headers['etag'] ?? '').trim();
    return ReaMicroS3Object(
      bytes: Uint8List.fromList(response.bodyBytes),
      etag: etag,
    );
  }

  @override
  Future<String> put(
    String key,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
    String? ifMatch,
    String? ifNoneMatch,
  }) async {
    final signed = await api.fetchMoteUploadUrl(
      token,
      objectKey: key,
      contentLength: bytes.length,
      ifMatch: ifMatch ?? '',
      ifNoneMatch: ifNoneMatch == '*',
    );
    late final http.Response response;
    try {
      response = await _http
          .put(
            Uri.parse(signed.url),
            headers: <String, String>{'Content-Type': contentType},
            body: bytes,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ReaMicroS3Exception('向阅微对象存储上传超时');
    } on http.ClientException catch (error) {
      throw ReaMicroS3Exception('向阅微对象存储上传失败：${error.message}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReaMicroS3Exception('向阅微对象存储上传失败：HTTP ${response.statusCode}');
    }
    await api.confirmMoteUpload(
      token,
      objectKey: key,
      contentLength: bytes.length,
    );
    final head = await api.fetchMoteHead(token, objectKey: key);
    if (!head.exists) {
      throw const ReaMicroS3Exception('阅微对象存储未确认上传结果');
    }
    final etag = head.etag.trim().isNotEmpty
        ? head.etag.trim()
        : (response.headers['etag'] ?? '').trim();
    return etag;
  }

  @override
  Future<void> delete(String key) async {
    await api.deleteMoteObject(token, objectKey: key);
  }
}

/// S3 文件描述。
class ReaMicroS3File {
  /// 创建文件描述。
  const ReaMicroS3File({
    required this.sha256,
    required this.sourceSha256,
    required this.objectId,
  });

  /// 内容 SHA-256 十六进制。
  final String sha256;

  /// 源文件 SHA-256 十六进制。
  final String sourceSha256;

  /// 对象目录标识。
  final String objectId;

  bool get usable => sha256.isNotEmpty && objectId.isNotEmpty;

  /// 转换为阅微 CBOR 文件描述。
  Map<String, Object?> toCbor() => <String, Object?>{
    'h': sha256.isEmpty ? null : _bytesFromHex(sha256),
    's': sourceSha256.isEmpty ? null : _bytesFromHex(sourceSha256),
    'o': objectId,
  };
}

/// 云端书籍条目。
class ReaMicroS3Book {
  /// 创建条目。
  const ReaMicroS3Book({
    required this.uuid,
    required this.size,
    required this.title,
    required this.author,
    required this.createdAt,
    required this.cloudId,
    required this.revisionTimestamp,
    required this.revisionCounter,
    required this.deviceId,
    required this.metadataUpdatedAt,
    required this.epub,
    this.metadata = const <String, Object?>{},
    this.cover,
    this.bookmarks,
    this.banner,
    this.bannerTracked = false,
  });

  /// 阅微书籍标识。
  final String uuid;

  /// EPUB 字节数。
  final int size;

  /// 书名。
  final String title;

  /// 作者。
  final String author;

  /// 导入时间毫秒。
  final int createdAt;

  /// 阅微账号内书籍 ID。
  final int cloudId;

  /// 修订时间戳毫秒。
  final int revisionTimestamp;

  /// 同毫秒修订计数。
  final int revisionCounter;

  /// 修订设备标识。
  final String deviceId;

  /// 元数据更新时间毫秒。
  final int metadataUpdatedAt;

  /// EPUB 文件描述。
  final ReaMicroS3File epub;

  /// 阅微原始元数据；上传时只覆盖本地可控字段，保留其余扩展字段。
  final Map<String, Object?> metadata;

  /// 封面文件描述。
  final ReaMicroS3File? cover;

  /// 批注文件描述。
  final ReaMicroS3File? bookmarks;

  /// 横幅文件描述。
  final ReaMicroS3File? banner;

  /// 是否追踪横幅。
  final bool bannerTracked;

  /// 用于比较新旧修订。
  String get revisionOrder =>
      revisionTimestamp.toString().padLeft(20, '0') +
      revisionCounter.toString().padLeft(10, '0') +
      deviceId;

  /// 用于书名作者匹配的键。
  String get fingerprint => '${_normalize(title)}|${_normalize(author)}|$size';

  /// 从 CBOR 映射恢复。
  static ReaMicroS3Book? fromCbor(Object? value) {
    final map = _asMap(value);
    final metadata = _asMap(map['b']);
    final revision = _asMap(map['r']);
    final uuid = _asString(metadata['u']);
    final epub = _fileFromCbor(map['e']);
    if (uuid.isEmpty || epub == null) return null;
    return ReaMicroS3Book(
      uuid: uuid,
      size: _asInt(metadata['s']),
      title: _asString(metadata['t']),
      author: _asString(metadata['a']),
      createdAt: _asInt(metadata['cr']),
      cloudId: _asInt(metadata['i']),
      revisionTimestamp: _asInt(revision['t']),
      revisionCounter: _asInt(revision['c']),
      deviceId: _asString(revision['d']),
      metadataUpdatedAt: _asInt(map['m']),
      epub: epub,
      metadata: metadata,
      cover: _fileFromCbor(map['c']),
      bookmarks: _fileFromCbor(map['k']),
      banner: _fileFromCbor(map['bn']),
      bannerTracked: map['bt'] == true,
    );
  }

  /// 转换为阅微 CBOR 映射。
  Map<String, Object?> toCbor() => <String, Object?>{
    'b': <String, Object?>{
      'v': 2,
      'e': 0,
      'x': 0,
      'bt': 0,
      'bi': '',
      'bc': '',
      'p': '',
      ...metadata,
      'u': uuid,
      's': size,
      't': title,
      'a': author,
      'cr': createdAt,
      'i': cloudId,
    },
    'r': <String, Object?>{
      't': revisionTimestamp,
      'c': revisionCounter,
      'd': deviceId,
    },
    'm': metadataUpdatedAt,
    'e': epub.toCbor(),
    if (cover != null) 'c': cover!.toCbor(),
    if (bookmarks != null) 'k': bookmarks!.toCbor(),
    if (banner != null) 'bn': banner!.toCbor(),
    'bt': bannerTracked,
  };

  static ReaMicroS3File? _fileFromCbor(Object? value) {
    if (value == null) return null;
    final map = _asMap(value);
    final objectId = _asString(map['o']);
    if (objectId.isEmpty) return null;
    return ReaMicroS3File(
      sha256: _hexFromBytes(map['h']),
      sourceSha256: _hexFromBytes(map['s']),
      objectId: objectId,
    );
  }
}

/// 一次 S3 同步结果。
class ReaMicroS3SyncResult {
  /// 创建结果。
  const ReaMicroS3SyncResult({
    required this.uploaded,
    required this.downloaded,
    required this.merged,
    required this.failed,
    required this.message,
    this.links = const <String, int>{},
    this.bookmarkBases = const <String, String>{},
    this.syncedBookmarks = 0,
    this.deleted = 0,
    this.localBookUuids = const <String, String>{},
    this.pendingDeletions = const <String>{},
  });

  /// 新上传或更新的书籍数。
  final int uploaded;

  /// 新下载并导入的书籍数。
  final int downloaded;

  /// 合并但未传输的书籍数。
  final int merged;

  /// 失败数。
  final int failed;

  /// 用户可读摘要。
  final String message;

  /// 本地书籍 ID → 阅微云端书籍 ID。
  final Map<String, int> links;

  /// 本地书籍 ID → 上次与云端一致的书签文件哈希。
  final Map<String, String> bookmarkBases;

  /// 本次实际合并或上传的书签文件数。
  final int syncedBookmarks;

  /// 本次新增的本地删除墓碑数。
  final int deleted;

  /// 本地书籍 ID → S3 书籍 UUID，供下次识别本地删除。
  final Map<String, String> localBookUuids;

  /// 尚未成功提交到云端清单的删除 UUID。
  final Set<String> pendingDeletions;
}

/// 阅微 S3 书籍同步引擎。
///
/// 清单索引位于 `<同步目录>/manifest.cbor`，书籍分片位于
/// `<同步目录>/manifests/<分片>/<对象>.cbor`，书籍文件位于
/// `<同步目录>/<uuid>/<对象>/book.epub`，与阅微 2.3.4 的读取路径一致。
class ReaMicroS3SyncEngine {
  /// 创建同步引擎。
  ReaMicroS3SyncEngine({
    required this.library,
    required this.config,
    required this.client,
    required this.userId,
    required this.deviceId,
    this.cloudIds = const <String, int>{},
    this.bookmarkBases = const <String, String>{},
    this.localBookUuids = const <String, String>{},
    this.pendingDeletions = const <String>{},
    this.onStatus,
  });

  /// 本地书架。
  final LibraryStore library;

  /// 同步配置。
  final ReaMicroS3Config config;

  /// S3 客户端。
  final ReaMicroS3Client client;

  /// 当前阅微账号 ID。
  final String userId;

  /// 当前设备标识。
  final String deviceId;

  /// 本地书籍 ID → 阅微云端书籍 ID。
  final Map<String, int> cloudIds;

  /// 本地书籍 ID → 上次与云端一致的书签文件哈希。
  final Map<String, String> bookmarkBases;

  /// 上次同步完成时本地书籍 ID → S3 书籍 UUID。
  final Map<String, String> localBookUuids;

  /// 尚未成功提交到云端清单的删除 UUID。
  final Set<String> pendingDeletions;

  /// 进度回调。
  final void Function(String message)? onStatus;

  static const String _shardId = 'spectacular';
  static const String _manifestContentType = 'application/cbor';
  static const Duration _deletionRetention = Duration(days: 30);

  /// 执行一次增量同步。
  Future<ReaMicroS3SyncResult> sync({
    bool restoreMissing = true,
    bool uploadCovers = true,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _syncOnce(
          restoreMissing: restoreMissing,
          uploadCovers: uploadCovers,
        );
      } on ReaMicroS3ConflictException catch (error) {
        lastError = error;
        onStatus?.call('云端清单已更新，正在重新读取…');
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }
    throw lastError is ReaMicroS3Exception
        ? lastError
        : const ReaMicroS3Exception('云端清单持续被修改，请稍后同步');
  }

  Future<ReaMicroS3SyncResult> _syncOnce({
    required bool restoreMissing,
    required bool uploadCovers,
  }) async {
    onStatus?.call('读取云端清单…');
    final manifestKey = _key('manifest.cbor');
    final manifestObject = await client.get(manifestKey);
    final manifest = manifestObject == null
        ? _emptyManifest()
        : _asMap(ReaMicroCborDecoder.decode(manifestObject.bytes));
    final version = _asInt(manifest['v']);
    if (manifestObject != null && version != 1) {
      throw ReaMicroS3Exception('不支持的 S3 同步协议版本：$version');
    }

    final books = <String, ReaMicroS3Book>{};
    for (final shardId in _asList(manifest['s']).whereType<String>()) {
      final objectId = _asString(_asMap(manifest['sp'])[shardId]);
      if (objectId.isEmpty) continue;
      try {
        final shardObject = await client.get(_shardKey(shardId, objectId));
        if (shardObject == null) continue;
        final shard = _asMap(ReaMicroCborDecoder.decode(shardObject.bytes));
        for (final entry in _asList(shard['b'])) {
          final book = ReaMicroS3Book.fromCbor(entry);
          if (book == null) continue;
          final existing = books[book.uuid];
          if (existing == null ||
              book.revisionOrder.compareTo(existing.revisionOrder) > 0) {
            books[book.uuid] = book;
          }
        }
      } on ReaMicroS3Exception catch (error) {
        onStatus?.call('分片 $shardId 读取失败：${error.message}');
      }
    }

    final tombstones = <String, String>{};
    final deletionEntries = <String, Map<String, Object?>>{};
    final ownDeletionEntries = <String, Map<String, Object?>>{};
    for (final shardId in _asList(manifest['d']).whereType<String>()) {
      final objectId = _asString(_asMap(manifest['dp'])[shardId]);
      if (objectId.isEmpty) continue;
      try {
        final shardObject = await client.get(_deletionKey(shardId, objectId));
        if (shardObject == null) continue;
        final shard = _asMap(ReaMicroCborDecoder.decode(shardObject.bytes));
        final rawEntries = <Object?>[
          ..._asList(shard['e']),
          ..._asList(shard['a']),
        ];
        for (final entry in rawEntries) {
          final map = _deletionEntryFromCbor(entry);
          final uuid = _asString(map['u']);
          if (uuid.isEmpty) continue;
          final order = _deletionRevisionOrder(map);
          final existing = deletionEntries[uuid];
          if (existing == null ||
              order.compareTo(_deletionRevisionOrder(existing)) > 0) {
            deletionEntries[uuid] = map;
          }
          if (shardId == _shardId) ownDeletionEntries[uuid] = map;
        }
      } on ReaMicroS3Exception catch (error) {
        onStatus?.call('删除分片 $shardId 读取失败：${error.message}');
      }
    }
    final nowAtRead = DateTime.now().millisecondsSinceEpoch;
    deletionEntries.forEach((uuid, entry) {
      final expiresAt = _asInt(entry['x']);
      if (expiresAt <= nowAtRead) return;
      final revision = _deletionRevisionOrder(entry);
      final book = books[uuid];
      if (book != null && revision.compareTo(book.revisionOrder) >= 0) {
        books.remove(uuid);
        tombstones[uuid] = revision;
      } else if (_deletionTargetsBook(entry, book)) {
        books.remove(uuid);
        tombstones[uuid] = revision;
      }
    });

    final localBooks = await library.list();
    final matchedRemote = <String>{};
    final links = <String, int>{};
    final nextBookmarkBases = Map<String, String>.of(bookmarkBases);
    final currentLocalUuids = <String, String>{};
    var uploaded = 0;
    var skipped = 0;
    var failed = 0;
    var syncedBookmarks = 0;
    var deleted = 0;

    for (final local in localBooks) {
      currentLocalUuids[local.id] = localBookUuids[local.id] ?? local.id;
      final file = File(local.filePath);
      if (!await file.exists()) {
        skipped += 1;
        continue;
      }
      final int size;
      try {
        size = await file.length();
      } on FileSystemException {
        skipped += 1;
        continue;
      }
      final sha = await _localSha256(local);
      if (sha.isEmpty) {
        skipped += 1;
        continue;
      }
      final fingerprint = _bookFingerprint(local.title, local.author, size);
      ReaMicroS3Book? matched = books[local.id];
      if (matched == null) {
        for (final book in books.values) {
          if (book.fingerprint == fingerprint &&
              (book.size == 0 || book.size == size)) {
            matched = book;
            break;
          }
        }
      }
      final uuid = matched?.uuid ?? local.id;
      currentLocalUuids[local.id] = uuid;
      final now = DateTime.now().millisecondsSinceEpoch;
      final epubMatches =
          matched != null &&
          (matched.epub.sha256 == sha || matched.epub.sourceSha256 == sha);
      final _BookmarkSyncOutcome? bookmarkOutcome;
      try {
        bookmarkOutcome = await _syncBookmarks(
          local: local,
          matched: matched,
          uuid: uuid,
          now: now,
        );
      } catch (error) {
        failed += 1;
        onStatus?.call('《${local.title}》书签同步失败：$error');
        continue;
      }
      if (bookmarkOutcome != null) {
        nextBookmarkBases[local.id] = bookmarkOutcome.baseSha;
        if (bookmarkOutcome.synced) syncedBookmarks += 1;
      }
      final coverBytes = uploadCovers ? await _readLocalCover(local) : null;
      final coverSha = coverBytes == null
          ? ''
          : sha256.convert(coverBytes).toString();
      final coverChanged =
          coverBytes != null &&
          coverBytes.isNotEmpty &&
          coverSha != (matched?.cover?.sha256 ?? '');
      if (matched != null) {
        matchedRemote.add(matched.uuid);
        if (matched.cloudId > 0) {
          links[local.id] = matched.cloudId;
        }
        if (epubMatches &&
            !coverChanged &&
            !(bookmarkOutcome?.entryChanged ?? false)) {
          skipped += 1;
          continue;
        }
      }
      onStatus?.call('上传《${local.title}》…');
      try {
        final bytes = epubMatches ? null : await file.readAsBytes();
        final epubFile = epubMatches
            ? matched.epub
            : ReaMicroS3File(
                sha256: sha,
                sourceSha256: sha,
                objectId: _objectId(sha, now),
              );
        if (bytes != null) {
          await client.put(
            _bookKey(uuid, epubFile.objectId, 'book.epub'),
            bytes,
            contentType: 'application/epub+zip',
          );
        }
        ReaMicroS3File? coverFile = matched?.cover;
        if (coverBytes != null &&
            coverBytes.isNotEmpty &&
            (!epubMatches || coverChanged)) {
          final coverObjectId = _objectId(coverSha, now);
          await client.put(
            _bookKey(uuid, coverObjectId, 'cover'),
            coverBytes,
            contentType: 'image/jpeg',
          );
          coverFile = ReaMicroS3File(
            sha256: coverSha,
            sourceSha256: coverSha,
            objectId: coverObjectId,
          );
        }
        books[uuid] = ReaMicroS3Book(
          uuid: uuid,
          size: size,
          title: local.title,
          author: local.author,
          createdAt: local.addedAt.millisecondsSinceEpoch,
          cloudId: cloudIds[local.id] ?? matched?.cloudId ?? 0,
          revisionTimestamp: now,
          revisionCounter: 0,
          deviceId: deviceId,
          metadataUpdatedAt: now,
          epub: epubFile,
          metadata: matched?.metadata ?? const <String, Object?>{},
          cover: coverFile,
          bookmarks: bookmarkOutcome?.file ?? matched?.bookmarks,
          banner: matched?.banner,
          bannerTracked: matched?.bannerTracked ?? false,
        );
        if ((bookmarkOutcome?.file ?? matched?.bookmarks) != null) {
          final bookmarkSha =
              (bookmarkOutcome?.file ?? matched?.bookmarks)!.sha256;
          if (bookmarkSha.isNotEmpty) {
            nextBookmarkBases[local.id] = bookmarkSha;
          }
        }
        if ((cloudIds[local.id] ?? matched?.cloudId ?? 0) > 0) {
          links[local.id] = cloudIds[local.id] ?? matched?.cloudId ?? 0;
        }
        uploaded += 1;
      } catch (error) {
        failed += 1;
        onStatus?.call('《${local.title}》上传失败：$error');
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final currentLocalIds = <String>{for (final local in localBooks) local.id};
    final currentLocalUuidValues = <String>{...currentLocalUuids.values};
    final deletionCandidates =
        <String>{
          ...pendingDeletions,
          for (final entry in localBookUuids.entries)
            if (!currentLocalIds.contains(entry.key) &&
                !currentLocalUuidValues.contains(entry.value))
              entry.value,
        }..removeWhere(
          (uuid) => uuid.isEmpty || currentLocalUuidValues.contains(uuid),
        );
    for (final uuid in deletionCandidates) {
      final remote = books[uuid];
      final existing = deletionEntries[uuid];
      final existingRevision = _asMap(existing?['r']);
      final remoteIsNewer =
          remote != null &&
          (existing == null ||
              remote.revisionOrder.compareTo(_deletionRevisionOrder(existing)) >
                  0);
      final revisionTimestamp = remoteIsNewer
          ? max(now, remote.revisionTimestamp)
          : max(now, _asInt(existingRevision['t']));
      final revisionCounter = remoteIsNewer
          ? (revisionTimestamp == remote.revisionTimestamp
                ? remote.revisionCounter + 1
                : 0)
          : (revisionTimestamp == _asInt(existingRevision['t'])
                ? _asInt(existingRevision['c']) + 1
                : 0);
      final revision = <String, Object?>{
        't': revisionTimestamp,
        'c': revisionCounter,
        'd': deviceId,
      };
      final target = remote != null
          ? <String, Object?>{
              't': remote.revisionTimestamp,
              'c': remote.revisionCounter,
              'd': remote.deviceId,
            }
          : _asMap(existing?['t']);
      final entry = <String, Object?>{
        'u': uuid,
        'r': revision,
        if (target.isNotEmpty) 't': target,
        'd': now,
        'x': now + _deletionRetention.inMilliseconds,
      };
      ownDeletionEntries[uuid] = entry;
      deletionEntries[uuid] = entry;
      tombstones[uuid] = _deletionRevisionOrder(entry);
      books.remove(uuid);
      if (!pendingDeletions.contains(uuid)) deleted += 1;
    }
    ownDeletionEntries.removeWhere((uuid, entry) {
      final expiresAt = _asInt(entry['x']);
      if (expiresAt <= now || currentLocalUuidValues.contains(uuid)) {
        return true;
      }
      return false;
    });

    var downloaded = 0;
    if (restoreMissing) {
      final localFingerprints = <String>{};
      for (final book in localBooks) {
        try {
          localFingerprints.add(
            _bookFingerprint(
              book.title,
              book.author,
              await File(book.filePath).length(),
            ),
          );
        } on FileSystemException {
          // 本地文件已缺失时不能参与去重，但不应中断云端恢复。
        }
      }
      for (final book in books.values) {
        if (matchedRemote.contains(book.uuid)) continue;
        if (localFingerprints.contains(book.fingerprint)) continue;
        onStatus?.call('下载《${book.title}》…');
        try {
          final object = await client.get(
            _bookKey(book.uuid, book.epub.objectId, 'book.epub'),
          );
          if (object == null) {
            skipped += 1;
            continue;
          }
          final sha = sha256.convert(object.bytes).toString();
          if (book.epub.sha256.isNotEmpty && book.epub.sha256 != sha) {
            failed += 1;
            onStatus?.call('《${book.title}》校验失败，已跳过');
            continue;
          }
          final imported = await library.importBytes(
            object.bytes,
            fallbackTitle: book.title,
          );
          final bookmarkOutcome = await _importRemoteBookmarks(
            book: imported,
            remote: book,
          );
          if (bookmarkOutcome != null) {
            nextBookmarkBases[imported.id] = bookmarkOutcome;
            syncedBookmarks += 1;
          }
          if (book.cloudId > 0) {
            links[imported.id] = book.cloudId;
          }
          currentLocalUuids[imported.id] = book.uuid;
          downloaded += 1;
          localFingerprints.add(book.fingerprint);
        } catch (error) {
          failed += 1;
          onStatus?.call('《${book.title}》下载失败：$error');
        }
      }
    }

    onStatus?.call('写入云端清单…');
    final revision = DateTime.now().millisecondsSinceEpoch;
    final entries = books.values
        .toList()
        .map((book) => book.toCbor())
        .toList(growable: false);
    final shardBytes = ReaMicroCborEncoder.encode(<String, Object?>{
      'b': entries,
    });
    final shardSha = sha256.convert(shardBytes).toString();
    final shardObjectId = _objectId(shardSha, revision);
    await client.put(
      _shardKey(_shardId, shardObjectId),
      shardBytes,
      contentType: _manifestContentType,
    );
    String? deletionShardObjectId;
    if (ownDeletionEntries.isNotEmpty) {
      final deletionBytes = ReaMicroCborEncoder.encode(<String, Object?>{
        'e': ownDeletionEntries.values.toList(growable: false),
      });
      final deletionSha = sha256.convert(deletionBytes).toString();
      deletionShardObjectId = _objectId(deletionSha, revision);
      await client.put(
        _deletionKey(_shardId, deletionShardObjectId),
        deletionBytes,
        contentType: _manifestContentType,
      );
    }
    final nextDeletionShards = <Object?>[
      for (final value in _asList(manifest['d']).whereType<String>())
        if (value != _shardId) value,
      if (ownDeletionEntries.isNotEmpty) _shardId,
    ];
    final nextDeletionRevisions = Map<String, Object?>.of(
      _asMap(manifest['dr']),
    );
    final nextDeletionExpirations = Map<String, Object?>.of(
      _asMap(manifest['de']),
    );
    final nextDeletionPointers = Map<String, Object?>.of(
      _asMap(manifest['dp']),
    );
    if (ownDeletionEntries.isEmpty || deletionShardObjectId == null) {
      nextDeletionRevisions.remove(_shardId);
      nextDeletionExpirations.remove(_shardId);
      nextDeletionPointers.remove(_shardId);
    } else {
      nextDeletionRevisions[_shardId] = revision;
      nextDeletionExpirations[_shardId] = ownDeletionEntries.values
          .map((entry) => _asInt(entry['x']))
          .where((value) => value > now)
          .fold<int>(
            now + _deletionRetention.inMilliseconds,
            (earliest, value) => min(earliest, value),
          );
      nextDeletionPointers[_shardId] = deletionShardObjectId;
    }
    final shardIds = <Object?>[
      for (final value in _asList(manifest['s']).whereType<String>())
        if (value != _shardId) value,
      _shardId,
    ];
    final nextManifest = <String, Object?>{
      ...manifest,
      'v': 1,
      's': shardIds,
      'r': revision,
      'sr': <String, Object?>{..._asMap(manifest['sr']), _shardId: revision},
      'sp': <String, Object?>{
        ..._asMap(manifest['sp']),
        _shardId: shardObjectId,
      },
      'd': nextDeletionShards,
      'dr': nextDeletionRevisions,
      'de': nextDeletionExpirations,
      'dp': nextDeletionPointers,
    };
    final etag = manifestObject?.etag ?? '';
    if (manifestObject == null) {
      await client.put(
        manifestKey,
        ReaMicroCborEncoder.encode(nextManifest),
        contentType: _manifestContentType,
        ifNoneMatch: '*',
      );
    } else {
      if (etag.isEmpty || etag.startsWith('W/')) {
        throw const ReaMicroS3Exception('对象存储未提供强 ETag，无法安全提交清单');
      }
      await client.put(
        manifestKey,
        ReaMicroCborEncoder.encode(nextManifest),
        contentType: _manifestContentType,
        ifMatch: etag,
      );
    }

    final parts = <String>[
      if (uploaded > 0) '上传 $uploaded 本',
      if (downloaded > 0) '下载 $downloaded 本',
      if (deleted > 0) '删除 $deleted 本',
      if (syncedBookmarks > 0) '同步 $syncedBookmarks 本书签',
      if (uploaded == 0 &&
          downloaded == 0 &&
          deleted == 0 &&
          syncedBookmarks == 0)
        '没有新的书籍变更',
      if (skipped > 0) '$skipped 本已是最新',
      if (failed > 0) '$failed 本失败',
    ];
    return ReaMicroS3SyncResult(
      uploaded: uploaded,
      downloaded: downloaded,
      merged: books.length,
      failed: failed,
      message: 'S3 同步完成：${parts.join('，')}（云端共 ${books.length} 本）',
      links: links,
      bookmarkBases: nextBookmarkBases,
      syncedBookmarks: syncedBookmarks,
      deleted: deleted,
      localBookUuids: currentLocalUuids,
      pendingDeletions: const <String>{},
    );
  }

  static Map<String, Object?> _deletionEntryFromCbor(Object? value) {
    final source = _asMap(value);
    final entry = Map<String, Object?>.of(source);
    final revision = source['r'];
    entry['r'] = revision is Map
        ? Map<String, Object?>.of(_asMap(revision))
        : _deletionRevisionFromLegacy(source['r'] ?? source['t'], source['d']);
    final target = source['t'];
    entry['t'] = target is Map
        ? Map<String, Object?>.of(_asMap(target))
        : _deletionRevisionFromLegacy(target, source['d']);
    return entry;
  }

  static Map<String, Object?> _deletionRevisionFromLegacy(
    Object? value,
    Object? device,
  ) => <String, Object?>{'t': _asInt(value), 'c': 0, 'd': _asString(device)};

  static String _deletionRevisionOrder(Map<String, Object?> entry) {
    final revision = _asMap(entry['r']);
    return _asInt(revision['t']).toString().padLeft(20, '0') +
        _asInt(revision['c']).toString().padLeft(10, '0') +
        _asString(revision['d']);
  }

  static bool _deletionTargetsBook(
    Map<String, Object?> entry,
    ReaMicroS3Book? book,
  ) {
    if (book == null) return false;
    final target = _asMap(entry['t']);
    if (target.isEmpty) return false;
    return _asInt(target['t']).toString().padLeft(20, '0') +
            _asInt(target['c']).toString().padLeft(10, '0') +
            _asString(target['d']) ==
        book.revisionOrder;
  }

  Future<Uint8List?> _readLocalCover(BookEntry local) async {
    final path = local.coverPath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return bytes;
  }

  Future<_BookmarkSyncOutcome?> _syncBookmarks({
    required BookEntry local,
    required ReaMicroS3Book? matched,
    required String uuid,
    required int now,
  }) async {
    final localRecords = await library.listBookBookmarks(local.id);
    final localBytes = _encodeBookmarkJson(localRecords);
    final localSha = sha256.convert(localBytes).toString();
    final remote = matched?.bookmarks;
    final base = bookmarkBases[local.id] ?? '';
    if (remote == null || !remote.usable) {
      if (localRecords.isEmpty) return null;
      return _uploadBookmarkRecords(
        uuid: uuid,
        now: now,
        records: localRecords,
        bytes: localBytes,
        sha: localSha,
      );
    }
    if (remote.sha256.isNotEmpty && remote.sha256 == localSha) {
      return _BookmarkSyncOutcome(
        file: remote,
        baseSha: localSha,
        entryChanged: false,
        synced: false,
      );
    }
    if (base.isNotEmpty && localSha == base) {
      final remoteRecords = await _downloadBookmarkRecords(uuid, remote);
      if (remoteRecords == null) {
        return _uploadBookmarkRecords(
          uuid: uuid,
          now: now,
          records: localRecords,
          bytes: localBytes,
          sha: localSha,
        );
      }
      await library.applyBookBookmarkSnapshot(
        local.id,
        remoteRecords,
        removeMissing: true,
      );
      return _BookmarkSyncOutcome(
        file: remote,
        baseSha: remote.sha256,
        entryChanged: false,
        synced: true,
      );
    }
    if (base.isNotEmpty && remote.sha256 == base) {
      return _uploadBookmarkRecords(
        uuid: uuid,
        now: now,
        records: localRecords,
        bytes: localBytes,
        sha: localSha,
      );
    }
    final remoteRecords = await _downloadBookmarkRecords(uuid, remote);
    final merged = _mergeBookBookmarks(remoteRecords ?? const [], localRecords);
    await library.applyBookBookmarkSnapshot(
      local.id,
      merged.values,
      removeMissing: false,
    );
    return _uploadBookmarkRecords(
      uuid: uuid,
      now: now,
      records: merged.values.toList(growable: false),
      bytes: _encodeBookmarkJson(merged.values),
      sha: '',
    );
  }

  Future<_BookmarkSyncOutcome> _uploadBookmarkRecords({
    required String uuid,
    required int now,
    required Iterable<BookBookmarkRecord> records,
    required Uint8List bytes,
    required String sha,
  }) async {
    final digest = sha.isEmpty ? sha256.convert(bytes).toString() : sha;
    final objectId = _objectId(digest, now);
    await client.put(
      _bookKey(uuid, objectId, 'bookmarks'),
      bytes,
      contentType: 'application/json; charset=utf-8',
    );
    return _BookmarkSyncOutcome(
      file: ReaMicroS3File(
        sha256: digest,
        sourceSha256: digest,
        objectId: objectId,
      ),
      baseSha: digest,
      entryChanged: true,
      synced: records.isNotEmpty,
    );
  }

  Future<List<BookBookmarkRecord>?> _downloadBookmarkRecords(
    String uuid,
    ReaMicroS3File file,
  ) async {
    final key = _bookKey(uuid, file.objectId, 'bookmarks');
    final object = await client.get(key);
    if (object == null) return null;
    final sha = sha256.convert(object.bytes).toString();
    if (file.sha256.isNotEmpty && file.sha256 != sha) {
      throw const ReaMicroS3Exception('云端书签文件校验失败');
    }
    return _decodeBookmarkJson(object.bytes);
  }

  Future<String?> _importRemoteBookmarks({
    required BookEntry book,
    required ReaMicroS3Book remote,
  }) async {
    final file = remote.bookmarks;
    if (file == null || !file.usable) return null;
    try {
      final records = await _downloadBookmarkRecords(remote.uuid, file);
      if (records == null) return null;
      await library.applyBookBookmarkSnapshot(
        book.id,
        records,
        removeMissing: true,
      );
      return file.sha256;
    } catch (error) {
      onStatus?.call('《${book.title}》书签下载失败：$error');
      return null;
    }
  }

  Future<String> _localSha256(BookEntry local) async {
    final cached = local.contentRevision?.trim().toLowerCase() ?? '';
    if (RegExp(r'^[a-f0-9]{64}$').hasMatch(cached)) return cached;
    final digest = await sha256.bind(File(local.filePath).openRead()).first;
    return digest.toString();
  }

  String _key(String suffix) {
    final prefix = config.normalizedPrefix;
    return prefix.isEmpty ? suffix : '$prefix/$suffix';
  }

  String _shardKey(String shardId, String objectId) =>
      _key('manifests/$shardId/$objectId.cbor');

  String _deletionKey(String shardId, String objectId) =>
      _key('deletions/$shardId/$objectId.cbor');

  String _bookKey(String uuid, String objectId, String name) =>
      _key('$uuid/$objectId/$name');

  static String _objectId(String sha, int now) =>
      '$now-${sha.substring(0, 32)}';

  static Map<String, Object?> _emptyManifest() => <String, Object?>{
    'v': 1,
    's': <Object?>[],
    'd': <Object?>[],
    'r': 0,
    'sr': <String, Object?>{},
    'dr': <String, Object?>{},
    'de': <String, Object?>{},
    'sp': <String, Object?>{},
    'dp': <String, Object?>{},
    'gc': <String, Object?>{},
    'tx': <String, Object?>{},
  };
}

class _BookmarkSyncOutcome {
  const _BookmarkSyncOutcome({
    required this.file,
    required this.baseSha,
    required this.entryChanged,
    required this.synced,
  });

  final ReaMicroS3File? file;
  final String baseSha;
  final bool entryChanged;
  final bool synced;
}

Uint8List _encodeBookmarkJson(Iterable<BookBookmarkRecord> records) {
  final sorted =
      records
          .where((record) => record.cfi.trim().isNotEmpty)
          .toList(growable: false)
        ..sort((left, right) => left.cfi.compareTo(right.cfi));
  final items = <Map<String, Object?>>[
    for (final record in sorted)
      <String, Object?>{
        if (record.spineIndex != 0) 'chapter': record.spineIndex,
        if (record.title.isNotEmpty) 'title': record.title,
        if (record.summary.isNotEmpty) 'summary': record.summary,
        'epubcfi': record.cfi,
        if (record.remark.isNotEmpty) 'remark': record.remark,
      },
  ];
  return Uint8List.fromList(utf8.encode(jsonEncode(items)));
}

List<BookBookmarkRecord> _decodeBookmarkJson(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: false);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  if (text.trim().isEmpty) return const <BookBookmarkRecord>[];
  final decoded = jsonDecode(text);
  if (decoded is! List<Object?>) {
    throw const ReaMicroS3Exception('云端书签文件格式不正确');
  }
  final records = <String, BookBookmarkRecord>{};
  for (final item in decoded) {
    if (item is! Map<String, Object?>) continue;
    final cfi = _asString(item['epubcfi']).trim();
    if (cfi.isEmpty) continue;
    records[cfi] = BookBookmarkRecord(
      cfi: cfi,
      spineIndex: _asInt(item['chapter']),
      title: _asString(item['title']),
      summary: _asString(item['summary']),
      remark: _asString(item['remark']),
      createdAt: 0,
      updatedAt: 0,
    );
  }
  return records.values.toList(growable: false);
}

Map<String, BookBookmarkRecord> _mergeBookBookmarks(
  Iterable<BookBookmarkRecord> remote,
  Iterable<BookBookmarkRecord> local,
) {
  final merged = <String, BookBookmarkRecord>{
    for (final record in remote)
      if (record.cfi.trim().isNotEmpty) record.cfi.trim(): record,
  };
  for (final record in local) {
    final cfi = record.cfi.trim();
    if (cfi.isEmpty) continue;
    final previous = merged[cfi];
    merged[cfi] = BookBookmarkRecord(
      cfi: cfi,
      spineIndex: record.spineIndex != 0
          ? record.spineIndex
          : previous?.spineIndex ?? 0,
      title: record.title.isNotEmpty ? record.title : previous?.title ?? '',
      summary: record.summary.isNotEmpty
          ? record.summary
          : previous?.summary ?? '',
      remark: record.remark.isNotEmpty ? record.remark : previous?.remark ?? '',
      createdAt: record.createdAt > 0
          ? record.createdAt
          : previous?.createdAt ?? 0,
      updatedAt: record.updatedAt > (previous?.updatedAt ?? 0)
          ? record.updatedAt
          : previous?.updatedAt ?? 0,
    );
  }
  return merged;
}

Map<String, Object?> _asMap(Object? value) =>
    value is Map<String, Object?> ? value : <String, Object?>{};

List<Object?> _asList(Object? value) =>
    value is List<Object?> ? value : const <Object?>[];

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

String _asString(Object? value) => value is String ? value : '';

String _normalize(String value) => value.trim().toLowerCase();

String _bookFingerprint(String title, String author, int size) =>
    '${_normalize(title)}|${_normalize(author)}|$size';

String _hexFromBytes(Object? value) {
  if (value is Uint8List && value.length == 32) {
    return value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
  return '';
}

Uint8List _bytesFromHex(String value) {
  final bytes = Uint8List(value.length ~/ 2);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = int.parse(
      value.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return bytes;
}
