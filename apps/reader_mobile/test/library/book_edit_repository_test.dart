import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reader_core/editing.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_mobile/editing/book_edit_repository.dart';
import 'package:reader_mobile/library/import_analysis.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_index.dart';
import 'package:reader_mobile/library/revision_anchor_store.dart'
    show requireAnchorRecord;
import 'package:reader_mobile/storage/db.dart';

import 'fixtures/revision_epub.dart';

const _textChange = EpubEditSummary(
  changedPaths: {'OEBPS/first.xhtml'},
  cssOnly: false,
);
const _cssChange = EpubEditSummary(
  changedPaths: {'OEBPS/style.css'},
  cssOnly: true,
);

class _Fixture {
  _Fixture(this.root, this.db, this.library, this.entry);
  final Directory root;
  final AppDatabase db;
  final LibraryStore library;
  final BookEntry entry;
  BookEditRepository get repository => BookEditRepository(library);
  Future<BookRow> get book => db.select(db.books).getSingle();
  Future<File> file(Uint8List bytes) async =>
      File('${root.path}/input-${DateTime.now().microsecondsSinceEpoch}.epub')
          .writeAsBytes(bytes);
}

Future<_Fixture> _fixture({bool css = false, Uint8List? epub}) async {
  final root = await Directory.systemTemp.createTemp('book-edit-test-');
  final db = AppDatabase(NativeDatabase.memory());
  final library = LibraryStore(
    database: db,
    directoryProvider: () async => root,
  );
  addTearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  final bytes =
      epub ?? (css ? _styled('p { color: black; }') : buildRevisionTestEpub());
  final entry = await library.importBytes(bytes);
  final fixture = _Fixture(root, db, library, entry);
  await _seedPosition(fixture);
  return fixture;
}

Future<void> _seedPosition(_Fixture fixture) async {
  final book = await fixture.book;
  final index = await buildRevisionAnchorBookFile(
    File(book.sourcePath!),
    revision: book.contentRevision,
    spineIndex: 0,
  );
  final chapter = index.chapter(0)!;
  final cfi = chapter.cfiAt(chapter.text.indexOf(revisionQuote))!;
  final anchor = index.capture(cfi)!;
  final record = AnchorRecord(original: anchor).encode();
  await fixture.db
      .into(fixture.db.annotations)
      .insert(
        AnnotationsCompanion.insert(
          id: 'retained-note',
          bookId: book.id,
          type: 1,
          startCfi: cfi,
          endCfi: cfi,
          quote: revisionQuote,
          note: const Value('不能丢失的笔记'),
          anchorJson: Value(record),
          createdAt: 1,
          updatedAt: 2,
        ),
      );
  await fixture.db
      .into(fixture.db.readingProgress)
      .insert(
        ReadingProgressCompanion.insert(
          bookId: Value(book.id),
          locatorCfi: cfi,
          anchorJson: Value(record),
          spineIndex: const Value(0),
          pageIndex: const Value(7),
          percent: const Value(21),
          finished: const Value(true),
          updatedAt: 3,
        ),
      );
}

Uint8List _styled(String css) {
  final source = ZipDecoder().decodeBytes(buildRevisionTestEpub());
  final result = Archive();
  for (final entry in source.files) {
    var bytes = entry.content;
    if (entry.name.endsWith('.opf')) {
      bytes = utf8.encode(
        utf8
            .decode(bytes)
            .replaceFirst(
              '</manifest>',
              '<item id="style" href="style.css" media-type="text/css"/></manifest>',
            ),
      );
    } else if (entry.name.endsWith('.xhtml')) {
      bytes = utf8.encode(
        utf8
            .decode(bytes)
            .replaceAll('<p>', '<p class="shared">')
            .replaceFirst(
              '</head>',
              '<link rel="stylesheet" href="style.css"/></head>',
            ),
      );
    }
    result.addFile(ArchiveFile.bytes(entry.name, bytes));
  }
  result.addFile(ArchiveFile.string('OEBPS/style.css', css));
  return Uint8List.fromList(ZipEncoder().encodeBytes(result));
}

Future<void> _expectUnchanged(_Fixture f, BookRow before) async {
  expect((await f.book).toJson(), before.toJson());
  expect(await File(before.sourcePath!).exists(), isTrue);
  expect(await f.repository.versions(before.uuid), isEmpty);
  final stages = Directory('${f.root.path}/books/${before.uuid}/versions');
  if (await stages.exists()) {
    final abandoned = await stages
        .list()
        .where(
          (entry) =>
              !p.equals(entry.path, File(before.sourcePath!).parent.path),
        )
        .toList();
    expect(abandoned, isEmpty);
  }
}

Future<BookEntry> _rekey(_Fixture f) => f.library.updateBytes(
  f.entry.id,
  buildRevisionTestEpub(
    identifier: 'urn:uuid:editing-new-identity',
    chapters: revisionUpdatedChapters,
  ),
);

Future<void> _removeReimportedOriginal(_Fixture f, BookEntry current) async {
  final reimported = await f.library.importBytes(
    _styled('p { color: black; }'),
  );
  expect(reimported.id, f.entry.id);
  expect(current.id, isNot(reimported.id));
  expect(await f.library.list(), hasLength(2));

  await f.library.remove(reimported.id);

  expect((await f.library.list()).single.id, current.id);
  expect(await File(current.filePath).exists(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OCR 选区编辑经书库保存，保留邻文、原版本和已有笔记', () async {
    final fixture = await _fixture();
    final before = await fixture.book;
    final original = await File(before.sourcePath!).readAsBytes();
    final index = await buildRevisionAnchorBookFile(
      File(before.sourcePath!),
      revision: before.contentRevision,
    );
    final chapter = index.chapter(0)!;
    final offset = chapter.text.indexOf(revisionQuote);
    final raw = chapter.text.substring(offset, offset + 3);
    final edit = await fixture.repository.openParagraph(
      before.uuid,
      before.contentRevision,
      File(before.sourcePath!),
      0,
      chapter.cfiAt(offset)!,
      chapter.cfiAt(offset + 3)!,
      recognizedText: '识别文字',
      sourceText: raw,
    );
    addTearDown(edit.session.close);
    expect(edit.initialText, '识别文字');
    await fixture.repository.saveParagraph(before.uuid, edit, '校对后的文字');
    final after = await fixture.book;
    final updated = await buildRevisionAnchorBookFile(
      File(after.sourcePath!),
      revision: after.contentRevision,
    );
    expect(
      updated.chapter(0)!.text,
      chapter.text.replaceRange(offset, offset + 3, '校对后的文字'),
    );
    expect(await File(before.sourcePath!).readAsBytes(), original);
    expect(
      (await fixture.db.select(fixture.db.annotations).getSingle()).note,
      '不能丢失的笔记',
    );
    final reopened = await EpubEditSession.open(File(after.sourcePath!));
    addTearDown(reopened.close);
    expect(
      reopened.readText(reopened.spinePaths.first),
      contains('font-family: serif !important'),
    );
  });

  test('千章书段落保存只迁移修改章，未改章的进度和笔记保留原文位置', () async {
    const target = 901;
    final chapters = [
      ...revisionOriginalChapters,
      for (var index = revisionOriginalChapters.length; index < 1047; index++)
        RevisionTestChapter('chapter-$index.xhtml', '第 $index 章', [
          '这一段记录第 $index 章的内容。',
        ]),
    ];
    final fixture = await _fixture(
      epub: buildRevisionTestEpub(chapters: chapters),
    );
    final old = await fixture.book;
    final note = await fixture.db.select(fixture.db.annotations).getSingle();
    final beforeProgress = await fixture.db
        .select(fixture.db.readingProgress)
        .getSingle();
    final index = await buildRevisionAnchorBookFile(
      File(old.sourcePath!),
      revision: old.contentRevision,
      spineIndex: target,
    );
    expect(index.chapters.map((chapter) => chapter.spineIndex), [target]);
    final chapter = index.chapter(target)!;
    final cfi = chapter.cfiAt(chapter.text.indexOf('这一段'))!;
    final edit = await fixture.repository.openParagraph(
      old.uuid,
      old.contentRevision,
      File(old.sourcePath!),
      target,
      cfi,
      cfi,
    );
    addTearDown(edit.session.close);
    final watch = Stopwatch()..start();
    final stages = <String>[];
    await fixture.repository.saveParagraph(
      old.uuid,
      edit,
      '${edit.initialText}补字',
      onStage: stages.add,
    );
    watch.stop();
    debugPrint('千章合成书段落保存：${watch.elapsedMilliseconds} 毫秒');
    expect(stages, ['正在写入 EPUB…', '正在更新书库和阅读位置…']);
    final saved = await fixture.book;
    expect(saved.charCount, old.charCount + 2);
    final newIndex = await buildRevisionAnchorBookFile(
      File(saved.sourcePath!),
      revision: saved.contentRevision,
      spineIndex: target,
    );
    expect(newIndex.chapter(target)!.text, contains('${edit.initialText}补字'));
    final retained = await fixture.db
        .select(fixture.db.annotations)
        .getSingle();
    final record = requireAnchorRecord(retained.anchorJson);
    expect(
      record.original.toJson(),
      requireAnchorRecord(note.anchorJson).original.toJson(),
    );
    expect(record.status, 'verified');
    expect(record.effective.revision, saved.contentRevision);
    expect(retained.startCfi, note.startCfi);
    final progress = await fixture.db
        .select(fixture.db.readingProgress)
        .getSingle();
    expect(progress.locatorCfi, beforeProgress.locatorCfi);
    expect(
      requireAnchorRecord(progress.anchorJson).effective.revision,
      saved.contentRevision,
    );
  });

  test('修改章删除标注原文时，不把它迁到另一章的同一句话', () async {
    final fixture = await _fixture(
      epub: buildRevisionTestEpub(
        chapters: [
          ...revisionOriginalChapters,
          const RevisionTestChapter('duplicate.xhtml', '其他章节', [
            revisionBefore,
            revisionQuote,
            revisionAfter,
          ]),
        ],
      ),
    );
    final old = await fixture.book;
    final note = await fixture.db.select(fixture.db.annotations).getSingle();
    final edit = await fixture.repository.openParagraph(
      old.uuid,
      old.contentRevision,
      File(old.sourcePath!),
      0,
      note.startCfi,
      note.endCfi,
    );
    addTearDown(edit.session.close);
    await fixture.repository.saveParagraph(old.uuid, edit, '改为完全不同的段落。');
    final retained = await fixture.db
        .select(fixture.db.annotations)
        .getSingle();
    expect(requireAnchorRecord(retained.anchorJson).status, 'pending');
    expect(retained.startCfi, note.startCfi);
    expect(retained.note, note.note);
  });

  test('段落保存遇到触及修改章的跨章标注，按完整范围验证原文', () async {
    final fixture = await _fixture();
    final old = await fixture.book;
    final file = File(old.sourcePath!);
    final index = await buildRevisionAnchorBookFile(
      file,
      revision: old.contentRevision,
    );
    final first = index.chapter(0)!;
    final second = index.chapter(1)!;
    final start = first.cfiAt(first.text.indexOf(revisionAfter))!;
    final end = second.cfiAt(
      second.text.indexOf(revisionBookmarkQuote) + 3,
      end: true,
    )!;
    final range = index.capture(start, endCfi: end)!;
    await fixture.db
        .update(fixture.db.annotations)
        .write(
          AnnotationsCompanion(
            startCfi: Value(start),
            endCfi: Value(end),
            quote: Value(range.quote),
            anchorJson: Value(AnchorRecord(original: range).encode()),
          ),
        );
    final cfi = first.cfiAt(first.text.indexOf(revisionBefore))!;
    final edit = await fixture.repository.openParagraph(
      old.uuid,
      old.contentRevision,
      file,
      0,
      cfi,
      cfi,
    );
    addTearDown(edit.session.close);
    await fixture.repository.saveParagraph(
      old.uuid,
      edit,
      '${edit.initialText}补字',
    );
    final saved = await fixture.book;
    final retained = await fixture.db
        .select(fixture.db.annotations)
        .getSingle();
    final anchor = requireAnchorRecord(retained.anchorJson);
    expect(anchor.isResolved, isTrue);
    expect(anchor.effective.revision, saved.contentRevision);
    final next = await buildRevisionAnchorBookFile(
      File(saved.sourcePath!),
      revision: saved.contentRevision,
    );
    expect(
      next.capture(retained.startCfi, endCfi: retained.endCfi)?.quote,
      range.quote,
    );
  });

  test('段落写回不覆盖已有草稿，解除冲突后可重试且保留书架元数据', () async {
    final fixture = await _fixture();
    final entry = fixture.entry;
    final repository = fixture.repository;
    final progress = await fixture.db
        .select(fixture.db.readingProgress)
        .getSingle();
    final edit = await repository.openParagraph(
      entry.id,
      entry.contentRevision!,
      File(entry.filePath),
      0,
      progress.locatorCfi,
      progress.locatorCfi,
    );
    addTearDown(edit.session.close);
    final input = '${edit.initialText}补字';
    await repository.saveDraft(
      entry.id,
      entry.contentRevision!,
      (_) => {'保留': '草稿'},
    );
    await expectLater(
      repository.saveParagraph(entry.id, edit, input),
      throwsA(isA<LibraryImportException>()),
    );
    expect((await repository.openDraft(entry.id))!.data['保留'], '草稿');
    expect(edit.session.changedPaths, isEmpty);
    expect((await fixture.book).contentRevision, entry.contentRevision);
    await repository.discardDraft(entry.id);
    await fixture.db
        .update(fixture.db.books)
        .write(const BooksCompanion(title: Value('书架别名')));
    await repository.saveParagraph(entry.id, edit, input);
    final saved = await fixture.book;
    expect(saved.title, '书架别名');
    expect(saved.contentRevision, isNot(entry.contentRevision));
  });

  test('正文和元数据保存保持书籍身份、迁移位置，原版与最近版可以恢复', () async {
    final f = await _fixture();
    final before = await f.book;
    final input = await f.file(
      buildRevisionTestEpub(
        chapters: revisionUpdatedChapters,
        title: '修改后的书名',
        identifier: 'edited-id',
      ),
    );
    final updated = await f.repository.commitEditedFile(
      before.uuid,
      before.contentRevision,
      input,
      _textChange,
    );
    expect(updated.id, before.uuid);
    expect(updated.title, '修改后的书名');
    expect((await f.book).id, before.id);
    final note = await f.db.select(f.db.annotations).getSingle();
    expect(note.note, '不能丢失的笔记');
    expect(
      AnchorRecord.decode(note.anchorJson)!.original.revision,
      before.contentRevision,
    );
    expect(
      AnchorRecord.decode(note.anchorJson)!.effective.revision,
      updated.contentRevision,
    );
    final progress = await f.db.select(f.db.readingProgress).getSingle();
    expect(progress.spineIndex, 1);
    expect(progress.finished, isFalse);
    final restored = await f.repository.restoreOriginal(
      updated.id,
      updated.contentRevision!,
    );
    expect(restored.contentRevision, before.contentRevision);
    expect(restored.id, before.uuid);
    await f.library.sweepOrphans();
    final versions = await f.repository.versions(before.uuid);
    expect(versions.map((v) => v.kind), containsAll(['original', 'previous']));
    for (final version in versions) {
      expect(await version.sourceFile.exists(), isTrue);
    }
    final recent = await f.repository.restorePrevious(
      restored.id,
      restored.contentRevision!,
    );
    expect(recent.contentRevision, updated.contentRevision);
    expect(await input.exists(), isTrue);
  });

  test('纯 CSS 跳过正文统计和迁移，CFI 与原始证据保留并清空旧页序', () async {
    final f = await _fixture(css: true);
    final before = await f.book;
    final original = await f.db.select(f.db.annotations).getSingle();
    final file = await f.file(_styled('p { color: red; font-size: 22px; }'));
    final analysis = await analyzeEditedFile(
      file.path,
      oldPath: before.sourcePath!,
      cssOnly: true,
      knownCounts: [17, 18, 19],
    );
    expect(analysis.cssOnly, isTrue);
    expect(analysis.analysis.charCounts, [17, 18, 19]);
    final saved = await f.repository.commitEditedFile(
      before.uuid,
      before.contentRevision,
      file,
      _cssChange,
    );
    final note = await f.db.select(f.db.annotations).getSingle();
    expect(note.startCfi, original.startCfi);
    expect(AnchorRecord.decode(note.anchorJson)!.status, 'verified');
    expect(
      AnchorRecord.decode(note.anchorJson)!.original.toJson(),
      AnchorRecord.decode(original.anchorJson)!.original.toJson(),
    );
    expect(
      AnchorRecord.decode(note.anchorJson)!.effective.revision,
      saved.contentRevision,
    );
    final progress = await f.db.select(f.db.readingProgress).getSingle();
    expect(progress.pageIndex, 0);
    expect(progress.finished, isTrue);
    expect(progress.percent, 21);
    expect((await f.book).layoutVersion, before.layoutVersion + 1);
  });

  test('不能用错误 CSS 标记绕过正文迁移，过期草稿在写文件前拒绝', () async {
    final f = await _fixture();
    final before = await f.book;
    final input = await f.file(
      buildRevisionTestEpub(chapters: revisionUpdatedChapters),
    );
    final updated = await f.repository.commitEditedFile(
      before.uuid,
      before.contentRevision,
      input,
      _cssChange,
    );
    expect((await f.db.select(f.db.readingProgress).getSingle()).spineIndex, 1);
    await expectLater(
      f.repository.commitEditedFile(
        before.uuid,
        before.contentRevision,
        input,
        _textChange,
      ),
      throwsA(
        isA<LibraryImportException>().having(
          (e) => e.errorCode,
          'code',
          'E_STALE_REVISION',
        ),
      ),
    );
    expect((await f.book).contentRevision, updated.contentRevision);
  });

  test('首次共享 class 样式的 link 与归属元数据不触发正文迁移', () async {
    final f = await _fixture(css: true);
    final session = await EpubEditSession.open(File(f.entry.filePath));
    addTearDown(session.close);
    final report = ClassStyleEditor(session).apply('shared', {'color': 'red'});
    expect(report.elementCount, greaterThan(0));
    expect(session.summary.cssOnly, isTrue);
    final output = File('${f.root.path}/class-style.epub');
    await EpubWriter.write(session, output);
    final analysis = await analyzeEditedFile(
      output.path,
      oldPath: f.entry.filePath,
      cssOnly: session.summary.cssOnly,
      knownCounts: [17, 18, 19],
    );
    expect(analysis.cssOnly, isTrue);
    expect(analysis.analysis.charCounts, [17, 18, 19]);
    await f.repository.commitEditedFile(
      f.entry.id,
      f.entry.contentRevision!,
      output,
      session.summary,
    );
    final note = await f.db.select(f.db.annotations).getSingle();
    expect(AnchorRecord.decode(note.anchorJson)!.status, 'verified');
    expect(
      (await f.db.select(f.db.readingProgress).getSingle()).finished,
      isTrue,
    );
  });

  test('非法文件和事务中途失败都回滚历史、文件指针与阅读数据', () async {
    final f = await _fixture();
    final before = await f.book;
    final broken = await f.file(Uint8List.fromList([1, 2, 3]));
    await expectLater(
      f.repository.commitEditedFile(
        before.uuid,
        before.contentRevision,
        broken,
        _textChange,
      ),
      throwsA(anything),
    );
    await _expectUnchanged(f, before);
    await f.db.customStatement(
      "CREATE TRIGGER fail_edit BEFORE UPDATE OF source_path ON books BEGIN SELECT RAISE(ABORT, '模拟写库失败'); END",
    );
    final valid = await f.file(
      buildRevisionTestEpub(chapters: revisionUpdatedChapters),
    );
    await expectLater(
      f.repository.commitEditedFile(
        before.uuid,
        before.contentRevision,
        valid,
        _textChange,
      ),
      throwsA(anything),
    );
    await _expectUnchanged(f, before);
    expect((await f.db.select(f.db.readingProgress).getSingle()).pageIndex, 7);
    await f.db.customStatement('DROP TRIGGER fail_edit');
    expect(
      (await f.repository.commitEditedFile(
        before.uuid,
        before.contentRevision,
        valid,
        _textChange,
      )).importOutcome,
      BookImportOutcome.updated,
    );
  });

  test('草稿资源目录可恢复正式编辑会话，失败快照不覆盖上次草稿', () async {
    final f = await _fixture(css: true);
    final source = File(f.entry.filePath);
    final session = await EpubEditSession.open(source);
    addTearDown(session.close);
    session.transaction(
      '修改样式',
      (tx) => tx.writeText('OEBPS/style.css', 'p { color: blue; }'),
    );
    await f.repository.saveDraft(
      f.entry.id,
      f.entry.contentRevision!,
      (blob) => session.toDraft(storeBlob: blob),
    );
    final draft = (await f.repository.openDraft(f.entry.id))!;
    expect(jsonEncode(draft.data), isNot(contains('base64')));
    expect(() => draft.readBlob('../source.epub'), throwsFormatException);
    await expectLater(
      f.repository.saveDraft(
        f.entry.id,
        f.entry.contentRevision!,
        (_) => throw StateError('模拟序列化失败'),
      ),
      throwsStateError,
    );
    await f.library.sweepOrphans();
    final recovered = (await BookEditRepository(f.library)
        .openDraft(f.entry.id))!;
    expect(recovered.directory.path, draft.directory.path);
    final reopened = await EpubEditSession.open(
      recovered.sourceFile,
      draft: recovered.data,
      readBlob: recovered.readBlob,
    );
    addTearDown(reopened.close);
    expect(reopened.readText('OEBPS/style.css'), 'p { color: blue; }');
    await f.repository.discardDraft(f.entry.id);
    expect(await f.repository.openDraft(f.entry.id), isNull);
    expect(await draft.directory.exists(), isFalse);
    expect(await source.exists(), isTrue);
  });

  test('外部换版后的旧草稿仍可独立导出，扫描不删除其基线文件', () async {
    final f = await _fixture(css: true);
    final session = await EpubEditSession.open(File(f.entry.filePath));
    addTearDown(session.close);
    session.transaction(
      '草稿样式',
      (tx) => tx.writeText('OEBPS/style.css', 'p { color: green; }'),
    );
    await f.repository.saveDraft(
      f.entry.id,
      f.entry.contentRevision!,
      (blob) => session.toDraft(storeBlob: blob),
    );
    final updated = await f.library.updateBytes(
      f.entry.id,
      buildRevisionTestEpub(chapters: revisionUpdatedChapters),
    );
    await f.library.sweepOrphans();
    await expectLater(
      f.repository.openDraft(updated.id),
      throwsA(
        isA<LibraryImportException>().having(
          (error) => error.errorCode,
          'code',
          'E_STALE_REVISION',
        ),
      ),
    );
    final draft = (await f.repository.readDraftForRecovery(updated.id))!;
    expect(draft.baseRevision, f.entry.contentRevision);
    expect(await draft.sourceFile.exists(), isTrue);
    final recovered = await EpubEditSession.open(
      draft.sourceFile,
      draft: draft.data,
      readBlob: draft.readBlob,
    );
    addTearDown(recovered.close);
    final export = File('${f.root.path}/recovered.epub');
    await EpubWriter.write(recovered, export);
    final reopened = await EpubEditSession.open(export);
    addTearDown(reopened.close);
    expect(reopened.readText('OEBPS/style.css'), 'p { color: green; }');
    await expectLater(
      f.repository.commitEditedFile(
        updated.id,
        draft.baseRevision,
        export,
        _cssChange,
      ),
      throwsA(
        isA<LibraryImportException>().having(
          (error) => error.errorCode,
          'code',
          'E_STALE_REVISION',
        ),
      ),
    );
    expect((await f.book).contentRevision, updated.contentRevision);
  });

  test('改版重键后删除再次导入的原书，保留另一记录在旧目录中的编辑历史', () async {
    final f = await _fixture(css: true);
    final edited = await f.repository.commitEditedFile(
      f.entry.id,
      f.entry.contentRevision!,
      await f.file(_styled('p { color: red; }')),
      _cssChange,
    );
    expect(edited.importOutcome, BookImportOutcome.updated);
    final current = await _rekey(f);
    final before = await f.repository.versions(current.id);
    expect(
      before.map((version) => version.kind),
      containsAll(['original', 'previous']),
    );
    expect(await f.db.select(f.db.editDrafts).get(), isEmpty);

    await _removeReimportedOriginal(f, current);

    final retained = await f.repository.versions(current.id);
    expect(
      retained.map((version) => version.sourceFile.path),
      before.map((version) => version.sourceFile.path),
    );
    for (final version in retained) {
      expect(await version.sourceFile.exists(), isTrue);
    }
    final restored = await f.repository.restoreOriginal(
      current.id,
      current.contentRevision!,
    );
    expect(restored.contentRevision, f.entry.contentRevision);
  });

  test('改版重键后删除再次导入的原书，保留另一记录在旧目录中的草稿和基线', () async {
    final f = await _fixture(css: true);
    final session = await EpubEditSession.open(File(f.entry.filePath));
    addTearDown(session.close);
    session.transaction(
      '保留的草稿样式',
      (tx) => tx.writeText('OEBPS/style.css', 'p { color: green; }'),
    );
    await f.repository.saveDraft(
      f.entry.id,
      f.entry.contentRevision!,
      (blob) => session.toDraft(storeBlob: blob),
    );
    final current = await _rekey(f);
    final before = (await f.repository.readDraftForRecovery(current.id))!;
    expect(await f.repository.versions(current.id), isEmpty);

    await _removeReimportedOriginal(f, current);

    final retained = (await f.repository.readDraftForRecovery(current.id))!;
    expect(retained.directory.path, before.directory.path);
    expect(retained.sourceFile.path, before.sourceFile.path);
    expect(await retained.sourceFile.exists(), isTrue);
    final recovered = await EpubEditSession.open(
      retained.sourceFile,
      draft: retained.data,
      readBlob: retained.readBlob,
    );
    addTearDown(recovered.close);
    expect(recovered.readText('OEBPS/style.css'), 'p { color: green; }');
  });
}
