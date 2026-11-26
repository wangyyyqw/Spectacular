import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'cloud_models.dart';

class CloudDownloadCancelled extends CloudException {
  const CloudDownloadCancelled() : super('已取消下载');
}

/// 每个文件独立连接；取消会关闭连接并删除未完成的文件。
class CloudBookDownload {
  CloudBookDownload({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client.close();
  }

  void _check() {
    if (_cancelled) throw const CloudDownloadCancelled();
  }

  Future<File> save(
    CloudDownload source,
    File target, {
    required void Function(int received, int total) onProgress,
  }) async {
    var completed = false;
    try {
      _check();
      final response = await _open(source);
      await _write(response, source, target, onProgress);
      _check();
      completed = true;
      return target;
    } on TimeoutException {
      throw const CloudException('下载超时，请检查网络后重试');
    } on http.ClientException {
      _check();
      throw const CloudException('下载连接中断，请重试');
    } on SocketException {
      _check();
      throw const CloudException('无法连接下载服务器，请重试');
    } on FileSystemException {
      throw const CloudException('无法保存下载文件，请检查存储空间');
    } finally {
      _client.close();
      if (!completed && await target.exists()) await target.delete();
    }
  }

  Future<http.StreamedResponse> _open(CloudDownload source) async {
    var uri = source.url;
    var headers = {...source.headers, 'Accept-Encoding': 'identity'};
    for (var redirects = 0; redirects <= 5; redirects++) {
      _check();
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll(headers);
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
        return _accepted(response);
      }
      await response.stream.listen(null).cancel();
      final location = response.headers['location'];
      if (location == null) break;
      final next = cloudUrl(uri.resolve(location).toString());
      if (uri.scheme == 'https' && next.scheme != 'https') {
        throw const CloudException('下载地址跳转到不安全连接，已停止下载');
      }
      if (uri.origin != next.origin) headers = _publicHeaders(headers);
      uri = next;
    }
    throw const CloudException('下载地址跳转异常，请刷新目录后重试');
  }

  Future<http.StreamedResponse> _accepted(
    http.StreamedResponse response,
  ) async {
    if (response.statusCode == 200) return response;
    await response.stream.listen(null).cancel();
    throw CloudException(
      {401, 403, 410}.contains(response.statusCode)
          ? '下载地址已失效或无下载权限，请重试；仍失败时重新登录'
          : '下载失败（${response.statusCode}），请稍后重试',
    );
  }

  Map<String, String> _publicHeaders(Map<String, String> headers) => {
    for (final entry in headers.entries)
      if ({
        'user-agent',
        'accept',
        'accept-encoding',
      }.contains(entry.key.toLowerCase()))
        entry.key: entry.value,
  };

  Future<void> _write(
    http.StreamedResponse response,
    CloudDownload source,
    File target,
    void Function(int, int) onProgress,
  ) async {
    final type = response.headers['content-type']?.toLowerCase() ?? '';
    if (type.contains('text/html') || type.contains('application/json')) {
      await response.stream.listen(null).cancel();
      throw const CloudException('网盘返回了验证页，请重新登录后下载原文件');
    }
    final length = response.contentLength ?? 0;
    if (source.size > 0 && length > 0 && length != source.size) {
      await response.stream.listen(null).cancel();
      throw const CloudException('下载内容大小与所选文件不一致，请刷新目录');
    }
    final output = await target.open(mode: FileMode.write);
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 45),
      )) {
        _check();
        await output.writeFrom(chunk);
        received += chunk.length;
        onProgress(received, source.size > 0 ? source.size : length);
      }
    } finally {
      await output.close();
    }
    final expected = source.size > 0 ? source.size : length;
    if (received == 0 || expected > 0 && received != expected) {
      throw const CloudException('文件未下载完整，请重试');
    }
  }
}
