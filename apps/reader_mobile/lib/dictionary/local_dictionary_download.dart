import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'builtin_dictionaries.dart';
import 'local_dictionary_store.dart';

class LocalDictionaryDownloadCancelled extends LocalDictionaryException {
  const LocalDictionaryDownloadCancelled() : super('已取消下载');
}

/// 流式下载到临时目录，校验后复用正式导入入口；结束时回收临时文件。
class LocalDictionaryDownload {
  LocalDictionaryDownload({
    http.Client? client,
    this.temporaryDirectoryProvider = getTemporaryDirectory,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Future<Directory> Function() temporaryDirectoryProvider;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client.close();
  }

  void _checkCancelled() {
    if (_cancelled) throw const LocalDictionaryDownloadCancelled();
  }

  Future<LocalDictionaryEntry> install(
    BuiltInDictionary source,
    LocalDictionaryStore store, {
    required void Function(int received) onProgress,
    required void Function() onImport,
  }) async {
    Directory? temporary;
    try {
      _checkCancelled();
      temporary = await (await temporaryDirectoryProvider()).createTemp(
        'dictionary-download-',
      );
      final file = File(p.join(temporary.path, '${source.id}.mdx'));
      await _download(source, file, onProgress);
      final digest = await sha256.bind(file.openRead()).first;
      _checkCancelled();
      if (digest.toString() != source.digest) {
        throw const LocalDictionaryException('词典文件校验失败，请重新下载');
      }
      onImport();
      return await store.importFiles([file.path]);
    } on TimeoutException {
      _checkCancelled();
      throw const LocalDictionaryException('下载超时，请检查网络后重试');
    } on http.ClientException {
      _checkCancelled();
      throw const LocalDictionaryException('下载连接中断，请重试');
    } on SocketException {
      _checkCancelled();
      throw const LocalDictionaryException('无法连接下载服务器，请重试');
    } on FileSystemException {
      throw const LocalDictionaryException('无法保存词典，请检查存储空间后重试');
    } finally {
      _client.close();
      if (temporary != null) await temporary.delete(recursive: true);
    }
  }

  Future<void> _download(
    BuiltInDictionary source,
    File file,
    void Function(int) onProgress,
  ) async {
    _checkCancelled();
    final request = http.Request('GET', Uri.parse(source.url));
    request.headers['Accept-Encoding'] = 'identity';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw LocalDictionaryException('词典下载失败（${response.statusCode}），请稍后重试');
    }
    if (response.contentLength != null &&
        response.contentLength != source.size) {
      throw const LocalDictionaryException('词典文件大小不符，请重新下载');
    }
    await _write(response.stream, file, source.size, onProgress);
  }

  Future<void> _write(
    Stream<List<int>> stream,
    File file,
    int expected,
    void Function(int) onProgress,
  ) async {
    final output = await file.open(mode: FileMode.write);
    var received = 0;
    try {
      await for (final chunk in stream.timeout(const Duration(seconds: 45))) {
        _checkCancelled();
        received += chunk.length;
        if (received > expected) {
          throw const LocalDictionaryException('词典文件大小不符，请重新下载');
        }
        await output.writeFrom(chunk);
        onProgress(received);
      }
      _checkCancelled();
      if (received != expected) {
        throw const LocalDictionaryException('词典未下载完整，请重试');
      }
    } finally {
      await output.close();
    }
  }
}
