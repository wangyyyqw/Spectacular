import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as path;

import '../layout/page_index.dart';

/// 同一版面的准确总数与可选页界索引，不携带文字布局或页面位图。
class ChapterPaginationData {
  const ChapterPaginationData({
    required this.key,
    required this.pageCount,
    this.pageIndex,
  });

  final String key;
  final int pageCount;
  final Uint8List? pageIndex;
}

/// 缓存存储只读写已完成的分页决策，不执行章节解析、测量或绘制。
abstract interface class ChapterPaginationStore {
  Future<ChapterPaginationData?> read(String key);
  Future<void> write(ChapterPaginationData data);
}

/// 文件异步读写，编码与完整性校验在独立 isolate 中完成。
class FileChapterPaginationStore implements ChapterPaginationStore {
  FileChapterPaginationStore({
    required this.directoryProvider,
    this.maxBytes = 64 << 20,
  });

  final Future<Directory> Function() directoryProvider;
  final int maxBytes;
  Future<Directory>? _directory;

  Future<Directory> _root() => _directory ??= directoryProvider().then(
    (root) =>
        Directory(path.join(root.path, 'chapter-pagination-v1'))
            .create(recursive: true),
  );

  File _file(Directory root, String key) => File(
    path.join(root.path, '${sha256.convert(utf8.encode(key))}.pagination'),
  );

  @override
  Future<ChapterPaginationData?> read(String key) async {
    try {
      final file = _file(await _root(), key);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file || stat.size > maxBytes) {
        return null;
      }
      final result = await compute(_decodePaginationRecord, (
        key: key,
        bytes: await file.readAsBytes(),
      ));
      if (result != null) await file.setLastModified(DateTime.now());
      return result;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(ChapterPaginationData data) async {
    final bytes = await compute(_encodePaginationRecord, data);
    if (bytes.length > maxBytes) return;
    final root = await _root();
    final target = _file(root, data.key);
    final staging = await root.createTemp('write-');
    try {
      final file = File(path.join(staging.path, 'record'));
      await file.writeAsBytes(bytes, flush: true);
      await file.rename(target.path);
    } finally {
      await staging.delete(recursive: true);
    }
    await _trim(root, target.path);
  }

  Future<void> _trim(Directory root, String retainedPath) async {
    final files = <({File file, FileStat stat})>[];
    var bytes = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.pagination')) continue;
      final stat = await entity.stat();
      files.add((file: entity, stat: stat));
      bytes += stat.size;
    }
    files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    for (final entry in files) {
      if (bytes <= maxBytes) break;
      if (entry.file.path == retainedPath) continue;
      await entry.file.delete();
      bytes -= entry.stat.size;
    }
  }
}

Uint8List _encodePaginationRecord(ChapterPaginationData data) {
  final body = utf8.encode(
    jsonEncode({
      'version': 1,
      'key': data.key,
      'pageCount': data.pageCount,
      'pageIndex': data.pageIndex == null
          ? null
          : base64.encode(data.pageIndex!),
    }),
  );
  return Uint8List.fromList([
    ...ascii.encode(sha256.convert(body).toString()),
    10,
    ...body,
  ]);
}

ChapterPaginationData? _decodePaginationRecord(
  ({String key, Uint8List bytes}) input,
) {
  final bytes = input.bytes;
  if (bytes.length < 65 || bytes[64] != 10) return null;
  final body = Uint8List.sublistView(bytes, 65);
  if (ascii.decode(bytes.sublist(0, 64), allowInvalid: true) !=
      sha256.convert(body).toString()) {
    return null;
  }
  try {
    final data = jsonDecode(utf8.decode(body));
    if (data is! Map<String, dynamic> || data['version'] != 1) return null;
    final count = data['pageCount'];
    final encoded = data['pageIndex'];
    if (data['key'] != input.key || count is! int || count < 0) return null;
    if (encoded != null && encoded is! String) return null;
    final index = encoded == null ? null : base64.decode(encoded as String);
    if (index != null && PageIndex.decode(index)?.entries.length != count) {
      return null;
    }
    return ChapterPaginationData(
      key: input.key,
      pageCount: count,
      pageIndex: index,
    );
  } on FormatException {
    return null;
  }
}
