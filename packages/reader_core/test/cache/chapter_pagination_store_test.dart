import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/cache/chapter_pagination_store.dart';
import 'package:reader_core/layout/page_index.dart';

Uint8List _index(int pages, {int? version}) => PageIndex(
  schemaVersion: version ?? PageIndex.currentSchemaVersion,
  entries: [
    for (var page = 0; page < pages; page++)
      PageIndexEntry(
        blockIndex: page,
        startLine: 0,
        usedHeight: 300,
        pageHeight: 700,
        topPadding: 0,
      ),
  ],
).encode();

Future<FileChapterPaginationStore> _store({int maxBytes = 64 << 20}) async {
  final root = await Directory.systemTemp.createTemp('分页缓存回归-');
  addTearDown(() => root.delete(recursive: true));
  return FileChapterPaginationStore(
    directoryProvider: () async => root,
    maxBytes: maxBytes,
  );
}

Future<List<File>> _files(FileChapterPaginationStore store) async {
  final root = await store.directoryProvider();
  return root
      .list(recursive: true)
      .where((file) => file is File)
      .cast<File>()
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('新存储实例复用同键准确总数和索引，其他版面视为未命中', () async {
    final store = await _store();
    await store.write(
      ChapterPaginationData(
        key: '原文版本|字体|366x773',
        pageCount: 3,
        pageIndex: _index(3),
      ),
    );
    final reopened = FileChapterPaginationStore(
      directoryProvider: store.directoryProvider,
    );
    final data = await reopened.read('原文版本|字体|366x773');
    expect(data!.pageCount, 3);
    expect(PageIndex.decode(data.pageIndex!)!.entries, hasLength(3));
    expect(await reopened.read('原文版本|字体|360x700'), isNull);
  });

  test('准确总数可以先落盘，之后同键补齐页索引', () async {
    final store = await _store();
    await store.write(const ChapterPaginationData(key: '长章', pageCount: 4));
    expect((await store.read('长章'))!.pageIndex, isNull);
    await store.write(
      ChapterPaginationData(key: '长章', pageCount: 4, pageIndex: _index(4)),
    );
    expect((await store.read('长章'))!.pageIndex, isNotNull);
    expect(await _files(store), hasLength(1));
  });

  test('损坏、页数与索引不符或过期索引均回退未命中', () async {
    final store = await _store();
    await store.write(
      ChapterPaginationData(key: '损坏', pageCount: 2, pageIndex: _index(2)),
    );
    final file = (await _files(store)).single;
    final bytes = await file.readAsBytes();
    bytes[bytes.length - 2] ^= 1;
    await file.writeAsBytes(bytes);
    expect(await store.read('损坏'), isNull);
    await store.write(
      ChapterPaginationData(key: '错误总数', pageCount: 3, pageIndex: _index(2)),
    );
    expect(await store.read('错误总数'), isNull);
    await store.write(
      ChapterPaginationData(
        key: '过期',
        pageCount: 2,
        pageIndex: _index(2, version: PageIndex.currentSchemaVersion - 1),
      ),
    );
    expect(await store.read('过期'), isNull);
  });

  test('容量超限淘汰旧记录，保留新记录且不会留下临时文件', () async {
    final store = await _store(maxBytes: 600);
    final oldKey = '旧版面${'字' * 70}';
    final newKey = '新版面${'字' * 70}';
    await store.write(ChapterPaginationData(key: oldKey, pageCount: 20));
    await store.write(ChapterPaginationData(key: newKey, pageCount: 21));
    expect(await store.read(oldKey), isNull);
    expect((await store.read(newKey))!.pageCount, 21);
    final files = await _files(store);
    expect(files, hasLength(1));
    expect(await files.single.length(), lessThanOrEqualTo(600));
  });
}
