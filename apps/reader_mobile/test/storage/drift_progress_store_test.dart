import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_store.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

Uint8List _imageBook() {
  final archive = ZipDecoder().decodeBytes(buildTestEpub(title: '纯图片进度'));
  final chapter = utf8.encode(
    '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
    '<img id="image-1" src="one.png"/>'
    '<img id="image-2" src="two.png"/>'
    '<img id="image-3" src="three.png"/>'
    '</body></html>',
  );
  archive.addFile(ArchiveFile('OEBPS/c1.xhtml', chapter.length, chapter));
  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCZkAAAAASUVORK5CYII=',
  );
  final manifest = StringBuffer();
  for (final name in ['one.png', 'two.png', 'three.png']) {
    archive.addFile(ArchiveFile('OEBPS/$name', pixel.length, pixel));
    manifest.write('<item id="$name" href="$name" media-type="image/png"/>');
  }
  final opf = utf8.encode(
    utf8
        .decode(archive.findFile('OEBPS/content.opf')!.content)
        .replaceFirst('</manifest>', '$manifest</manifest>'),
  );
  archive.addFile(ArchiveFile('OEBPS/content.opf', opf.length, opf));
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

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
    final book = (await db.select(db.books).get()).single;
    await store.save(
      entry.id,
      ReaderProgress(
        spineIndex: 1,
        pageIndex: 0,
        readingPercent: 0.375,
        contentRevision: book.contentRevision,
      ),
    );
    final row = (await db.select(db.readingProgress).get()).single;
    expect(row.percent, closeTo(37.5, 1e-9));
    expect((await store.load(entry.id))?.readingPercent, closeTo(0.375, 1e-9));
    expect((await store.load(entry.id))?.contentRevision, book.contentRevision);
  });

  test('旧内容锚点的百分比按字节权重校正且保留原始 CFI', () async {
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
    final metadata = jsonDecode(row.anchorJson!) as Map<String, dynamic>
      ..remove('progressAlgorithmVersion')
      ..remove('readingPercent');
    await (db.update(
      db.readingProgress,
    )..where((table) => table.bookId.equals(book.id))).write(
      ReadingProgressCompanion(
        anchorJson: Value(jsonEncode(metadata)),
        percent: const Value(99.0),
      ),
    );
    final loaded = await store.load(entry.id);
    expect(loaded?.cfi, cfi);
    expect(
      loaded?.readingPercent,
      closeTo(source.readingPercentForCfi(cfi)!, 1e-9),
    );
    expect(
      (await store.snapshot())[entry.id]?.readingPercent,
      loaded?.readingPercent,
    );
    final calibrated = (await db.select(db.readingProgress).get()).single;
    expect(calibrated.percent, closeTo(loaded!.readingPercent! * 100, 1e-9));
    expect(
      (jsonDecode(calibrated.anchorJson!) as Map)['progressAlgorithmVersion'],
      1,
    );
  });

  test('阅读权重仅取条目元数据，旧字数字段保持原值', () async {
    final entry = await library.importBytes(
      buildMultiChapterEpub(
        chapters: <String>['第一章' * 80, '第二章' * 40, '第三章' * 60],
        title: '轻量进度权重',
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
    final release = await store.bindSource(
      entry.id,
      source,
      book.contentRevision!,
    );
    addTearDown(release);
    final weights = await loadBookProgressIndex(db, book);
    expect(weights, same(source.progressIndex));
    expect(weights!.estimated, isFalse);
    expect(weights.totalWeight, greaterThan(0));
    expect(source.anchorPreparationCount, 0);
    final retainedRows = await (db.select(
      db.spineItems,
    )..where((table) => table.bookId.equals(book.id))).get();
    expect(
      retainedRows.every((row) => row.charCount == 0 && row.charStart == 0),
      isTrue,
    );
    expect((await db.select(db.books).get()).single.charCount, book.charCount);
    final markers = await (db.select(
      db.settingsTable,
    )..where((table) => table.key.like('character-index-v2:%'))).get();
    expect(markers, isEmpty);

    final chapter = await source.loadAnchorChapter(1);
    final cfi = chapter.cfiAt(chapter.text.length ~/ 2)!;
    final percent = source.readingPercentForCfi(cfi)!;
    await store.save(
      entry.id,
      ReaderProgress(
        spineIndex: 1,
        pageIndex: 2,
        cfi: cfi,
        contentRevision: book.contentRevision,
        readingPercent: percent,
      ),
    );
    expect((await store.load(entry.id))?.readingPercent, percent);
    expect(source.anchorPreparationCount, 1);
  });

  test('来源缺失的旧书各自按自己的章节数降级', () async {
    for (final entry in [('甲', 2), ('乙', 5)]) {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              uuid: entry.$1,
              title: entry.$1,
              contentDir: dir.path,
              spineCount: Value(entry.$2),
              createdAt: 1,
            ),
          );
    }
    final books = await db.select(db.books).get();
    expect((await loadBookProgressIndex(db, books[0]))?.chapterCount, 2);
    expect((await loadBookProgressIndex(db, books[1]))?.chapterCount, 5);
  });

  test('纯图片章保存真实元素 CFI，恢复位置和比例一致', () async {
    final entry = await library.importBytes(_imageBook());
    final book = (await db.select(db.books).get()).single;
    final source = await EpubChapterSource.openFile(File(entry.filePath));
    addTearDown(source.close);
    final release = await store.bindSource(
      entry.id,
      source,
      book.contentRevision!,
    );
    addTearDown(release);
    final cfi = (await source.prepareCfiForReadingPercent(0.5))!;
    expect(source.anchorChapter(0).text, isEmpty);
    expect(source.isValidElementCfi(cfi), isTrue, reason: '真实图片元素 $cfi');
    final percent = source.readingPercentForCfi(cfi)!;
    await store.save(
      entry.id,
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 1,
        cfi: cfi,
        contentRevision: book.contentRevision,
        readingPercent: percent,
      ),
    );
    final row = (await db.select(db.readingProgress).get()).single;
    final anchor = AnchorRecord.decode(row.anchorJson)!;
    expect(anchor.original.start.cfi, cfi);
    expect(anchor.original.start.chapterLength, 0);
    expect(anchor.original.quote, isEmpty);
    expect((await store.load(entry.id))?.cfi, cfi);
    expect((await store.load(entry.id))?.readingPercent, percent);
    final metadata = jsonDecode(row.anchorJson!) as Map<String, dynamic>
      ..remove('progressAlgorithmVersion')
      ..remove('readingPercent');
    await (db.update(
      db.readingProgress,
    )..where((table) => table.bookId.equals(book.id))).write(
      ReadingProgressCompanion(
        anchorJson: Value(jsonEncode(metadata)),
        percent: const Value(99),
      ),
    );
    release();
    source.close();
    final restored = await store.load(entry.id);
    expect(restored?.cfi, cfi);
    expect(restored?.readingPercent, percent);
    await expectLater(
      store.save(
        entry.id,
        ReaderProgress(
          spineIndex: 0,
          pageIndex: 0,
          cfi: 'epubcfi(/6/2!/4/9998:0)',
          contentRevision: book.contentRevision,
        ),
      ),
      throwsStateError,
    );
    expect((await store.load(entry.id))?.cfi, cfi);
  });

  test('原书文件恢复后不继续复用临时等权降级', () async {
    final entry = await library.importBytes(
      buildMultiChapterEpub(chapters: ['甲' * 10, '乙' * 200], title: '来源恢复'),
    );
    final book = (await db.select(db.books).get()).single;
    final file = File(entry.filePath);
    final held = await file.rename('${file.path}.held');
    expect((await loadBookProgressIndex(db, book))?.estimated, isTrue);
    await held.rename(file.path);
    final recovered = await loadBookProgressIndex(db, book);
    expect(recovered?.estimated, isFalse);
    expect(
      recovered!.chapterWeights[1],
      greaterThan(recovered.chapterWeights[0]),
    );
  });
}
