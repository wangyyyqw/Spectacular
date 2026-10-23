import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'epub_exception.dart';

/// EPUB 的 ZIP 容器读取（P1-01 的最小实现，P1-03 扩展 OCF 校验）。
class EpubArchive {
  EpubArchive._(this._entries);

  /// 从字节打开 ZIP；损坏时抛出 [EpubException]。
  factory EpubArchive.fromBytes(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final entries = <String, ArchiveFile>{};
      for (final file in archive.files) {
        final name = _normalizePath(file.name);
        if (name.isNotEmpty) {
          entries[name] = file;
        }
      }
      return EpubArchive._(entries);
    } on EpubException {
      rethrow;
    } catch (error) {
      throw EpubException('E_ARCHIVE', 'ZIP 解析失败：$error');
    }
  }

  final Map<String, ArchiveFile> _entries;

  /// 全部条目名（已去掉前导 `/`）。
  Iterable<String> get names => _entries.keys;

  /// 条目数。
  int get length => _entries.length;

  /// 是否存在指定路径。
  bool contains(String path) => _entries.containsKey(_normalizePath(path));

  /// 读取字节；不存在返回 null。
  Uint8List? readBytes(String path) {
    final entry = _entries[_normalizePath(path)];
    if (entry == null) {
      return null;
    }
    return Uint8List.fromList(entry.content);
  }

  /// 读取文本（UTF-8）；不存在返回 null。
  String? readString(String path) {
    final bytes = readBytes(path);
    if (bytes == null) {
      return null;
    }
    return utf8.decode(bytes);
  }

  static String _normalizePath(String path) {
    var result = path.replaceAll('\\', '/');
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    return result;
  }
}
