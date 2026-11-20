import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/txt.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_index.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/storage/import_queue.dart';
import 'package:reader_mobile/txt/txt_book_service.dart';
import 'package:reader_mobile/txt/txt_rule_store.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

final _txt = Uint8List.fromList(
  utf8.encode(
    '\n　\n第一章 初见\n　　相同的段落。\n另一段原文。\n\n'
    '第二章 再会\n　　相同的段落。\n需要保存的位置。\n',
  ),
);
const _oneChapter = ChapterDetectionOptions(
  mode: ChapterDetectionMode.custom,
  rule: ChapterRule(id: 'one', name: '只从第一章开始', pattern: r'第一章.*'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDatabase db;
  late LibraryStore library;
  late TxtBookService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('txt-library-test-');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => root);
    service = TxtBookService(library);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test('混合导入 TXT 与 EPUB，空行清理且同一 TXT 改名不重复入架', () async {
    final queue = ImportQueue(library);
    addTearDown(queue.dispose);
    final text = queue.enqueue(_txt, fallbackTitle: '样本.txt');
    queue.enqueue(buildTestEpub(title: '原生 EPUB'));
    await queue.drain();
    expect(
      queue.jobs.map((job) => job.status),
      everyElement(ImportStatus.succeeded),
    );
    expect(await library.list(), hasLength(2));
    final entry = text.entry!;
    expect(entry.title, '样本');
    expect(await service.canRechapter(entry), isTrue);
    final opened = await openEpubFile(File(entry.filePath));
    expect(opened.document, isNotNull);
    final metadata = opened.document!.archive.readString(txtMetadataPath)!;
    expect((jsonDecode(metadata) as Map<String, dynamic>)['schema'], 1);
    opened.document!.archive.close();
    final again = await library.importTxtBytes(_txt, fallbackTitle: '改名.txt');
    expect(again.id, entry.id);
    expect(again.importOutcome, BookImportOutcome.unchanged);
    expect(await library.list(), hasLength(2));
  });

  test('重新分章迁移重复原文中的进度、书签和批注，保留身份与设置', () async {
    final entry = await library.importTxtBytes(_txt, fallbackTitle: '迁移.txt');
    final oldIndex = await buildRevisionAnchorBookFile(
      File(entry.filePath),
      revision: entry.contentRevision!,
    );
    expect(oldIndex.chapters, hasLength(2));
    final chapter = oldIndex.chapter(1)!;
    final offset = chapter.text.indexOf('相同的段落');
    final start = chapter.cfiAt(offset)!;
    final end = chapter.cfiAt(offset + 6, end: true)!;
    final progressStore = DriftProgressStore(db);
    await progressStore.save(
      entry.id,
      ReaderProgress(
        spineIndex: 1,
        pageIndex: 2,
        cfi: start,
        contentRevision: entry.contentRevision,
      ),
    );
    await library
        .bookmarkStore(entry.id)!
        .add(cfi: start, spineIndex: 1, label: '第二次出现');
    await library
        .annotationStore(entry.id)!
        .add(
          type: ReaderAnnotationType.thought,
          startCfi: start,
          endCfi: end,
          quote: '相同的段落。',
          note: '保留的笔记',
          color: 0xff123456,
        );
    await library.setSetting('reader.setting.test', '保留');
    final beforeRows = await db.select(db.annotations).get();
    final preview = await service.preview(entry, _oneChapter);
    expect(preview.canApply, isTrue, reason: preview.diagnostics.join('；'));
    final saved = await service.apply(entry, preview);
    expect(saved.id, entry.id);
    expect(saved.spineCount, 1);
    expect(await library.getSetting('reader.setting.test'), '保留');
    final nextIndex = await buildRevisionAnchorBookFile(
      File(saved.filePath),
      revision: saved.contentRevision!,
    );
    final afterRows = await db.select(db.annotations).get();
    expect(
      afterRows.map((row) => row.id).toSet(),
      beforeRows.map((row) => row.id).toSet(),
    );
    for (final row in afterRows) {
      final anchor = AnchorRecord.decode(row.anchorJson)!;
      expect(anchor.isResolved, isTrue, reason: anchor.reason);
      expect(anchor.effective.start.spineIndex, 0);
      expect(
        nextIndex.pointForCfi(row.startCfi)!.charOffset,
        greaterThan(oldIndex.chapter(0)!.text.length),
      );
    }
    final progress = await progressStore.load(entry.id);
    expect(progress!.spineIndex, 0);
    expect(
      nextIndex.pointForCfi(progress.cfi!)!.charOffset,
      greaterThan(oldIndex.chapter(0)!.text.length),
    );
    expect(await library.editVersions(entry.id), hasLength(2));
  });

  test('正文编辑后按当前 EPUB 重分章，重复 TXT 导入不覆盖编辑', () async {
    final entry = await library.importTxtBytes(_txt, fallbackTitle: '编辑.txt');
    final session = await EpubEditSession.open(File(entry.filePath));
    final path = session.spinePaths.first;
    session.transaction(
      '改正文',
      (tx) => tx.writeText(
        path,
        session.readText(path).replaceAll('另一段原文。', '已经修改的正文。'),
      ),
    );
    final editedFile = File('${root.path}/edited.epub');
    await EpubWriter.write(session, editedFile);
    final edited = await library.commitEditedFile(
      entry.id,
      entry.contentRevision!,
      editedFile,
      session.summary,
    );
    session.close();
    final preview = await service.preview(edited, _oneChapter);
    final saved = await service.apply(edited, preview);
    final next = await buildRevisionAnchorBookFile(
      File(saved.filePath),
      revision: saved.contentRevision!,
    );
    expect(next.chapters.single.text, contains('已经修改的正文。'));
    final again = await library.importTxtBytes(_txt, fallbackTitle: '编辑.txt');
    expect(again.contentRevision, saved.contentRevision);
    expect(again.importOutcome, BookImportOutcome.unchanged);
  });

  test('取消或过期预览不替换当前 EPUB，已有编辑草稿阻止重新分章', () async {
    final entry = await library.importTxtBytes(_txt, fallbackTitle: '取消.txt');
    final preview = await service.preview(entry, _oneChapter);
    await expectLater(
      service.apply(entry, preview, isCancelled: () => true),
      throwsA(anything),
    );
    expect(
      (await library.bookById(entry.id))!.contentRevision,
      entry.contentRevision,
    );
    final saved = await service.apply(entry, preview);
    await expectLater(
      service.apply(entry, preview),
      throwsA(isA<LibraryImportException>()),
    );
    expect(
      (await library.bookById(entry.id))!.contentRevision,
      saved.contentRevision,
    );
    await library.persistEditDraft(
      saved.id,
      saved.contentRevision!,
      (_) => {'version': 1},
    );
    await expectLater(
      service.preview(saved, _oneChapter),
      throwsA(isA<LibraryImportException>()),
    );
    expect(await service.hasDraft(saved), isTrue);
  });

  test('个人规则可保存和删除，不修改本书规则快照', () async {
    final entry = await library.importTxtBytes(_txt, fallbackTitle: '规则.txt');
    final rules = TxtRuleStore(library);
    await rules.save(_oneChapter.rule!);
    expect((await rules.load()).single.name, '只从第一章开始');
    expect(
      (await service.info(entry))!.options.mode,
      ChapterDetectionMode.auto,
    );
    await rules.delete('one');
    expect(await rules.load(), isEmpty);
    await expectLater(
      rules.save(const ChapterRule(id: 'empty', name: '空行', pattern: r'.*')),
      throwsA(isA<TxtConversionException>()),
    );
    expect(await rules.load(), isEmpty);
  });

  test('编辑器重命名来源信息资源后，仍从当前清单识别并重新分章', () async {
    final entry = await library.importTxtBytes(_txt, fallbackTitle: '来源.txt');
    final session = await EpubEditSession.open(File(entry.filePath));
    late BookEntry edited;
    try {
      PackageEditor(session)
          .renameResource(txtMetadataPath, 'OEBPS/info/来源.json');
      final file = File('${root.path}/renamed.epub');
      await EpubWriter.write(session, file);
      edited = await library.commitEditedFile(
        entry.id,
        entry.contentRevision!,
        file,
        session.summary,
      );
    } finally {
      session.close();
    }
    expect(await service.canRechapter(edited), isTrue);
    final preview = await service.preview(edited, _oneChapter);
    final saved = await service.apply(edited, preview);
    expect(saved.spineCount, 1);
    expect(await service.canRechapter(saved), isTrue);
  });

  test('启用的个人规则用于下一次自动导入，已有书名资料不被重分章覆盖', () async {
    await TxtRuleStore(library).save(
      const ChapterRule(
        id: 'custom-volumes',
        name: '以自定义卷分组',
        pattern: r'第.章.*',
        volumePattern: r'分卷.*',
        autoEnabled: true,
      ),
    );
    final entry = await library.importTxtBytes(
      Uint8List.fromList(utf8.encode('分卷开始\n第一章 初见\n正文\n分卷后续\n第二章 再见\n正文\n')),
      fallbackTitle: '个人规则.txt',
    );
    final info = await service.info(entry);
    expect(info!.options.autoRules.single.id, 'custom-volumes');
    final named = await library.updateBookMetadata(
      entry.id,
      title: '用户改的书名',
      author: '用户作者',
      description: '用户简介',
    );
    final preview = await service.preview(named, _oneChapter);
    final saved = await service.apply(named, preview);
    expect(saved.title, '用户改的书名');
    expect(saved.author, '用户作者');
    expect(saved.description, '用户简介');
  });
}
