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

Future<File> _temporaryDatabaseFile() async {
  final directory = await Directory.systemTemp.createTemp('reader-schema-');
  addTearDown(() => directory.delete(recursive: true));
  return File('${directory.path}/${AppDatabase.fileName}');
}

Future<void> _writeEdits(AppDatabase database, int bookId) async {
  await database.customStatement(
    'INSERT INTO edit_drafts (book_id, base_revision, source_path, directory, updated_at) '
    'VALUES (?, ?, ?, ?, ?)',
    [bookId, 'test-content', 'books/原书.epub', 'edits/草稿', 19],
  );
  await database.customStatement(
    'INSERT INTO edit_versions (book_id, kind, revision, source_path, summary, created_at) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    [bookId, 'original', '原修订', 'edits/原版.epub', '原版', 18],
  );
}

Future<int> _seedDevelopmentDatabase(File file, int version) async {
  final database = await AppDatabase.open(file);
  try {
    final bookId = await _insertBook(database);
    await database.customStatement(
      'INSERT INTO reading_progress (book_id, locator_cfi, percent, updated_at) VALUES (?, ?, ?, ?)',
      [bookId, 'epubcfi(/6/2!/4/2/1:3)', 35.5, 17],
    );
    await database.customStatement(
      'INSERT INTO annotations (id, book_id, type, start_cfi, end_cfi, quote, note, created_at, updated_at) '
      'VALUES (?, ?, 1, ?, ?, ?, ?, 13, 15)',
      ['note-1', bookId, '起点', '终点', '引用', '旧笔记正文'],
    );
    await database.customStatement("INSERT INTO settings VALUES ('主题', '墨色')");
    if (version == 1) {
      await database.customStatement('DROP TABLE edit_drafts');
      await database.customStatement('DROP TABLE edit_versions');
    } else {
      await _writeEdits(database, bookId);
      await database.customStatement('PRAGMA user_version = 2');
    }
    return bookId;
  } finally {
    await database.close();
  }
}

Future<void> _expectUserRows(AppDatabase database, int bookId) async {
  final book = await database.select(database.books).getSingle();
  expect(
    (book.id, book.uuid, book.contentRevision),
    (bookId, 'urn:uuid:test-book', 'test-content'),
  );
  final progress = await database.select(database.readingProgress).getSingle();
  expect(
    (
      progress.bookId,
      progress.locatorCfi,
      progress.percent,
      progress.updatedAt,
    ),
    (bookId, 'epubcfi(/6/2!/4/2/1:3)', 35.5, 17),
  );
  final note = await database.select(database.annotations).getSingle();
  expect(
    (note.bookId, note.id, note.note, note.quote, note.updatedAt),
    (bookId, 'note-1', '旧笔记正文', '引用', 15),
  );
  final setting = await (database.select(
    database.settingsTable,
  )..where((t) => t.key.equals('主题'))).getSingle();
  expect((setting.key, setting.value), ('主题', '墨色'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('旧整星评分只迁移一次，正文和保存时间保持不变', () async {
    final file = await _temporaryDatabaseFile();
    var database = await AppDatabase.open(file);
    final bookId = await _insertBook(database);
    await database.customStatement(
      'INSERT INTO book_reviews (book_id, rating, content, created_at, updated_at) VALUES (?, 4, ?, 11, 12)',
      [bookId, '旧书评正文'],
    );
    await database.customStatement(
      "DELETE FROM settings WHERE key='bookReviews.ratingUnit'",
    );
    await database.close();
    for (var opening = 0; opening < 2; opening++) {
      database = await AppDatabase.open(file);
      final review = await database.select(database.bookReviews).getSingle();
      expect(
        (review.rating, review.content, review.createdAt, review.updatedAt),
        (8, '旧书评正文', 11, 12),
      );
      await database.close();
    }
  });

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
      1,
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

  for (final legacyVersion in [1, 2]) {
    test('开发库 V$legacyVersion 原地归并：保留用户记录，编辑数据跨两次开库可用', () async {
      final file = await _temporaryDatabaseFile();
      final bookId = await _seedDevelopmentDatabase(file, legacyVersion);
      for (var opening = 1; opening <= 2; opening++) {
        final database = await AppDatabase.open(file);
        try {
          await _expectUserRows(database, bookId);
          final version = await database
              .customSelect('PRAGMA user_version')
              .getSingle();
          expect(version.read<int>('user_version'), 1);
          if (legacyVersion == 1 && opening == 1) {
            expect(await database.select(database.editDrafts).get(), isEmpty);
            expect(await database.select(database.editVersions).get(), isEmpty);
            await _writeEdits(database, bookId);
          }
          final draft = await database.select(database.editDrafts).getSingle();
          expect(
            (
              draft.bookId,
              draft.baseRevision,
              draft.sourcePath,
              draft.directory,
              draft.updatedAt,
            ),
            (bookId, 'test-content', 'books/原书.epub', 'edits/草稿', 19),
          );
          final edit = await database.select(database.editVersions).getSingle();
          expect(
            (
              edit.bookId,
              edit.kind,
              edit.revision,
              edit.sourcePath,
              edit.summary,
              edit.createdAt,
            ),
            (bookId, 'original', '原修订', 'edits/原版.epub', '原版', 18),
          );
          expect(
            await database.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
        } finally {
          await database.close();
        }
      }
    });
  }

  for (final version in [0, 1, 2, 3]) {
    test('非空无版本、结构不符或未知版本：拒开 V$version 不改写文件', () async {
      final file = await _temporaryDatabaseFile();
      await _seedDevelopmentDatabase(file, version == 1 ? 1 : 2);
      final raw = sqlite.sqlite3.open(file.path);
      if (version == 1 || version == 2) {
        raw.execute('ALTER TABLE annotations RENAME COLUMN note TO other_note');
      }
      raw.execute('PRAGMA user_version = $version');
      raw.close();
      final before = await file.readAsBytes();
      final database = await AppDatabase.open(file);
      try {
        await expectLater(database.warmUp(), throwsStateError);
      } finally {
        await database.close();
      }
      expect(await file.readAsBytes(), before);
    });
  }

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
