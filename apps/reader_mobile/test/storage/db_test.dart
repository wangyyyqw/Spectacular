import 'dart:io';

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
        contentRevision: 'test-content',
        title: '测试书',
        contentDir: 'books/$uuid/content',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        spineCount: const Value(2),
        charCount: const Value(1000),
      ),
    );

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
        'decorations',
        'decoration_rule_groups',
        'decoration_rules',
        'edit_drafts',
        'edit_versions',
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
        'idx_decoration_book',
        'idx_decoration_range',
        'idx_decoration_group_book',
        'idx_decoration_rule_group',
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
      2,
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

  test('v1 升级到 v2 只新增编辑表，既有书库和阅读数据保留', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reader-v1-upgrade-',
    );
    final file = File('${directory.path}/reader.sqlite');
    addTearDown(() => directory.delete(recursive: true));
    final original = await AppDatabase.open(file);
    final id = await _insertBook(original);
    await original
        .into(original.readingProgress)
        .insert(
          ReadingProgressCompanion.insert(
            bookId: Value(id),
            locatorCfi: '旧位置',
            updatedAt: 17,
          ),
        );
    await original.customStatement('DROP TABLE edit_drafts');
    await original.customStatement('DROP TABLE edit_versions');
    await original.customStatement('PRAGMA user_version = 1');
    await original.close();
    final migrated = await AppDatabase.open(file);
    addTearDown(migrated.close);
    await migrated.warmUp();
    expect((await migrated.select(migrated.books).getSingle()).id, id);
    expect(
      (await migrated.select(migrated.readingProgress).getSingle()).locatorCfi,
      '旧位置',
    );
    expect(await migrated.select(migrated.editDrafts).get(), isEmpty);
    expect(await migrated.select(migrated.editVersions).get(), isEmpty);
    expect(
      (await migrated.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      2,
    );
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

  test('阅读统计跨实例保存时长、翻页和字符数', () async {
    final directory = Directory.systemTemp.createTempSync('reader-db');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/${AppDatabase.fileName}');
    final first = await AppDatabase.open(file);
    try {
      final bookId = await _insertBook(first);
      await first
          .into(first.readingSessions)
          .insert(
            ReadingSessionsCompanion.insert(
              bookId: bookId,
              startedAt: 1000,
              endedAt: 61000,
              durationMs: 60000,
              pageTurns: const Value(9),
              charactersRead: const Value(1680),
            ),
          );
    } finally {
      await first.close();
    }
    final reopened = await AppDatabase.open(file);
    addTearDown(reopened.close);
    final saved =
        (await reopened.select(reopened.readingSessions).get()).single;
    expect(saved.startedAt, 1000);
    expect(saved.endedAt, 61000);
    expect(saved.durationMs, 60000);
    expect(saved.pageTurns, 9);
    expect(saved.charactersRead, 1680);
    expect(
      (await reopened.select(reopened.books).get()).single.contentRevision,
      'test-content',
    );
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
