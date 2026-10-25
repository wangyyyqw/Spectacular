import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
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

  test('新增高亮：落库含 CFI 区间、原文、前后文与颜色（P4-17）', () async {
    final store = library.annotationStore(book.id)!;
    final created = await store.add(
      type: ReaderAnnotationType.highlight,
      startCfi: 'epubcfi(/6/4!/4/2/1:3)',
      endCfi: 'epubcfi(/6/4!/4/2/1:9)',
      quote: '找学习资源',
      contextBefore: '毕竟帮他',
      contextAfter: '自己怎么着',
      color: 0xFFFFEB3B,
    );
    expect(created, isNotNull);

    final list = await store.list();
    expect(list, hasLength(1));
    final item = list.single;
    expect(item.type, ReaderAnnotationType.highlight);
    expect(item.startCfi, 'epubcfi(/6/4!/4/2/1:3)');
    expect(item.endCfi, 'epubcfi(/6/4!/4/2/1:9)');
    expect(item.quote, '找学习资源');
    expect(item.contextBefore, '毕竟帮他');
    expect(item.color, 0xFFFFEB3B);
  });

  test('同一区间不重复：同类型同起止 CFI 返回 null', () async {
    final store = library.annotationStore(book.id)!;
    Future<ReaderAnnotation?> add() => store.add(
      type: ReaderAnnotationType.highlight,
      startCfi: 'epubcfi(/6/4!/4/2/1:3)',
      endCfi: 'epubcfi(/6/4!/4/2/1:9)',
      quote: '找学习资源',
    );
    expect(await add(), isNotNull);
    expect(await add(), isNull, reason: '同区间不重复写入');
    expect(await store.list(), hasLength(1));

    // 不同类型/不同区间各自独立。
    expect(
      await store.add(
        type: ReaderAnnotationType.note,
        startCfi: 'epubcfi(/6/4!/4/2/1:3)',
        endCfi: 'epubcfi(/6/4!/4/2/1:9)',
        quote: '找学习资源',
        note: '想法',
      ),
      isNotNull,
    );
    expect(
      await store.add(
        type: ReaderAnnotationType.highlight,
        startCfi: 'epubcfi(/6/4!/4/2/1:10)',
        endCfi: 'epubcfi(/6/4!/4/2/1:12)',
        quote: '另一段',
      ),
      isNotNull,
    );
    expect(await store.list(), hasLength(3));
  });

  test('更新颜色与备注，更新时间刷新', () async {
    final store = library.annotationStore(book.id)!;
    final created = (await store.add(
      type: ReaderAnnotationType.highlight,
      startCfi: 'epubcfi(/6/4!/4/2/1:1)',
      endCfi: 'epubcfi(/6/4!/4/2/1:2)',
      quote: '文字',
      color: 0xFFFFEB3B,
    ))!;
    await store.update(created.id, color: 0xFF4CAF50, note: '改了');
    final item = (await store.list()).single;
    expect(item.color, 0xFF4CAF50);
    expect(item.note, '改了');
    expect(
      item.updatedAt.isAfter(created.updatedAt) ||
          item.updatedAt.isAtSameMomentAs(created.updatedAt),
      isTrue,
    );
  });

  test('删除后列表为空', () async {
    final store = library.annotationStore(book.id)!;
    final created = (await store.add(
      type: ReaderAnnotationType.highlight,
      startCfi: 'epubcfi(/6/4!/4/2/1:1)',
      endCfi: 'epubcfi(/6/4!/4/2/1:2)',
      quote: '文字',
    ))!;
    await store.remove(created.id);
    expect(await store.list(), isEmpty);
  });

  test('重启后标注仍在（落库验证）', () async {
    final file = File('${dir.path}/restart.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    final firstLibrary = LibraryStore(
      database: first,
      directoryProvider: () async => dir,
    );
    final entry = await firstLibrary.importBytes(
      buildTestEpub(title: '重启书'),
    );
    await firstLibrary.annotationStore(entry.id)!.add(
      type: ReaderAnnotationType.highlight,
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
}
