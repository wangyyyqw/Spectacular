import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_store.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/api.dart' show TocEntry;
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';
import '../reader/support/css_chapter_book.dart';

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
      ReaderProgress(
        spineIndex: 1,
        pageIndex: 3,
        approximate: true,
        contentRevision: entry.contentRevision,
        readingPercent: 0,
      ),
    );
    final row = (await db.select(db.readingProgress).get()).single;
    expect(row.spineIndex, 1);
    expect(row.pageIndex, 3);
    expect(row.locatorCfi, isEmpty);
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
      ReaderProgress(
        spineIndex: 2,
        pageIndex: 5,
        approximate: true,
        contentRevision: entry.contentRevision,
        readingPercent: 0,
      ),
    );
  });

  test('连续滚动的页内偏移通过锚点元数据恢复', () async {
    final entry = await library.importBytes(buildTestEpub(title: '滚动进度书'));
    await store.save(
      entry.id,
      const ReaderProgress(spineIndex: 1, pageIndex: 3, scrollOffset: 87.5),
    );

    expect(
      await store.load(entry.id),
      ReaderProgress(
        contentRevision: entry.contentRevision,
        readingPercent: 0,
        spineIndex: 1,
        pageIndex: 3,
        scrollOffset: 87.5,
        approximate: true,
      ),
    );
    final row = (await db.select(db.readingProgress).get()).single;
    expect((jsonDecode(row.anchorJson!) as Map)['scrollOffset'], 87.5);
  });

  test('读完状态保存后可读回并进入快照', () async {
    final entry = await library.importBytes(buildTestEpub(title: '读完书'));
    await store.save(
      entry.id,
      const ReaderProgress(spineIndex: 2, pageIndex: 0, finished: true),
    );

    expect(
      await store.load(entry.id),
      ReaderProgress(
        contentRevision: entry.contentRevision,
        readingPercent: 0,
        spineIndex: 2,
        pageIndex: 0,
        finished: true,
        approximate: true,
      ),
    );
    expect(
      (await store.snapshot())[entry.id],
      ReaderProgress(
        contentRevision: entry.contentRevision,
        readingPercent: 0,
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
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 1,
        approximate: true,
        contentRevision: first.contentRevision,
        readingPercent: 0,
      ),
    );
    expect(
      snapshot[second.id],
      ReaderProgress(
        spineIndex: 1,
        pageIndex: 2,
        approximate: true,
        contentRevision: second.contentRevision,
        readingPercent: 0,
      ),
    );

    await store.clear(first.id);
    expect(await store.load(first.id), isNull);
    expect((await store.snapshot()).containsKey(first.id), isFalse);
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

  test('真实锚点和字节比例保存后直接读回，查询不改写记录', () async {
    final entry = await library.importBytes(buildTestEpub(title: '锚点比例'));
    final source = await EpubChapterSource.openFile(File(entry.filePath));
    addTearDown(source.close);
    final chapter = await source.loadAnchorChapter(0);
    final cfi = chapter.cfiAt(chapter.text.length ~/ 2)!;
    await store.save(
      entry.id,
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 0,
        cfi: cfi,
        contentRevision: entry.contentRevision,
      ),
    );
    final saved = (await db.select(db.readingProgress).get()).single;
    final loaded = await store.load(entry.id);
    expect(loaded?.cfi, cfi);
    expect(
      loaded?.readingPercent,
      closeTo(source.readingPercentForCfi(cfi)!, 1e-9),
    );
    expect((await store.snapshot())[entry.id], loaded);
    expect(
      (await db.select(db.readingProgress).get()).single.toJson(),
      saved.toJson(),
    );
  });

  test('阅读权重仅取条目元数据，字符统计独立保存', () async {
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
      book.contentRevision,
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

  test('来源缺失时各书按自己的章节数降级', () async {
    for (final entry in [('甲', 2), ('乙', 5)]) {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              uuid: entry.$1,
              contentRevision: 'test-content-${entry.$1}',
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
      book.contentRevision,
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

  test('目录跳到混合图文元素后保存并重开，保留元素 CFI 和原文进度', () async {
    final entry = await library.importBytes(
      buildCssChapterBook(
        body:
            '<p>${'前文。' * 100}</p><h2 id="title">目标标题</h2>'
            '<p>${'标题后。' * 60}</p><div id="picture">'
            '<img id="leaf" src="../Images/p.png" width="120" height="180"/>'
            '</div><p>${'后文。' * 60}</p>',
        binaryFiles: {
          'OEBPS/Images/p.png': base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCZkAAAAASUVORK5CYII=',
          ),
        },
      ),
    );
    final source = await EpubChapterSource.openFile(File(entry.filePath));
    addTearDown(source.close);
    final release = await store.bindSource(
      entry.id,
      source,
      entry.contentRevision!,
    );
    addTearDown(release);
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: entry.id,
      contentRevision: entry.contentRevision,
    );
    addTearDown(session.dispose);
    await session.open();
    for (final id in ['title', 'picture', 'leaf']) {
      await session.jumpToTocEntry(
        TocEntry(title: id, spineIndex: 0, fragment: id),
      );
      final cfi = source.document
          .parseDocument(0)
          .elementById(id)!
          .cfi
          .serialize();
      expect(session.readingCfi, cfi);
      expect(session.readingPercent, isNotNull);
      await session.flushProgress();
      final loaded = (await store.load(entry.id))!;
      expect(loaded.cfi, cfi);
      expect(loaded.readingPercent, closeTo(session.readingPercent!, 1e-9));
      final reopened = ReaderSession(
        source: source,
        store: store,
        bookId: entry.id,
        contentRevision: entry.contentRevision,
      );
      try {
        await reopened.open();
        expect(reopened.readingCfi, cfi);
        expect(reopened.readingPercent, closeTo(loaded.readingPercent!, 1e-9));
        expect(reopened.page?.pageIndex, session.page?.pageIndex);
      } finally {
        reopened.dispose();
      }
    }
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
