import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/epub/book_identity.dart';
import 'package:reader_core/epub/epub_exception.dart';
import 'package:reader_core/position/locator.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/position/revision_relocator.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';

import '../reader/epub_chapter_source.dart';
import '../reader/reader_settings.dart';
import '../storage/book_review_store.dart';
import '../storage/db.dart';
import '../storage/drift_annotation_store.dart';
import '../storage/drift_bookmark_store.dart';
import '../storage/reading_session_store.dart';
import 'book_identity_migration.dart';
import 'revision_anchor_index.dart';

part 'library_revision.dart';

/// 导入成功的实际结果，覆盖更新不会新建用户数据。
enum BookImportOutcome { added, updated, unchanged }

/// 阅读状态（P4-04）：未读 / 在读 / 已读。
enum BookReadingStatus {
  /// 从未打开。
  unread,

  /// 有阅读记录。
  reading,

  /// 已到达全书最后一页。
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
    this.description = '',
    this.lastReadAt,
    this.spineCount,
    this.readabilityLevel = 0,
    this.coverPath,
    this.contentRevision,
    this.importOutcome = BookImportOutcome.added,
  });

  /// 固定三元组摘要标识（= `books.uuid`，32 位小写十六进制）。
  final String id;

  /// 书名（OPF dc:title；缺失时用文件名）。
  final String title;

  /// 作者（OPF dc:creator；缺失为空串）。
  final String author;

  /// 用户可编辑的简介。
  final String description;

  /// EPUB 文件绝对路径（新书为 `books-v1/<id>/source.epub`）。
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

  /// 原书 SHA-256（导入时计算并落库）；旧数据或内存模式为 null。
  final String? contentRevision;

  /// 仅用于此次导入提示，不持久化到书架。
  final BookImportOutcome importOutcome;

  /// 阅读状态（由 lastReadAt 推导）。
  BookReadingStatus get status =>
      lastReadAt == null ? BookReadingStatus.unread : BookReadingStatus.reading;

  /// 结合持久化完成标记返回阅读状态。
  BookReadingStatus statusWith({bool finished = false}) {
    if (lastReadAt == null) {
      return BookReadingStatus.unread;
    }
    return finished ? BookReadingStatus.finished : BookReadingStatus.reading;
  }

  /// 封面占位色：由 id 派生的稳定色相（§37.3 四级回退的第 4 级）。
  int get coverHue => id.hashCode.abs() % 360;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'author': author,
    'description': description,
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
      description: json['description'] is String
          ? json['description'] as String
          : '',
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

  BookEntry copyWith({
    DateTime? lastReadAt,
    String? title,
    String? author,
    String? description,
  }) => BookEntry(
    id: id,
    title: title ?? this.title,
    author: author ?? this.author,
    description: description ?? this.description,
    filePath: filePath,
    addedAt: addedAt,
    lastReadAt: lastReadAt ?? this.lastReadAt,
    spineCount: spineCount,
    readabilityLevel: readabilityLevel,
    contentRevision: contentRevision,
    coverPath: coverPath,
    importOutcome: importOutcome,
  );
}

/// 书架分组。
@immutable
class ShelfGroup {
  /// 创建分组。
  const ShelfGroup({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  /// 分组标识。
  final String id;

  /// 分组名称。
  final String name;

  /// 创建时间。
  final DateTime createdAt;
}

/// 可跨书籍复用的自定义标签。
@immutable
class BookTag {
  /// 创建标签。
  const BookTag({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  /// 标签标识。
  final String id;

  /// 标签名称。
  final String name;

  /// 创建时间。
  final DateTime createdAt;
}

/// 书架封面到开场页封面的 Hero 标识。
String bookCoverHeroTag(String bookId) => 'book-cover-$bookId';

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

/// 应用保存的用户字体，不暴露数据库生成类型给阅读界面。
class ReaderFontEntry {
  const ReaderFontEntry({
    required this.family,
    required this.filePath,
    required this.displayName,
  });

  final String family;
  final String filePath;
  final String displayName;
}

/// 书库存储（P4-04）：drift `books` 表 + `books-v1/<id>/` 目录
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
  LibraryStore.memory() : _db = null, _directoryProvider = null;

  final AppDatabase? _db;
  final Future<Directory> Function()? _directoryProvider;
  final Map<String, Uint8List> _memoryBytes = <String, Uint8List>{};
  final Map<String, BookEntry> _memoryEntries = <String, BookEntry>{};
  final Map<String, String> _memorySettings = <String, String>{};
  final Map<String, ReaderFontEntry> _memoryFonts = <String, ReaderFontEntry>{};
  final Map<String, ShelfGroup> _memoryGroups = <String, ShelfGroup>{};
  final Map<String, String> _memoryBookGroups = <String, String>{};
  final Map<String, BookTag> _memoryTags = <String, BookTag>{};
  final Map<String, Set<String>> _memoryBookTags = <String, Set<String>>{};
  final List<void Function()> _listeners = <void Function()>[];
  Future<int>? _identityMigration;
  Future<void>? _importQueue;
  static final _databaseImportQueues = Expando<Future<void>>();

  bool get _isMemory => _db == null;

  /// 启动和导入共用迁移入口；失败可重试，不改变原书路径与整数外键。
  Future<int> migrateBookIds() async {
    if (_isMemory) return 0;
    final pending = _identityMigration;
    if (pending != null) return pending;
    final migration = migrateBookIdentities(_db!);
    _identityMigration = migration;
    try {
      return await migration;
    } finally {
      _identityMigration = null;
    }
  }

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
    final directory = _safeBookDirectory(root, id, canonical: true);
    if (directory == null) {
      throw const LibraryImportException('书籍标识无效，无法创建存储目录');
    }
    await directory.create(recursive: true);
    return directory;
  }

  Directory? _safeBookDirectory(
    Directory root,
    String id, {
    bool canonical = false,
  }) {
    if (id == '.' ||
        id == '..' ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(id)) {
      return null;
    }
    final booksPath = p.normalize(
      p.join(root.path, canonical ? 'books-v1' : 'books'),
    );
    final path = p.normalize(p.join(booksPath, id));
    return p.isWithin(booksPath, path) ? Directory(path) : null;
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
    await db
        .into(db.settingsTable)
        .insertOnConflictUpdate(
          SettingsTableCompanion.insert(key: key, value: value),
        );
  }

  /// 读取自定义字体清单；字体字节按实际选择延迟加载。
  Future<List<ReaderFontEntry>> listUserFonts() async {
    if (_isMemory) return List.unmodifiable(_memoryFonts.values);
    final db = _db!;
    final rows = await (db.select(
      db.userFonts,
    )..orderBy([(table) => OrderingTerm.asc(table.id)])).get();
    return rows
        .map(
          (row) => ReaderFontEntry(
            family: row.family,
            filePath: row.filePath,
            displayName: row.displayName ?? row.family,
          ),
        )
        .toList(growable: false);
  }

  /// 同一内容标识只保存一条，重复导入不会增加字体条目。
  Future<void> saveUserFont(ReaderFontEntry font) async {
    if (_isMemory) {
      _memoryFonts[font.family] = font;
      return;
    }
    final db = _db!;
    await db.transaction(() async {
      final existing = await (db.select(
        db.userFonts,
      )..where((table) => table.family.equals(font.family))).get();
      if (existing.isNotEmpty) {
        await (db.update(db.userFonts)
              ..where((table) => table.family.equals(font.family)))
            .write(UserFontsCompanion(filePath: Value(font.filePath)));
        return;
      }
      await db
          .into(db.userFonts)
          .insert(
            UserFontsCompanion.insert(
              family: font.family,
              filePath: font.filePath,
              displayName: Value(font.displayName),
            ),
          );
    });
  }

  /// 全部分组，按创建时间升序。
  Future<List<ShelfGroup>> listGroups() async {
    if (_isMemory) {
      final groups = _memoryGroups.values.toList()
        ..sort((a, b) {
          final compared = a.createdAt.compareTo(b.createdAt);
          return compared == 0 ? a.id.compareTo(b.id) : compared;
        });
      return groups;
    }
    final db = _db!;
    final rows =
        await (db.select(db.shelfGroups)..orderBy([
              (table) => OrderingTerm(expression: table.createdAt),
              (table) => OrderingTerm(expression: table.id),
            ]))
            .get();
    return <ShelfGroup>[
      for (final row in rows)
        ShelfGroup(
          id: row.id,
          name: row.name,
          createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
        ),
    ];
  }

  /// 书籍 uuid → 分组 id；没有分组的书不出现在结果中。
  Future<Map<String, String>> groupAssignments() async {
    if (_isMemory) {
      return Map<String, String>.of(_memoryBookGroups);
    }
    final db = _db!;
    final rows = await db.select(db.shelfGroupBooks).get();
    return <String, String>{for (final row in rows) row.bookUuid: row.groupId};
  }

  /// 新建分组；名称去首尾空白，空名或重名会被拒绝。
  Future<ShelfGroup> createGroup(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const LibraryImportException('分组名称不能为空');
    }
    final groups = await listGroups();
    if (groups.any((group) => group.name == normalized)) {
      throw const LibraryImportException('分组名称已存在');
    }
    final now = DateTime.now();
    final group = ShelfGroup(
      id:
          'group-${now.microsecondsSinceEpoch}-'
          '${math.Random().nextInt(0x7fffffff)}',
      name: normalized,
      createdAt: now,
    );
    if (_isMemory) {
      _memoryGroups[group.id] = group;
    } else {
      final db = _db!;
      await db
          .into(db.shelfGroups)
          .insert(
            ShelfGroupsCompanion.insert(
              id: group.id,
              name: group.name,
              createdAt: now.millisecondsSinceEpoch,
            ),
          );
    }
    _notify();
    return group;
  }

  /// 重命名分组。
  Future<void> renameGroup(String id, String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const LibraryImportException('分组名称不能为空');
    }
    final groups = await listGroups();
    if (groups.any((group) => group.id != id && group.name == normalized)) {
      throw const LibraryImportException('分组名称已存在');
    }
    ShelfGroup? existing;
    for (final group in groups) {
      if (group.id == id) {
        existing = group;
        break;
      }
    }
    if (existing == null) {
      throw const LibraryImportException('分组不存在');
    }
    if (_isMemory) {
      _memoryGroups[id] = ShelfGroup(
        id: id,
        name: normalized,
        createdAt: existing.createdAt,
      );
    } else {
      final db = _db!;
      await (db.update(db.shelfGroups)..where((table) => table.id.equals(id)))
          .write(ShelfGroupsCompanion(name: Value<String>(normalized)));
    }
    _notify();
  }

  /// 删除分组；书籍本身保留，归属关系一并移除。
  Future<void> deleteGroup(String id) async {
    if (_isMemory) {
      _memoryGroups.remove(id);
      _memoryBookGroups.removeWhere((_, groupId) => groupId == id);
    } else {
      final db = _db!;
      await (db.delete(
        db.shelfGroups,
      )..where((table) => table.id.equals(id))).go();
    }
    _notify();
  }

  /// 将书籍移入分组；[groupId] 为 null 时移出分组。
  Future<void> setBooksGroup(
    Iterable<String> bookIds, {
    String? groupId,
  }) async {
    final ids = bookIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    if (groupId != null) {
      final exists = (await listGroups()).any((group) => group.id == groupId);
      if (!exists) {
        throw const LibraryImportException('分组不存在');
      }
    }
    if (_isMemory) {
      if (groupId == null) {
        for (final id in ids) {
          _memoryBookGroups.remove(id);
        }
      } else {
        for (final id in ids) {
          _memoryBookGroups[id] = groupId;
        }
      }
    } else {
      final db = _db!;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.transaction(() async {
        if (groupId == null) {
          await (db.delete(
            db.shelfGroupBooks,
          )..where((table) => table.bookUuid.isIn(ids))).go();
        } else {
          await db.batch((batch) {
            batch.insertAllOnConflictUpdate(
              db.shelfGroupBooks,
              <ShelfGroupBooksCompanion>[
                for (final id in ids)
                  ShelfGroupBooksCompanion.insert(
                    bookUuid: id,
                    groupId: groupId,
                    createdAt: now,
                  ),
              ],
            );
          });
        }
      });
    }
    _notify();
  }

  /// 全部标签，按创建时间升序。
  Future<List<BookTag>> listTags() async {
    if (_isMemory) {
      final tags = _memoryTags.values.toList()
        ..sort((a, b) {
          final compared = a.createdAt.compareTo(b.createdAt);
          return compared == 0 ? a.id.compareTo(b.id) : compared;
        });
      return tags;
    }
    final db = _db!;
    final rows =
        await (db.select(db.bookTags)..orderBy([
              (table) => OrderingTerm(expression: table.createdAt),
              (table) => OrderingTerm(expression: table.id),
            ]))
            .get();
    return <BookTag>[
      for (final row in rows)
        BookTag(
          id: row.id,
          name: row.name,
          createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
        ),
    ];
  }

  /// 某本书已打的标签。
  Future<List<BookTag>> bookTags(String bookId) async {
    if (_isMemory) {
      final ids = _memoryBookTags[bookId] ?? const <String>{};
      return <BookTag>[
        for (final tag in await listTags())
          if (ids.contains(tag.id)) tag,
      ];
    }
    final db = _db!;
    final links = await (db.select(
      db.bookTagLinks,
    )..where((table) => table.bookUuid.equals(bookId))).get();
    final ids = <String>{for (final link in links) link.tagId};
    return <BookTag>[
      for (final tag in await listTags())
        if (ids.contains(tag.id)) tag,
    ];
  }

  /// 新建标签；名称去首尾空白，同名标签直接复用。
  Future<BookTag> createTag(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const LibraryImportException('标签名称不能为空');
    }
    for (final tag in await listTags()) {
      if (tag.name == normalized) {
        return tag;
      }
    }
    final now = DateTime.now();
    final tag = BookTag(
      id:
          'tag-${now.microsecondsSinceEpoch}-'
          '${math.Random().nextInt(0x7fffffff)}',
      name: normalized,
      createdAt: now,
    );
    if (_isMemory) {
      _memoryTags[tag.id] = tag;
    } else {
      final db = _db!;
      await db
          .into(db.bookTags)
          .insert(
            BookTagsCompanion.insert(
              id: tag.id,
              name: tag.name,
              createdAt: now.millisecondsSinceEpoch,
            ),
          );
    }
    _notify();
    return tag;
  }

  /// 给书籍添加标签；重复添加保持幂等。
  Future<void> addBookTag(String bookId, String tagId) async {
    if (!(await listTags()).any((tag) => tag.id == tagId)) {
      throw const LibraryImportException('标签不存在');
    }
    if (!await _bookExists(bookId)) {
      throw const LibraryImportException('书籍不存在');
    }
    if (_isMemory) {
      _memoryBookTags.putIfAbsent(bookId, () => <String>{}).add(tagId);
    } else {
      final db = _db!;
      await db
          .into(db.bookTagLinks)
          .insertOnConflictUpdate(
            BookTagLinksCompanion.insert(
              bookUuid: bookId,
              tagId: tagId,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    }
    _notify();
  }

  /// 移除书籍标签；不存在时保持幂等。
  Future<void> removeBookTag(String bookId, String tagId) async {
    if (_isMemory) {
      _memoryBookTags[bookId]?.remove(tagId);
    } else {
      final db = _db!;
      await (db.delete(db.bookTagLinks)..where(
            (table) =>
                table.bookUuid.equals(bookId) & table.tagId.equals(tagId),
          ))
          .go();
    }
    _notify();
  }

  /// 某本书的书签存储（P4-13）；内存模式下没有书签能力时返回 null。
  DriftBookmarkStore? bookmarkStore(String bookId) {
    final db = _db;
    return db == null ? null : DriftBookmarkStore(db, bookId);
  }

  /// 书 uuid → 数据库内部 id（搜索按内部 id 查索引）。
  Future<int?> internalBookId(String uuid) => _bookIdOfUuid(uuid);

  Future<int?> _bookIdOfUuid(String uuid) async {
    final db = _db;
    if (db == null) {
      return null;
    }
    final rows = await (db.select(
      db.books,
    )..where((table) => table.uuid.equals(uuid))).get();
    return rows.isEmpty ? null : rows.single.id;
  }

  /// 某本书的标注存储（P4-17）；内存模式下没有标注能力时返回 null。
  DriftAnnotationStore? annotationStore(String bookId) {
    final db = _db;
    return db == null ? null : DriftAnnotationStore(db, bookId);
  }

  /// 全库书评存储；内存模式下没有持久化能力时返回 null。
  BookReviewStore? reviewStore() {
    final db = _db;
    return db == null ? null : DriftBookReviewStore(db);
  }

  /// 全库阅读会话存储；内存模式下没有持久化能力时返回 null。
  ReadingSessionStore? readingSessionStore() {
    final db = _db;
    return db == null ? null : DriftReadingSessionStore(db);
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
        await (db.select(db.books)
              ..where((table) => table.deletedAt.isNull())
              ..orderBy([
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
    return <BookEntry>[for (final row in rows) _entryFromRow(row)];
  }

  /// 按 uuid 读取当前书籍；不存在或已从书架移除时返回 null。
  Future<BookEntry?> bookById(String id) async {
    if (_isMemory) {
      return _memoryEntries[id];
    }
    final row = await _bookRowOfUuid(id);
    return row == null || row.deletedAt != null ? null : _entryFromRow(row);
  }

  /// 保存用户编辑的书名、作者和简介。
  Future<BookEntry> updateBookMetadata(
    String id, {
    required String title,
    required String author,
    required String description,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw const LibraryImportException('书名不能为空');
    }
    final normalizedAuthor = author.trim();
    final normalizedDescription = description.trim();
    if (_isMemory) {
      final entry = _memoryEntries[id];
      if (entry == null) {
        throw const LibraryImportException('书籍不存在');
      }
      final updated = entry.copyWith(
        title: normalizedTitle,
        author: normalizedAuthor,
        description: normalizedDescription,
      );
      _memoryEntries[id] = updated;
      _notify();
      return updated;
    }
    final row = await _bookRowOfUuid(id);
    if (row == null || row.deletedAt != null) {
      throw const LibraryImportException('书籍不存在');
    }
    final db = _db!;
    await (db.update(
      db.books,
    )..where((table) => table.id.equals(row.id))).write(
      BooksCompanion(
        title: Value<String>(normalizedTitle),
        author: Value<String?>(
          normalizedAuthor.isEmpty ? null : normalizedAuthor,
        ),
        description: Value<String?>(
          normalizedDescription.isEmpty ? null : normalizedDescription,
        ),
      ),
    );
    _notify();
    return _entryFromRow((await _bookRowOfUuid(id))!);
  }

  /// 替换封面：写入书目录并删除旧封面文件。
  Future<BookEntry> replaceCover(
    String id,
    Uint8List bytes, {
    required String extension,
  }) async {
    if (bytes.isEmpty) {
      throw const LibraryImportException('封面图片为空');
    }
    if (_isMemory) {
      throw const LibraryImportException('当前模式无法保存封面');
    }
    final row = await _bookRowOfUuid(id);
    if (row == null || row.deletedAt != null) {
      throw const LibraryImportException('书籍不存在');
    }
    final normalized = extension.toLowerCase().replaceFirst('.', '');
    if (!const <String>{'jpg', 'jpeg', 'png', 'webp'}.contains(normalized)) {
      throw const LibraryImportException('仅支持 JPG、PNG 或 WebP 图片');
    }
    final suffix = normalized == 'jpeg' ? 'jpg' : normalized;
    final directory = await _bookDirectory(id);
    final coverFile = File(
      '${directory.path}/cover-${DateTime.now().microsecondsSinceEpoch}.$suffix',
    );
    await coverFile.writeAsBytes(bytes, flush: true);
    final db = _db!;
    try {
      await (db.update(db.books)..where((table) => table.id.equals(row.id)))
          .write(BooksCompanion(coverPath: Value<String>(coverFile.path)));
    } catch (_) {
      try {
        await coverFile.delete();
      } catch (_) {
        // 数据库写入失败时尽量回滚新文件，失败则留给启动扫描清理。
      }
      rethrow;
    }
    final oldPath = row.coverPath;
    if (oldPath != null && oldPath != coverFile.path) {
      final normalizedOld = p.normalize(oldPath);
      if (p.isWithin(directory.path, normalizedOld)) {
        final oldFile = File(oldPath);
        if (await oldFile.exists()) {
          try {
            await oldFile.delete();
          } catch (_) {
            // 旧封面占用或权限失败时保留，不影响新封面生效。
          }
        }
      }
    }
    _notify();
    return _entryFromRow((await _bookRowOfUuid(id))!);
  }

  /// 导入 EPUB 字节：解析校验 → 落盘原书 → 提取并缓存封面 → 入库。
  ///
  /// [onProgress] 上报阶段进度 0～1（解析 → 落盘 → 封面 → 入库）。
  Future<BookEntry> importBytes(
    Uint8List bytes, {
    String? fallbackTitle,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) {
    final db = _db;
    final queue = db == null ? _importQueue : _databaseImportQueues[db];
    Future<BookEntry> import() => _importBytes(
      bytes,
      fallbackTitle: fallbackTitle,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    final result = queue == null ? import() : queue.then((_) => import());
    _importQueue = result.then<void>((_) {}, onError: (Object _) {});
    if (db != null) _databaseImportQueues[db] = _importQueue;
    return result;
  }

  // 新书导入沿用既有串行主流程，文件和数据库提交共用完成标记。
  // 此协调方法保留较长结构，避免拆散软删除恢复的外键与失败清理边界。
  Future<BookEntry> _importBytes(
    Uint8List bytes, {
    String? fallbackTitle,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    _checkImportCancelled(isCancelled);
    try {
      await migrateBookIds();
    } on FormatException {
      // 单本旧书损坏或冲突保留待恢复，不阻止无关新书导入。
    }
    onProgress?.call(0.1);
    final result = await openEpub(bytes);
    final document = result.document;
    if (document == null) {
      final detail = result.report.message ?? result.report.errorCode ?? '未知错误';
      throw LibraryImportException(
        '无法导入：$detail',
        errorCode: result.report.errorCode,
      );
    }
    onProgress?.call(0.45);
    final meta = document.meta;
    final identifier = originalEpubIdentifier(document);
    final id = generateBookId(
      title: meta.title,
      author: meta.author,
      identifier: identifier,
    );
    final existing = _isMemory ? null : await _bookRowOfUuid(id);
    if (existing != null && existing.identityVersion != 1) {
      throw const LibraryImportException(
        '书籍标识与待迁移旧记录冲突，已保留原数据',
        errorCode: 'E_IDENTITY_CONFLICT',
      );
    }
    if (!_isMemory && existing != null && existing.deletedAt == null) {
      return _replaceRevision(
        existing,
        bytes,
        result,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    }
    if (_isMemory && _memoryEntries.containsKey(id)) {
      final same = listEquals(_memoryBytes[id], bytes);
      _checkImportCancelled(isCancelled);
      _memoryBytes[id] = bytes;
      final current = _memoryEntries[id]!;
      final entry = _withImportOutcome(
        current,
        same ? BookImportOutcome.unchanged : BookImportOutcome.updated,
      );
      _memoryEntries[id] = entry;
      _notify();
      return entry;
    }
    final title = document.meta.title.trim().isEmpty
        ? (fallbackTitle?.trim().isEmpty ?? true ? '未命名书籍' : fallbackTitle!)
        : document.meta.title.trim();
    _checkImportCancelled(isCancelled);
    // 整本哈希只算一次，暂存目录名与 contentRevision 共用。
    final sourceRevision = _isMemory ? '' : sha256.convert(bytes).toString();
    String filePath = '';
    String? coverPath;
    Directory? stagedDirectory;
    var committed = false;
    try {
      if (!_isMemory) {
        final directory = await _bookDirectory(id);
        final revisionDirectory = Directory(
          p.join(
            directory.path,
            'versions',
            '$sourceRevision-${DateTime.now().microsecondsSinceEpoch}',
          ),
        );
        stagedDirectory = revisionDirectory;
        await revisionDirectory.create(recursive: true);
        final file = File(p.join(revisionDirectory.path, 'source.epub'));
        await file.writeAsBytes(bytes, flush: true);
        filePath = file.path;
        onProgress?.call(0.7);
        final coverBytes = document.readCoverBytes();
        if (coverBytes != null && coverBytes.isNotEmpty) {
          final extension = _coverExtension(document.coverResourcePath);
          final coverFile = File('${revisionDirectory.path}/cover.$extension');
          await coverFile.writeAsBytes(coverBytes, flush: true);
          coverPath = coverFile.path;
        }
      }
      onProgress?.call(0.85);
      // §22.3/§76.1：导入期顺序统计各章正文字符数，进度量化与后续搜索索引
      // 共用同一次扫描。
      final charCounts = await document.countChapterCharacters(
        onProgress: (done, total) =>
            onProgress?.call(0.85 + 0.1 * (total == 0 ? 1 : done / total)),
      );
      final weights = ProgressWeights.fromCharCounts(
        charCounts,
        excluded: document.progressExcludedSpineIndexes,
      );
      if (isCancelled?.call() == true) {
        if (!_isMemory && filePath.isNotEmpty) await File(filePath).delete();
        _checkImportCancelled(isCancelled);
      }
      final now = DateTime.now();
      final addedAt = existing == null
          ? now
          : DateTime.fromMillisecondsSinceEpoch(existing.createdAt);
      final entry = BookEntry(
        id: id,
        title: title,
        author: document.meta.author.trim(),
        description: existing?.description ?? '',
        filePath: filePath,
        addedAt: addedAt,
        spineCount: document.spine.length,
        readabilityLevel: result.report.readabilityLevel,
        coverPath: coverPath,
      );
      if (_isMemory) {
        _memoryBytes[id] = bytes;
        _memoryEntries[id] = entry;
      } else {
        final db = _db!;
        final companion = BooksCompanion.insert(
          uuid: id,
          epubIdentifier: Value(identifier),
          identityVersion: const Value(1),
          contentRevision: Value(sourceRevision),
          legacyUuid: Value(existing?.legacyUuid ?? existing?.uuid),
          title: title,
          author: Value(
            document.meta.author.trim().isEmpty
                ? null
                : document.meta.author.trim(),
          ),
          description: Value(existing?.description),
          language: Value(
            document.meta.language.trim().isEmpty
                ? null
                : document.meta.language.trim(),
          ),
          // 尚未解包：书目录即资源目录。
          contentDir: 'books-v1/$id',
          sourcePath: Value(filePath),
          coverPath: Value(coverPath),
          spineCount: Value(document.spine.length),
          charCount: Value(weights.totalCharacters),
          createdAt: addedAt.millisecondsSinceEpoch,
          level: Value(result.report.readabilityLevel),
          warnings: Value(
            result.report.warnings.isEmpty
                ? null
                : jsonEncode(result.report.warnings),
          ),
          deletedAt: const Value<int?>(null),
        );
        await db.transaction(() async {
          _checkImportCancelled(isCancelled);
          final int bookId;
          if (existing == null) {
            bookId = await db.into(db.books).insert(companion);
          } else {
            // 软删除记录的原主键不变；用户数据通过外键继续挂在同一本书上。
            bookId = existing.id;
            await (db.update(
              db.books,
            )..where((table) => table.id.equals(bookId))).write(companion);
            await (db.delete(
              db.spineItems,
            )..where((table) => table.bookId.equals(bookId))).go();
            await (db.delete(
              db.chapters,
            )..where((table) => table.bookId.equals(bookId))).go();
            await (db.delete(
              db.importReports,
            )..where((table) => table.bookId.equals(bookId))).go();
          }
          // P4-06：把修复与告警按诊断码拆行落库，详情页可逐条展示。
          await _writeImportReports(bookId, result.report);
          // P4-09：spine 行落地（字符数与章前累计），供进度量化使用。
          await _writeSpineItems(bookId, document, charCounts, weights);
          _checkImportCancelled(isCancelled);
        });
      }
      committed = true;
      onProgress?.call(1);
      _notify();
      return entry;
    } finally {
      if (!committed &&
          stagedDirectory != null &&
          await stagedDirectory.exists()) {
        await stagedDirectory.delete(recursive: true);
      }
    }
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
          .write(BooksCompanion(lastReadAt: Value(now.millisecondsSinceEpoch)));
    }
    _notify();
  }

  /// 从书架移除书籍：保留用户数据，只清理书籍文件并标记为已删除。
  ///
  /// 重新导入同一 OPF identifier 时复用原书主键，进度、标注、书评和阅读
  /// 会话随之恢复。
  Future<void> remove(String id) async {
    if (_isMemory) {
      _memoryBytes.remove(id);
      _memoryEntries.remove(id);
      _notify();
      return;
    }
    // 软删除保留子表；文件删除失败留孤儿，启动扫描可清理。
    final db = _db!;
    final root = await _root();
    final directory = _safeBookDirectory(root, id, canonical: true);
    final rows = await (db.select(
      db.books,
    )..where((table) => table.uuid.equals(id))).get();
    final directories = <Directory>[
      ?directory,
      for (final row in rows)
        if (row.identityVersion == 0) ?_safeBookDirectory(root, row.uuid),
      for (final row in rows)
        if (row.legacyUuid != null) ?_safeBookDirectory(root, row.legacyUuid!),
    ];
    final otherBooks =
        await (db.select(db.books)..where(
              (table) => table.uuid.isNotValue(id) & table.deletedAt.isNull(),
            ))
            .get();
    directories.removeWhere(
      (item) => otherBooks.any(
        (book) => [
          book.sourcePath,
          book.coverPath,
        ].nonNulls.any((path) => p.isWithin(item.path, p.normalize(path))),
      ),
    );
    final sourcePaths = <String>[
      for (final row in rows)
        if (row.sourcePath != null) row.sourcePath!,
    ];
    await (db.update(db.books)..where((table) => table.uuid.equals(id))).write(
      BooksCompanion(
        deletedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
        sourcePath: const Value<String?>(null),
        coverPath: const Value<String?>(null),
      ),
    );
    for (final path in sourcePaths) {
      if (otherBooks.any((book) => book.sourcePath == path)) continue;
      // 旧库异常路径只能清理记录，不能扩大文件删除范围。
      final normalized = p.normalize(path);
      final legacyDirectory = p.normalize(p.join(root.path, 'books'));
      final owned = directories.any(
        (item) => p.isWithin(item.path, normalized),
      );
      final legacy =
          p.dirname(normalized) == legacyDirectory &&
          p.extension(normalized).toLowerCase() == '.epub';
      if (directory == null || (!owned && !legacy)) {
        continue;
      }
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
    for (final item in directories) {
      if (await item.exists()) {
        try {
          await item.delete(recursive: true);
        } catch (_) {
          // 权限/占用失败：下次启动扫描清理。
        }
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
  Future<({int removed, int bytes})> sweepOrphans() {
    final db = _db;
    final previous = db == null ? _importQueue : _databaseImportQueues[db];
    final result = previous == null
        ? _sweepOrphans()
        : previous.then((_) => _sweepOrphans());
    _importQueue = result.then<void>((_) {}, onError: (Object _) {});
    if (db != null) _databaseImportQueues[db] = _importQueue;
    return result;
  }

  Future<({int removed, int bytes})> _sweepOrphans() async {
    if (_isMemory) {
      return (removed: 0, bytes: 0);
    }
    final db = _db!;
    final root = await _root();
    final rows = await (db.select(
      db.books,
    )..where((table) => table.deletedAt.isNull())).get();
    final knownIds = <String>{
      for (final row in rows) row.uuid,
      for (final row in rows)
        if (row.legacyUuid != null) row.legacyUuid!,
    };
    final knownFiles = <String>{
      for (final row in rows)
        if (row.sourcePath != null) p.normalize(row.sourcePath!),
      for (final row in rows)
        if (row.coverPath != null) p.normalize(row.coverPath!),
    };
    final legacy = await _sweepBookDirectory(
      Directory('${root.path}/books'),
      knownIds,
      knownFiles,
    );
    final canonical = await _sweepBookDirectory(
      Directory('${root.path}/books-v1'),
      {for (final row in rows) row.uuid},
      knownFiles,
    );
    return (
      removed: legacy.removed + canonical.removed,
      bytes: legacy.bytes + canonical.bytes,
    );
  }

  Future<({int removed, int bytes})> _sweepBookDirectory(
    Directory booksDirectory,
    Set<String> knownIds,
    Set<String> knownFiles,
  ) async {
    if (!await booksDirectory.exists()) return (removed: 0, bytes: 0);
    var removed = 0;
    var bytes = 0;
    await for (final entity in booksDirectory.list(followLinks: false)) {
      if (entity is Directory) {
        // 新格式：books/<uuid>/；未知 uuid 即孤儿目录。
        if (knownIds.contains(p.basename(entity.path)) ||
            knownFiles.any((path) => p.isWithin(entity.path, path))) {
          final retired = await _sweepRetiredVersions(entity, knownFiles);
          removed += retired.removed;
          bytes += retired.bytes;
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
        if (knownFiles.contains(p.normalize(entity.path))) {
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

  Future<({int removed, int bytes})> _sweepRetiredVersions(
    Directory book,
    Set<String> active,
  ) async {
    var removed = 0;
    var bytes = 0;
    final versions = Directory(p.join(book.path, 'versions'));
    if (await versions.exists()) {
      await for (final child in versions.list(followLinks: false)) {
        if (child is! Directory ||
            active.any((path) => p.isWithin(child.path, path))) {
          continue;
        }
        final size = await _sizeOf(child);
        try {
          await child.delete(recursive: true);
          removed++;
          bytes += size;
        } on FileSystemException {
          // 未提交版本或已退休版本留待下次启动处理。
        }
      }
    }
    final source = File(p.join(book.path, 'source.epub'));
    if (!active.contains(p.normalize(source.path)) && await source.exists()) {
      try {
        final size = await source.length();
        await source.delete();
        removed++;
        bytes += size;
      } on FileSystemException {
        // 不影响数据库引用的当前有效版本。
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
    final rows =
        await (db.select(db.books)..where(
              (table) => table.deletedAt.isNull() & table.coverPath.isNull(),
            ))
            .get();
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
        final directory = await _bookDirectory(row.uuid);
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
    final rows = await (db.select(
      db.books,
    )..where((table) => table.deletedAt.isNull())).get();
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
      throw const FormatException('旧书库数据必须是对象');
    }
    final entries = decoded['books'];
    if (entries is! List) {
      throw const FormatException('旧书库缺少书籍列表');
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
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              uuid: entry.id,
              title: entry.title,
              author: Value(entry.author.isEmpty ? null : entry.author),
              description: Value(
                entry.description.isEmpty ? null : entry.description,
              ),
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

  Future<BookRow?> _bookRowOfUuid(String id) async {
    final db = _db!;
    final rows = await (db.select(
      db.books,
    )..where((table) => table.uuid.equals(id))).get();
    return rows.isEmpty ? null : rows.single;
  }

  BookEntry _entryFromRow(BookRow row) => BookEntry(
    id: row.uuid,
    title: row.title,
    author: row.author ?? '',
    description: row.description ?? '',
    filePath: row.sourcePath ?? '',
    addedAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    lastReadAt: row.lastReadAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.lastReadAt!),
    spineCount: row.spineCount,
    readabilityLevel: row.level,
    coverPath: row.coverPath,
    contentRevision: row.contentRevision,
  );

  Future<bool> _bookExists(String id) async {
    if (_isMemory) {
      return _memoryEntries.containsKey(id);
    }
    final row = await _bookRowOfUuid(id);
    return row != null && row.deletedAt == null;
  }
}
