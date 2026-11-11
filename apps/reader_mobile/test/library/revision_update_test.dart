import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show DataClass, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reader_core/epub/book_identity.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_index.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/storage/import_queue.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_mobile/reader/reader_decoration_image_store.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/reader_session.dart';

import 'fixtures/revision_epub.dart';

List<Map<String, dynamic>> _jsonRows(Iterable<DataClass> rows) =>
    rows.map((row) => row.toJson()).toList();

Future<Map<String, Object?>> _snapshot(AppDatabase db) async => {
  'books': _jsonRows(await db.select(db.books).get()),
  'annotations': _jsonRows(await db.select(db.annotations).get()),
  'decorations': _jsonRows(await db.select(db.decorations).get()),
  'decorationGroups': _jsonRows(await db.select(db.decorationRuleGroups).get()),
  'decorationRules': _jsonRows(await db.select(db.decorationRules).get()),
  'progress': _jsonRows(await db.select(db.readingProgress).get()),
  'reviews': _jsonRows(await db.select(db.bookReviews).get()),
  'sessions': _jsonRows(await db.select(db.readingSessions).get()),
  'groups': _jsonRows(await db.select(db.shelfGroupBooks).get()),
  'tags': _jsonRows(await db.select(db.bookTagLinks).get()),
  'aliases': _jsonRows(await db.select(db.bookIdAliases).get()),
  'spine': _jsonRows(await db.select(db.spineItems).get()),
  'chapters': _jsonRows(await db.select(db.chapters).get()),
};

LocationAnchor _quoteAnchor(AnchorBook book) {
  final chapter = book.chapter(0)!;
  final offset = chapter.text.indexOf(revisionQuote);
  expect(offset, greaterThanOrEqualTo(0));
  return book.capture(
    chapter.cfiAt(offset)!,
    endCfi: chapter.cfiAt(offset + revisionQuote.length, end: true)!,
  )!;
}

Future<void> _seedAnnotations(
  LibraryStore library,
  BookEntry entry,
  AnchorBook index,
) async {
  final anchor = _quoteAnchor(index);
  for (final type in [
    ReaderAnnotationType.mark,
    ReaderAnnotationType.thought,
  ]) {
    final chapter = index.chapter(0)!;
    final markEnd = chapter.cfiAt(
      chapter.text.indexOf(revisionQuote) + 4,
      end: true,
    )!;
    final annotation = await library
        .annotationStore(entry.id)!
        .add(
          type: type,
          startCfi: anchor.start.cfi,
          endCfi: type == ReaderAnnotationType.mark ? markEnd : anchor.end!.cfi,
          quote: type == ReaderAnnotationType.mark
              ? revisionQuote.substring(0, 4)
              : revisionQuote,
          contextBefore: revisionBefore,
          contextAfter: revisionAfter,
          color: 0xff123456,
          style: ReaderAnnotationStyle.wavyUnderline,
          note: type == ReaderAnnotationType.thought
              ? '旧版笔记正文、标点与换行\n全部保留。'
              : null,
        );
    expect(annotation, isNotNull);
  }
  final chapter = index.chapter(1)!;
  final cfi = chapter.cfiAt(chapter.text.indexOf(revisionBookmarkQuote))!;
  expect(
    await library
        .bookmarkStore(entry.id)!
        .add(cfi: cfi, spineIndex: 1, label: '旧第 2 章 · 第 1 页'),
    isNotNull,
  );
}

Future<void> _seedHistory(
  AppDatabase db,
  LibraryStore library,
  BookEntry entry,
) async {
  await library.touchLastRead(entry.id);
  await DriftBookReviewStore(db)
      .save(entry.id, rating: 4, content: '升级后仍保留这篇书评。');
  await DriftReadingSessionStore(db).add(
    bookId: entry.id,
    startedAt: DateTime(2026, 11, 1, 10),
    endedAt: DateTime(2026, 11, 1, 10, 7),
    pageTurns: 9,
    charactersRead: 1234,
  );
  final group = await library.createGroup('版本更新分组');
  await library.setBooksGroup([entry.id], groupId: group.id);
  final tag = await library.createTag('需要保留的标签');
  await library.addBookTag(entry.id, tag.id);
}

Future<void> _seedData(
  AppDatabase db,
  LibraryStore library,
  BookEntry entry,
  Uint8List bytes, {
  bool finished = false,
}) async {
  final index = await buildRevisionAnchorBook(bytes);
  await _seedAnnotations(library, entry, index);
  await DriftProgressStore(db).save(
    entry.id,
    ReaderProgress(
      spineIndex: 0,
      pageIndex: 2,
      cfi: _quoteAnchor(index).start.cfi,
      contentRevision: index.revision,
      finished: finished,
    ),
  );
  await _seedHistory(db, library, entry);
}

Map<String, dynamic> _userAnnotation(AnnotationRow row) => row.toJson()
  ..remove('startCfi')
  ..remove('endCfi')
  ..remove('anchorJson');

List<List<RevisionTestChapter>> _restructuredVersions() => [
  [
    const RevisionTestChapter('new-before.xhtml', '相遇上篇', [revisionBefore]),
    const RevisionTestChapter('new-after.xhtml', '相遇下篇', [
      revisionQuote,
      revisionAfter,
    ]),
    ...revisionOriginalChapters.skip(1),
  ],
  [
    revisionOriginalChapters.last,
    const RevisionTestChapter('combined.xhtml', '新的合并章', [
      revisionBefore,
      revisionQuote,
      revisionAfter,
      revisionBookmarkQuote,
      '这一章另有不重复的独有段落用于章节关联。',
    ]),
  ],
  const [
    RevisionTestChapter('deleted.xhtml', '正文删除版', [
      revisionBefore,
      revisionAfter,
      revisionBookmarkQuote,
      '这一章另有不重复的独有段落用于章节关联。',
    ]),
  ],
  revisionUpdatedChapters,
];

void _verifyRestructuredAnnotation(
  AnnotationRow row,
  AnnotationRow old,
  AnchorBook index, {
  required bool deleted,
}) {
  expect(_userAnnotation(row), _userAnnotation(old));
  final record = AnchorRecord.decode(row.anchorJson)!;
  expect(
    record.original.toJson(),
    AnchorRecord.decode(old.anchorJson)!.original.toJson(),
  );
  if (deleted && row.type != 2) {
    expect(record.status, 'pending');
    return;
  }
  expect(record.isResolved, isTrue);
  final actual = index.capture(
    row.startCfi,
    endCfi: row.type == 2 ? null : row.endCfi,
  )!;
  expect(
    actual.quote,
    row.type == 2 ? startsWith(revisionBookmarkQuote) : row.quote,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Directory directory;
  late AppDatabase db;
  late LibraryStore library;
  late Uint8List original;
  late Uint8List updated;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('revision-update-test-');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    original = buildRevisionTestEpub();
    updated = buildRevisionTestEpub(chapters: revisionUpdatedChapters);
  });
  tearDown(() async {
    await db.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('同 ID 自动覆盖实际 EPUB，前插中插后追加不使阅读数据按章号错位', () async {
    final entry = await library.importBytes(original);
    await _seedData(db, library, entry, original);
    final oldBook = (await db.select(db.books).get()).single;
    final oldAnnotations = await db.select(db.annotations).get();
    final oldSessions = _jsonRows(await db.select(db.readingSessions).get());
    final oldReviews = _jsonRows(await db.select(db.bookReviews).get());

    final result = await library.importBytes(updated);
    expect(result.importOutcome, BookImportOutcome.updated);
    expect(result.id, entry.id);
    expect(await library.list(), hasLength(1));
    final book = (await db.select(db.books).get()).single;
    expect(book.id, oldBook.id);
    expect(book.createdAt, oldBook.createdAt);
    expect(book.lastReadAt, oldBook.lastReadAt);
    expect(book.contentRevision, isNot(oldBook.contentRevision));
    expect(book.spineCount, 7);
    expect(File(entry.filePath).existsSync(), isFalse);
    expect(await File(result.filePath).readAsBytes(), orderedEquals(updated));

    final index = await buildRevisionAnchorBook(
      await library.readBytes(result),
    );
    final annotations = await db.select(db.annotations).get();
    expect(annotations, hasLength(3));
    for (final row in annotations) {
      final old = oldAnnotations.singleWhere((item) => item.id == row.id);
      expect(_userAnnotation(row), _userAnnotation(old));
      final record = AnchorRecord.decode(row.anchorJson)!;
      expect(record.isResolved, isTrue);
      expect(record.original.revision, oldBook.contentRevision);
      final actual = index.capture(
        row.startCfi,
        endCfi: row.type == 2 ? null : row.endCfi,
      )!;
      expect(actual.start.spineIndex, row.type == 2 ? 4 : 1);
      expect(
        actual.quote,
        row.type == 2 ? startsWith(revisionBookmarkQuote) : row.quote,
      );
    }
    final progress = (await DriftProgressStore(db).load(result.id))!;
    expect(progress.spineIndex, 1);
    expect(index.capture(progress.cfi!)!.quote, startsWith(revisionQuote));
    expect(progress.contentRevision, index.revision);
    expect(_jsonRows(await db.select(db.readingSessions).get()), oldSessions);
    expect(_jsonRows(await db.select(db.bookReviews).get()), oldReviews);
  });

  test('完全相同文件返回内容未变化，所有用户数据与文件路径保持', () async {
    final entry = await library.importBytes(original);
    await _seedData(db, library, entry, original);
    final before = await _snapshot(db);
    final result = await library.importBytes(original);
    expect(result.importOutcome, BookImportOutcome.unchanged);
    expect(result.filePath, entry.filePath);
    expect(await _snapshot(db), before);
    expect(File(entry.filePath).existsSync(), isTrue);
  });

  test('真实连续 EPUB 拆章改名、合并搬移和删除再恢复保留同一用户记录', () async {
    final entry = await library.importBytes(original);
    await _seedData(db, library, entry, original);
    final oldRows = await db.select(db.annotations).get();
    final versions = _restructuredVersions();
    for (var version = 0; version < versions.length; version++) {
      final bytes = buildRevisionTestEpub(chapters: versions[version]);
      final result = await library.importBytes(bytes);
      final index = await buildRevisionAnchorBook(bytes);
      final rows = await db.select(db.annotations).get();
      expect(result.importOutcome, BookImportOutcome.updated);
      expect(rows, hasLength(oldRows.length));
      for (final row in rows) {
        final old = oldRows.singleWhere((item) => item.id == row.id);
        _verifyRestructuredAnnotation(row, old, index, deleted: version == 2);
      }
    }
  });

  test('真实 EPUB 跨段标注拆成跨章后核对新版实际范围', () async {
    final entry = await library.importBytes(original);
    final oldIndex = await buildRevisionAnchorBook(original);
    final chapter = oldIndex.chapter(0)!;
    final start = chapter.text.indexOf(revisionBefore) + 20;
    final end = chapter.text.indexOf(revisionAfter) + 10;
    final anchor = oldIndex.capture(
      chapter.cfiAt(start)!,
      endCfi: chapter.cfiAt(end, end: true)!,
    )!;
    final saved = await library
        .annotationStore(entry.id)!
        .add(
          type: ReaderAnnotationType.mark,
          startCfi: anchor.start.cfi,
          endCfi: anchor.end!.cfi,
          quote: anchor.quote,
        );
    expect(saved, isNotNull);
    final bytes = buildRevisionTestEpub(
      chapters: _restructuredVersions().first,
    );
    await library.importBytes(bytes);
    final row = (await db.select(db.annotations).get()).single;
    final record = AnchorRecord.decode(row.anchorJson)!;
    expect(record.isResolved, isTrue);
    expect(record.current!.start.spineIndex, 0);
    expect(record.current!.end!.spineIndex, 1);
    final actual = (await buildRevisionAnchorBook(bytes))
        .capture(row.startCfi, endCfi: row.endCfi)!;
    expect(
      actual.quote,
      '${revisionBefore.substring(20)}相遇下篇'
      '$revisionQuote${revisionAfter.substring(0, 10)}',
    );
    expect(row.id, saved!.id);
    expect(row.quote, anchor.quote);
    expect(record.original.toJson(), anchor.toJson());
  });

  test('不同 ID 普通导入新增书，不认领原书的数据', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final other = await library.importBytes(
      buildRevisionTestEpub(
        identifier: 'urn:uuid:another-edition',
        chapters: revisionUpdatedChapters,
      ),
    );
    expect(other.importOutcome, BookImportOutcome.added);
    expect(other.id, isNot(old.id));
    expect(await library.list(), hasLength(2));
    expect(await library.annotationStore(old.id)!.list(), hasLength(2));
    expect(await library.annotationStore(other.id)!.list(), isEmpty);
    expect(File(old.filePath).existsSync(), isTrue);
  });

  test('强制改 ID 保持整数主键、分组、标签、书评和阅读历史，记录旧别名', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final row = (await db.select(db.books).get()).single;
    final groups = await library.groupAssignments();
    final tags = await library.bookTags(old.id);
    final sessions = _jsonRows(await db.select(db.readingSessions).get());
    final reviews = _jsonRows(await db.select(db.bookReviews).get());
    const newIdentifier = 'urn:uuid:forced-new-identity';
    final bytes = buildRevisionTestEpub(
      identifier: newIdentifier,
      chapters: revisionUpdatedChapters,
    );
    final result = await library.updateBytes(old.id, bytes);
    expect(result.importOutcome, BookImportOutcome.updated);
    expect(
      result.id,
      generateBookId(
        title: revisionTitle,
        author: revisionAuthor,
        identifier: newIdentifier,
      ),
    );
    expect((await db.select(db.books).get()).single.id, row.id);
    expect(await library.groupAssignments(), {result.id: groups[old.id]});
    expect(
      (await library.bookTags(result.id)).map((tag) => tag.id),
      tags.map((tag) => tag.id),
    );
    expect(
      (await db.select(db.shelfGroupBooks).get()).single.bookUuid,
      result.id,
    );
    expect((await db.select(db.bookTagLinks).get()).single.bookUuid, result.id);
    final alias = (await db.select(db.bookIdAliases).get()).single;
    expect(alias.aliasId, old.id);
    expect(alias.bookId, row.id);
    expect(
      await DriftProgressStore(db).load(old.id),
      await DriftProgressStore(db).load(result.id),
    );
    expect(_jsonRows(await db.select(db.readingSessions).get()), sessions);
    expect(_jsonRows(await db.select(db.bookReviews).get()), reviews);
    expect((await DriftBookReviewStore(db).snapshot()).keys, [result.id]);
    expect(
      (await DriftReadingSessionStore(db).list()).single.bookId,
      result.id,
    );
    expect(File(old.filePath).existsSync(), isFalse);
  });

  test('新 ID 已属于另一条书架记录则拒绝强制更新，两本原书均保留', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final otherBytes = buildRevisionTestEpub(
      identifier: 'urn:uuid:occupied-id',
    );
    final other = await library.importBytes(otherBytes);
    final before = await _snapshot(db);
    await expectLater(
      library.updateBytes(old.id, otherBytes),
      throwsA(
        isA<LibraryImportException>().having(
          (error) => error.errorCode,
          '错误码',
          'E_REVISION_CONFLICT',
        ),
      ),
    );
    expect(await _snapshot(db), before);
    expect(await File(old.filePath).readAsBytes(), orderedEquals(original));
    expect(await File(other.filePath).readAsBytes(), orderedEquals(otherBytes));
  });

  test('暂存完成和提交前取消只清暂存文件，不调用删书或改变数据', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final before = await _snapshot(db);
    for (final threshold in [0.5, 0.85]) {
      var cancelled = false;
      await expectLater(
        library.updateBytes(
          old.id,
          updated,
          onProgress: (value) {
            if (value >= threshold) cancelled = true;
          },
          isCancelled: () => cancelled,
        ),
        throwsA(
          isA<LibraryImportException>().having(
            (error) => error.errorCode,
            '错误码',
            'E_CANCELLED',
          ),
        ),
      );
      expect(await _snapshot(db), before);
      expect(await File(old.filePath).readAsBytes(), orderedEquals(original));
      expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('source.epub'))
            .map((file) => file.path),
        [old.filePath],
      );
    }
  });

  test('事务内部写入后取消仍整体回滚，保留旧文件和所有用户数据', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final before = await _snapshot(db);
    var checks = 0;
    await expectLater(
      library.updateBytes(old.id, updated, isCancelled: () => ++checks >= 5),
      throwsA(
        isA<LibraryImportException>().having(
          (error) => error.errorCode,
          '错误码',
          'E_CANCELLED',
        ),
      ),
    );
    expect(checks, 5);
    expect(await _snapshot(db), before);
    expect(await File(old.filePath).readAsBytes(), orderedEquals(original));
    expect(
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('source.epub'))
          .map((file) => file.path),
      [old.filePath],
    );
  });

  test('重复更新结果稳定，第二次不迁移或重复创建用户数据', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final first = await library.importBytes(updated);
    final before = await _snapshot(db);
    final second = await library.updateBytes(first.id, updated);
    expect(first.importOutcome, BookImportOutcome.updated);
    expect(second.importOutcome, BookImportOutcome.unchanged);
    expect(second.filePath, first.filePath);
    expect(await _snapshot(db), before);
    expect(await db.select(db.annotations).get(), hasLength(3));
    expect(await db.select(db.readingSessions).get(), hasLength(1));
  });

  test('已读完书新增可读章节后转在读并保留全部阅读历史', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original, finished: true);
    final history = _jsonRows(await db.select(db.readingSessions).get());
    expect((await DriftProgressStore(db).load(old.id))!.finished, isTrue);
    final result = await library.importBytes(updated);
    final progress = (await DriftProgressStore(db).load(result.id))!;
    expect(progress.finished, isFalse);
    expect(
      result.statusWith(finished: progress.finished),
      BookReadingStatus.reading,
    );
    expect(_jsonRows(await db.select(db.readingSessions).get()), history);
    expect(
      (await db.select(db.readingProgress).get()).single.percent,
      lessThan(100),
    );
  });

  test('只有已有文字修改不重置读完状态', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original, finished: true);
    final changed = buildRevisionTestEpub(
      chapters: [
        const RevisionTestChapter('first.xhtml', '相遇', [
          revisionBefore,
          '作者修改了原来的这一个段落。',
          revisionAfter,
        ]),
        ...revisionOriginalChapters.skip(1),
      ],
    );
    final result = await library.importBytes(changed);
    expect(result.importOutcome, BookImportOutcome.updated);
    expect((await DriftProgressStore(db).load(result.id))!.finished, isTrue);
    final notes = await library.annotationStore(result.id)!.list();
    expect(
      notes
          .singleWhere((item) => item.type == ReaderAnnotationType.thought)
          .quote,
      revisionQuote,
    );
    expect(
      notes
          .singleWhere((item) => item.type == ReaderAnnotationType.thought)
          .currentQuote,
      '作者修改了原来的这一个段落。',
    );
  });

  test('原文件缺失时仍用已保存的内容证据修订，未匹配记录保留原引用', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final before = await db.select(db.annotations).get();
    await File(old.filePath).delete();
    final replacement = buildRevisionTestEpub(
      chapters: [
        const RevisionTestChapter('new.xhtml', '全新章节', ['旧引用和书签指向的文字全部删除。']),
      ],
    );
    final result = await library.importBytes(replacement);
    expect(result.importOutcome, BookImportOutcome.updated);
    final annotations = await db.select(db.annotations).get();
    for (final row in annotations) {
      final oldRow = before.singleWhere((item) => item.id == row.id);
      expect(AnchorRecord.decode(row.anchorJson)!.status, 'pending');
      expect(row.startCfi, oldRow.startCfi);
      expect(row.endCfi, oldRow.endCfi);
      expect(_userAnnotation(row), _userAnnotation(oldRow));
      expect(
        AnchorRecord.decode(row.anchorJson)!.original.toJson(),
        AnchorRecord.decode(oldRow.anchorJson)!.original.toJson(),
      );
    }
    expect(
      AnchorRecord.decode(
        annotations.singleWhere((row) => row.type == 2).anchorJson,
      )!.original.quote,
      startsWith(revisionBookmarkQuote),
    );
    expect((await DriftProgressStore(db).load(result.id))!.approximate, isTrue);
    expect(File(result.filePath).existsSync(), isTrue);
  });

  test('历史别名用于旧数据查找，普通导入原 ID 仍新增独立书', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final forced = await library.updateBytes(
      old.id,
      buildRevisionTestEpub(
        identifier: 'urn:uuid:alias-target',
        chapters: revisionUpdatedChapters,
      ),
    );
    final forcedRow = (await db.select(db.books).get()).single;
    final restored = await library.importBytes(original);
    expect(restored.id, old.id);
    expect(restored.importOutcome, BookImportOutcome.added);
    expect(await library.list(), hasLength(2));
    expect(
      (await db.select(db.books).get())
          .singleWhere((row) => row.uuid == forced.id)
          .id,
      forcedRow.id,
    );
    expect(await library.annotationStore(restored.id)!.list(), isEmpty);
    expect(await library.annotationStore(forced.id)!.list(), hasLength(2));
  });

  test('同数据库的两个导入入口串行更新，连续版本继承原始锚点且不重复用户数据', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final originalRevision =
        (await db.select(db.books).get()).single.contentRevision;
    final third = buildRevisionTestEpub(
      chapters: [
        const RevisionTestChapter('third-preface.xhtml', '第三版增补序', [
          '第三版在所有正文前再插入一章。',
        ]),
        ...revisionUpdatedChapters,
      ],
    );
    final secondLibrary = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    final results = await Future.wait([
      library.importBytes(updated),
      secondLibrary.importBytes(third),
    ]);
    expect(
      results.map((entry) => entry.importOutcome),
      everyElement(BookImportOutcome.updated),
    );
    final current = (await library.list()).single;
    expect(await library.readBytes(current), orderedEquals(third));
    expect(File(results.first.filePath).existsSync(), isFalse);
    final index = await buildRevisionAnchorBook(third);
    final rows = await db.select(db.annotations).get();
    expect(rows, hasLength(3));
    for (final row in rows) {
      final record = AnchorRecord.decode(row.anchorJson)!;
      expect(record.original.revision, originalRevision);
      expect(record.current!.revision, index.revision);
      expect(
        index.capture(row.startCfi)!.start.spineIndex,
        row.type == 2 ? 5 : 2,
      );
    }
    expect(await db.select(db.readingSessions).get(), hasLength(1));
    expect(await db.select(db.readingProgress).get(), hasLength(1));
  });

  test('更新后旧阅读会话不得覆盖新版进度、改笔记或删除书签', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final oldIndex = await buildRevisionAnchorBook(original);
    final annotations = library.annotationStore(old.id)!;
    final bookmarks = library.bookmarkStore(old.id)!;
    final note = (await annotations.list()).singleWhere(
      (row) => row.type == ReaderAnnotationType.thought,
    );
    final bookmark = (await bookmarks.list()).single;
    await library.importBytes(updated);
    final before = await _snapshot(db);
    await DriftProgressStore(db).save(
      old.id,
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 99,
        cfi: _quoteAnchor(oldIndex).start.cfi,
        contentRevision: oldIndex.revision,
        finished: true,
      ),
    );
    await annotations.update(note.id, note: '旧会话错误回写的内容');
    await bookmarks.remove(bookmark.id);
    expect(
      await annotations.add(
        type: ReaderAnnotationType.thought,
        startCfi: _quoteAnchor(oldIndex).start.cfi,
        endCfi: _quoteAnchor(oldIndex).end!.cfi,
        quote: revisionQuote,
        note: '旧会话新增的笔记',
      ),
      isNull,
    );
    expect(await _snapshot(db), before);
  });

  test('损坏 EPUB 更新失败，数据库和当前有效原书均保留', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final before = await _snapshot(db);
    await expectLater(
      library.updateBytes(
        old.id,
        Uint8List.fromList(List.generate(64, (index) => index)),
      ),
      throwsA(isA<LibraryImportException>()),
    );
    expect(await _snapshot(db), before);
    expect(await File(old.filePath).readAsBytes(), orderedEquals(original));
  });

  test('装饰随版本迁移，样式与原引用不变，本书规则保持稳定外键', () async {
    final old = await library.importBytes(original);
    final anchor = _quoteAnchor(await buildRevisionAnchorBook(original));
    final images = ReaderDecorationImages(
      directoryProvider: () async => directory,
    );
    final oldStore = library.decorationStore(old.id, images: images)!;
    final decoration = (await oldStore.add(
      startCfi: anchor.start.cfi,
      endCfi: anchor.end!.cfi,
      quote: revisionQuote,
      style: ReaderDecorationPreset.tag.style,
    ))!;
    final rules = library.decorationRuleStore(old.id)!;
    final group = (await rules.listGroups()).singleWhere(
      (group) => group.bookId != null,
    );
    await rules.saveRule(
      ReaderDecorationRule(
        id: 'stable-rule',
        groupId: group.id,
        pattern: revisionQuote,
        style: const ReaderDecorationRuleStyle(color: 0xff123456),
      ),
    );
    final result = await library.updateBytes(
      old.id,
      buildRevisionTestEpub(
        identifier: 'urn:uuid:decoration-update',
        chapters: revisionUpdatedChapters,
      ),
    );
    final store = library.decorationStore(result.id, images: images)!;
    final restored = (await store.list()).single;
    expect(restored.id, decoration.id);
    expect(restored.quote, revisionQuote);
    expect(restored.createdAt, decoration.createdAt);
    expect(restored.style.toJson(), decoration.style.toJson());
    expect(restored.needsRelocation, isFalse);
    final index = await buildRevisionAnchorBook(
      await library.readBytes(result),
    );
    expect(
      index.capture(restored.startCfi, endCfi: restored.endCfi)!.quote,
      revisionQuote,
    );
    expect(
      AnchorRecord.decode(restored.anchorData)!.original.revision,
      AnchorRecord.decode(decoration.anchorData)!.original.revision,
    );
    final updatedGroups = await library
        .decorationRuleStore(result.id)!
        .listGroups();
    expect(
      updatedGroups.singleWhere((value) => value.id == group.id).bookId,
      result.id,
    );
    expect(
      (await library.decorationRuleStore(result.id)!.listRules()).single.id,
      'stable-rule',
    );
    final snapshot = await _snapshot(db);
    await oldStore.update(decoration.id, style: const ReaderDecorationStyle());
    await oldStore.remove(decoration.id);
    expect(await _snapshot(db), snapshot);
  });

  test('失效装饰保留原区间与样式，显示待修复并允许关联新位置', () async {
    final old = await library.importBytes(original);
    final anchor = _quoteAnchor(await buildRevisionAnchorBook(original));
    final images = ReaderDecorationImages(
      directoryProvider: () async => directory,
    );
    final created = (await library
        .decorationStore(old.id, images: images)!
        .add(
          startCfi: anchor.start.cfi,
          endCfi: anchor.end!.cfi,
          quote: revisionQuote,
          style: ReaderDecorationPreset.emphasis.style,
        ))!;
    final bytes = buildRevisionTestEpub(
      chapters: [
        const RevisionTestChapter('removed.xhtml', '删除版', ['这段完全不同的内容作为修复位置。']),
        ...revisionOriginalChapters.skip(1),
      ],
    );
    final current = await library.updateBytes(old.id, bytes);
    final store = library.decorationStore(current.id, images: images)!;
    final pending = (await store.list()).single;
    expect(pending.needsRelocation, isTrue);
    expect(pending.startCfi, created.startCfi);
    expect(pending.endCfi, created.endCfi);
    expect(pending.quote, created.quote);
    expect(
      await library.pendingLocationReasons(current.id),
      contains(startsWith('装饰：')),
    );
    final chapter = (await buildRevisionAnchorBook(bytes)).chapter(0)!;
    const text = '这段完全不同的内容作为修复位置。';
    final offset = chapter.text.indexOf(text);
    await store.relocate(
      created.id,
      startCfi: chapter.cfiAt(offset)!,
      endCfi: chapter.cfiAt(offset + text.length, end: true)!,
    );
    final repaired = (await store.list()).single;
    expect(repaired.needsRelocation, isFalse);
    expect(repaired.quote, created.quote);
    expect(repaired.currentQuote, text);
    expect(repaired.style.toJson(), created.style.toJson());
  });

  test('内容锚点损坏时拒绝修订，数据库和原文件整体保留', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    await db
        .update(db.annotations)
        .write(const AnnotationsCompanion(anchorJson: Value(null)));
    final before = await _snapshot(db);
    await expectLater(library.importBytes(updated), throwsFormatException);
    expect(await _snapshot(db), before);
    expect(await File(old.filePath).readAsBytes(), orderedEquals(original));
    expect(
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('source.epub'))
          .map((file) => file.path),
      [old.filePath],
    );
  });

  test('恢复扫描删除未提交和已退休版本，同时保护新原书和旧 ID 目录中的封面', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jh4kAAAAASUVORK5CYII=',
    );
    final withCover = await library.replaceCover(old.id, png, extension: 'png');
    final current = await library.updateBytes(
      old.id,
      buildRevisionTestEpub(
        identifier: 'urn:uuid:recovery-new-id',
        chapters: revisionUpdatedChapters,
      ),
    );
    expect(current.coverPath, withCover.coverPath);
    final oldDirectory = Directory(p.join(directory.path, 'books', old.id));
    final pending = Directory(
      p.join(directory.path, 'books', current.id, 'versions', 'not-committed'),
    );
    await pending.create(recursive: true);
    await File(p.join(pending.path, 'source.epub')).writeAsBytes(updated);
    final retiredRoot = File(p.join(oldDirectory.path, 'source.epub'));
    await retiredRoot.writeAsBytes(original);
    final retiredVersion = File(old.filePath);
    await retiredVersion.parent.create(recursive: true);
    await retiredVersion.writeAsBytes(original);
    final before = await _snapshot(db);

    final scanned = await library.sweepOrphans();
    expect(scanned.removed, greaterThanOrEqualTo(3));
    expect(
      scanned.bytes,
      greaterThanOrEqualTo(updated.length + original.length * 2),
    );
    expect(pending.existsSync(), isFalse);
    expect(retiredRoot.existsSync(), isFalse);
    expect(retiredVersion.existsSync(), isFalse);
    expect(File(current.filePath).existsSync(), isTrue);
    expect(await File(current.coverPath!).readAsBytes(), orderedEquals(png));
    expect(oldDirectory.existsSync(), isTrue, reason: '当前封面仍存放在旧 ID 目录');
    expect(await _snapshot(db), before);
  });

  test('同数据库恢复扫描等待更新队列，暂存文件在提交前不被误删', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final staged = Completer<void>();
    final release = Completer<void>();
    var hold = false;
    final updater = LibraryStore(
      database: db,
      directoryProvider: () async {
        if (hold) await release.future;
        return directory;
      },
    );
    var scanStarted = false;
    var scanCompleted = false;
    final cleaner = LibraryStore(
      database: db,
      directoryProvider: () async {
        scanStarted = true;
        return directory;
      },
    );
    final update = updater.updateBytes(
      old.id,
      updated,
      onProgress: (value) {
        if (value == 0.5) {
          hold = true;
          staged.complete();
        }
      },
    );
    await staged.future;
    final stagedSource = directory
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere(
          (file) =>
              file.path.endsWith('source.epub') && file.path != old.filePath,
        );
    final scan = cleaner.sweepOrphans().then((value) {
      scanCompleted = true;
      return value;
    });
    try {
      await Future<void>.delayed(Duration.zero);
      expect(scanStarted, isFalse);
      expect(scanCompleted, isFalse);
      expect(stagedSource.existsSync(), isTrue);
      expect(File(old.filePath).existsSync(), isTrue);
    } finally {
      release.complete();
    }
    final current = await update;
    await scan;
    expect(scanStarted, isTrue);
    expect(current.filePath, stagedSource.path);
    expect(await File(current.filePath).readAsBytes(), orderedEquals(updated));
    expect(File(old.filePath).existsSync(), isFalse);
    expect(await library.list(), hasLength(1));
  });

  test('存储根目录被文件占用时更新写入失败，原数据库与旧 EPUB 不变', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final before = await _snapshot(db);
    final blockedRoot = File(p.join(directory.path, 'blocked-storage-root'));
    await blockedRoot.writeAsString('阻止创建存储目录');
    final failing = LibraryStore(
      database: db,
      directoryProvider: () async => Directory(blockedRoot.path),
    );
    await expectLater(
      failing.updateBytes(old.id, updated),
      throwsA(isA<FileSystemException>()),
    );
    expect(await _snapshot(db), before);
    expect(await File(old.filePath).readAsBytes(), orderedEquals(original));
    expect(await blockedRoot.readAsString(), '阻止创建存储目录');
    expect(
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('source.epub'))
          .map((file) => file.path),
      [old.filePath],
    );
  });

  test('导入队列在底层提交完成进度回调中取消仍视为成功，不删除更新后的书', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final queue = ImportQueue(library);
    addTearDown(queue.dispose);
    var cancelledAtCommit = false;
    queue.addListener(() {
      final active = queue.activeJob;
      // 底层 onProgress(1) 在队列中映射为 0.95，此时事务已经提交。
      if (!cancelledAtCommit && active != null && active.progress >= 0.949) {
        cancelledAtCommit = true;
        queue.cancel(active.id);
      }
    });
    final job = queue.enqueue(updated, updateBookId: old.id);
    await queue.drain();
    expect(cancelledAtCommit, isTrue);
    expect(job.status, ImportStatus.succeeded);
    expect(job.entry!.importOutcome, BookImportOutcome.updated);
    expect(job.bytes, isNull);
    expect(job.progress, 1);
    expect(await library.list(), hasLength(1));
    expect(
      await File(job.entry!.filePath).readAsBytes(),
      orderedEquals(updated),
    );
    expect(File(old.filePath).existsSync(), isFalse);
    expect(await db.select(db.annotations).get(), hasLength(3));
    expect(await db.select(db.readingSessions).get(), hasLength(1));
  });

  test('导入队列释放时取消提交前的覆盖任务，保留旧书与全部数据', () async {
    final old = await library.importBytes(original);
    await _seedData(db, library, old, original);
    final before = await _snapshot(db);
    final queue = ImportQueue(library);
    var disposed = false;
    addTearDown(() {
      if (!disposed) queue.dispose();
    });
    queue.addListener(() {
      final active = queue.activeJob;
      // 底层 onProgress(0.5) 已写入暂存，尚未提交数据库切换。
      if (!disposed && active != null && active.progress >= 0.49) {
        disposed = true;
        queue.dispose();
      }
    });
    final job = queue.enqueue(updated, updateBookId: old.id);
    await queue.drain();
    expect(disposed, isTrue);
    expect(job.status, ImportStatus.cancelled);
    expect(job.entry, isNull);
    expect(job.canRetry, isTrue);
    expect(await _snapshot(db), before);
    expect(await File(old.filePath).readAsBytes(), orderedEquals(original));
    expect(
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('source.epub'))
          .map((file) => file.path),
      [old.filePath],
    );
  });
}
