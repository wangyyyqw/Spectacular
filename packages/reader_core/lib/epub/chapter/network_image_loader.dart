import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../paint/image_size.dart';

/// 网络图片保存原始字节，包内图片和网络图片共用上层解码管线。
class NetworkImageLoader {
  NetworkImageLoader({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? _temporaryDirectory;

  static const maxImageBytes = 20 << 20;
  static const maxCacheBytes = 128 << 20;
  static const maxCacheEntries = 256;
  static const requestTimeout = Duration(seconds: 15);

  final Future<Directory> Function() _directoryProvider;
  final _clients = <HttpClient>{};
  Future<Directory>? _directoryTask;
  bool _closed = false;

  static Future<Directory> _temporaryDirectory() async => Directory.systemTemp;

  /// 调用方已校验 HTTP/HTTPS 地址；缓存键保留原网址的查询参数。
  Future<Uint8List?> read(Uri url) async {
    if (_closed) return null;
    final file = await _cacheFile(url);
    final cached = file == null ? null : await _readCached(file);
    if (_closed) return null;
    if (cached != null) return cached;
    final client = HttpClient()..connectionTimeout = requestTimeout;
    _clients.add(client);
    try {
      final bytes = await _download(client, url).timeout(requestTimeout);
      if (_closed || bytes == null) return null;
      if (file != null) await _writeCached(file, bytes);
      return _closed ? null : bytes;
    } on IOException {
      return null;
    } on TimeoutException {
      return null;
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  Future<Uint8List?> _download(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    if (_closed) return null;
    request.headers.set(HttpHeaders.acceptHeader, 'image/*');
    // HttpClient 的重定向仍属于同一次读取，落盘键始终是原始稳定网址。
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength > maxImageBytes) {
      return null;
    }
    final data = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (_closed || data.length + chunk.length > maxImageBytes) return null;
      data.add(chunk);
    }
    final bytes = data.takeBytes();
    // 拦下返回 200 的错误页面和不支持的图片，不污染持久缓存。
    return ImageSizeParser.readImageSize(bytes) == null ? null : bytes;
  }

  Future<File?> _cacheFile(Uri url) async {
    try {
      final root = await (_directoryTask ??= _directoryProvider());
      final key = sha256.convert(utf8.encode(url.toString()));
      return File(p.join(root.path, 'epub_network_images', '$key.image'));
    } on Exception {
      // 缓存目录不可用时仍允许网络读取；下次可以重新获取目录。
      _directoryTask = null;
      return null;
    }
  }

  Future<Uint8List?> _readCached(File file) async {
    Uint8List bytes;
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      if (stat.size > maxImageBytes) {
        await file.delete();
        return null;
      }
      bytes = await file.readAsBytes();
      if (ImageSizeParser.readImageSize(bytes) == null) {
        await file.delete();
        return null;
      }
    } on FileSystemException {
      return null;
    }
    try {
      await file.setLastModified(DateTime.now());
    } on FileSystemException {
      // 只读缓存仍可用于离线阅读，更新时间失败不丢弃有效字节。
    }
    return bytes;
  }

  Future<void> _writeCached(File file, Uint8List bytes) async {
    File? temporary;
    try {
      await file.parent.create(recursive: true);
      if (_closed) return;
      temporary = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
      );
      await temporary.writeAsBytes(bytes);
      if (_closed) return;
      await temporary.rename(file.path);
      temporary = null;
      await _pruneCache(file.parent);
    } on FileSystemException {
      // 缓存写入失败不影响本次显示，也不保存失败结果。
    } finally {
      if (temporary != null) {
        try {
          await temporary.delete();
        } on FileSystemException {
          // 系统缓存清理可能已经删除临时文件。
        }
      }
    }
  }

  Future<void> _pruneCache(Directory directory) async {
    final entries = <({File file, int size, DateTime modified})>[];
    var total = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || p.extension(entry.path) != '.image') continue;
      final stat = await entry.stat();
      entries.add((file: entry, size: stat.size, modified: stat.modified));
      total += stat.size;
    }
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    var count = entries.length;
    for (final entry in entries) {
      if (total <= maxCacheBytes && count <= maxCacheEntries) break;
      await entry.file.delete();
      total -= entry.size;
      count -= 1;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final client in _clients) {
      client.close(force: true);
    }
  }
}
