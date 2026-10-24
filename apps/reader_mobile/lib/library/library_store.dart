import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/epub/epub_document.dart';

/// 书架条目（P4-01 前的轻量 JSON 存储；drift 落地后迁移）。
@immutable
class BookEntry {
  /// 创建条目。
  const BookEntry({
    required this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.addedAt,
    this.lastReadAt,
    this.spineCount,
  });

  /// 唯一标识（导入时间 + 随机数）。
  final String id;

  /// 书名（OPF dc:title；缺失时用文件名）。
  final String title;

  /// 作者（OPF dc:creator；缺失为空串）。
  final String author;

  /// EPUB 文件绝对路径（`books/<id>.epub`）。
  final String filePath;

  /// 导入时间。
  final DateTime addedAt;

  /// 最近阅读时间。
  final DateTime? lastReadAt;

  /// 章节数（打开结果携带，书架展示用）。
  final int? spineCount;

  /// 封面占位色：由 id 派生的稳定色相（§37.3 四级回退的第 4 级）。
  int get coverHue => id.hashCode.abs() % 360;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'author': author,
    'filePath': filePath,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'lastReadAt': lastReadAt?.millisecondsSinceEpoch,
    'spineCount': spineCount,
  };

  static BookEntry? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final filePath = json['filePath'];
    final addedAt = json['addedAt'];
    if (id is! String ||
        title is! String ||
        filePath is! String ||
        addedAt is! int) {
      return null;
    }
    final lastReadAt = json['lastReadAt'];
    final spineCount = json['spineCount'];
    return BookEntry(
      id: id,
      title: title,
      author: json['author'] is String ? json['author'] as String : '',
      filePath: filePath,
      addedAt: DateTime.fromMillisecondsSinceEpoch(addedAt),
      lastReadAt: lastReadAt is int
          ? DateTime.fromMillisecondsSinceEpoch(lastReadAt)
          : null,
      spineCount: spineCount is int ? spineCount : null,
    );
  }

  BookEntry copyWith({DateTime? lastReadAt}) => BookEntry(
    id: id,
    title: title,
    author: author,
    filePath: filePath,
    addedAt: addedAt,
    lastReadAt: lastReadAt ?? this.lastReadAt,
    spineCount: spineCount,
  );
}

/// 导入失败的对外错误（UI 直接展示 message）。
class LibraryImportException implements Exception {
  /// 创建错误。
  const LibraryImportException(this.message);

  /// 用户可读原因（来自 ImportReport 或 IO）。
  final String message;

  @override
  String toString() => message;
}

/// 书架存储：`books.json` 条目表 + `books/<id>.epub` 文件（真机测试版）。
/// [LibraryStore.memory] 为纯内存模式（无 IO，widget 测试用）。
class LibraryStore {
  /// 创建存储（真实文件模式）；[directoryProvider] 供测试注入。
  LibraryStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  /// 纯内存模式：不触文件系统，导入字节存内存（测试专用）。
  LibraryStore.memory() : _directoryProvider = null;

  final Future<Directory> Function()? _directoryProvider;
  final Map<String, Uint8List> _memoryBytes = <String, Uint8List>{};

  bool get _isMemory => _directoryProvider == null;
  Future<void>? _loading;
  File? _file;
  final Map<String, BookEntry> _items = <String, BookEntry>{};
  final List<void Function()> _listeners = <void Function()>[];

  /// 条目变化通知（书架刷新用）。
  void addListener(void Function() listener) => _listeners.add(listener);

  /// 取消通知。
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  Future<Directory> _booksDirectory() async {
    final root = await _directoryProvider!();
    final directory = Directory('${root.path}/books');
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _ensureLoaded() {
    if (_isMemory) {
      return Future<void>.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final root = await _directoryProvider!();
      await root.create(recursive: true);
      _file = File('${root.path}/books.json');
      if (!await _file!.exists()) {
        return;
      }
      final decoded = jsonDecode(await _file!.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final entries = decoded['books'];
      if (entries is! List) {
        return;
      }
      for (final raw in entries) {
        if (raw is Map<String, dynamic>) {
          final entry = BookEntry.fromJson(raw);
          if (entry != null && await File(entry.filePath).exists()) {
            _items[entry.id] = entry;
          }
        }
      }
    } catch (_) {
      // 存储不可用时退回内存；不阻塞书架。
    }
  }

  Future<void> _persist() async {
    if (_isMemory) {
      return;
    }
    final file = _file;
    if (file == null) {
      return;
    }
    final payload = jsonEncode(<String, Object?>{
      'books': _items.values.map((entry) => entry.toJson()).toList(),
    });
    await file.writeAsString(payload, flush: true);
  }

  /// 全部条目（导入时间倒序）。
  Future<List<BookEntry>> list() async {
    await _ensureLoaded();
    final entries = _items.values.toList()
      ..sort(
        (a, b) => b.addedAt.compareTo(a.addedAt),
      );
    return entries;
  }

  /// 导入 EPUB 字节：先打开校验（拿元数据与诊断报告），成功落盘
  /// `books/<id>.epub` 并入库；失败抛 [LibraryImportException]。
  Future<BookEntry> importBytes(
    Uint8List bytes, {
    String? fallbackTitle,
  }) async {
    await _ensureLoaded();
    final result = await openEpub(bytes);
    final document = result.document;
    if (document == null) {
      final detail = result.report.message ?? result.report.errorCode ?? '未知错误';
      throw LibraryImportException('无法导入：$detail');
    }
    final id = _newId();
    String filePath = '';
    if (_isMemory) {
      _memoryBytes[id] = bytes;
    } else {
      final directory = await _booksDirectory();
      final file = File('${directory.path}/$id.epub');
      await file.writeAsBytes(bytes, flush: true);
      filePath = file.path;
    }
    final title = document.meta.title.trim().isEmpty
        ? (fallbackTitle?.trim().isEmpty ?? true ? '未命名书籍' : fallbackTitle!)
        : document.meta.title.trim();
    final entry = BookEntry(
      id: id,
      title: title,
      author: document.meta.author.trim(),
      filePath: filePath,
      addedAt: DateTime.now(),
      spineCount: document.spine.length,
    );
    _items[id] = entry;
    await _persist();
    _notify();
    return entry;
  }

  /// 读书籍字节（打开阅读用）。
  Future<Uint8List> readBytes(BookEntry entry) async {
    await _ensureLoaded();
    if (_isMemory) {
      final bytes = _memoryBytes[entry.id];
      if (bytes != null) {
        return bytes;
      }
    }
    return File(entry.filePath).readAsBytes();
  }

  /// 记录最近阅读时间。
  Future<void> touchLastRead(String id) async {
    await _ensureLoaded();
    final entry = _items[id];
    if (entry == null) {
      return;
    }
    _items[id] = entry.copyWith(lastReadAt: DateTime.now());
    await _persist();
    _notify();
  }

  /// 删除书籍：先删条目再删文件（孤儿文件下次加载时被忽略）。
  Future<void> remove(String id) async {
    await _ensureLoaded();
    final entry = _items.remove(id);
    _memoryBytes.remove(id);
    await _persist();
    _notify();
    if (entry != null && !_isMemory) {
      try {
        await File(entry.filePath).delete();
      } catch (_) {
        // 文件删除失败留孤儿，加载时按「文件不存在」剔除。
      }
    }
  }

  String _newId() {
    final random = math.Random();
    return '${DateTime.now().millisecondsSinceEpoch}'
        '-${random.nextInt(0x7FFFFFFF).toRadixString(36)}';
  }
}
