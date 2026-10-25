import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/epub/epub_exception.dart';
import 'package:reader_core/position/locator.dart';
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

/// 导入报告明细（P4-06，`import_reports` 表的一行）。
@immutable
class ImportReportEntry {
  /// 创建条目。
  const ImportReportEntry({
    required this.code,
    required this.severity,
    required this.message,
    this.offset,
  });

  /// 诊断码（P7-05 码表；非码表告警用 `IMPORT_WARNING`）。
  final String code;

  /// 分级：0 提示、1 警告、2 错误。
  final int severity;

  /// 人类可读信息。
  final String message;

  /// 相关文件内偏移（可空）。
  final int? offset;
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
  final Map<String, String> _memorySettings = <String, String>{};
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

  /// 读取设置（`settings` 表 key/value，值由调用方约定格式）。
  Future<String?> getSetting(String key) async {
    if (_isMemory) {
      return _memorySettings[key];
    }
    final db = _db!;
    final rows = await (db.select(
      db.settingsTable,
    )..where((table) => table.key.equals(key))).get();
    return rows.isEmpty ? null : rows.single.value;
  }

  /// 写入设置（幂等 upsert）。
  Future<void> setSetting(String key, String value) async {
    if (_isMemory) {
      _memorySettings[key] = value;
      return;
    }
    final db = _db!;
    await db.into(db.settingsTable).insertOnConflictUpdate(
      SettingsTableCompanion.insert(key: key, value: value),
    );
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
    // §22.3/§76.1：导入期顺序统计各章正文字符数，进度量化与后续搜索索引
    // 共用同一次扫描。
    final charCounts = await document.countChapterCharacters(
      onProgress: (done, total) => onProgress?.call(
        0.85 + 0.1 * (total == 0 ? 1 : done / total),
      ),
    );
    final weights = ProgressWeights.fromCharCounts(
      charCounts,
      excluded: document.progressExcludedSpineIndexes,
    );
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
      final bookId = await db.into(db.books).insert(
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
          charCount: Value(weights.totalCharacters),
          createdAt: entry.addedAt.millisecondsSinceEpoch,
          level: Value(result.report.readabilityLevel),
          warnings: Value(
            result.report.warnings.isEmpty
                ? null
                : jsonEncode(result.report.warnings),
          ),
        ),
      );
      // P4-06：把修复与告警按诊断码拆行落库，详情页可逐条展示。
      await _writeImportReports(bookId, result.report);
      // P4-09：spine 行落地（字符数与章前累计），供进度量化使用。
      await _writeSpineItems(bookId, document, charCounts, weights);
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
    // §37.4：先删库行（级联清子表），再删书目录与旧格式原书文件；
    // 删文件失败留孤儿，启动扫描可清理。
    final db = _db!;
    final rows = await (db.select(
      db.books,
    )..where((table) => table.uuid.equals(id))).get();
    final sourcePaths = <String>[
      for (final row in rows)
        if (row.sourcePath != null) row.sourcePath!,
    ];
    await (db.delete(
      db.books,
    )..where((table) => table.uuid.equals(id))).go();
    for (final path in sourcePaths) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // 占用失败留孤儿，启动扫描清理。
        }
      }
    }
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

  /// 写入 spine 行（§36.1）：字符数与章前累计供进度量化（§76.1）。
  Future<void> _writeSpineItems(
    int bookId,
    EpubDocumentImpl document,
    List<int> charCounts,
    ProgressWeights weights,
  ) async {
    final db = _db!;
    await db.batch((batch) {
      batch.insertAll(db.spineItems, <SpineItemsCompanion>[
        for (var index = 0; index < document.spine.length; index++)
          SpineItemsCompanion.insert(
            bookId: bookId,
            spineIndex: index,
            href: document.spine[index].href,
            linear: Value<int>(document.spine[index].linear ? 1 : 0),
            charCount: Value<int>(charCounts[index]),
            charStart: Value<int>(weights.charStarts[index]),
          ),
      ]);
    });
  }

  /// 读取某本书的进度权重表（§76.1）；未统计时按章等权估算。
  Future<ProgressWeights> progressWeights(String bookId) async {
    if (_isMemory) {
      return ProgressWeights.fromCharCounts(const <int>[]);
    }
    final db = _db!;
    final bookRows = await (db.select(
      db.books,
    )..where((table) => table.uuid.equals(bookId))).get();
    if (bookRows.isEmpty) {
      return ProgressWeights.fromCharCounts(const <int>[]);
    }
    final spineRows =
        await (db.select(db.spineItems)
              ..where((table) => table.bookId.equals(bookRows.single.id))
              ..orderBy([
                (table) => OrderingTerm(expression: table.spineIndex),
              ]))
            .get();
    return ProgressWeights.fromCharCounts(
      <int>[for (final row in spineRows) row.charCount ?? 0],
      excluded: <int>{
        for (final row in spineRows)
          if (row.linear == 0) row.spineIndex,
      },
    );
  }

  /// `CODE: message` 形式的导入告警。
  static final RegExp _diagnosticPattern = RegExp(
    r'^([A-Z][A-Z0-9_]{2,}):\s*([\s\S]*)$',
  );

  /// 写入导入报告明细（P4-06）：每条告警一行，分级取 P7-05 码表。
  Future<void> _writeImportReports(int bookId, ImportReport report) async {
    if (report.warnings.isEmpty) {
      return;
    }
    final db = _db!;
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    await db.batch((batch) {
      batch.insertAll(db.importReports, <ImportReportsCompanion>[
        for (final warning in report.warnings)
          _reportCompanion(bookId, warning, createdAt),
      ]);
    });
  }

  ImportReportsCompanion _reportCompanion(
    int bookId,
    String warning,
    int createdAt,
  ) {
    final trimmed = warning.trim();
    final match = _diagnosticPattern.firstMatch(trimmed);
    final code = match?.group(1) ?? 'IMPORT_WARNING';
    final message = ((match?.group(2) ?? trimmed)).trim();
    final severity = switch (EpubCodeTable.byCode(code)?.severity) {
      EpubErrorSeverity.fatal => 2,
      EpubErrorSeverity.recoverable => 1,
      EpubErrorSeverity.informational => 0,
      null => 1,
    };
    return ImportReportsCompanion.insert(
      bookId: bookId,
      code: code,
      severity: Value<int>(severity),
      message: message.isEmpty ? trimmed : message,
      createdAt: createdAt,
    );
  }

  /// 读取某本书的导入报告明细（错误优先，其次按写入顺序）。
  Future<List<ImportReportEntry>> importReports(String bookId) async {
    if (_isMemory) {
      return const <ImportReportEntry>[];
    }
    final db = _db!;
    final bookRows = await (db.select(
      db.books,
    )..where((table) => table.uuid.equals(bookId))).get();
    if (bookRows.isEmpty) {
      return const <ImportReportEntry>[];
    }
    final rows =
        await (db.select(db.importReports)
              ..where((table) => table.bookId.equals(bookRows.single.id))
              ..orderBy([
                (table) => OrderingTerm(
                  expression: table.severity,
                  mode: OrderingMode.desc,
                ),
                (table) => OrderingTerm(expression: table.id),
              ]))
            .get();
    return <ImportReportEntry>[
      for (final row in rows)
        ImportReportEntry(
          code: row.code,
          severity: row.severity,
          message: row.message,
          offset: row.offset,
        ),
    ];
  }

  /// 启动扫描：清理数据库中不存在的书目录与旧格式孤儿文件（§37.4）。
  ///
  /// 返回清理的条目数与释放的字节数；失败项跳过（下次启动再试）。
  Future<({int removed, int bytes})> sweepOrphans() async {
    if (_isMemory) {
      return (removed: 0, bytes: 0);
    }
    final db = _db!;
    final root = await _root();
    final booksDirectory = Directory('${root.path}/books');
    if (!await booksDirectory.exists()) {
      return (removed: 0, bytes: 0);
    }
    final rows = await db.select(db.books).get();
    final knownIds = <String>{for (final row in rows) row.uuid};
    final knownFiles = <String>{
      for (final row in rows)
        if (row.sourcePath != null) row.sourcePath!,
    };
    var removed = 0;
    var bytes = 0;
    await for (final entity in booksDirectory.list(followLinks: false)) {
      if (entity is Directory) {
        // 新格式：books/<uuid>/；未知 uuid 即孤儿目录。
        if (knownIds.contains(p.basename(entity.path))) {
          continue;
        }
        bytes += await _sizeOf(entity);
        try {
          await entity.delete(recursive: true);
          removed += 1;
        } catch (_) {
          // 占用/权限失败：保留，下次启动再试。
        }
      } else if (entity is File) {
        // 旧格式：books/<id>.epub；只留数据库引用中的文件。
        if (knownFiles.contains(entity.path)) {
          continue;
        }
        try {
          bytes += await entity.length();
          await entity.delete();
          removed += 1;
        } catch (_) {
          // 同上。
        }
      }
    }
    return (removed: removed, bytes: bytes);
  }

  Future<int> _sizeOf(FileSystemEntity entity) async {
    var total = 0;
    if (entity is File) {
      try {
        total += await entity.length();
      } catch (_) {
        // 单个文件不可读时忽略大小。
      }
      return total;
    }
    if (entity is Directory) {
      await for (final child in entity.list(
        recursive: true,
        followLinks: false,
      )) {
        if (child is File) {
          try {
            total += await child.length();
          } catch (_) {
            // 同上。
          }
        }
      }
    }
    return total;
  }

  /// 给缺封面的旧书补提取封面（迁移后的一次性回填，幂等）。
  ///
  /// 只处理 `cover_path` 为空的书；单本失败不影响其它书。
  Future<int> backfillCovers() async {
    if (_isMemory) {
      return 0;
    }
    final db = _db!;
    final rows = await (db.select(
      db.books,
    )..where((table) => table.coverPath.isNull())).get();
    var filled = 0;
    for (final row in rows) {
      final sourcePath = row.sourcePath;
      if (sourcePath == null || !await File(sourcePath).exists()) {
        continue;
      }
      try {
        final bytes = await File(sourcePath).readAsBytes();
        final document = (await openEpub(bytes)).document;
        final coverBytes = document?.readCoverBytes();
        if (document == null || coverBytes == null || coverBytes.isEmpty) {
          continue;
        }
        final root = await _root();
        final directory = Directory('${root.path}/books/${row.uuid}');
        await directory.create(recursive: true);
        final extension = _coverExtension(document.coverResourcePath);
        final coverFile = File('${directory.path}/cover.$extension');
        await coverFile.writeAsBytes(coverBytes, flush: true);
        await (db.update(db.books)..where((table) => table.id.equals(row.id)))
            .write(BooksCompanion(coverPath: Value(coverFile.path)));
        filled += 1;
      } catch (_) {
        // 单本解析失败跳过，不影响其它书。
      }
    }
    if (filled > 0) {
      _notify();
    }
    return filled;
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
