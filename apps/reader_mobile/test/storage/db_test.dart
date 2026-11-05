import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 新建内存库并触发建库。
Future<AppDatabase> _openFresh() async {
  final database = AppDatabase(NativeDatabase.memory());
  await database.warmUp();
  addTearDown(database.close);
  return database;
}

/// 插入一本最小可用的书，返回主键。
Future<int> _insertBook(
  AppDatabase database, {
  String uuid = 'urn:uuid:test-book',
}) async => database
    .into(database.books)
    .insert(
      BooksCompanion.insert(
        uuid: uuid,
        title: '测试书',
        contentDir: 'books/$uuid/content',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        spineCount: const Value(2),
        charCount: const Value(1000),
      ),
    );

/// 从当前 schema 还原 v1 建表语句：去掉后续版本新增的列。
String _stripPostV1Columns(String statement) {
  var result = _stripIdentityColumns(statement);
  if (result.contains('"books"')) {
    result = result
        .replaceAll(RegExp(r',\s*"?deleted_at"?\s+INTEGER(\s+NULL)?'), '')
        .replaceAll(RegExp(r',\s*"?description"?\s+TEXT(\s+NULL)?'), '');
  }
  if (result.contains('reading_progress')) {
    result = result
        .replaceAll(RegExp(r',\s*"?spine_index"?\s+INTEGER(\s+NULL)?'), '')
        .replaceAll(RegExp(r',\s*"?page_index"?\s+INTEGER(\s+NULL)?'), '')
        .replaceAll(
          RegExp(r',\s*"?finished"?\s+BOOLEAN\s+NOT\s+NULL\s+DEFAULT\s+0'),
          '',
        );
  }
  return result;
}

String _stripIdentityColumns(String statement) =>
    _stripRevisionColumns(statement)
        .replaceAll(
          RegExp(r',\s*"?(epub_identifier|legacy_uuid)"?\s+TEXT(\s+NULL)?'),
          '',
        )
        .replaceAll(
          RegExp(r',\s*"?identity_version"?\s+INTEGER\s+NOT NULL\s+DEFAULT 0'),
          '',
        );

String _stripRevisionColumns(String statement) => statement.replaceAll(
  RegExp(r',\s*"?(content_revision|anchor_json)"?\s+TEXT(\s+NULL)?'),
  '',
);

/// 从当前 schema 导出 v1 建表语句（排除后续版本新增的表）。
Future<List<String>> _v1Schema() async {
  final database = AppDatabase(NativeDatabase.memory());
  await database.warmUp();
  final rows = await database
      .customSelect(
        'SELECT sql FROM sqlite_master WHERE sql IS NOT NULL '
        "AND name NOT IN ('import_reports', 'idx_report_book', 'book_reviews', "
        "'reading_sessions', 'idx_session_time', 'shelf_groups', "
        "'shelf_group_books', 'idx_shelf_group_book_group', 'book_tags', "
        "'book_tag_links', 'idx_book_tag_link_tag', 'book_id_aliases') "
        "AND name NOT LIKE 'sqlite_%'",
      )
      .get();
  final sql = <String>[
    for (final row in rows) _stripPostV1Columns(row.read<String>('sql')),
  ];
  await database.close();
  return sql;
}

/// 从当前 schema 还原 v10 建表语句：去掉阅读会话的翻页与字数列。
Future<List<String>> _v10Schema() async {
  final database = AppDatabase(NativeDatabase.memory());
  await database.warmUp();
  final rows = await database
      .customSelect(
        'SELECT sql FROM sqlite_master WHERE sql IS NOT NULL '
        "AND type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'book_id_aliases' ORDER BY rowid",
      )
      .get();
  final sql = <String>[
    for (final row in rows)
      _stripIdentityColumns(row.read<String>('sql')).replaceAll(
        RegExp(
          r',\s*"?(page_turns|characters_read)"?\s+INTEGER'
          r'(\s+NOT NULL)?(\s+DEFAULT\s+0)?',
        ),
        '',
      ),
  ];
  await database.close();
  return sql;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('建库：表与索引齐全，外键已开启', () async {
    final database = await _openFresh();
    final tables = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    final names = {for (final row in tables) row.read<String>('name')};
    expect(
      names,
      containsAll(<String>[
        'books',
        'spine_items',
        'chapters',
        'annotations',
        'reading_progress',
        'user_fonts',
        'settings',
        'import_reports',
        'book_reviews',
        'reading_sessions',
        'shelf_groups',
        'shelf_group_books',
        'book_tags',
        'book_tag_links',
        'book_id_aliases',
      ]),
    );
    final indexes = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND name LIKE 'idx_%'",
        )
        .get();
    expect(
      {for (final row in indexes) row.read<String>('name')},
      containsAll(<String>[
        'idx_spine_book',
        'idx_chapter_book',
        'idx_anno_book',
        'idx_anno_quote',
        'idx_report_book',
        'idx_session_time',
        'idx_shelf_group_book_group',
        'idx_book_tag_link_tag',
      ]),
    );
    final foreignKeys = await database
        .customSelect('PRAGMA foreign_keys')
        .get();
    expect(foreignKeys.first.data['foreign_keys'], 1);
    expect(
      await database
          .customSelect('PRAGMA user_version')
          .getSingle()
          .then((row) => row.read<int>('user_version')),
      14,
    );
  });

  test('books.uuid 唯一：重复导入落到同一本书不产生两份', () async {
    final database = await _openFresh();
    await _insertBook(database);
    await expectLater(
      _insertBook(database),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect((await database.select(database.books).get()).length, 1);
  });

  test('v12→v14增加身份与锚点列，原主键和元数据保持不变', () async {
    final template = await _openFresh();
    final schema = await template
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'book_id_aliases' ORDER BY rowid",
        )
        .get();
    final raw = sqlite.sqlite3.openInMemory();
    for (final row in schema) {
      raw.execute(_stripIdentityColumns(row.read<String>('sql')));
    }
    raw.execute('PRAGMA user_version = 12');
    raw.execute(
      "INSERT INTO books (id,uuid,title,content_dir,created_at) VALUES (7,'legacy','旧书','books/legacy',1)",
    );
    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.warmUp();
    final book = (await db.select(db.books).get()).single;
    expect(book.id, 7);
    expect(book.uuid, 'legacy');
    expect(book.title, '旧书');
    expect(book.identityVersion, 0);
    expect(book.epubIdentifier, isNull);
    expect(book.legacyUuid, isNull);
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      14,
    );
  });

  test('v13→v14保留原CFI和用户数据，新锚点为空', () async {
    final template = await _openFresh();
    final schema = await template
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'book_id_aliases' ORDER BY rowid",
        )
        .get();
    final raw = sqlite.sqlite3.openInMemory();
    for (final row in schema) {
      raw.execute(_stripRevisionColumns(row.read<String>('sql')));
    }
    raw.execute('PRAGMA user_version = 13');
    raw.execute(
      "INSERT INTO books (id,uuid,title,content_dir,created_at) VALUES (7,'v13','旧书','books/v13',1)",
    );
    raw.execute(
      "INSERT INTO annotations (id,book_id,type,start_cfi,end_cfi,quote,note,color,style,created_at,updated_at) VALUES ('a',7,1,'old-start','old-end','原引用','原笔记',123,2,4,5)",
    );
    raw.execute(
      "INSERT INTO reading_progress (book_id,locator_cfi,percent,spine_index,page_index,finished,updated_at) VALUES (7,'spine:2/page:4',0.5,2,4,1,5)",
    );
    final database = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(database.close);
    await database.warmUp();
    final book = (await database.select(database.books).get()).single;
    final annotation =
        (await database.select(database.annotations).get()).single;
    final progress =
        (await database.select(database.readingProgress).get()).single;
    expect(book.id, 7);
    expect(book.contentRevision, isNull);
    expect(annotation.startCfi, 'old-start');
    expect(annotation.quote, '原引用');
    expect(annotation.note, '原笔记');
    expect(annotation.color, 123);
    expect(annotation.style, 2);
    expect(annotation.createdAt, 4);
    expect(annotation.anchorJson, isNull);
    expect(progress.locatorCfi, 'spine:2/page:4');
    expect(progress.finished, isTrue);
    expect(progress.anchorJson, isNull);
    expect(await database.select(database.bookIdAliases).get(), isEmpty);
  });

  test('删书级联清理：spine/目录/标注/进度/索引/报告一并删除', () async {
    final database = await _openFresh();
    final bookId = await _insertBook(database);
    await database
        .into(database.spineItems)
        .insert(
          SpineItemsCompanion.insert(
            bookId: bookId,
            spineIndex: 0,
            href: 'c1.xhtml',
          ),
        );
    await database
        .into(database.chapters)
        .insert(
          ChaptersCompanion.insert(
            bookId: bookId,
            title: '第一章',
            href: 'c1.xhtml',
            orderIndex: 0,
          ),
        );
    await database
        .into(database.annotations)
        .insert(
          AnnotationsCompanion.insert(
            id: 'anno-1',
            bookId: bookId,
            type: 0,
            startCfi: 'cfi:1',
            endCfi: 'cfi:2',
            quote: '引用',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await database
        .into(database.readingProgress)
        .insert(
          ReadingProgressCompanion(
            bookId: Value<int>(bookId),
            locatorCfi: const Value<String>('cfi:1'),
            updatedAt: const Value<int>(1),
          ),
        );
    await database
        .into(database.bookReviews)
        .insert(
          BookReviewsCompanion.insert(
            bookId: Value<int>(bookId),
            rating: const Value<int?>(4),
            content: const Value<String>('一段书评'),
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await database
        .into(database.readingSessions)
        .insert(
          ReadingSessionsCompanion.insert(
            bookId: bookId,
            startedAt: 1,
            endedAt: 61,
            durationMs: 60,
          ),
        );

    await (database.delete(
      database.books,
    )..where((table) => table.id.equals(bookId))).go();

    expect(await database.select(database.books).get(), isEmpty);
    expect(await database.select(database.spineItems).get(), isEmpty);
    expect(await database.select(database.chapters).get(), isEmpty);
    expect(await database.select(database.annotations).get(), isEmpty);
    expect(await database.select(database.readingProgress).get(), isEmpty);
    expect(await database.select(database.importReports).get(), isEmpty);
    expect(await database.select(database.bookReviews).get(), isEmpty);
    expect(await database.select(database.readingSessions).get(), isEmpty);
  });

  test('v1→v14 迁移：数据保留并新增报告、进度列、书评、会话、软删除、分组、标签、阅读统计与身份列', () async {
    final raw = sqlite.sqlite3.openInMemory();
    for (final statement in await _v1Schema()) {
      raw.execute(statement);
    }
    raw.execute('PRAGMA user_version = 1');
    raw.execute(
      'INSERT INTO books (uuid, title, content_dir, created_at, '
      'spine_count, char_count, layout_version, level) '
      "VALUES ('urn:uuid:old', '旧书', 'books/old/content', 1, 1, 100, 0, 0)",
    );

    final database = AppDatabase(NativeDatabase.opened(raw));
    await database.warmUp();
    addTearDown(database.close);

    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 14, reason: 'schema 已升到 v14');
    final columns = await database
        .customSelect('PRAGMA table_info(reading_progress)')
        .get();
    final names = <String>{for (final row in columns) row.read<String>('name')};
    expect(
      names,
      containsAll(<String>['spine_index', 'page_index', 'finished']),
    );
    final bookColumns = await database
        .customSelect('PRAGMA table_info(books)')
        .get();
    expect(<String>{
      for (final row in bookColumns) row.read<String>('name'),
    }, contains('deleted_at'));
    expect(<String>{
      for (final row in bookColumns) row.read<String>('name'),
    }, contains('description'));
    final books = await database.select(database.books).get();
    expect(books.single.title, '旧书', reason: '迁移不丢数据');
    await database
        .into(database.importReports)
        .insert(
          ImportReportsCompanion.insert(
            bookId: books.single.id,
            code: 'W001',
            message: '迁移后可写报告',
            createdAt: 1,
          ),
        );
    expect((await database.select(database.importReports).get()).length, 1);
    await database
        .into(database.bookReviews)
        .insert(
          BookReviewsCompanion.insert(
            bookId: Value<int>(books.single.id),
            rating: const Value<int?>(5),
            content: const Value<String>('迁移后可写书评'),
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    expect((await database.select(database.bookReviews).get()).length, 1);
    await database
        .into(database.readingSessions)
        .insert(
          ReadingSessionsCompanion.insert(
            bookId: books.single.id,
            startedAt: 1,
            endedAt: 61,
            durationMs: 60,
          ),
        );
    final sessions = await database.select(database.readingSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.pageTurns, 0);
    expect(sessions.single.charactersRead, 0);
    final sessionColumns = await database
        .customSelect('PRAGMA table_info(reading_sessions)')
        .get();
    expect(<String>{
      for (final row in sessionColumns) row.read<String>('name'),
    }, containsAll(<String>['page_turns', 'characters_read']));

    // 搜索改为扫描式后，旧的倒排索引两张表不再创建。
    final tables = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final tableNames = <String>{
      for (final row in tables) row.read<String>('name'),
    };
    expect(
      tableNames,
      containsAll(<String>['shelf_groups', 'shelf_group_books']),
    );
    expect(tableNames, containsAll(<String>['book_tags', 'book_tag_links']));
    expect(tableNames, isNot(contains('chapter_text')));
    expect(tableNames, isNot(contains('search_grams')));
  });

  test('v10→v11 迁移：旧阅读会话保留数据并补默认统计列', () async {
    final raw = sqlite.sqlite3.openInMemory();
    for (final statement in await _v10Schema()) {
      raw.execute(statement);
    }
    raw.execute('PRAGMA user_version = 10');
    raw.execute(
      'INSERT INTO books (uuid, title, content_dir, created_at, '
      'spine_count, char_count, layout_version, level) '
      "VALUES ('urn:uuid:v10', 'v10 书', 'books/v10/content', 1, 1, 100, 0, 0)",
    );
    final bookId = raw.lastInsertRowId;
    raw.execute(
      'INSERT INTO reading_sessions '
      '(book_id, started_at, ended_at, duration_ms) VALUES (?, ?, ?, ?)',
      <Object?>[bookId, 1, 60001, 60000],
    );

    final database = AppDatabase(NativeDatabase.opened(raw));
    await database.warmUp();
    addTearDown(database.close);

    final session =
        (await database.select(database.readingSessions).get()).single;
    expect(session.bookId, bookId);
    expect(session.durationMs, 60000);
    expect(session.pageTurns, 0);
    expect(session.charactersRead, 0);
  });

  test('并发写入不锁超时', () async {
    final database = await _openFresh();
    await Future.wait(<Future<void>>[
      for (var i = 0; i < 30; i++)
        _insertBook(database, uuid: 'urn:uuid:concurrent-$i'),
    ]);
    expect((await database.select(database.books).get()).length, 30);
  });

  test('版本过新：容错打开返回 null 且上报错误，不崩溃', () async {
    final raw = sqlite.sqlite3.openInMemory();
    for (final statement in await _v1Schema()) {
      raw.execute(statement);
    }
    raw.execute('PRAGMA user_version = 99');

    Object? reported;
    final database = await AppDatabase.tryOpenExecutor(
      NativeDatabase.opened(raw),
      onError: (error, stack) => reported = error,
    );
    expect(database, isNull);
    expect(reported, isNotNull, reason: '错误已上报，调用方可靠记录');
  });
}
