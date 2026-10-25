import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';

import '../support/test_epub.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late LibraryStore library;
  late BookEntry book;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('bookmarks');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => dir);
    book = await library.importBytes(buildTestEpub(title: '书签书'));
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('添加书签后能列出，CFI 解析出章节号（P4-13）', () async {
    final store = library.bookmarkStore(book.id)!;
    final created = await store.add(
      cfi: 'epubcfi(/6/4!/4/2/1:0)',
      spineIndex: 1,
      label: '第 2 章 · 第 1 页',
    );
    expect(created, isNotNull);

    final list = await store.list();
    expect(list, hasLength(1));
    expect(list.single.label, '第 2 章 · 第 1 页');
    expect(list.single.cfi, 'epubcfi(/6/4!/4/2/1:0)');
    // itemref 步进 4 → spineIndex = 4 ~/ 2 - 1 = 1。
    expect(list.single.spineIndex, 1);
  });

  test('同一位置重复添加不产生第二条', () async {
    final store = library.bookmarkStore(book.id)!;
    await store.add(cfi: 'epubcfi(/6/6!/4/2/1:0)', spineIndex: 2, label: '第 3 章');
    final again = await store.add(
      cfi: 'epubcfi(/6/6!/4/2/1:0)',
      spineIndex: 2,
      label: '第 3 章（重复）',
    );
    expect(again, isNull, reason: '重复位置返回 null');
    expect(await store.list(), hasLength(1));
  });

  test('删除书签', () async {
    final store = library.bookmarkStore(book.id)!;
    final created = (await store.add(
      cfi: 'epubcfi(/6/4!/4/2/1:0)',
      spineIndex: 1,
      label: '书签',
    ))!;
    await store.remove(created.id);
    expect(await store.list(), isEmpty);
  });

  test('列表按章节顺序排序', () async {
    final store = library.bookmarkStore(book.id)!;
    await store.add(cfi: 'epubcfi(/6/10!/4/2/1:0)', spineIndex: 4, label: '第 5 章');
    await store.add(cfi: 'epubcfi(/6/4!/4/2/1:0)', spineIndex: 1, label: '第 2 章');
    final list = await store.list();
    expect(list.map((item) => item.spineIndex), <int>[1, 4]);
  });

  test('内存模式没有书签能力时返回 null', () {
    final memory = LibraryStore.memory();
    expect(memory.bookmarkStore('any'), isNull);
  });
}
