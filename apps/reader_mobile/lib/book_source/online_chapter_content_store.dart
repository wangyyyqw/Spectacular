import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 在线书源的逐章正文磁盘缓存。目录元数据与正文缓存彼此独立。
class OnlineChapterContentStore {
  OnlineChapterContentStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;
  Future<Directory>? _rootTask;
  int _writeSequence = 0;

  /// 后台下载使用同一缓存根目录，不调用平台目录通道。
  Future<Directory> supportDirectory() => _directoryProvider();

  Future<String?> read({
    required String sourceId,
    required String bookUrl,
    required String chapterUrl,
    required String rulesFingerprint,
  }) async {
    final file = await _file(sourceId, bookUrl, chapterUrl, rulesFingerprint);
    try {
      if (!await file.exists()) return null;
      final value = await file.readAsString();
      return value.isEmpty ? null : value;
    } on FileSystemException {
      return null;
    }
  }

  /// 目录仅查询文件状态，避免读取全部章节正文。
  Future<bool> contains({
    required String sourceId,
    required String bookUrl,
    required String chapterUrl,
    required String rulesFingerprint,
  }) async {
    try {
      final file = await _file(sourceId, bookUrl, chapterUrl, rulesFingerprint);
      return await file.exists() && await file.length() > 0;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> write({
    required String sourceId,
    required String bookUrl,
    required String chapterUrl,
    required String rulesFingerprint,
    required String content,
  }) async {
    if (content.isEmpty) return;
    final file = await _file(sourceId, bookUrl, chapterUrl, rulesFingerprint);
    final temp = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.${++_writeSequence}.tmp',
    );
    try {
      await temp.writeAsString(content, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<Directory> _root() => _rootTask ??= _createRoot();

  Future<Directory> _createRoot() async {
    final root = Directory(
      p.join((await _directoryProvider()).path, 'online_chapter_cache'),
    );
    await root.create(recursive: true);
    return root;
  }

  Future<File> _file(
    String sourceId,
    String bookUrl,
    String chapterUrl,
    String rulesFingerprint,
  ) async {
    final key = sha256.convert(
      utf8.encode(
        jsonEncode([sourceId, bookUrl, chapterUrl, rulesFingerprint]),
      ),
    );
    return File(p.join((await _root()).path, '$key.txt'));
  }
}
