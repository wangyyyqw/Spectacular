import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late LibraryStore library;
  late DriftProgressStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('drift-progress');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => dir);
    store = DriftProgressStore(db);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('保存后读回：spine/page 与 updated_at 落库（P4-10）', () async {
    final entry = await library.importBytes(buildTestEpub(title: '进度书'));
    await store.save(
      entry.id,
      const ReaderProgress(spineIndex: 1, pageIndex: 3),
    );

    final loaded = await store.load(entry.id);
    expect(
      loaded,
      const ReaderProgress(spineIndex: 1, pageIndex: 3, approximate: true),
    );
    final row = (await db.select(db.readingProgress).get()).single;
    expect(row.spineIndex, 1);
    expect(row.pageIndex, 3);
    expect(row.locatorCfi, 'spine:1/page:3');
    expect(row.updatedAt, greaterThan(0));
  });

  test('重复保存是 upsert，不产生第二行', () async {
    final entry = await library.importBytes(buildTestEpub(title: '进度书2'));
    await store.save(
      entry.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 1),
    );
    await store.save(
      entry.id,
      const ReaderProgress(spineIndex: 2, pageIndex: 5),
    );
    final rows = await db.select(db.readingProgress).get();
    expect(rows, hasLength(1));
    expect(
      await store.load(entry.id),
      const ReaderProgress(spineIndex: 2, pageIndex: 5, approximate: true),
    );
  });

  test('连续滚动的页内偏移可从位置串恢复', () async {
    final entry = await library.importBytes(buildTestEpub(title: '滚动进度书'));
    await store.save(
      entry.id,
      const ReaderProgress(spineIndex: 1, pageIndex: 3, scrollOffset: 87.5),
    );

    expect(
      await store.load(entry.id),
      const ReaderProgress(
        spineIndex: 1,
        pageIndex: 3,
        scrollOffset: 87.5,
        approximate: true,
      ),
    );
    final row = (await db.select(db.readingProgress).get()).single;
    expect(row.locatorCfi, 'spine:1/page:3/scroll:87.5');
  });

  test('读完状态保存后可读回并进入快照', () async {
    final entry = await library.importBytes(buildTestEpub(title: '读完书'));
    await store.save(
      entry.id,
      const ReaderProgress(spineIndex: 2, pageIndex: 0, finished: true),
    );

    expect(
      await store.load(entry.id),
      const ReaderProgress(
        spineIndex: 2,
        pageIndex: 0,
        finished: true,
        approximate: true,
      ),
    );
    expect(
      (await store.snapshot())[entry.id],
      const ReaderProgress(
        spineIndex: 2,
        pageIndex: 0,
        finished: true,
        approximate: true,
      ),
    );
    final row = (await db.select(db.readingProgress).get()).single;
    expect(row.finished, isTrue);
  });

  test('clear 删进度；snapshot 返回 uuid → 进度', () async {
    final first = await library.importBytes(buildTestEpub(title: '甲书'));
    final second = await library.importBytes(buildTestEpub(title: '乙书'));
    await store.save(
      first.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 1),
    );
    await store.save(
      second.id,
      const ReaderProgress(spineIndex: 1, pageIndex: 2),
    );

    final snapshot = await store.snapshot();
    expect(
      snapshot[first.id],
      const ReaderProgress(spineIndex: 0, pageIndex: 1, approximate: true),
    );
    expect(
      snapshot[second.id],
      const ReaderProgress(spineIndex: 1, pageIndex: 2, approximate: true),
    );

    await store.clear(first.id);
    expect(await store.load(first.id), isNull);
    expect((await store.snapshot()).containsKey(first.id), isFalse);
  });

  test('旧版 reader_progress.json 一次性迁入（幂等）', () async {
    final entry = await library.importBytes(buildTestEpub(title: '旧进度书'));
    final file = File('${dir.path}/reader_progress.json')
      ..writeAsStringSync(
        '{"${entry.id}":{"spine":2,"page":4},"missing-book":{"spine":0,"page":0}}',
      );

    expect(await store.migrateLegacyJson(file), 1, reason: '只迁存在的书');
    expect(
      await store.load(entry.id),
      const ReaderProgress(spineIndex: 2, pageIndex: 4, approximate: true),
    );
    expect(await store.migrateLegacyJson(file), 0, reason: '已有进度则跳过');
  });

  test('旧 JSON 迁移按书继续，已有新进度不被覆盖', () async {
    final existing = await library.importBytes(buildTestEpub(title: '已有进度'));
    final pending = await library.importBytes(buildTestEpub(title: '待迁移'));
    await store.save(
      existing.id,
      const ReaderProgress(spineIndex: 1, pageIndex: 2),
    );
    final file = File('${dir.path}/reader_progress.json')
      ..writeAsStringSync(
        '{"${existing.id}":{"spine":4,"page":9},'
        '"${pending.id}":{"spine":2,"page":4}}',
      );

    expect(await store.migrateLegacyJson(file), 1);
    expect(
      await store.load(existing.id),
      const ReaderProgress(spineIndex: 1, pageIndex: 2, approximate: true),
      reason: '已有数据库进度优先',
    );
    expect(
      await store.load(pending.id),
      const ReaderProgress(spineIndex: 2, pageIndex: 4, approximate: true),
    );
    expect(await store.migrateLegacyJson(file), 0, reason: '重跑可继续且幂等');
  });

  test('保存的阅读比例按 0～1 读回，数据库保持 0～100', () async {
    final entry = await library.importBytes(buildTestEpub(title: '比例书'));
    await store.save(
      entry.id,
      const ReaderProgress(spineIndex: 1, pageIndex: 0, readingPercent: 0.375),
    );
    final row = (await db.select(db.readingProgress).get()).single;
    expect(row.percent, closeTo(37.5, 1e-9));
    expect((await store.load(entry.id))?.readingPercent, closeTo(0.375, 1e-9));
  });

  test('旧内容锚点没有附加字段时回退到 percent 列的比例', () async {
    final entry = await library.importBytes(buildTestEpub(title: '旧锚点比例'));
    final book = await (db.select(
      db.books,
    )..where((table) => table.uuid.equals(entry.id))).getSingle();
    final revision = book.contentRevision;
    expect(revision, isNotNull);
    final source = await EpubChapterSource.openFile(File(entry.filePath));
    addTearDown(source.close);
    final chapter = source.anchorChapter(0);
    final cfi = chapter.cfiAt(chapter.text.length ~/ 2)!;
    await store.save(
      entry.id,
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 0,
        cfi: cfi,
        contentRevision: revision,
      ),
    );
    final row = (await db.select(db.readingProgress).get()).single;
    expect(row.percent, greaterThan(0));
    final loaded = await store.load(entry.id);
    expect(loaded?.readingPercent, closeTo(row.percent / 100, 1e-9));
  });

  test('旧书字符索引刷新可取消、完成后复用且排除非正文', () async {
    final entry = await library.importBytes(
      buildMultiChapterEpub(
        chapters: <String>['第一章' * 80, '第二章' * 40, '第三章' * 60],
        title: '旧字符索引',
      ),
    );
    final book = await (db.select(
      db.books,
    )..where((table) => table.uuid.equals(entry.id))).getSingle();
    final source = await EpubChapterSource.openFile(File(entry.filePath));
    addTearDown(source.close);
    await (db.update(
      db.spineItems,
    )..where((table) => table.bookId.equals(book.id))).write(
      const SpineItemsCompanion(
        charCount: Value<int>(0),
        charStart: Value<int>(0),
      ),
    );
    await (db.delete(
      db.settingsTable,
    )..where((table) => table.key.like('character-index-v2:%'))).go();

    expect(
      await store.ensureCharacterIndex(
        entry.id,
        source,
        book.contentRevision!,
        isCancelled: () => true,
      ),
      isNull,
    );
    final cancelledRows = await (db.select(
      db.spineItems,
    )..where((table) => table.bookId.equals(book.id))).get();
    expect(cancelledRows.every((row) => row.charCount == 0), isTrue);
    expect(await db.select(db.settingsTable).get(), isEmpty);

    final weights = await store.ensureCharacterIndex(
      entry.id,
      source,
      book.contentRevision!,
    );
    expect(weights, isNotNull);
    expect(weights!.estimated, isFalse);
    expect(weights.total, greaterThan(0));
    final refreshedRows = await (db.select(
      db.spineItems,
    )..where((table) => table.bookId.equals(book.id))).get();
    expect(refreshedRows.every((row) => (row.charCount ?? 0) > 0), isTrue);
    final setting = await (db.select(
      db.settingsTable,
    )..where((table) => table.key.like('character-index-v2:%'))).getSingle();
    expect(setting.value, contains('"version":2'));

    final reused = await store.ensureCharacterIndex(
      entry.id,
      source,
      book.contentRevision!,
    );
    expect(reused!.total, weights.total);
    expect(reused.charCounts, weights.charCounts);
  });
}
