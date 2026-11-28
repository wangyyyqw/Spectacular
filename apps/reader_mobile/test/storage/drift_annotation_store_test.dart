import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_index.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/annotations/relocator.dart';
import 'package:reader_ui/annotations/annotation.dart';

import '../support/test_epub.dart';

void main() {
  // 重启用例会在同一进程打开多个 AppDatabase（模拟重启），关掉该噪声告警。
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late Directory dir;
  late AppDatabase db;
  late LibraryStore library;
  late BookEntry book;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('annotations');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => dir);
    book = await library.importBytes(buildTestEpub(title: '标注书'));
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('新增划线：落库含 CFI 区间、原文、前后文、颜色与样式', () async {
    final store = library.annotationStore(book.id)!;
    final created = await store.add(
      type: ReaderAnnotationType.mark,
      startCfi: 'epubcfi(/6/4!/4/2/1:3)',
      endCfi: 'epubcfi(/6/4!/4/2/1:9)',
      quote: '找学习资源',
      contextBefore: '毕竟帮他',
      contextAfter: '自己怎么着',
      color: 0xFFFFEB3B,
      style: ReaderAnnotationStyle.wavyUnderline,
    );
    expect(created, isNotNull);

    final list = await store.list();
    expect(list, hasLength(1));
    final item = list.single;
    expect(item.type, ReaderAnnotationType.mark);
    expect(item.startCfi, 'epubcfi(/6/4!/4/2/1:3)');
    expect(item.endCfi, 'epubcfi(/6/4!/4/2/1:9)');
    expect(item.quote, '找学习资源');
    expect(item.contextBefore, '毕竟帮他');
    expect(item.color, 0xFFFFEB3B);
    expect(item.style, ReaderAnnotationStyle.wavyUnderline);
  });

  test('同一区间更新原记录，划线升级想法且再次划线不降级', () async {
    final store = library.annotationStore(book.id)!;
    Future<ReaderAnnotation?> add() => store.add(
      type: ReaderAnnotationType.mark,
      startCfi: 'epubcfi(/6/4!/4/2/1:3)',
      endCfi: 'epubcfi(/6/4!/4/2/1:9)',
      quote: '找学习资源',
    );
    final first = (await add())!;
    expect((await add())!.id, first.id);
    expect(await store.list(), hasLength(1));

    expect(
      await store.add(
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/4!/4/2/1:3)',
        endCfi: 'epubcfi(/6/4!/4/2/1:9)',
        quote: '找学习资源',
        note: '想法',
      ),
      isNotNull,
    );
    expect((await store.list()).single.type, ReaderAnnotationType.thought);
    final updated = await store.add(
      type: ReaderAnnotationType.mark,
      startCfi: first.startCfi,
      endCfi: first.endCfi,
      quote: first.quote,
      color: 0xff123456,
      style: ReaderAnnotationStyle.dottedUnderline,
      opacity: 0.6,
    );
    expect(updated!.id, first.id);
    expect(updated.type, ReaderAnnotationType.thought);
    expect(updated.note, '想法');
    expect(updated.color, 0xff123456);
    expect(updated.style, ReaderAnnotationStyle.dottedUnderline);
    expect(updated.opacity, 0.6);
    expect(
      await store.add(
        type: ReaderAnnotationType.mark,
        startCfi: 'epubcfi(/6/4!/4/2/1:10)',
        endCfi: 'epubcfi(/6/4!/4/2/1:12)',
        quote: '另一段',
      ),
      isNotNull,
    );
    expect(await store.list(), hasLength(2));
  });

  test('更新类型、颜色、样式与备注，更新时间刷新', () async {
    final store = library.annotationStore(book.id)!;
    final created = (await store.add(
      type: ReaderAnnotationType.mark,
      startCfi: 'epubcfi(/6/4!/4/2/1:1)',
      endCfi: 'epubcfi(/6/4!/4/2/1:2)',
      quote: '文字',
      color: 0xFFFFEB3B,
    ))!;
    await store.update(
      created.id,
      type: ReaderAnnotationType.thought,
      color: 0xFF4CAF50,
      style: ReaderAnnotationStyle.dashedUnderline,
      opacity: 0.42,
      note: '改了',
    );
    final item = (await store.list()).single;
    expect(item.type, ReaderAnnotationType.thought);
    expect(item.color, 0xFF4CAF50);
    expect(item.style, ReaderAnnotationStyle.dashedUnderline);
    expect(item.note, '改了');
    expect(item.opacity, 0.42);
    expect(
      item.updatedAt.isAfter(created.updatedAt) ||
          item.updatedAt.isAtSameMomentAs(created.updatedAt),
      isTrue,
    );

    await store.update(
      created.id,
      type: ReaderAnnotationType.mark,
      clearNote: true,
    );
    final highlight = (await store.list()).single;
    expect(highlight.type, ReaderAnnotationType.mark);
    expect(highlight.note, isNull);
  });

  test('删除后列表为空', () async {
    final store = library.annotationStore(book.id)!;
    final created = (await store.add(
      type: ReaderAnnotationType.mark,
      startCfi: 'epubcfi(/6/4!/4/2/1:1)',
      endCfi: 'epubcfi(/6/4!/4/2/1:2)',
      quote: '文字',
    ))!;
    await store.remove(created.id);
    expect(await store.list(), isEmpty);
  });

  test('想法仅非空校验，不限制字数，标注接口不修改书签', () async {
    final store = library.annotationStore(book.id)!;
    await expectLater(
      store.add(
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:1)',
        quote: '文',
        note: ' \n ',
      ),
      throwsFormatException,
    );
    final thought = (await store.add(
      type: ReaderAnnotationType.thought,
      startCfi: 'epubcfi(/6/2!/4/2/1:0)',
      endCfi: 'epubcfi(/6/2!/4/2/1:1)',
      quote: '文',
      note: List.filled(300, '想法').join(),
    ))!;
    expect(thought.note!.length, 600);
    await expectLater(
      store.update(thought.id, note: '   '),
      throwsFormatException,
    );
    final bookmark = (await library
        .bookmarkStore(book.id)!
        .add(cfi: 'epubcfi(/6/2!/4/2/1:2)', spineIndex: 0, label: '保留书签'))!;
    final before = (await db.select(db.annotations).get())
        .singleWhere((row) => row.type == 2)
        .toJson();
    await store.update(
      bookmark.id,
      type: ReaderAnnotationType.thought,
      color: 123,
      note: '越界',
    );
    await store.remove(bookmark.id);
    await expectLater(
      store.relocate(
        bookmark.id,
        startCfi: thought.startCfi,
        endCfi: thought.endCfi,
      ),
      throwsFormatException,
    );
    expect(
      (await db.select(db.annotations).get())
          .singleWhere((row) => row.type == 2)
          .toJson(),
      before,
    );
  });

  test('重启后标注仍在（落库验证）', () async {
    final file = File('${dir.path}/restart.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    final firstLibrary = LibraryStore(
      database: first,
      directoryProvider: () async => dir,
    );
    final entry = await firstLibrary.importBytes(buildTestEpub(title: '重启书'));
    await firstLibrary
        .annotationStore(entry.id)!
        .add(
          type: ReaderAnnotationType.mark,
          startCfi: 'epubcfi(/6/4!/4/2/1:5)',
          endCfi: 'epubcfi(/6/4!/4/2/1:8)',
          quote: '重启后仍可见',
        );
    await first.close();

    // 重新打开同一文件：等效于应用重启。
    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final secondLibrary = LibraryStore(
      database: second,
      directoryProvider: () async => dir,
    );
    final items = await secondLibrary.annotationStore(entry.id)!.list();
    expect(items, hasLength(1));
    expect(items.single.quote, '重启后仍可见');
  });

  test('OCR 引用落盘重开后保留原码点锚点，重排仍可定位，重复划线保留想法', () async {
    final bytes = buildTestEpub(paragraphs: ['甲乙丙丁戊己庚辛壬癸，邻文保留。']);
    final file = File('${dir.path}/ocr.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    final initialLibrary = LibraryStore(
      database: first,
      directoryProvider: () async => dir,
    );
    final entry = await initialLibrary.importBytes(bytes);
    final index = await buildRevisionAnchorBook(
      bytes,
      revision: entry.contentRevision,
    );
    final chapter = index.chapter(0)!;
    final offset = chapter.text.indexOf('丙丁戊');
    final start = chapter.cfiAt(offset)!;
    final end = chapter.cfiAt(offset + 3)!;
    final store = initialLibrary.annotationStore(entry.id)!;
    final created = (await store.add(
      type: ReaderAnnotationType.thought,
      startCfi: start,
      endCfi: end,
      quote: '可见文字',
      sourceQuote: '丙丁戊',
      note: '用户笔记',
    ))!;
    await expectLater(
      store.add(
        type: ReaderAnnotationType.mark,
        startCfi: start,
        endCfi: end,
        quote: '不能写入',
        sourceQuote: '错误证据',
      ),
      throwsFormatException,
    );
    await first.close();
    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final next = LibraryStore(
      database: reopened,
      directoryProvider: () async => dir,
    ).annotationStore(entry.id)!;
    final saved = (await next.list()).single;
    expect(saved.quote, '可见文字');
    expect(AnchorRecord.decode(saved.anchorData)!.effective.quote, '丙丁戊');
    expect(saved.note, '用户笔记');
    final source = await openTestChapterSource(bytes);
    addTearDown(source.close);
    await source.applyOverrides(const ReaderOverrides(fontSize: 28));
    final pages = await source.loadChapter(0);
    final relocated = AnnotationRelocator.relocate(
      annotations: [saved],
      pages: pages,
      contentRevision: entry.contentRevision,
    ).single;
    expect(relocated.isResolved, isTrue);
    expect(relocated.resolved.quote, '可见文字');
    final updated = await next.add(
      type: ReaderAnnotationType.mark,
      startCfi: start,
      endCfi: end,
      quote: '再次识别文字',
      sourceQuote: '丙丁戊',
    );
    expect(updated!.id, created.id);
    expect(updated.note, '用户笔记');
    expect(updated.type, ReaderAnnotationType.thought);
    expect(updated.quote, '再次识别文字');
    expect(await next.list(), hasLength(1));
  });
}
