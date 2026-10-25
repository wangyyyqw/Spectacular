import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';

import '../support/test_epub.dart';

/// 内存数据库 + 临时目录的书库。
({LibraryStore store, AppDatabase db}) _open(Directory dir) {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return (
    store: LibraryStore(
      database: db,
      directoryProvider: () async => dir,
    ),
    db: db,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('导入成功：元数据来自 OPF，文件落盘并可回读', () async {
    final dir = Directory.systemTemp.createTempSync('library_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final entry = await store.importBytes(buildTestEpub());
    expect(entry.title, '测试书');
    expect(entry.author, '测试作者');
    expect(entry.spineCount, 1);
    expect(File(entry.filePath).existsSync(), isTrue);
    expect(await store.list(), hasLength(1));
    final bytes = await store.readBytes(entry);
    expect(bytes.length, greaterThan(0));
  });

  test('条目跨实例持久化；删除后目录与条目都消失', () async {
    final dir = Directory.systemTemp.createTempSync('library_persist');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    final entry = await opened.store.importBytes(buildTestEpub(title: '持久书'));
    await opened.store.touchLastRead(entry.id);

    // 同一数据库、新 Store 实例 ≈ 重启后重新打开书库。
    final second = LibraryStore(
      database: opened.db,
      directoryProvider: () async => dir,
    );
    final books = await second.list();
    expect(books.single.title, '持久书');
    expect(books.single.lastReadAt, isNotNull);
    expect(books.single.status, BookReadingStatus.reading);
    expect(File(books.single.filePath).existsSync(), isTrue);

    final bookDir = Directory(entry.filePath).parent;
    await second.remove(books.single.id);
    expect(await second.list(), isEmpty);
    expect(bookDir.existsSync(), isFalse, reason: '删书清理整个书目录');
  });

  test('同一本书（OPF identifier）重复导入被拒', () async {
    final dir = Directory.systemTemp.createTempSync('library_dup');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    await store.importBytes(buildTestEpub(title: '唯一书'));
    await expectLater(
      store.importBytes(buildTestEpub(title: '唯一书')),
      throwsA(
        isA<LibraryImportException>().having(
          (error) => error.errorCode,
          'errorCode',
          'E_DUPLICATE',
        ),
      ),
    );
    expect(await store.list(), hasLength(1));
  });

  test('坏 EPUB 导入抛可读错误，不入库', () async {
    final dir = Directory.systemTemp.createTempSync('library_bad');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    await expectLater(
      store.importBytes(Uint8List.fromList(List<int>.generate(64, (i) => i))),
      throwsA(isA<LibraryImportException>()),
    );
    expect(await store.list(), isEmpty);
  });

  test('封面提取并缓存到书目录；无封面时为 null 交给占位', () async {
    final dir = Directory.systemTemp.createTempSync('library_cover');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final withCover = await store.importBytes(
      buildTestEpub(title: '有封面', cover: true),
    );
    expect(withCover.coverPath, isNotNull);
    expect(File(withCover.coverPath!).existsSync(), isTrue);

    final withoutCover = await store.importBytes(buildTestEpub(title: '无封面'));
    expect(withoutCover.coverPath, isNull);
  });

  test('排序：最近阅读优先，未读按导入时间倒序', () async {
    final dir = Directory.systemTemp.createTempSync('library_sort');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final first = await store.importBytes(buildTestEpub(title: '先导入'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = await store.importBytes(buildTestEpub(title: '后导入'));
    var books = await store.list();
    expect(books.first.title, '后导入', reason: '未读按导入时间倒序');

    await store.touchLastRead(first.id);
    books = await store.list();
    expect(books.first.title, '先导入', reason: '最近阅读优先');
    expect(books.first.status, BookReadingStatus.reading);
    expect(second.id, isNot(books.first.id));
  });

  test('旧版 books.json 一次性迁入 drift 且幂等', () async {
    final dir = Directory.systemTemp.createTempSync('library_migrate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final epubFile = File('${dir.path}/legacy.epub')
      ..writeAsBytesSync(buildTestEpub(title: '旧书'));
    File('${dir.path}/books.json').writeAsStringSync(
      '{"books":[{"id":"legacy-1","title":"旧书","author":"旧作者",'
      '"filePath":"${epubFile.path}","addedAt":1700000000000,'
      '"spineCount":1,"readabilityLevel":1}]}',
    );
    final store = _open(dir).store;
    expect(await store.migrateLegacyJson(), 1);
    final books = await store.list();
    expect(books.single.title, '旧书');
    expect(books.single.readabilityLevel, 1);
    expect(await store.migrateLegacyJson(), 0, reason: '幂等：库非空不再迁');
  });
}
