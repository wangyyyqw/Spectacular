import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'sync_models.dart';

abstract interface class SyncStorage {
  Future<Uint8List?> read(String key);
  Future<void> upload(String key, File file, {bool createOnly = false});
  Future<void> download(String key, File file);
  Future<List<String>> list(String directory);
  Future<void> delete(String key);
  void close();
}

/// 小型元数据限定大小；图书和素材直接通过文件流传输。
abstract class SyncHttpStorage implements SyncStorage {
  SyncHttpStorage(this.profile, {http.Client? client})
    : client = client ?? http.Client();
  final SyncProfile profile;
  final http.Client client;
  static const timeout = Duration(seconds: 120);

  Uri address(String key, {bool directory = false}) {
    if (key.isNotEmpty) validateSyncPath(key);
    return profile.uri.replace(
      pathSegments: [
        ...profile.uri.pathSegments.where((part) => part.isNotEmpty),
        if (profile.provider == SyncProvider.s3) profile.bucket.trim(),
        ...profile.directory.split('/'),
        ...key.split('/').where((part) => part.isNotEmpty),
        if (directory) '',
      ],
    );
  }

  Map<String, String> headers(
    String method,
    Uri uri,
    String digest,
    Map<String, String> extra,
  );

  Future<http.StreamedResponse> request(
    String method,
    Uri uri, {
    List<int>? bytes,
    File? file,
    Map<String, String> extra = const {},
  }) async {
    final digest = file == null
        ? sha256.convert(bytes ?? []).toString()
        : (await sha256.bind(file.openRead()).first).toString();
    final request = http.StreamedRequest(method, uri)
      ..followRedirects = false
      ..headers.addAll(headers(method, uri, digest, extra))
      ..contentLength = file == null
          ? (bytes?.length ?? 0)
          : await file.length();
    final response = client.send(request).timeout(timeout);
    response.ignore();
    try {
      if (file != null) {
        await request.sink.addStream(file.openRead()).timeout(timeout);
      } else if (bytes != null) {
        request.sink.add(bytes);
      }
      await request.sink.close();
      return await response;
    } on TimeoutException {
      throw const HttpException('同步传输超时，待发送数据已保留');
    }
  }

  Future<Uint8List> responseBytes(http.StreamedResponse response) async {
    final result = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(timeout)) {
      result.add(chunk);
      if (result.length > 8 * 1024 * 1024) {
        throw const FormatException('同步元数据超过协议的 8 MiB 限制');
      }
    }
    return result.takeBytes();
  }

  void check(http.StreamedResponse response, String operation) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw HttpException('$operation失败：HTTP ${response.statusCode}');
  }

  @override
  Future<Uint8List?> read(String key) async {
    final response = await request('GET', address(key));
    if (response.statusCode == 404) {
      await response.stream.drain<void>();
      return null;
    }
    check(response, '读取同步数据');
    return responseBytes(response);
  }

  @override
  Future<void> download(String key, File file) async {
    final response = await request('GET', address(key));
    check(response, '下载同步文件');
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    try {
      await sink.addStream(response.stream.timeout(timeout));
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> upload(String key, File file, {bool createOnly = false}) async {
    final response = await request(
      'PUT',
      address(key),
      file: file,
      extra: {
        'content-type': 'application/octet-stream',
        if (createOnly) 'if-none-match': '*',
      },
    );
    check(response, '上传同步文件');
    await response.stream.timeout(timeout).drain<void>();
  }

  @override
  Future<void> delete(String key) async {
    final response = await request('DELETE', address(key));
    if (response.statusCode != 404) check(response, '清理连接测试文件');
    await response.stream.timeout(timeout).drain<void>();
  }

  @override
  void close() => client.close();
}
