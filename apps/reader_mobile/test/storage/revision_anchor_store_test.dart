import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/position/text_length.dart';
import 'package:reader_mobile/library/revision_anchor_index.dart';
import 'package:reader_mobile/library/revision_anchor_store.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_annotation_store.dart';
import 'package:reader_mobile/storage/drift_bookmark_store.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

void main() {
  late Directory directory;
  late AppDatabase db;
  late AnchorBook index;
  late BookRow book;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('revision-anchor-store');
    db = AppDatabase(NativeDatabase.memory());
    final bytes = buildTestEpub(
      paragraphs: ['这是旧版本中需要继承的正文，包含书签与笔记。', '这里是用于重新选择的另一段正文。'],
    );
    index = await buildRevisionAnchorBook(bytes);
    final path = '${directory.path}/source.epub';
    await File(path).writeAsBytes(bytes);
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            uuid: 'current',
            title: '更新测试书',
            contentDir: directory.path,
            sourcePath: Value(path),
            contentRevision: index.revision,
            createdAt: 1,
          ),
        );
    book = (await db.select(db.books).get()).single;
  });

  tearDown(() async {
    await db.close();
    directory.deleteSync(recursive: true);
  });

  String cfi(int offset) => index.anchorAt(0, offset)!.start.cfi;

  Future<double> percentAt(int spine, int offset) async {
    final source = await EpubChapterSource.openFile(File(book.sourcePath!));
    try {
      await source.loadAnchorChapter(spine);
      return source.readingPercentForCfi(
        index.anchorAt(spine, offset)!.start.cfi,
      )!;
    } finally {
      source.close();
    }
  }

  Future<EpubChapterSource> bindMultiChapterSource() async {
    final bytes = buildMultiChapterEpub(
      chapters: ['第一章用于连续保存进度和笔记。', '中间章节的内容必须完整保留。', '最后一章用于恢复最新位置。'],
    );
    index = await buildRevisionAnchorBook(bytes);
    await File(book.sourcePath!).writeAsBytes(bytes);
    await (db.update(
      db.books,
    )..where((table) => table.id.equals(book.id))).write(
      BooksCompanion(
        contentRevision: Value(index.revision),
        spineCount: Value(index.chapters.length),
        charCount: Value(
          index.chapters.fold(
            0,
            (sum, chapter) =>
                sum + TextLengthScanner.countPlainText(chapter.text),
          ),
        ),
      ),
    );
    var before = 0;
    for (final chapter in index.chapters) {
      await db
          .into(db.spineItems)
          .insert(
            SpineItemsCompanion.insert(
              bookId: book.id,
              spineIndex: chapter.spineIndex,
              href: chapter.href,
              charCount: Value(TextLengthScanner.countPlainText(chapter.text)),
              charStart: Value(before),
            ),
          );
      before += TextLengthScanner.countPlainText(chapter.text);
    }
    final source = await EpubChapterSource.open(bytes, verifyCrc: false);
    final release = await bindReadingAnchorSource(
      db,
      'current',
      source,
      index.revision,
    );
    addTearDown(() {
      release();
      source.close();
    });
    await File(book.sourcePath!).rename('${book.sourcePath!}.moved');
    return source;
  }

  test('借用阅读源保存多章进度与笔记无需重读原文件，恢复最新位置和准确百分比', () async {
    final source = await bindMultiChapterSource();
    final progress = DriftProgressStore(db);
    final annotations = DriftAnnotationStore(db, 'current');
    ReaderProgress? latest;
    for (var spine = 0; spine < index.chapters.length; spine++) {
      latest = ReaderProgress(
        spineIndex: spine,
        pageIndex: spine + 1,
        cfi: index.anchorAt(spine, 8)!.start.cfi,
        contentRevision: index.revision,
      );
      await progress.save('current', latest);
      final selection = index.capture(
        index.anchorAt(spine, 9)!.start.cfi,
        endCfi: index.anchorAt(spine, 15)!.start.cfi,
      )!;
      final added = await annotations.add(
        type: ReaderAnnotationType.thought,
        startCfi: selection.start.cfi,
        endCfi: selection.end!.cfi,
        quote: selection.quote,
        note: '第${spine + 1}章笔记',
      );
      expect(added?.relocationStatus, 'verified');
    }
    final restored = await DriftProgressStore(db).load('current');
    expect(restored!.cfi, latest!.cfi);
    expect(restored.pageIndex, latest.pageIndex);
    expect(restored.contentRevision, latest.contentRevision);
    expect(await annotations.list(), hasLength(3));
    final row = (await db.select(db.readingProgress).get()).single;
    expect(
      row.percent,
      closeTo(source.readingPercentForCfi(latest.cfi)! * 100, 0.001),
    );
    expect(restored.readingPercent, closeTo(row.percent / 100, 0.001));
  });

  test('借用阅读源保存跨章笔记保留中间章节和完整引用', () async {
    await bindMultiChapterSource();
    final start = index.anchorAt(0, 8)!.start.cfi;
    final end = index.anchorAt(2, 12)!.start.cfi;
    final quote =
        index.chapters[0].text.substring(8) +
        index.chapters[1].text +
        index.chapters[2].text.substring(0, 12);
    final annotations = DriftAnnotationStore(db, 'current');
    final added = await annotations.add(
      type: ReaderAnnotationType.thought,
      startCfi: start,
      endCfi: end,
      quote: quote,
      note: '跨章笔记',
    );
    expect(added?.relocationStatus, 'verified');
    final stored = (await annotations.list()).single;
    final anchor = AnchorRecord.decode(stored.anchorData)!.effective;
    expect(anchor.start.cfi, start);
    expect(anchor.end!.cfi, end);
    expect(anchor.quote, quote);
    expect(anchor.quote, contains('中间章节的内容必须完整保留。'));
    expect(stored.note, '跨章笔记');
  });

  test('当前身份优先，书籍修订标识仅唯一时可读取', () async {
    final otherId = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            uuid: 'other',
            title: '另一书',
            contentDir: 'other',
            createdAt: 2,
            contentRevision: 'other-content',
          ),
        );
    Future<void> alias(String value, int id) => db
        .into(db.bookIdAliases)
        .insert(BookIdAliasesCompanion.insert(aliasId: value, bookId: id));
    await alias('current', otherId);
    await alias('history', book.id);
    expect((await resolveBookRow(db, 'current'))!.id, book.id);
    expect((await resolveBookRow(db, 'history'))!.id, book.id);
    expect(await resolveBookRow(db, 'history', allowAliases: false), isNull);
    await alias('history', otherId);
    expect(await resolveBookRow(db, 'history'), isNull);
  });

  test('真实进度保留首次锚点、滚动偏移与近似状态，旧版本禁止回写', () async {
    final store = DriftProgressStore(db);
    final initial = ReaderProgress(
      spineIndex: 0,
      pageIndex: 1,
      cfi: cfi(5),
      contentRevision: index.revision,
      scrollOffset: 12.5,
    );
    await store.save('current', initial);
    final first = (await db.select(db.readingProgress).get()).single;
    final original = AnchorRecord.decode(first.anchorJson)!.original.toJson();
    expect(first.locatorCfi, initial.cfi);
    expect(first.percent, closeTo(await percentAt(0, 5) * 100, 0.001));
    final loaded = (await store.load('current'))!;
    expect(loaded.cfi, initial.cfi);
    expect(loaded.scrollOffset, initial.scrollOffset);
    expect(loaded.approximate, isFalse);
    expect(loaded.readingPercent, closeTo(await percentAt(0, 5), 0.001));
    await store.save(
      'current',
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 2,
        cfi: cfi(15),
        contentRevision: index.revision,
        approximate: true,
      ),
    );
    final second = (await db.select(db.readingProgress).get()).single;
    expect(AnchorRecord.decode(second.anchorJson)!.original.toJson(), original);
    expect((await store.load('current'))!.approximate, isTrue);
    await store.save(
      'current',
      const ReaderProgress(spineIndex: 0, pageIndex: 0, finished: true),
    );
    final marked = (await db.select(db.readingProgress).get()).single;
    expect(marked.anchorJson, second.anchorJson);
    expect(marked.locatorCfi, second.locatorCfi);
    await (db.update(db.books)..where((table) => table.id.equals(book.id)))
        .write(const BooksCompanion(contentRevision: Value('new-revision')));
    await store.save('current', initial);
    expect(
      (await db.select(db.readingProgress).get()).single.toJson(),
      marked.toJson(),
    );
  });

  test('强制更换bookId后，旧ID能读取但不能保存或清除新版数据', () async {
    final store = DriftProgressStore(db);
    await store.save(
      'current',
      const ReaderProgress(spineIndex: 0, pageIndex: 3),
    );
    await db
        .into(db.bookIdAliases)
        .insert(
          BookIdAliasesCompanion.insert(aliasId: 'current', bookId: book.id),
        );
    await (db.update(db.books)..where((table) => table.id.equals(book.id)))
        .write(const BooksCompanion(uuid: Value('new-id')));
    await store.save(
      'current',
      const ReaderProgress(spineIndex: 0, pageIndex: 9),
    );
    await store.clear('current');
    expect((await store.load('new-id'))!.pageIndex, 3);
    expect((await store.load('current'))!.pageIndex, 3);
  });

  test('手动重新定位只改当前锚点及CFI，原引用笔记样式时间保持', () async {
    final store = DriftAnnotationStore(db, 'current');
    final annotation = await store.add(
      type: ReaderAnnotationType.thought,
      startCfi: cfi(8),
      endCfi: cfi(18),
      quote: '原引用原样保留',
      contextBefore: '原前文',
      contextAfter: '原后文',
      note: '笔记正文',
      color: 123,
      style: ReaderAnnotationStyle.underline,
    );
    final before = (await db.select(db.annotations).get()).single;
    final record = AnchorRecord.decode(before.anchorJson)!;
    await (db.update(
      db.annotations,
    )..where((table) => table.id.equals(before.id))).write(
      AnnotationsCompanion(
        anchorJson: Value(
          AnchorRecord(
            original: record.original,
            status: 'pending',
            reason: '重复引用',
          ).encode(),
        ),
      ),
    );
    expect((await store.list()).single.needsRelocation, isTrue);
    await store.relocate(annotation!.id, startCfi: cfi(25), endCfi: cfi(35));
    final after = (await db.select(db.annotations).get()).single;
    final repaired = AnchorRecord.decode(after.anchorJson)!;
    expect(repaired.original.toJson(), record.original.toJson());
    expect(repaired.effective.start.cfi, cfi(25));
    expect(repaired.isResolved, isTrue);
    expect(after.quote, before.quote);
    expect(after.note, before.note);
    expect(after.color, before.color);
    expect(after.style, before.style);
    expect(after.contextBefore, before.contextBefore);
    expect(after.contextAfter, before.contextAfter);
    expect(after.createdAt, before.createdAt);
    expect(after.updatedAt, before.updatedAt);
    expect((await store.list()).single.anchorData, after.anchorJson);
  });

  test('书签捕获真实正文，重新定位保留原标签和原始锚点', () async {
    final store = DriftBookmarkStore(db, 'current');
    final bookmark = await store.add(
      cfi: cfi(10),
      spineIndex: 0,
      label: '我的标签',
    );
    final before = (await db.select(db.annotations).get()).single;
    final original = AnchorRecord.decode(before.anchorJson)!.original;
    expect(original.quote, isNot('我的标签'));
    await store.relocate(bookmark!.id, cfi: cfi(25));
    final after = (await db.select(db.annotations).get()).single;
    expect(after.quote, before.quote);
    expect(after.createdAt, before.createdAt);
    expect(
      AnchorRecord.decode(after.anchorJson)!.original.toJson(),
      original.toJson(),
    );
  });

  test('内容更新后旧标注和书签存储实例拒绝修改及删除', () async {
    final annotations = DriftAnnotationStore(db, 'current');
    final bookmarks = DriftBookmarkStore(db, 'current');
    final annotation = await annotations.add(
      type: ReaderAnnotationType.thought,
      startCfi: cfi(8),
      endCfi: cfi(18),
      quote: '引用',
      note: '笔记',
    );
    final bookmark = await bookmarks.add(
      cfi: cfi(10),
      spineIndex: 0,
      label: '书签',
    );
    await (db.update(db.books)..where((table) => table.id.equals(book.id)))
        .write(const BooksCompanion(contentRevision: Value('new-revision')));
    await annotations.update(annotation!.id, note: '过期回写');
    await annotations.remove(annotation.id);
    await bookmarks.remove(bookmark!.id);
    expect(
      await annotations.add(
        type: ReaderAnnotationType.mark,
        startCfi: cfi(25),
        endCfi: cfi(35),
        quote: '新引用',
      ),
      isNull,
    );
    final rows = await db.select(db.annotations).get();
    expect(rows, hasLength(2));
    expect(rows.singleWhere((row) => row.id == annotation.id).note, '笔记');
    await expectLater(
      bookmarks.relocate(bookmark.id, cfi: cfi(20)),
      throwsA(isA<FormatException>()),
    );
  });

  test('存储实例绑定内容摘要，文件更新后不得回写先前会话', () async {
    final bookmarks = DriftBookmarkStore(db, 'current');
    final annotations = DriftAnnotationStore(db, 'current');
    final progress = DriftProgressStore(db);
    final value = ReaderProgress(
      spineIndex: 0,
      pageIndex: 1,
      cfi: cfi(10),
      contentRevision: index.revision,
    );
    await progress.save('current', value);
    final restored = (await progress.load('current'))!;
    expect(restored.cfi, value.cfi);
    expect(restored.pageIndex, value.pageIndex);
    expect(restored.contentRevision, value.contentRevision);
    expect(restored.readingPercent, closeTo(await percentAt(0, 10), 0.001));
    await (db.update(db.books)..where((table) => table.id.equals(book.id)))
        .write(const BooksCompanion(contentRevision: Value('new-revision')));
    expect(
      await bookmarks.add(cfi: cfi(10), spineIndex: 0, label: '旧会话'),
      isNull,
    );
    expect(
      await annotations.add(
        type: ReaderAnnotationType.mark,
        startCfi: cfi(10),
        endCfi: cfi(20),
        quote: '旧引用',
      ),
      isNull,
    );
    await progress.save(
      'current',
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 9,
        cfi: cfi(20),
        contentRevision: index.revision,
      ),
    );
    expect((await progress.load('current'))!.pageIndex, 1);
  });

  test('合法偏移对应了其他文字也不能把原引用标为已验证', () async {
    final annotations = DriftAnnotationStore(db, 'current');
    final added = await annotations.add(
      type: ReaderAnnotationType.mark,
      startCfi: cfi(10),
      endCfi: cfi(20),
      quote: '这里并不是选区文字',
      contextBefore: '原前文',
      contextAfter: '原后文',
    );
    expect(added!.relocationStatus, 'pending');
    final record = AnchorRecord.decode(added.anchorData)!;
    expect(record.isResolved, isFalse);
    expect(record.original.quote, '这里并不是选区文字');
    expect(record.original.start.contextBefore, '原前文');
  });

  test('损坏锚点只标记待定位，读取不回填也不替换原引用', () async {
    await db
        .into(db.annotations)
        .insert(
          AnnotationsCompanion.insert(
            id: 'damaged-annotation',
            bookId: book.id,
            type: 1,
            startCfi: cfi(10),
            endCfi: cfi(20),
            quote: '原引用',
            anchorJson: const Value('{'),
            note: const Value('原笔记'),
            createdAt: 3,
            updatedAt: 4,
          ),
        );
    final annotations = DriftAnnotationStore(db, 'current');
    final listed = (await annotations.list()).single;
    expect(listed.relocationStatus, 'pending');
    expect(listed.quote, '原引用');
    await expectLater(
      annotations.relocate(
        'damaged-annotation',
        startCfi: cfi(25),
        endCfi: cfi(35),
      ),
      throwsFormatException,
    );
    final row = (await db.select(db.annotations).get()).single;
    expect(row.anchorJson, '{');
    expect(row.startCfi, cfi(10));
    expect(row.endCfi, cfi(20));
    expect(row.note, '原笔记');
    expect(row.updatedAt, 4);
  });

  test('无效CFI进度不清除最近成功定位与原始锚点', () async {
    final progress = DriftProgressStore(db);
    await progress.save(
      'current',
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 1,
        cfi: cfi(10),
        contentRevision: index.revision,
      ),
    );
    final saved = (await db.select(db.readingProgress).get()).single;
    await expectLater(
      progress.save(
        'current',
        ReaderProgress(
          spineIndex: 0,
          pageIndex: 9,
          cfi: 'epubcfi(/6/99999!/4/2:10000)',
          contentRevision: index.revision,
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      (await db.select(db.readingProgress).get()).single.toJson(),
      saved.toJson(),
    );
  });

  test('缺失原文件的新记录不伪造可靠锚点', () async {
    final source = File(book.sourcePath!);
    final bytes = await source.readAsBytes();
    await source.delete();
    final store = DriftBookmarkStore(db, 'current');
    final bookmark = await store.add(
      cfi: cfi(10),
      spineIndex: 0,
      label: '书签标签',
    );
    expect(bookmark, isNotNull);
    expect(bookmark!.relocationStatus, 'pending');
    expect((await db.select(db.annotations).get()).single.anchorJson, isNull);
    await source.writeAsBytes(bytes);
    final recovered = await store.add(
      cfi: cfi(20),
      spineIndex: 0,
      label: '恢复后',
    );
    expect(recovered!.relocationStatus, 'verified');
  });
}
