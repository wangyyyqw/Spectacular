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

  /// 首次导入生成的书籍标识；本地编辑元数据时保持稳定。
  TextColumn get uuid => text().unique()();

  /// EPUB 原始 unique-identifier，不使用书籍标识替换字体解混淆密钥。
  TextColumn get epubIdentifier => text().nullable()();

  /// 当前 EPUB 字节摘要，与书籍身份分开。
  TextColumn get contentRevision => text()();

  /// 书名。
  TextColumn get title => text()();

  /// 作者。
  TextColumn get author => text().nullable()();

  /// 用户可编辑的简介。
  TextColumn get description => text().nullable()();

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

/// 标注表（§36.1）：划线 / 想法 / 书签共用，`type` 区分。
@DataClassName('AnnotationRow')
class Annotations extends Table {
  /// 主键（uuid 字符串，可迁移）。
  TextColumn get id => text()();

  /// 所属书籍。
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();

  /// 类型：0 划线、1 想法、2 书签。
  IntColumn get type => integer()();

  /// 起始 CFI。
  TextColumn get startCfi => text()();

  /// 结束 CFI。
  TextColumn get endCfi => text()();

  /// 原始与当前内容锚点，以及迁移状态。
  TextColumn get anchorJson => text().nullable()();

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

  /// 标记透明度；空值跟随样式默认值。
  RealColumn get opacity => real().nullable()();

  /// 笔记正文。
  TextColumn get note => text().nullable()();

  /// 创建时间（毫秒）。
  IntColumn get createdAt => integer()();

  /// 更新时间（毫秒）。
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 手工装饰表：内容锚点与排版样式分开保存。
@DataClassName('DecorationRow')
class Decorations extends Table {
  /// 唯一标识。
  TextColumn get id => text()();

  /// 所属书籍，彻底删除时级联清理。
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();

  /// 原文起点。
  TextColumn get startCfi => text()();

  /// 原文终点。
  TextColumn get endCfi => text()();

  /// 原始引用。
  TextColumn get quote => text()();

  /// 前文证据。
  TextColumn get contextBefore => text().nullable()();

  /// 后文证据。
  TextColumn get contextAfter => text().nullable()();

  /// 版本化内容锚点。
  TextColumn get anchorJson => text().nullable()();

  /// 带版本号的装饰样式。
  TextColumn get styleJson => text()();

  /// 创建时间（毫秒）。
  IntColumn get createdAt => integer()();

  /// 更新时间（毫秒）。
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 自动装饰分组；空书籍外键表示全局作用域。
@DataClassName('DecorationRuleGroupRow')
class DecorationRuleGroups extends Table {
  /// 唯一标识。
  TextColumn get id => text()();

  /// 所属书籍；全局组为空。
  IntColumn get bookId => integer().nullable().references(
    Books,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// 分组名称。
  TextColumn get name => text()();

  /// 启用状态。
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 默认组固定在同作用域最后。
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  /// 组间排序。
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 创建时间（毫秒）。
  IntColumn get createdAt => integer()();

  /// 更新时间（毫秒）。
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 自动装饰规则；仅保存规格，不保存章节匹配结果。
@DataClassName('DecorationRuleRow')
class DecorationRules extends Table {
  /// 唯一标识。
  TextColumn get id => text()();

  /// 所属分组。
  TextColumn get groupId => text().references(
    DecorationRuleGroups,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// 可选名称。
  TextColumn get name => text().nullable()();

  /// 字面内容或 Unicode 正则。
  TextColumn get pattern => text()();

  /// 是否使用正则。
  BoolColumn get isRegex => boolean().withDefault(const Constant(false))();

  /// 是否区分大小写。
  BoolColumn get caseSensitive =>
      boolean().withDefault(const Constant(false))();

  /// 单条启用状态。
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 不影响度量的绘制样式。
  TextColumn get styleJson => text()();

  /// 组内排序。
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

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

  /// 当前原文的 CFI；没有内容位置的读完标记保存空串。
  TextColumn get locatorCfi => text()();

  /// 原始与当前内容锚点及位置元数据。
  TextColumn get anchorJson => text().nullable()();

  /// spine 序号，供书架和续读使用。
  IntColumn get spineIndex => integer().nullable()();

  /// 章内页序号。
  IntColumn get pageIndex => integer().nullable()();

  /// 用户手动标记的读完状态。
  BoolColumn get finished => boolean().withDefault(const Constant(false))();

  /// 全书百分比（0～100；UI 使用的 `ReaderProgress.readingPercent` 为 0～1）。
  RealColumn get percent => real().withDefault(const Constant(0))();

  /// 写入时间（毫秒）。
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{bookId};
}

/// 原书被用户指定替换后的身份，用于定位同一条修订记录。
@DataClassName('BookIdAliasRow')
class BookIdAliases extends Table {
  TextColumn get aliasId => text()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{aliasId, bookId};
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

  /// 本段阅读的翻页次数。
  IntColumn get pageTurns => integer().withDefault(const Constant(0))();

  /// 本段阅读翻过页面的非空白字符数。
  IntColumn get charactersRead => integer().withDefault(const Constant(0))();
}

/// 书架分组表：用户自定义的书籍分组。
@DataClassName('ShelfGroupRow')
class ShelfGroups extends Table {
  /// 分组标识。
  TextColumn get id => text()();

  /// 分组名称。
  TextColumn get name => text()();

  /// 创建时间（毫秒）。
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 书籍分组归属：一本书最多属于一个分组，重新分组时覆盖旧值。
@DataClassName('ShelfGroupBookRow')
class ShelfGroupBooks extends Table {
  /// 书籍 uuid（`books.uuid`）；删书走软删除，归属保留供重新导入恢复。
  TextColumn get bookUuid => text()();

  /// 所属分组。
  TextColumn get groupId =>
      text().references(ShelfGroups, #id, onDelete: KeyAction.cascade)();

  /// 加入分组时间（毫秒）。
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{bookUuid};
}

/// 标签表：跨书籍复用的自定义标签。
@DataClassName('BookTagRow')
class BookTags extends Table {
  /// 标签标识。
  TextColumn get id => text()();

  /// 标签名称（全局唯一）。
  TextColumn get name => text().unique()();

  /// 创建时间（毫秒）。
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 书籍与标签的多对多关联；标签删除时级联清理关联。
@DataClassName('BookTagLinkRow')
class BookTagLinks extends Table {
  /// 书籍 uuid（`books.uuid`）；删书走软删除，关联保留供重新导入恢复。
  TextColumn get bookUuid => text()();

  /// 标签。
  TextColumn get tagId =>
      text().references(BookTags, #id, onDelete: KeyAction.cascade)();

  /// 打标签时间（毫秒）。
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{bookUuid, tagId};
}

/// 草稿仅保存目录指针；修改资源存为独立文件，不把 EPUB 放进数据库。
@DataClassName('EditDraftRow')
class EditDrafts extends Table {
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get baseRevision => text()();
  TextColumn get sourcePath => text()();
  TextColumn get directory => text()();
  IntColumn get updatedAt => integer()();
  @override
  Set<Column<Object>> get primaryKey => {bookId};
}

/// 每本书保留首次编辑前原版和最近一次保存前版本。
@DataClassName('EditVersionRow')
class EditVersions extends Table {
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  TextColumn get revision => text()();
  TextColumn get sourcePath => text()();
  TextColumn get summary => text()();
  IntColumn get createdAt => integer()();
  @override
  Set<Column<Object>> get primaryKey => {bookId, kind};
}

/// 应用数据库：书库、进度、标注、搜索索引（技术方案 §36）。
@DriftDatabase(
  tables: [
    Books,
    SpineItems,
    Chapters,
    Annotations,
    Decorations,
    DecorationRuleGroups,
    DecorationRules,
    ReadingProgress,
    UserFonts,
    SettingsTable,
    ImportReports,
    BookReviews,
    ReadingSessions,
    ShelfGroups,
    ShelfGroupBooks,
    BookTags,
    BookTagLinks,
    BookIdAliases,
    EditDrafts,
    EditVersions,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 用给定执行器创建（测试传内存库）。
  AppDatabase(super.executor);

  /// 数据库文件名。
  static const String fileName = 'reader.sqlite';

  /// 数据库结构版本，与书级排版版本分开；v2 增加草稿与编辑历史。
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createIndexes();
    },
    onUpgrade: (migrator, from, to) async {
      if (from > to) throw StateError('数据库版本过新，不能降级打开');
      if (from < 2) {
        await migrator.createTable(editDrafts);
        await migrator.createTable(editVersions);
      }
    },
    beforeOpen: (details) async {
      // §36.2：级联删除依赖外键约束。
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// 新库索引随当前表结构一次创建。
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
      'CREATE INDEX IF NOT EXISTS idx_decoration_book '
      'ON decorations(book_id, start_cfi)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_decoration_range '
      'ON decorations(book_id, start_cfi, end_cfi)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_decoration_group_book '
      'ON decoration_rule_groups(book_id, sort_order)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_decoration_rule_group '
      'ON decoration_rules(group_id, sort_order)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_report_book '
      'ON import_reports(book_id, severity)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_session_time '
      'ON reading_sessions(started_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_shelf_group_book_group '
      'ON shelf_group_books(group_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_book_tag_link_tag '
      'ON book_tag_links(tag_id)',
    );
  }

  /// 触发打开与建库。
  ///
  /// drift 是懒打开：只构造不会建库，第一次查询才执行 onCreate /
  /// 版本检查。启动时调用一次，让建库或不支持的数据库版本在可控位置失败。
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
