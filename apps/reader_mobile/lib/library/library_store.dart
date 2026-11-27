import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/epub/book_identity.dart';
import 'package:reader_core/epub/chapter/book_progress.dart'
    show bookProgressIndexFor;
import 'package:reader_core/epub/epub_exception.dart';
import 'package:reader_core/position/locator.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/opf.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/perf/trace.dart';
import 'package:reader_core/txt.dart';
import 'package:reader_core/position/revision_relocator.dart';
import 'package:reader_ui/annotations/annotation.dart'
    show ReaderAnnotationType;
import 'package:reader_ui/decorations/decoration_image_store.dart';

import '../reader/reader_decoration_image_store.dart';
import '../storage/book_review_store.dart';
import 'book_list_store.dart';
import '../storage/db.dart';
import '../storage/drift_annotation_store.dart';
import '../storage/drift_decoration_store.dart';
import '../storage/drift_decoration_rule_store.dart';
import '../storage/drift_bookmark_store.dart';
import '../storage/reading_session_store.dart';
import 'import_analysis.dart';
import 'book_edit_models.dart';
import 'revision_anchor_index.dart';
import 'revision_anchor_store.dart' show requireAnchorRecord, resolveBookRow;
import '../sync/sync_assets.dart';
import '../sync/sync_layout.dart';
import '../sync/sync_models.dart';
import '../sync/sync_repository.dart';
import '../sync/sync_state.dart';

part 'library_revision.dart';
part 'library_editing.dart';
part 'library_metadata.dart';
part 'library_edit_drafts.dart';
part 'library_sweep_paths.dart';
part 'library_txt.dart';
part 'library_sync.dart';
part 'library_sync_snapshot.dart';
part 'library_sync_apply.dart';

/// 导入成功的实际结果，覆盖更新不会新建用户数据。
enum BookImportOutcome { added, updated, unchanged }

const txtChapterRulesSettingKey = 'txt.chapterRules.v1';

typedef BookNoteCounts = ({int thoughts, int marks, DateTime updatedAt});

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

  /// 初次导入的三元组摘要（`books.uuid`）；本地编辑时身份保持稳定。
  final String id;

  /// 书名（OPF dc:title；缺失时用文件名）。
  final String title;

  /// 作者（OPF dc:creator；缺失为空串）。
  final String author;

  /// 用户可编辑的简介。
  final String description;

  /// EPUB 文件绝对路径（新书为 `books/<id>/source.epub`）。
  final String filePath;

  /// 导入时间。
  final DateTime addedAt;

  /// 最近阅读时间。
  final DateTime? lastReadAt;

  /// 章节数（打开结果携带，书架展示用）。
  final int? spineCount;

  /// 可读性分级（P3-26，0~4）。
  final int readabilityLevel;

  /// 封面缓存文件路径（§37.3 三级提取成功后落盘）；null 用占位。
  final String? coverPath;

  /// 原书 SHA-256，导入时计算并与条目一起保存。
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

  BookEntry copyWith({
    DateTime? lastReadAt,
    String? title,
    String? author,
    String? description,
    String? contentRevision,
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
    contentRevision: contentRevision ?? this.contentRevision,
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

/// 书库存储（P4-04）：drift `books` 表 + `books/<id>/` 目录
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
  final Map<String, Map<int, String>> _memoryChapterTitles =
      <String, Map<int, String>>{};
  final Map<String, String> _memorySettings = <String, String>{};
  final Map<String, ReaderFontEntry> _memoryFonts = <String, ReaderFontEntry>{};
  final Map<String, ShelfGroup> _memoryGroups = <String, ShelfGroup>{};
  final Map<String, String> _memoryBookGroups = <String, String>{};
  final Map<String, BookTag> _memoryTags = <String, BookTag>{};
  final Map<String, Set<String>> _memoryBookTags = <String, Set<String>>{};
  final List<void Function()> _listeners = <void Function()>[];
  Future<void>? _importQueue;
  int _syncReaders = 0;
  bool _syncTransaction = false;
  Future<void> Function(String)? _syncRestoreBook;
  void Function()? _syncSettingChanged;
  static final _databaseImportQueues = Expando<Future<void>>();

  bool get _isMemory => _db == null;

  /// 是否连接了可持久化的数据库；临时模式不得执行磁盘清理。
  bool get supportsPersistence => _db != null;

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    final db = _db;
    final previous = db == null ? _importQueue : _databaseImportQueues[db];
    // 先登记队列，再执行首个操作，进度回调中的新请求也会正确排队。
    final result = (previous ?? Future<void>.value()).then((_) => operation());
    _importQueue = result.then<void>((_) {}, onError: (Object _) {});
    if (db != null) _databaseImportQueues[db] = _importQueue;
    return result;
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
    final directory = _safeBookDirectory(root, id);
    if (directory == null) {
      throw const LibraryImportException('书籍标识无效，无法创建存储目录');
    }
    await directory.create(recursive: true);
    return directory;
  }

  Directory? _safeBookDirectory(Directory root, String id) {
    if (id == '.' ||
        id == '..' ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(id)) {
      return null;
    }
    final booksPath = p.normalize(p.join(root.path, 'books'));
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
    if (!key.startsWith('sync.')) _syncSettingChanged?.call();
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
        await (db.update(
          db.userFonts,
        )..where((table) => table.family.equals(font.family))).write(
          UserFontsCompanion(
            filePath: Value(font.filePath),
            displayName: Value(font.displayName),
          ),
        );
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

  /// 删除字体清单项，文件生命周期由字体存储负责。
  Future<void> removeUserFont(String family) async {
    if (_isMemory) {
      _memoryFonts.remove(family);
      return;
    }
    final db = _db!;
    await (db.delete(
      db.userFonts,
    )..where((table) => table.family.equals(family))).go();
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

  /// 书籍 uuid → 自定义分组 id；没有归属记录的书属于默认分组。
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

  /// 删除分组；移除归属关系，书籍回到默认分组，阅读记录保留。
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

  /// 将书籍移入唯一的目标分组；[groupId] 为 null 时移回默认分组。
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
    if (_isMemory) {
      for (final tag in _memoryTags.values) {
        if (tag.name == normalized) return tag;
      }
      final tag = _newTag(normalized);
      _memoryTags[tag.id] = tag;
      _notify();
      return tag;
    }
    return _createStoredTag(_newTag(normalized));
  }

  BookTag _newTag(String name) {
    final now = DateTime.now();
    return BookTag(
      id:
          'tag-${now.microsecondsSinceEpoch}-'
          '${math.Random().nextInt(0x7fffffff)}',
      name: name,
      createdAt: now,
    );
  }

  Future<BookTag> _createStoredTag(BookTag candidate) async {
    final db = _db!;
    await db
        .into(db.bookTags)
        .insert(
          BookTagsCompanion.insert(
            id: candidate.id,
            name: candidate.name,
            createdAt: candidate.createdAt.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final row = await (db.select(
      db.bookTags,
    )..where((table) => table.name.equals(candidate.name))).getSingle();
    if (row.id == candidate.id) _notify();
    return BookTag(
      id: row.id,
      name: row.name,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    );
  }

  /// 给书籍添加标签；重复添加保持幂等。
  Future<void> addBookTag(String bookId, String tagId) =>
      _enqueueOperation(() => _changeBookTag(bookId, tagId, selected: true));

  /// 移除书籍标签，并从 EPUB 的主题元数据移除；不存在时保持幂等。
  Future<void> removeBookTag(String bookId, String tagId) =>
      _enqueueOperation(() => _changeBookTag(bookId, tagId, selected: false));

  Future<void> _changeBookTag(
    String bookId,
    String tagId, {
    required bool selected,
  }) async {
    final tags = await bookTags(bookId);
    if (tags.any((tag) => tag.id == tagId) == selected) return;
    final available = await listTags();
    if (!available.any((tag) => tag.id == tagId)) {
      throw const LibraryImportException('标签不存在');
    }
    if (!await _bookExists(bookId)) {
      throw const LibraryImportException('书籍不存在');
    }
    if (_isMemory) {
      final ids = _memoryBookTags.putIfAbsent(bookId, () => <String>{});
      selected ? ids.add(tagId) : ids.remove(tagId);
      _notify();
    } else {
      final next = selected
          ? [...tags, available.firstWhere((tag) => tag.id == tagId)]
          : tags.where((tag) => tag.id != tagId).toList();
      await _writeBookMetadata(await _editableBook(bookId), tags: next);
    }
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

  Future<Map<String, BookNoteCounts>> bookNoteCounts() async {
    final db = _db;
    if (db == null) return {};
    final notes = db.annotations;
    final books = db.books;
    final thought = notes.type.equals(
      ReaderAnnotationType.thought.storageValue,
    );
    final mark = notes.type.equals(ReaderAnnotationType.mark.storageValue);
    final thoughts = notes.id.count(filter: thought);
    final marks = notes.id.count(filter: mark);
    final updatedAt = notes.updatedAt.max();
    final query = db.selectOnly(notes)
      ..join([
        innerJoin(books, books.id.equalsExp(notes.bookId), useColumns: false),
      ])
      ..addColumns([books.uuid, thoughts, marks, updatedAt])
      ..where(thought | mark)
      ..groupBy([books.uuid]);
    return {
      for (final row in await query.get())
        row.read(books.uuid)!: (
          thoughts: row.read(thoughts)!,
          marks: row.read(marks)!,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(row.read(updatedAt)!),
        ),
    };
  }

  Future<Map<String, Duration>> bookReadingDurations() async {
    final db = _db;
    if (db == null) return {};
    final sessions = db.readingSessions;
    final books = db.books;
    final total = sessions.durationMs.sum();
    final query = db.selectOnly(sessions)
      ..join([
        innerJoin(
          books,
          books.id.equalsExp(sessions.bookId),
          useColumns: false,
        ),
      ])
      ..addColumns([books.uuid, total])
      ..where(
        sessions.endedAt.isBiggerThan(sessions.startedAt) &
            sessions.durationMs.isBiggerThanValue(0),
      )
      ..groupBy([books.uuid]);
    return {
      for (final row in await query.get())
        row.read(books.uuid)!: Duration(milliseconds: row.read(total)!),
    };
  }

  /// 当前书的手工装饰存储；彻底删除或更换图片时检查全库引用。
  DriftDecorationStore? decorationStore(
    String bookId, {
    ReaderDecorationImageStore? images,
  }) {
    final db = _db;
    return db == null
        ? null
        : DriftDecorationStore(
            db,
            bookId,
            images: images ?? ReaderDecorationImages(),
          );
  }

  /// 当前书与全局的自动装饰规则。
  DriftDecorationRuleStore? decorationRuleStore(
    String bookId, {
    ReaderDecorationImageStore? images,
  }) {
    final db = _db;
    return db == null
        ? null
        : DriftDecorationRuleStore(
            db,
            bookId,
            images: images ?? ReaderDecorationImages(),
          );
  }

  /// 全库书评存储；内存模式下没有持久化能力时返回 null。
  BookReviewStore? reviewStore() {
    final db = _db;
    return db == null ? null : DriftBookReviewStore(db);
  }

  /// 书单存储；序列化到 settings 表，内存模式同样可用。
  BookListStore bookListStore() => BookListStore(this);

  Future<Set<String>> finishedBookIds() async {
    final db = _db;
    if (db == null) return const {};
    final query =
        db.selectOnly(db.books).join([
            innerJoin(
              db.readingProgress,
              db.readingProgress.bookId.equalsExp(db.books.id),
            ),
          ])
          ..addColumns([db.books.uuid])
          ..where(
            db.books.deletedAt.isNull() &
                db.readingProgress.finished.equals(true),
          );
    return {for (final row in await query.get()) row.read(db.books.uuid)!};
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

  /// 已从书架移除但仍保留笔记、书评、书单归属的书籍。
  ///
  /// 书籍按软删除处理，行内仍保留书名、作者等元数据；这里只返回已移除的
  /// 条目，供笔记、书评和书单继续展示，不进入书架列表。
  Future<List<BookEntry>> retainedBooks() async {
    if (_isMemory) return const <BookEntry>[];
    final db = _db!;
    final rows =
        await (db.select(db.books)
              ..where((table) => table.deletedAt.isNotNull())
              ..orderBy([
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

  /// 书名、作者和简介先写入 EPUB，再与书库资料一起提交。
  Future<BookEntry> updateBookMetadata(
    String id, {
    required String title,
    required String author,
    required String description,
  }) => _enqueueOperation(() async {
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
    return _writeBookMetadata(
      await _editableBook(id),
      metadata: (
        title: normalizedTitle,
        author: normalizedAuthor,
        description: normalizedDescription,
      ),
    );
  });

  /// 替换 EPUB 封面资源与书架缓存，正文原有图片保持不变。
  Future<BookEntry> replaceCover(
    String id,
    Uint8List bytes, {
    required String extension,
  }) => _enqueueOperation(() async {
    if (bytes.isEmpty) {
      throw const LibraryImportException('封面图片为空');
    }
    if (_isMemory) {
      throw const LibraryImportException('当前模式无法保存封面');
    }
    final normalized = extension.toLowerCase().replaceFirst('.', '');
    if (!const <String>{'jpg', 'jpeg', 'png', 'webp'}.contains(normalized)) {
      throw const LibraryImportException('仅支持 JPG、PNG 或 WebP 图片');
    }
    final suffix = normalized == 'jpeg' ? 'jpg' : normalized;
    return _writeBookMetadata(
      await _editableBook(id),
      cover: (bytes: bytes, extension: suffix),
    );
  });

  /// 导入 EPUB 字节：解析校验 → 落盘原书 → 提取并缓存封面 → 入库。
  ///
  /// 书名仅取 EPUB 元数据；[fallbackTitle] 保留兼容调用，不用于书名。
  /// [onProgress] 上报阶段进度 0～1（解析 → 落盘 → 封面 → 入库）。
  Future<BookEntry> importBytes(
    Uint8List bytes, {
    String? fallbackTitle,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) => _enqueueOperation(
    () => _import(
      _ImportPayload.bytes(bytes),
      onProgress: onProgress,
      isCancelled: isCancelled,
    ),
  );

  /// 从文件导入 EPUB：哈希、解析与落盘全程流式，不把整本读入内存。
  ///
  /// 这是书架导入的默认入口；100MB+ 的书内存占用与文件体积无关。
  Future<BookEntry> importFile(
    String path, {
    String? fallbackTitle,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) {
    if (_isMemory) {
      return importBytes(
        File(path).readAsBytesSync(),
        fallbackTitle: fallbackTitle,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    }
    return _enqueueOperation(
      () => _import(
        _ImportPayload.file(path),
        onProgress: onProgress,
        isCancelled: isCancelled,
      ),
    );
  }

  // 新书导入沿用既有串行主流程，文件和数据库提交共用完成标记。
  // 此协调方法保留较长结构，避免拆散软删除恢复的外键与失败清理边界。
  Future<BookEntry> _import(
    _ImportPayload payload, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    _checkImportCancelled(isCancelled);
    onProgress?.call(0.1);
    // 哈希、CRC 校验、字数统计与封面提取都在后台 isolate 完成。
    final analysisTrace = readerTraceEnabled
        ? ReaderTrace.instance.start(ReaderTraceName.import)
        : null;
    BookEntry? unchangedEntry;
    final analysis = await payload.analyze(
      shouldSkip: (revision) async {
        final db = _db;
        if (db == null) return false;
        final rows =
            await (db.select(db.books)..where(
                  (table) =>
                      table.contentRevision.equals(revision) &
                      table.deletedAt.isNull(),
                ))
                .get();
        final row = rows.firstOrNull;
        if (row == null ||
            row.sourcePath == null ||
            !await File(row.sourcePath!).exists()) {
          return false;
        }
        unchangedEntry = _withImportOutcome(
          _entryFromRow(row),
          BookImportOutcome.unchanged,
        );
        return true;
      },
    );
    analysisTrace?.stop();
    _checkImportCancelled(isCancelled);
    if (analysis == null) {
      onProgress?.call(1);
      return unchangedEntry!;
    }
    final summary = analysis.summary;
    if (summary == null) {
      final report = analysis.report;
      final detail = report.message ?? report.errorCode ?? '未知错误';
      throw LibraryImportException('无法导入：$detail', errorCode: report.errorCode);
    }
    onProgress?.call(0.45);
    final report = analysis.report;
    final meta = summary.meta;
    final identifier = summary.identifier;
    final id = generateBookId(
      title: meta.title,
      author: meta.author,
      identifier: identifier,
    );
    final existing = _isMemory ? null : await _bookRowOfUuid(id);
    // 同版本缺失文件只补回原书，不能重写位置锚点与版式恢复提示。
    if (existing != null && existing.contentRevision != analysis.revision) {
      final updateBytes = await payload.readBytes(analysis.revision);
      _checkImportCancelled(isCancelled);
      final openTrace = readerTraceEnabled
          ? ReaderTrace.instance.start(ReaderTraceName.import)
          : null;
      final result = await openAnalyzed(updateBytes, analysis);
      openTrace?.stop();
      final document = result.document;
      if (document == null) {
        final detail =
            result.report.message ?? result.report.errorCode ?? '未知错误';
        throw LibraryImportException(
          '无法更新：$detail',
          errorCode: result.report.errorCode,
        );
      }
      try {
        return await _replaceRevision(
          existing,
          updateBytes,
          result,
          analysis: analysis,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
      } finally {
        document.archive.close();
      }
    }
    if (_isMemory && _memoryEntries.containsKey(id)) {
      final bytes = payload.bytes!;
      final same = listEquals(_memoryBytes[id], bytes);
      _checkImportCancelled(isCancelled);
      _memoryBytes[id] = bytes;
      final current = _memoryEntries[id]!;
      final entry = _withImportOutcome(
        current.copyWith(contentRevision: analysis.revision),
        same ? BookImportOutcome.unchanged : BookImportOutcome.updated,
      );
      _memoryEntries[id] = entry;
      _memoryChapterTitles[id] = _chapterTitlesFromToc(summary.toc);
      _notify();
      return entry;
    }
    final title =
        existing?.title ??
        (meta.title.trim().isEmpty
            ? '未命名书籍'
            : meta.title.trim());
    final author = existing == null
        ? meta.author.trim()
        : existing.author ?? '';
    _checkImportCancelled(isCancelled);
    // 整本哈希已在后台算好，暂存目录名与 contentRevision 共用。
    final sourceRevision = analysis.revision;
    String filePath = '';
    String? coverPath = existing?.coverPath;
    if (coverPath != null && !await File(coverPath).exists()) coverPath = null;
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
        await payload.writeTo(file);
        filePath = file.path;
        onProgress?.call(0.7);
        final coverBytes = summary.coverBytes;
        if (coverPath == null && coverBytes != null && coverBytes.isNotEmpty) {
          final coverFile = File(
            '${revisionDirectory.path}/cover.${summary.coverExtension}',
          );
          await coverFile.writeAsBytes(coverBytes, flush: true);
          coverPath = coverFile.path;
        }
      }
      onProgress?.call(0.85);
      // §22.3/§76.1：各章正文字符数已在后台 isolate 统计，进度量化与后续
      // 搜索索引共用同一次扫描。
      final charCounts = analysis.charCounts!;
      onProgress?.call(0.95);
      final weights = ProgressWeights.fromCharCounts(
        charCounts,
        excluded: summary.excludedSpineIndexes,
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
        author: author,
        description: existing?.description ?? '',
        filePath: filePath,
        addedAt: addedAt,
        spineCount: summary.spine.length,
        readabilityLevel: report.readabilityLevel,
        coverPath: coverPath,
        contentRevision: sourceRevision,
        importOutcome: existing != null && existing.deletedAt == null
            ? BookImportOutcome.updated
            : BookImportOutcome.added,
      );
      if (_isMemory) {
        _memoryBytes[id] = payload.bytes!;
        _memoryEntries[id] = entry;
        _memoryChapterTitles[id] = _chapterTitlesFromToc(summary.toc);
      } else {
        final db = _db!;
        final companion = BooksCompanion.insert(
          uuid: id,
          epubIdentifier: Value(identifier),
          contentRevision: sourceRevision,
          title: title,
          author: Value(author.isEmpty ? null : author),
          description: Value(existing?.description),
          language: Value(
            meta.language.trim().isEmpty ? null : meta.language.trim(),
          ),
          // 尚未解包：书目录即资源目录。
          contentDir: 'books/$id',
          sourcePath: Value(filePath),
          coverPath: Value(coverPath),
          spineCount: Value(summary.spine.length),
          charCount: Value(weights.totalCharacters),
          createdAt: addedAt.millisecondsSinceEpoch,
          level: Value(report.readabilityLevel),
          warnings: Value(
            report.warnings.isEmpty ? null : jsonEncode(report.warnings),
          ),
          deletedAt: const Value<int?>(null),
        );
        await _verifyImportSnapshot(File(filePath), sourceRevision);
        _checkImportCancelled(isCancelled);
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
          await _writeImportReports(bookId, report);
          // P4-09：spine 行落地（字符数与章前累计），供进度量化使用。
          await _writeSpineItems(bookId, summary.spine, charCounts, weights);
          await _writeImportToc(bookId, summary.spine, summary.toc);
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
  Future<void> remove(String id) => _enqueueOperation(() => _remove(id));

  Future<void> _remove(String id) async {
    if (_isMemory) {
      _memoryBytes.remove(id);
      _memoryEntries.remove(id);
      _memoryChapterTitles.remove(id);
      _notify();
      return;
    }
    final row = await _bookRowOfUuid(id);
    if (row == null) return;
    final root = await _root();
    final retainedCover = await _retainCover(root, row);
    final directories = await _removalDirectories(root, row);
    await _markBookRemoved(row.id, retainedCover);
    _notify();
    for (final directory in directories) {
      try {
        if (await directory.exists()) await directory.delete(recursive: true);
      } on FileSystemException {
        // 权限或占用失败时保留，下一次启动扫描再清理。
      }
    }
  }

  /// 删除书籍前把封面复制到独立目录，供笔记、书评和书单继续展示。
  Future<String?> _retainCover(Directory root, BookRow book) async {
    final coverPath = book.coverPath;
    if (coverPath == null) return null;
    final source = File(coverPath);
    if (!await source.exists()) return null;
    final directory = Directory(p.join(root.path, 'covers'));
    final target = File(
      p.join(directory.path, '${book.uuid}${p.extension(coverPath)}'),
    );
    if (p.equals(p.normalize(source.path), p.normalize(target.path))) {
      return target.path;
    }
    try {
      await directory.create(recursive: true);
      await source.copy(target.path);
      return target.path;
    } on FileSystemException {
      // 复制失败时退回无封面，内容仍按软删除保留。
      return null;
    }
  }

  Future<List<Directory>> _removalDirectories(
    Directory root,
    BookRow book,
  ) async {
    final db = _db!;
    final directory = _safeBookDirectory(root, book.uuid);
    if (directory == null) return [];
    final ownedPaths = [book.sourcePath, book.coverPath].nonNulls;
    if (!ownedPaths.any(
      (path) => p.isWithin(directory.path, p.normalize(path)),
    )) {
      return [];
    }
    final otherBooks = await (db.select(
      db.books,
    )..where((table) => table.id.isNotValue(book.id))).get();
    final versions = await (db.select(
      db.editVersions,
    )..where((table) => table.bookId.isNotValue(book.id))).get();
    final drafts = await (db.select(
      db.editDrafts,
    )..where((table) => table.bookId.isNotValue(book.id))).get();
    final protected = <String>[
      for (final other in otherBooks) ...[?other.sourcePath, ?other.coverPath],
      for (final version in versions) version.sourcePath,
      for (final draft in drafts) ...[draft.sourcePath, draft.directory],
    ];
    return _directoryHasReference(directory, protected) ? [] : [directory];
  }

  bool _directoryHasReference(Directory directory, Iterable<String> paths) {
    final root = p.normalize(directory.path);
    return paths.any((path) {
      final normalized = p.normalize(path);
      return p.equals(root, normalized) ||
          p.isWithin(root, normalized) ||
          p.isWithin(normalized, root);
    });
  }

  Future<void> _markBookRemoved(int bookId, String? retainedCover) =>
      _db!.transaction(() async {
        final db = _db;
        // 软删除保留阅读数据；源文件指针清理，封面改指保留副本。
        await (db.update(
          db.books,
        )..where((table) => table.id.equals(bookId))).write(
          BooksCompanion(
            deletedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
            sourcePath: const Value<String?>(null),
            coverPath: Value<String?>(retainedCover),
          ),
        );
        await (db.delete(
          db.editDrafts,
        )..where((t) => t.bookId.equals(bookId))).go();
        await (db.delete(
          db.editVersions,
        )..where((t) => t.bookId.equals(bookId))).go();
      });

  /// 写入 spine 行（§36.1）：字符数与章前累计供进度量化（§76.1）。
  Future<void> _writeSpineItems(
    int bookId,
    List<SpineItem> spine,
    List<int> charCounts,
    ProgressWeights weights,
  ) async {
    final db = _db!;
    await db.batch((batch) {
      batch.insertAll(db.spineItems, <SpineItemsCompanion>[
        for (var index = 0; index < spine.length; index++)
          SpineItemsCompanion.insert(
            bookId: bookId,
            spineIndex: index,
            href: spine[index].href,
            linear: Value<int>(spine[index].linear ? 1 : 0),
            charCount: Value<int>(charCounts[index]),
            charStart: Value<int>(weights.charStarts[index]),
          ),
      ]);
    });
  }

  Future<void> _writeImportToc(
    int bookId,
    List<SpineItem> spine,
    List<({String title, int spineIndex, int depth, int orderIndex})> toc,
  ) async {
    final entries = [
      for (final item in toc)
        if (item.spineIndex >= 0 && item.spineIndex < spine.length)
          ChaptersCompanion.insert(
            bookId: bookId,
            depth: Value(item.depth),
            title: item.title,
            href: spine[item.spineIndex].href,
            orderIndex: item.orderIndex,
          ),
    ];
    final db = _db!;
    if (entries.isNotEmpty) {
      await db.batch((batch) => batch.insertAll(db.chapters, entries));
    }
  }

  Map<int, String> _chapterTitlesFromToc(
    List<({String title, int spineIndex, int depth, int orderIndex})> toc,
  ) {
    final titles = <int, (String title, int depth)>{};
    for (final item in toc) {
      final previous = titles[item.spineIndex];
      if (previous == null || item.depth > previous.$2) {
        titles[item.spineIndex] = (item.title, item.depth);
      }
    }
    return <int, String>{
      for (final entry in titles.entries) entry.key: entry.value.$1,
    };
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

  /// 一次读取多本书的进度权重，供书架批量刷新进度。
  ///
  /// 书架若逐本调用 [progressWeights]，每本都要重复查询书籍与全部章节行；
  /// 这里改为两次固定查询后按书分组，数据库往返次数不再随藏书量增长。
  Future<Map<String, ProgressWeights>> progressWeightsForBooks(
    Iterable<String> bookIds,
  ) async {
    final ids = bookIds.toSet();
    if (_isMemory || ids.isEmpty) {
      return const <String, ProgressWeights>{};
    }
    final db = _db!;
    final books = await (db.select(
      db.books,
    )..where((table) => table.uuid.isIn(ids) & table.deletedAt.isNull())).get();
    if (books.isEmpty) {
      return const <String, ProgressWeights>{};
    }
    final internalIds = <int>{for (final book in books) book.id};
    final rows =
        await (db.select(db.spineItems)
              ..where((table) => table.bookId.isIn(internalIds))
              ..orderBy([
                (table) => OrderingTerm(expression: table.bookId),
                (table) => OrderingTerm(expression: table.spineIndex),
              ]))
            .get();
    final rowsByBook = <int, List<SpineItemRow>>{};
    for (final row in rows) {
      rowsByBook.putIfAbsent(row.bookId, () => <SpineItemRow>[]).add(row);
    }
    return <String, ProgressWeights>{
      for (final book in books)
        book.uuid: _weightsFromRows(
          rowsByBook[book.id] ?? const <SpineItemRow>[],
        ),
    };
  }

  /// 按书架进度批量读取当前章节的目录标题。
  Future<Map<String, String>> readingChapterTitles(
    Map<String, int> spineIndexes,
  ) async {
    if (spineIndexes.isEmpty) return const <String, String>{};
    if (_isMemory) {
      final titles = <String, String>{};
      for (final entry in spineIndexes.entries) {
        final title = _memoryChapterTitles[entry.key]?[entry.value];
        if (title != null) titles[entry.key] = title;
      }
      return titles;
    }

    final db = _db!;
    final query =
        db.selectOnly(db.books).join([
            innerJoin(
              db.spineItems,
              db.spineItems.bookId.equalsExp(db.books.id),
            ),
            innerJoin(
              db.chapters,
              db.chapters.bookId.equalsExp(db.books.id) &
                  db.chapters.href.equalsExp(db.spineItems.href),
            ),
          ])
          ..addColumns([
            db.books.uuid,
            db.spineItems.spineIndex,
            db.chapters.title,
            db.chapters.depth,
            db.chapters.orderIndex,
          ])
          ..where(db.books.uuid.isIn(spineIndexes.keys))
          ..orderBy([
            OrderingTerm.desc(db.chapters.depth),
            OrderingTerm.asc(db.chapters.orderIndex),
          ]);
    final titles = <String, String>{};
    for (final row in await query.get()) {
      final id = row.read(db.books.uuid)!;
      if (row.read(db.spineItems.spineIndex) != spineIndexes[id]) continue;
      titles.putIfAbsent(id, () => row.read(db.chapters.title)!);
    }
    return titles;
  }

  ProgressWeights _weightsFromRows(List<SpineItemRow> rows) =>
      ProgressWeights.fromCharCounts(
        <int>[for (final row in rows) row.charCount ?? 0],
        excluded: <int>{
          for (final row in rows)
            if (row.linear == 0) row.spineIndex,
        },
      );

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

  /// 启动扫描：清理当前书库中的孤儿目录与未提交版本（§37.4）。
  ///
  /// 返回清理的条目数与释放的字节数；失败项跳过（下次启动再试）。
  Future<({int removed, int bytes})> sweepOrphans() =>
      _enqueueOperation(_sweepOrphans);

  Future<({int removed, int bytes})> _sweepOrphans() async {
    if (_isMemory) {
      return (removed: 0, bytes: 0);
    }
    final db = _db!;
    final root = await _root();
    final rows = await (db.select(
      db.books,
    )..where((table) => table.deletedAt.isNull())).get();
    final paths = _LibrarySweepPaths(Directory(p.join(root.path, 'books')));
    await paths.resolveReferences(db, rows);
    await _sweepEditDrafts([
      for (final row in rows)
        if (!paths.deferredBookIds.contains(row.uuid)) row,
    ]);
    return _sweepBookDirectory(paths, {for (final row in rows) row.uuid});
  }

  Future<({int removed, int bytes})> _sweepBookDirectory(
    _LibrarySweepPaths paths,
    Set<String> knownIds,
  ) async {
    final booksDirectory = paths.booksDirectory;
    final knownFiles = paths.files;
    if (!await booksDirectory.exists()) return (removed: 0, bytes: 0);
    var removed = 0;
    var bytes = 0;
    await for (final entity in booksDirectory.list(followLinks: false)) {
      if (entity is Directory) {
        // books/<id>/；未知标识且无活动文件引用即为孤儿目录。
        final id = p.basename(entity.path);
        if (paths.deferredBookIds.contains(id)) continue;
        if (knownIds.contains(id) ||
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
        // 未提交的临时文件只保留数据库仍在引用的条目。
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

/// 一次导入的输入：文件路径（默认）或字节（测试/内存库）。
///
/// 文件路径全程不整本读入：哈希流式计算，解析在后台 isolate 走惰性 ZIP，
/// 落盘直接复制文件。
class _ImportPayload {
  const _ImportPayload.bytes(Uint8List bytes) : _bytes = bytes, _path = null;

  const _ImportPayload.file(String path) : _bytes = null, _path = path;

  final Uint8List? _bytes;
  final String? _path;

  Uint8List? get bytes => _bytes;

  Future<ImportAnalysis?> analyze({
    required Future<bool> Function(String revision) shouldSkip,
  }) {
    final path = _path;
    if (path != null) {
      return analyzeImportFileUnlessKnown(path, shouldSkip: shouldSkip);
    }
    return analyzeImportUnlessKnown(_bytes!, shouldSkip: shouldSkip);
  }

  Future<Uint8List> readBytes(String expectedRevision) async {
    final path = _path;
    if (path == null) return _bytes!;
    final snapshot = await readRevisionFileSnapshot(path);
    if (snapshot.revision != expectedRevision) throw _changedImportSource;
    return snapshot.bytes;
  }

  Future<void> writeTo(File target) async {
    final path = _path;
    if (path != null) {
      await File(path).copy(target.path);
      return;
    }
    await target.writeAsBytes(_bytes!, flush: true);
  }
}
