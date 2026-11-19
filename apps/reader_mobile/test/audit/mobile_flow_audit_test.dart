import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/search/scan_search_service.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实 SQLite 重开后恢复书库、进度、书评和阅读记录，软删除后重导入恢复', () async {
    final root = Directory.systemTemp.createTempSync('mobile-audit-db');
    final file = File('${root.path}/audit.sqlite');
    var db = await AppDatabase.open(file);
    addTearDown(() async {
      await db.close();
      root.deleteSync(recursive: true);
    });
    LibraryStore library() =>
        LibraryStore(database: db, directoryProvider: () async => root);
    final bytes = buildTestEpub(title: '审计书籍', identifier: 'audit-persist');
    final entry = await library().importBytes(bytes);
    await library().touchLastRead(entry.id);
    const progress = ReaderProgress(
      spineIndex: 0,
      pageIndex: 2,
      finished: true,
    );
    await DriftProgressStore(db).save(entry.id, progress);
    await DriftBookReviewStore(db).save(entry.id, rating: 4, content: '审计书评');
    final startedAt = DateTime(2026, 11, 4, 10);
    await DriftReadingSessionStore(db).add(
      bookId: entry.id,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 3)),
      pageTurns: 2,
      charactersRead: 60,
    );
    await db.close();
    db = await AppDatabase.open(file);
    expect((await library().list()).single.lastReadAt, isNotNull);
    expect(await library().finishedBookIds(), {entry.id});
    expect(
      await DriftProgressStore(db).load(entry.id),
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 2,
        finished: true,
        approximate: true,
        contentRevision: entry.contentRevision,
        readingPercent: 0,
      ),
    );
    expect((await DriftBookReviewStore(db).snapshot())[entry.id]?.rating, 4);
    expect(
      (await DriftReadingSessionStore(db).list()).single.charactersRead,
      60,
    );
    expect(
      (await db.customSelect('PRAGMA integrity_check').getSingle())
          .data
          .values
          .single,
      'ok',
    );

    await library().remove(entry.id);
    expect(await library().list(), isEmpty);
    expect(await library().finishedBookIds(), isEmpty);
    expect(File(entry.filePath).existsSync(), isFalse);
    expect(await DriftBookReviewStore(db).snapshot(), isEmpty);
    await library().importBytes(bytes);
    expect(await library().finishedBookIds(), {entry.id});
    expect(
      await DriftProgressStore(db).load(entry.id),
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 2,
        finished: true,
        approximate: true,
        contentRevision: entry.contentRevision,
        readingPercent: 0,
      ),
    );
    expect(
      (await DriftBookReviewStore(db).snapshot())[entry.id]?.content,
      '审计书评',
    );
    expect((await DriftReadingSessionStore(db).list()).single.pageTurns, 2);
  });

  test('扫描搜索遵守结果上限，命中可定位，新查询与释放取消旧扫描', () async {
    final source = await EpubChapterSource.open(
      buildMultiChapterEpub(chapters: ['审计词 前文 审计词', '第二章 审计词', '第三章 审计词']),
    );
    addTearDown(source.close);
    final search = ScanSearchService(source: source, maxResults: 2);
    final results = await search.search('审计词');
    expect(results, hasLength(2));
    expect(results.map((result) => result.spineIndex), [0, 0]);
    expect(results[0].charOffset, lessThan(results[1].charOffset));
    expect(await search.resolveCfi(results.last), startsWith('epubcfi('));

    final oldStream = search.searchStream('审计词');
    expect(await search.search('第二章'), hasLength(1));
    expect(await oldStream.toList(), isEmpty);
    search.dispose();
    expect(await search.search('审计词'), isEmpty);
  });
}
