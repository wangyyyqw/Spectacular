import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';

import '../support/test_epub.dart';

void main() {
  test('导入成功：元数据来自 OPF，文件落盘并可回读', () async {
    final dir = Directory.systemTemp.createTempSync('library_test');
    final store = LibraryStore(directoryProvider: () async => dir);
    final entry = await store.importBytes(buildTestEpub());
    expect(entry.title, '测试书');
    expect(entry.author, '测试作者');
    expect(entry.spineCount, 1);
    final file = File(entry.filePath);
    expect(file.existsSync(), isTrue);
    final books = await store.list();
    expect(books, hasLength(1));
    final bytes = await store.readBytes(entry);
    expect(bytes.length, greaterThan(0));
    dir.deleteSync(recursive: true);
  });

  test('条目跨实例持久化；删除后文件与条目都消失', () async {
    final dir = Directory.systemTemp.createTempSync('library_persist');
    final first = LibraryStore(directoryProvider: () async => dir);
    final entry = await first.importBytes(buildTestEpub(title: '持久书'));
    await first.touchLastRead(entry.id);

    final second = LibraryStore(directoryProvider: () async => dir);
    final books = await second.list();
    expect(books.single.title, '持久书');
    expect(books.single.lastReadAt, isNotNull);
    expect(File(books.single.filePath).existsSync(), isTrue);

    final path = books.single.filePath;
    await second.remove(books.single.id);
    expect(await second.list(), isEmpty);
    expect(File(path).existsSync(), isFalse);
    dir.deleteSync(recursive: true);
  });

  test('坏 EPUB 导入抛可读错误，不入库', () async {
    final dir = Directory.systemTemp.createTempSync('library_bad');
    final store = LibraryStore(directoryProvider: () async => dir);
    await expectLater(
      store.importBytes(Uint8List.fromList(List<int>.generate(64, (i) => i))),
      throwsA(isA<LibraryImportException>()),
    );
    expect(await store.list(), isEmpty);
    dir.deleteSync(recursive: true);
  });
}
