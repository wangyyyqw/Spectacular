import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late Directory dir;
  late AppDatabase db;
  late LibraryStore library;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('library-data-restore');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => dir);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('删书后导入修订版保留封面副本并恢复可打开的书籍', () async {
    final old = await library.importBytes(
      buildTestEpub(identifier: 'restore-cover', cover: true),
    );
    await library.remove(old.id);
    final retainedCover = (await library.retainedBooks()).single.coverPath;
    expect(retainedCover, isNotNull);
    final updated = buildTestEpub(
      identifier: 'restore-cover',
      cover: true,
      paragraphs: ['修订后的正文'],
    );
    final restored = await library.importBytes(updated);
    expect((await library.list()).single.id, old.id);
    expect(await library.readBytes(restored), updated);
    expect(restored.coverPath, retainedCover);
    expect(await File(restored.coverPath!).readAsBytes(), isNotEmpty);
  });

  test('重新导入恢复读完状态和书评编辑权限', () async {
    final bytes = buildTestEpub(identifier: 'restore-review-permission');
    final book = await library.importBytes(bytes);
    final progress = DriftProgressStore(db);
    await progress.save(
      book.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0, finished: true),
    );
    await library.reviewStore()!.save(book.id, rating: 5, content: '原有书评');
    await library.remove(book.id);
    expect(await library.finishedBookIds(), isEmpty);
    final restored = await library.importBytes(bytes);
    expect(restored.id, book.id);
    expect(await library.finishedBookIds(), {restored.id});
    expect((await progress.load(restored.id))!.finished, isTrue);
    expect(
      (await library.reviewStore()!.snapshot())[restored.id]!.content,
      '原有书评',
    );
    await library.reviewStore()!.save(restored.id, rating: 4, content: '恢复后补充');
    expect(
      (await library.reviewStore()!.snapshot())[restored.id]!.content,
      '恢复后补充',
    );
  });

  test('删书保留进度、标注、书签、书评和会话，重新导入后完整恢复', () async {
    final bytes = buildTestEpub(
      identifier: 'urn:uuid:library-data-restore',
      title: '数据恢复测试书',
    );
    final book = await library.importBytes(bytes);
    final internalId = (await library.internalBookId(book.id))!;
    await library.touchLastRead(book.id);

    final progressStore = DriftProgressStore(db);
    await progressStore.save(
      book.id,
      const ReaderProgress(spineIndex: 2, pageIndex: 7, finished: true),
    );

    final annotationStore = library.annotationStore(book.id)!;
    await annotationStore.add(
      type: ReaderAnnotationType.mark,
      startCfi: 'epubcfi(/6/4!/4/2/1:3)',
      endCfi: 'epubcfi(/6/4!/4/2/1:9)',
      quote: '保留的高亮',
      color: 0xFFFFEB3B,
    );
    await annotationStore.add(
      type: ReaderAnnotationType.thought,
      startCfi: 'epubcfi(/6/4!/4/2/1:12)',
      endCfi: 'epubcfi(/6/4!/4/2/1:18)',
      quote: '保留的笔记',
      note: '重新导入后仍应存在',
    );

    await library
        .bookmarkStore(book.id)!
        .add(cfi: 'epubcfi(/6/4!/4/2/1:0)', spineIndex: 1, label: '保留的书签');
    await library.reviewStore()!.save(book.id, rating: 5, content: '保留的书评');
    await library.readingSessionStore()!.add(
      bookId: book.id,
      startedAt: DateTime(2026, 11, 3, 8),
      endedAt: DateTime(2026, 11, 3, 8, 12),
    );

    await library.remove(book.id);

    expect(await library.list(), isEmpty);
    final deletedBook = (await db.select(db.books).get()).single;
    expect(deletedBook.id, internalId);
    expect(deletedBook.deletedAt, isNotNull);
    expect(deletedBook.sourcePath, isNull);
    expect(deletedBook.coverPath, isNull);
    expect(await db.select(db.readingProgress).get(), hasLength(1));
    expect(await db.select(db.annotations).get(), hasLength(3));
    expect(await db.select(db.bookReviews).get(), hasLength(1));
    expect(await db.select(db.readingSessions).get(), hasLength(1));
    expect(await progressStore.snapshot(), isEmpty);
    expect(await library.finishedBookIds(), isEmpty);
    // 书评不跟随书架增删：移出后仍可读到。
    expect(
      (await library.reviewStore()!.snapshot())[book.id]?.content,
      '保留的书评',
    );
    // 阅读记录同样不跟随书架增删，移出后仍可统计。
    expect(await library.readingSessionStore()!.list(), hasLength(1));

    final restored = await library.importBytes(bytes);

    expect(restored.id, book.id);
    expect(await library.internalBookId(restored.id), internalId);
    final restoredRow = (await db.select(db.books).get()).single;
    expect(restoredRow.deletedAt, isNull);
    expect(restoredRow.createdAt, book.addedAt.millisecondsSinceEpoch);
    expect(restoredRow.sourcePath, restored.filePath);
    expect(File(restored.filePath).existsSync(), isTrue);
    expect(await db.select(db.spineItems).get(), hasLength(1));
    expect((await library.list()).single.lastReadAt, isNotNull);

    expect(
      await progressStore.load(restored.id),
      ReaderProgress(
        spineIndex: 2,
        pageIndex: 7,
        finished: true,
        approximate: true,
        contentRevision: restored.contentRevision,
        readingPercent: 0,
      ),
    );
    expect(await library.finishedBookIds(), {restored.id});
    final annotations = await library.annotationStore(restored.id)!.list();
    expect(annotations, hasLength(2));
    expect(
      annotations.map((item) => item.quote),
      containsAll(<String>['保留的高亮', '保留的笔记']),
    );
    expect(
      annotations
          .singleWhere((item) => item.type == ReaderAnnotationType.thought)
          .note,
      '重新导入后仍应存在',
    );
    expect(
      (await library.bookmarkStore(restored.id)!.list()).single.label,
      '保留的书签',
    );
    final review = (await library.reviewStore()!.snapshot())[restored.id]!;
    expect(review.rating, 5);
    expect(review.content, '保留的书评');
    final sessions = await library.readingSessionStore()!.list();
    expect(sessions.single.bookId, restored.id);
    expect(sessions.single.duration, const Duration(minutes: 12));
  });
}
