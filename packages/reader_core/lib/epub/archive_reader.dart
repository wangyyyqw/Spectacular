import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'epub_exception.dart';

/// OCF 校验结果。
class OcfReport {
  /// 创建校验结果。
  const OcfReport({required this.errors, required this.warnings});

  /// 致命问题。
  final List<String> errors;

  /// 可恢复问题（例如真实书籍的 mimetype 被压缩）。
  final List<String> warnings;

  /// 是否通过（无致命问题）。
  bool get ok => errors.isEmpty;
}

/// EPUB 的 ZIP 容器读取与 OCF 校验。
class EpubArchive {
  EpubArchive._(this._entries, this._orderedNames);

  /// 从字节打开 ZIP；损坏时抛出 [EpubException]。
  factory EpubArchive.fromBytes(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final entries = <String, ArchiveFile>{};
      final order = <String>[];
      for (final file in archive.files) {
        if (file.isFile && file.crc32 != null) {
          final actual = getCrc32(file.content);
          if (actual != file.crc32) {
            throw EpubException('E_CRC', 'CRC 校验失败：');
          }
        }
        final name = _normalizePath(file.name);
        if (name.isEmpty || file.isDirectory) {
          continue;
        }
        entries[name] = file;
        order.add(name);
      }
      if (entries.isEmpty) {
        throw const EpubException('E_ARCHIVE', 'ZIP 中没有文件');
      }
      return EpubArchive._(entries, order);
    } on EpubException {
      rethrow;
    } catch (error) {
      throw EpubException('E_ARCHIVE', 'ZIP 解析失败：$error');
    }
  }

  final Map<String, ArchiveFile> _entries;
  final List<String> _orderedNames;

  /// 全部文件名（保持 ZIP 顺序）。
  List<String> get names => List<String>.unmodifiable(_orderedNames);

  /// 文件数。
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
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 条目的压缩方式；不存在返回 null。
  CompressionType? compressionOf(String path) =>
      _entries[_normalizePath(path)]?.compression;

  /// 校验 OCF 的 mimetype 约定。
  OcfReport validateOcf() {
    final errors = <String>[];
    final warnings = <String>[];

    if (_orderedNames.isEmpty) {
      return OcfReport(errors: <String>['ZIP 为空'], warnings: warnings);
    }
    if (_orderedNames.first != 'mimetype') {
      errors.add('mimetype 不是第一个条目（实际：${_orderedNames.first}）');
    }

    final mimetype = _entries['mimetype'];
    if (mimetype == null) {
      return OcfReport(errors: <String>['缺少 mimetype 条目'], warnings: warnings);
    }

    final value = utf8.decode(mimetype.content, allowMalformed: true).trim();
    if (value != 'application/epub+zip') {
      errors.add('mimetype 内容错误：$value');
    }
    if (mimetype.compression != CompressionType.none) {
      warnings.add(
        'mimetype 被压缩（${mimetype.compression?.name ?? 'unknown'}），不符合 OCF',
      );
    }
    return OcfReport(errors: errors, warnings: warnings);
  }

  static String _normalizePath(String path) {
    var result = path.replaceAll('\\', '/');
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    return result;
  }
}
