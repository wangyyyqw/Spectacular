import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/epub/epub_document.dart';

import '../storage/db.dart';

/// 阅读状态（P4-04）：未读 / 在读 / 已读。
///
/// 已读判定依赖进度百分比（P4-09 量化），当前只有「未读 / 在读」两态，
/// `finished` 留给进度模型接入。
enum BookReadingStatus {
  /// 从未打开。
  unread,

  /// 有阅读记录。
  reading,

  /// 已读完（待 P4-09 进度百分比接入）。
  finished,
}

/// 书架条目（drift `books` 表的一行投影）。
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
    this.readabilityLevel = 0,
    this.coverPath,
  });

  /// 唯一标识（= `books.uuid`，导入时间 + 随机数）。
  final String id;

  /// 书名（OPF dc:title；缺失时用文件名）。
  final String title;

  /// 作者（OPF dc:creator；缺失为空串）。
  final String author;

  /// EPUB 文件绝对路径（`books/<id>/source.epub`）。
  final String filePath;

  /// 导入时间。
  final DateTime addedAt;

  /// 最近阅读时间。
  final DateTime? lastReadAt;

  /// 章节数（打开结果携带，书架展示用）。
  final int? spineCount;

  /// 可读性分级（P3-26，0~4）：L2/L3 书架显示「结构异常」角标。
  final int readabilityLevel;

  /// 封面缓存文件路径（§37.3 三级提取成功后落盘）；null 用占位。
  final String? coverPath;

  /// 阅读状态（由 lastReadAt 推导）。
  BookReadingStatus get status =>
      lastReadAt == null ? BookReadingStatus.unread : BookReadingStatus.reading;

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
    'readabilityLevel': readabilityLevel,
    'coverPath': coverPath,
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
      readabilityLevel: json['readabilityLevel'] is int
          ? json['readabilityLevel'] as int
          : 0,
      coverPath: json['coverPath'] is String
          ? json['coverPath'] as String
          : null,
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
    readabilityLevel: readabilityLevel,
    coverPath: coverPath,
  );
}

/// 导入失败的对外错误（UI 直接展示 message）。
class LibraryImportException implements Exception {
  /// 创建错误。
  const LibraryImportException(this.message, {this.errorCode});

  /// 用户可读原因（来自 ImportReport 或 IO）。
  final String message;

  /// 结构化错误码（P3-27：UI 据此映射拒绝文案）。
  final String? errorCode;

  @override
  String toString() => message;
}

/// 书库存储（P4-04）：drift `books` 表 + `books/<uuid>/` 目录
/// （`source.epub` 原书 + `cover.jpg` 封面缓存）。
///
/// [LibraryStore.memory] 为纯内存模式（无数据库、无 IO，widget 测试用）。
class LibraryStore {
  /// 创建存储；[database] 是启动时打开的库，[directoryProvider] 供测试注入。
  LibraryStore({
    required AppDatabase database,
    Future<Directory> Function()? directoryProvider,
  }) : _db = database,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  /// 纯内存模式：不触文件系统与数据库（测试专用）。
  LibraryStore.memory()
    : _db = null,
      _directoryProvider = null;

  final AppDatabase? _db;
  final Future<Directory> Function()? _directoryProvider;
  final Map<String, Uint8List> _memoryBytes = <String, Uint8List>{};
  final Map<String, BookEntry> _memoryEntries = <String, BookEntry>{};
  final List<void Function()> _listeners = <void Function()>[];

  bool get _isMemory => _db == null;

  /// 条目变化通知（书架刷新用）。
  void addListener(void Function() listener) => _listeners.add(listener);

  /// 取消通知。
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  Future<Directory> _root() async {
    final root = await _directoryProvider!();
    await root.create(recursive: true);
    return root;
  }

  Future<Directory> _bookDirectory(String id) async {
    final root = await _root();
    final directory = Directory('${root.path}/books/$id');
    await directory.create(recursive: true);
    return directory;
  }

  /// 全部条目（最近阅读优先，其次导入时间倒序）。
  Future<List<BookEntry>> list() async {
    if (_isMemory) {
      final entries = _memoryEntries.values.toList()
        ..sort((a, b) {
          final left = a.lastReadAt;
          final right = b.lastReadAt;
          if (left != null || right != null) {
            if (left == null) {
              return 1;
            }
            if (right == null) {
              return -1;
            }
            final compared = right.compareTo(left);
            if (compared != 0) {
              return compared;
            }
          }
          return b.addedAt.compareTo(a.addedAt);
        });
      return entries;
    }
    final db = _db!;
    final rows =
        await (db.select(db.books)..orderBy([
              (table) => OrderingTerm(
                expression: table.lastReadAt,
                mode: OrderingMode.desc,
              ),
              (table) => OrderingTerm(
                expression: table.createdAt,
                mode: OrderingMode.desc,
              ),
            ]))
            .get();
    return <BookEntry>[
      for (final row in rows)
        BookEntry(
          id: row.uuid,
          title: row.title,
          author: row.author ?? '',
          filePath: row.sourcePath ?? '',
          addedAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
          lastReadAt: row.lastReadAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(row.lastReadAt!),
          spineCount: row.spineCount,
          readabilityLevel: row.level,
          coverPath: row.coverPath,
        ),
    ];
  }

  /// 导入 EPUB 字节：解析校验 → 落盘原书 → 提取并缓存封面 → 入库。
  ///
  /// [onProgress] 上报阶段进度 0～1（解析 → 落盘 → 封面 → 入库）。
  Future<BookEntry> importBytes(
    Uint8List bytes, {
    String? fallbackTitle,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.1);
    final result = await openEpub(bytes);
    final document = result.document;
    if (document == null) {
      final detail =
          result.report.message ?? result.report.errorCode ?? '未知错误';
      throw LibraryImportException(
        '无法导入：$detail',
        errorCode: result.report.errorCode,
      );
    }
    onProgress?.call(0.45);
    // §36.2：同一本书（OPF unique-identifier）只允许一份。
    final id = _bookKey(document.meta.identifier);
    if (await _contains(id)) {
      throw const LibraryImportException(
        '这本书已在书架中',
        errorCode: 'E_DUPLICATE',
      );
    }
    final title = document.meta.title.trim().isEmpty
        ? (fallbackTitle?.trim().isEmpty ?? true ? '未命名书籍' : fallbackTitle!)
        : document.meta.title.trim();
    String filePath = '';
    String? coverPath;
    if (_isMemory) {
      _memoryBytes[id] = bytes;
    } else {
      final directory = await _bookDirectory(id);
      final file = File('${directory.path}/source.epub');
      await file.writeAsBytes(bytes, flush: true);
      filePath = file.path;
      onProgress?.call(0.7);
      final coverBytes = document.readCoverBytes();
      if (coverBytes != null && coverBytes.isNotEmpty) {
        final extension = _coverExtension(document.coverResourcePath);
        final coverFile = File('${directory.path}/cover.$extension');
        await coverFile.writeAsBytes(coverBytes, flush: true);
        coverPath = coverFile.path;
      }
    }
    onProgress?.call(0.85);
    final entry = BookEntry(
      id: id,
      title: title,
      author: document.meta.author.trim(),
      filePath: filePath,
      addedAt: DateTime.now(),
      spineCount: document.spine.length,
      readabilityLevel: result.report.readabilityLevel,
      coverPath: coverPath,
    );
    if (_isMemory) {
      _memoryEntries[id] = entry;
    } else {
      final db = _db!;
      await db.into(db.books).insert(
        BooksCompanion.insert(
          uuid: id,
          title: title,
          author: Value(
            document.meta.author.trim().isEmpty
                ? null
                : document.meta.author.trim(),
          ),
          language: Value(
            document.meta.language.trim().isEmpty
                ? null
                : document.meta.language.trim(),
          ),
          // 尚未解包：书目录即资源目录；P4-04 之后解包到 books/<id>/content。
          contentDir: 'books/$id',
          sourcePath: Value(filePath),
          coverPath: Value(coverPath),
          spineCount: Value(document.spine.length),
          createdAt: entry.addedAt.millisecondsSinceEpoch,
          level: Value(result.report.readabilityLevel),
          warnings: Value(
            result.report.warnings.isEmpty
                ? null
                : jsonEncode(result.report.warnings),
          ),
        ),
      );
    }
    onProgress?.call(1);
    _notify();
    return entry;
  }

  /// 读书籍字节（打开阅读用）。
  Future<Uint8List> readBytes(BookEntry entry) async {
    if (_isMemory) {
      final bytes = _memoryBytes[entry.id];
      if (bytes != null) {
        return bytes;
      }
    }
    return File(entry.filePath).readAsBytes();
  }

  /// 记录最近阅读时间（同时把书标成「在读」）。
  Future<void> touchLastRead(String id) async {
    final now = DateTime.now();
    if (_isMemory) {
      final entry = _memoryEntries[id];
      if (entry == null) {
        return;
      }
      _memoryEntries[id] = entry.copyWith(lastReadAt: now);
    } else {
      final db = _db!;
      await (db.update(db.books)..where((table) => table.uuid.equals(id)))
          .write(
            BooksCompanion(lastReadAt: Value(now.millisecondsSinceEpoch)),
          );
    }
    _notify();
  }

  /// 删除书籍：先删库行（级联清标注/进度/spine/目录），再删书目录
  /// （原书 + 封面缓存），不留孤儿文件。
  Future<void> remove(String id) async {
    if (_isMemory) {
      _memoryBytes.remove(id);
      _memoryEntries.remove(id);
      _notify();
      return;
    }
    // §37.4：先删库行（级联清子表），再删书目录；删文件失败留孤儿目录，
    // 启动扫描可清理。
    final db = _db!;
    await (db.delete(
      db.books,
    )..where((table) => table.uuid.equals(id))).go();
    _notify();
    final root = await _root();
    final directory = Directory('${root.path}/books/$id');
    if (await directory.exists()) {
      try {
        await directory.delete(recursive: true);
      } catch (_) {
        // 权限/占用失败：下次启动扫描清理。
      }
    }
  }

  /// 把旧版 `books.json` 一次性迁入 drift（幂等：库非空直接返回 0）。
  ///
  /// §36.2：uuid 唯一，重复导入落到同一本书。
  Future<int> migrateLegacyJson() async {
    if (_isMemory) {
      return 0;
    }
    final db = _db!;
    final rows = await db.select(db.books).get();
    if (rows.isNotEmpty) {
      return 0;
    }
    final root = await _root();
    final file = File('${root.path}/books.json');
    if (!await file.exists()) {
      return 0;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return 0;
    }
    final entries = decoded['books'];
    if (entries is! List) {
      return 0;
    }
    var migrated = 0;
    for (final raw in entries) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final entry = BookEntry.fromJson(raw);
      if (entry == null || !await File(entry.filePath).exists()) {
        continue;
      }
      await db.into(db.books).insert(
        BooksCompanion.insert(
          uuid: entry.id,
          title: entry.title,
          author: Value(entry.author.isEmpty ? null : entry.author),
          contentDir: 'books/${entry.id}',
          sourcePath: Value(entry.filePath),
          coverPath: Value(entry.coverPath),
          spineCount: Value(entry.spineCount ?? 0),
          createdAt: entry.addedAt.millisecondsSinceEpoch,
          lastReadAt: Value(entry.lastReadAt?.millisecondsSinceEpoch),
          level: Value(entry.readabilityLevel),
        ),
      );
      migrated += 1;
    }
    _notify();
    return migrated;
  }

  static const _coverExtensions = <String>{'jpg', 'jpeg', 'png', 'gif', 'webp'};

  /// 封面文件扩展名：按资源路径后缀，未知按 jpg。
  static String _coverExtension(String? resourcePath) {
    if (resourcePath != null) {
      final dot = resourcePath.lastIndexOf('.');
      if (dot >= 0 && dot + 1 < resourcePath.length) {
        final extension = resourcePath.substring(dot + 1).toLowerCase();
        if (_coverExtensions.contains(extension)) {
          return extension == 'jpeg' ? 'jpg' : extension;
        }
      }
    }
    return 'jpg';
  }

  /// 书库主键：OPF unique-identifier 清洗成文件安全字符串；
  /// identifier 缺失时退回时间戳随机串。
  String _bookKey(String identifier) {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) {
      return _newId();
    }
    final sanitized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return sanitized.isEmpty ? _newId() : sanitized;
  }

  /// 书库里是否已有该主键的书。
  Future<bool> _contains(String id) async {
    if (_isMemory) {
      return _memoryEntries.containsKey(id);
    }
    final db = _db!;
    final rows = await (db.select(
      db.books,
    )..where((table) => table.uuid.equals(id))).get();
    return rows.isNotEmpty;
  }

  String _newId() {
    final random = math.Random();
    return '${DateTime.now().millisecondsSinceEpoch}'
        '-${random.nextInt(0x7FFFFFFF).toRadixString(36)}';
  }
}
