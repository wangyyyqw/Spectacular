import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_store.dart';

const _sourceJson = '''
{
  "bookSourceName": "示例源",
  "bookSourceUrl": "https://example.com",
  "bookSourceType": 0,
  "customField": "保留",
  "searchUrl": "/search?q={{key}}",
  "ruleSearch": {
    "bookList": "div.book",
    "name": "a.title@text",
    "author": "span.author@text",
    "bookUrl": "a.title@href"
  },
  "ruleBookInfo": {"name": "h1@text", "tocUrl": "a#toc@href"},
  "ruleToc": {
    "chapterList": "ul li",
    "chapterName": "a@text",
    "chapterUrl": "a@href"
  },
  "ruleContent": {"content": "#content"}
}
''';

void main() {
  late Directory directory;
  late BookSourceStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('book-source-test-');
    store = BookSourceStore(directoryProvider: () async => directory);
  });

  tearDown(() async {
    store.dispose();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('导入 JSON 后重新读取，未知字段保留', () async {
    final source = await store.importText(_sourceJson);
    expect(source.name, '示例源');
    expect(source.id, startsWith('online_'));
    expect(source.canSearch, isTrue);
    expect(source.toJson()['customField'], '保留');

    final reader = BookSourceStore(directoryProvider: () async => directory);
    final reloaded = await reader.load();
    reader.dispose();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.id, source.id);
    expect(reloaded.single.toJson()['customField'], '保留');
    expect(reloaded.single.toc.chapterList, 'ul li');
  });

  test('重复导入保留启停状态', () async {
    final source = await store.importText(_sourceJson);
    await store.setEnabled(source.id, false);

    await store.importText(_sourceJson);
    final reader = BookSourceStore(directoryProvider: () async => directory);
    final reloaded = await reader.load(refresh: true);
    reader.dispose();
    expect(reloaded.single.enabled, isFalse);
  });

  test('书籍关联随配置持久化，删除书源时清理', () async {
    final source = await store.importText(_sourceJson);
    await store.saveLink(
      'book-1',
      OnlineBookLink(
        sourceId: source.id,
        bookUrl: 'https://example.com/book/1',
        name: '书名',
        author: '作者',
      ),
    );

    final other = BookSourceStore(directoryProvider: () async => directory);
    final links = await other.loadLinks();
    expect(links['book-1']?.sourceId, source.id);
    expect(links['book-1']?.updatedAt, isNotNull);
    other.dispose();

    await store.remove(source.id);
    expect(await store.loadLinks(), isEmpty);
  });

  test('多书源数组与损坏内容给出明确错误', () async {
    expect(
      () => store.importText('["{}", "{}"]'),
      throwsA(isA<BookSourceException>()),
    );
    expect(
      () => store.importText('not json'),
      throwsA(isA<BookSourceException>()),
    );
  });

  test('编译型压缩书源提示无法直接执行', () async {
    final manifest = utf8.encode('{"name":"编译书源"}');
    final archive = Archive()
      ..addFile(ArchiveFile('classes.dex', 4, <int>[0, 1, 2, 3]))
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    expect(
      () => store.importBytes(bytes),
      throwsA(
        isA<BookSourceException>().having(
          (error) => error.message,
          'message',
          contains('无法直接执行'),
        ),
      ),
    );
  });
}
