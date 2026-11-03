import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'db.g.dart';

/// 书籍表（技术方案 §36.1）：每本书一行，`uuid` 唯一防重复导入。
@DataClassName('BookRow')
class Books extends Table {
  /// 主键。
  IntColumn get id => integer().autoIncrement()();

  /// OPF unique-identifier：同一本书重复导入落到同一目录。
  TextColumn get uuid => text().unique()();

  /// 书名。
  TextColumn get title => text()();

  /// 作者。
  TextColumn get author => text().nullable()();

  /// 语言。
  TextColumn get language => text().nullable()();

  /// 解包后的内容目录（`books/<uuid>/content`）。
  TextColumn get contentDir => text()();

  /// 原始 EPUB 备份路径。
  TextColumn get sourcePath => text().nullable()();

  /// 封面缓存文件路径。
  TextColumn get coverPath => text().nullable()();

  /// spine 项数。
  IntColumn get spineCount => integer().withDefault(const Constant(0))();

  /// 全书字符数（进度算法用，§22.3）。
  IntColumn get charCount => integer().withDefault(const Constant(0))();

  /// 导入时间（毫秒）。
  IntColumn get createdAt => integer()();

  /// 最近阅读时间（毫秒）。
  IntColumn get lastReadAt => integer().nullable()();

  /// 书级排版版本（§70.3）：算法变更时 +1，与 schema 版本无关。
  IntColumn get layoutVersion => integer().withDefault(const Constant(0))();

  /// 可读性分级 L0～L4（§55.2）。
  IntColumn get level => integer().withDefault(const Constant(0))();

  /// 导入修复与降级摘要（JSON 数组）。
  TextColumn get warnings => text().nullable()();

  /// 从书架移除的时间（毫秒）；非空时保留用户数据但不对书架展示。
  IntColumn get deletedAt => integer().nullable()();
}

/// spine 项表（§36.1）：按 spine 建，供分页与虚拟页窗口使用。
@DataClassName('SpineItemRow')
class SpineItems extends Table {
  /// 主键。
  IntColumn get id => integer().autoIncrement()();

  /// 所属书籍（删书级联）。
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();

  /// spine 序号（§34.2：(原序+1)×2）。
  IntColumn get spineIndex => integer()();

  /// 章节文档路径。
  TextColumn get href => text()();

  /// 是否 linear（1 参与主线阅读）。
  IntColumn get linear => integer().withDefault(const Constant(1))();

  /// 文档字节数。
  IntColumn get byteSize => integer().nullable()();

  /// 本章字符数（进度用）。
  IntColumn get charCount => integer().nullable()();

  /// 全书字符偏移起点。
  IntColumn get charStart => integer().nullable()();
}

/// 目录项表（§35.3）：按目录项建，可与 spine 多对一。
@DataClassName('ChapterRow')
class Chapters extends Table {
  /// 主键。
  IntColumn get id => integer().autoIncrement()();

  /// 所属书籍。
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();

  /// 层级（1 起，决定目录缩进）。
  IntColumn get depth => integer().withDefault(const Constant(1))();

  /// 标题。
  TextColumn get title => text()();

  /// 目标文档路径。
  TextColumn get href => text()();

  /// 解析期算出的 CFI。
  TextColumn get cfi => text().nullable()();

  /// 文档顺序。
  IntColumn get orderIndex => integer()();
}

/// 标注表（§36.1）：高亮 / 笔记 / 书签共用，`type` 区分。
@DataClassName('AnnotationRow')
class Annotations extends Table {
  /// 主键（uuid 字符串，可迁移）。
  TextColumn get id => text()();

  /// 所属书籍。
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();

  /// 类型：0 高亮、1 笔记、2 书签。
  IntColumn get type => integer()();

  /// 起始 CFI。
  TextColumn get startCfi => text()();

  /// 结束 CFI。
  TextColumn get endCfi => text()();

  /// 原文引用（兜底重定位）。
  TextColumn get quote => text()();

  /// 前文上下文（约 20 字）。
  TextColumn get contextBefore => text().nullable()();

  /// 后文上下文（约 20 字）。
  TextColumn get contextAfter => text().nullable()();

  /// 样式（划线/波浪线等）。
  IntColumn get style => integer().nullable()();

  /// 颜色（ARGB）。
  IntColumn get color => integer().nullable()();

  /// 笔记正文。
  TextColumn get note => text().nullable()();

  /// 创建时间（毫秒）。
  IntColumn get createdAt => integer()();

  /// 更新时间（毫秒）。
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 阅读进度表（§36.1）：每本书一行，只存 CFI，重排不丢位置（§70.3）。
@DataClassName('ProgressRow')
class ReadingProgress extends Table {
  /// 书籍主键兼外键。
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();

  /// 位置 CFI（P5 接入 CFI 后使用；当前存 `spine:i/page:j` 占位串）。
  TextColumn get locatorCfi => text()();

  /// spine 序号（P4-10：进度迁移到表内，书架/续读用）。
  IntColumn get spineIndex => integer().nullable()();

  /// 章内页序号。
  IntColumn get pageIndex => integer().nullable()();

  /// 全书百分比（0～1）。
  RealColumn get percent => real().withDefault(const Constant(0))();

  /// 写入时间（毫秒）。
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{bookId};
}

/// 用户导入字体表（§36.1）。
@DataClassName('UserFontRow')
class UserFonts extends Table {
  /// 主键。
  IntColumn get id => integer().autoIncrement()();

  /// 族名。
  TextColumn get family => text()();

  /// 字体文件路径。
  TextColumn get filePath => text()();

  /// 字重。
  IntColumn get weight => integer().nullable()();

  /// 字体样式（normal/italic）。
  IntColumn get style => integer().nullable()();

  /// 展示名。
  TextColumn get displayName => text().nullable()();
}

/// 设置表（§36.1）：key/value 平铺，值用 JSON 字符串。
@DataClassName('SettingRow')
class SettingsTable extends Table {
  @override
  String get tableName => 'settings';

  /// 设置键。
  TextColumn get key => text()();

  /// 设置值。
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// 导入报告明细表（v2，P4-06）：修复项 / 警告分级落库。
@DataClassName('ImportReportRow')
class ImportReports extends Table {
  /// 主键。
  IntColumn get id => integer().autoIncrement()();

  /// 所属书籍。
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();

  /// 诊断码（P7-05 诊断码）。
  TextColumn get code => text()();

  /// 分级：0 info、1 warning、2 error。
  IntColumn get severity => integer().withDefault(const Constant(0))();

  /// 人类可读信息。
  TextColumn get message => text()();

  /// 相关文件内偏移（可空）。
  IntColumn get offset => integer().nullable()();

  /// 记录时间（毫秒）。
  IntColumn get createdAt => integer()();
}

/// 书评表：每本书保存一条评分与正文，删书时级联删除。
@DataClassName('BookReviewRow')
class BookReviews extends Table {
  /// 所属书籍，同时作为主键。
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();

  /// 评分 1～5；null 表示未评分。
  IntColumn get rating => integer().nullable()();

  /// 书评正文。
  TextColumn get content => text().withDefault(const Constant(''))();

  /// 创建时间（毫秒）。
  IntColumn get createdAt => integer()();

  /// 更新时间（毫秒）。
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{bookId};
}

/// 阅读会话表：只记录前台有效阅读时段，供统计页汇总时长与天数。
@DataClassName('ReadingSessionRow')
class ReadingSessions extends Table {
  /// 主键。
  IntColumn get id => integer().autoIncrement()();

  /// 所属书籍，删书时级联删除。
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();

  /// 开始时间（毫秒）。
  IntColumn get startedAt => integer()();

  /// 结束时间（毫秒）。
  IntColumn get endedAt => integer()();

  /// 有效阅读时长（毫秒）。
  IntColumn get durationMs => integer()();
}

/// 应用数据库：书库、进度、标注、搜索索引（技术方案 §36）。
@DriftDatabase(
  tables: [
    Books,
    SpineItems,
    Chapters,
    Annotations,
    ReadingProgress,
    UserFonts,
    SettingsTable,
    ImportReports,
    BookReviews,
    ReadingSessions,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 用给定执行器创建（测试传内存库）。
  AppDatabase(super.executor);

  /// 数据库文件名。
  static const String fileName = 'reader.sqlite';

  /// schema 版本（§70.1：全局表结构版本，与书级 layoutVersion 分开）。
  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createIndexes();
    },
    // §70.2 三条纪律：每步单调递增不合并、不删列、索引单独建。
    onUpgrade: (migrator, from, to) async {
      var version = from;
      if (version < 2) {
        await migrator.createTable(importReports);
        version = 2;
      }
      if (version < 3) {
        // P4-10：进度迁入 reading_progress，补 spine/page 两列。
        await migrator.addColumn(
          readingProgress,
          readingProgress.spineIndex,
        );
        await migrator.addColumn(readingProgress, readingProgress.pageIndex);
        version = 3;
      }
      if (version < 4) {
        // P4-24 时期的搜索索引表已废弃（搜索改为扫描式），v4 只推进版本号。
        version = 4;
      }
      if (version < 5) {
        // 搜索改为扫描式（对照 Reeden）：不再维护倒排索引，删表回收空间。
        await customStatement('DROP TABLE IF EXISTS search_grams');
        await customStatement('DROP TABLE IF EXISTS chapter_text');
        version = 5;
      }
      if (version < 6) {
        await migrator.createTable(bookReviews);
        version = 6;
      }
      if (version < 7) {
        await migrator.createTable(readingSessions);
        version = 7;
      }
      if (version < 8) {
        // 删书改为软删除：保留进度、标注、书评和阅读会话，重新导入可恢复。
        await migrator.addColumn(books, books.deletedAt);
        version = 8;
      }
      await _createIndexes();
    },
    beforeOpen: (details) async {
      // §36.2：级联删除依赖外键约束。
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// 索引单独建（§70.2 纪律 3）：幂等，升级/新建共用。
  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_spine_book '
      'ON spine_items(book_id, spine_index)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_chapter_book '
      'ON chapters(book_id, order_index)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_anno_book ON annotations(book_id, type)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_anno_quote '
      'ON annotations(book_id, quote)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_report_book '
      'ON import_reports(book_id, severity)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_session_time '
      'ON reading_sessions(started_at)',
    );
  }

  /// 触发打开与迁移。
  ///
  /// drift 是懒打开：只构造不会建库，第一次查询才执行 onCreate /
  /// onUpgrade。启动时调用一次，让建库与迁移在可控位置失败。
  Future<void> warmUp() async {
    await customSelect('SELECT 1').getSingle();
  }

  /// 打开文档目录下的默认库文件（不存在则建库）。
  static Future<AppDatabase> openDefault() async {
    final directory = await getApplicationDocumentsDirectory();
    return open(File(p.join(directory.path, fileName)));
  }

  /// 打开指定库文件。
  static Future<AppDatabase> open(File file) async =>
      AppDatabase(NativeDatabase(file));

  /// 容错打开给定执行器：库损坏或版本过新时返回 null，启动流程不因
  /// 数据库崩溃（P4-02「降级不崩溃并有提示」）。
  static Future<AppDatabase?> tryOpenExecutor(
    QueryExecutor executor, {
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    final database = AppDatabase(executor);
    try {
      await database.warmUp();
      return database;
    } catch (error, stack) {
      unawaited(database.close().catchError((Object _) {}));
      onError?.call(error, stack);
      return null;
    }
  }

  /// 容错打开默认库，见 [tryOpenExecutor]。
  static Future<AppDatabase?> tryOpenDefault({
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return await tryOpenExecutor(
        NativeDatabase(File(p.join(directory.path, fileName))),
        onError: onError,
      );
    } catch (error, stack) {
      onError?.call(error, stack);
      return null;
    }
  }
}
