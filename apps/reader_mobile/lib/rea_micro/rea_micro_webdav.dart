import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'rea_micro_s3.dart';

/// 通过 WebDAV 读写阅微同步对象。
///
/// 清单与书籍使用与 S3 同步相同的对象路径；写入依赖强 ETag 的
/// `If-Match`/`If-None-Match` 条件请求，服务不支持时直接拒绝同步，
/// 避免多设备互相覆盖。
class ReaMicroWebDavClient implements ReaMicroS3Client {
  /// 创建客户端。
  ReaMicroWebDavClient(this.config, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// 同步配置。
  final ReaMicroS3Config config;
  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 120);

  @override
  Future<ReaMicroS3Object?> get(String key) async {
    final response = await _send('GET', key);
    if (response.statusCode == 404) return null;
    _check(response, '读取 $key');
    return ReaMicroS3Object(
      bytes: response.bodyBytes,
      etag: _requireStrongEtag(response.headers['etag']),
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
    await _ensureParents(key);
    final headers = <String, String>{'content-type': contentType};
    if (ifMatch != null && ifMatch.isNotEmpty) {
      headers['if-match'] = _strongEtag(ifMatch);
    }
    if (ifNoneMatch != null && ifNoneMatch.isNotEmpty) {
      headers['if-none-match'] = ifNoneMatch;
    }
    final response = await _send('PUT', key, bytes: bytes, headers: headers);
    if (response.statusCode == 412 || response.statusCode == 409) {
      throw const ReaMicroS3ConflictException('云端清单已被其他设备修改');
    }
    _check(response, '上传 $key');
    return (response.headers['etag'] ?? '').trim();
  }

  @override
  Future<void> delete(String key) async {
    final response = await _send('DELETE', key);
    if (response.statusCode == 404) return;
    _check(response, '删除 $key');
  }

  Future<void> _ensureParents(String key) async {
    final segments = key.split('/').where((item) => item.isNotEmpty).toList();
    if (segments.length <= 1) return;
    for (var index = 1; index < segments.length; index++) {
      final parent = segments.take(index).join('/');
      final response = await _send('MKCOL', parent, directory: true);
      if (response.statusCode == 405) {
        final head = await _send('HEAD', parent, directory: true);
        _check(head, '确认目录 $parent');
        continue;
      }
      if (response.statusCode == 409) {
        throw ReaMicroS3Exception('WebDAV 无法创建同步目录 $parent');
      }
      _check(response, '创建目录 $parent');
    }
  }

  Future<http.Response> _send(
    String method,
    String key, {
    Uint8List? bytes,
    Map<String, String> headers = const <String, String>{},
    bool directory = false,
  }) async {
    final uri = _uriFor(key, directory: directory);
    final request = http.Request(method, uri)..headers.addAll(headers);
    final authorization = _authorization;
    if (authorization.isNotEmpty) {
      request.headers['authorization'] = authorization;
    }
    if (bytes != null && method != 'GET' && method != 'HEAD') {
      request.bodyBytes = bytes;
    }
    try {
      final streamed = await _http.send(request).timeout(_timeout);
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ReaMicroS3Exception('连接 WebDAV 超时，请检查地址与网络');
    } on SocketException catch (error) {
      throw ReaMicroS3Exception('连接 WebDAV 失败：${error.message}');
    } on http.ClientException catch (error) {
      throw ReaMicroS3Exception('连接 WebDAV 失败：${error.message}');
    }
  }

  Uri _uriFor(String key, {bool directory = false}) {
    final base = Uri.parse(config.normalizedEndpoint);
    final segments = <String>[
      ...base.pathSegments.where((item) => item.isNotEmpty),
      ...key.split('/').where((item) => item.isNotEmpty),
    ];
    var path = '/${segments.map(Uri.encodeComponent).join('/')}';
    if (directory) path = '$path/';
    return base.replace(path: path, query: null, fragment: null);
  }

  String get _authorization {
    final username = config.accessKey;
    final password = config.secretKey;
    if (username.isEmpty && password.isEmpty) return '';
    final token = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $token';
  }

  static String _requireStrongEtag(String? value) {
    final tag = (value ?? '').trim();
    if (!_isStrongEtag(tag)) {
      throw const ReaMicroS3Exception(
        'WebDAV 服务必须提供强 ETag，无法安全同步到此服务',
      );
    }
    return tag;
  }

  static String _strongEtag(String value) {
    final tag = value.trim();
    if (!_isStrongEtag(tag)) {
      throw const ReaMicroS3Exception('WebDAV 条件写入的 ETag 无效');
    }
    return tag;
  }

  static bool _isStrongEtag(String value) =>
      value.length >= 2 &&
      value.startsWith('"') &&
      value.endsWith('"') &&
      value.runes.skip(1).take(value.length - 2).every(
        (char) => char == 0x21 || (char >= 0x23 && char <= 0x7e),
      );

  void _check(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final text = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    final suffix = text.isEmpty
        ? ''
        : '：${text.length > 200 ? '${text.substring(0, 200)}…' : text}';
    throw ReaMicroS3Exception(
      '$action失败：HTTP ${response.statusCode}$suffix',
    );
  }
}
